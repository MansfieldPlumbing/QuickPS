[CmdletBinding()]
param(
    [int] $Width = 960,
    [int] $Height = 540,
    [string] $Title = 'QuickPS Window',
    [uint32] $BackgroundColor = 0x0033CC,
    [int] $X = 150,
    [int] $Y = 150,
    [switch] $Borderless,
    [switch] $Topmost,
    [Nullable[uint32]] $TransparentColorKey,
    [switch] $Headless
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Window.Windows.ps1 must be invoked with &, not dot-sourced.'
}

if ($Headless) {
    return [PSCustomObject]@{
        PSTypeName = 'QuickPS.Window.Windows'
        Hwnd = [IntPtr]::Zero
        Title = $Title
        Width = $Width
        Height = $Height
        Headless = $true
        Alive = $true
    }
}

$Window = & {
    param(
        [int] $RequestedWidth,
        [int] $RequestedHeight,
        [string] $RequestedTitle,
        [uint32] $RequestedBackgroundColor,
        [int] $RequestedX,
        [int] $RequestedY,
        [bool] $RequestedBorderless,
        [bool] $RequestedTopmost,
        [Nullable[uint32]] $RequestedTransparentColorKey
    )
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Window.' + [Guid]::NewGuid().ToString('N')),
        [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module = $assembly.DefineDynamicModule('Native')
    $types = [Collections.Generic.Dictionary[string, Type]]::new()
    $calls = [Collections.Generic.Dictionary[string, Delegate]]::new()

    $nativeCall = ({
        param([IntPtr] $Address, [Type] $ReturnType, [Type[]] $ParameterTypes)
        $signature = $ReturnType.FullName + ':' + (($ParameterTypes | ForEach-Object FullName) -join ',')
        if (-not $types.ContainsKey($signature)) {
            $builder = $module.DefineType(
                'Call_' + [Guid]::NewGuid().ToString('N'),
                'Class,Public,Sealed', [MulticastDelegate])
            $constructor = $builder.DefineConstructor(
                'Public,HideBySig,RTSpecialName',
                [Reflection.CallingConventions]::Standard, @([object], [IntPtr]))
            $constructor.SetImplementationFlags('Runtime,Managed')
            $invoke = $builder.DefineMethod(
                'Invoke', 'Public,HideBySig,NewSlot,Virtual', $ReturnType, $ParameterTypes)
            $invoke.SetImplementationFlags('Runtime,Managed')
            $attribute = [Reflection.Emit.CustomAttributeBuilder]::new(
                [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
                    @([Runtime.InteropServices.CallingConvention])),
                @([Runtime.InteropServices.CallingConvention]::StdCall))
            $builder.SetCustomAttribute($attribute)
            $types[$signature] = $builder.CreateType()
        }
        $key = $Address.ToInt64().ToString() + ':' + $signature
        if (-not $calls.ContainsKey($key)) {
            $calls[$key] = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
                $Address, $types[$signature])
        }
        $calls[$key]
    }).GetNewClosure()

    $user32 = [Runtime.InteropServices.NativeLibrary]::Load('user32.dll')
    $kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
    $dwmapi = [Runtime.InteropServices.NativeLibrary]::Load('dwmapi.dll')
    $gdi32 = [Runtime.InteropServices.NativeLibrary]::Load('gdi32.dll')
    $bind = ({
        param([IntPtr] $Library, [string] $Name, [Type] $ReturnType, [Type[]] $Parameters)
        & $nativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($Library, $Name)) $ReturnType $Parameters
    }).GetNewClosure()
    $getModuleHandle = & $bind $kernel32 'GetModuleHandleW' ([IntPtr]) @([IntPtr])
    $registerClass = & $bind $user32 'RegisterClassExW' ([uint16]) @([IntPtr])
    $loadCursor = & $bind $user32 'LoadCursorW' ([IntPtr]) @([IntPtr], [IntPtr])
    $unregisterClass = & $bind $user32 'UnregisterClassW' ([bool]) @([IntPtr], [IntPtr])
    $createWindow = & $bind $user32 'CreateWindowExW' ([IntPtr]) @(
        [uint32], [IntPtr], [IntPtr], [uint32], [int32], [int32], [int32], [int32],
        [IntPtr], [IntPtr], [IntPtr], [IntPtr])
    $destroyWindow = & $bind $user32 'DestroyWindow' ([bool]) @([IntPtr])
    $showWindow = & $bind $user32 'ShowWindow' ([bool]) @([IntPtr], [int32])
    $updateWindow = & $bind $user32 'UpdateWindow' ([bool]) @([IntPtr])
    # ABI source: Windows SDK 10.0.26100.0, winuser.h. On Windows x64 MSG is 48 bytes.
    # GetMessageW returns BOOL as a signed 32-bit value so its documented -1 error is preserved.
    $getMessage = & $bind $user32 'GetMessageW' ([int32]) @(
        [IntPtr], [IntPtr], [uint32], [uint32])
    $translateMessage = & $bind $user32 'TranslateMessage' ([bool]) @([IntPtr])
    $dispatchMessage = & $bind $user32 'DispatchMessageW' ([IntPtr]) @([IntPtr])
    $postMessage = & $bind $user32 'PostMessageW' ([bool]) @(
        [IntPtr], [uint32], [IntPtr], [IntPtr])
    $isWindow = & $bind $user32 'IsWindow' ([bool]) @([IntPtr])
    $isChild = & $bind $user32 'IsChild' ([bool]) @([IntPtr],[IntPtr])
    $setLayeredWindowAttributes = & $bind $user32 'SetLayeredWindowAttributes' ([bool]) @(
        [IntPtr], [uint32], [byte], [uint32])
    $createSolidBrush = & $bind $gdi32 'CreateSolidBrush' ([IntPtr]) @([uint32])
    $deleteObject = & $bind $gdi32 'DeleteObject' ([bool]) @([IntPtr])
    $dwmSetWindowAttribute = & $bind $dwmapi 'DwmSetWindowAttribute' ([int32]) @(
        [IntPtr], [uint32], [IntPtr], [uint32])
    $dwmExtendFrame = & $bind $dwmapi 'DwmExtendFrameIntoClientArea' ([int32]) @(
        [IntPtr], [IntPtr])

    {
        $hModule = [IntPtr]$getModuleHandle.DynamicInvoke([IntPtr]::Zero)
        $className = 'QuickPSWindow_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
        $classNamePointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($className)
        $titlePointer = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($RequestedTitle)
        # Callers use RGB 0xRRGGBB; GDI COLORREF stores the bytes as 0x00BBGGRR.
        $colorRef = [uint32]((($RequestedBackgroundColor -band 0xFF) -shl 16) -bor
            ($RequestedBackgroundColor -band 0x00FF00) -bor
            (($RequestedBackgroundColor -shr 16) -band 0xFF))
        $backgroundBrush = [IntPtr]$createSolidBrush.DynamicInvoke($colorRef)
        if ($backgroundBrush -eq [IntPtr]::Zero) { throw 'CreateSolidBrush failed.' }
        $class = [Runtime.InteropServices.Marshal]::AllocHGlobal(80)
        for ($index = 0; $index -lt 80; $index++) {
            [Runtime.InteropServices.Marshal]::WriteByte($class, $index, 0)
        }
        try {
            [Runtime.InteropServices.Marshal]::WriteInt32($class, 0, 80)
            # CS_HREDRAW | CS_VREDRAW.
            [Runtime.InteropServices.Marshal]::WriteInt32($class, 4, 3)
            [Runtime.InteropServices.Marshal]::WriteIntPtr(
                $class, 8, [Runtime.InteropServices.NativeLibrary]::GetExport($user32, 'DefWindowProcW'))
            [Runtime.InteropServices.Marshal]::WriteIntPtr($class, 24, $hModule)
            # Give the client area its own standard arrow; otherwise Windows may
            # leave the last non-client resize cursor visible over the window.
            $cursor = [IntPtr]$loadCursor.DynamicInvoke(
                [IntPtr]::Zero, [IntPtr]::new(32512))
            [Runtime.InteropServices.Marshal]::WriteIntPtr($class, 40, $cursor)
            [Runtime.InteropServices.Marshal]::WriteIntPtr($class, 48, $backgroundBrush)
            [Runtime.InteropServices.Marshal]::WriteIntPtr($class, 64, $classNamePointer)
            $atom = [uint16]$registerClass.DynamicInvoke($class)
            if ($atom -eq 0) { throw 'RegisterClassExW failed.' }

            $style = if ($RequestedBorderless) { [uint32]0x80000000 } else { [uint32]0x00CF0000 }
            $extendedStyle = [uint32]0
            if ($RequestedBorderless) { $extendedStyle = $extendedStyle -bor [uint32]0x00040000 }
            if ($RequestedTopmost) { $extendedStyle = $extendedStyle -bor [uint32]0x00000008 }
            if ($null -ne $RequestedTransparentColorKey) { $extendedStyle = $extendedStyle -bor [uint32]0x00080000 }
            $hwnd = [IntPtr]$createWindow.DynamicInvoke(
                $extendedStyle, $classNamePointer, $titlePointer, $style,
                $RequestedX, $RequestedY, $RequestedWidth, $RequestedHeight,
                [IntPtr]::Zero, [IntPtr]::Zero, $hModule, [IntPtr]::Zero)
            if ($hwnd -eq [IntPtr]::Zero) { throw 'CreateWindowExW failed.' }

            if ($null -ne $RequestedTransparentColorKey) {
                $key = [uint32]$RequestedTransparentColorKey
                $keyColorRef = [uint32]((($key -band 0xFF) -shl 16) -bor
                    ($key -band 0x00FF00) -bor (($key -shr 16) -band 0xFF))
                if (-not $setLayeredWindowAttributes.DynamicInvoke($hwnd, $keyColorRef, [byte]255, [uint32]1)) {
                    throw 'SetLayeredWindowAttributes failed.'
                }
            }
        }
        catch {
            if ($atom) { [void]$unregisterClass.DynamicInvoke($classNamePointer, $hModule) }
            if ($backgroundBrush -ne [IntPtr]::Zero) {
                [void]$deleteObject.DynamicInvoke($backgroundBrush)
            }
            throw
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($class)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($titlePointer)
        }

        if ($RequestedBorderless) {
            $value = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
            $margins = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
            try {
                [Runtime.InteropServices.Marshal]::WriteInt32($value, 1)
                [void]$dwmSetWindowAttribute.DynamicInvoke($hwnd, [uint32]20, $value, [uint32]4)
                [Runtime.InteropServices.Marshal]::WriteInt32($margins, 0, -1)
                [Runtime.InteropServices.Marshal]::WriteInt32($margins, 4, -1)
                [Runtime.InteropServices.Marshal]::WriteInt32($margins, 8, -1)
                [Runtime.InteropServices.Marshal]::WriteInt32($margins, 12, -1)
                [void]$dwmExtendFrame.DynamicInvoke($hwnd, $margins)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($value)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($margins)
            }
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.Window.Windows'
            Hwnd = $hwnd
            HModule = $hModule
            ClassName = $className
            ClassNamePointer = $classNamePointer
            BackgroundBrush = $backgroundBrush
            Title = $RequestedTitle
            BackgroundColor = $RequestedBackgroundColor
            Width = $RequestedWidth
            Height = $RequestedHeight
            X = $RequestedX
            Y = $RequestedY
            Borderless = $RequestedBorderless
            Topmost = $RequestedTopmost
            Headless = $false
            Alive = $true
            Visible = $false
            ShowWindowCall = $showWindow
            UpdateWindowCall = $updateWindow
            CreateWindowCall = $createWindow
            SetLayeredWindowAttributesCall = $setLayeredWindowAttributes
            GetMessageCall = $getMessage
            TranslateMessageCall = $translateMessage
            DispatchMessageCall = $dispatchMessage
            PostMessageCall = $postMessage
            IsWindowCall = $isWindow
            IsChildCall = $isChild
            DwmSetWindowAttributeCall = $dwmSetWindowAttribute
            DestroyWindowCall = $destroyWindow
            UnregisterClassCall = $unregisterClass
            DeleteObjectCall = $deleteObject
        }

        $instance | Add-Member ScriptMethod Show ({
            [void]$this.ShowWindowCall.DynamicInvoke($this.Hwnd, [int32]5)
            [void]$this.UpdateWindowCall.DynamicInvoke($this.Hwnd)
            $this.Visible = $true
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateLayeredChild ({
            param([int]$X, [int]$Y, [int]$Width, [int]$Height,
                [bool]$TransparentBlack = $false)
            if ($this.Hwnd -eq [IntPtr]::Zero -or
                -not $this.IsWindowCall.DynamicInvoke($this.Hwnd)) {
                throw 'A live parent window is required.'
            }
            if ($Width -le 0 -or $Height -le 0) {
                throw 'Layered child dimensions must be positive.'
            }
            # SDK 10.0.26100.0 winuser.h: WS_EX_LAYERED; WS_CHILD, WS_VISIBLE,
            # WS_CLIPSIBLINGS; LWA_ALPHA or LWA_COLORKEY. The parent owns the child.
            $child = [IntPtr]$this.CreateWindowCall.DynamicInvoke(
                [uint32]0x00080000,$this.ClassNamePointer,[IntPtr]::Zero,
                [uint32]0x54000000,[int32]$X,[int32]$Y,[int32]$Width,[int32]$Height,
                $this.Hwnd,[IntPtr]::Zero,$this.HModule,[IntPtr]::Zero)
            if ($child -eq [IntPtr]::Zero) { throw 'CreateWindowExW(layered child) failed.' }
            $layerFlags = if ($TransparentBlack) { [uint32]1 } else { [uint32]2 }
            if (-not $this.SetLayeredWindowAttributesCall.DynamicInvoke(
                $child,[uint32]0,[byte]255,$layerFlags)) {
                [void]$this.DestroyWindowCall.DynamicInvoke($child)
                throw 'SetLayeredWindowAttributes(layered child) failed.'
            }
            $child
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetChildCloak ({
            param([IntPtr]$Child,[bool]$Cloak)
            if ($Child -eq [IntPtr]::Zero -or
                -not $this.IsChildCall.DynamicInvoke($this.Hwnd,$Child)) {
                throw 'The window is not a child of this parent.'
            }
            $value = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
            try {
                [Runtime.InteropServices.Marshal]::WriteInt32($value,[int]$Cloak)
                # SDK 10.0.26100.0 dwmapi.h: DWMWA_CLOAK = 13, BOOL = 4 bytes.
                $hr = [int32]$this.DwmSetWindowAttributeCall.DynamicInvoke(
                    $Child,[uint32]13,$value,[uint32]4)
                if ($hr -lt 0) {
                    throw ('DwmSetWindowAttribute(DWMWA_CLOAK) failed: 0x{0:X8}' -f [uint32]$hr)
                }
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($value) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod DestroyChild ({
            param([IntPtr]$Child)
            if ($Child -eq [IntPtr]::Zero -or
                -not $this.IsChildCall.DynamicInvoke($this.Hwnd,$Child)) {
                throw 'The window is not a child of this parent.'
            }
            if (-not $this.DestroyWindowCall.DynamicInvoke($Child)) {
                throw 'DestroyWindow(child) failed.'
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Close ({
            if ($this.Hwnd -eq [IntPtr]::Zero -or
                -not $this.IsWindowCall.DynamicInvoke($this.Hwnd)) {
                $this.Alive = $false
                return $false
            }
            if (-not $this.PostMessageCall.DynamicInvoke(
                $this.Hwnd, [uint32]0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) {
                throw 'PostMessageW(WM_CLOSE) failed.'
            }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Run ({
            param([scriptblock]$OnInput)
            $message = [Runtime.InteropServices.Marshal]::AllocHGlobal(48)
            try {
                $this.Alive = [bool]$this.IsWindowCall.DynamicInvoke($this.Hwnd)
                while ($this.Alive) {
                    $result = [int32]$this.GetMessageCall.DynamicInvoke(
                        $message, [IntPtr]::Zero, [uint32]0, [uint32]0)
                    if ($result -eq -1) { throw 'GetMessageW failed.' }
                    if ($result -eq 0) { break }
                    if ($OnInput) {
                        # MSG on Windows x64: HWND 0, UINT message 8,
                        # WPARAM 16, LPARAM 24. Dispatch semantic input only.
                        $messageId=[Runtime.InteropServices.Marshal]::ReadInt32($message,8)
                        $inputEvent=$null
                        if ($messageId -eq 0x0100) {
                            $key=[Runtime.InteropServices.Marshal]::ReadIntPtr($message,16).ToInt32()
                            $flags=[Runtime.InteropServices.Marshal]::ReadIntPtr($message,24).ToInt64()
                            $inputEvent=[pscustomobject]@{Kind='KeyDown';KeyCode=$key;Repeat=($flags -band 0x40000000) -ne 0}
                        } elseif ($messageId -eq 0x0201) {
                            $inputEvent=[pscustomobject]@{Kind='PointerDown';Button='Left'}
                        } elseif ($messageId -eq 0x0202) {
                            $inputEvent=[pscustomobject]@{Kind='PointerUp';Button='Left'}
                        }
                        if ($inputEvent) { $null=& $OnInput $inputEvent }
                    }
                    [void]$this.TranslateMessageCall.DynamicInvoke($message)
                    [void]$this.DispatchMessageCall.DynamicInvoke($message)
                    $this.Alive = [bool]$this.IsWindowCall.DynamicInvoke($this.Hwnd)
                }
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($message) }
            $this.Alive
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            if ($this.Hwnd -ne [IntPtr]::Zero) {
                if ($this.IsWindowCall.DynamicInvoke($this.Hwnd)) {
                    [void]$this.DestroyWindowCall.DynamicInvoke($this.Hwnd)
                }
                $this.Hwnd = [IntPtr]::Zero
            }
            if ($this.ClassNamePointer -ne [IntPtr]::Zero) {
                [void]$this.UnregisterClassCall.DynamicInvoke(
                    $this.ClassNamePointer, $this.HModule)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($this.ClassNamePointer)
                $this.ClassNamePointer = [IntPtr]::Zero
            }
            if ($this.BackgroundBrush -ne [IntPtr]::Zero) {
                [void]$this.DeleteObjectCall.DynamicInvoke($this.BackgroundBrush)
                $this.BackgroundBrush = [IntPtr]::Zero
            }
            $this.Alive = $false
            $this.Visible = $false
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
} $Width $Height $Title $BackgroundColor $X $Y ([bool]$Borderless) ([bool]$Topmost) $TransparentColorKey

& $Window

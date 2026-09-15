[CmdletBinding()]
param(
    [int] $Width = 960,
    [int] $Height = 540,
    [string] $Title = 'QuickPS Window',
    [uint32] $BackgroundColor = 0x0033CC,
    [switch] $Borderless,
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
        [bool] $RequestedBorderless
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
    $peekMessage = & $bind $user32 'PeekMessageW' ([bool]) @(
        [IntPtr], [IntPtr], [uint32], [uint32], [uint32])
    $translateMessage = & $bind $user32 'TranslateMessage' ([bool]) @([IntPtr])
    $dispatchMessage = & $bind $user32 'DispatchMessageW' ([IntPtr]) @([IntPtr])
    $isWindow = & $bind $user32 'IsWindow' ([bool]) @([IntPtr])
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
            $extendedStyle = if ($RequestedBorderless) { [uint32]0x00040000 } else { [uint32]0 }
            $hwnd = [IntPtr]$createWindow.DynamicInvoke(
                $extendedStyle, $classNamePointer, $titlePointer, $style,
                [int32]150, [int32]150, $RequestedWidth, $RequestedHeight,
                [IntPtr]::Zero, [IntPtr]::Zero, $hModule, [IntPtr]::Zero)
            if ($hwnd -eq [IntPtr]::Zero) { throw 'CreateWindowExW failed.' }
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
            Borderless = $RequestedBorderless
            Headless = $false
            Alive = $true
            Visible = $false
            ShowWindowCall = $showWindow
            UpdateWindowCall = $updateWindow
            PeekMessageCall = $peekMessage
            TranslateMessageCall = $translateMessage
            DispatchMessageCall = $dispatchMessage
            IsWindowCall = $isWindow
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

        $instance | Add-Member ScriptMethod Pump ({
            $message = [Runtime.InteropServices.Marshal]::AllocHGlobal(48)
            try {
                while ($this.PeekMessageCall.DynamicInvoke(
                    $message, [IntPtr]::Zero, [uint32]0, [uint32]0, [uint32]1)) {
                    [void]$this.TranslateMessageCall.DynamicInvoke($message)
                    [void]$this.DispatchMessageCall.DynamicInvoke($message)
                }
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($message) }
            $this.Alive = [bool]$this.IsWindowCall.DynamicInvoke($this.Hwnd)
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
} $Width $Height $Title $BackgroundColor ([bool]$Borderless)

& $Window

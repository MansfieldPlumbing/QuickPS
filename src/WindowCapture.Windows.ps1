[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'WindowCapture.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$WindowCapture = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.WindowCapture.' + [Guid]::NewGuid().ToString('N')),
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
    $gdi32 = [Runtime.InteropServices.NativeLibrary]::Load('gdi32.dll')
    $dwmapi = [Runtime.InteropServices.NativeLibrary]::Load('dwmapi.dll')
    $kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')

    $bind = ({
        param([IntPtr] $Library, [string] $Name, [Type] $ReturnType, [Type[]] $Parameters)
        & $nativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($Library, $Name)) $ReturnType $Parameters
    }).GetNewClosure()

    $cbType = $module.DefineType(
        'WndEnumCallback_' + [Guid]::NewGuid().ToString('N'),
        'Class,Public,Sealed', [MulticastDelegate])
    $cbCtor = $cbType.DefineConstructor(
        'Public,HideBySig,RTSpecialName',
        [Reflection.CallingConventions]::Standard, @([object], [IntPtr]))
    $cbCtor.SetImplementationFlags('Runtime,Managed')
    $cbInv = $cbType.DefineMethod(
        'Invoke', 'Public,HideBySig,NewSlot,Virtual',
        [bool], @([IntPtr], [IntPtr]))
    $cbInv.SetImplementationFlags('Runtime,Managed')
    $cbAttr = [Reflection.Emit.CustomAttributeBuilder]::new(
        [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
            @([Runtime.InteropServices.CallingConvention])),
        @([Runtime.InteropServices.CallingConvention]::StdCall))
    $cbType.SetCustomAttribute($cbAttr)
    $wndEnumProcType = $cbType.CreateType()

    $enumDesktopWindows = & $bind $user32 'EnumDesktopWindows' ([bool]) @([IntPtr], $wndEnumProcType, [IntPtr])
    $getWindowText = & $bind $user32 'GetWindowTextW' ([int32]) @([IntPtr], [IntPtr], [int32])
    $getWindowTextLength = & $bind $user32 'GetWindowTextLengthW' ([int32]) @([IntPtr])
    $isWindowVisible = & $bind $user32 'IsWindowVisible' ([bool]) @([IntPtr])
    $isIconic = & $bind $user32 'IsIconic' ([bool]) @([IntPtr])
    $getWindowRect = & $bind $user32 'GetWindowRect' ([bool]) @([IntPtr], [IntPtr])
    $getWindowThreadProcessId = & $bind $user32 'GetWindowThreadProcessId' ([uint32]) @([IntPtr], [IntPtr])
    $getDC = & $bind $user32 'GetDC' ([IntPtr]) @([IntPtr])
    $releaseDC = & $bind $user32 'ReleaseDC' ([int32]) @([IntPtr], [IntPtr])
    $printWindow = & $bind $user32 'PrintWindow' ([bool]) @([IntPtr], [IntPtr], [uint32])
    $getDesktopWindow = & $bind $user32 'GetDesktopWindow' ([IntPtr]) @()

    $createCompatibleDC = & $bind $gdi32 'CreateCompatibleDC' ([IntPtr]) @([IntPtr])
    $createDIBSection = & $bind $gdi32 'CreateDIBSection' ([IntPtr]) @(
        [IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr], [uint32])
    $selectObject = & $bind $gdi32 'SelectObject' ([IntPtr]) @([IntPtr], [IntPtr])
    $bitBlt = & $bind $gdi32 'BitBlt' ([bool]) @(
        [IntPtr], [int32], [int32], [int32], [int32], [IntPtr], [int32], [int32], [uint32])
    $deleteDC = & $bind $gdi32 'DeleteDC' ([bool]) @([IntPtr])
    $deleteObject = & $bind $gdi32 'DeleteObject' ([bool]) @([IntPtr])

    $dwmGetWindowAttribute = & $bind $dwmapi 'DwmGetWindowAttribute' ([int32]) @(
        [IntPtr], [uint32], [IntPtr], [uint32])

    $allocate = ({
        param([int] $Bytes)
        $p = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
        for ($i = 0; $i -lt $Bytes; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($p, $i, 0) }
        $p
    }).GetNewClosure()

    $instance = [PSCustomObject]@{
        PSTypeName = 'QuickPS.WindowCapture.Windows'
        User32 = $user32
        Gdi32 = $gdi32
        Dwmapi = $dwmapi
        Kernel32 = $kernel32
        Allocate = $allocate
        EnumDesktopWindowsCall = $enumDesktopWindows
        GetWindowTextCall = $getWindowText
        GetWindowTextLengthCall = $getWindowTextLength
        IsWindowVisibleCall = $isWindowVisible
        IsIconicCall = $isIconic
        GetWindowRectCall = $getWindowRect
        GetWindowThreadProcessIdCall = $getWindowThreadProcessId
        GetDCCall = $getDC
        ReleaseDCCall = $releaseDC
        PrintWindowCall = $printWindow
        GetDesktopWindowCall = $getDesktopWindow
        CreateCompatibleDCCall = $createCompatibleDC
        CreateDIBSectionCall = $createDIBSection
        SelectObjectCall = $selectObject
        BitBltCall = $bitBlt
        DeleteDCCall = $deleteDC
        DeleteObjectCall = $deleteObject
        DwmGetWindowAttributeCall = $dwmGetWindowAttribute
        WndEnumProcType = $wndEnumProcType
        HWinsta = [IntPtr]::Zero
        HDesk = [IntPtr]::Zero
        Disposed = $false
    }

    $instance | Add-Member ScriptMethod EnsureDesktop ({
        if($this.Disposed){throw 'Capture instance is disposed.'}
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod GetWindows ({
        $this.EnsureDesktop()
        $windowList = [Collections.Generic.List[object]]::new()
        $rectBuffer = & $this.Allocate 16
        $pidBuffer = & $this.Allocate 4
        $textBuffer = & $this.Allocate 512

        try {
            $context = $this
            $scriptCallback = {
                param([IntPtr] $hwnd, [IntPtr] $lparam)
                if (-not $context.IsWindowVisibleCall.DynamicInvoke(@($hwnd))) { return $true }
                $len = [int]$context.GetWindowTextLengthCall.DynamicInvoke(@($hwnd))
                if ($len -le 0) { return $true }

                [void]$context.GetWindowTextCall.DynamicInvoke(@($hwnd, $textBuffer, 256))
                $title = [Runtime.InteropServices.Marshal]::PtrToStringUni($textBuffer)
                if ([string]::IsNullOrWhiteSpace($title)) { return $true }

                # Filter out internal/system IME windows and popups with no area
                if ($title -eq 'Default IME' -or $title -eq 'MSCTFIME UI') { return $true }

                [void]$context.GetWindowThreadProcessIdCall.DynamicInvoke(@($hwnd, $pidBuffer))
                $processId = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($pidBuffer)

                # DWMWA_EXTENDED_FRAME_BOUNDS = 9
                $hr = [int]$context.DwmGetWindowAttributeCall.DynamicInvoke(@($hwnd, [uint32]9, $rectBuffer, [uint32]16))
                if ($hr -lt 0) {
                    [void]$context.GetWindowRectCall.DynamicInvoke(@($hwnd, $rectBuffer))
                }
                $left = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 0)
                $top = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 4)
                $right = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 8)
                $bottom = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 12)
                $width = $right - $left
                $height = $bottom - $top

                if ($width -gt 32 -and $height -gt 32) {
                    $processName = ''
                    try {
                        $p = [Diagnostics.Process]::GetProcessById([int]$processId)
                        try{$processName = $p.ProcessName}finally{$p.Dispose()}
                    } catch { }

                    $windowList.Add([PSCustomObject]@{
                        Hwnd = $hwnd
                        Title = $title
                        ProcessId = $processId
                        ProcessName = $processName
                        Width = $width
                        Height = $height
                        Left = $left
                        Top = $top
                        IsIconic = [bool]$context.IsIconicCall.DynamicInvoke(@($hwnd))
                    })
                }
                return $true
            }.GetNewClosure()

            $delegate = $scriptCallback -as $this.WndEnumProcType
            # Null desktop selects the calling thread's current desktop.
            if(-not $this.EnumDesktopWindowsCall.DynamicInvoke(@([IntPtr]::Zero, $delegate, [IntPtr]::Zero))){throw 'Window enumeration failed.'}
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($rectBuffer)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($pidBuffer)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($textBuffer)
        }

        return $windowList.ToArray()
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod CaptureWindow ({
        param(
            [Parameter(Mandatory)][IntPtr] $Hwnd,
            [Parameter(Mandatory)][string] $OutputPath, [switch] $AllowScreenFallback
        )
        if ($Hwnd -eq [IntPtr]::Zero) { throw 'Invalid window handle.' }
        $this.EnsureDesktop()


        $rectBuffer = & $this.Allocate 16
        try {
            $hr = [int]$this.DwmGetWindowAttributeCall.DynamicInvoke(@($Hwnd, [uint32]9, $rectBuffer, [uint32]16))
            if ($hr -lt 0) {
                [void]$this.GetWindowRectCall.DynamicInvoke(@($Hwnd, $rectBuffer))
            }
            $left = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 0)
            $top = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 4)
            $right = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 8)
            $bottom = [Runtime.InteropServices.Marshal]::ReadInt32($rectBuffer, 12)
            $width = $right - $left
            $height = $bottom - $top
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($rectBuffer)
        }

        if ($width -le 0 -or $height -le 0) {
            throw "Window has invalid dimensions: ${width}x${height}"
        }

        if([long]$width * [long]$height * 4 -gt 268435456){throw 'Capture exceeds 256 MiB capacity.'}
        $screenDC = [IntPtr]$this.GetDCCall.DynamicInvoke(@([IntPtr]::Zero))
        if ($screenDC -eq [IntPtr]::Zero) { throw 'GetDC(0) failed.' }

        $memDC = [IntPtr]$this.CreateCompatibleDCCall.DynamicInvoke(@($screenDC))
        if ($memDC -eq [IntPtr]::Zero) {
            [void]$this.ReleaseDCCall.DynamicInvoke(@([IntPtr]::Zero, $screenDC))
            throw 'CreateCompatibleDC failed.'
        }

        $bmi = & $this.Allocate 40
        $bitsPtrRef = & $this.Allocate ([IntPtr]::Size)
        [IntPtr]$hBitmap = [IntPtr]::Zero
        [IntPtr]$oldBitmap = [IntPtr]::Zero
        try {
            [Runtime.InteropServices.Marshal]::WriteInt32($bmi, 0, 40)
            [Runtime.InteropServices.Marshal]::WriteInt32($bmi, 4, $width)
            [Runtime.InteropServices.Marshal]::WriteInt32($bmi, 8, -$height)
            [Runtime.InteropServices.Marshal]::WriteInt16($bmi, 12, 1)
            [Runtime.InteropServices.Marshal]::WriteInt16($bmi, 14, 32)
            [Runtime.InteropServices.Marshal]::WriteInt32($bmi, 16, 0)

            $hBitmap = [IntPtr]$this.CreateDIBSectionCall.DynamicInvoke(@(
                $memDC, $bmi, [uint32]0, $bitsPtrRef, [IntPtr]::Zero, [uint32]0))
            if ($hBitmap -eq [IntPtr]::Zero) { throw 'CreateDIBSection failed.' }

            $bitsPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($bitsPtrRef)
            $oldBitmap = [IntPtr]$this.SelectObjectCall.DynamicInvoke(@($memDC, $hBitmap))

            # PW_RENDERFULLCONTENT = 2
            $captured = [bool]$this.PrintWindowCall.DynamicInvoke(@($Hwnd, $memDC, [uint32]2))
            if (-not $captured) {
                # Fallback to PW_CLIENTONLY (1) or default (0)
                $captured = [bool]$this.PrintWindowCall.DynamicInvoke(@($Hwnd, $memDC, [uint32]0))
            }
            if (-not $captured -and $AllowScreenFallback) {
                # Explicit screen-copy fallback.
                $captured=[bool]$this.BitBltCall.DynamicInvoke(@(
                    $memDC, 0, 0, $width, $height, $screenDC, $left, $top, [uint32]0x00CC0020))
            }

            if(-not $captured){throw 'Requested window capture failed.'}
            $stride = $width * 4
            $imageBytes = $stride * $height
            $fileHeaderSize = 14
            $infoHeaderSize = 40
            $totalFileSize = $fileHeaderSize + $infoHeaderSize + $imageBytes

            $outDir = [IO.Path]::GetDirectoryName($OutputPath)
            if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                [IO.Directory]::CreateDirectory($outDir) | Out-Null
            }

            $stream = [IO.FileStream]::new($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
            $writer = [IO.BinaryWriter]::new($stream)
            try {
                # BITMAPFILEHEADER
                $writer.Write([byte]0x42) # 'B'
                $writer.Write([byte]0x4D) # 'M'
                $writer.Write([uint32]$totalFileSize)
                $writer.Write([uint16]0)
                $writer.Write([uint16]0)
                $writer.Write([uint32]($fileHeaderSize + $infoHeaderSize))

                # BITMAPINFOHEADER (positive height for standard BMP format)
                $writer.Write([uint32]40)
                $writer.Write([int32]$width)
                $writer.Write([int32]$height)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]0)
                $writer.Write([uint32]$imageBytes)
                $writer.Write([int32]0)
                $writer.Write([int32]0)
                $writer.Write([uint32]0)
                $writer.Write([uint32]0)

                $rowBuffer = [byte[]]::new($stride)
                for ($row = $height - 1; $row -ge 0; $row--) {
                    $rowAddress = [IntPtr]::Add($bitsPtr, $row * $stride)
                    [Runtime.InteropServices.Marshal]::Copy($rowAddress, $rowBuffer, 0, $stride)
                    $writer.Write($rowBuffer, 0, $stride)
                }
            }
            finally {
                $writer.Dispose()
                $stream.Dispose()
            }

            return [PSCustomObject]@{
                Path = $OutputPath
                Width = $width
                Height = $height
                Bytes = $imageBytes
                Hwnd = $Hwnd
            }
        }
        finally {
            if ($oldBitmap -ne [IntPtr]::Zero) { [void]$this.SelectObjectCall.DynamicInvoke(@($memDC, $oldBitmap)) }
            if ($hBitmap -ne [IntPtr]::Zero) { [void]$this.DeleteObjectCall.DynamicInvoke(@($hBitmap)) }
            [void]$this.DeleteDCCall.DynamicInvoke(@($memDC))
            [void]$this.ReleaseDCCall.DynamicInvoke(@([IntPtr]::Zero, $screenDC))
            [Runtime.InteropServices.Marshal]::FreeHGlobal($bmi)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($bitsPtrRef)
        }
    }.GetNewClosure())

    $instance | Add-Member ScriptMethod Dispose ({
        if ($this.Disposed) { return }
        $this.Disposed = $true
        foreach($name in @('User32','Gdi32','Dwmapi','Kernel32')){
            if($this.$name -ne [IntPtr]::Zero){[Runtime.InteropServices.NativeLibrary]::Free($this.$name);$this.$name=[IntPtr]::Zero}
        }
    }.GetNewClosure())

    return $instance
}

$WindowCapture

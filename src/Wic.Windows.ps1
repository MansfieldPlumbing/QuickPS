[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Wic.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$Wic = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Wic.' + [Guid]::NewGuid().ToString('N')),
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

    $exportCall = ({
        param([IntPtr] $Library, [string] $Name, [Type] $ReturnType, [Type[]] $ParameterTypes)
        & $nativeCall (
            [Runtime.InteropServices.NativeLibrary]::GetExport($Library, $Name)
        ) $ReturnType $ParameterTypes
    }).GetNewClosure()

    $comCall = ({
        param(
            [IntPtr] $Object,
            [int] $Slot,
            [Type] $ReturnType,
            [object[]] $Arguments,
            [Type[]] $ParameterTypes
        )
        if ($Object -eq [IntPtr]::Zero) { throw 'Cannot invoke a null COM interface.' }
        $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
        $address = [Runtime.InteropServices.Marshal]::ReadIntPtr(
            $vtable, $Slot * [IntPtr]::Size)
        $call = & $nativeCall $address $ReturnType (@([IntPtr]) + $ParameterTypes)
        $call.DynamicInvoke(@($Object) + $Arguments)
    }).GetNewClosure()

    $allocate = ({
        param([int] $Bytes)
        $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
        for ($index = 0; $index -lt $Bytes; $index++) {
            [Runtime.InteropServices.Marshal]::WriteByte($pointer, $index, 0)
        }
        $pointer
    }).GetNewClosure()

    $guidBlock = ({
        param([Guid] $Guid)
        $pointer = & $allocate 16
        [Runtime.InteropServices.Marshal]::Copy($Guid.ToByteArray(), 0, $pointer, 16)
        $pointer
    }).GetNewClosure()

    $ole32 = [Runtime.InteropServices.NativeLibrary]::Load('ole32.dll')
    $coInitializeEx = & $exportCall $ole32 'CoInitializeEx' ([int32]) @([IntPtr], [uint32])
    $coUninitialize = & $exportCall $ole32 'CoUninitialize' ([void]) @()
    $coCreateInstance = & $exportCall $ole32 'CoCreateInstance' ([int32]) @(
        [IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr])

    {
        $coHr = [int32]$coInitializeEx.DynamicInvoke([IntPtr]::Zero, [uint32]0)
        $coOwned = $coHr -eq 0 -or $coHr -eq 1
        $coBits = [uint32]([int64]$coHr -band 0xFFFFFFFFL)
        # RPC_E_CHANGED_MODE is acceptable because COM is already initialized.
        if ($coHr -lt 0 -and $coBits -ne [uint32]2147549446) {
            throw ('CoInitializeEx failed: 0x{0:X8}' -f $coBits)
        }

        $classId = & $guidBlock ([Guid]'cacaf262-9370-4615-a13b-9f5539da4c0a')
        $interfaceId = & $guidBlock ([Guid]'ec5ec8a9-c395-4314-9c77-54d7a935ff70')
        $output = & $allocate ([IntPtr]::Size)
        try {
            $hr = [int32]$coCreateInstance.DynamicInvoke(
                $classId, [IntPtr]::Zero, [uint32]1, $interfaceId, $output)
            $factory = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($classId)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($interfaceId)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
        }
        if ($hr -lt 0 -or $factory -eq [IntPtr]::Zero) {
            if ($coOwned) { $coUninitialize.DynamicInvoke() }
            throw ('CoCreateInstance(WICImagingFactory) failed: 0x{0:X8}' -f [uint32]$hr)
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.Wic.Windows'
            Factory = $factory
            Children = [Collections.Generic.List[IntPtr]]::new()
            CoOwned = $coOwned
            CoUninitializeCall = $coUninitialize
            ComCall = $comCall
            Allocate = $allocate
            GuidBlock = $guidBlock
            PixelFormat32bppPbgra = [Guid]'6fddc324-4e03-4bfe-b185-3d77768dc910'
        }

        $instance | Add-Member ScriptMethod Track ({
            param([IntPtr] $Pointer)
            if ($Pointer -ne [IntPtr]::Zero) { $this.Children.Add($Pointer) }
            $Pointer
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateBitmap ({
            param(
                [uint32] $Width,
                [uint32] $Height,
                [Guid] $PixelFormat = $this.PixelFormat32bppPbgra,
                [ValidateSet('OnDemand', 'OnLoad')][string] $Cache = 'OnLoad'
            )
            if ($Width -eq 0 -or $Height -eq 0) { throw 'Bitmap dimensions must be positive.' }
            $cacheOption = if ($Cache -eq 'OnDemand') { [uint32]0 } else { [uint32]2 }
            $format = & $this.GuidBlock $PixelFormat
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IWICImagingFactory inherits IUnknown; CreateBitmap is slot 17.
                $hr = [int32](& $this.ComCall $this.Factory 17 ([int32]) @(
                    $Width, $Height, $format, $cacheOption, $output
                ) @([uint32], [uint32], [IntPtr], [uint32], [IntPtr]))
                $bitmap = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($format)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $bitmap -eq [IntPtr]::Zero) {
                throw ('IWICImagingFactory::CreateBitmap failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Track($bitmap)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetSize ({
            param([IntPtr] $BitmapSource)
            $size = & $this.Allocate 8
            try {
                # IWICBitmapSource::GetSize follows IUnknown at slot 3.
                $hr = [int32](& $this.ComCall $BitmapSource 3 ([int32]) @(
                    $size, [IntPtr]::Add($size, 4)) @([IntPtr], [IntPtr]))
                $width = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($size)
                $height = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($size, 4)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($size) }
            if ($hr -lt 0) { throw ('IWICBitmapSource::GetSize failed: 0x{0:X8}' -f [uint32]$hr) }
            [PSCustomObject]@{ Width = $width; Height = $height }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateFormatConverter ({
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IWICImagingFactory::CreateFormatConverter is slot 10.
                $hr = [int32](& $this.ComCall $this.Factory 10 ([int32]) @($output) @([IntPtr]))
                $converter = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $converter -eq [IntPtr]::Zero) {
                throw ('IWICImagingFactory::CreateFormatConverter failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Track($converter)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod InitializeConverter ({
            param(
                [IntPtr] $Converter,
                [IntPtr] $Source,
                [Guid] $DestinationFormat = $this.PixelFormat32bppPbgra
            )
            $format = & $this.GuidBlock $DestinationFormat
            try {
                # IWICFormatConverter::Initialize is slot 8 after IWICBitmapSource.
                $hr = [int32](& $this.ComCall $Converter 8 ([int32]) @(
                    $Source, $format, [uint32]0, [IntPtr]::Zero, [double]0, [uint32]0
                ) @([IntPtr], [IntPtr], [uint32], [IntPtr], [double], [uint32]))
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($format) }
            if ($hr -lt 0) { throw ('IWICFormatConverter::Initialize failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod DecodeFile ({
            param([string] $Path)
            $fullPath = [IO.Path]::GetFullPath($Path)
            if (-not [IO.File]::Exists($fullPath)) { throw "Image file not found: $fullPath" }
            $name = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($fullPath)
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # GENERIC_READ and WICDecodeMetadataCacheOnDemand.
                $hr = [int32](& $this.ComCall $this.Factory 3 ([int32]) @(
                    $name, [IntPtr]::Zero, [uint32]2147483648, [uint32]0, $output
                ) @([IntPtr], [IntPtr], [uint32], [uint32], [IntPtr]))
                $decoder = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($name)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $decoder -eq [IntPtr]::Zero) {
                throw ('IWICImagingFactory::CreateDecoderFromFilename failed: 0x{0:X8}' -f [uint32]$hr)
            }
            [void]$this.Track($decoder)
            $frameOut = & $this.Allocate ([IntPtr]::Size)
            try {
                # IWICBitmapDecoder::GetFrame is slot 13.
                $hr = [int32](& $this.ComCall $decoder 13 ([int32]) @(
                    [uint32]0, $frameOut) @([uint32], [IntPtr]))
                $frame = [Runtime.InteropServices.Marshal]::ReadIntPtr($frameOut)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($frameOut) }
            if ($hr -lt 0 -or $frame -eq [IntPtr]::Zero) {
                throw ('IWICBitmapDecoder::GetFrame failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Track($frame)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            for ($index = $this.Children.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Children[$index] 2 ([uint32]) @() @())
            }
            $this.Children.Clear()
            if ($this.Factory -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Factory 2 ([uint32]) @() @())
                $this.Factory = [IntPtr]::Zero
            }
            if ($this.CoOwned) {
                $this.CoUninitializeCall.DynamicInvoke()
                $this.CoOwned = $false
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $Wic

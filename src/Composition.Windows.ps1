[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [IntPtr] $DxgiDevice
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Composition.Windows.ps1 must be invoked with &, not dot-sourced.'
}
if ($DxgiDevice -eq [IntPtr]::Zero) {
    throw 'Composition.Windows.ps1 requires a live IDXGIDevice.'
}

$Composition = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Composition.' + [Guid]::NewGuid().ToString('N')),
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

    $dcomp = [Runtime.InteropServices.NativeLibrary]::Load('dcomp.dll')
    $createAddress = [Runtime.InteropServices.NativeLibrary]::GetExport(
        $dcomp, 'DCompositionCreateDevice')
    $createDevice = & $nativeCall $createAddress ([int32]) @([IntPtr], [IntPtr], [IntPtr])

    {
        $iid = & $allocate 16
        $output = & $allocate ([IntPtr]::Size)
        try {
            [Runtime.InteropServices.Marshal]::Copy(
                ([Guid]'c37ea93a-e7aa-450d-b16f-9746cb0407f3').ToByteArray(),
                0, $iid, 16)
            $hr = [int32]$createDevice.DynamicInvoke($DxgiDevice, $iid, $output)
            $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
        }
        if ($hr -lt 0 -or $device -eq [IntPtr]::Zero) {
            throw ('DCompositionCreateDevice failed: 0x{0:X8}' -f [uint32]$hr)
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.Composition.Windows'
            Device = $device
            Targets = [Collections.Generic.List[IntPtr]]::new()
            Visuals = [Collections.Generic.List[IntPtr]]::new()
            ComCall = $comCall
            Allocate = $allocate
        }

        $instance | Add-Member ScriptMethod CreateTargetForWindow ({
            param([IntPtr] $Window, [bool] $Topmost = $true)
            if ($Window -eq [IntPtr]::Zero) { throw 'A live HWND is required.' }
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IDCompositionDevice inherits IUnknown; CreateTargetForHwnd is slot 6.
                $hr = [int32](& $this.ComCall $this.Device 6 ([int32]) @(
                    $Window, [int32]$Topmost, $output) @([IntPtr], [int32], [IntPtr]))
                $target = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $target -eq [IntPtr]::Zero) {
                throw ('IDCompositionDevice::CreateTargetForHwnd failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Targets.Add($target)
            $target
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateVisual ({
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IDCompositionDevice::CreateVisual is slot 7.
                $hr = [int32](& $this.ComCall $this.Device 7 ([int32]) @($output) @([IntPtr]))
                $visual = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $visual -eq [IntPtr]::Zero) {
                throw ('IDCompositionDevice::CreateVisual failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Visuals.Add($visual)
            $visual
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetRoot ({
            param([IntPtr] $Target, [IntPtr] $Visual)
            # IDCompositionTarget::SetRoot follows IUnknown at slot 3.
            $hr = [int32](& $this.ComCall $Target 3 ([int32]) @($Visual) @([IntPtr]))
            if ($hr -lt 0) { throw ('IDCompositionTarget::SetRoot failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetContent ({
            param([IntPtr] $Visual, [IntPtr] $Content)
            # IDCompositionVisual::SetContent is slot 15.
            $hr = [int32](& $this.ComCall $Visual 15 ([int32]) @($Content) @([IntPtr]))
            if ($hr -lt 0) { throw ('IDCompositionVisual::SetContent failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Commit ({
            # IDCompositionDevice::Commit follows IUnknown at slot 3.
            $hr = [int32](& $this.ComCall $this.Device 3 ([int32]) @() @())
            if ($hr -lt 0) { throw ('IDCompositionDevice::Commit failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod WaitForCommitCompletion ({
            # IDCompositionDevice::WaitForCommitCompletion is slot 4.
            $hr = [int32](& $this.ComCall $this.Device 4 ([int32]) @() @())
            if ($hr -lt 0) {
                throw ('IDCompositionDevice::WaitForCommitCompletion failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            for ($index = $this.Visuals.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Visuals[$index] 2 ([uint32]) @() @())
            }
            for ($index = $this.Targets.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Targets[$index] 2 ([uint32]) @() @())
            }
            $this.Visuals.Clear()
            $this.Targets.Clear()
            if ($this.Device -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Device 2 ([uint32]) @() @())
                $this.Device = [IntPtr]::Zero
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $Composition

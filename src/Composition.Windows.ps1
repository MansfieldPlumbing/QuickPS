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
            Resources = [Collections.Generic.List[IntPtr]]::new()
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

        # ABI: Windows SDK 10.0.26100.0 dcomp.h/dcompanimation.h and Microsoft
        # windows-rs 0.62.2 projection. Overloaded animation setters precede
        # their scalar counterparts in the COM vtable.
        # Each returned COM reference is owned by this device and released in Dispose.
        $instance | Add-Member ScriptMethod CreateSurfaceFromWindow ({
            param([IntPtr]$Window)
            if ($Window -eq [IntPtr]::Zero) { throw 'A layered window is required.' }
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                $hr = [int32](& $this.ComCall $this.Device 11 ([int32]) @(
                    $Window,$output) @([IntPtr],[IntPtr]))
                $surface = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $surface -eq [IntPtr]::Zero) {
                throw ('CreateSurfaceFromHwnd failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Resources.Add($surface)
            $surface
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateScaleTransform ({
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                $hr = [int32](& $this.ComCall $this.Device 13 ([int32]) @($output) @([IntPtr]))
                $scale = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $scale -eq [IntPtr]::Zero) {
                throw ('CreateScaleTransform failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Resources.Add($scale)
            $scale
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateRotateTransform ({
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IDCompositionDevice::CreateRotateTransform is slot 14.
                $hr = [int32](& $this.ComCall $this.Device 14 ([int32]) @($output) @([IntPtr]))
                $rotation = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $rotation -eq [IntPtr]::Zero) {
                throw ('CreateRotateTransform failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Resources.Add($rotation)
            $rotation
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateAnimation ({
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                $hr = [int32](& $this.ComCall $this.Device 25 ([int32]) @($output) @([IntPtr]))
                $animation = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $animation -eq [IntPtr]::Zero) {
                throw ('CreateAnimation failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Resources.Add($animation)
            $animation
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AddCubicSegment ({
            param([IntPtr]$Animation,[double]$Start,[single]$Constant,
                [single]$Linear,[single]$Quadratic,[single]$Cubic)
            $hr = [int32](& $this.ComCall $Animation 5 ([int32]) @(
                $Start,$Constant,$Linear,$Quadratic,$Cubic) @(
                [double],[single],[single],[single],[single]))
            if ($hr -lt 0) { throw ('AddCubic failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AddSinusoidalSegment ({
            param([IntPtr]$Animation,[double]$Start,[single]$Bias,
                [single]$Amplitude,[single]$Frequency,[single]$Phase)
            # IDCompositionAnimation::AddSinusoidal is slot 6; phase is degrees.
            $hr = [int32](& $this.ComCall $Animation 6 ([int32]) @(
                $Start,$Bias,$Amplitude,$Frequency,$Phase) @(
                [double],[single],[single],[single],[single]))
            if ($hr -lt 0) { throw ('AddSinusoidal failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AddRepeat ({
            param([IntPtr]$Animation,[double]$Start,[double]$Duration)
            if ($Start -le 0 -or $Duration -le 0 -or $Duration -gt $Start) {
                throw 'Repeat needs a positive preceding interval.'
            }
            # SDK 10.0.26100.0 dcompanimation.h: IDCompositionAnimation slot 7.
            $hr = [int32](& $this.ComCall $Animation 7 ([int32]) @(
                $Start,$Duration) @([double],[double]))
            if ($hr -lt 0) { throw ('AddRepeat failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod EndAnimation ({
            param([IntPtr]$Animation,[double]$At,[single]$Value)
            $hr = [int32](& $this.ComCall $Animation 8 ([int32]) @($At,$Value) @(
                [double],[single]))
            if ($hr -lt 0) { throw ('Animation End failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetScaleCenter ({
            param([IntPtr]$Scale,[single]$X,[single]$Y)
            foreach ($part in @(@(8,$X),@(10,$Y))) {
                $hr = [int32](& $this.ComCall $Scale $part[0] ([int32]) @(
                    [single]$part[1]) @([single]))
                if ($hr -lt 0) { throw ('Scale center failed: 0x{0:X8}' -f [uint32]$hr) }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetScaleAnimation ({
            param([IntPtr]$Scale,[IntPtr]$Animation)
            foreach ($slot in @(3,5)) {
                $hr = [int32](& $this.ComCall $Scale $slot ([int32]) @(
                    $Animation) @([IntPtr]))
                if ($hr -lt 0) { throw ('Scale animation failed: 0x{0:X8}' -f [uint32]$hr) }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetScaleAnimations ({
            param([IntPtr]$Scale,[IntPtr]$X,[IntPtr]$Y)
            foreach ($part in @(@(3,$X),@(5,$Y))) {
                $hr = [int32](& $this.ComCall $Scale $part[0] ([int32]) @(
                    [IntPtr]$part[1]) @([IntPtr]))
                if ($hr -lt 0) { throw ('Scale animation failed: 0x{0:X8}' -f [uint32]$hr) }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetRotateCenter ({
            param([IntPtr]$Rotation,[single]$X,[single]$Y)
            foreach ($part in @(@(6,$X),@(8,$Y))) {
                $hr = [int32](& $this.ComCall $Rotation $part[0] ([int32]) @(
                    [single]$part[1]) @([single]))
                if ($hr -lt 0) { throw ('Rotate center failed: 0x{0:X8}' -f [uint32]$hr) }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetRotateAnimation ({
            param([IntPtr]$Rotation,[IntPtr]$Animation)
            $hr = [int32](& $this.ComCall $Rotation 3 ([int32]) @(
                $Animation) @([IntPtr]))
            if ($hr -lt 0) { throw ('Rotate animation failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetVisualTransform ({
            param([IntPtr]$Visual,[IntPtr]$Transform)
            $hr = [int32](& $this.ComCall $Visual 7 ([int32]) @(
                $Transform) @([IntPtr]))
            if ($hr -lt 0) { throw ('SetTransform failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetVisualOffset ({
            param([IntPtr]$Visual,[single]$X,[single]$Y)
            foreach ($part in @(@(4,$X),@(6,$Y))) {
                $hr = [int32](& $this.ComCall $Visual $part[0] ([int32]) @(
                    [single]$part[1]) @([single]))
                if ($hr -lt 0) { throw ('SetOffset failed: 0x{0:X8}' -f [uint32]$hr) }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod SetVisualOffsetAnimation ({
            param([IntPtr]$Visual,[string]$Axis,[IntPtr]$Animation)
            $slot = switch ($Axis) { 'X' { 3 } 'Y' { 5 } default { throw 'Axis must be X or Y.' } }
            $hr = [int32](& $this.ComCall $Visual $slot ([int32]) @(
                $Animation) @([IntPtr]))
            if ($hr -lt 0) { throw ('Offset animation failed: 0x{0:X8}' -f [uint32]$hr) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AddVisual ({
            param([IntPtr]$Parent,[IntPtr]$Child)
            # IDCompositionVisual::AddVisual is slot 16; append above siblings.
            $hr = [int32](& $this.ComCall $Parent 16 ([int32]) @(
                $Child,[int32]1,[IntPtr]::Zero) @([IntPtr],[int32],[IntPtr]))
            if ($hr -lt 0) { throw ('AddVisual failed: 0x{0:X8}' -f [uint32]$hr) }
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
            for ($index = $this.Resources.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Resources[$index] 2 ([uint32]) @() @())
            }
            for ($index = $this.Visuals.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Visuals[$index] 2 ([uint32]) @() @())
            }
            for ($index = $this.Targets.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Targets[$index] 2 ([uint32]) @() @())
            }
            $this.Visuals.Clear()
            $this.Targets.Clear()
            $this.Resources.Clear()
            if ($this.Device -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Device 2 ([uint32]) @() @())
                $this.Device = [IntPtr]::Zero
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $Composition

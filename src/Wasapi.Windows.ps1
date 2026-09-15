[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Wasapi.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$Wasapi = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.Wasapi.' + [Guid]::NewGuid().ToString('N')),
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
                'Class,Public,Sealed',
                [MulticastDelegate])
            $constructor = $builder.DefineConstructor(
                'Public,HideBySig,RTSpecialName',
                [Reflection.CallingConventions]::Standard,
                @([object], [IntPtr]))
            $constructor.SetImplementationFlags('Runtime,Managed')
            $invoke = $builder.DefineMethod(
                'Invoke', 'Public,HideBySig,NewSlot,Virtual',
                $ReturnType, $ParameterTypes)
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
    $kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
    $coInitializeEx = & $exportCall $ole32 'CoInitializeEx' ([int32]) @([IntPtr], [uint32])
    $coUninitialize = & $exportCall $ole32 'CoUninitialize' ([void]) @()
    $coCreateInstance = & $exportCall $ole32 'CoCreateInstance' ([int32]) @(
        [IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr])
    $coTaskMemFree = & $exportCall $ole32 'CoTaskMemFree' ([void]) @([IntPtr])
    $createEvent = & $exportCall $kernel32 'CreateEventW' ([IntPtr]) @(
        [IntPtr], [bool], [bool], [IntPtr])
    $closeHandle = & $exportCall $kernel32 'CloseHandle' ([bool]) @([IntPtr])

    {
        $coHr = [int32]$coInitializeEx.DynamicInvoke([IntPtr]::Zero, [uint32]0)
        $coOwned = $coHr -eq 0 -or $coHr -eq 1
        $coBits = [uint32]([int64]$coHr -band 0xFFFFFFFFL)
        # RPC_E_CHANGED_MODE means COM is already initialized with another apartment model.
        if ($coHr -lt 0 -and $coBits -ne [uint32]2147549446) {
            throw ('CoInitializeEx failed: 0x{0:X8}' -f $coBits)
        }

        $classId = & $guidBlock ([Guid]'bcde0395-e52f-467c-8e3d-c4579291692e')
        $interfaceId = & $guidBlock ([Guid]'a95664d2-9614-4f35-a746-de8db63617e6')
        $output = & $allocate ([IntPtr]::Size)
        try {
            $hr = [int32]$coCreateInstance.DynamicInvoke(
                $classId, [IntPtr]::Zero, [uint32]23, $interfaceId, $output)
            $enumerator = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($classId)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($interfaceId)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
        }
        if ($hr -lt 0 -or $enumerator -eq [IntPtr]::Zero) {
            if ($coOwned) { $coUninitialize.DynamicInvoke() }
            throw ('CoCreateInstance(MMDeviceEnumerator) failed: 0x{0:X8}' -f [uint32]$hr)
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.Wasapi.Windows'
            Enumerator = $enumerator
            Interfaces = [Collections.Generic.List[IntPtr]]::new()
            Formats = [Collections.Generic.List[IntPtr]]::new()
            Events = [Collections.Generic.List[IntPtr]]::new()
            ActiveClients = [Collections.Generic.List[IntPtr]]::new()
            CoOwned = $coOwned
            CoUninitializeCall = $coUninitialize
            CoTaskMemFreeCall = $coTaskMemFree
            CreateEventCall = $createEvent
            CloseHandleCall = $closeHandle
            ComCall = $comCall
            Allocate = $allocate
            GuidBlock = $guidBlock
            AudioClientIid = [Guid]'1cb9ad4c-dbfa-4c32-b178-c2f568a703b2'
            CaptureClientIid = [Guid]'c8adbd64-e71e-48a0-a4de-185c395cd317'
            RenderClientIid = [Guid]'f294acfc-3146-4483-a7bf-addca7c260e2'
        }

        $instance | Add-Member ScriptMethod TrackInterface ({
            param([IntPtr] $Pointer)
            if ($Pointer -ne [IntPtr]::Zero) { $this.Interfaces.Add($Pointer) }
            $Pointer
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetDefaultEndpoint ({
            param(
                [ValidateSet('Render', 'Capture')][string] $Flow = 'Render',
                [ValidateSet('Console', 'Multimedia', 'Communications')][string] $Role = 'Multimedia'
            )
            $flowValue = if ($Flow -eq 'Render') { [uint32]0 } else { [uint32]1 }
            $roleValue = switch ($Role) {
                Console { [uint32]0 }
                Multimedia { [uint32]1 }
                Communications { [uint32]2 }
            }
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IMMDeviceEnumerator inherits IUnknown; GetDefaultAudioEndpoint is slot 4.
                $hr = [int32](& $this.ComCall $this.Enumerator 4 ([int32]) @(
                    $flowValue, $roleValue, $output) @([uint32], [uint32], [IntPtr]))
                $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $device -eq [IntPtr]::Zero) {
                throw ('IMMDeviceEnumerator::GetDefaultAudioEndpoint failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.TrackInterface($device)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ActivateAudioClient ({
            param([IntPtr] $Device)
            $iid = & $this.GuidBlock $this.AudioClientIid
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IMMDevice inherits IUnknown; Activate is slot 3.
                $hr = [int32](& $this.ComCall $Device 3 ([int32]) @(
                    $iid, [uint32]23, [IntPtr]::Zero, $output
                ) @([IntPtr], [uint32], [IntPtr], [IntPtr]))
                $client = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $client -eq [IntPtr]::Zero) {
                throw ('IMMDevice::Activate(IAudioClient) failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.TrackInterface($client)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetMixFormat ({
            param([IntPtr] $AudioClient)
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IAudioClient::GetMixFormat is slot 8 after IUnknown and earlier client methods.
                $hr = [int32](& $this.ComCall $AudioClient 8 ([int32]) @($output) @([IntPtr]))
                $format = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $format -eq [IntPtr]::Zero) {
                throw ('IAudioClient::GetMixFormat failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Formats.Add($format)
            $format
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetBufferSize ({
            param([IntPtr] $AudioClient)
            $output = & $this.Allocate 4
            try {
                $hr = [int32](& $this.ComCall $AudioClient 4 ([int32]) @($output) @([IntPtr]))
                $frames = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0) { throw ('IAudioClient::GetBufferSize failed: 0x{0:X8}' -f [uint32]$hr) }
            $frames
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod InitializeShared ({
            param(
                [IntPtr] $AudioClient,
                [IntPtr] $Format,
                [switch] $Loopback,
                [switch] $EventDriven,
                [int64] $BufferDuration = 10000000
            )
            [uint32]$flags = 0
            if ($Loopback) { $flags = $flags -bor [uint32]0x00020000 }
            if ($EventDriven) { $flags = $flags -bor [uint32]0x00040000 }
            $hr = [int32](& $this.ComCall $AudioClient 3 ([int32]) @(
                [uint32]0, $flags, $BufferDuration, [int64]0, $Format, [IntPtr]::Zero
            ) @([uint32], [uint32], [int64], [int64], [IntPtr], [IntPtr]))
            if ($hr -lt 0) { throw ('IAudioClient::Initialize failed: 0x{0:X8}' -f [uint32]$hr) }
            if (-not $EventDriven) { return [IntPtr]::Zero }
            $event = [IntPtr]$this.CreateEventCall.DynamicInvoke(
                [IntPtr]::Zero, $false, $false, [IntPtr]::Zero)
            if ($event -eq [IntPtr]::Zero) { throw 'CreateEventW failed for WASAPI.' }
            $this.Events.Add($event)
            $hr = [int32](& $this.ComCall $AudioClient 13 ([int32]) @($event) @([IntPtr]))
            if ($hr -lt 0) { throw ('IAudioClient::SetEventHandle failed: 0x{0:X8}' -f [uint32]$hr) }
            $event
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetService ({
            param(
                [IntPtr] $AudioClient,
                [ValidateSet('Capture', 'Render')][string] $Kind
            )
            $serviceIid = if ($Kind -eq 'Capture') {
                $this.CaptureClientIid
            } else {
                $this.RenderClientIid
            }
            $iid = & $this.GuidBlock $serviceIid
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                $hr = [int32](& $this.ComCall $AudioClient 14 ([int32]) @(
                    $iid, $output) @([IntPtr], [IntPtr]))
                $service = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $service -eq [IntPtr]::Zero) {
                throw ("IAudioClient::GetService($Kind) failed: 0x{0:X8}" -f [uint32]$hr)
            }
            $this.TrackInterface($service)
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetNextCapturePacketSize ({
            param([IntPtr] $CaptureClient)
            $output = & $this.Allocate 4
            try {
                $hr = [int32](& $this.ComCall $CaptureClient 5 ([int32]) @($output) @([IntPtr]))
                $frames = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0) {
                throw ('IAudioCaptureClient::GetNextPacketSize failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $frames
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AcquireCaptureBuffer ({
            param([IntPtr] $CaptureClient)
            $scratch = & $this.Allocate 32
            try {
                $dataOut = $scratch
                $framesOut = [IntPtr]::Add($scratch, 8)
                $flagsOut = [IntPtr]::Add($scratch, 12)
                $devicePositionOut = [IntPtr]::Add($scratch, 16)
                $qpcPositionOut = [IntPtr]::Add($scratch, 24)
                $hr = [int32](& $this.ComCall $CaptureClient 3 ([int32]) @(
                    $dataOut, $framesOut, $flagsOut, $devicePositionOut, $qpcPositionOut
                ) @([IntPtr], [IntPtr], [IntPtr], [IntPtr], [IntPtr]))
                if ($hr -lt 0) {
                    throw ('IAudioCaptureClient::GetBuffer failed: 0x{0:X8}' -f [uint32]$hr)
                }
                [PSCustomObject]@{
                    Data = [Runtime.InteropServices.Marshal]::ReadIntPtr($dataOut)
                    Frames = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($framesOut)
                    Flags = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($flagsOut)
                    DevicePosition = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($devicePositionOut)
                    QpcPosition = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($qpcPositionOut)
                }
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($scratch) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ReleaseCaptureBuffer ({
            param([IntPtr] $CaptureClient, [uint32] $Frames)
            $hr = [int32](& $this.ComCall $CaptureClient 4 ([int32]) @($Frames) @([uint32]))
            if ($hr -lt 0) {
                throw ('IAudioCaptureClient::ReleaseBuffer failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod AcquireRenderBuffer ({
            param([IntPtr] $RenderClient, [uint32] $Frames)
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                $hr = [int32](& $this.ComCall $RenderClient 3 ([int32]) @(
                    $Frames, $output) @([uint32], [IntPtr]))
                $data = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ($hr -lt 0 -or $data -eq [IntPtr]::Zero) {
                throw ('IAudioRenderClient::GetBuffer failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $data
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ReleaseRenderBuffer ({
            param([IntPtr] $RenderClient, [uint32] $Frames, [uint32] $Flags = 0)
            $hr = [int32](& $this.ComCall $RenderClient 4 ([int32]) @(
                $Frames, $Flags) @([uint32], [uint32]))
            if ($hr -lt 0) {
                throw ('IAudioRenderClient::ReleaseBuffer failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Start ({
            param([IntPtr] $AudioClient)
            $hr = [int32](& $this.ComCall $AudioClient 10 ([int32]) @() @())
            if ($hr -lt 0) { throw ('IAudioClient::Start failed: 0x{0:X8}' -f [uint32]$hr) }
            if (-not $this.ActiveClients.Contains($AudioClient)) {
                $this.ActiveClients.Add($AudioClient)
            }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Stop ({
            param([IntPtr] $AudioClient)
            $hr = [int32](& $this.ComCall $AudioClient 11 ([int32]) @() @())
            [void]$this.ActiveClients.Remove($AudioClient)
            if ($hr -lt 0) { throw ('IAudioClient::Stop failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            for ($index = $this.ActiveClients.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.ActiveClients[$index] 11 ([int32]) @() @())
            }
            $this.ActiveClients.Clear()
            for ($index = $this.Events.Count - 1; $index -ge 0; $index--) {
                [void]$this.CloseHandleCall.DynamicInvoke($this.Events[$index])
            }
            $this.Events.Clear()
            for ($index = $this.Formats.Count - 1; $index -ge 0; $index--) {
                $this.CoTaskMemFreeCall.DynamicInvoke($this.Formats[$index])
            }
            $this.Formats.Clear()
            for ($index = $this.Interfaces.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Interfaces[$index] 2 ([uint32]) @() @())
            }
            $this.Interfaces.Clear()
            if ($this.Enumerator -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Enumerator 2 ([uint32]) @() @())
                $this.Enumerator = [IntPtr]::Zero
            }
            if ($this.CoOwned) {
                $this.CoUninitializeCall.DynamicInvoke()
                $this.CoOwned = $false
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $Wasapi

[CmdletBinding()]
param(
    [IntPtr] $Adapter = [IntPtr]::Zero
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'D3D12.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$D3D12 = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.D3D12.' + [Guid]::NewGuid().ToString('N')),
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

    $d3d12 = [Runtime.InteropServices.NativeLibrary]::Load('d3d12.dll')
    $kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
    $createDevice = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($d3d12, 'D3D12CreateDevice')
    ) ([int32]) @([IntPtr], [int32], [IntPtr], [IntPtr])
    $createEvent = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($kernel32, 'CreateEventW')
    ) ([IntPtr]) @([IntPtr], [bool], [bool], [IntPtr])
    $closeHandle = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($kernel32, 'CloseHandle')
    ) ([bool]) @([IntPtr])
    $waitForSingleObject = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($kernel32, 'WaitForSingleObject')
    ) ([uint32]) @([IntPtr], [uint32])
    $serializeRootSignature = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($d3d12, 'D3D12SerializeRootSignature')
    ) ([int32]) @([IntPtr], [int32], [IntPtr], [IntPtr])

    {
        $iid = & $guidBlock ([Guid]'189819f1-1db6-4b57-be54-1821339b85f7')
        $output = & $allocate ([IntPtr]::Size)
        try {
            $hr = [int32]$createDevice.DynamicInvoke(
                $Adapter, [int32]0xB000, $iid, $output)
            $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
        }
        if ($hr -lt 0 -or $device -eq [IntPtr]::Zero) {
            throw ('D3D12CreateDevice failed: 0x{0:X8}' -f [uint32]$hr)
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.D3D12.Windows'
            Device = $device
            Queues = [Collections.Generic.List[IntPtr]]::new()
            Allocators = [Collections.Generic.List[IntPtr]]::new()
            CommandLists = [Collections.Generic.List[IntPtr]]::new()
            DescriptorHeaps = [Collections.Generic.List[IntPtr]]::new()
            RootSignatures = [Collections.Generic.List[IntPtr]]::new()
            PipelineStates = [Collections.Generic.List[IntPtr]]::new()
            Resources = [Collections.Generic.List[IntPtr]]::new()
            Fences = [Collections.Generic.List[IntPtr]]::new()
            Events = [Collections.Generic.List[IntPtr]]::new()
            ComCall = $comCall
            Allocate = $allocate
            GuidBlock = $guidBlock
            CreateEventCall = $createEvent
            CloseHandleCall = $closeHandle
            WaitCall = $waitForSingleObject
            NativeCall = $nativeCall
            SerializeRootSignatureCall = $serializeRootSignature
        }

        $instance | Add-Member ScriptMethod CreateCommandQueue ({
            $description = & $this.Allocate 16
            $iid = & $this.GuidBlock ([Guid]'0ec870a6-5d7e-4c22-8cfc-5baae07616ed')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # D3D12_COMMAND_LIST_TYPE_DIRECT, normal priority, no flags, node 0.
                # ID3D12Device::CreateCommandQueue is slot 8.
                $hr = [int32](& $this.ComCall $this.Device 8 ([int32]) @(
                    $description, $iid, $output) @([IntPtr], [IntPtr], [IntPtr]))
                $queue = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $queue -eq [IntPtr]::Zero) {
                throw ('ID3D12Device::CreateCommandQueue failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Queues.Add($queue)
            $queue
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateCommandAllocator ({
            $iid = & $this.GuidBlock ([Guid]'6102dee4-af59-4b09-b999-b44d73f09b24')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # ID3D12Device::CreateCommandAllocator is slot 9.
                $hr = [int32](& $this.ComCall $this.Device 9 ([int32]) @(
                    [uint32]0, $iid, $output) @([uint32], [IntPtr], [IntPtr]))
                $allocator = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $allocator -eq [IntPtr]::Zero) {
                throw ('ID3D12Device::CreateCommandAllocator failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Allocators.Add($allocator)
            $allocator
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateCommandList ({
            param([IntPtr] $Allocator)
            $iid = & $this.GuidBlock ([Guid]'5b160d0f-ac1b-4185-8ba8-b3ae42a5a455')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # ID3D12Device::CreateCommandList is slot 12.
                $hr = [int32](& $this.ComCall $this.Device 12 ([int32]) @(
                    [uint32]0, [uint32]0, $Allocator, [IntPtr]::Zero, $iid, $output
                ) @([uint32], [uint32], [IntPtr], [IntPtr], [IntPtr], [IntPtr]))
                $list = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $list -eq [IntPtr]::Zero) {
                throw ('ID3D12Device::CreateCommandList failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.CommandLists.Add($list)
            $list
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CloseCommandList ({
            param([IntPtr] $CommandList)
            # ID3D12GraphicsCommandList::Close is slot 9.
            $hr = [int32](& $this.ComCall $CommandList 9 ([int32]) @() @())
            if ($hr -lt 0) { throw ('ID3D12GraphicsCommandList::Close failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ResetCommandAllocator ({
            param([IntPtr] $Allocator)
            $hr = [int32](& $this.ComCall $Allocator 8 ([int32]) @() @())
            if ($hr -lt 0) { throw ('ID3D12CommandAllocator::Reset failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateRtvHeap ({
            param([uint32] $Count)
            $description = & $this.Allocate 16
            $iid = & $this.GuidBlock ([Guid]'8efb471d-616c-4f49-90f7-127bb763fa51')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # D3D12_DESCRIPTOR_HEAP_TYPE_RTV, shader-invisible, node 0.
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 0, 2)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 4, [int]$Count)
                # ID3D12Device::CreateDescriptorHeap is slot 14.
                $hr = [int32](& $this.ComCall $this.Device 14 ([int32]) @(
                    $description, $iid, $output) @([IntPtr], [IntPtr], [IntPtr]))
                $heap = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $heap -eq [IntPtr]::Zero) {
                throw ('ID3D12Device::CreateDescriptorHeap failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.DescriptorHeaps.Add($heap)
            $heap
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetRtvIncrementSize ({
            # ID3D12Device::GetDescriptorHandleIncrementSize is slot 15.
            [uint32](& $this.ComCall $this.Device 15 ([uint32]) @([uint32]2) @([uint32]))
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetCpuDescriptorHandleStart ({
            param([IntPtr] $Heap)
            # MSVC returns this native structure through a hidden first argument.
            $result = & $this.Allocate ([IntPtr]::Size)
            try {
                $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($Heap)
                $address = [Runtime.InteropServices.Marshal]::ReadIntPtr(
                    $vtable, 9 * [IntPtr]::Size)
                $call = & $this.NativeCall $address ([void]) @([IntPtr], [IntPtr])
                [void]$call.DynamicInvoke($Heap, $result)
                [Runtime.InteropServices.Marshal]::ReadIntPtr($result)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($result) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateRenderTargetView ({
            param([IntPtr] $Resource, [IntPtr] $Handle)
            # A null description selects the resource's native render-target format.
            # ID3D12Device::CreateRenderTargetView is slot 20.
            [void](& $this.ComCall $this.Device 20 ([void]) @(
                $Resource, [IntPtr]::Zero, $Handle) @([IntPtr], [IntPtr], [IntPtr]))
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateDepthTarget ({
            param([uint32] $Width, [uint32] $Height)
            $heapDescription = & $this.Allocate 16
            $heapIid = & $this.GuidBlock ([Guid]'8efb471d-616c-4f49-90f7-127bb763fa51')
            $heapOut = & $this.Allocate ([IntPtr]::Size)
            try {
                # D3D12_DESCRIPTOR_HEAP_TYPE_DSV, one shader-invisible descriptor.
                [Runtime.InteropServices.Marshal]::WriteInt32($heapDescription, 0, 3)
                [Runtime.InteropServices.Marshal]::WriteInt32($heapDescription, 4, 1)
                $hr = [int32](& $this.ComCall $this.Device 14 ([int32]) @(
                    $heapDescription, $heapIid, $heapOut) @([IntPtr], [IntPtr], [IntPtr]))
                $heap = [Runtime.InteropServices.Marshal]::ReadIntPtr($heapOut)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($heapDescription)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($heapIid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($heapOut)
            }
            if ($hr -lt 0 -or $heap -eq [IntPtr]::Zero) { throw "Create DSV heap failed: $hr" }
            $this.DescriptorHeaps.Add($heap)

            $properties = & $this.Allocate 32
            $description = & $this.Allocate 56
            $clearValue = & $this.Allocate 20
            $iid = & $this.GuidBlock ([Guid]'696442be-a72e-4059-bc79-5b5c98040fad')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # Default heap and a 2D D32_FLOAT texture allowing depth/stencil use.
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 0, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 12, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 16, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 0, 3)
                [Runtime.InteropServices.Marshal]::WriteInt64($description, 16, [int64]$Width)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 24, [int]$Height)
                [Runtime.InteropServices.Marshal]::WriteInt16($description, 28, 1)
                [Runtime.InteropServices.Marshal]::WriteInt16($description, 30, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 32, 40)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 36, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 44, 0)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 48, 2)
                [Runtime.InteropServices.Marshal]::WriteInt32($clearValue, 0, 40)
                [Runtime.InteropServices.Marshal]::Copy([single[]]@(1.0), 0, [IntPtr]::Add($clearValue, 4), 1)
                # ID3D12Device::CreateCommittedResource is slot 27.
                $hr = [int32](& $this.ComCall $this.Device 27 ([int32]) @(
                    $properties, [uint32]0, $description, [uint32]0x10,
                    $clearValue, $iid, $output
                ) @([IntPtr], [uint32], [IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr]))
                $resource = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($properties)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($clearValue)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $resource -eq [IntPtr]::Zero) { throw "Create depth resource failed: $hr" }
            $this.Resources.Add($resource)
            [IntPtr]$handle = $this.GetCpuDescriptorHandleStart([IntPtr]$heap)
            # ID3D12Device::CreateDepthStencilView is slot 21.
            [void](& $this.ComCall $this.Device 21 ([void]) @(
                [IntPtr]$resource, [IntPtr]::Zero, [IntPtr]$handle) @([IntPtr], [IntPtr], [IntPtr]))
            [PSCustomObject]@{ Resource = $resource; Heap = $heap; Handle = $handle }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateUploadBuffer ({
            param([byte[]] $Data)
            if (-not $Data -or $Data.Length -eq 0) { throw 'Buffer data cannot be empty.' }
            $properties = & $this.Allocate 32
            $description = & $this.Allocate 56
            $iid = & $this.GuidBlock ([Guid]'696442be-a72e-4059-bc79-5b5c98040fad')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # Upload heap and row-major buffer, kept in GENERIC_READ state.
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 0, 2)
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 12, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($properties, 16, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 0, 1)
                [Runtime.InteropServices.Marshal]::WriteInt64($description, 16, [int64]$Data.Length)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 24, 1)
                [Runtime.InteropServices.Marshal]::WriteInt16($description, 28, 1)
                [Runtime.InteropServices.Marshal]::WriteInt16($description, 30, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 36, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 44, 1)
                # ID3D12Device::CreateCommittedResource is slot 27.
                $hr = [int32](& $this.ComCall $this.Device 27 ([int32]) @(
                    $properties, [uint32]0, $description, [uint32]0xAC3,
                    [IntPtr]::Zero, $iid, $output
                ) @([IntPtr], [uint32], [IntPtr], [uint32], [IntPtr], [IntPtr], [IntPtr]))
                $resource = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($properties)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $resource -eq [IntPtr]::Zero) { throw "Create upload buffer failed: $hr" }
            $mappedOut = & $this.Allocate ([IntPtr]::Size)
            try {
                # ID3D12Resource::Map and Unmap are slots 8 and 9.
                $hr = [int32](& $this.ComCall $resource 8 ([int32]) @(
                    [uint32]0, [IntPtr]::Zero, $mappedOut) @([uint32], [IntPtr], [IntPtr]))
                $mapped = [Runtime.InteropServices.Marshal]::ReadIntPtr($mappedOut)
                if ($hr -lt 0 -or $mapped -eq [IntPtr]::Zero) { throw "Map upload buffer failed: $hr" }
                [Runtime.InteropServices.Marshal]::Copy($Data, 0, $mapped, $Data.Length)
                [void](& $this.ComCall $resource 9 ([void]) @(
                    [uint32]0, [IntPtr]::Zero) @([uint32], [IntPtr]))
                # ID3D12Resource::GetGPUVirtualAddress is slot 11.
                $address = [uint64](& $this.ComCall $resource 11 ([uint64]) @() @())
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($mappedOut) }
            $this.Resources.Add($resource)
            [PSCustomObject]@{ Resource = $resource; Address = $address; Size = [uint32]$Data.Length }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ResetCommandList ({
            param([IntPtr] $CommandList, [IntPtr] $Allocator)
            # ID3D12GraphicsCommandList::Reset is slot 10.
            $hr = [int32](& $this.ComCall $CommandList 10 ([int32]) @(
                $Allocator, [IntPtr]::Zero) @([IntPtr], [IntPtr]))
            if ($hr -lt 0) { throw ('ID3D12GraphicsCommandList::Reset failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Transition ({
            param([IntPtr] $CommandList, [IntPtr] $Resource, [uint32] $Before, [uint32] $After)
            $barrier = & $this.Allocate 32
            try {
                # D3D12_RESOURCE_BARRIER_TYPE_TRANSITION, all subresources.
                [Runtime.InteropServices.Marshal]::WriteIntPtr($barrier, 8, $Resource)
                [Runtime.InteropServices.Marshal]::WriteInt32($barrier, 16, -1)
                [Runtime.InteropServices.Marshal]::WriteInt32($barrier, 20, [int]$Before)
                [Runtime.InteropServices.Marshal]::WriteInt32($barrier, 24, [int]$After)
                # ID3D12GraphicsCommandList::ResourceBarrier is slot 26.
                [void](& $this.ComCall $CommandList 26 ([void]) @(
                    [uint32]1, $barrier) @([uint32], [IntPtr]))
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($barrier) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ClearRenderTarget ({
            param([IntPtr] $CommandList, [IntPtr] $Handle, [single[]] $Color)
            if ($Color.Count -ne 4) { throw 'Clear color must contain four RGBA values.' }
            $values = & $this.Allocate 16
            try {
                [Runtime.InteropServices.Marshal]::Copy($Color, 0, $values, 4)
                # ID3D12GraphicsCommandList::ClearRenderTargetView is slot 48.
                [void](& $this.ComCall $CommandList 48 ([void]) @(
                    $Handle, $values, [uint32]0, [IntPtr]::Zero
                ) @([IntPtr], [IntPtr], [uint32], [IntPtr]))
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($values) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ExecuteCommandLists ({
            param([IntPtr] $Queue, [IntPtr[]] $CommandLists)
            $pointers = & $this.Allocate ($CommandLists.Count * [IntPtr]::Size)
            try {
                for ($index = 0; $index -lt $CommandLists.Count; $index++) {
                    [Runtime.InteropServices.Marshal]::WriteIntPtr(
                        $pointers, $index * [IntPtr]::Size, $CommandLists[$index])
                }
                # ID3D12CommandQueue::ExecuteCommandLists is slot 10.
                [void](& $this.ComCall $Queue 10 ([void]) @(
                    [uint32]$CommandLists.Count, $pointers) @([uint32], [IntPtr]))
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($pointers) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateGraphicsPipeline ({
            param([byte[]] $VertexShader, [byte[]] $PixelShader, [int32] $RenderTargetFormat = 87, [bool] $DepthEnabled = $false, [object[]] $InputLayout = @(), [uint32] $RootConstantCount = 0)
            $rootDescription = & $this.Allocate 40
            $rootParameter = if ($RootConstantCount) { & $this.Allocate 32 } else { [IntPtr]::Zero }
            $blobOut = & $this.Allocate ([IntPtr]::Size)
            $errorOut = & $this.Allocate ([IntPtr]::Size)
            $rootBlob = [IntPtr]::Zero
            $errorBlob = [IntPtr]::Zero
            try {
                if ($RootConstantCount) {
                    # One vertex-visible root-constant parameter at b0.
                    [Runtime.InteropServices.Marshal]::WriteInt32($rootParameter,0,1)
                    [Runtime.InteropServices.Marshal]::WriteInt32($rootParameter,16,[int]$RootConstantCount)
                    [Runtime.InteropServices.Marshal]::WriteInt32($rootParameter,24,1)
                    [Runtime.InteropServices.Marshal]::WriteInt32($rootDescription,0,1)
                    [Runtime.InteropServices.Marshal]::WriteIntPtr($rootDescription,8,$rootParameter)
                }
                # Input-assembler access is permitted.
                [Runtime.InteropServices.Marshal]::WriteInt32($rootDescription, 32, 1)
                $hr = [int32]$this.SerializeRootSignatureCall.DynamicInvoke(
                    $rootDescription, [int32]1, $blobOut, $errorOut)
                $rootBlob = [Runtime.InteropServices.Marshal]::ReadIntPtr($blobOut)
                $errorBlob = [Runtime.InteropServices.Marshal]::ReadIntPtr($errorOut)
                if ($hr -lt 0 -or $rootBlob -eq [IntPtr]::Zero) {
                    throw ('D3D12SerializeRootSignature failed: 0x{0:X8}' -f [uint32]$hr)
                }
                $rootBytes = & $this.ComCall $rootBlob 3 ([IntPtr]) @() @()
                $rootLength = [UIntPtr](& $this.ComCall $rootBlob 4 ([UIntPtr]) @() @())
                $iidRoot = & $this.GuidBlock ([Guid]'c54a6b66-72df-4ee8-8be5-a946a1429214')
                $rootOut = & $this.Allocate ([IntPtr]::Size)
                try {
                    $hr = [int32](& $this.ComCall $this.Device 16 ([int32]) @(
                        [uint32]0, $rootBytes, $rootLength, $iidRoot, $rootOut
                    ) @([uint32], [IntPtr], [UIntPtr], [IntPtr], [IntPtr]))
                    $root = [Runtime.InteropServices.Marshal]::ReadIntPtr($rootOut)
                }
                finally {
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($iidRoot)
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($rootOut)
                }
                if ($hr -lt 0 -or $root -eq [IntPtr]::Zero) {
                    throw ('ID3D12Device::CreateRootSignature failed: 0x{0:X8}' -f [uint32]$hr)
                }
                $this.RootSignatures.Add($root)

                $vertexBytes = & $this.Allocate $VertexShader.Length
                $pixelBytes = & $this.Allocate $PixelShader.Length
                $description = & $this.Allocate 656
                $elements = if ($InputLayout.Count) { & $this.Allocate ($InputLayout.Count * 32) } else { [IntPtr]::Zero }
                $semantics = [Collections.Generic.List[IntPtr]]::new()
                $iidPipeline = & $this.GuidBlock ([Guid]'765a30f3-f624-4c6f-a828-ace948622445')
                $pipelineOut = & $this.Allocate ([IntPtr]::Size)
                try {
                    [Runtime.InteropServices.Marshal]::Copy($VertexShader, 0, $vertexBytes, $VertexShader.Length)
                    [Runtime.InteropServices.Marshal]::Copy($PixelShader, 0, $pixelBytes, $PixelShader.Length)
                    [Runtime.InteropServices.Marshal]::WriteIntPtr($description, 0, $root)
                    [Runtime.InteropServices.Marshal]::WriteIntPtr($description, 8, $vertexBytes)
                    [Runtime.InteropServices.Marshal]::WriteInt64($description, 16, $VertexShader.Length)
                    [Runtime.InteropServices.Marshal]::WriteIntPtr($description, 24, $pixelBytes)
                    [Runtime.InteropServices.Marshal]::WriteInt64($description, 32, $PixelShader.Length)
                    for ($elementIndex = 0; $elementIndex -lt $InputLayout.Count; $elementIndex++) {
                        $element = $InputLayout[$elementIndex]
                        $semantic = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi([string]$element.Semantic)
                        $semantics.Add($semantic)
                        $offset = $elementIndex * 32
                        [Runtime.InteropServices.Marshal]::WriteIntPtr($elements, $offset, $semantic)
                        [Runtime.InteropServices.Marshal]::WriteInt32($elements, $offset + 8, [int]$element.SemanticIndex)
                        [Runtime.InteropServices.Marshal]::WriteInt32($elements, $offset + 12, [int]$element.Format)
                        [Runtime.InteropServices.Marshal]::WriteInt32($elements, $offset + 16, [int]$element.Slot)
                        [Runtime.InteropServices.Marshal]::WriteInt32($elements, $offset + 20, [int]$element.Offset)
                    }
                    if ($InputLayout.Count) {
                        [Runtime.InteropServices.Marshal]::WriteIntPtr($description, 552, $elements)
                        [Runtime.InteropServices.Marshal]::WriteInt32($description, 560, $InputLayout.Count)
                    }
                    # Default blend write mask, solid fill, back-face culling.
                    [Runtime.InteropServices.Marshal]::WriteByte($description, 164, 15)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 448, -1)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 452, 3)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 456, 3)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 476, 1)
                    if ($DepthEnabled) {
                        [Runtime.InteropServices.Marshal]::WriteInt32($description, 496, 1)
                        [Runtime.InteropServices.Marshal]::WriteInt32($description, 500, 1)
                        [Runtime.InteropServices.Marshal]::WriteInt32($description, 504, 2)
                        [Runtime.InteropServices.Marshal]::WriteInt32($description, 612, 40)
                    }
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 572, 3)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 576, 1)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 580, $RenderTargetFormat)
                    [Runtime.InteropServices.Marshal]::WriteInt32($description, 616, 1)
                    $hr = [int32](& $this.ComCall $this.Device 10 ([int32]) @(
                        $description, $iidPipeline, $pipelineOut
                    ) @([IntPtr], [IntPtr], [IntPtr]))
                    $pipeline = [Runtime.InteropServices.Marshal]::ReadIntPtr($pipelineOut)
                }
                finally {
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($vertexBytes)
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($pixelBytes)
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                    if ($elements -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($elements) }
                    foreach ($semantic in $semantics) { [Runtime.InteropServices.Marshal]::FreeHGlobal($semantic) }
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($iidPipeline)
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($pipelineOut)
                }
                if ($hr -lt 0 -or $pipeline -eq [IntPtr]::Zero) {
                    throw ('ID3D12Device::CreateGraphicsPipelineState failed: {0}' -f $hr)
                }
                $this.PipelineStates.Add($pipeline)
                [PSCustomObject]@{ RootSignature = $root; PipelineState = $pipeline }
            }
            finally {
                if ($errorBlob -ne [IntPtr]::Zero) { [void](& $this.ComCall $errorBlob 2 ([uint32]) @() @()) }
                if ($rootBlob -ne [IntPtr]::Zero) { [void](& $this.ComCall $rootBlob 2 ([uint32]) @() @()) }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($rootDescription)
                if ($rootParameter -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($rootParameter) }
                [Runtime.InteropServices.Marshal]::FreeHGlobal($blobOut)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($errorOut)
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod DrawIndexed ({
            param([IntPtr] $CommandList, $Pipeline, [IntPtr] $RenderTarget, [uint32] $Width, [uint32] $Height,
                $VertexBuffer, [uint32] $VertexStride, $IndexBuffer, [uint32] $IndexCount,
                [IntPtr] $DepthStencil = [IntPtr]::Zero, [uint32] $IndexFormat = 57, [single[]] $RootConstants = @())
            $viewport = & $this.Allocate 24
            $scissor = & $this.Allocate 16
            $target = & $this.Allocate ([IntPtr]::Size)
            $depth = & $this.Allocate ([IntPtr]::Size)
            $vertexView = & $this.Allocate 16
            $indexView = & $this.Allocate 16
            try {
                [Runtime.InteropServices.Marshal]::Copy([single[]]@(0,0,[single]$Width,[single]$Height,0,1),0,$viewport,6)
                [Runtime.InteropServices.Marshal]::WriteInt32($scissor,8,[int]$Width)
                [Runtime.InteropServices.Marshal]::WriteInt32($scissor,12,[int]$Height)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($target,$RenderTarget)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($depth,$DepthStencil)
                $vertexAddressBits = [BitConverter]::ToInt64(
                    [BitConverter]::GetBytes([uint64]$VertexBuffer.Address), 0)
                [Runtime.InteropServices.Marshal]::WriteInt64($vertexView,0,$vertexAddressBits)
                [Runtime.InteropServices.Marshal]::WriteInt32($vertexView,8,[int]$VertexBuffer.Size)
                [Runtime.InteropServices.Marshal]::WriteInt32($vertexView,12,[int]$VertexStride)
                $indexAddressBits = [BitConverter]::ToInt64(
                    [BitConverter]::GetBytes([uint64]$IndexBuffer.Address), 0)
                [Runtime.InteropServices.Marshal]::WriteInt64($indexView,0,$indexAddressBits)
                [Runtime.InteropServices.Marshal]::WriteInt32($indexView,8,[int]$IndexBuffer.Size)
                [Runtime.InteropServices.Marshal]::WriteInt32($indexView,12,[int]$IndexFormat)
                [void](& $this.ComCall $CommandList 25 ([void]) @($Pipeline.PipelineState) @([IntPtr]))
                [void](& $this.ComCall $CommandList 30 ([void]) @($Pipeline.RootSignature) @([IntPtr]))
                if ($RootConstants.Count) {
                    $constantBytes = & $this.Allocate ($RootConstants.Count * 4)
                    try {
                        [Runtime.InteropServices.Marshal]::Copy($RootConstants,0,$constantBytes,$RootConstants.Count)
                        # ID3D12GraphicsCommandList::SetGraphicsRoot32BitConstants is slot 36.
                        [void](& $this.ComCall $CommandList 36 ([void]) @(
                            [uint32]0,[uint32]$RootConstants.Count,$constantBytes,[uint32]0
                        ) @([uint32],[uint32],[IntPtr],[uint32]))
                    }
                    finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($constantBytes) }
                }
                [void](& $this.ComCall $CommandList 21 ([void]) @([uint32]1,$viewport) @([uint32],[IntPtr]))
                [void](& $this.ComCall $CommandList 22 ([void]) @([uint32]1,$scissor) @([uint32],[IntPtr]))
                $depthPointer = if ($DepthStencil -eq [IntPtr]::Zero) { [IntPtr]::Zero } else { $depth }
                [void](& $this.ComCall $CommandList 46 ([void]) @([uint32]1,$target,$true,$depthPointer) @([uint32],[IntPtr],[bool],[IntPtr]))
                [void](& $this.ComCall $CommandList 20 ([void]) @([uint32]4) @([uint32]))
                # IASetIndexBuffer, IASetVertexBuffers, then DrawIndexedInstanced.
                [void](& $this.ComCall $CommandList 43 ([void]) @($indexView) @([IntPtr]))
                [void](& $this.ComCall $CommandList 44 ([void]) @([uint32]0,[uint32]1,$vertexView) @([uint32],[uint32],[IntPtr]))
                [void](& $this.ComCall $CommandList 13 ([void]) @($IndexCount,[uint32]1,[uint32]0,[int32]0,[uint32]0) @([uint32],[uint32],[uint32],[int32],[uint32]))
            }
            finally {
                foreach ($pointer in @($viewport,$scissor,$target,$depth,$vertexView,$indexView)) {
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($pointer)
                }
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Draw ({
            param([IntPtr] $CommandList, $Pipeline, [IntPtr] $RenderTarget, [uint32] $Width, [uint32] $Height, [uint32] $VertexCount, [IntPtr] $DepthStencil = [IntPtr]::Zero)
            $viewport = & $this.Allocate 24
            $scissor = & $this.Allocate 16
            $target = & $this.Allocate ([IntPtr]::Size)
            $depth = & $this.Allocate ([IntPtr]::Size)
            try {
                [Runtime.InteropServices.Marshal]::Copy(
                    [single[]]@(0, 0, [single]$Width, [single]$Height, 0, 1), 0, $viewport, 6)
                [Runtime.InteropServices.Marshal]::WriteInt32($scissor, 8, [int]$Width)
                [Runtime.InteropServices.Marshal]::WriteInt32($scissor, 12, [int]$Height)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($target, $RenderTarget)
                [Runtime.InteropServices.Marshal]::WriteIntPtr($depth, $DepthStencil)
                [void](& $this.ComCall $CommandList 25 ([void]) @($Pipeline.PipelineState) @([IntPtr]))
                [void](& $this.ComCall $CommandList 30 ([void]) @($Pipeline.RootSignature) @([IntPtr]))
                [void](& $this.ComCall $CommandList 21 ([void]) @([uint32]1, $viewport) @([uint32], [IntPtr]))
                [void](& $this.ComCall $CommandList 22 ([void]) @([uint32]1, $scissor) @([uint32], [IntPtr]))
                $depthPointer = if ($DepthStencil -eq [IntPtr]::Zero) { [IntPtr]::Zero } else { $depth }
                [void](& $this.ComCall $CommandList 46 ([void]) @([uint32]1, $target, $true, $depthPointer) @([uint32], [IntPtr], [bool], [IntPtr]))
                [void](& $this.ComCall $CommandList 20 ([void]) @([uint32]4) @([uint32]))
                [void](& $this.ComCall $CommandList 12 ([void]) @($VertexCount, [uint32]1, [uint32]0, [uint32]0) @([uint32], [uint32], [uint32], [uint32]))
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($viewport)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($scissor)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($target)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($depth)
            }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod ClearDepth ({
            param([IntPtr] $CommandList, [IntPtr] $DepthStencil, [single] $Value = 1.0)
            # ID3D12GraphicsCommandList::ClearDepthStencilView is slot 47.
            [void](& $this.ComCall $CommandList 47 ([void]) @(
                $DepthStencil, [uint32]1, $Value, [byte]0, [uint32]0, [IntPtr]::Zero
            ) @([IntPtr], [uint32], [single], [byte], [uint32], [IntPtr]))
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateFence ({
            param([uint64] $InitialValue = 0)
            $iid = & $this.GuidBlock ([Guid]'0a753dcf-c4d8-4b91-adf6-be5a60d95a76')
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # ID3D12Device::CreateFence is slot 36.
                $hr = [int32](& $this.ComCall $this.Device 36 ([int32]) @(
                    $InitialValue, [uint32]0, $iid, $output
                ) @([uint64], [uint32], [IntPtr], [IntPtr]))
                $fence = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $fence -eq [IntPtr]::Zero) {
                throw ('ID3D12Device::CreateFence failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Fences.Add($fence)
            $fence
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Signal ({
            param([IntPtr] $Queue, [IntPtr] $Fence, [uint64] $Value)
            # ID3D12CommandQueue::Signal is slot 14.
            $hr = [int32](& $this.ComCall $Queue 14 ([int32]) @(
                $Fence, $Value) @([IntPtr], [uint64]))
            if ($hr -lt 0) { throw ('ID3D12CommandQueue::Signal failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetCompletedValue ({
            param([IntPtr] $Fence)
            [uint64](& $this.ComCall $Fence 8 ([uint64]) @() @())
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Wait ({
            param([IntPtr] $Fence, [uint64] $Value, [uint32] $Timeout = 5000)
            if ($this.GetCompletedValue($Fence) -ge $Value) { return $true }
            $event = [IntPtr]$this.CreateEventCall.DynamicInvoke(
                [IntPtr]::Zero, $false, $false, [IntPtr]::Zero)
            if ($event -eq [IntPtr]::Zero) { throw 'CreateEventW failed for D3D12 fence.' }
            $this.Events.Add($event)
            # ID3D12Fence::SetEventOnCompletion is slot 9.
            $hr = [int32](& $this.ComCall $Fence 9 ([int32]) @(
                $Value, $event) @([uint64], [IntPtr]))
            if ($hr -lt 0) { throw ('ID3D12Fence::SetEventOnCompletion failed: 0x{0:X8}' -f [uint32]$hr) }
            $waitResult = [uint32]$this.WaitCall.DynamicInvoke($event, $Timeout)
            if ($waitResult -ne 0) { throw "D3D12 fence wait failed or timed out: $waitResult" }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            foreach ($event in $this.Events) { [void]$this.CloseHandleCall.DynamicInvoke($event) }
            $this.Events.Clear()
            foreach ($collection in @(
                $this.CommandLists, $this.Allocators, $this.DescriptorHeaps,
                $this.PipelineStates, $this.RootSignatures,
                $this.Resources,
                $this.Fences, $this.Queues)) {
                for ($index = $collection.Count - 1; $index -ge 0; $index--) {
                    [void](& $this.ComCall $collection[$index] 2 ([uint32]) @() @())
                }
                $collection.Clear()
            }
            if ($this.Device -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Device 2 ([uint32]) @() @())
                $this.Device = [IntPtr]::Zero
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $D3D12

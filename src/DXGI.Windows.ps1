[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'DXGI.Windows.ps1 must be invoked with &, not dot-sourced.'
}

$Dxgi = & {
    $assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        [Reflection.AssemblyName]::new('QuickPS.DXGI.' + [Guid]::NewGuid().ToString('N')),
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

    $dxgi = [Runtime.InteropServices.NativeLibrary]::Load('dxgi.dll')
    $createFactory = & $nativeCall (
        [Runtime.InteropServices.NativeLibrary]::GetExport($dxgi, 'CreateDXGIFactory2')
    ) ([int32]) @([uint32], [IntPtr], [IntPtr])

    {
        $iid = & $allocate 16
        $output = & $allocate ([IntPtr]::Size)
        try {
            [Runtime.InteropServices.Marshal]::Copy(
                ([Guid]'50c83a1c-e072-4c48-87b0-3630fa36a6d0').ToByteArray(), 0, $iid, 16)
            $hr = [int32]$createFactory.DynamicInvoke([uint32]0, $iid, $output)
            $factory = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
        }
        if ($hr -lt 0 -or $factory -eq [IntPtr]::Zero) {
            throw ('CreateDXGIFactory2 failed: 0x{0:X8}' -f [uint32]$hr)
        }

        $instance = [PSCustomObject]@{
            PSTypeName = 'QuickPS.DXGI.Windows'
            Factory = $factory
            Adapters = [Collections.Generic.List[IntPtr]]::new()
            SwapChains = [Collections.Generic.List[IntPtr]]::new()
            Buffers = [Collections.Generic.List[IntPtr]]::new()
            ComCall = $comCall
            Allocate = $allocate
        }

        $instance | Add-Member ScriptMethod GetAdapter ({
            param([uint32] $Index = 0)
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                # IDXGIFactory1::EnumAdapters1 is slot 12.
                $hr = [int32](& $this.ComCall $this.Factory 12 ([int32]) @(
                    $Index, $output) @([uint32], [IntPtr]))
                $adapter = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
            if ([uint32]([int64]$hr -band 0xFFFFFFFFL) -eq [uint32]2289696770) { return $null }
            if ($hr -lt 0 -or $adapter -eq [IntPtr]::Zero) {
                throw ('IDXGIFactory1::EnumAdapters1 failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Adapters.Add($adapter)
            $adapter
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetAdapterDescription ({
            param([IntPtr] $Adapter)
            $description = & $this.Allocate 312
            try {
                # IDXGIAdapter1::GetDesc1 is slot 10.
                $hr = [int32](& $this.ComCall $Adapter 10 ([int32]) @($description) @([IntPtr]))
                if ($hr -lt 0) { throw ('IDXGIAdapter1::GetDesc1 failed: 0x{0:X8}' -f [uint32]$hr) }
                $name = [Runtime.InteropServices.Marshal]::PtrToStringUni($description, 128).TrimEnd([char]0)
                [PSCustomObject]@{
                    Description = $name
                    VendorId = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($description, 256)
                    DeviceId = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($description, 260)
                    SubSystemId = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($description, 264)
                    Revision = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($description, 268)
                    DedicatedVideoMemory = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($description, 272)
                    DedicatedSystemMemory = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($description, 280)
                    SharedSystemMemory = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($description, 288)
                    AdapterLuid = [uint64][Runtime.InteropServices.Marshal]::ReadInt64($description, 296)
                    Flags = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($description, 304)
                }
            }
            finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($description) }
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod CreateSwapChainForWindow ({
            param(
                [IntPtr] $CommandQueue,
                [IntPtr] $Window,
                [uint32] $Width,
                [uint32] $Height,
                [uint32] $BufferCount = 2
            )
            if ($CommandQueue -eq [IntPtr]::Zero -or $Window -eq [IntPtr]::Zero) {
                throw 'A live command queue and HWND are required.'
            }
            # DXGI_SWAP_CHAIN_DESC1 is 48 bytes on x64.
            $description = & $this.Allocate 48
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 0, [int32]$Width)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 4, [int32]$Height)
                # DXGI_FORMAT_B8G8R8A8_UNORM, stereo false, sample count 1.
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 8, 87)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 12, 0)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 16, 1)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 20, 0)
                # DXGI_USAGE_RENDER_TARGET_OUTPUT, buffer count, scaling stretch, flip discard.
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 24, 0x20)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 28, [int32]$BufferCount)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 32, 0)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 36, 4)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 40, 0)
                [Runtime.InteropServices.Marshal]::WriteInt32($description, 44, 0)
                # IDXGIFactory2::CreateSwapChainForHwnd is slot 15.
                $hr = [int32](& $this.ComCall $this.Factory 15 ([int32]) @(
                    $CommandQueue, $Window, $description, [IntPtr]::Zero,
                    [IntPtr]::Zero, $output
                ) @([IntPtr], [IntPtr], [IntPtr], [IntPtr], [IntPtr], [IntPtr]))
                $swapChain = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($description)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $swapChain -eq [IntPtr]::Zero) {
                throw ('IDXGIFactory2::CreateSwapChainForHwnd failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.SwapChains.Add($swapChain)
            $swapChain
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetBuffer ({
            param([IntPtr] $SwapChain, [uint32] $Index)
            $iid = & $this.Allocate 16
            $output = & $this.Allocate ([IntPtr]::Size)
            try {
                [Runtime.InteropServices.Marshal]::Copy(
                    ([Guid]'696442be-a72e-4059-bc79-5b5c98040fad').ToByteArray(), 0, $iid, 16)
                # IDXGISwapChain::GetBuffer is slot 9.
                $hr = [int32](& $this.ComCall $SwapChain 9 ([int32]) @(
                    $Index, $iid, $output) @([uint32], [IntPtr], [IntPtr]))
                $buffer = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
            }
            finally {
                [Runtime.InteropServices.Marshal]::FreeHGlobal($iid)
                [Runtime.InteropServices.Marshal]::FreeHGlobal($output)
            }
            if ($hr -lt 0 -or $buffer -eq [IntPtr]::Zero) {
                throw ('IDXGISwapChain::GetBuffer failed: 0x{0:X8}' -f [uint32]$hr)
            }
            $this.Buffers.Add($buffer)
            $buffer
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod GetCurrentBackBufferIndex ({
            param([IntPtr] $SwapChain)
            # IDXGISwapChain3::GetCurrentBackBufferIndex is slot 36.
            [uint32](& $this.ComCall $SwapChain 36 ([uint32]) @() @())
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Present ({
            param([IntPtr] $SwapChain, [uint32] $SyncInterval = 1, [uint32] $Flags = 0)
            # IDXGISwapChain::Present is slot 8.
            $hr = [int32](& $this.ComCall $SwapChain 8 ([int32]) @(
                $SyncInterval, $Flags) @([uint32], [uint32]))
            if ($hr -lt 0) { throw ('IDXGISwapChain::Present failed: 0x{0:X8}' -f [uint32]$hr) }
            $true
        }.GetNewClosure())

        $instance | Add-Member ScriptMethod Dispose ({
            for ($index = $this.Buffers.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Buffers[$index] 2 ([uint32]) @() @())
            }
            for ($index = $this.SwapChains.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.SwapChains[$index] 2 ([uint32]) @() @())
            }
            for ($index = $this.Adapters.Count - 1; $index -ge 0; $index--) {
                [void](& $this.ComCall $this.Adapters[$index] 2 ([uint32]) @() @())
            }
            $this.SwapChains.Clear()
            $this.Buffers.Clear()
            $this.Adapters.Clear()
            if ($this.Factory -ne [IntPtr]::Zero) {
                [void](& $this.ComCall $this.Factory 2 ([uint32]) @() @())
                $this.Factory = [IntPtr]::Zero
            }
        }.GetNewClosure())

        $instance
    }.GetNewClosure()
}

& $Dxgi

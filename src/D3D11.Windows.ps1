[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    throw 'D3D11.Windows.ps1 must be invoked with &, not dot-sourced.'
}
if (-not $IsWindows -or [IntPtr]::Size -ne 8) {
    throw 'D3D11.Windows.ps1 requires Windows x64.'
}

# ABI: Windows SDK 10.0.26100.0 d3d11.h and dxgi.h; x64 StdCall.
# The returned COM references and the loaded system DLL belong to this instance.
$assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('QuickPS.D3D11.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run)
$module = $assembly.DefineDynamicModule('Native')
$types = [Collections.Generic.Dictionary[string,Type]]::new()
$calls = [Collections.Generic.Dictionary[string,Delegate]]::new()
$bind = ({
    param([IntPtr]$Address, [Type]$ReturnType, [Type[]]$Parameters)
    $signature = $ReturnType.FullName + ':' + (($Parameters | ForEach-Object FullName) -join ',')
    if (-not $types.ContainsKey($signature)) {
        $builder = $module.DefineType('Call_' + [Guid]::NewGuid().ToString('N'),
            'Class,Public,Sealed', [MulticastDelegate])
        $constructor = $builder.DefineConstructor('Public,HideBySig,RTSpecialName',
            [Reflection.CallingConventions]::Standard, @([object],[IntPtr]))
        $constructor.SetImplementationFlags('Runtime,Managed')
        $invoke = $builder.DefineMethod('Invoke','Public,HideBySig,NewSlot,Virtual',
            $ReturnType,$Parameters)
        $invoke.SetImplementationFlags('Runtime,Managed')
        $attribute = [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
            @([Runtime.InteropServices.CallingConvention]))
        $builder.SetCustomAttribute([Reflection.Emit.CustomAttributeBuilder]::new(
            $attribute,@([Runtime.InteropServices.CallingConvention]::StdCall)))
        $types[$signature] = $builder.CreateType()
    }
    $key = $Address.ToInt64().ToString() + ':' + $signature
    if (-not $calls.ContainsKey($key)) {
        $calls[$key] = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
            $Address,$types[$signature])
    }
    $calls[$key]
}).GetNewClosure()

$library = [IntPtr]::Zero
$device = [IntPtr]::Zero
$dxgiDevice = [IntPtr]::Zero
$output = [IntPtr]::Zero
$iid = [IntPtr]::Zero
try {
    $library = [Runtime.InteropServices.NativeLibrary]::Load('d3d11.dll')
    $create = & $bind ([Runtime.InteropServices.NativeLibrary]::GetExport(
        $library,'D3D11CreateDevice')) ([int32]) @(
        [IntPtr],[int32],[IntPtr],[uint32],[IntPtr],[uint32],[uint32],
        [IntPtr],[IntPtr],[IntPtr])
    $output = [Runtime.InteropServices.Marshal]::AllocHGlobal([IntPtr]::Size)
    foreach ($driver in @(1,5)) { # hardware, then WARP
        [Runtime.InteropServices.Marshal]::WriteIntPtr($output,[IntPtr]::Zero)
        $hr = [int32]$create.DynamicInvoke(
            [IntPtr]::Zero,[int32]$driver,[IntPtr]::Zero,[uint32]0x20,
            [IntPtr]::Zero,[uint32]0,[uint32]7,$output,[IntPtr]::Zero,[IntPtr]::Zero)
        $device = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
        if ($hr -ge 0 -and $device -ne [IntPtr]::Zero) { break }
    }
    if ($device -eq [IntPtr]::Zero) {
        throw ('D3D11CreateDevice failed: 0x{0:X8}' -f [uint32]$hr)
    }

    $iid = [Runtime.InteropServices.Marshal]::AllocHGlobal(16)
    [Runtime.InteropServices.Marshal]::Copy(
        ([Guid]'54ec77fa-1377-44e6-8c32-88fd5f44c84c').ToByteArray(),0,$iid,16)
    [Runtime.InteropServices.Marshal]::WriteIntPtr($output,[IntPtr]::Zero)
    $vtable = [Runtime.InteropServices.Marshal]::ReadIntPtr($device)
    $query = & $bind ([Runtime.InteropServices.Marshal]::ReadIntPtr($vtable)) `
        ([int32]) @([IntPtr],[IntPtr],[IntPtr])
    $hr = [int32]$query.DynamicInvoke($device,$iid,$output)
    $dxgiDevice = [Runtime.InteropServices.Marshal]::ReadIntPtr($output)
    if ($hr -lt 0 -or $dxgiDevice -eq [IntPtr]::Zero) {
        throw ('QueryInterface(IDXGIDevice) failed: 0x{0:X8}' -f [uint32]$hr)
    }

    $instance = [PSCustomObject]@{
        PSTypeName = 'QuickPS.D3D11.Windows'
        Device = $device
        DxgiDevice = $dxgiDevice
        Driver = if ($driver -eq 1) { 'Hardware' } else { 'WARP' }
        Library = $library
        Bind = $bind
    }
    $instance | Add-Member ScriptMethod Dispose ({
        foreach ($name in @('DxgiDevice','Device')) {
            $pointer = [IntPtr]$this.$name
            if ($pointer -ne [IntPtr]::Zero) {
                $table = [Runtime.InteropServices.Marshal]::ReadIntPtr($pointer)
                $release = & $this.Bind ([Runtime.InteropServices.Marshal]::ReadIntPtr(
                    $table,2*[IntPtr]::Size)) ([uint32]) @([IntPtr])
                [void]$release.DynamicInvoke($pointer)
                $this.$name = [IntPtr]::Zero
            }
        }
        if ($this.Library -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.NativeLibrary]::Free($this.Library)
            $this.Library = [IntPtr]::Zero
        }
    }.GetNewClosure())
    $device = [IntPtr]::Zero
    $dxgiDevice = [IntPtr]::Zero
    $library = [IntPtr]::Zero
    $instance
} finally {
    if ($iid -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($iid) }
    if ($output -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeHGlobal($output) }
    foreach ($pointer in @($dxgiDevice,$device)) {
        if ($pointer -ne [IntPtr]::Zero) {
            $table = [Runtime.InteropServices.Marshal]::ReadIntPtr($pointer)
            $release = & $bind ([Runtime.InteropServices.Marshal]::ReadIntPtr(
                $table,2*[IntPtr]::Size)) ([uint32]) @([IntPtr])
            [void]$release.DynamicInvoke($pointer)
        }
    }
    if ($library -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.NativeLibrary]::Free($library)
    }
}

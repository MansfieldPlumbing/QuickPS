[CmdletBinding()]
param(
    [Parameter(Mandatory)] $Native,
    [Parameter(Mandatory)] $MediaFoundation
)
if ($MyInvocation.InvocationName -eq '.') {
    throw 'CaptureDevice.Windows.ps1 must be invoked with &, not dot-sourced.'
}
if ([IntPtr]::Size -ne 8) { throw 'These bindings require a 64-bit process.' }

# Enumeration owns IMFActivate references; sessions take a separate AddRef.
# No capture client starts during enumeration. The caller owns both dependencies.
$n = $Native
$mf = $MediaFoundation
$check = { param([int] $Result, [string] $Operation)
    if ($Result -lt 0) { throw ('{0}: 0x{1:X8}' -f $Operation, $Result) }
}
$guid = { param([Guid] $Value)
    $p = $n.Allocate(16)
    [Runtime.InteropServices.Marshal]::Copy($Value.ToByteArray(), 0, $p, 16)
    $p
}.GetNewClosure()
$freeTask = $n.GetExportCall('ole32.dll', 'CoTaskMemFree', [void], @([IntPtr]))
$locate = $n.GetExportCall('cfgmgr32.dll', 'CM_Locate_DevNodeW', [uint32], @([IntPtr], [IntPtr], [uint32]))
$property = $n.GetExportCall('cfgmgr32.dll', 'CM_Get_DevNode_PropertyW', [uint32], @([uint32], [IntPtr], [IntPtr], [IntPtr], [IntPtr], [uint32]))
$instance = [PSCustomObject]@{ PSTypeName = 'QuickPS.CaptureDevice'; Devices = @() }
$instance | Add-Member ScriptMethod GetText ({
    param([IntPtr] $Object, [Guid] $Key)
    $keyBlock = & $guid $Key
    $scratch = $n.Allocate(16)
    try {
        $hr = $n.InvokeCom($Object, 13, [int], @([IntPtr], [IntPtr], [IntPtr]), @($keyBlock, $scratch, [IntPtr]::Add($scratch, 8)))
        if ($hr -lt 0) { return '' }
        $text = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
        try { [Runtime.InteropServices.Marshal]::PtrToStringUni($text) }
        finally { $freeTask.Invoke($text) }
    } finally { $n.Free($scratch); $n.Free($keyBlock) }
}.GetNewClosure())
$instance | Add-Member ScriptMethod GetContainerId ({
    param([string] $InstanceId)
    # DEVPROPKEY: GUID at 0, DWORD pid at 16. ContainerId is a DEVPROP_TYPE_GUID.
    $id = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($InstanceId)
    $scratch = $n.Allocate(48)
    $key = $n.Allocate(20)
    try {
        [Runtime.InteropServices.Marshal]::Copy(([Guid]'8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c').ToByteArray(), 0, $key, 16)
        [Runtime.InteropServices.Marshal]::WriteInt32($key, 16, 2)
        if ($locate.Invoke($scratch, $id, [uint32]0) -ne 0) { return [Guid]::Empty }
        $node = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($scratch)
        [Runtime.InteropServices.Marshal]::WriteInt32($scratch, 8, 16)
        $hr = $property.Invoke($node, $key, [IntPtr]::Add($scratch, 4), [IntPtr]::Add($scratch, 16), [IntPtr]::Add($scratch, 8), [uint32]0)
        if ($hr -ne 0 -or [Runtime.InteropServices.Marshal]::ReadInt32($scratch, 4) -ne 13 -or [Runtime.InteropServices.Marshal]::ReadInt32($scratch, 8) -ne 16) { return [Guid]::Empty }
        $bytes = [byte[]]::new(16)
        [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($scratch, 16), $bytes, 0, 16)
        [Guid]::new($bytes)
    } finally { $n.Free($id); $n.Free($scratch); $n.Free($key) }
}.GetNewClosure())
$instance | Add-Member ScriptMethod Enumerate ({
    param([ValidateSet('Video', 'Audio')][string] $Kind = 'Video')
    $category = if ($Kind -eq 'Video') { [Guid]'8ac3587a-4ae7-42d8-99e0-0a6013eef90f' } else { [Guid]'14dd9a1c-7cff-41be-b1b9-ba1ac6ecb571' }
    $linkKey = if ($Kind -eq 'Video') { [Guid]'58f0aad8-22bf-4f8a-bb3d-d2c4978c6e2f' } else { [Guid]'30da9258-feb9-47a7-a453-763a7a8e1c5f' }
    $attrs = $mf.CreateAttributes(1)
    $scratch = $n.Allocate(16)
    $array = [IntPtr]::Zero
    $result = [Collections.Generic.List[object]]::new()
    try {
        $mf.SetGuid($attrs, [Guid]'c60ac5fe-252a-478f-a0ef-bc8fa5f7cad3', $category)
        & $check ([int]$mf.EnumDeviceSourcesCall.DynamicInvoke($attrs, $scratch, [IntPtr]::Add($scratch, 8))) 'Enumerate capture devices'
        $array = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
        $count = [Runtime.InteropServices.Marshal]::ReadInt32($scratch, 8)
        for ($i = 0; $i -lt $count; $i++) {
            $activate = [Runtime.InteropServices.Marshal]::ReadIntPtr($array, 8 * $i)
            # Track before reading properties so failed discovery still releases the reference.
            $device = [PSCustomObject]@{ Activate = $activate; Kind = $Kind; Name = ''; Link = ''; ContainerId = [Guid]::Empty }
            $result.Add($device)
            $device.Name = $this.GetText($activate, [Guid]'60d0e559-52f8-4fa2-bbce-acdb34a8ec01')
            $device.Link = $this.GetText($activate, $linkKey)
            $id = if ($Kind -eq 'Video') { ($device.Link -replace '^\\\\\?\\', '' -replace '#\{.*$', '').Replace('#', '\') } else { 'SWD\MMDEVAPI\' + $device.Link }
            $device.ContainerId = $this.GetContainerId($id)
        }
        foreach ($item in $result) { $this.Devices += $item }
        $result.ToArray()
    } catch { foreach ($item in $result) { [void]$n.ReleaseCom($item.Activate) }; throw }
    finally { if ($array -ne [IntPtr]::Zero) { $freeTask.Invoke($array) }; [void]$n.ReleaseCom($attrs); $n.Free($scratch) }
}.GetNewClosure())
$instance | Add-Member ScriptMethod MatchAudio ({
    param($Camera, [object[]] $AudioDevices)
    if ($Camera.ContainerId -eq [Guid]::Empty) { return $null }
    $AudioDevices | Where-Object { $_.ContainerId -eq $Camera.ContainerId } | Select-Object -First 1
}.GetNewClosure())
$instance | Add-Member ScriptMethod ReleaseDevices ({
    param([object[]] $Devices)
    foreach ($item in $Devices) {
        if ($item.Activate -ne [IntPtr]::Zero) { [void]$n.ReleaseCom($item.Activate); $item.Activate = [IntPtr]::Zero }
    }
    $this.Devices = @($this.Devices | Where-Object { $_.Activate -ne [IntPtr]::Zero })
}.GetNewClosure())
$instance | Add-Member ScriptMethod Dispose ({ $this.ReleaseDevices(@($this.Devices)) }.GetNewClosure())
$instance

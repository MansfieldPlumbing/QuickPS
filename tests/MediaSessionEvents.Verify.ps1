[CmdletBinding()]
param([string]$AssemblyPath = (Join-Path $PSScriptRoot '..\build\managed\QuickPS.MediaSessionEvents.dll'))
$ErrorActionPreference = 'Stop'
# Drives the compiled event worker from an IMFMediaEventQueue, which shares
# IMFMediaEventGenerator's leading slots (mfobjects.h, SDK 10.0.26100.0), so no
# capture device or media session is needed. Messages go to a message-only window.
$src = Join-Path $PSScriptRoot '..\src'
$assembly = [Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath([IO.Path]::GetFullPath($AssemblyPath))
foreach ($reference in $assembly.GetReferencedAssemblies()) {
    if ($reference.Name -match 'Management.Automation|Microsoft.CSharp') { throw 'Managed output depends on the PowerShell engine or C# dynamic binder.' }
}
$type = $assembly.GetType('QuickPSMediaSessionEvents', $true)
$guidPointer = $type.GetMethod('GuidMemory').Invoke($null, @('8D01C530539A4B45AD9E6D5F8FA7C43B'))
try {
    $actual = [byte[]]::new(16); [Runtime.InteropServices.Marshal]::Copy($guidPointer, $actual, 0, 16)
    $expected = ([Guid]'30c5018d-9a53-454b-ad9e-6d5f8fa7c43b').ToByteArray()
    if ([Convert]::ToHexString($actual) -cne [Convert]::ToHexString($expected)) { throw 'MF_EVENT_TOPOLOGY_STATUS byte layout differs.' }
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($guidPointer) }

$n = & "$src\Native.ps1"
$media = & "$src\MediaFoundation.Windows.ps1"
$hwnd = [IntPtr]::Zero
$className = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('STATIC')
$message = $n.Allocate(48)
$scratch = $n.Allocate(32)
$propVariant = $n.Allocate(24)   # VT_EMPTY
$nullGuid = $n.Allocate(16)
$topologyKey = $n.Allocate(16)
[Runtime.InteropServices.Marshal]::Copy(([Guid]'30c5018d-9a53-454b-ad9e-6d5f8fa7c43b').ToByteArray(), 0, $topologyKey, 16)
$base = [uint32]0x8040
try {
    $create = $n.GetExportCall('user32.dll', 'CreateWindowExW', [IntPtr], @([uint32], [IntPtr], [IntPtr], [uint32], [int], [int], [int], [int], [IntPtr], [IntPtr], [IntPtr], [IntPtr]))
    $destroy = $n.GetExportCall('user32.dll', 'DestroyWindow', [bool], @([IntPtr]))
    $peek = $n.GetExportCall('user32.dll', 'PeekMessageW', [bool], @([IntPtr], [IntPtr], [uint32], [uint32], [uint32]))
    $createQueue = $n.GetExportCall('mfplat.dll', 'MFCreateEventQueue', [int], @([IntPtr]))
    $createEvent = $n.GetExportCall('mfplat.dll', 'MFCreateMediaEvent', [int], @([uint32], [IntPtr], [int], [IntPtr], [IntPtr]))
    # HWND_MESSAGE (-3): a message-only window receives posted messages, never shown.
    $hwnd = $create.Invoke([uint32]0, $className, [IntPtr]::Zero, [uint32]0, 0, 0, 0, 0, [IntPtr]::new(-3), [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
    if ($hwnd -eq [IntPtr]::Zero) { throw 'CreateWindowExW failed.' }

    function Read-Posted {
        $items = [Collections.Generic.List[string]]::new()
        while ($peek.Invoke($message, $hwnd, $base, $base + 2, [uint32]1)) {
            $items.Add(('{0}:{1}:{2}' -f ([Runtime.InteropServices.Marshal]::ReadInt32($message, 8) - $base), [Runtime.InteropServices.Marshal]::ReadInt64($message, 16), [Runtime.InteropServices.Marshal]::ReadInt64($message, 24)))
        }
        $items -join ' '
    }
    function New-Queue {
        if ($createQueue.Invoke($scratch) -lt 0) { throw 'MFCreateEventQueue failed.' }
        [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
    }

    # 1. Event order, statuses, topology detail, and stop after MESessionClosed.
    $queue = New-Queue
    try {
        if ($createEvent.Invoke([uint32]111, $nullGuid, 0, $propVariant, $scratch) -lt 0) { throw 'MFCreateMediaEvent failed.' }
        $event = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
        try {
            if ($n.InvokeCom($event, 21, [int], @([IntPtr], [uint32]), @($topologyKey, [uint32]100)) -lt 0) { throw 'SetUINT32 failed.' }
            if ($n.InvokeCom($queue, 6, [int], @([IntPtr]), @($event)) -lt 0) { throw 'QueueEvent failed.' }
        } finally { [void]$n.ReleaseCom($event) }
        foreach ($pair in @(@(103, 0), @(1, -2147467259), @(106, 0))) {
            if ($n.InvokeCom($queue, 7, [int], @([uint32], [IntPtr], [int], [IntPtr]), @([uint32]$pair[0], $nullGuid, [int]$pair[1], $propVariant)) -lt 0) { throw 'QueueEventParamVar failed.' }
        }
        $worker = & "$src\MediaSessionEvents.Windows.ps1" -AssemblyPath $AssemblyPath -Generator $queue -NotifyWindow $hwnd -Message $base
        $worker.Thread.Start()
        if (-not $worker.Thread.Join(5000)) { throw 'Worker did not stop after MESessionClosed.' }
        $posted = Read-Posted
        $expectedPosted = '0:111:0 1:100:0 0:103:0 0:1:-2147467259 0:106:0'
        if ($posted -ne $expectedPosted) { throw "Posted '$posted', expected '$expectedPosted'." }
    } finally { [void]$n.InvokeCom($queue, 9, [int], @(), @()); [void]$n.ReleaseCom($queue) }

    # 2. Shutdown while the worker blocks in GetEvent ends it without a message.
    $queue = New-Queue
    try {
        $worker = & "$src\MediaSessionEvents.Windows.ps1" -AssemblyPath $AssemblyPath -Generator $queue -NotifyWindow $hwnd -Message $base
        $worker.Thread.Start()
        if ($worker.Thread.Join(200)) { throw 'Worker returned before any event or shutdown.' }
        if ($n.InvokeCom($queue, 9, [int], @(), @()) -lt 0) { throw 'Queue shutdown failed.' }
        if (-not $worker.Thread.Join(5000)) { throw 'Worker did not stop after Shutdown.' }
        $posted = Read-Posted
        if ($posted) { throw "Shutdown posted '$posted'." }
        if ($worker.Failure -ne 0) { throw "Shutdown recorded failure $($worker.Failure)." }
    } finally { [void]$n.ReleaseCom($queue) }
    'PASS: engine-independent assembly, GUID layout, event order and status, topology detail, stop on MESessionClosed and on Shutdown. No capture device used.'
} finally {
    if ($hwnd -ne [IntPtr]::Zero) { [void]$destroy.Invoke($hwnd) }
    foreach ($p in @($message, $scratch, $propVariant, $nullGuid, $topologyKey)) { $n.Free($p) }
    [Runtime.InteropServices.Marshal]::FreeHGlobal($className)
    $media.Dispose()
    $n.Dispose()
}

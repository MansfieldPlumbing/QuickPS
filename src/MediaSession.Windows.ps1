[CmdletBinding()]
param(
    [Parameter(Mandatory)] $Native,
    [Parameter(Mandatory)] $MediaFoundation,
    [Parameter(Mandatory)] [IntPtr] $Activate,
    [Parameter(Mandatory)] [scriptblock] $StartEvents,
    [ValidateRange(0x8000, 0xBFFD)] [uint32] $NotifyMessage = 0x8000,
    [ValidateSet('Video', 'Audio')] [string] $Kind = 'Video',
    [IntPtr] $Hwnd = [IntPtr]::Zero,
    [int] $Width = 1920,
    [int] $Height = 1080,
    [double] $FrameRate = 60,
    [Guid] $PreferredSubtype = '3231564e-0000-0010-8000-00aa00389b71'
)
if ($MyInvocation.InvocationName -eq '.') { throw 'MediaSession.Windows.ps1 must be invoked with &, not dot-sourced.' }
if ([IntPtr]::Size -ne 8) { throw 'These bindings require a 64-bit process.' }
if ($Kind -eq 'Video' -and $Hwnd -eq [IntPtr]::Zero) { throw 'Video rendering requires a live HWND.' }

# One capture source played by a native IMFMediaSession: video to the EVR on
# Hwnd, audio to the Windows audio renderer (WASAPI) on its own clock. Media
# Foundation owns scheduling and samples; no frame or packet enters PowerShell.
# StartEvents receives the session (an IMFMediaEventGenerator) and returns a
# started QuickPSMediaSessionEvents worker (src/MediaSessionEvents.Windows.ps1)
# that posts NotifyMessage .. NotifyMessage + 2 to the caller's window; the
# window owner passes each message to HandleMessage. Nothing here polls.
# Layouts: Windows SDK 10.0.26100.0 mfidl.h, mfobjects.h, evr.h, mfapi.h.
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
$outCom = { param([IntPtr] $Object, [int] $Slot)
    $p = $n.Allocate(8)
    try { & $check ($n.InvokeCom($Object, $Slot, [int], @([IntPtr]), @($p))) "COM slot $Slot"; [Runtime.InteropServices.Marshal]::ReadIntPtr($p) }
    finally { $n.Free($p) }
}.GetNewClosure()
$set = { param([IntPtr] $Object, [Guid] $Key, $Value, [switch] $Unknown)
    $p = & $guid $Key
    try {
        # IMFAttributes::SetUINT32 21, SetUnknown 27.
        $slot = if ($Unknown) { 27 } else { 21 }
        $type = if ($Unknown) { [IntPtr] } else { [uint32] }
        $v = if ($Unknown) { [IntPtr]$Value } else { [uint32]$Value }
        & $check ($n.InvokeCom($Object, $slot, [int], @([IntPtr], $type), @($p, $v))) 'Set native attribute'
    } finally { $n.Free($p) }
}.GetNewClosure()
$read = { param([IntPtr] $Object, [Guid] $Key, [int] $Slot = 8)
    # IMFAttributes::GetUINT32 7, GetUINT64 8, GetGUID 10.
    $keyPtr = & $guid $Key
    $p = $n.Allocate(16)
    try {
        & $check ($n.InvokeCom($Object, $Slot, [int], @([IntPtr], [IntPtr]), @($keyPtr, $p))) 'Read native attribute'
        if ($Slot -eq 8) { return [uint64][Runtime.InteropServices.Marshal]::ReadInt64($p) }
        if ($Slot -eq 7) { return [Runtime.InteropServices.Marshal]::ReadInt32($p) }
        $bytes = [byte[]]::new(16); [Runtime.InteropServices.Marshal]::Copy($p, $bytes, 0, 16); [Guid]::new($bytes)
    } finally { $n.Free($p); $n.Free($keyPtr) }
}.GetNewClosure()
$export = { param([string] $Name, [Type[]] $Types)
    $n.GetExportCall('mf.dll', $Name, [int], $Types)
}.GetNewClosure()
$getService = & $export 'MFGetService' @([IntPtr], [IntPtr], [IntPtr], [IntPtr])
$getClientRect = $n.GetExportCall('user32.dll', 'GetClientRect', [bool], @([IntPtr], [IntPtr]))
$instance = [PSCustomObject]@{
    PSTypeName = 'QuickPS.MediaSession'; Kind = $Kind; Hwnd = $Hwnd
    NotifyMessage = $NotifyMessage; Events = $null
    Activate = [IntPtr]::Zero; Session = [IntPtr]::Zero; Source = [IntPtr]::Zero
    Renderer = [IntPtr]::Zero; Display = [IntPtr]::Zero; Quality = [IntPtr]::Zero
    Started = $false; Ready = $false; Closed = $false; Mode = $null; SupportedModes = @()
    DestinationWidth = 0; DestinationHeight = 0
}
$instance | Add-Member ScriptMethod Resize ({
    param([int] $Width, [int] $Height)
    if ($this.Display -eq [IntPtr]::Zero -or $Width -le 0 -or $Height -le 0) { return }
    if ($this.DestinationWidth -eq $Width -and $this.DestinationHeight -eq $Height) { return }
    $rect = $n.Allocate(16)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 8, $Width)
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 12, $Height)
        # IMFVideoDisplayControl::SetVideoPosition 5: whole source to the client rectangle.
        & $check ($n.InvokeCom($this.Display, 5, [int], @([IntPtr], [IntPtr]), @([IntPtr]::Zero, $rect))) 'Set EVR destination'
        $this.DestinationWidth = $Width; $this.DestinationHeight = $Height
    } finally { $n.Free($rect) }
}.GetNewClosure())
$instance | Add-Member ScriptMethod HandleMessage ({
    # Returns $false for a message outside this session's range. Throws on a
    # failed event status or a stopped event worker.
    param([uint32] $Message, [long] $WParam, [long] $LParam)
    $offset = [long]$Message - $this.NotifyMessage
    if ($offset -lt 0 -or $offset -gt 2) { return $false }
    if ($offset -eq 2) { throw ('{0} session events stopped: 0x{1:X8}' -f $this.Kind, [int]$LParam) }
    & $check ([int]$LParam) "$($this.Kind) session event $WParam"
    if ($offset -eq 0) {
        if ($WParam -eq 103) { $this.Started = $true }    # MESessionStarted
        if ($WParam -eq 106) { $this.Closed = $true }     # MESessionClosed
        return $true
    }
    # MESessionTopologyStatus with MF_TOPOSTATUS_READY (100): bind the EVR, start.
    if ($WParam -ne 100 -or $this.Ready) { return $true }
    $this.Ready = $true
    $scratch = $n.Allocate(24)
    try {
        if ($this.Kind -eq 'Video') {
            $service = & $guid ([Guid]'1092a86c-ab1a-459a-a336-831fbc4d11ff')   # MR_VIDEO_RENDER_SERVICE
            $iid = & $guid ([Guid]'a490b1e4-ab84-4d31-a1b2-181e03b1077a')       # IMFVideoDisplayControl
            try {
                & $check ($getService.Invoke($this.Session, $service, $iid, $scratch)) 'Get EVR display'
                $this.Display = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                # SetAspectRatioMode 7, MFVideoARMode_None: stretch to the client.
                & $check ($n.InvokeCom($this.Display, 7, [int], @([uint32]), @([uint32]0))) 'Stretch to fill'
                if ($getClientRect.Invoke($this.Hwnd, $scratch)) {
                    $this.Resize([Runtime.InteropServices.Marshal]::ReadInt32($scratch, 8), [Runtime.InteropServices.Marshal]::ReadInt32($scratch, 12))
                }
                $n.Free($iid); $iid = & $guid ([Guid]'1bd0ecb0-f8e2-11ce-aac6-0020af0b99a3')   # IQualProp
                if ($getService.Invoke($this.Session, $service, $iid, $scratch) -ge 0) { $this.Quality = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch) }
            } finally { $n.Free($service); $n.Free($iid) }
        }
        $format = & $guid ([Guid]::Empty)
        $position = $n.Allocate(24)   # PROPVARIANT VT_EMPTY: live sources cannot seek.
        try {
            # IMFMediaSession::Start 9.
            & $check ($n.InvokeCom($this.Session, 9, [int], @([IntPtr], [IntPtr]), @($format, $position))) 'Start native media session'
        } finally { $n.Free($format); $n.Free($position) }
    } finally { $n.Free($scratch) }
    $true
}.GetNewClosure())
$instance | Add-Member ScriptMethod GetStatistics ({
    # IQualProp (amvideo.h): get_FramesDroppedInRenderer 3, get_FramesDrawn 4,
    # get_AvgFrameRate 5 (frames per second times 100).
    # A counter the renderer does not implement (E_NOTIMPL) is reported as $null.
    if ($this.Quality -eq [IntPtr]::Zero) { return $null }
    $scratch = $n.Allocate(4)
    try {
        $values = foreach ($slot in 3, 4, 5) {
            $hr = $n.InvokeCom($this.Quality, $slot, [int], @([IntPtr]), @($scratch))
            if ($hr -eq -2147467263) { $null }
            else { & $check $hr "Get EVR statistic $slot"; [Runtime.InteropServices.Marshal]::ReadInt32($scratch) }
        }
        [PSCustomObject]@{ Dropped = $values[0]; Drawn = $values[1]; FramesPerSecond = if ($null -ne $values[2]) { $values[2] / 100.0 } else { $null } }
    } finally { $n.Free($scratch) }
}.GetNewClosure())
$instance | Add-Member ScriptMethod Dispose ({
    # Close, wait for the worker to see MESessionClosed, Shutdown, then release.
    # Teardown continues after a failure, and every failure is reported.
    $errors = [Collections.Generic.List[string]]::new()
    $worker = $this.Events
    if ($this.Session -ne [IntPtr]::Zero) {
        $closeHr = $n.InvokeCom($this.Session, 12, [int], @(), @())   # Close
        if ($closeHr -ge 0 -and $worker -and $worker.Thread.IsAlive -and -not $worker.Thread.Join(3000)) {
            $errors.Add('Session close did not complete within three seconds.')
        }
        $hr = $n.InvokeCom($this.Session, 13, [int], @(), @())        # Shutdown
        if ($hr -lt 0 -and $hr -ne -1072873851) { $errors.Add(('Session shutdown: 0x{0:X8}' -f $hr)) }
        # After Shutdown, GetEvent returns MF_E_SHUTDOWN and the worker ends.
        if ($worker -and $worker.Thread.IsAlive -and -not $worker.Thread.Join(3000)) {
            # The worker still holds the session pointer: leak it rather than free it under the thread.
            $errors.Add('Session event worker did not stop; the session was not released.')
            $this.Session = [IntPtr]::Zero
        }
    }
    foreach ($name in @('Quality', 'Display', 'Session')) { if ($this.$name -ne [IntPtr]::Zero) { [void]$n.ReleaseCom($this.$name); $this.$name = [IntPtr]::Zero } }
    if ($this.Source -ne [IntPtr]::Zero) {
        $hr = $n.InvokeCom($this.Source, 12, [int], @(), @())          # IMFMediaSource::Shutdown
        if ($hr -lt 0 -and $hr -ne -1072873851) { $errors.Add(('Capture shutdown: 0x{0:X8}' -f $hr)) }
        [void]$n.ReleaseCom($this.Source); $this.Source = [IntPtr]::Zero
    }
    foreach ($name in @('Renderer', 'Activate')) {
        if ($this.$name -ne [IntPtr]::Zero) {
            # IMFActivate::ShutdownObject 34 clears the cached object, so the
            # same device can be opened again.
            $hr = $n.InvokeCom($this.$name, 34, [int], @(), @())
            if ($hr -lt 0) { $errors.Add(('{0} shutdown: 0x{1:X8}' -f $name, $hr)) }
            [void]$n.ReleaseCom($this.$name); $this.$name = [IntPtr]::Zero
        }
    }
    $this.Started = $false
    if ($errors.Count) { throw ($errors -join '; ') }
}.GetNewClosure())

$scratch = $n.Allocate(32)
$temporary = [Collections.Generic.List[IntPtr]]::new()
try {
    [void]$n.InvokeCom($Activate, 1, [uint32], @(), @())   # AddRef: the session owns its own reference.
    $instance.Activate = $Activate
    if ($Kind -eq 'Video') {
        # MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_MAX_BUFFERS = 1, set before
        # ActivateObject: the capture source holds at most one frame.
        & $set $Activate ([Guid]'7dd9b730-4f2d-41d5-8f95-0cc9a912ba26') 1
    }
    $iid = & $guid ([Guid]'279a808d-aec7-40c8-9c6b-a6b492c78a66')   # IMFMediaSource
    try { & $check ($n.InvokeCom($Activate, 33, [int], @([IntPtr], [IntPtr]), @($iid, $scratch))) 'Activate capture source'; $instance.Source = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch) }
    finally { $n.Free($iid) }
    $presentation = & $outCom $instance.Source 8; $temporary.Add($presentation)   # CreatePresentationDescriptor
    & $check ($n.InvokeCom($presentation, 33, [int], @([IntPtr]), @($scratch))) 'Count streams'
    $streamCount = [Runtime.InteropServices.Marshal]::ReadInt32($scratch)
    if ($streamCount -lt 1) { throw 'Capture source has no streams.' }
    & $check ($n.InvokeCom($presentation, 34, [int], @([uint32], [IntPtr], [IntPtr]), @([uint32]0, $scratch, [IntPtr]::Add($scratch, 8)))) 'Get capture stream'
    $stream = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch, 8); $temporary.Add($stream)
    & $check ($n.InvokeCom($presentation, 35, [int], @([uint32]), @([uint32]0))) 'Select capture stream'
    for ($i = 1; $i -lt $streamCount; $i++) { & $check ($n.InvokeCom($presentation, 36, [int], @([uint32]), @([uint32]$i))) 'Deselect other streams' }
    $handler = & $outCom $stream 34; $temporary.Add($handler)   # GetMediaTypeHandler
    if ($Kind -eq 'Video') {
        & $check ($n.InvokeCom($handler, 4, [int], @([IntPtr]), @($scratch))) 'Count native video modes'
        $count = [Runtime.InteropServices.Marshal]::ReadInt32($scratch)
        $best = [IntPtr]::Zero; $bestScore = -1.0
        try {
            for ($i = 0; $i -lt $count; $i++) {
                & $check ($n.InvokeCom($handler, 5, [int], @([uint32], [IntPtr]), @([uint32]$i, $scratch))) 'Read native mode'
                $typePtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                try {
                    $size = & $read $typePtr ([Guid]'1652c33d-d6b2-4012-b834-72030849a37d')   # MF_MT_FRAME_SIZE
                    $rate = & $read $typePtr ([Guid]'c459a2e8-3d2c-4e44-b132-fee5156c7bb0')   # MF_MT_FRAME_RATE
                    $subtype = & $read $typePtr ([Guid]'f7e34c9a-42e8-4714-b74b-cb29d72c35e5') 10   # MF_MT_SUBTYPE
                    $w = [int]($size -shr 32); $h = [int]($size -band 0xffffffffL)
                    $denominator = [int]($rate -band 0xffffffffL)
                    if ($denominator -eq 0) { continue }
                    $fps = ($rate -shr 32) / [double]$denominator
                    $mode = [PSCustomObject]@{ Width = $w; Height = $h; FrameRate = $fps; Subtype = $subtype }
                    $instance.SupportedModes += $mode
                    # Prefer the requested size, then the closest rate, then the preferred subtype.
                    $score = $(if ($w -eq $Width -and $h -eq $Height) { 1e9 } else { 0 }) - [Math]::Abs($fps - $FrameRate) * 1e6 - [Math]::Abs($w * $h - $Width * $Height) + $(if ($subtype -eq $PreferredSubtype) { 1000 } else { 0 })
                    if ($score -gt $bestScore -or $best -eq [IntPtr]::Zero) {
                        if ($best -ne [IntPtr]::Zero) { [void]$n.ReleaseCom($best) }
                        $best = $typePtr; $typePtr = [IntPtr]::Zero; $bestScore = $score
                        $instance.Mode = $mode
                    }
                } finally { if ($typePtr -ne [IntPtr]::Zero) { [void]$n.ReleaseCom($typePtr) } }
            }
            if ($best -eq [IntPtr]::Zero) { throw 'No supported video mode.' }
            & $check ($n.InvokeCom($handler, 6, [int], @([IntPtr]), @($best))) 'Select native video mode'
        } finally { if ($best -ne [IntPtr]::Zero) { [void]$n.ReleaseCom($best) } }
    }
    $attrs = $mf.CreateAttributes(1); $temporary.Add($attrs)
    & $set $attrs ([Guid]'9c27891a-ed7a-40e1-88e8-b22727a024ee') 1   # MF_LOW_LATENCY
    $createSession = & $export 'MFCreateMediaSession' @([IntPtr], [IntPtr])
    & $check ($createSession.Invoke($attrs, $scratch)) 'Create media session'; $instance.Session = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
    # The worker starts before the topology is set, so it sees every event.
    $instance.Events = & $StartEvents $instance.Session
    if (-not $instance.Events -or -not $instance.Events.Thread.IsAlive) { throw 'StartEvents did not return a running event worker.' }
    $createTopology = & $export 'MFCreateTopology' @([IntPtr])
    & $check ($createTopology.Invoke($scratch)) 'Create topology'; $topology = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch); $temporary.Add($topology)
    & $set $topology ([Guid]'9c27891a-ed7a-40e1-88e8-b22727a024ee') 1   # MF_LOW_LATENCY
    & $set $topology ([Guid]'6248c36d-5d0b-4f40-a0bb-b0b305f77698') 0   # MF_TOPOLOGY_ENUMERATE_SOURCE_TYPES
    if ($Kind -eq 'Video') {
        # Permit hardware transforms and pass the EVR's DXVA device through the
        # resolved graph; do not require hardware where a driver lacks it.
        & $set $topology ([Guid]'d2d362fd-4e4f-4191-a579-c618b66706af') 1   # MF_TOPOLOGY_HARDWARE_MODE
        & $set $topology ([Guid]'1e8d34f6-f5ab-4e23-bb88-874aa3a1a74d') 0   # MF_TOPOLOGY_DXVA_MODE (auto)
        $createRenderer = & $export 'MFCreateVideoRendererActivate' @([IntPtr], [IntPtr])
        & $check ($createRenderer.Invoke($Hwnd, $scratch)) 'Create EVR'
    } else {
        $createRenderer = & $export 'MFCreateAudioRendererActivate' @([IntPtr])
        & $check ($createRenderer.Invoke($scratch)) 'Create Windows audio renderer'
    }
    $instance.Renderer = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
    if ($Kind -eq 'Audio') {
        # Low latency on the renderer activation, before topology resolution.
        & $set $instance.Renderer ([Guid]'9c27891a-ed7a-40e1-88e8-b22727a024ee') 1
    }
    $createNode = & $export 'MFCreateTopologyNode' @([uint32], [IntPtr])
    & $check ($createNode.Invoke([uint32]1, $scratch)) 'Create source node'; $sourceNode = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch); $temporary.Add($sourceNode)
    & $set $sourceNode ([Guid]'835c58ec-e075-4bc7-bcba-4de000df9ae6') $instance.Source -Unknown   # MF_TOPONODE_SOURCE
    & $set $sourceNode ([Guid]'835c58ed-e075-4bc7-bcba-4de000df9ae6') $presentation -Unknown      # MF_TOPONODE_PRESENTATION_DESCRIPTOR
    & $set $sourceNode ([Guid]'835c58ee-e075-4bc7-bcba-4de000df9ae6') $stream -Unknown            # MF_TOPONODE_STREAM_DESCRIPTOR
    & $check ($createNode.Invoke([uint32]0, $scratch)) 'Create output node'; $outputNode = [Runtime.InteropServices.Marshal]::ReadIntPtr($scratch); $temporary.Add($outputNode)
    & $check ($n.InvokeCom($outputNode, 33, [int], @([IntPtr]), @($instance.Renderer))) 'Attach renderer'
    & $set $outputNode ([Guid]'14932f9b-9087-4bb4-8412-5167145cbe04') 0   # MF_TOPONODE_STREAMID
    foreach ($node in @($sourceNode, $outputNode)) { & $check ($n.InvokeCom($topology, 34, [int], @([IntPtr]), @($node))) 'Add topology node' }
    & $check ($n.InvokeCom($sourceNode, 40, [int], @([uint32], [IntPtr], [uint32]), @([uint32]0, $outputNode, [uint32]0))) 'Connect native capture to renderer'
    # IMFMediaSession::SetTopology 7; MESessionTopologyStatus READY follows as a message.
    & $check ($n.InvokeCom($instance.Session, 7, [int], @([uint32], [IntPtr]), @([uint32]0, $topology))) 'Resolve topology'
} catch { try { $instance.Dispose() } catch { Write-Warning $_ }; throw }
finally { for ($i = $temporary.Count - 1; $i -ge 0; $i--) { [void]$n.ReleaseCom($temporary[$i]) }; $n.Free($scratch) }
$instance

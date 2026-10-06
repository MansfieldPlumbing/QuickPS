[CmdletBinding()]
param(
    [string] $Device,
    [switch] $Windowed,
    [string] $EventsAssemblyPath = $(if (Test-Path (Join-Path $PSScriptRoot '..\lib\QuickPS.MediaSessionEvents.dll')) { Join-Path $PSScriptRoot '..\lib\QuickPS.MediaSessionEvents.dll' } else { Join-Path $PSScriptRoot '..\build\managed\QuickPS.MediaSessionEvents.dll' }),
    [switch] $Verify
)
if ($MyInvocation.InvocationName -eq '.') { throw 'VideoIn.ps1 must be invoked with &, not dot-sourced.' }
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [IntPtr]::Size -ne 8) { throw 'Use 64-bit PowerShell 7 on Windows.' }

# Shows a video capture input (a camera or a USB HDMI capture adapter) with its
# matching audio. Media Foundation renders natively; this script blocks on the
# window's message queue and reacts to keys, size changes and session events.
#   F or Enter: toggle fullscreen.  Esc: leave fullscreen.  N: next input.
# -Device selects the first input whose name contains the text.
$src = Join-Path $PSScriptRoot '..\src'
$videoMessage = [uint32]0x8000
$audioMessage = [uint32]0x8010
$state = [pscustomobject]@{ Cameras = @(); AudioDevices = @(); Selected = 0; Video = $null; Audio = $null; Result = $null; Clock = $null; DrawnAtStart = $null }
$native = $media = $devices = $window = $null
$coOwned = $false
$dpi = [IntPtr]::Zero
try {
    $native = & "$src\Native.ps1"
    $dpiCall = $native.GetExportCall('user32.dll', 'SetThreadDpiAwarenessContext', [IntPtr], @([IntPtr]))
    $dpi = $dpiCall.Invoke([IntPtr]::new(-4))   # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
    $coHr = $native.GetExportCall('ole32.dll', 'CoInitializeEx', [int], @([IntPtr], [uint32])).Invoke([IntPtr]::Zero, [uint32]0)
    if ($coHr -lt 0 -and $coHr -ne -2147417850) { throw ('COM initialization: 0x{0:X8}' -f $coHr) }   # RPC_E_CHANGED_MODE is tolerated.
    $coOwned = $coHr -ge 0
    $media = & "$src\MediaFoundation.Windows.ps1"
    $devices = & "$src\CaptureDevice.Windows.ps1" -Native $native -MediaFoundation $media
    $state.Cameras = @($devices.Enumerate('Video'))
    $state.AudioDevices = @($devices.Enumerate('Audio'))
    if (-not $state.Cameras.Count) {
        if ($Verify) { 'NOT RUN: no video capture input is attached.'; return }
        throw 'No video capture input found.'
    }
    if ($Device) {
        $state.Selected = [Array]::FindIndex([object[]]$state.Cameras, [Predicate[object]]{ param($c) $c.Name -like "*$Device*" })
        if ($state.Selected -lt 0) { throw "No video capture input matches '$Device'." }
    }
    $window = & "$src\Window.Windows.ps1" -Width 1280 -Height 720 -Title 'Video In' -BackgroundColor 0

    $closeInput = {
        foreach ($name in 'Audio', 'Video') {
            $session = $state.$name
            $state.$name = $null
            if ($session) { try { $session.Dispose() } catch { Write-Warning $_ } }
        }
    }
    # Each session's compiled event worker posts to this window in its own range.
    $eventsFor = {
        param([uint32] $Message)
        $hwnd = $window.Hwnd
        {
            param([IntPtr] $Generator)
            $worker = & "$src\MediaSessionEvents.Windows.ps1" -AssemblyPath $EventsAssemblyPath -Generator $Generator -NotifyWindow $hwnd -Message $Message
            $worker.Thread.Start()
            $worker
        }.GetNewClosure()
    }
    $openInput = {
        param([int] $Index)
        & $closeInput
        $state.Selected = $Index
        $camera = $state.Cameras[$Index]
        $state.Video = & "$src\MediaSession.Windows.ps1" -Native $native -MediaFoundation $media -Activate $camera.Activate `
            -StartEvents (& $eventsFor $videoMessage) -NotifyMessage $videoMessage -Hwnd $window.Hwnd
        $partner = $devices.MatchAudio($camera, $state.AudioDevices)
        if ($partner) {
            $state.Audio = & "$src\MediaSession.Windows.ps1" -Native $native -MediaFoundation $media -Activate $partner.Activate `
                -StartEvents (& $eventsFor $audioMessage) -NotifyMessage $audioMessage -Kind Audio
        }
    }
    $setTimer = $native.GetExportCall('user32.dll', 'SetTimer', [UIntPtr], @([IntPtr], [UIntPtr], [uint32], [IntPtr]))
    $killTimer = $native.GetExportCall('user32.dll', 'KillTimer', [bool], @([IntPtr], [UIntPtr]))

    $onInput = {
        param($event)
        switch ($event.Kind) {
            'Notify' {
                foreach ($name in 'Video', 'Audio') {
                    $session = $state.$name
                    if (-not $session) { continue }
                    try {
                        if ($session.HandleMessage($event.Message, $event.WParam, $event.LParam)) {
                            if ($Verify -and $name -eq 'Video' -and $event.Message -eq $videoMessage -and $event.WParam -eq 103) {
                                # MESessionStarted: count frames drawn over three seconds.
                                $state.Clock = [Diagnostics.Stopwatch]::StartNew()
                                $state.DrawnAtStart = $state.Video.GetStatistics().Drawn
                                [void]$setTimer.Invoke($window.Hwnd, [UIntPtr]::new(1), [uint32]3000, [IntPtr]::Zero)
                            }
                            break
                        }
                    } catch {
                        Write-Warning "$name input stopped: $($_.Exception.Message)"
                        $state.$name = $null
                        try { $session.Dispose() } catch { Write-Warning $_ }
                        if ($Verify) { $state.Result = "FAIL: $($_.Exception.Message)"; [void]$window.Close() }
                    }
                }
            }
            'Resize' { if ($state.Video) { $state.Video.Resize($event.Width, $event.Height) } }
            'KeyDown' {
                if ($event.Repeat) { break }
                switch ($event.KeyCode) {
                    { $_ -in 0x46, 0x0D } { $window.SetFullscreen(-not $window.Fullscreen) }   # F, Enter
                    0x1B { $window.SetFullscreen($false) }                                      # Esc
                    0x4E { & $openInput (($state.Selected + 1) % $state.Cameras.Count) }        # N
                }
            }
            'Timer' {
                if ($event.TimerId -ne 1) { break }
                [void]$killTimer.Invoke($window.Hwnd, [UIntPtr]::new(1))
                $stats = $state.Video.GetStatistics()
                $seconds = $state.Clock.Elapsed.TotalSeconds
                $mode = $state.Video.Mode
                $drawn = if ($null -ne $stats.Drawn -and $null -ne $state.DrawnAtStart) { $stats.Drawn - $state.DrawnAtStart } else { $null }
                $state.Result = if ($drawn -gt 0) {
                    'PASS: {0} {1}x{2} at {3:0.##} fps offered; renderer drew {4} frames in {5:0.00} s ({6:0.##} fps), dropped {7}. No frame entered PowerShell.' -f $state.Cameras[$state.Selected].Name, $mode.Width, $mode.Height, $mode.FrameRate, $drawn, $seconds, ($drawn / $seconds), $stats.Dropped
                } elseif ($null -eq $drawn) { 'FAIL: the renderer does not report frames drawn.' } else { 'FAIL: the renderer drew no frames.' }
                [void]$window.Close()
            }
        }
    }.GetNewClosure()

    if (-not $Windowed -and -not $Verify) { $window.SetFullscreen($true) }
    [void]$window.Show()
    & $openInput $state.Selected
    $null = $window.Run($onInput)
    if ($Verify) {
        if (-not $state.Result) { throw 'Verification ended before a result.' }
        $state.Result
        if ($state.Result -like 'FAIL*') { exit 1 }
    }
} finally {
    # Sessions close before the HWND they render to; native libraries unload last.
    foreach ($name in 'Audio', 'Video') { if ($state.$name) { try { $state.$name.Dispose() } catch { Write-Warning $_ } } }
    foreach ($owner in @($window, $devices, $media)) { if ($owner) { try { $owner.Dispose() } catch { Write-Warning $_ } } }
    if ($native) {
        if ($coOwned) { $native.GetExportCall('ole32.dll', 'CoUninitialize', [void], @()).Invoke() }
        if ($dpi -ne [IntPtr]::Zero) { [void]$dpiCall.Invoke($dpi) }
        $native.Dispose()
    }
}

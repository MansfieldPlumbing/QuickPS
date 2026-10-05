[CmdletBinding()]
param([switch] $Verify)

$ErrorActionPreference = 'Stop'
$window = $null
$binding = $null
$resources = [Collections.Generic.List[object]]::new()

try {
    $window = & (Join-Path $PSScriptRoot '..\src\Window.Windows.ps1') `
        -Width 760 -Height 440 -Title 'QuickPS Direct2D and DirectWrite' `
        -BackgroundColor 0x001B1815
    if (-not $Verify) { $null = $window.Show() }

    $binding = & (Join-Path $PSScriptRoot '..\src\D2D.Windows.ps1')
    $factory = $binding.CreateFactory.Invoke()
    $resources.Add($factory)
    $target = $factory.CreateHwndRenderTarget.Invoke($window.Hwnd, $window.Width, $window.Height)
    $resources.Add($target)
    $textFactory = $binding.CreateDWriteFactory.Invoke()
    $resources.Add($textFactory)
    $heading = $textFactory.CreateTextFormat.Invoke('Segoe UI', [single]32, [uint32]600)
    $resources.Add($heading)
    $body = $textFactory.CreateTextFormat.Invoke('Segoe UI', [single]18)
    $resources.Add($body)
    $accent = $target.CreateSolidColorBrush.Invoke([single]0.14, [single]0.83, [single]0.70)
    $resources.Add($accent)
    $white = $target.CreateSolidColorBrush.Invoke([single]0.92, [single]0.95, [single]0.97)
    $resources.Add($white)

    $target.BeginDraw.Invoke()
    $target.ClearColor.Invoke([single]0.08, [single]0.10, [single]0.13)
    $target.FillRectangle.Invoke([single]40, [single]42, [single]48, [single]330, $accent)
    $target.DrawText.Invoke('Native text, from PowerShell', [single]72, [single]62,
        [single]700, [single]122, $heading, $white)
    $target.DrawText.Invoke('DirectWrite shapes Unicode text. Direct2D draws it into a Win32 window.',
        [single]72, [single]153, [single]680, [single]235, $body, $white)
    $target.DrawText.Invoke('Close this window to release its native resources.',
        [single]72, [single]260, [single]680, [single]325, $body, $accent)
    $hr = [int32](& $target.EndDraw)
    if ($hr -lt 0) { throw "ID2D1RenderTarget::EndDraw failed: $hr" }

    if ($Verify) {
        if ($target.Pointer -eq [IntPtr]::Zero -or $heading.Pointer -eq [IntPtr]::Zero) {
            throw 'A native drawing resource was not created.'
        }
        if (-not $window.Close()) { throw 'Window close was not queued.' }
        $null = $window.Run()
        if ($window.Alive) { throw 'Window remained alive after close dispatch.' }
        'PASS: native window, Direct2D target and brushes, DirectWrite formats, drawing, and close dispatch.'
    } else {
        $null = $window.Run()
    }
} finally {
    for ($index = $resources.Count - 1; $index -ge 0; $index--) {
        [void]$resources[$index].Release.Invoke()
    }
    if ($binding) {
        [Runtime.InteropServices.NativeLibrary]::Free($binding.DWriteHandle)
        [Runtime.InteropServices.NativeLibrary]::Free($binding.D2D1Handle)
    }
    if ($window) { $window.Dispose() }
}

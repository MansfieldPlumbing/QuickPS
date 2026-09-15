[CmdletBinding()]
param(
    [int] $Milliseconds = 8000,
    [string] $Title = 'QuickPS Window Conformance',
    [uint32] $BackgroundColor = 0x0033CC
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Show-Window.ps1 must be invoked with &, not dot-sourced.'
}

$ErrorActionPreference = 'Stop'
$windowParameters = @{
    Width = 720
    Height = 420
    Title = $Title
    BackgroundColor = $BackgroundColor
}
$window = & (Join-Path $PSScriptRoot '..\src\Window.Windows.ps1') @windowParameters
try {
    $null = $window.Show()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $Milliseconds -and $window.Alive) {
        $null = $window.Pump()
        [Threading.Thread]::Sleep(8)
    }
}
finally {
    $window.Dispose()
}

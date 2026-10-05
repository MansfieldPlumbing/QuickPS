[CmdletBinding()]
param(
    [switch] $Verify,
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
    if ($Verify) { $null = $window.Close() }
    $null = $window.Run()
    if ($Verify -and $window.Alive) { throw 'Window remained alive after WM_CLOSE dispatch.' }
}
finally {
    $window.Dispose()
}

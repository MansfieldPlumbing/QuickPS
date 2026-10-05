[CmdletBinding()]
param([switch] $Verify)

$ErrorActionPreference = 'Stop'
$window = & (Join-Path $PSScriptRoot '..\src\Window.Windows.ps1') `
    -Width 720 -Height 420 -Title 'QuickPS native window' -BackgroundColor 0x0033CC

try {
    if ($Verify) {
        if ($window.Hwnd -eq [IntPtr]::Zero -or -not $window.Alive) {
            throw 'Window creation did not return a live HWND.'
        }
        if (-not $window.Close()) { throw 'WM_CLOSE was not queued.' }
        $null = $window.Run()
        if ($window.Alive) { throw 'Window remained alive after WM_CLOSE dispatch.' }
        $window.Dispose()
        $window.Dispose()
        'PASS: native HWND creation, queued close, blocking dispatch, and repeated disposal.'
        return
    }

    $null = $window.Show()
    $null = $window.Run()
}
finally {
    $window.Dispose()
}

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))
$camera = & (Join-Path $root 'Camera3D.ps1')

foreach ($matrixName in 'View','Projection','ViewProjection') {
    $matrix = $camera.$matrixName
    if ($matrix.Count -ne 16) { throw "$matrixName does not contain 16 values." }
    if (@($matrix | Where-Object { [single]::IsNaN($_) -or [single]::IsInfinity($_) }).Count) {
        throw "$matrixName contains a non-finite value."
    }
}
if ([Math]::Abs($camera.View[14] - 4.5) -gt 0.0001) { throw 'Default camera translation is wrong.' }
$wide = & (Join-Path $root 'Camera3D.ps1') -AspectRatio 2
$square = & (Join-Path $root 'Camera3D.ps1') -AspectRatio 1
if ($wide.Projection[0] -ge $square.Projection[0]) { throw 'Horizontal projection does not respond to aspect ratio.' }
$rejected = $false
try { $null = & (Join-Path $root 'Camera3D.ps1') -Position @(0,0,0) -Target @(0,0,0) }
catch { $rejected = $true }
if (-not $rejected) { throw 'Coincident camera position and target were accepted.' }

[PSCustomObject]@{
    MatrixValues = $camera.ViewProjection.Count
    DefaultViewTranslationZ = $camera.View[14]
    AspectRatioChangesProjection = $true
    InvalidDirectionRejected = $true
    Passed = $true
}

$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::Load('System.Drawing.Common')
$gate=Join-Path $PSScriptRoot 'ImageSilhouette.Verify.ps1'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-Silhouette-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary)|Out-Null
$makeImage={param($Path,[scriptblock]$Draw)
    $bitmap=[Drawing.Bitmap]::new(200,150);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{$graphics.Clear([Drawing.Color]::FromArgb(4,6,15));& $Draw $graphics;$bitmap.Save($Path,[Drawing.Imaging.ImageFormat]::Png)}
    finally{$graphics.Dispose();$bitmap.Dispose()}
}
try {
    $blankPath=Join-Path $temporary 'blank.png';$splitPath=Join-Path $temporary 'split.png';$voidPath=Join-Path $temporary 'void.png'
    & $makeImage $blankPath {param($Graphics)}
    & $makeImage $splitPath {param($Graphics);$brush=[Drawing.SolidBrush]::new([Drawing.Color]::Lime);try{$Graphics.FillRectangle($brush,30,40,55,80);$Graphics.FillRectangle($brush,115,40,55,80)}finally{$brush.Dispose()}}
    & $makeImage $voidPath {param($Graphics);$brush=[Drawing.SolidBrush]::new([Drawing.Color]::Lime);$erase=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(4,6,15));try{$Graphics.FillRectangle($brush,30,35,140,90);$Graphics.FillRectangle($erase,75,60,50,40)}finally{$brush.Dispose();$erase.Dispose()}}
    $rejected=$false;try{& $gate -Path $blankPath *> $null}catch{$rejected=$true};if(-not $rejected){throw 'Gate accepted a blank image.'}
    $rejected=$false;try{& $gate -Path $splitPath -MinimumForegroundPixels 100 *> $null}catch{$rejected=$true};if(-not $rejected){throw 'Gate accepted two foreground components.'}
    $rejected=$false;try{& $gate -Path $voidPath -MinimumForegroundPixels 100 *> $null}catch{$rejected=$true};if(-not $rejected){throw 'Gate accepted an undeclared silhouette void.'}
    $accepted=& $gate -Path $voidPath -MinimumForegroundPixels 100 -ExpectedSilhouetteVoidCount 1
    if(-not $accepted.Passed){throw 'Gate rejected a declared silhouette void.'}
    [PSCustomObject]@{BlankRejected=$true;SplitRejected=$true;UndeclaredVoidRejected=$true;DeclaredVoidAccepted=$true;Passed=$true}
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force}

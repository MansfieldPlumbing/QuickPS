[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Path,
    [ValidateRange(1,1000000)][int] $MinimumForegroundPixels = 1000,
    [ValidateRange(0,64)][int] $ExpectedSilhouetteVoidCount = 0
)
$ErrorActionPreference='Stop'
[void][Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $PSHOME 'System.Drawing.Common.dll'))
$bitmap=[Drawing.Bitmap]::new([IO.Path]::GetFullPath($Path))
try {
    $left=8;$top=31;$width=$bitmap.Width-16;$height=$bitmap.Height-39
    if($width-le 0-or $height-le 0){throw 'Capture is too small to contain a client area.'}
    $background=$bitmap.GetPixel($left+2,$top+2)
    $foreground=[bool[]]::new($width*$height);$foregroundPixels=0
    for($y=0;$y-lt $height;$y++){for($x=0;$x-lt $width;$x++){
        $pixel=$bitmap.GetPixel($left+$x,$top+$y)
        $distance=($pixel.R-$background.R)*($pixel.R-$background.R)+($pixel.G-$background.G)*($pixel.G-$background.G)+($pixel.B-$background.B)*($pixel.B-$background.B)
        if($distance-gt 900){$foreground[$y*$width+$x]=$true;$foregroundPixels++}
    }}
    if($foregroundPixels-lt $MinimumForegroundPixels){throw "Rendered silhouette has only $foregroundPixels foreground pixels."}
    $countComponents={
        param([bool]$CountForeground)
        $visited=[bool[]]::new($foreground.Length);$queue=[int[]]::new($foreground.Length);$components=0;$enclosed=0
        for($start=0;$start-lt $foreground.Length;$start++){
            if($visited[$start]-or $foreground[$start]-ne $CountForeground){continue}
            $components++;$head=0;$tail=1;$queue[0]=$start;$visited[$start]=$true;$touchesBoundary=$false
            while($head-lt $tail){
                $current=$queue[$head++];$x=$current%$width;$y=[int][Math]::Floor($current/$width)
                if($x-eq 0-or $y-eq 0-or $x-eq $width-1-or $y-eq $height-1){$touchesBoundary=$true}
                foreach($next in @(($current-1),($current+1),($current-$width),($current+$width))){
                    if($next-lt 0-or $next-ge $foreground.Length){continue}
                    $nextX=$next%$width
                    if([Math]::Abs($nextX-$x)-gt 1){continue}
                    if(-not $visited[$next]-and $foreground[$next]-eq $CountForeground){$visited[$next]=$true;$queue[$tail++]=$next}
                }
            }
            if(-not $CountForeground-and-not $touchesBoundary){$enclosed++}
        }
        [PSCustomObject]@{Components=$components;Enclosed=$enclosed}
    }
    $foregroundResult=& $countComponents $true;$backgroundResult=& $countComponents $false
    if($foregroundResult.Components-ne 1){throw "Rendered silhouette has $($foregroundResult.Components) foreground components; expected 1."}
    if($backgroundResult.Enclosed-ne $ExpectedSilhouetteVoidCount){throw "Rendered silhouette has $($backgroundResult.Enclosed) enclosed background components; expected $ExpectedSilhouetteVoidCount."}
    [PSCustomObject]@{ForegroundPixels=$foregroundPixels;ForegroundComponentCount=$foregroundResult.Components;SilhouetteVoidCount=$backgroundResult.Enclosed;ExpectedSilhouetteVoidCount=$ExpectedSilhouetteVoidCount;Passed=$true}
} finally {$bitmap.Dispose()}

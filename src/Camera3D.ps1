[CmdletBinding()]
param(
    [single[]] $Position = @(0, 0, -4.5),
    [single[]] $Target = @(0, 0, 0),
    [single[]] $Up = @(0, 1, 0),
    [single] $FieldOfView = 60,
    [single] $AspectRatio = (720.0 / 420.0),
    [single] $NearPlane = 0.1,
    [single] $FarPlane = 1000.0
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Camera3D.ps1 must be invoked with &, not dot-sourced.'
}
foreach ($vector in @($Position,$Target,$Up)) {
    if ($vector.Count -ne 3) { throw 'Camera vectors must contain exactly three values.' }
}
if ($AspectRatio -le 0 -or $NearPlane -le 0 -or $FarPlane -le $NearPlane) {
    throw 'Camera projection bounds are invalid.'
}

$normalize = {
    param([double[]] $Value)
    $length = [Math]::Sqrt($Value[0]*$Value[0]+$Value[1]*$Value[1]+$Value[2]*$Value[2])
    if ($length -le 1e-12) { throw 'Cannot normalize a zero-length camera vector.' }
    [double[]]@(($Value[0]/$length),($Value[1]/$length),($Value[2]/$length))
}
$cross = {
    param([double[]] $A,[double[]] $B)
    [double[]]@(
        ($A[1]*$B[2]-$A[2]*$B[1]),
        ($A[2]*$B[0]-$A[0]*$B[2]),
        ($A[0]*$B[1]-$A[1]*$B[0]))
}
$direction = [double[]]@(
    ([double]$Target[0]-[double]$Position[0]),
    ([double]$Target[1]-[double]$Position[1]),
    ([double]$Target[2]-[double]$Position[2]))
$z = & $normalize $direction
$x = & $normalize (& $cross ([double[]]$Up) $z)
$y = & $cross $z $x
$view = [single[]]::new(16)
$view[0]=[single]$x[0]; $view[1]=[single]$y[0]; $view[2]=[single]$z[0]
$view[4]=[single]$x[1]; $view[5]=[single]$y[1]; $view[6]=[single]$z[1]
$view[8]=[single]$x[2]; $view[9]=[single]$y[2]; $view[10]=[single]$z[2]
$view[12]=[single]-($x[0]*$Position[0]+$x[1]*$Position[1]+$x[2]*$Position[2])
$view[13]=[single]-($y[0]*$Position[0]+$y[1]*$Position[1]+$y[2]*$Position[2])
$view[14]=[single]-($z[0]*$Position[0]+$z[1]*$Position[1]+$z[2]*$Position[2])
$view[15]=1
$yScale = 1 / [Math]::Tan($FieldOfView * [Math]::PI / 360)
$xScale = $yScale / $AspectRatio
$range = $FarPlane / ($FarPlane - $NearPlane)
$projection = [single[]]::new(16)
$projection[0]=[single]$xScale
$projection[5]=[single]$yScale
$projection[10]=[single]$range
$projection[11]=1
$projection[14]=[single](-$NearPlane*$range)
$viewProjection = [single[]]::new(16)
for ($row=0;$row-lt 4;$row++) {
    for ($column=0;$column-lt 4;$column++) {
        $sum=0.0
        for ($k=0;$k-lt 4;$k++) { $sum += $view[$row*4+$k]*$projection[$k*4+$column] }
        $viewProjection[$row*4+$column]=[single]$sum
    }
}

[PSCustomObject]@{
    PSTypeName='QuickPS.Camera3D'
    Position=[single[]]$Position
    Target=[single[]]$Target
    Up=[single[]]$Up
    FieldOfView=$FieldOfView
    AspectRatio=$AspectRatio
    NearPlane=$NearPlane
    FarPlane=$FarPlane
    View=$view
    Projection=$projection
    ViewProjection=$viewProjection
}

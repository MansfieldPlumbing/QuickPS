$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src'))

function Test-MeshFaces {
    param($Mesh, [switch] $GroundPlane, [switch] $Torus)
    $badIndices = 0
    $degenerate = 0
    $inward = 0
    for ($at = 0; $at -lt $Mesh.IndexCount; $at += 3) {
        $indices = for ($corner = 0; $corner -lt 3; $corner++) {
            [BitConverter]::ToUInt16($Mesh.IndexBytes, ($at + $corner) * 2)
        }
        if (($indices | Measure-Object -Maximum).Maximum -ge $Mesh.VertexCount) {
            $badIndices++
            continue
        }
        $p = foreach ($index in $indices) {
            $byte = $index * $Mesh.VertexStride
            ,@([BitConverter]::ToSingle($Mesh.VertexBytes,$byte),
                [BitConverter]::ToSingle($Mesh.VertexBytes,$byte+4),
                [BitConverter]::ToSingle($Mesh.VertexBytes,$byte+8))
        }
        $ax=$p[1][0]-$p[0][0]; $ay=$p[1][1]-$p[0][1]; $az=$p[1][2]-$p[0][2]
        $bx=$p[2][0]-$p[0][0]; $by=$p[2][1]-$p[0][1]; $bz=$p[2][2]-$p[0][2]
        $nx=$ay*$bz-$az*$by; $ny=$az*$bx-$ax*$bz; $nz=$ax*$by-$ay*$bx
        $areaSquared=$nx*$nx+$ny*$ny+$nz*$nz
        if ($areaSquared -lt 1e-10) { $degenerate++; continue }
        if ($Torus) {
            $radialLength=[Math]::Sqrt($cx*$cx+$cz*$cz)
            $tubeX=$cx-0.72*$cx/$radialLength
            $tubeZ=$cz-0.72*$cz/$radialLength
            if($nx*$tubeX+$ny*$cy+$nz*$tubeZ-le 0){$inward++}
        }
        elseif ($GroundPlane) {
            if ($ny -le 0) { $inward++ }
        }
        else {
            $cx=($p[0][0]+$p[1][0]+$p[2][0])/3
            $cy=($p[0][1]+$p[1][1]+$p[2][1])/3
            $cz=($p[0][2]+$p[1][2]+$p[2][2])/3
            if ($nx*$cx+$ny*$cy+$nz*$cz -le 0) { $inward++ }
        }
    }
    if ($badIndices -or $degenerate -or $inward) {
        throw "$($Mesh.Shape) face gate failed: badIndices=$badIndices degenerate=$degenerate inward=$inward"
    }
    [PSCustomObject]@{ Shape=$Mesh.Shape; Triangles=$Mesh.IndexCount/3; BadIndices=0; Degenerate=0; Inward=0; Passed=$true }
}

function Assert-SamePosition {
    param($Mesh,[int]$A,[int]$B)
    for($byte=0;$byte-lt 12;$byte++) {
        if($Mesh.VertexBytes[$A*$Mesh.VertexStride+$byte] -ne $Mesh.VertexBytes[$B*$Mesh.VertexStride+$byte]) {
            throw "$($Mesh.Shape) seam vertices $A and $B differ at position byte $byte."
        }
    }
}

$box = & (Join-Path $root 'Geometry3D.ps1') Box

if ($box.Shape -ne 'Box') { throw 'Wrong shape.' }
if ($box.VertexCount -ne 24 -or $box.VertexBytes.Length -ne 576) { throw 'Wrong vertex payload.' }
if ($box.VertexStride -ne 24) { throw 'Wrong vertex stride.' }
if ($box.IndexCount -ne 36 -or $box.IndexBytes.Length -ne 72) { throw 'Wrong index payload.' }
if ($box.IndexFormat -ne 57) { throw 'Wrong DXGI index format.' }
$plane = & (Join-Path $root 'Geometry3D.ps1') Plane
if ($plane.VertexCount -ne 4 -or $plane.VertexBytes.Length -ne 96) { throw 'Wrong plane vertex payload.' }
if ($plane.IndexCount -ne 6 -or $plane.IndexBytes.Length -ne 12) { throw 'Wrong plane index payload.' }
$sphere = & (Join-Path $root 'Geometry3D.ps1') Sphere
if ($sphere.VertexCount -ne 425 -or $sphere.VertexBytes.Length -ne 10200) { throw 'Wrong sphere vertex payload.' }
if ($sphere.IndexCount -ne 2160 -or $sphere.IndexBytes.Length -ne 4320) { throw 'Wrong sphere index payload.' }
$cylinder = & (Join-Path $root 'Geometry3D.ps1') Cylinder
if ($cylinder.VertexCount -ne 102 -or $cylinder.VertexBytes.Length -ne 2448) { throw 'Wrong cylinder vertex payload.' }
if ($cylinder.IndexCount -ne 288 -or $cylinder.IndexBytes.Length -ne 576) { throw 'Wrong cylinder index payload.' }
$cone = & (Join-Path $root 'Geometry3D.ps1') Cone
if ($cone.VertexCount -ne 52 -or $cone.VertexBytes.Length -ne 1248) { throw 'Wrong cone vertex payload.' }
if ($cone.IndexCount -ne 144 -or $cone.IndexBytes.Length -ne 288) { throw 'Wrong cone index payload.' }
$torus = & (Join-Path $root 'Geometry3D.ps1') Torus
if ($torus.VertexCount -ne 425 -or $torus.VertexBytes.Length -ne 10200) { throw 'Wrong torus vertex payload.' }
if ($torus.IndexCount -ne 2304 -or $torus.IndexBytes.Length -ne 4608) { throw 'Wrong torus index payload.' }
$capsule = & (Join-Path $root 'Geometry3D.ps1') Capsule
if ($capsule.VertexCount -ne 425 -or $capsule.VertexBytes.Length -ne 10200) { throw 'Wrong capsule vertex payload.' }
if ($capsule.IndexCount -ne 2160 -or $capsule.IndexBytes.Length -ne 4320) { throw 'Wrong capsule index payload.' }
$null = Test-MeshFaces $box
$null = Test-MeshFaces $plane -GroundPlane
$null = Test-MeshFaces $sphere
$null = Test-MeshFaces $cylinder
$null = Test-MeshFaces $cone
$null = Test-MeshFaces $torus -Torus
$null = Test-MeshFaces $capsule
for($ring=0;$ring-le $sphere.Rings;$ring++) {
    Assert-SamePosition $sphere ($ring*($sphere.Segments+1)) ($ring*($sphere.Segments+1)+$sphere.Segments)
}
Assert-SamePosition $cylinder 0 ($cylinder.Segments*2)
Assert-SamePosition $cylinder 1 ($cylinder.Segments*2+1)
$cylinderTopCenter=2*($cylinder.Segments+1)
$cylinderBottomCenter=$cylinderTopCenter+$cylinder.Segments+2
Assert-SamePosition $cylinder ($cylinderTopCenter+1) ($cylinderTopCenter+1+$cylinder.Segments)
Assert-SamePosition $cylinder ($cylinderBottomCenter+1) ($cylinderBottomCenter+1+$cylinder.Segments)
Assert-SamePosition $cone 1 (1+$cone.Segments)
$coneBaseCenter=$cone.Segments+2
Assert-SamePosition $cone ($coneBaseCenter+1) ($coneBaseCenter+1+$cone.Segments)
for($ring=0;$ring-le $torus.Rings;$ring++) {
    Assert-SamePosition $torus ($ring*($torus.Segments+1)) ($ring*($torus.Segments+1)+$torus.Segments)
}
for($segment=0;$segment-le $torus.Segments;$segment++) {
    Assert-SamePosition $torus $segment ($torus.Rings*($torus.Segments+1)+$segment)
}
for($ring=0;$ring-le $capsule.Rings;$ring++) {
    Assert-SamePosition $capsule ($ring*($capsule.Segments+1)) ($ring*($capsule.Segments+1)+$capsule.Segments)
}

[PSCustomObject]@{
    Shape = $box.Shape
    Vertices = $box.VertexCount
    Indices = $box.IndexCount
    VertexBytes = $box.VertexBytes.Length
    IndexBytes = $box.IndexBytes.Length
    Passed = $true
}
[PSCustomObject]@{
    Shape = $sphere.Shape
    Vertices = $sphere.VertexCount
    Indices = $sphere.IndexCount
    Segments = $sphere.Segments
    Rings = $sphere.Rings
    Passed = $true
}
[PSCustomObject]@{
    Shape = $cylinder.Shape
    Vertices = $cylinder.VertexCount
    Indices = $cylinder.IndexCount
    Segments = $cylinder.Segments
    Passed = $true
}
[PSCustomObject]@{
    Shape = $cone.Shape
    Vertices = $cone.VertexCount
    Indices = $cone.IndexCount
    Segments = $cone.Segments
    Passed = $true
}
[PSCustomObject]@{
    Shape = $torus.Shape
    Vertices = $torus.VertexCount
    Indices = $torus.IndexCount
    Segments = $torus.Segments
    Rings = $torus.Rings
    Passed = $true
}
[PSCustomObject]@{
    Shape = $capsule.Shape
    Vertices = $capsule.VertexCount
    Indices = $capsule.IndexCount
    Segments = $capsule.Segments
    Rings = $capsule.Rings
    Passed = $true
}
[PSCustomObject]@{
    Shape = $plane.Shape
    Vertices = $plane.VertexCount
    Indices = $plane.IndexCount
    VertexBytes = $plane.VertexBytes.Length
    IndexBytes = $plane.IndexBytes.Length
    Passed = $true
}

[CmdletBinding()]
param(
    [ValidateSet('Box', 'Plane', 'Sphere', 'Cylinder', 'Cone', 'Torus', 'Capsule')]
    [string] $Shape = 'Box',
    [single] $Size = 2.0,
    [ValidateRange(3, 128)]
    [int] $Segments = 24,
    [ValidateRange(2, 128)]
    [int] $Rings = 16
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Geometry3D.ps1 must be invoked with &, not dot-sourced.'
}

$half = $Size / 2
if ($Shape -eq 'Capsule') {
    $vertexCount=($Rings+1)*($Segments+1)
    if($vertexCount-gt [uint16]::MaxValue){throw 'Capsule exceeds the R16_UINT vertex limit.'}
    $vertices=[single[]]::new($vertexCount*6)
    $radius=$half*0.5;$halfBody=$half-$radius
    for($ring=0;$ring-le $Rings;$ring++){
        $latitude=[Math]::PI*$ring/$Rings;$normalY=[Math]::Cos($latitude);$radial=[Math]::Sin($latitude)
        $bodyOffset=if($normalY-gt 0){$halfBody}elseif($normalY-lt 0){-$halfBody}else{0}
        for($segment=0;$segment-le $Segments;$segment++){
            $longitude=if($segment-eq $Segments){0.0}else{2*[Math]::PI*$segment/$Segments}
            $normalX=$radial*[Math]::Cos($longitude);$normalZ=$radial*[Math]::Sin($longitude)
            $at=($ring*($Segments+1)+$segment)*6
            $vertices[$at]=[single]($normalX*$radius)
            $vertices[$at+1]=[single]($normalY*$radius+$bodyOffset)
            $vertices[$at+2]=[single]($normalZ*$radius)
            $vertices[$at+3]=0.20;$vertices[$at+4]=[single](0.48+0.32*($normalY+1)/2);$vertices[$at+5]=0.92
        }
    }
    $indexCount=($Rings-1)*$Segments*6;$indices=[uint16[]]::new($indexCount);$at=0
    for($ring=0;$ring-lt $Rings;$ring++){for($segment=0;$segment-lt $Segments;$segment++){
        $top=[uint16]($ring*($Segments+1)+$segment);$bottom=[uint16](($ring+1)*($Segments+1)+$segment)
        if($ring-gt 0){$indices[$at++]=$top;$indices[$at++]=$top+1;$indices[$at++]=$bottom}
        if($ring-lt $Rings-1){$indices[$at++]=$bottom;$indices[$at++]=$top+1;$indices[$at++]=$bottom+1}
    }}
}
elseif ($Shape -eq 'Torus') {
    $vertexCount=($Rings+1)*($Segments+1)
    if($vertexCount-gt [uint16]::MaxValue){throw 'Torus exceeds the R16_UINT vertex limit.'}
    $vertices=[single[]]::new($vertexCount*6)
    $major=$half*0.72; $minor=$half*0.28
    for($ring=0;$ring-le $Rings;$ring++) {
        $v=if($ring-eq $Rings){0.0}else{2*[Math]::PI*$ring/$Rings}
        for($segment=0;$segment-le $Segments;$segment++) {
            $u=if($segment-eq $Segments){0.0}else{2*[Math]::PI*$segment/$Segments}
            $radius=$major+$minor*[Math]::Cos($v)
            $at=($ring*($Segments+1)+$segment)*6
            $vertices[$at]=[single]($radius*[Math]::Cos($u))
            $vertices[$at+1]=[single]($minor*[Math]::Sin($v))
            $vertices[$at+2]=[single]($radius*[Math]::Sin($u))
            $vertices[$at+3]=[single](0.20+0.55*($ring/$Rings))
            $vertices[$at+4]=0.42
            $vertices[$at+5]=[single](0.95-0.45*($ring/$Rings))
        }
    }
    $indexCount=$Rings*$Segments*6
    $indices=[uint16[]]::new($indexCount)
    $at=0
    for($ring=0;$ring-lt $Rings;$ring++) {
        for($segment=0;$segment-lt $Segments;$segment++) {
            $a=[uint16]($ring*($Segments+1)+$segment)
            $b=[uint16](($ring+1)*($Segments+1)+$segment)
            $indices[$at++]=$a; $indices[$at++]=$b; $indices[$at++]=$a+1
            $indices[$at++]=$b; $indices[$at++]=$b+1; $indices[$at++]=$a+1
        }
    }
}
elseif ($Shape -eq 'Cone') {
    $vertexCount = 2 * $Segments + 4
    $vertices = [single[]]::new($vertexCount * 6)
    # Side apex followed by a closed rim; the base uses separate vertices.
    $vertices[1]=[single]$half; $vertices[3]=1.0; $vertices[4]=0.42; $vertices[5]=0.12
    for ($segment=0;$segment-le $Segments;$segment++) {
        $angle=if($segment-eq $Segments){0.0}else{2*[Math]::PI*$segment/$Segments}
        $vertex=1+$segment; $at=$vertex*6
        $vertices[$at]=[single]([Math]::Cos($angle)*$half)
        $vertices[$at+1]=[single]-$half
        $vertices[$at+2]=[single]([Math]::Sin($angle)*$half)
        $vertices[$at+3]=1.0; $vertices[$at+4]=0.42; $vertices[$at+5]=0.12
    }
    $baseCenter=$Segments+2
    $vertices[$baseCenter*6+1]=[single]-$half
    $vertices[$baseCenter*6+3]=0.12; $vertices[$baseCenter*6+4]=0.72; $vertices[$baseCenter*6+5]=0.28
    for ($segment=0;$segment-le $Segments;$segment++) {
        $angle=if($segment-eq $Segments){0.0}else{2*[Math]::PI*$segment/$Segments}
        $vertex=$baseCenter+1+$segment; $at=$vertex*6
        $vertices[$at]=[single]([Math]::Cos($angle)*$half)
        $vertices[$at+1]=[single]-$half
        $vertices[$at+2]=[single]([Math]::Sin($angle)*$half)
        $vertices[$at+3]=0.12; $vertices[$at+4]=0.72; $vertices[$at+5]=0.28
    }
    $indexCount=$Segments*6
    $indices=[uint16[]]::new($indexCount)
    $at=0
    for ($segment=0;$segment-lt $Segments;$segment++) {
        $indices[$at++]=0; $indices[$at++]=[uint16]($segment+2); $indices[$at++]=[uint16]($segment+1)
        $indices[$at++]=[uint16]$baseCenter; $indices[$at++]=[uint16]($baseCenter+1+$segment); $indices[$at++]=[uint16]($baseCenter+2+$segment)
    }
}
elseif ($Shape -eq 'Cylinder') {
    $vertexCount = 4 * ($Segments + 1) + 2
    $vertices = [single[]]::new($vertexCount * 6)
    for ($segment = 0; $segment -le $Segments; $segment++) {
        $angle = if ($segment -eq $Segments) { 0.0 } else { 2 * [Math]::PI * $segment / $Segments }
        $x = [Math]::Cos($angle) * $half
        $z = [Math]::Sin($angle) * $half
        foreach ($row in 0,1) {
            $vertex = $segment * 2 + $row
            $at = $vertex * 6
            $vertices[$at] = [single]$x
            $vertices[$at + 1] = if ($row -eq 0) { $half } else { -$half }
            $vertices[$at + 2] = [single]$z
            $vertices[$at + 3] = [single](0.15 + 0.25 * ([Math]::Cos($angle) + 1))
            $vertices[$at + 4] = [single](0.55 + 0.20 * ([Math]::Sin($angle) + 1))
            $vertices[$at + 5] = 0.88
        }
    }
    $topCenter = 2 * ($Segments + 1)
    $bottomCenter = $topCenter + $Segments + 2
    foreach ($cap in 0,1) {
        $center = if ($cap -eq 0) { $topCenter } else { $bottomCenter }
        $centerAt = $center * 6
        $vertices[$centerAt + 1] = if ($cap -eq 0) { $half } else { -$half }
        $vertices[$centerAt + 3] = 0.12
        $vertices[$centerAt + 4] = if ($cap -eq 0) { 0.82 } else { 0.42 }
        $vertices[$centerAt + 5] = 0.38
        for ($segment = 0; $segment -le $Segments; $segment++) {
            $angle = if ($segment -eq $Segments) { 0.0 } else { 2 * [Math]::PI * $segment / $Segments }
            $vertex = $center + 1 + $segment
            $at = $vertex * 6
            $vertices[$at] = [single]([Math]::Cos($angle) * $half)
            $vertices[$at + 1] = if ($cap -eq 0) { $half } else { -$half }
            $vertices[$at + 2] = [single]([Math]::Sin($angle) * $half)
            $vertices[$at + 3] = $vertices[$centerAt + 3]
            $vertices[$at + 4] = $vertices[$centerAt + 4]
            $vertices[$at + 5] = $vertices[$centerAt + 5]
        }
    }
    $indexCount = $Segments * 12
    $indices = [uint16[]]::new($indexCount)
    $at = 0
    for ($segment = 0; $segment -lt $Segments; $segment++) {
        $top = [uint16]($segment * 2)
        $bottom = [uint16]($top + 1)
        $nextTop = [uint16]($top + 2)
        $nextBottom = [uint16]($top + 3)
        $indices[$at++]=$top; $indices[$at++]=$nextTop; $indices[$at++]=$bottom
        $indices[$at++]=$bottom; $indices[$at++]=$nextTop; $indices[$at++]=$nextBottom
        $indices[$at++]=$topCenter; $indices[$at++]=[uint16]($topCenter+2+$segment); $indices[$at++]=[uint16]($topCenter+1+$segment)
        $indices[$at++]=$bottomCenter; $indices[$at++]=[uint16]($bottomCenter+1+$segment); $indices[$at++]=[uint16]($bottomCenter+2+$segment)
    }
}
elseif ($Shape -eq 'Sphere') {
    $vertexCount = ($Rings + 1) * ($Segments + 1)
    if ($vertexCount -gt [uint16]::MaxValue) { throw 'Sphere exceeds the R16_UINT vertex limit.' }
    $vertices = [single[]]::new($vertexCount * 6)
    for ($ring = 0; $ring -le $Rings; $ring++) {
        $latitude = [Math]::PI * $ring / $Rings
        $y = [Math]::Cos($latitude)
        $radius = [Math]::Sin($latitude)
        for ($segment = 0; $segment -le $Segments; $segment++) {
            $longitude = if ($segment -eq $Segments) { 0.0 } else { 2 * [Math]::PI * $segment / $Segments }
            $x = $radius * [Math]::Cos($longitude)
            $z = $radius * [Math]::Sin($longitude)
            $at = ($ring * ($Segments + 1) + $segment) * 6
            $vertices[$at] = [single]($x * $half)
            $vertices[$at + 1] = [single]($y * $half)
            $vertices[$at + 2] = [single]($z * $half)
            $vertices[$at + 3] = [single](0.15 + 0.25 * ($x + 1))
            $vertices[$at + 4] = [single](0.35 + 0.45 * ($y + 1) / 2)
            $vertices[$at + 5] = [single](0.55 + 0.35 * ($z + 1) / 2)
        }
    }
    $indexCount = ($Rings - 1) * $Segments * 6
    $indices = [uint16[]]::new($indexCount)
    $at = 0
    for ($ring = 0; $ring -lt $Rings; $ring++) {
        for ($segment = 0; $segment -lt $Segments; $segment++) {
            $top = [uint16]($ring * ($Segments + 1) + $segment)
            $bottom = [uint16](($ring + 1) * ($Segments + 1) + $segment)
            if ($ring -gt 0) {
                $indices[$at++] = $top
                $indices[$at++] = $top + 1
                $indices[$at++] = $bottom
            }
            if ($ring -lt $Rings - 1) {
                $indices[$at++] = $bottom
                $indices[$at++] = $top + 1
                $indices[$at++] = $bottom + 1
            }
        }
    }
}
else {
$positions = if ($Shape -eq 'Plane') { [single[]]@(
    -$half,0,-$half,  $half,0,-$half,  $half,0,$half,  -$half,0,$half
) } else { [single[]]@(
    -$half,-$half,-$half,  $half,-$half,-$half,  $half,$half,-$half, -$half,$half,-$half,
     $half,-$half,-$half,  $half,-$half,$half,   $half,$half,$half,   $half,$half,-$half,
     $half,-$half,$half,  -$half,-$half,$half,  -$half,$half,$half,  $half,$half,$half,
    -$half,-$half,$half,  -$half,-$half,-$half, -$half,$half,-$half, -$half,$half,$half,
    -$half,$half,-$half,   $half,$half,-$half,   $half,$half,$half,  -$half,$half,$half,
    -$half,-$half,$half,   $half,-$half,$half,   $half,-$half,-$half,-$half,-$half,-$half
) }
$faceColors = [single[]]@(
    0.05,0.55,1.00, 0.00,0.85,0.70, 0.55,0.25,1.00,
    1.00,0.35,0.25, 1.00,0.75,0.10, 0.20,0.90,0.35
)
$vertexCount = if ($Shape -eq 'Plane') { 4 } else { 24 }
$vertices = [single[]]::new($vertexCount * 6)
for ($vertex = 0; $vertex -lt $vertexCount; $vertex++) {
    [Array]::Copy($positions, $vertex * 3, $vertices, $vertex * 6, 3)
    if ($Shape -eq 'Plane') {
        [Array]::Copy([single[]]@(0.10,0.78,0.32), 0, $vertices, $vertex * 6 + 3, 3)
    }
    else {
        [Array]::Copy($faceColors, [Math]::Floor($vertex / 4) * 3, $vertices, $vertex * 6 + 3, 3)
    }
}
$indexCount = if ($Shape -eq 'Plane') { 6 } else { 36 }
$indices = [uint16[]]::new($indexCount)
for ($face = 0; $face -lt ($indexCount / 6); $face++) {
    $first = [uint16]($face * 4)
    $at = $face * 6
    $indices[$at] = $first
    $indices[$at + 1] = $first + 2
    $indices[$at + 2] = $first + 1
    $indices[$at + 3] = $first
    $indices[$at + 4] = $first + 3
    $indices[$at + 5] = $first + 2
}
}
$vertexBytes = [byte[]]::new($vertices.Length * 4)
$indexBytes = [byte[]]::new($indices.Length * 2)
[Buffer]::BlockCopy($vertices, 0, $vertexBytes, 0, $vertexBytes.Length)
[Buffer]::BlockCopy($indices, 0, $indexBytes, 0, $indexBytes.Length)

[PSCustomObject]@{
    PSTypeName = 'QuickPS.Geometry3D'
    Shape = $Shape
    VertexBytes = $vertexBytes
    VertexCount = $vertexCount
    VertexStride = 24
    IndexBytes = $indexBytes
    IndexCount = $indexCount
    IndexFormat = 57
    Segments = if ($Shape -in @('Sphere','Cylinder','Cone','Torus','Capsule')) { $Segments } else { $null }
    Rings = if ($Shape -in @('Sphere','Torus','Capsule')) { $Rings } else { $null }
}

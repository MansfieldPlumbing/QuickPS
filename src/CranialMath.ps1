[CmdletBinding()]
param(
    [ValidateRange(0,1)][single] $SmoothAlpha = 0.35,
    [ValidateRange(0,3600)][double] $HoldTimeoutSeconds = 2.5
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'CranialMath.ps1 must be invoked with &, not dot-sourced.'
}

$instance = [PSCustomObject]@{
    PSTypeName         = 'QuickPS.CranialMath'
    SmoothAlpha        = $SmoothAlpha
    HoldTimeoutSeconds = $HoldTimeoutSeconds
    HasTracking        = $false
    LastValidTime      = [DateTime]::MinValue
    SmoothedX          = 0.0
    SmoothedY          = 0.0
    SmoothedZ          = -5.0
    SmoothedYaw        = 0.0
    SmoothedPitch      = 0.0
    SmoothedRoll       = 0.0
    SmoothedScale      = 1.0
}

$instance | Add-Member ScriptMethod Reset ({
    $this.HasTracking = $false
    $this.LastValidTime = [DateTime]::MinValue
    $this.SmoothedX = 0.0
    $this.SmoothedY = 0.0
    $this.SmoothedZ = -5.0
    $this.SmoothedYaw = 0.0
    $this.SmoothedPitch = 0.0
    $this.SmoothedRoll = 0.0
    $this.SmoothedScale = 1.0
}.GetNewClosure())

$instance | Add-Member ScriptMethod Solve ({
    param(
        [PSCustomObject] $Keypoints,
        [int] $ImageWidth = 1280,
        [int] $ImageHeight = 720,
        [single] $OffsetX = 0.0,
        [single] $OffsetY = 0.0,
        [single] $OffsetZ = 0.0,
        [single] $Scale = 1.0,
        [single] $PitchKnob = 0.0,
        [single] $YawKnob = 0.0,
        [single] $RollKnob = 0.0
    )

    $now = [DateTime]::UtcNow
    if($ImageWidth -le 0 -or $ImageHeight -le 0){throw 'Image dimensions must be positive.'}
    foreach($value in @($OffsetX,$OffsetY,$OffsetZ,$Scale,$PitchKnob,$YawKnob,$RollKnob)){
        if([single]::IsNaN($value) -or [single]::IsInfinity($value)){throw 'Transform inputs must be finite.'}
    }
    if($Keypoints){
        foreach($name in @('LeftEye','RightEye','Nose')){
            $property=$Keypoints.PSObject.Properties[$name]
            if($property -and $null -ne $property.Value){
                if($property.Value.Count -ne 2){throw 'A landmark must contain two coordinates.'}
                foreach($coordinate in $property.Value){if([double]::IsNaN($coordinate) -or [double]::IsInfinity($coordinate)){throw 'Landmarks must be finite.'}}
            }
        }
    }
    $isValid = $null -ne $Keypoints -and $null -ne $Keypoints.LeftEye -and $null -ne $Keypoints.RightEye

    if ($isValid) {
        $this.LastValidTime = $now
        $this.HasTracking = $true

        $lx = [double]$Keypoints.LeftEye[0]
        $ly = [double]$Keypoints.LeftEye[1]
        $rx = [double]$Keypoints.RightEye[0]
        $ry = [double]$Keypoints.RightEye[1]

        # 1. Inter-Pupillary Distance (IPD)
        $dx = $rx - $lx
        $dy = $ry - $ly
        $ipd = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($ipd -lt 1.0) { $ipd = 1.0 }

        # 2. Eye Midpoint
        $midX = ($lx + $rx) * 0.5
        $midY = ($ly + $ry) * 0.5

        # 3. Roll angle
        $roll = [Math]::Atan2($dy, $dx)

        # 4. Yaw & Pitch from nose if available
        $yaw = 0.0
        $pitch = 0.0
        if ($null -ne $Keypoints.Nose) {
            $nx = [double]$Keypoints.Nose[0]
            $ny = [double]$Keypoints.Nose[1]
            $yaw = (($nx - $midX) / $ipd) * 1.3
            $pitch = ((($ny - $midY) / $ipd) - 0.72) * 1.5
        }

        # 5. Estimated 3D position
        # Normalized Device Coords (-1 to +1)
        $ndcX = ($midX - ($ImageWidth * 0.5)) / ($ImageWidth * 0.5)
        $ndcY = -(($midY - ($ImageHeight * 0.5)) / ($ImageHeight * 0.5))
        
        # Approximate focal-depth relationship: larger IPD = closer to camera
        $rawZ = -[Math]::Min(15.0, [Math]::Max(1.5, (180.0 / $ipd)))
        $rawX = $ndcX * [Math]::Abs($rawZ) * 0.55
        $rawY = $ndcY * [Math]::Abs($rawZ) * 0.55

        # 6. Exponential Moving Average Filter
        $a = $this.SmoothAlpha
        $this.SmoothedX += $a * ($rawX - $this.SmoothedX)
        $this.SmoothedY += $a * ($rawY - $this.SmoothedY)
        $this.SmoothedZ += $a * ($rawZ - $this.SmoothedZ)
        $this.SmoothedYaw += $a * ($yaw - $this.SmoothedYaw)
        $this.SmoothedPitch += $a * ($pitch - $this.SmoothedPitch)
        $this.SmoothedRoll += $a * ($roll - $this.SmoothedRoll)
    }
    else {
        # Check pose hold timeout
        $elapsed = ($now - $this.LastValidTime).TotalSeconds
        if ($elapsed -gt $this.HoldTimeoutSeconds) {
            $this.HasTracking = $false
        }
    }

    # Combined Euler angles (Tracking + Manual Knobs in radians)
    $finalPitch = $this.SmoothedPitch + ($PitchKnob * [Math]::PI / 180.0)
    $finalYaw   = $this.SmoothedYaw + ($YawKnob * [Math]::PI / 180.0)
    $finalRoll  = $this.SmoothedRoll + ($RollKnob * [Math]::PI / 180.0)

    # Combined Position & Scale
    $posX = [single]($this.SmoothedX + $OffsetX)
    $posY = [single]($this.SmoothedY + $OffsetY)
    $posZ = [single]($this.SmoothedZ + $OffsetZ)
    $s    = [single]($Scale * 0.12) # Legacy model-unit conversion; this is an uncalibrated estimate.

    # Synthesize 4x4 row-major transform matrix
    $cp = [Math]::Cos($finalPitch); $sp = [Math]::Sin($finalPitch)
    $cy = [Math]::Cos($finalYaw);   $sy = [Math]::Sin($finalYaw)
    $cr = [Math]::Cos($finalRoll);  $sr = [Math]::Sin($finalRoll)

    # Combined Rotation Matrix R = Rz * Rx * Ry
    $m = [single[]]::new(16)
    $m[0]  = [single]($s * ($cy * $cr + $sy * $sp * $sr))
    $m[1]  = [single]($s * ($sr * $cp))
    $m[2]  = [single]($s * (-$sy * $cr + $cy * $sp * $sr))
    $m[3]  = 0.0

    $m[4]  = [single]($s * (-$cy * $sr + $sy * $sp * $cr))
    $m[5]  = [single]($s * ($cr * $cp))
    $m[6]  = [single]($s * ($sr * $sy + $cy * $sp * $cr))
    $m[7]  = 0.0

    $m[8]  = [single]($s * ($sy * $cp))
    $m[9]  = [single]($s * (-$sp))
    $m[10] = [single]($s * ($cy * $cp))
    $m[11] = 0.0

    $m[12] = $posX
    $m[13] = $posY
    $m[14] = $posZ
    $m[15] = 1.0

    [PSCustomObject]@{
        PSTypeName     = 'QuickPS.CranialPose'
        IsTracking     = $this.HasTracking
        ModelMatrix    = $m
        Position       = @($posX, $posY, $posZ)
        EulerDegrees   = @([single]($finalPitch * 180.0 / [Math]::PI), [single]($finalYaw * 180.0 / [Math]::PI), [single]($finalRoll * 180.0 / [Math]::PI))
    }
}.GetNewClosure())

$instance

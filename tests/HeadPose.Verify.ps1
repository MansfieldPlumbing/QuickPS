[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$estimate=& (Join-Path $PSScriptRoot '..\src\HeadPose.ps1') -SmoothAlpha 1
$keys=[pscustomobject]@{LeftEye=@(580,320);RightEye=@(700,320);Nose=@(640,406.4)}
$result=$estimate.Solve($keys,1280,720)
if(-not $result.IsTracking -or $result.ModelMatrix.Count -ne 16 -or $result.ModelMatrix[15] -ne 1){throw 'Estimate shape or homogeneous coordinate differs.'}
if([Math]::Abs($result.Position[0]) -gt 0.00001 -or [Math]::Abs($result.Position[2]+1.5) -gt 0.00001){throw 'Centered landmark/depth clamp vector differs.'}
foreach($value in $result.ModelMatrix){if([single]::IsNaN($value) -or [single]::IsInfinity($value)){throw 'Nonfinite estimated transform.'}}
$rejected=$false;try{$null=$estimate.Solve($keys,0,720)}catch{$rejected=$true}
if(-not $rejected){throw 'Zero image width accepted.'}
$estimate.LastValidTime=[DateTime]::UtcNow.AddSeconds(-10)
if($estimate.Solve($null,1280,720).IsTracking){throw 'Expired estimate retained tracking state.'}
$estimate.Reset()
if($estimate.HasTracking){throw 'Reset retained tracking state.'}
'PASS: synthetic landmark vectors, dimension rejection, expiration and reset. Physical pose accuracy is not established.'

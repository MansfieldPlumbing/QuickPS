[CmdletBinding()]
param([ValidateSet('Box','Plane','Sphere','Cylinder','Cone','Torus','Capsule')][string]$Shape='Box',[switch]$Verify)
& (Join-Path $PSScriptRoot '..\tests\Scene3D.ps1') -Shape $Shape -Seconds $(if($Verify){4}else{0})

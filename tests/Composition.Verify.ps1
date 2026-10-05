[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$device=$composition=$window=$null
try {
    $device=& (Join-Path $PSScriptRoot '..\src\D3D11.Windows.ps1')
    $composition=& (Join-Path $PSScriptRoot '..\src\Composition.Windows.ps1') -DxgiDevice $device.DxgiDevice
    $window=& (Join-Path $PSScriptRoot '..\src\Window.Windows.ps1') -Width 320 -Height 240
    $target=$composition.CreateTargetForWindow($window.Hwnd)
    $visual=$composition.CreateVisual()
    $child=$composition.CreateVisual()
    $scale=$composition.CreateScaleTransform()
    $rotation=$composition.CreateRotateTransform()
    $animation=$composition.CreateAnimation()
    $composition.AddCubicSegment($animation,0,[single]0,[single]100,[single]0,[single]0)
    $composition.EndAnimation($animation,1,[single]100)
    $composition.SetScaleCenter($scale,[single]50,[single]50)
    $composition.SetScaleAnimation($scale,$animation)
    $composition.SetRotateCenter($rotation,[single]50,[single]50)
    $composition.SetRotateAnimation($rotation,$animation)
    $composition.SetVisualTransform($visual,$scale)
    $composition.SetVisualOffset($visual,[single]10,[single]20)
    $composition.SetVisualOffsetAnimation($child,'X',$animation)
    $composition.AddVisual($visual,$child)
    $composition.SetRoot($target,$visual)
    $null=$composition.Commit()
    $null=$composition.WaitForCommitCompletion()
    'PASS: D3D11 device, native composition hierarchy, finite animation, scale/rotation/offset binding and commit. Presented pixels not measured.'
}finally{
    if($composition){$composition.Dispose();$composition.Dispose()}
    if($window){$window.Dispose()}
    if($device){$device.Dispose();$device.Dispose()}
}

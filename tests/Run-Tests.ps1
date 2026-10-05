[CmdletBinding()]
param([switch]$Native,[switch]$Hardware,[string]$ResultDirectory=(Join-Path $PSScriptRoot '..\verification-results'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resultsPath=[IO.Path]::GetFullPath($ResultDirectory)
$null=[IO.Directory]::CreateDirectory($resultsPath)
$parseFiles=@(Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'gallery'),$PSScriptRoot,(Join-Path $root 'tools') -Recurse -File -Filter '*.ps1')
foreach($file in $parseFiles){
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Parse failed: $($file.Name): $($errors[0].Message)"}
}
$rows=[Collections.Generic.List[object]]::new()
function Invoke-Check([string]$Name,[string]$Path,[string[]]$Arguments=@(),[string]$SkipReason=''){
    if($SkipReason){$rows.Add([pscustomobject]@{Test=$Name;Result='NOT RUN';ExitCode=$null;Reason=$SkipReason});Write-Output "NOT RUN: $Name ($SkipReason)";return}
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=(Join-Path $PSHOME 'pwsh.exe')
    $info.WorkingDirectory=$root
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-NonInteractive','-File',$Path)+$Arguments){$info.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($info)
    $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
    try {
        if(-not $process.WaitForExit(60000)){$process.Kill($true);$process.WaitForExit();$result='TIMEOUT';$code=-1}
        else{$code=$process.ExitCode;$result=if($code -eq 0){'PASS'}else{'FAIL'}}
        $outText=$outTask.GetAwaiter().GetResult();$errText=$errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $resultsPath ($Name+'.log')),$outText+"`n"+$errText)
        if(($outText+$errText) -match '(?i)(malicious content|blocked by.*antivirus|AMSI.*(blocked|detected)|Behavior:Win32)'){throw 'Security detection: stop work and inspect the private log.'}
        $rows.Add([pscustomobject]@{Test=$Name;Result=$result;ExitCode=$code;Reason=''})
        Write-Output "$result`: $Name (exit $code)"
    }finally{$process.Dispose()}
}
$synthetic=Join-Path $resultsPath 'synthetic-silhouette.png'
if($Native){
    $null=[Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath((Join-Path $PSHOME 'System.Drawing.Common.dll'))
    $bitmap=[Drawing.Bitmap]::new(200,150)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $brush=[Drawing.SolidBrush]::new([Drawing.Color]::Lime)
    try{$graphics.Clear([Drawing.Color]::FromArgb(4,6,15));$graphics.FillRectangle($brush,30,40,140,70);$bitmap.Save($synthetic,[Drawing.Imaging.ImageFormat]::Png)}finally{$brush.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
$pure=@('Verify.ps1','Geometry3D.Verify.ps1','Camera3D.Verify.ps1','CranialMath.Verify.ps1','Gallery.Verify.ps1')
foreach($file in Get-ChildItem $PSScriptRoot -File -Filter '*.ps1' | Where-Object Name -NE 'Run-Tests.ps1' | Sort-Object Name){
    $arguments=@();$skip=''
    if($file.Name -notin $pure -and -not $Native){$skip='Requires Windows native services; pass -Native.'}
    switch($file.Name){
        'Show-Window.ps1' {$arguments=@('-Verify')}
        'ImageSilhouette.Verify.ps1' {$arguments=@('-Path',$synthetic)}
        'Record-Wasapi.ps1' {
            if(-not $Hardware){$skip='Explicit audio hardware check; pass -Hardware.'}
            $arguments=@('-Loopback','-Milliseconds','250','-OutputPath',(Join-Path $resultsPath 'audio-probe.wav'))
        }
        'Managed.Hardware.Verify.ps1' {if(-not $Hardware){$skip='Explicit audio hardware check; pass -Hardware.'}}
    }
    Invoke-Check $file.Name $file.FullName $arguments $skip
}
if($Native){
    foreach($sample in @('Window','WindowControls','Backdrop','Typography','SoundRecorder','WindowCapture')){
        Invoke-Check ('gallery-'+$sample) (Join-Path $root ('gallery\'+$sample+'.ps1')) @('-Verify')
    }
    Invoke-Check 'standalone-drift' (Join-Path $root 'tools\Build-Backdrop.ps1') @('-Check')
    Invoke-Check 'standalone-native' (Join-Path $root 'build\standalone\Backdrop.ps1') @('-Verify')
}
$rows | Export-Csv -LiteralPath (Join-Path $resultsPath 'results.csv')
if(@($rows | Where-Object Result -In @('FAIL','TIMEOUT')).Count){throw 'One or more verification checks failed; see per-test local logs.'}

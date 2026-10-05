[CmdletBinding()]
param([string]$AssemblyPath=(Join-Path $PSScriptRoot '..\build\managed\QuickPS.Windows.dll'),[string]$TracePath)
$ErrorActionPreference='Stop'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-Audio-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temporary)
$assembly=[Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath([IO.Path]::GetFullPath($AssemblyPath))
$native=$assembly.GetType('QuickPSWindows',$true)
$wait=$native.GetMethod('WaitOne')
try {
    $worker=& (Join-Path $PSScriptRoot '..\src\Capture.Windows.ps1') -AssemblyPath $AssemblyPath -OutputPath (Join-Path $temporary 'loopback.wav') -Loopback -Normalize
    try {
        if($TracePath){$worker.TracePath=[IO.Path]::GetFullPath($TracePath)}
        $worker.Thread.Start()
        if($wait.Invoke($null,@($worker.StartedEvent,[uint32]5000)) -ne 0){throw 'Audio initialization exceeded five seconds.'}
        if($worker.GetStatus() -eq 5){throw $worker.Failure}
        # Hardware-only event wake/format/Stop proof. No microphone activation.
        $worker.Pause();$worker.Resume();$worker.RequestStop();$worker.RequestStop()
        if(-not $worker.Thread.Join(5000)){throw 'Managed loopback Stop did not complete.'}
        if($worker.GetStatus() -ne 4){throw $worker.Failure}
        $bytes=[IO.File]::ReadAllBytes($worker.OutputPath)
        if([BitConverter]::ToUInt32($bytes,4) -ne $bytes.Length-8){throw 'Hardware RIFF finalization differs.'}
        'PASS: managed loopback endpoint activation, event-driven initialization, pause/resume signals, Stop and WAV finalization. Microphone and mixed-source capture not exercised.'
    }finally{if($worker.Thread.IsAlive){$worker.RequestStop();$null=$worker.Thread.Join(5000)};$worker.Dispose()}
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}

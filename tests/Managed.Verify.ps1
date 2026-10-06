[CmdletBinding()]
param([string]$AssemblyPath=(Join-Path $PSScriptRoot '..\build\managed\QuickPS.AudioCapture.dll'))
$ErrorActionPreference='Stop'
$assembly=[Runtime.Loader.AssemblyLoadContext]::Default.LoadFromAssemblyPath([IO.Path]::GetFullPath($AssemblyPath))
foreach($reference in $assembly.GetReferencedAssemblies()){
    if($reference.Name -match 'Management.Automation|Microsoft.CSharp'){throw 'Managed output depends on the PowerShell engine or C# dynamic binder.'}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-Managed-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($temp)
try {
    # Native event cancellation before and after Run begins, repeated lifetimes,
    # deterministic RIFF finalization, failed output creation, no microphone.
    for($i=0;$i -lt 6;$i++){
        $path=Join-Path $temp ('capture-'+$i+'.wav')
        $worker=& (Join-Path $PSScriptRoot '..\src\Capture.Windows.ps1') -AssemblyPath $AssemblyPath -OutputPath $path -Synthetic -Normalize
        try {
            if(($i % 2) -eq 0){$worker.RequestStop()}
            $worker.Thread.Start()
            $worker.Pause();$worker.Resume();$worker.RequestStop();$worker.RequestStop()
            if(-not $worker.Thread.Join(5000)){throw 'Synthetic stop did not complete within five seconds.'}
            if($worker.GetStatus() -ne 4){throw "Synthetic capture failed: $($worker.Failure)"}
            $bytes=[IO.File]::ReadAllBytes($path)
            if([Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'RIFF' -or [BitConverter]::ToUInt32($bytes,4) -ne $bytes.Length-8){throw 'RIFF finalization failed.'}
            if([BitConverter]::ToUInt32($bytes,$bytes.Length-4) -ne 0){throw 'Empty capture contains data.'}
        } finally {if($worker.Thread.IsAlive){$worker.RequestStop();$null=$worker.Thread.Join(5000)};$worker.Dispose();$worker.Dispose()}
    }
    $worker=& (Join-Path $PSScriptRoot '..\src\Capture.Windows.ps1') -AssemblyPath $AssemblyPath -OutputPath (Join-Path $temp 'absent\file.wav') -Synthetic
    try {
        $worker.Thread.Start()
        if(-not $worker.Thread.Join(5000) -or $worker.GetStatus() -ne 5){throw 'Failed output creation did not complete with failure.'}
    }finally{$worker.Dispose()}
    $wave=$assembly.GetType('QuickPSWave',$true)
    $native=$assembly.GetType('QuickPSAudioInterop',$true)
    $guidPointer=$native.GetMethod('GuidMemory').Invoke($null,@('9503DEBC2FE57C468E3DC4579291692E'))
    try{
        $actual=[byte[]]::new(16);[Runtime.InteropServices.Marshal]::Copy($guidPointer,$actual,0,16)
        $expected=([Guid]'bcde0395-e52f-467c-8e3d-c4579291692e').ToByteArray()
        if([Convert]::ToHexString($actual) -cne [Convert]::ToHexString($expected)){throw 'Managed native GUID byte layout differs.'}
    }finally{[Runtime.InteropServices.Marshal]::FreeHGlobal($guidPointer)}
    $extensible=[byte[]]::new(40)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]65534),0,$extensible,0,2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]32),0,$extensible,14,2)
    [Buffer]::BlockCopy(([Guid]'00000003-0000-0010-8000-00aa00389b71').ToByteArray(),0,$extensible,24,16)
    # @(,$array) passes the byte array as one argument; @($array) would unroll it.
    if($wave.GetMethod('SampleSize').Invoke($null,@(,$extensible)) -ne 4){throw 'Extensible float subtype not recognized.'}
    $extensible[24]=1
    if($wave.GetMethod('SampleSize').Invoke($null,@(,$extensible)) -ne 0){throw 'PCM32 misidentified as IEEE float.'}
    $worker=& (Join-Path $PSScriptRoot '..\src\Capture.Windows.ps1') -AssemblyPath $AssemblyPath -OutputPath (Join-Path $temp 'nonempty.wav') -Synthetic -Normalize
    try {
        $worker.SyntheticBytes=[byte[]]::new(96000)
        for($i=0;$i -lt $worker.SyntheticBytes.Length;$i+=2){[Buffer]::BlockCopy([BitConverter]::GetBytes([int16](-12000 + ($i % 24000))),0,$worker.SyntheticBytes,$i,2)}
        $worker.Thread.Start();$worker.RequestStop()
        if(-not $worker.Thread.Join(5000) -or $worker.GetStatus() -ne 4 -or -not $worker.Normalized -or $worker.BytesWritten -ne 96000){throw 'Nonempty synthetic Stop/normalization failed.'}
    }finally{if($worker.Thread.IsAlive){$worker.RequestStop();$null=$worker.Thread.Join(5000)};$worker.Dispose()}
    $format=[byte[]]::new(18)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]1),0,$format,0,2)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([uint16]16),0,$format,14,2)
    $path=Join-Path $temp 'vector.raw'
    [IO.File]::WriteAllBytes($path,[BitConverter]::GetBytes([int16]::MinValue))
    $file=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
    try {
        if(-not $wave.GetMethod('Normalize').Invoke($null,@($file,[long]0,[long]2,$format))){throw 'PCM16 minimum value was not normalized.'}
        $file.Position=0;$reader=[IO.BinaryReader]::new($file,[Text.Encoding]::UTF8,$true)
        try{if([Math]::Abs([int]$reader.ReadInt16()+29204) -gt 1){throw 'PCM16 normalization vector differs.'}}finally{$reader.Dispose()}
        $rejected=$false
        try{$null=$wave.GetMethod('Normalize').Invoke($null,@($file,[long]0,[long]3,$format))}catch{$rejected=$true}
        if(-not $rejected){throw 'Misaligned/truncated sample extent accepted.'}
    }finally{$file.Dispose()}
    'PASS: engine-independent assembly, native events, six Stop/dispose cycles, output failure, RIFF headers and PCM16 minimum-value normalization. Hardware capture not exercised.'
} finally {
    if(-not $temp.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected temporary path.'}
    Remove-Item -LiteralPath $temp -Recurse -Force
}

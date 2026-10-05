[CmdletBinding()]
param(
    [ValidateSet('Mic','Apps')][string]$Source='Mic',
    [string]$OutputDirectory=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)) 'Recordings'),
    [string]$AssemblyPath=$(if(Test-Path (Join-Path $PSScriptRoot '..\lib\QuickPS.Windows.dll')){Join-Path $PSScriptRoot '..\lib\QuickPS.Windows.dll'}else{Join-Path $PSScriptRoot '..\build\managed\QuickPS.Windows.dll'}),
    [switch]$NoNormalize,
    [string]$ScreenshotPath,
    [switch]$Verify
)
if ($MyInvocation.InvocationName -eq '.') { throw 'SoundRecorder.ps1 must be invoked with &, not dot-sourced.' }
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath $AssemblyPath)){throw 'Build managed capabilities with tools/Build-Managed.ps1 first, or pass -AssemblyPath from the DLL release.'}
$ui=$null
$commonControls=[IntPtr]::Zero
$state=@{Worker=$null;Paused=$false;Source=$Source;Status=[IntPtr]::Zero;Meter=[IntPtr]::Zero}
$verifyDirectory=$null
if($Verify){$verifyDirectory=Join-Path ([IO.Path]::GetTempPath()) ('QuickPS-Recorder-'+[Guid]::NewGuid().ToString('N'));$OutputDirectory=$verifyDirectory}
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
try {
    $ui=& (Join-Path $PSScriptRoot '..\src\Win32.Windows.ps1')
    $window=$ui.CreateWindow('Sound Recorder',640,390,'MicaAlt')
    $ui.Root=$window
    $state.Status=$ui.AddControl($window,'STATIC','Ready. Choose a source and press Record.',24,24,580,48,[uint32]0,$null)
    $null=$ui.AddControl($window,'STATIC','Peak level',24,92,140,24,[uint32]0,$null)
    $commonControls=[Runtime.InteropServices.NativeLibrary]::Load('comctl32.dll')
    $init=$ui.Native.GetCall([Runtime.InteropServices.NativeLibrary]::GetExport($commonControls,'InitCommonControlsEx'),[bool],@([IntPtr]))
    $settings=$ui.Native.Allocate(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($settings,0,8)
        [Runtime.InteropServices.Marshal]::WriteInt32($settings,4,32)
        if(-not $init.DynamicInvoke($settings)){throw 'Progress control initialization failed.'}
    }finally{$ui.Native.Free($settings)}
    $state.Meter=$ui.AddControl($window,'msctls_progress32','',24,126,576,24,[uint32]1,$null)
    $completion={
        param($hostUi,$code)
        if($code -ne 0 -or -not $state.Worker){return}
        $worker=$state.Worker
        if(-not $worker.Thread.Join(1000)){throw 'Completed capture worker did not exit.'}
        if($worker.GetStatus() -eq 5){$hostUi.SetText($state.Status,'Failed: '+$worker.Failure)}
        else{$hostUi.SetText($state.Status,('Saved {0:N0} bytes. Normalized: {1}' -f $worker.BytesWritten,$worker.Normalized))}
        $worker.Dispose();$state.Worker=$null;$state.Paused=$false
        if($Verify){
            if($worker.GetStatus() -ne 4){throw 'Synthetic recorder verification failed.'}
            [void]$hostUi.Api.SendMessageW.Invoke($window,[uint32]16,[IntPtr]::Zero,[IntPtr]::Zero)
        }
    }.GetNewClosure()
    $notify=$ui.AddControl($window,'STATIC','',0,0,0,0,[uint32]0,$completion)
    $notifyId=$ui.NextId-1
    $record={
        param($hostUi,$code)
        if($code -ne 0 -or $state.Worker){return}
        $path=Join-Path $OutputDirectory ('Recording-'+[Guid]::NewGuid().ToString('N')+'.wav')
        $state.Worker=& (Join-Path $PSScriptRoot '..\src\Capture.Windows.ps1') -AssemblyPath $AssemblyPath -OutputPath $path `
            -Loopback:($state.Source -eq 'Apps') -Normalize:(-not $NoNormalize) -Synthetic:$Verify `
            -NotifyWindow $window -NotifyControl $notify -NotifyId $notifyId
        $state.Worker.MeterWindow=$state.Meter
        $hostUi.SetText($state.Status,'Recording '+$state.Source+'.')
        $state.Worker.Thread.Start()
    }.GetNewClosure()
    $stop={param($hostUi,$code)
        if($code -ne 0 -or -not $state.Worker){return}
        $state.Worker.RequestStop()
        $hostUi.SetText($state.Status,'Stopping and finalizing on the capture worker...')
    }.GetNewClosure()
    $pause={param($hostUi,$code)
        if($code -ne 0 -or -not $state.Worker){return}
        $state.Paused=-not $state.Paused
        if($state.Paused){$state.Worker.Pause();$hostUi.SetText($state.Status,'Paused.')}
        else{$state.Worker.Resume();$hostUi.SetText($state.Status,'Recording '+$state.Source+'.')}
    }.GetNewClosure()
    $recordButton=$ui.AddControl($window,'BUTTON','Record',24,190,170,44,[uint32]0,$record)
    $recordId=$ui.NextId-1
    $null=$ui.AddControl($window,'BUTTON','Pause / Resume',216,190,180,44,[uint32]0,$pause)
    $stopButton=$ui.AddControl($window,'BUTTON','Stop',418,190,182,44,[uint32]0,$stop)
    $stopId=$ui.NextId-1
    foreach($choice in @('Mic','Apps')){
        $selected=$choice
        $select={param($hostUi,$code)
            if($code -eq 0 -and -not $state.Worker){$state.Source=$selected;$hostUi.SetText($state.Status,'Ready: '+$selected)}
        }.GetNewClosure()
        $x=if($choice -eq 'Mic'){24}else{216}
        $null=$ui.AddControl($window,'BUTTON',$choice,$x,258,170,40,[uint32]0,$select)
    }
    if($ScreenshotPath){
        $ui.Show($window)
        $snapshot={param($hostUi,$code)
            $redraw=$hostUi.Native.GetExportCall('user32.dll','RedrawWindow',[bool],@([IntPtr],[IntPtr],[IntPtr],[uint32]))
            if(-not $redraw.DynamicInvoke($window,[IntPtr]::Zero,[IntPtr]::Zero,[uint32]0x185)){throw 'Native redraw request failed.'}
            $capture=& (Join-Path $PSScriptRoot '..\src\WindowCapture.Windows.ps1')
            try{$null=$capture.CaptureWindow($window,[IO.Path]::GetFullPath($ScreenshotPath))}finally{$capture.Dispose()}
        }.GetNewClosure()
        $shot=$ui.AddControl($window,'STATIC','',0,0,0,0,[uint32]0,$snapshot)
        [void]$ui.Api.SendMessageW.Invoke($window,[uint32]273,[IntPtr]($ui.NextId-1),$shot)
    }
    if($Verify){
        [void]$ui.Api.SendMessageW.Invoke($window,[uint32]273,[IntPtr]$recordId,$recordButton)
        [void]$ui.Api.SendMessageW.Invoke($window,[uint32]273,[IntPtr]$stopId,$stopButton)
    }else{$ui.Show($window)}
    $ui.Run()
    if($Verify){'PASS: native recorder window, registered Record/Stop command dispatch, managed asynchronous completion and disposal; synthetic input only.'}
} finally {
    if($state.Worker){
        $state.Worker.RequestStop()
        if(-not $state.Worker.Thread.Join(5000)){throw 'Capture shutdown exceeded five seconds; worker resources retained until process exit.'}
        $state.Worker.Dispose()
    }
    if($ui){$ui.Dispose()}
    if($commonControls -ne [IntPtr]::Zero){[Runtime.InteropServices.NativeLibrary]::Free($commonControls)}
    if($verifyDirectory){Remove-Item -LiteralPath $verifyDirectory -Recurse -Force}
}

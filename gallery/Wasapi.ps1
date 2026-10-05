$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$recording = Join-Path $repositoryRoot 'artifacts\wasapi-capture.wav'

while ($true) {
    Clear-Host
    Write-Host ' QUICKPS WASAPI ' -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ''
    Write-Host '[R] Record microphone for three seconds'
    Write-Host '[P] Play the latest recording'
    Write-Host '[Q] Quit'
    $choice = Read-Host 'Choose'
    switch ($choice.ToUpperInvariant()) {
        R {
            $recordingParameters = @{ OutputPath = $recording; Milliseconds = 3000 }
$result = & (Join-Path $repositoryRoot 'tests\Record-Wasapi.ps1') @recordingParameters
Write-Host "Recorded $($result.Bytes) bytes at $($result.SamplesPerSecond) Hz." -ForegroundColor Cyan
            Read-Host 'Press Enter'
        }
        P {
            if (-not (Test-Path -LiteralPath $recording)) {
                Write-Host 'No recording exists yet.' -ForegroundColor White -BackgroundColor Black
                Read-Host 'Press Enter'
                continue
            }
            Start-Process -FilePath $recording
            Write-Host 'Playback opened in the registered audio player.' -ForegroundColor Cyan
            Read-Host 'Press Enter'
        }
        Q { return }
    }
}

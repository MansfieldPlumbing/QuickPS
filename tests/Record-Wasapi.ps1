[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\artifacts\wasapi-capture.wav'),
    [ValidateRange(1, 60000)][int] $Milliseconds = 2000,
    [switch] $Loopback
)

if ($MyInvocation.InvocationName -eq '.') {
    throw 'Record-Wasapi.ps1 must be invoked with &, not dot-sourced.'
}

$ErrorActionPreference = 'Stop'
$output = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
$wasapi = & (Join-Path $PSScriptRoot '..\src\Wasapi.Windows.ps1')
$bytes = [Collections.Generic.List[byte]]::new()
$native = $null

try {
    $native = & (Join-Path $PSScriptRoot '..\src\Native.ps1')
    $wait = $native.GetExportCall('kernel32.dll', 'WaitForSingleObject', [uint32], @([IntPtr], [uint32]))
    $flow = if ($Loopback) { 'Render' } else { 'Capture' }
    $device = $wasapi.GetDefaultEndpoint($flow, 'Multimedia')
    $client = $wasapi.ActivateAudioClient($device)
    $format = $wasapi.GetMixFormat($client)
    $formatTag = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($format, 0) -band 0xFFFF)
    $channels = [uint16][Runtime.InteropServices.Marshal]::ReadInt16($format, 2)
    $samplesPerSecond = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($format, 4)
    $averageBytesPerSecond = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($format, 8)
    $blockAlign = [uint16][Runtime.InteropServices.Marshal]::ReadInt16($format, 12)
    $bitsPerSample = [uint16][Runtime.InteropServices.Marshal]::ReadInt16($format, 14)
    $audioReady = $wasapi.InitializeShared($client, $format, $Loopback, $true, 0)
    $capture = $wasapi.GetService($client, 'Capture')
    $null = $wasapi.Start($client)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    # SetEventHandle signals buffer availability. The sole timeout is the test's
    # final deadline, not a recurring retry interval. Drain only after a signal.
    # https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-seteventhandle
    while ($clock.ElapsedMilliseconds -lt $Milliseconds) {
        $remainingMilliseconds = [long]$Milliseconds - $clock.ElapsedMilliseconds
        if ($remainingMilliseconds -le 0) { break }
        $remaining = [uint32]$remainingMilliseconds
        $waitResult = [uint32]$wait.Invoke($audioReady, $remaining)
        if ($waitResult -eq 258) { break } # WAIT_TIMEOUT: final deadline
        if ($waitResult -ne 0) { throw 'Audio buffer wait failed.' }
        while (($packetFrames = $wasapi.GetNextCapturePacketSize($capture)) -ne 0) {
            $packet = $wasapi.AcquireCaptureBuffer($capture)
            try {
                $byteCount64 = [long]$packet.Frames * [long]$blockAlign
                if ($byteCount64 -lt 0 -or $byteCount64 -gt 16777216 -or [long]$bytes.Count + $byteCount64 -gt 268435456) {
                    throw 'Capture data exceeds the test buffer bound.'
                }
                $byteCount = [int]$byteCount64
                $chunk = [byte[]]::new($byteCount)
                # AUDCLNT_BUFFERFLAGS_SILENT means the pointer must not be read.
                if (($packet.Flags -band [uint32]2) -eq 0 -and $byteCount -gt 0) {
                    if ($packet.Data -eq [IntPtr]::Zero) { throw 'Non-silent capture packet has no data.' }
                    [Runtime.InteropServices.Marshal]::Copy($packet.Data, $chunk, 0, $byteCount)
                }
                $bytes.AddRange($chunk)
            }
            finally { $null = $wasapi.ReleaseCaptureBuffer($capture, $packet.Frames) }
            if ($clock.ElapsedMilliseconds -ge $Milliseconds) { break }
        }
    }
    $null = $wasapi.Stop($client)

    $stream = [IO.File]::Open($output, [IO.FileMode]::Create, [IO.FileAccess]::Write)
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([uint32](36 + $bytes.Count))
        $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([uint32]16)
        # WAVE_FORMAT_EXTENSIBLE is recorded as IEEE float/PCM according to its subformat.
        $waveTag = if ($formatTag -eq 65534 -and $bitsPerSample -eq 32) { [uint16]3 } else { $formatTag }
        $writer.Write($waveTag)
        $writer.Write($channels)
        $writer.Write($samplesPerSecond)
        $writer.Write($averageBytesPerSecond)
        $writer.Write($blockAlign)
        $writer.Write($bitsPerSample)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([uint32]$bytes.Count)
        $writer.Write($bytes.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }

    [PSCustomObject]@{
        Path = $output
        Bytes = $bytes.Count
        Milliseconds = $clock.ElapsedMilliseconds
        Channels = $channels
        SamplesPerSecond = $samplesPerSecond
        BitsPerSample = $bitsPerSample
        Sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    }
}
finally {
    try { if ($wasapi) { $wasapi.Dispose() } }
    finally { if ($native) { $native.Dispose() } }
}

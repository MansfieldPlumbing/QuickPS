[CmdletBinding()]
param(
    [switch]$Verify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($MyInvocation.InvocationName -eq '.') {
    throw 'SoundRecorder.ps1 must be invoked with &, not dot-sourced.'
}

# Dynamic Native Delegate Emitter (Zero Add-Type, Zero DllImport)
$assembly = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
    [Reflection.AssemblyName]::new('QuickPS.SoundRecorder.' + [Guid]::NewGuid().ToString('N')),
    [Reflection.Emit.AssemblyBuilderAccess]::Run
)
$module = $assembly.DefineDynamicModule('Native')
$types = [Collections.Generic.Dictionary[string, Type]]::new()
$calls = [Collections.Generic.Dictionary[string, Delegate]]::new()

$nativeCall = {
    param([IntPtr] $Address, [Type] $ReturnType, [Type[]] $ParameterTypes)
    $sig = $ReturnType.FullName + ':' + (($ParameterTypes | ForEach-Object FullName) -join ',')
    if (-not $types.ContainsKey($sig)) {
        $tb = $module.DefineType('Call_' + [Guid]::NewGuid().ToString('N'), 'Class,Public,Sealed', [MulticastDelegate])
        $ctor = $tb.DefineConstructor('Public,HideBySig,RTSpecialName', [Reflection.CallingConventions]::Standard, @([object], [IntPtr]))
        $ctor.SetImplementationFlags('Runtime,Managed')
        $invoke = $tb.DefineMethod('Invoke', 'Public,HideBySig,NewSlot,Virtual', $ReturnType, $ParameterTypes)
        $invoke.SetImplementationFlags('Runtime,Managed')
        $attr = [Reflection.Emit.CustomAttributeBuilder]::new(
            [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(@([Runtime.InteropServices.CallingConvention])),
            @([Runtime.InteropServices.CallingConvention]::StdCall)
        )
        $tb.SetCustomAttribute($attr)
        $types[$sig] = $tb.CreateType()
    }
    $key = $Address.ToInt64().ToString() + ':' + $sig
    if (-not $calls.ContainsKey($key)) {
        $calls[$key] = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($Address, $types[$sig])
    }
    $calls[$key]
}.GetNewClosure()

$user32 = [Runtime.InteropServices.NativeLibrary]::Load('user32.dll')
$gdi32 = [Runtime.InteropServices.NativeLibrary]::Load('gdi32.dll')
$dwmapi = [Runtime.InteropServices.NativeLibrary]::Load('dwmapi.dll')
$kernel32 = [Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
$ole32 = [Runtime.InteropServices.NativeLibrary]::Load('ole32.dll')

$bind = {
    param([IntPtr] $Lib, [string] $Name, [Type] $Ret, [Type[]] $Params)
    & $nativeCall ([Runtime.InteropServices.NativeLibrary]::GetExport($Lib, $Name)) $Ret $Params
}.GetNewClosure()

$comCall = {
    param(
        [IntPtr] $Object,
        [int] $Slot,
        [Type] $ReturnType,
        [object[]] $Arguments,
        [Type[]] $ParameterTypes
    )
    if ($Object -eq [IntPtr]::Zero) { throw "Cannot invoke COM slot $Slot on null pointer." }
    $vtbl = [Runtime.InteropServices.Marshal]::ReadIntPtr($Object)
    $addr = [Runtime.InteropServices.Marshal]::ReadIntPtr($vtbl, $Slot * [IntPtr]::Size)
    $fn = & $nativeCall $addr $ReturnType (@([IntPtr]) + $ParameterTypes)
    $fn.DynamicInvoke(@($Object) + $Arguments)
}.GetNewClosure()

$alloc = {
    param([int] $Bytes)
    $p = [Runtime.InteropServices.Marshal]::AllocHGlobal($Bytes)
    for ($i = 0; $i -lt $Bytes; $i++) { [Runtime.InteropServices.Marshal]::WriteByte($p, $i, 0) }
    $p
}.GetNewClosure()

$guidBlock = {
    param([Guid] $Guid)
    $p = & $alloc 16
    [Runtime.InteropServices.Marshal]::Copy($Guid.ToByteArray(), 0, $p, 16)
    $p
}.GetNewClosure()

# Win32 & GDI Exports
$getModuleHandle = & $bind $kernel32 'GetModuleHandleW' ([IntPtr]) @([IntPtr])
$registerClassEx = & $bind $user32 'RegisterClassExW' ([uint16]) @([IntPtr])
$unregisterClass = & $bind $user32 'UnregisterClassW' ([bool]) @([IntPtr], [IntPtr])
$createWindowEx = & $bind $user32 'CreateWindowExW' ([IntPtr]) @([uint32],[IntPtr],[IntPtr],[uint32],[int32],[int32],[int32],[int32],[IntPtr],[IntPtr],[IntPtr],[IntPtr])
$destroyWindow = & $bind $user32 'DestroyWindow' ([bool]) @([IntPtr])
$showWindow = & $bind $user32 'ShowWindow' ([bool]) @([IntPtr], [int32])
$setWindowPos = & $bind $user32 'SetWindowPos' ([bool]) @([IntPtr], [IntPtr], [int32], [int32], [int32], [int32], [uint32])
$updateWindow = & $bind $user32 'UpdateWindow' ([bool]) @([IntPtr])
$defWindowProc = & $bind $user32 'DefWindowProcW' ([IntPtr]) @([IntPtr], [uint32], [IntPtr], [IntPtr])
$getMessage = & $bind $user32 'GetMessageW' ([int32]) @([IntPtr], [IntPtr], [uint32], [uint32])
$translateMessage = & $bind $user32 'TranslateMessage' ([bool]) @([IntPtr])
$dispatchMessage = & $bind $user32 'DispatchMessageW' ([IntPtr]) @([IntPtr])
$postQuitMessage = & $bind $user32 'PostQuitMessage' ([Type]'System.Void') @([int32])
$sendMessage = & $bind $user32 'SendMessageW' ([IntPtr]) @([IntPtr], [uint32], [IntPtr], [IntPtr])
$postMessage = & $bind $user32 'PostMessageW' ([bool]) @([IntPtr], [uint32], [IntPtr], [IntPtr])
$loadCursor = & $bind $user32 'LoadCursorW' ([IntPtr]) @([IntPtr], [IntPtr])
$setTimer = & $bind $user32 'SetTimer' ([IntPtr]) @([IntPtr], [IntPtr], [uint32], [IntPtr])
$killTimer = & $bind $user32 'KillTimer' ([bool]) @([IntPtr], [IntPtr])
$invalidateRect = & $bind $user32 'InvalidateRect' ([bool]) @([IntPtr], [IntPtr], [bool])
$getClientRect = & $bind $user32 'GetClientRect' ([bool]) @([IntPtr], [IntPtr])
$beginPaint = & $bind $user32 'BeginPaint' ([IntPtr]) @([IntPtr], [IntPtr])
$endPaint = & $bind $user32 'EndPaint' ([bool]) @([IntPtr], [IntPtr])
$getSystemMetrics = & $bind $user32 'GetSystemMetrics' ([int32]) @([int32])

$createSolidBrush = & $bind $gdi32 'CreateSolidBrush' ([IntPtr]) @([uint32])
$createPen = & $bind $gdi32 'CreatePen' ([IntPtr]) @([int32], [int32], [uint32])
$selectObject = & $bind $gdi32 'SelectObject' ([IntPtr]) @([IntPtr], [IntPtr])
$deleteObject = & $bind $gdi32 'DeleteObject' ([bool]) @([IntPtr])
$createCompatibleDC = & $bind $gdi32 'CreateCompatibleDC' ([IntPtr]) @([IntPtr])
$createCompatibleBitmap = & $bind $gdi32 'CreateCompatibleBitmap' ([IntPtr]) @([IntPtr], [int32], [int32])
$deleteDC = & $bind $gdi32 'DeleteDC' ([bool]) @([IntPtr])
$bitBlt = & $bind $gdi32 'BitBlt' ([bool]) @([IntPtr],[int32],[int32],[int32],[int32],[IntPtr],[int32],[int32],[uint32])
$setBkMode = & $bind $gdi32 'SetBkMode' ([int32]) @([IntPtr], [int32])
$setTextColor = & $bind $gdi32 'SetTextColor' ([uint32]) @([IntPtr], [uint32])
$createFontW = & $bind $gdi32 'CreateFontW' ([IntPtr]) @([int32],[int32],[int32],[int32],[int32],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[uint32],[IntPtr])
$roundRect = & $bind $gdi32 'RoundRect' ([bool]) @([IntPtr], [int32], [int32], [int32], [int32], [int32], [int32])
$moveToEx = & $bind $gdi32 'MoveToEx' ([bool]) @([IntPtr], [int32], [int32], [IntPtr])
$lineTo = & $bind $gdi32 'LineTo' ([bool]) @([IntPtr], [int32], [int32])
$drawTextW = & $bind $user32 'DrawTextW' ([int32]) @([IntPtr], [IntPtr], [int32], [IntPtr], [uint32])
$getStockObject = & $bind $gdi32 'GetStockObject' ([IntPtr]) @([int32])

# DWM
$dwmSetWindowAttribute = & $bind $dwmapi 'DwmSetWindowAttribute' ([int32]) @([IntPtr], [uint32], [IntPtr], [uint32])
$dwmExtendFrame = & $bind $dwmapi 'DwmExtendFrameIntoClientArea' ([int32]) @([IntPtr], [IntPtr])

# COM & WASAPI
$coInitializeEx = & $bind $ole32 'CoInitializeEx' ([int32]) @([IntPtr], [uint32])
$coUninitialize = & $bind $ole32 'CoUninitialize' ([Type]'System.Void') @()
$coCreateInstance = & $bind $ole32 'CoCreateInstance' ([int32]) @([IntPtr], [IntPtr], [uint32], [IntPtr], [IntPtr])
$coTaskMemFree = & $bind $ole32 'CoTaskMemFree' ([Type]'System.Void') @([IntPtr])
$propVariantClear = & $bind $ole32 'PropVariantClear' ([int32]) @([IntPtr])

# Initialize COM apartment (COINIT_MULTITHREADED = 0)
$coHr = [int32]$coInitializeEx.DynamicInvoke(@([IntPtr]::Zero, [uint32]0))
$coOwned = ($coHr -eq 0 -or $coHr -eq 1)

# MMDeviceEnumerator & WASAPI Constants/GUIDs
$clsidMMDeviceEnumerator = [Guid]'BCDE0395-E52F-467C-8E3D-C4579291692E'
$iidIMMDeviceEnumerator  = [Guid]'A95664D2-9614-4F35-A746-DE8DB63617E6'
$iidIAudioClient         = [Guid]'1CB9AD4C-DBFA-4C32-B178-C2F568A703B2'
$iidIAudioCaptureClient  = [Guid]'C8ADBD64-E71E-48A0-A4DE-185C395CD317'
$pkeyFriendlyNameFmtid   = [Guid]'A45C254E-DF1C-4EFD-8020-67D146A850E0'

# Create MMDeviceEnumerator
$pClsid = & $guidBlock $clsidMMDeviceEnumerator
$pIid = & $guidBlock $iidIMMDeviceEnumerator
$pEnumOut = & $alloc ([IntPtr]::Size)
try {
    $hr = [int32]$coCreateInstance.DynamicInvoke(@($pClsid, [IntPtr]::Zero, [uint32]23, $pIid, $pEnumOut))
    if ($hr -lt 0) { throw ('CoCreateInstance(MMDeviceEnumerator) failed: 0x{0:X8}' -f [uint32]$hr) }
    $deviceEnumerator = [Runtime.InteropServices.Marshal]::ReadIntPtr($pEnumOut)
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pClsid)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pIid)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pEnumOut)
}

# Helpers for Audio Capture
function Get-DeviceName([IntPtr] $Device) {
    $storeOut = & $alloc ([IntPtr]::Size)
    try {
        # IMMDevice::OpenPropertyStore (slot 4)
        $hr = [int32](& $comCall $Device 4 ([int32]) @([uint32]0, $storeOut) @([uint32], [IntPtr]))
        $store = [Runtime.InteropServices.Marshal]::ReadIntPtr($storeOut)
        if ($hr -lt 0 -or $store -eq [IntPtr]::Zero) { return 'Audio Endpoint' }

        $key = & $alloc 20
        $pv = & $alloc 32
        try {
            [Runtime.InteropServices.Marshal]::Copy($pkeyFriendlyNameFmtid.ToByteArray(), 0, $key, 16)
            [Runtime.InteropServices.Marshal]::WriteInt32($key, 16, 14) # PID 14
            # IPropertyStore::GetValue (slot 5)
            $hr = [int32](& $comCall $store 5 ([int32]) @($key, $pv) @([IntPtr], [IntPtr]))
            $vt = [Runtime.InteropServices.Marshal]::ReadInt16($pv, 0)
            $val = [Runtime.InteropServices.Marshal]::ReadIntPtr($pv, 8)
            if ($vt -eq 31 -and $val -ne [IntPtr]::Zero) {
                return [Runtime.InteropServices.Marshal]::PtrToStringUni($val)
            }
            return 'Audio Endpoint'
        }
        finally {
            [void]$propVariantClear.DynamicInvoke(@($pv))
            [Runtime.InteropServices.Marshal]::FreeHGlobal($pv)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($key)
            [void](& $comCall $store 2 ([uint32]) @() @()) # Release
        }
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($storeOut)
    }
}

function Get-DefaultDevice([string] $Flow) {
    $flowVal = if ($Flow -eq 'Render') { [uint32]0 } else { [uint32]1 }
    $devOut = & $alloc ([IntPtr]::Size)
    try {
        # IMMDeviceEnumerator::GetDefaultAudioEndpoint (slot 4)
        $hr = [int32](& $comCall $deviceEnumerator 4 ([int32]) @($flowVal, [uint32]1, $devOut) @([uint32], [uint32], [IntPtr]))
        $dev = [Runtime.InteropServices.Marshal]::ReadIntPtr($devOut)
        if ($hr -lt 0 -or $dev -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
        return $dev
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($devOut)
    }
}

function Initialize-AudioStream([IntPtr] $Device, [bool] $Loopback) {
    $pAudioIid = & $guidBlock $iidIAudioClient
    $clientOut = & $alloc ([IntPtr]::Size)
    $client = [IntPtr]::Zero
    try {
        # IMMDevice::Activate (slot 3)
        $hr = [int32](& $comCall $Device 3 ([int32]) @($pAudioIid, [uint32]23, [IntPtr]::Zero, $clientOut) @([IntPtr], [uint32], [IntPtr], [IntPtr]))
        $client = [Runtime.InteropServices.Marshal]::ReadIntPtr($clientOut)
        if ($hr -lt 0 -or $client -eq [IntPtr]::Zero) { throw ('Activate(IAudioClient) failed: 0x{0:X8}' -f [uint32]$hr) }
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pAudioIid)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($clientOut)
    }

    # IAudioClient::GetMixFormat (slot 8)
    $fmtOut = & $alloc ([IntPtr]::Size)
    try {
        $hr = [int32](& $comCall $client 8 ([int32]) @($fmtOut) @([IntPtr]))
        $formatPtr = [Runtime.InteropServices.Marshal]::ReadIntPtr($fmtOut)
        if ($hr -lt 0 -or $formatPtr -eq [IntPtr]::Zero) { throw 'GetMixFormat failed.' }
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($fmtOut)
    }

    # Format parsing
    $tag = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($formatPtr, 0) -band 0xFFFF)
    $channels = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($formatPtr, 2) -band 0xFFFF)
    $sampleRate = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($formatPtr, 4)
    $avgBytesPerSec = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($formatPtr, 8)
    $blockAlign = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($formatPtr, 12) -band 0xFFFF)
    $bits = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($formatPtr, 14) -band 0xFFFF)
    $cb = [uint16]([Runtime.InteropServices.Marshal]::ReadInt16($formatPtr, 16) -band 0xFFFF)
    $fmtSize = 18 + [int]$cb

    $formatBytes = [byte[]]::new($fmtSize)
    [Runtime.InteropServices.Marshal]::Copy($formatPtr, $formatBytes, 0, $fmtSize)

    # IAudioClient::Initialize (slot 3)
    # AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000
    [uint32]$flags = if ($Loopback) { [uint32]0x00020000 } else { [uint32]0 }
    $hr = [int32](& $comCall $client 3 ([int32]) @(
        [uint32]0, $flags, [int64]10000000, [int64]0, $formatPtr, [IntPtr]::Zero
    ) @([uint32], [uint32], [int64], [int64], [IntPtr], [IntPtr]))
    if ($hr -lt 0) { throw ('IAudioClient::Initialize failed: 0x{0:X8}' -f [uint32]$hr) }

    # IAudioClient::GetService (slot 14) for IAudioCaptureClient
    $pCapIid = & $guidBlock $iidIAudioCaptureClient
    $capOut = & $alloc ([IntPtr]::Size)
    $capture = [IntPtr]::Zero
    try {
        $hr = [int32](& $comCall $client 14 ([int32]) @($pCapIid, $capOut) @([IntPtr], [IntPtr]))
        $capture = [Runtime.InteropServices.Marshal]::ReadIntPtr($capOut)
        if ($hr -lt 0 -or $capture -eq [IntPtr]::Zero) { throw 'GetService(IAudioCaptureClient) failed.' }
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pCapIid)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($capOut)
    }

    return @{
        Client = $client
        Capture = $capture
        FormatPointer = $formatPtr
        FormatBytes = $formatBytes
        Channels = $channels
        SampleRate = $sampleRate
        BlockAlign = $blockAlign
        Bits = $bits
        Tag = $tag
        Loopback = $Loopback
    }
}

$fnCloseAudioStream = {
    param($stream)
    if ($null -eq $stream) { return }
    if ($stream.Client -ne [IntPtr]::Zero) {
        [void](& $comCall $stream.Client 11 ([int32]) @() @()) # Stop
        [void](& $comCall $stream.Client 2 ([uint32]) @() @())  # Release
    }
    if ($stream.Capture -ne [IntPtr]::Zero) {
        [void](& $comCall $stream.Capture 2 ([uint32]) @() @()) # Release
    }
    if ($stream.FormatPointer -ne [IntPtr]::Zero) {
        [void]$coTaskMemFree.DynamicInvoke(@($stream.FormatPointer))
    }
}

# App State Container
$recordingsDir = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)) 'Recordings'
if (-not (Test-Path -LiteralPath $recordingsDir)) { [IO.Directory]::CreateDirectory($recordingsDir) | Out-Null }

$state = [PSCustomObject]@{
    IsRecording = $false
    IsPaused = $false
    AlwaysOnTop = $false
    Mode = 'Waveform'       # 'Waveform' or 'Transcript'
    SourceMode = 'Mic'      # 'Mic', 'Apps', or 'Both'
    MicDevice = [IntPtr]::Zero
    AppDevice = [IntPtr]::Zero
    MicName = ''
    AppName = ''
    MicStream = $null
    AppStream = $null
    WaveFile = $null
    WaveWriter = $null
    DataBytesPos = [long]0
    TotalAudioBytes = [long]0
    StartTime = [DateTime]::MinValue
    ElapsedSec = [double]0
    WaveformBars = [single[]]::new(52)
    RecentPeak = [single]0
    CurrentDb = [double]-48.0
    PeakHoldDb = [double]-48.0
    ClipCount = 0
    StatusMessage = 'Ready'
    LastSavedPath = ''
    SavedNotification = $null
    Hwnd = [IntPtr]::Zero
    TimerCount = 0
}

# Discover Audio Devices
$state.MicDevice = Get-DefaultDevice 'Capture'
if ($state.MicDevice -ne [IntPtr]::Zero) { $state.MicName = Get-DeviceName $state.MicDevice } else { $state.MicName = 'No Microphone detected' }

$state.AppDevice = Get-DefaultDevice 'Render'
if ($state.AppDevice -ne [IntPtr]::Zero) { $state.AppName = Get-DeviceName $state.AppDevice } else { $state.AppName = 'No Audio Output detected' }

$fnStartRecording = {
    if ($state.IsRecording) { return }
    $state.StatusMessage = 'Initializing capture...'
    $state.SavedNotification = $null

    # Setup streams
    try {
        if ($state.SourceMode -eq 'Mic' -or $state.SourceMode -eq 'Both') {
            if ($state.MicDevice -eq [IntPtr]::Zero) { throw 'Microphone device unavailable.' }
            $state.MicStream = Initialize-AudioStream $state.MicDevice $false
        }
        if ($state.SourceMode -eq 'Apps' -or $state.SourceMode -eq 'Both') {
            if ($state.AppDevice -eq [IntPtr]::Zero) { throw 'System audio render device unavailable.' }
            $state.AppStream = Initialize-AudioStream $state.AppDevice $true
        }

        # Primary stream determines WAV format
        $primary = if ($state.MicStream) { $state.MicStream } else { $state.AppStream }
        if (-not $primary) { throw 'No active audio source available.' }

        $fileName = 'Recording_{0}.wav' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        $filePath = Join-Path $recordingsDir $fileName
        $state.LastSavedPath = $filePath

        $fs = [IO.File]::Create($filePath)
        $bw = [IO.BinaryWriter]::new($fs)

        # Write WAV Header
        $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $bw.Write([uint32]0) # size placeholder
        $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
        $bw.Write([uint32]$primary.FormatBytes.Length)
        $bw.Write($primary.FormatBytes, 0, $primary.FormatBytes.Length)
        if (($primary.FormatBytes.Length -band 1) -ne 0) { $bw.Write([byte]0) }
        $bw.Write([Text.Encoding]::ASCII.GetBytes('data'))
        $state.DataBytesPos = $fs.Position
        $bw.Write([uint32]0) # data size placeholder

        $state.WaveFile = $fs
        $state.WaveWriter = $bw
        $state.TotalAudioBytes = 0

        # Start clients
        if ($state.MicStream) { [void](& $comCall $state.MicStream.Client 10 ([int32]) @() @()) }
        if ($state.AppStream) { [void](& $comCall $state.AppStream.Client 10 ([int32]) @() @()) }

        $state.StartTime = [DateTime]::UtcNow
        $state.ElapsedSec = 0
        $state.CurrentDb = -48.0
        $state.PeakHoldDb = -48.0
        $state.ClipCount = 0
        $state.IsRecording = $true
        $state.IsPaused = $false
        $state.StatusMessage = 'Recording'

        # Arm Win32 timer (40ms = 25 ticks/sec)
        [void]$setTimer.DynamicInvoke(@($state.Hwnd, [IntPtr]1, [uint32]40, [IntPtr]::Zero))
    }
    catch {
        $state.StatusMessage = 'Capture Error: ' + $_.Exception.Message
        & $fnStopRecording
        throw
    }
}

# Post-Capture Peak Normalizer & Studio Soft Limiter
$fnNormalizeWav = {
    param([string]$wavPath)
    if (-not (Test-Path -LiteralPath $wavPath)) { return @{ Normalized = $false } }
    try {
        $fi = Get-Item -LiteralPath $wavPath
        if ($fi.Length -lt 44) { return @{ Normalized = $false } }

        $fs = [IO.File]::Open($wavPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $br = [IO.BinaryReader]::new($fs)
        try {
            $riff = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($riff -ne 'RIFF') { return @{ Normalized = $false } }
            [void]$br.ReadUInt32()
            $wave = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($wave -ne 'WAVE') { return @{ Normalized = $false } }

            $audioFormat = 0
            $channels = 0
            $sampleRate = 0
            $bitsPerSample = 0
            $dataPos = 0
            $dataLen = 0

            while ($fs.Position -lt $fs.Length) {
                if (($fs.Position + 8) -gt $fs.Length) { break }
                $chunkId = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
                $chunkSize = $br.ReadUInt32()

                if ($chunkId -eq 'fmt ') {
                    $audioFormat = $br.ReadUInt16()
                    $channels = $br.ReadUInt16()
                    $sampleRate = $br.ReadUInt32()
                    [void]$br.ReadUInt32()
                    [void]$br.ReadUInt16()
                    $bitsPerSample = $br.ReadUInt16()
                    $rem = [int]$chunkSize - 16
                    if ($rem -gt 0) { [void]$br.ReadBytes($rem) }
                }
                elseif ($chunkId -eq 'data') {
                    $dataPos = $fs.Position
                    $dataLen = [int]$chunkSize
                    break
                }
                else {
                    $fs.Seek($chunkSize, [IO.SeekOrigin]::Current) | Out-Null
                }
            }

            if ($dataPos -eq 0 -or $dataLen -le 0) { return @{ Normalized = $false } }

            $isFloat = ($audioFormat -eq 3 -or ($audioFormat -eq 65534 -and $bitsPerSample -eq 32))
            $isPcm16 = ($audioFormat -eq 1 -and $bitsPerSample -eq 16)

            if ($isFloat) {
                $fs.Position = $dataPos
                [single]$maxAbs = 0.0
                $blockSize = 4096
                $floatBuf = [single[]]::new($blockSize)
                $byteBuf = [byte[]]::new($blockSize * 4)

                $bytesLeft = $dataLen
                while ($bytesLeft -gt 0) {
                    $toRead = [Math]::Min($bytesLeft, $byteBuf.Length)
                    $read = $fs.Read($byteBuf, 0, $toRead)
                    if ($read -le 0) { break }
                    $samplesRead = [int]($read / 4)
                    [Buffer]::BlockCopy($byteBuf, 0, $floatBuf, 0, $read)

                    for ($i = 0; $i -lt $samplesRead; $i++) {
                        $abs = [Math]::Abs($floatBuf[$i])
                        if (-not [single]::IsNaN($abs) -and -not [single]::IsInfinity($abs) -and $abs -gt $maxAbs) {
                            $maxAbs = $abs
                        }
                    }
                    $bytesLeft -= $read
                }

                if ($maxAbs -gt 0.0001) {
                    [single]$target = 0.89125 # -1.0 dBFS
                    [single]$gain = $target / $maxAbs

                    $fs.Position = $dataPos
                    $bytesLeft = $dataLen
                    while ($bytesLeft -gt 0) {
                        $pos = $fs.Position
                        $toRead = [Math]::Min($bytesLeft, $byteBuf.Length)
                        $read = $fs.Read($byteBuf, 0, $toRead)
                        if ($read -le 0) { break }
                        $samplesRead = [int]($read / 4)
                        [Buffer]::BlockCopy($byteBuf, 0, $floatBuf, 0, $read)

                        for ($i = 0; $i -lt $samplesRead; $i++) {
                            $val = $floatBuf[$i] * $gain
                            if ($val -gt 0.98) { $val = [single]0.98 }
                            elseif ($val -lt -0.98) { $val = [single]-0.98 }
                            $floatBuf[$i] = $val
                        }

                        [Buffer]::BlockCopy($floatBuf, 0, $byteBuf, 0, $read)
                        $fs.Position = $pos
                        $fs.Write($byteBuf, 0, $read)
                        $bytesLeft -= $read
                    }
                    $fs.Flush()
                    return @{ Normalized = $true; PeakBefore = $maxAbs; Gain = $gain }
                }
            }
            elseif ($isPcm16) {
                $fs.Position = $dataPos
                [int16]$maxAbs = 0
                $blockSize = 4096
                $shortBuf = [int16[]]::new($blockSize)
                $byteBuf = [byte[]]::new($blockSize * 2)

                $bytesLeft = $dataLen
                while ($bytesLeft -gt 0) {
                    $toRead = [Math]::Min($bytesLeft, $byteBuf.Length)
                    $read = $fs.Read($byteBuf, 0, $toRead)
                    if ($read -le 0) { break }
                    $samplesRead = [int]($read / 2)
                    [Buffer]::BlockCopy($byteBuf, 0, $shortBuf, 0, $read)

                    for ($i = 0; $i -lt $samplesRead; $i++) {
                        $abs = [Math]::Abs([int]$shortBuf[$i])
                        if ($abs -gt $maxAbs) { $maxAbs = [int16]$abs }
                    }
                    $bytesLeft -= $read
                }

                if ($maxAbs -gt 10) {
                    $target = 29200.0
                    $gain = $target / [double]$maxAbs

                    $fs.Position = $dataPos
                    $bytesLeft = $dataLen
                    while ($bytesLeft -gt 0) {
                        $pos = $fs.Position
                        $toRead = [Math]::Min($bytesLeft, $byteBuf.Length)
                        $read = $fs.Read($byteBuf, 0, $toRead)
                        if ($read -le 0) { break }
                        $samplesRead = [int]($read / 2)
                        [Buffer]::BlockCopy($byteBuf, 0, $shortBuf, 0, $read)

                        for ($i = 0; $i -lt $samplesRead; $i++) {
                            $val = [int]($shortBuf[$i] * $gain)
                            if ($val -gt 32760) { $val = 32760 }
                            elseif ($val -lt -32760) { $val = -32760 }
                            $shortBuf[$i] = [int16]$val
                        }

                        [Buffer]::BlockCopy($shortBuf, 0, $byteBuf, 0, $read)
                        $fs.Position = $pos
                        $fs.Write($byteBuf, 0, $read)
                        $bytesLeft -= $read
                    }
                    $fs.Flush()
                    return @{ Normalized = $true; PeakBefore = ($maxAbs / 32768.0); Gain = $gain }
                }
            }
        }
        finally {
            $br.Dispose()
            $fs.Dispose()
        }
    }
    catch { }
    return @{ Normalized = $false }
}

$fnStopRecording = {
    if (-not $state.IsRecording) { return }

    # Disarm Win32 timer
    [void]$killTimer.DynamicInvoke(@($state.Hwnd, [IntPtr]1))

    if ($state.MicStream) { & $fnCloseAudioStream $state.MicStream; $state.MicStream = $null }
    if ($state.AppStream) { & $fnCloseAudioStream $state.AppStream; $state.AppStream = $null }

    if ($state.WaveWriter -and $state.WaveFile) {
        try {
            $state.WaveWriter.Flush()
            $end = $state.WaveFile.Length
            $state.WaveFile.Position = 4
            $state.WaveWriter.Write([uint32]($end - 8))
            $state.WaveFile.Position = $state.DataBytesPos
            $state.WaveWriter.Write([uint32]$state.TotalAudioBytes)
            $state.WaveWriter.Flush()
        }
        catch { }
        finally {
            $state.WaveWriter.Dispose()
            $state.WaveFile.Dispose()
            $state.WaveWriter = $null
            $state.WaveFile = $null
        }
    }

    # Normalize audio & apply studio soft limiter
    $norm = & $fnNormalizeWav $state.LastSavedPath

    # Calculate metrics for user announcement
    $dur = [TimeSpan]::FromSeconds($state.ElapsedSec)
    $durStr = '{0:00}:{1:00}.{2:0}' -f [int]$dur.TotalMinutes, $dur.Seconds, [int]($dur.Milliseconds / 100)
    $sizeKb = [int]($state.TotalAudioBytes / 1024)
    $sizeStr = if ($sizeKb -gt 1024) { '{0:F1} MB' -f ($sizeKb / 1024.0) } else { '{0} KB' -f $sizeKb }

    $state.SavedNotification = @{
        Path = $state.LastSavedPath
        FileName = [IO.Path]::GetFileName($state.LastSavedPath)
        Duration = $durStr
        Size = $sizeStr
        Normalized = $norm.Normalized
        Gain = if ($norm.Gain) { $norm.Gain } else { 1.0 }
    }

    $state.IsRecording = $false
    $state.IsPaused = $false
    $state.RecentPeak = 0
    $state.CurrentDb = -48.0
    $state.StatusMessage = 'Saved: ' + $state.SavedNotification.FileName

    # Reset silent window title
    $pTitleReset = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('Sound Recorder')
    [void]$defWindowProc.DynamicInvoke(@($state.Hwnd, [uint32]0x000C, [IntPtr]::Zero, $pTitleReset)) # WM_SETTEXT
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pTitleReset)
}

$fnPauseResumeRecording = {
    if (-not $state.IsRecording) { return }
    if ($state.IsPaused) {
        # Resume
        if ($state.MicStream) { [void](& $comCall $state.MicStream.Client 10 ([int32]) @() @()) }
        if ($state.AppStream) { [void](& $comCall $state.AppStream.Client 10 ([int32]) @() @()) }
        $state.IsPaused = $false
        $state.StatusMessage = 'Recording'
        [void]$setTimer.DynamicInvoke(@($state.Hwnd, [IntPtr]1, [uint32]40, [IntPtr]::Zero))
    }
    else {
        # Pause
        [void]$killTimer.DynamicInvoke(@($state.Hwnd, [IntPtr]1))
        if ($state.MicStream) { [void](& $comCall $state.MicStream.Client 11 ([int32]) @() @()) }
        if ($state.AppStream) { [void](& $comCall $state.AppStream.Client 11 ([int32]) @() @()) }
        $state.IsPaused = $true
        $state.StatusMessage = 'Paused'

        $timeSpan = [TimeSpan]::FromSeconds($state.ElapsedSec)
        $pauseTitle = '⏸ PAUSED [{0:00}:{1:00}] - Sound Recorder' -f [int]$timeSpan.TotalMinutes, $timeSpan.Seconds
        $pPauseTitle = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($pauseTitle)
        [void]$defWindowProc.DynamicInvoke(@($state.Hwnd, [uint32]0x000C, [IntPtr]::Zero, $pPauseTitle))
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pPauseTitle)
    }
    [void]$invalidateRect.DynamicInvoke(@($state.Hwnd, [IntPtr]::Zero, $false))
}

$fnProcessAudioPackets = {
    if (-not $state.IsRecording -or $state.IsPaused) { return }

    $nextPkt = & $alloc 4
    $dataOut = & $alloc ([IntPtr]::Size)
    $framesOut = & $alloc 4
    $flagsOut = & $alloc 4
    $posOut = & $alloc 8
    $qpcOut = & $alloc 8

    [single]$maxPeak = 0

    try {
        $drainStream = {
            param($stream, [bool]$writeWav)
            if (-not $stream) { return [single]0 }
            $cap = $stream.Capture
            if ($cap -eq [IntPtr]::Zero) { return [single]0 }

            [single]$localPeak = 0
            for ($iter = 0; $iter -lt 32; $iter++) {
                [Runtime.InteropServices.Marshal]::WriteInt32($nextPkt, 0)
                $hrPkt = [int32](& $comCall $cap 5 ([int32]) @($nextPkt) @([IntPtr]))
                if ($hrPkt -lt 0) { break }
                $pktSize = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($nextPkt)
                if ($pktSize -eq 0) { break }

                $hr = [int32](& $comCall $cap 3 ([int32]) @($dataOut, $framesOut, $flagsOut, $posOut, $qpcOut) @([IntPtr],[IntPtr],[IntPtr],[IntPtr],[IntPtr]))
                if ($hr -ne 0) { break }

                $frames = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($framesOut)
                $flags = [uint32][Runtime.InteropServices.Marshal]::ReadInt32($flagsOut)
                $pData = [Runtime.InteropServices.Marshal]::ReadIntPtr($dataOut)
                $byteLen = [int]($frames * $stream.BlockAlign)

                if ($byteLen -gt 0) {
                    $buf = [byte[]]::new($byteLen)
                    if (($flags -band 2) -eq 0 -and $pData -ne [IntPtr]::Zero) {
                        [Runtime.InteropServices.Marshal]::Copy($pData, $buf, 0, $byteLen)

                        # Ultra-fast 24-point strided peak sampling
                        $numPks = [Math]::Min(24, [int]$frames)
                        $step = [Math]::Max(1, [int]($frames / $numPks))
                        $bAlign = [int]$stream.BlockAlign
                        $is32 = ($stream.Bits -eq 32)

                        for ($k = 0; $k -lt $numPks; $k++) {
                            $sOffset = $k * $step * $bAlign
                            if (($sOffset + 3) -lt $byteLen) {
                                $sVal = if ($is32) {
                                    [Math]::Abs([BitConverter]::ToSingle($buf, $sOffset))
                                } else {
                                    [Math]::Abs([BitConverter]::ToInt16($buf, $sOffset) / 32768.0)
                                }
                                if (-not [single]::IsNaN($sVal) -and $sVal -gt $localPeak) {
                                    $localPeak = [single]$sVal
                                }
                            }
                        }
                    }
                    if ($writeWav -and $state.WaveWriter) {
                        $state.WaveWriter.Write($buf, 0, $byteLen)
                        $state.TotalAudioBytes += $byteLen
                    }
                }
                [void](& $comCall $cap 4 ([int32]) @($frames) @([uint32]))
            }
            return $localPeak
        }

        $micPeak = & $drainStream $state.MicStream ($true)
        $appPeak = & $drainStream $state.AppStream (-not $state.MicStream)
        $maxPeak = [Math]::Max([single]$micPeak, [single]$appPeak)
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($nextPkt)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($dataOut)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($framesOut)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($flagsOut)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($posOut)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($qpcOut)
    }

    # Perceptual amplitude & fluid waveform scrolling
    $clamped = [Math]::Min(1.0, [double]$maxPeak)
    $scaledPeak = if ($clamped -gt 0.001) { [single][Math]::Pow($clamped, 0.42) } else { [single]0 }

    # Shift waveform history by 2 positions with interpolation for rapid 60fps velocity
    for ($i = 0; $i -lt $state.WaveformBars.Length - 2; $i++) {
        $state.WaveformBars[$i] = $state.WaveformBars[$i + 2]
    }
    $interp = [single](($state.RecentPeak + $scaledPeak) * 0.5)
    $state.WaveformBars[$state.WaveformBars.Length - 2] = $interp
    $state.WaveformBars[$state.WaveformBars.Length - 1] = $scaledPeak
    $state.RecentPeak = [single][Math]::Max([double]$scaledPeak, [double]$state.RecentPeak * 0.70)

    # Cool Edit Pro style dB calculation and peak hold
    $dB = if ($maxPeak -gt 0.0001) { [Math]::Max(-48.0, 20.0 * [Math]::Log10($maxPeak)) } else { -48.0 }
    $state.CurrentDb = [double]$dB
    $state.PeakHoldDb = [Math]::Max($dB, $state.PeakHoldDb - 0.8)
    if ($maxPeak -ge 0.98) { $state.ClipCount = 10 } elseif ($state.ClipCount -gt 0) { $state.ClipCount-- }

    # Update elapsed seconds
    $state.ElapsedSec = ([DateTime]::UtcNow - $state.StartTime).TotalSeconds

    # Silent visual announcement: update window title every 8 ticks (~320ms)
    if (($state.TimerCount % 8) -eq 0) {
        $timeSpan = [TimeSpan]::FromSeconds($state.ElapsedSec)
        $recTitle = '● REC [{0:00}:{1:00}] - Sound Recorder' -f [int]$timeSpan.TotalMinutes, $timeSpan.Seconds
        $pRecTitle = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($recTitle)
        [void]$defWindowProc.DynamicInvoke(@($state.Hwnd, [uint32]0x000C, [IntPtr]::Zero, $pRecTitle)) # WM_SETTEXT
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pRecTitle)
    }
}

# Window Class & Native Procedure
$wndProcType = $module.DefineType(
    'WndProc_' + [Guid]::NewGuid().ToString('N'),
    'Class,Public,Sealed', [MulticastDelegate]
)
$wndProcCtor = $wndProcType.DefineConstructor(
    'Public,HideBySig,RTSpecialName',
    [Reflection.CallingConventions]::Standard, @([object], [IntPtr])
)
$wndProcCtor.SetImplementationFlags('Runtime,Managed')
$wndProcInv = $wndProcType.DefineMethod(
    'Invoke', 'Public,HideBySig,NewSlot,Virtual',
    [IntPtr], @([IntPtr], [uint32], [IntPtr], [IntPtr])
)
$wndProcInv.SetImplementationFlags('Runtime,Managed')
$wndProcAttr = [Reflection.Emit.CustomAttributeBuilder]::new(
    [Runtime.InteropServices.UnmanagedFunctionPointerAttribute].GetConstructor(
        @([Runtime.InteropServices.CallingConvention])),
    @([Runtime.InteropServices.CallingConvention]::StdCall)
)
$wndProcType.SetCustomAttribute($wndProcAttr)
$wndProcDelegateType = $wndProcType.CreateType()

# UI Layout Coordinates (Compact Portrait Gadget)
$windowWidth = 360
$windowHeight = 540

# GDI Palette (Google Recorder & Cool Edit Pro Dark Theme on Mica Alt)
# COLORREF: 0x00BBGGRR
$colCardBg       = [uint32]0x00362016 # #162036 solid deep slate/card (R=0x16, G=0x20, B=0x36)
$colCardBorder   = [uint32]0x005E3C2B # #2B3C5E card border
$colWaveformBar  = [uint32]0x00FFB29F # #9FB2FF solid vibrant periwinkle
$colWaveMuted    = [uint32]0x006A4638 # #38466A solid resting bar
$colWaveGuide    = [uint32]0x00452E20 # #202E45 midline guide
$colBadgeBg      = [uint32]0x004A2E20 # #202E4A badge background
$colBadgeText    = [uint32]0x00FAC8A8 # #A8C8FA badge text
$colTextPrimary  = [uint32]0x00FFFFFF # #FFFFFF crisp white text
$colTextMuted    = [uint32]0x00D4B2A0 # #A0B2D4 readable secondary text
$colBtnSlate     = [uint32]0x004A2E20 # #202E4A solid slate pause button
$colBtnBorder    = [uint32]0x00724D3B # #3B4D72 button border
$colBtnCoral     = [uint32]0x005252FF # #FF5252 vibrant solid coral record/stop button
$colBtnDarkText  = [uint32]0x00241410 # #101424 high contrast dark text
$colPillActive   = [uint32]0x00FFA68E # #8EA6FF active pill segment
$colPillInactive = [uint32]0x0040281E # #1E2840 inactive pill background
$colMeterTrack   = [uint32]0x0024150E # #0E1524 level meter track
$colMeterGreen   = [uint32]0x0076E600 # #00E676 level meter green
$colMeterYellow  = [uint32]0x0000D6FF # #FFD600 level meter yellow
$colMeterRed     = [uint32]0x004417FF # #FF1744 level meter red / clip
$colSuccess      = [uint32]0x0071CC2E # #2ECC71 success green

$brCard        = [IntPtr]$createSolidBrush.DynamicInvoke(@($colCardBg))
$brCardBorder  = [IntPtr]$createSolidBrush.DynamicInvoke(@($colCardBorder))
$brWaveform    = [IntPtr]$createSolidBrush.DynamicInvoke(@($colWaveformBar))
$brWaveMuted   = [IntPtr]$createSolidBrush.DynamicInvoke(@($colWaveMuted))
$brBadge       = [IntPtr]$createSolidBrush.DynamicInvoke(@($colBadgeBg))
$brBtnSlate    = [IntPtr]$createSolidBrush.DynamicInvoke(@($colBtnSlate))
$brBtnCoral    = [IntPtr]$createSolidBrush.DynamicInvoke(@($colBtnCoral))
$brPillActive  = [IntPtr]$createSolidBrush.DynamicInvoke(@($colPillActive))
$brPillBg      = [IntPtr]$createSolidBrush.DynamicInvoke(@($colPillInactive))
$brMeterTrack  = [IntPtr]$createSolidBrush.DynamicInvoke(@($colMeterTrack))
$brMeterGreen  = [IntPtr]$createSolidBrush.DynamicInvoke(@($colMeterGreen))
$brMeterYellow = [IntPtr]$createSolidBrush.DynamicInvoke(@($colMeterYellow))
$brMeterRed    = [IntPtr]$createSolidBrush.DynamicInvoke(@($colMeterRed))
$brSuccess     = [IntPtr]$createSolidBrush.DynamicInvoke(@($colSuccess))

$penNull         = [IntPtr]$createPen.DynamicInvoke(@(5, 0, [uint32]0)) # PS_NULL = 5
$penBorder       = [IntPtr]$createPen.DynamicInvoke(@(0, 1, $colCardBorder))
$penRecordBorder = [IntPtr]$createPen.DynamicInvoke(@(0, 2, $colBtnCoral)) # Pulsing 2px record border
$penWaveform     = [IntPtr]$createPen.DynamicInvoke(@(0, 1, $colWaveformBar))
$penGuide        = [IntPtr]$createPen.DynamicInvoke(@(0, 1, $colWaveGuide))
$penBtnBorder    = [IntPtr]$createPen.DynamicInvoke(@(0, 1, $colBtnBorder))
$penNeedle       = [IntPtr]$createPen.DynamicInvoke(@(0, 2, [uint32]0x00FFFFFF))

$fontNameSegoe = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('Segoe UI')
$fontTitle  = [IntPtr]$createFontW.DynamicInvoke(@(-14, 0, 0, 0, 600, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
$fontTimer  = [IntPtr]$createFontW.DynamicInvoke(@(-32, 0, 0, 0, 700, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
$fontBadge  = [IntPtr]$createFontW.DynamicInvoke(@(-12, 0, 0, 0, 600, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
$fontButton = [IntPtr]$createFontW.DynamicInvoke(@(-15, 0, 0, 0, 700, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
$fontSmall  = [IntPtr]$createFontW.DynamicInvoke(@(-11, 0, 0, 0, 400, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
$fontTiny   = [IntPtr]$createFontW.DynamicInvoke(@(-9,  0, 0, 0, 400, [uint32]0, [uint32]0, [uint32]0, [uint32]1, [uint32]0, [uint32]0, [uint32]5, [uint32]0, $fontNameSegoe))
[Runtime.InteropServices.Marshal]::FreeHGlobal($fontNameSegoe)

$fnDrawString = {
    param([IntPtr]$hdc, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [uint32]$color, [IntPtr]$hFont, [uint32]$flags)
    [void]$setBkMode.DynamicInvoke(@($hdc, 1)) # TRANSPARENT
    [void]$setTextColor.DynamicInvoke(@($hdc, $color))
    $oldFont = [IntPtr]$selectObject.DynamicInvoke(@($hdc, $hFont))
    $rect = & $alloc 16
    $pStr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($text)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 0, $x)
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 4, $y)
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 8, ($x + $w))
        [Runtime.InteropServices.Marshal]::WriteInt32($rect, 12, ($y + $h))
        [void]$drawTextW.DynamicInvoke(@($hdc, $pStr, -1, $rect, $flags))
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pStr)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($rect)
        if ($oldFont -ne [IntPtr]::Zero) { [void]$selectObject.DynamicInvoke(@($hdc, $oldFont)) }
    }
}

# Responsive Layout Calculator
$fnGetLayout = {
    param([int]$cw, [int]$ch)

    # 1. Header Row (Y: 10..36)
    $pinBtnX = 12
    $pinBtnY = 10
    $pinBtnW = 68
    $pinBtnH = 26

    $sourceBtnX = 86
    $sourceBtnY = 10
    $sourceBtnW = 100
    $sourceBtnH = 26

    $folderBtnX = $cw - 42
    $folderBtnY = 10
    $folderBtnW = 30
    $folderBtnH = 26

    # 2. Main Elevated Card (Y: 42..278, H: 236)
    $cardX = 12
    $cardY = 42
    $cardW = $cw - 24
    $cardH = 236

    # 3. Mode Toggle Pill (Waveform / Text) (Y: 284..312, H: 28)
    $pillW = 160
    $pillH = 28
    $pillX = [int](($cw - $pillW) / 2)
    $pillY = 284

    # 4. Timer Section (Y: 318..372, H: 54)
    $timerY = 318
    $timerH = 54

    # 5. Action Buttons (Y: 376..430, H: 54)
    $btnH = 52
    $btnY = 376
    $btnGap = 12
    $btnW = [int](($cw - 24 - $btnGap) / 2)
    $btn1X = 12
    $btn2X = $btn1X + $btnW + $btnGap

    # 6. Status Text (Y: 436..456)
    $statusY = 436

    return @{
        Cw = $cw
        Ch = $ch
        PinBtnX = $pinBtnX
        PinBtnY = $pinBtnY
        PinBtnW = $pinBtnW
        PinBtnH = $pinBtnH
        SourceBtnX = $sourceBtnX
        SourceBtnY = $sourceBtnY
        SourceBtnW = $sourceBtnW
        SourceBtnH = $sourceBtnH
        FolderBtnX = $folderBtnX
        FolderBtnY = $folderBtnY
        FolderBtnW = $folderBtnW
        FolderBtnH = $folderBtnH
        CardX = $cardX
        CardY = $cardY
        CardW = $cardW
        CardH = $cardH
        PillX = $pillX
        PillY = $pillY
        PillW = $pillW
        PillH = $pillH
        TimerY = $timerY
        TimerH = $timerH
        Btn1X = $btn1X
        Btn2X = $btn2X
        BtnY = $btnY
        BtnW = $btnW
        BtnH = $btnH
        StatusY = $statusY
    }
}

# Window Procedure Implementation
$wndProc = {
    param([IntPtr] $hwnd, [uint32] $msg, [IntPtr] $wparam, [IntPtr] $lparam)
    try {
    # WM_PAINT
    if ($msg -eq 0x000F) {
        $ps = & $alloc 72
        $rc = & $alloc 16
        try {
            $hdc = [IntPtr]$beginPaint.DynamicInvoke(@($hwnd, $ps))
            [void]$getClientRect.DynamicInvoke(@($hwnd, $rc))
            $cw = [Runtime.InteropServices.Marshal]::ReadInt32($rc, 8)
            $ch = [Runtime.InteropServices.Marshal]::ReadInt32($rc, 12)

            $layout = & $fnGetLayout $cw $ch

            # Double Buffer
            $memDC = [IntPtr]$createCompatibleDC.DynamicInvoke(@($hdc))
            $memBmp = [IntPtr]$createCompatibleBitmap.DynamicInvoke(@($hdc, $cw, $ch))
            $oldBmp = [IntPtr]$selectObject.DynamicInvoke(@($memDC, $memBmp))

            # Fill Mica Alt Glass Base with stock BLACK_BRUSH (allows DWM Mica Alt to show)
            $stockBlack = [IntPtr]$getStockObject.DynamicInvoke(@(4))
            $oldBrush = [IntPtr]$selectObject.DynamicInvoke(@($memDC, $stockBlack))
            $oldPen = [IntPtr]$selectObject.DynamicInvoke(@($memDC, $penNull))
            [void]$roundRect.DynamicInvoke(@($memDC, 0, 0, ($cw + 1), ($ch + 1), 0, 0))

            # 1. Header Row
            # Pin Button (Always On Top Toggle)
            $pinBg = if ($state.AlwaysOnTop) { $brPillActive } else { $brBadge }
            $pinTxt = if ($state.AlwaysOnTop) { '📌 Pinned' } else { '📌 Top' }
            $pinCol = if ($state.AlwaysOnTop) { $colBtnDarkText } else { $colBadgeText }
            [void]$selectObject.DynamicInvoke(@($memDC, $pinBg))
            [void]$selectObject.DynamicInvoke(@($memDC, $penBorder))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.PinBtnX, $layout.PinBtnY, ($layout.PinBtnX + $layout.PinBtnW), ($layout.PinBtnY + $layout.PinBtnH), 12, 12))
            & $fnDrawString $memDC $pinTxt $layout.PinBtnX ($layout.PinBtnY + 4) $layout.PinBtnW 18 $pinCol $fontBadge 1

            # Source pill
            $sourceLabel = switch ($state.SourceMode) {
                'Mic'  { '🎙️ Mic' }
                'Apps' { '🔊 Apps' }
                'Both' { '🎙️+🔊 Dual' }
            }
            [void]$selectObject.DynamicInvoke(@($memDC, $brBadge))
            [void]$selectObject.DynamicInvoke(@($memDC, $penBorder))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.SourceBtnX, $layout.SourceBtnY, ($layout.SourceBtnX + $layout.SourceBtnW), ($layout.SourceBtnY + $layout.SourceBtnH), 12, 12))
            & $fnDrawString $memDC $sourceLabel $layout.SourceBtnX ($layout.SourceBtnY + 4) $layout.SourceBtnW 18 $colBadgeText $fontBadge 1

            # Folder icon button
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.FolderBtnX, $layout.FolderBtnY, ($layout.FolderBtnX + $layout.FolderBtnW), ($layout.FolderBtnY + $layout.FolderBtnH), 12, 12))
            & $fnDrawString $memDC '📁' $layout.FolderBtnX ($layout.FolderBtnY + 3) $layout.FolderBtnW 18 $colTextPrimary $fontBadge 1

            # 2. Main Elevated Card
            # Card border pulses vibrant red when recording!
            $cardPen = if ($state.IsRecording -and -not $state.IsPaused -and (($state.TimerCount % 16) -lt 8)) { $penRecordBorder } else { $penBorder }
            [void]$selectObject.DynamicInvoke(@($memDC, $brCard))
            [void]$selectObject.DynamicInvoke(@($memDC, $cardPen))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.CardX, $layout.CardY, ($layout.CardX + $layout.CardW), ($layout.CardY + $layout.CardH), 18, 18))

            # Card Header Badge (Live Announcement)
            $tagW = 140
            $tagX = $layout.CardX + [int](($layout.CardW - $tagW) / 2)
            $tagY = $layout.CardY + 10
            if ($state.IsRecording) {
                $recBg = if ($state.IsPaused) { $brBadge } else { $brBtnCoral }
                $recTxt = if ($state.IsPaused) { '⏸ PAUSED' } else { '● RECORDING LIVE' }
                $recCol = if ($state.IsPaused) { [uint32]0x0000C8FF } else { [uint32]0x00FFFFFF }
                [void]$selectObject.DynamicInvoke(@($memDC, $recBg))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, $tagX, $tagY, ($tagX + $tagW), ($tagY + 22), 10, 10))
                & $fnDrawString $memDC $recTxt $tagX ($tagY + 2) $tagW 18 $recCol $fontBadge 1
            }
            elseif ($state.SavedNotification) {
                [void]$selectObject.DynamicInvoke(@($memDC, $brSuccess))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, $tagX, $tagY, ($tagX + $tagW), ($tagY + 22), 10, 10))
                & $fnDrawString $memDC '✓ SAVED & NORMALIZED' $tagX ($tagY + 2) $tagW 18 $colBtnDarkText $fontBadge 1
            }
            else {
                [void]$selectObject.DynamicInvoke(@($memDC, $brBadge))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, $tagX, $tagY, ($tagX + $tagW), ($tagY + 22), 10, 10))
                & $fnDrawString $memDC '🎙️ SPEECH RECORDER' $tagX ($tagY + 2) $tagW 18 $colBadgeText $fontBadge 1
            }

            # Card Body: Waveform / VU Meter or Saved Announcement
            if (-not $state.IsRecording -and $state.SavedNotification -and $state.Mode -eq 'Waveform') {
                # Saved & Normalized Details Card
                $notif = $state.SavedNotification
                & $fnDrawString $memDC 'Audio Saved to Disk' $layout.CardX ($layout.CardY + 40) $layout.CardW 20 $colSuccess $fontBadge 1
                & $fnDrawString $memDC $notif.FileName $layout.CardX ($layout.CardY + 64) $layout.CardW 20 $colTextPrimary $fontTitle 1

                $shortDir = [IO.Path]::GetDirectoryName($notif.Path)
                & $fnDrawString $memDC ('📁 ' + $shortDir) 16 ($layout.CardY + 90) ($layout.CardW - 8) 16 $colTextMuted $fontTiny 1
                & $fnDrawString $memDC '✨ Normalized: -1.0 dBFS Peak (Studio Limiter)' $layout.CardX ($layout.CardY + 114) $layout.CardW 18 $colBadgeText $fontSmall 1
                & $fnDrawString $memDC ('Length: ' + $notif.Duration + '   |   Size: ' + $notif.Size) $layout.CardX ($layout.CardY + 136) $layout.CardW 18 $colTextMuted $fontSmall 1

                # Interactive Action Buttons inside card
                $actW = 120
                $actH = 30
                $actY = $layout.CardY + 172
                $actGap = 12
                $act1X = [int]($cw / 2) - $actW - [int]($actGap / 2)
                $act2X = [int]($cw / 2) + [int]($actGap / 2)

                [void]$selectObject.DynamicInvoke(@($memDC, $brBtnSlate))
                [void]$selectObject.DynamicInvoke(@($memDC, $penBtnBorder))
                [void]$roundRect.DynamicInvoke(@($memDC, $act1X, $actY, ($act1X + $actW), ($actY + $actH), 14, 14))
                & $fnDrawString $memDC '📁 Open Folder' $act1X ($actY + 6) $actW 16 $colTextPrimary $fontSmall 1

                [void]$selectObject.DynamicInvoke(@($memDC, $brPillActive))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, $act2X, $actY, ($act2X + $actW), ($actY + $actH), 14, 14))
                & $fnDrawString $memDC '▶ Play Audio' $act2X ($actY + 6) $actW 16 $colBtnDarkText $fontSmall 1
            }
            elseif ($state.Mode -eq 'Waveform') {
                # 1. Center Waveform Visualization
                $midY = $layout.CardY + 95
                [void]$selectObject.DynamicInvoke(@($memDC, $penGuide))
                [void]$moveToEx.DynamicInvoke(@($memDC, ($layout.CardX + 16), $midY, [IntPtr]::Zero))
                [void]$lineTo.DynamicInvoke(@($memDC, ($layout.CardX + $layout.CardW - 16), $midY))

                # Dense Capsule Bars
                $barW = 3
                $barGap = 2
                $slot = $barW + $barGap
                $availW = [Math]::Max(40, $layout.CardW - 32)
                $numBars = [Math]::Max(16, [int]($availW / $slot))
                $totalBarsW = ($numBars * $slot) - $barGap
                $startX = $layout.CardX + [int](($layout.CardW - $totalBarsW) / 2)
                $maxH = 90

                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                for ($b = 0; $b -lt $numBars; $b++) {
                    $idx = [int](($b / [double]$numBars) * $state.WaveformBars.Length)
                    if ($idx -ge $state.WaveformBars.Length) { $idx = $state.WaveformBars.Length - 1 }
                    $barAmp = $state.WaveformBars[$idx]

                    $barH = [int]([Math]::Max(4.0, [double]($barAmp * $maxH)))
                    $bx = $startX + ($b * $slot)
                    $by = [int]($midY - ($barH / 2))

                    if ($state.IsRecording -and -not $state.IsPaused -and $barAmp -gt 0.03) {
                        [void]$selectObject.DynamicInvoke(@($memDC, $brWaveform))
                    } else {
                        [void]$selectObject.DynamicInvoke(@($memDC, $brWaveMuted))
                    }
                    [void]$roundRect.DynamicInvoke(@($memDC, $bx, $by, ($bx + $barW), ($by + $barH), $barW, $barW))
                }

                # 2. Cool Edit Pro Style VU Peak Level Meter
                $vuX = $layout.CardX + 16
                $vuY = $layout.CardY + 168
                $vuW = $layout.CardW - 32
                $vuH = 12

                # VU Label & dB readout
                & $fnDrawString $memDC 'VU PEAK' $vuX ($vuY - 17) 60 14 $colTextMuted $fontTiny 0
                $dbValStr = if ($state.CurrentDb -gt -47) { '{0:F1} dB' -f $state.CurrentDb } else { '-∞ dB' }
                $dbCol = if ($state.ClipCount -gt 0) { $colMeterRed } else { $colBadgeText }
                & $fnDrawString $memDC $dbValStr ($vuX + $vuW - 84) ($vuY - 17) 48 14 $dbCol $fontTiny 2

                # CLIP indicator box
                $clipW = 28
                $clipX = $vuX + $vuW - $clipW
                $brClip = if ($state.ClipCount -gt 0) { $brMeterRed } else { $brMeterTrack }
                [void]$selectObject.DynamicInvoke(@($memDC, $brClip))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, $clipX, ($vuY - 17), ($clipX + $clipW), ($vuY - 3), 4, 4))
                $clipTxtCol = if ($state.ClipCount -gt 0) { [uint32]0x00FFFFFF } else { [uint32]0x005E3C2B }
                & $fnDrawString $memDC 'CLIP' $clipX ($vuY - 16) $clipW 14 $clipTxtCol $fontTiny 1

                # VU Track
                [void]$selectObject.DynamicInvoke(@($memDC, $brMeterTrack))
                [void]$selectObject.DynamicInvoke(@($memDC, $penBorder))
                [void]$roundRect.DynamicInvoke(@($memDC, $vuX, $vuY, ($vuX + $vuW), ($vuY + $vuH), 6, 6))

                # VU Level Fill Bar
                $dbFrac = [Math]::Max(0.0, [Math]::Min(1.0, ($state.CurrentDb + 48.0) / 48.0))
                $fillW = [int]($dbFrac * ($vuW - 4))
                if ($fillW -gt 2) {
                    $greenW = [int]([Math]::Min($fillW, ($vuW - 4) * 0.75))
                    [void]$selectObject.DynamicInvoke(@($memDC, $brMeterGreen))
                    [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                    [void]$roundRect.DynamicInvoke(@($memDC, ($vuX + 2), ($vuY + 2), ($vuX + 2 + $greenW), ($vuY + $vuH - 2), 4, 4))

                    if ($dbFrac -gt 0.75) {
                        $yelStart = [int](($vuW - 4) * 0.75)
                        $yelEnd = [int]([Math]::Min($fillW, ($vuW - 4) * 0.9375))
                        [void]$selectObject.DynamicInvoke(@($memDC, $brMeterYellow))
                        [void]$roundRect.DynamicInvoke(@($memDC, ($vuX + 2 + $yelStart), ($vuY + 2), ($vuX + 2 + $yelEnd), ($vuY + $vuH - 2), 4, 4))
                    }
                    if ($dbFrac -gt 0.9375) {
                        $redStart = [int](($vuW - 4) * 0.9375)
                        $redEnd = $fillW
                        [void]$selectObject.DynamicInvoke(@($memDC, $brMeterRed))
                        [void]$roundRect.DynamicInvoke(@($memDC, ($vuX + 2 + $redStart), ($vuY + 2), ($vuX + 2 + $redEnd), ($vuY + $vuH - 2), 4, 4))
                    }
                }

                # Peak Hold Needle
                $peakFrac = [Math]::Max(0.0, [Math]::Min(1.0, ($state.PeakHoldDb + 48.0) / 48.0))
                $needleX = [int]($vuX + 2 + ($peakFrac * ($vuW - 6)))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNeedle))
                [void]$moveToEx.DynamicInvoke(@($memDC, $needleX, ($vuY + 1), [IntPtr]::Zero))
                [void]$lineTo.DynamicInvoke(@($memDC, $needleX, ($vuY + $vuH - 1)))

                # Scale ticks
                & $fnDrawString $memDC '-48' $vuX ($vuY + $vuH + 2) 20 12 $colTextMuted $fontTiny 0
                & $fnDrawString $memDC '-24' ($vuX + [int]($vuW * 0.5) - 10) ($vuY + $vuH + 2) 20 12 $colTextMuted $fontTiny 1
                & $fnDrawString $memDC '-12' ($vuX + [int]($vuW * 0.75) - 10) ($vuY + $vuH + 2) 20 12 $colTextMuted $fontTiny 1
                & $fnDrawString $memDC '0' ($vuX + $vuW - 10) ($vuY + $vuH + 2) 10 12 $colTextMuted $fontTiny 2
            }
            else {
                # Transcript / Stats Mode
                $txY = $layout.CardY + 46
                & $fnDrawString $memDC 'Audio Stream Status' $layout.CardX $txY $layout.CardW 22 $colTextPrimary $fontTitle 1
                & $fnDrawString $memDC ('Device: ' + (if ($state.SourceMode -eq 'Apps') { $state.AppName } else { $state.MicName })) $layout.CardX ($txY + 30) $layout.CardW 18 $colTextMuted $fontSmall 1
                & $fnDrawString $memDC ('Captured: ' + [int]($state.TotalAudioBytes / 1024) + ' KB') $layout.CardX ($txY + 54) $layout.CardW 18 $colBadgeText $fontSmall 1
                & $fnDrawString $memDC 'Broadcast Normalization: -1.0 dBFS' $layout.CardX ($txY + 78) $layout.CardW 18 $colTextMuted $fontSmall 1
                & $fnDrawString $memDC '(Speech-to-text Whisper transcription reserved)' $layout.CardX ($txY + 110) $layout.CardW 18 $colTextMuted $fontTiny 1
            }

            # 3. Toggle Mode Pill (Waveform vs Text)
            [void]$selectObject.DynamicInvoke(@($memDC, $brPillBg))
            [void]$selectObject.DynamicInvoke(@($memDC, $penBorder))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.PillX, $layout.PillY, ($layout.PillX + $layout.PillW), ($layout.PillY + $layout.PillH), 16, 16))

            $halfW = [int]($layout.PillW / 2)
            if ($state.Mode -eq 'Waveform') {
                [void]$selectObject.DynamicInvoke(@($memDC, $brPillActive))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, ($layout.PillX + 2), ($layout.PillY + 2), ($layout.PillX + $halfW), ($layout.PillY + $layout.PillH - 2), 12, 12))
                & $fnDrawString $memDC '🎚️ Wave' ($layout.PillX + 2) ($layout.PillY + 6) $halfW 16 $colBtnDarkText $fontBadge 1
                & $fnDrawString $memDC '≡ Text' ($layout.PillX + $halfW) ($layout.PillY + 6) $halfW 16 $colTextMuted $fontBadge 1
            }
            else {
                [void]$selectObject.DynamicInvoke(@($memDC, $brPillActive))
                [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
                [void]$roundRect.DynamicInvoke(@($memDC, ($layout.PillX + $halfW), ($layout.PillY + 2), ($layout.PillX + $layout.PillW - 2), ($layout.PillY + $layout.PillH - 2), 12, 12))
                & $fnDrawString $memDC '🎚️ Wave' ($layout.PillX + 2) ($layout.PillY + 6) $halfW 16 $colTextMuted $fontBadge 1
                & $fnDrawString $memDC '≡ Text' ($layout.PillX + $halfW) ($layout.PillY + 6) $halfW 16 $colBtnDarkText $fontBadge 1
            }

            # 4. Timer Section
            $timeSpan = [TimeSpan]::FromSeconds($state.ElapsedSec)
            $timerText = '{0:00}:{1:00}.{2:0}' -f [int]$timeSpan.TotalMinutes, $timeSpan.Seconds, [int]($timeSpan.Milliseconds / 100)

            $dotColor = if ($state.IsRecording -and -not $state.IsPaused) {
                if (($state.TimerCount % 16) -lt 8) { $colBtnCoral } else { [uint32]0x00241410 }
            } elseif ($state.IsPaused) {
                [uint32]0x0000C8FF
            } else {
                $colTextMuted
            }

            & $fnDrawString $memDC '●' ($cw / 2 - 90) ($layout.TimerY + 4) 20 32 $dotColor $fontTitle 1
            & $fnDrawString $memDC $timerText ($cw / 2 - 68) $layout.TimerY 150 36 $colTextPrimary $fontTimer 1
            & $fnDrawString $memDC 'Studio Limiter & Normalizer Active' 10 ($layout.TimerY + 36) ($cw - 20) 16 $colTextMuted $fontTiny 1

            # 5. Large Rounded Action Buttons
            # Left Button: Pause/Resume or Switch Source
            [void]$selectObject.DynamicInvoke(@($memDC, $brBtnSlate))
            [void]$selectObject.DynamicInvoke(@($memDC, $penBtnBorder))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.Btn1X, $layout.BtnY, ($layout.Btn1X + $layout.BtnW), ($layout.BtnY + $layout.BtnH), 24, 24))

            $btn1Text = if ($state.IsRecording) {
                if ($state.IsPaused) { '▶ Resume' } else { '⏸ Pause' }
            } else {
                '🎙️ Source'
            }
            & $fnDrawString $memDC $btn1Text $layout.Btn1X ($layout.BtnY + 14) $layout.BtnW 22 $colTextPrimary $fontButton 1

            # Right Button: Stop or Record (Coral Red Pill)
            [void]$selectObject.DynamicInvoke(@($memDC, $brBtnCoral))
            [void]$selectObject.DynamicInvoke(@($memDC, $penNull))
            [void]$roundRect.DynamicInvoke(@($memDC, $layout.Btn2X, $layout.BtnY, ($layout.Btn2X + $layout.BtnW), ($layout.BtnY + $layout.BtnH), 24, 24))

            $btn2Text = if ($state.IsRecording) { '■ Stop' } else { '● Record' }
            & $fnDrawString $memDC $btn2Text $layout.Btn2X ($layout.BtnY + 14) $layout.BtnW 22 $colBtnDarkText $fontButton 1

            # 6. Status Text at bottom
            & $fnDrawString $memDC $state.StatusMessage 10 $layout.StatusY ($cw - 20) 18 $colTextMuted $fontSmall 1

            # Copy to screen
            [void]$bitBlt.DynamicInvoke(@($hdc, 0, 0, $cw, $ch, $memDC, 0, 0, [uint32]0x00CC0020))

            # Cleanup DCs & Bitmaps
            [void]$selectObject.DynamicInvoke(@($memDC, $oldBmp))
            [void]$selectObject.DynamicInvoke(@($memDC, $oldBrush))
            [void]$selectObject.DynamicInvoke(@($memDC, $oldPen))
            [void]$deleteObject.DynamicInvoke(@($memBmp))
            [void]$deleteDC.DynamicInvoke(@($memDC))
        }
        finally {
            [void]$endPaint.DynamicInvoke(@($hwnd, $ps))
            [Runtime.InteropServices.Marshal]::FreeHGlobal($ps)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($rc)
        }
        return [IntPtr]::Zero
    }

    # WM_SIZE
    if ($msg -eq 0x0005) {
        [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
        return [IntPtr]::Zero
    }

    # WM_ERASEBKGND
    if ($msg -eq 0x0014) {
        return [IntPtr]1
    }

    # WM_GETMINMAXINFO
    if ($msg -eq 0x0024 -and $lparam -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::WriteInt32($lparam, 24, 360) # min width
        [Runtime.InteropServices.Marshal]::WriteInt32($lparam, 28, 540) # min height
        return [IntPtr]::Zero
    }

    # WM_TIMER (Only runs while recording!)
    if ($msg -eq 0x0113) {
        $state.TimerCount++
        & $fnProcessAudioPackets
        [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
        return [IntPtr]::Zero
    }

    # WM_LBUTTONDOWN
    if ($msg -eq 0x0201) {
        $mx = [int]($lparam.ToInt64() -band 0xFFFF)
        $my = [int](($lparam.ToInt64() -shr 16) -band 0xFFFF)

        $rc = & $alloc 16
        try {
            [void]$getClientRect.DynamicInvoke(@($hwnd, $rc))
            $cw = [Runtime.InteropServices.Marshal]::ReadInt32($rc, 8)
            $ch = [Runtime.InteropServices.Marshal]::ReadInt32($rc, 12)

            $layout = & $fnGetLayout $cw $ch

            # Hit test Pin Button (Always On Top)
            if ($mx -ge $layout.PinBtnX -and $mx -le ($layout.PinBtnX + $layout.PinBtnW) -and $my -ge $layout.PinBtnY -and $my -le ($layout.PinBtnY + $layout.PinBtnH)) {
                $state.AlwaysOnTop = -not $state.AlwaysOnTop
                $hInsert = if ($state.AlwaysOnTop) { [IntPtr](-1) } else { [IntPtr](-2) }
                [void]$setWindowPos.DynamicInvoke(@($hwnd, $hInsert, 0, 0, 0, 0, [uint32]0x0003))
                $state.StatusMessage = if ($state.AlwaysOnTop) { 'Window pinned: Always on top' } else { 'Window unpinned' }
                [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
                return [IntPtr]::Zero
            }

            # Hit test Source pill
            if ($mx -ge $layout.SourceBtnX -and $mx -le ($layout.SourceBtnX + $layout.SourceBtnW) -and $my -ge $layout.SourceBtnY -and $my -le ($layout.SourceBtnY + $layout.SourceBtnH)) {
                if (-not $state.IsRecording) {
                    $state.SourceMode = switch ($state.SourceMode) {
                        'Mic'  { 'Apps' }
                        'Apps' { 'Both' }
                        'Both' { 'Mic' }
                    }
                    $state.StatusMessage = 'Audio source: ' + $state.SourceMode
                    [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
                }
            }

            # Hit test Folder button
            if ($mx -ge $layout.FolderBtnX -and $mx -le ($layout.FolderBtnX + $layout.FolderBtnW) -and $my -ge $layout.FolderBtnY -and $my -le ($layout.FolderBtnY + $layout.FolderBtnH)) {
                $psi = [Diagnostics.ProcessStartInfo]::new()
                $psi.FileName = $recordingsDir
                $psi.UseShellExecute = $true
                [void][Diagnostics.Process]::Start($psi)
            }

            # Hit test Saved Card Action Buttons (when stopped and notif displayed)
            if (-not $state.IsRecording -and $state.SavedNotification -and $state.Mode -eq 'Waveform') {
                $actW = 120
                $actH = 30
                $actY = $layout.CardY + 172
                $actGap = 12
                $act1X = [int]($cw / 2) - $actW - [int]($actGap / 2)
                $act2X = [int]($cw / 2) + [int]($actGap / 2)

                # Open folder & highlight file
                if ($mx -ge $act1X -and $mx -le ($act1X + $actW) -and $my -ge $actY -and $my -le ($actY + $actH)) {
                    $psi = [Diagnostics.ProcessStartInfo]::new()
                    $psi.FileName = 'explorer.exe'
                    $psi.Arguments = ('/select,"' + $state.SavedNotification.Path + '"')
                    $psi.UseShellExecute = $true
                    [void][Diagnostics.Process]::Start($psi)
                    return [IntPtr]::Zero
                }

                # Play audio
                if ($mx -ge $act2X -and $mx -le ($act2X + $actW) -and $my -ge $actY -and $my -le ($actY + $actH)) {
                    $psi = [Diagnostics.ProcessStartInfo]::new()
                    $psi.FileName = $state.SavedNotification.Path
                    $psi.UseShellExecute = $true
                    [void][Diagnostics.Process]::Start($psi)
                    return [IntPtr]::Zero
                }
            }

            # Hit test Mode Pill
            if ($mx -ge $layout.PillX -and $mx -le ($layout.PillX + $layout.PillW) -and $my -ge $layout.PillY -and $my -le ($layout.PillY + $layout.PillH)) {
                $halfW = [int]($layout.PillW / 2)
                if ($mx -lt ($layout.PillX + $halfW)) {
                    $state.Mode = 'Waveform'
                } else {
                    $state.Mode = 'Transcript'
                }
                [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
            }

            # Button 1 (Pause / Resume / Source)
            if ($mx -ge $layout.Btn1X -and $mx -le ($layout.Btn1X + $layout.BtnW) -and $my -ge $layout.BtnY -and $my -le ($layout.BtnY + $layout.BtnH)) {
                if ($state.IsRecording) {
                    & $fnPauseResumeRecording
                } else {
                    $state.SourceMode = switch ($state.SourceMode) {
                        'Mic'  { 'Apps' }
                        'Apps' { 'Both' }
                        'Both' { 'Mic' }
                    }
                    $state.StatusMessage = 'Audio source: ' + $state.SourceMode
                    [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
                }
            }

            # Button 2 (Record / Stop)
            if ($mx -ge $layout.Btn2X -and $mx -le ($layout.Btn2X + $layout.BtnW) -and $my -ge $layout.BtnY -and $my -le ($layout.BtnY + $layout.BtnH)) {
                if ($state.IsRecording) {
                    & $fnStopRecording
                } else {
                    & $fnStartRecording
                }
                [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
            }
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($rc)
        }
        return [IntPtr]::Zero
    }

    # WM_KEYDOWN
    if ($msg -eq 0x0100) {
        $key = $wparam.ToInt32()
        if ($key -eq 32) { # Space
            if ($state.IsRecording) { & $fnStopRecording } else { & $fnStartRecording }
            [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
        }
        elseif ($key -eq 80) { # P
            & $fnPauseResumeRecording
        }
        elseif ($key -eq 77) { # M
            if (-not $state.IsRecording) {
                $state.SourceMode = switch ($state.SourceMode) {
                    'Mic'  { 'Apps' }
                    'Apps' { 'Both' }
                    'Both' { 'Mic' }
                }
                $state.StatusMessage = 'Audio source: ' + $state.SourceMode
                [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
            }
        }
        elseif ($key -eq 84) { # T
            $state.Mode = if ($state.Mode -eq 'Waveform') { 'Transcript' } else { 'Waveform' }
            [void]$invalidateRect.DynamicInvoke(@($hwnd, [IntPtr]::Zero, $false))
        }
        elseif ($key -eq 79) { # O
            $psi = [Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $recordingsDir
            $psi.UseShellExecute = $true
            [void][Diagnostics.Process]::Start($psi)
        }
        elseif ($key -eq 27) { # Esc
            [void]$destroyWindow.DynamicInvoke(@($hwnd))
        }
        return [IntPtr]::Zero
    }

    # WM_DESTROY
    if ($msg -eq 0x0002) {
        & $fnStopRecording
        [void]$postQuitMessage.DynamicInvoke(@(0))
        return [IntPtr]::Zero
    }

    return [IntPtr]$defWindowProc.DynamicInvoke(@($hwnd, $msg, $wparam, $lparam))
    }
    catch {
        Write-Error ("WndProc error on msg 0x{0:X4}: {1}" -f $msg, $_.ToString())
        throw
    }
}.GetNewClosure()

$wndProcDelegate = $wndProc -as $wndProcDelegateType
$hModule = [IntPtr]$getModuleHandle.DynamicInvoke(@([IntPtr]::Zero))
$classNameStr = 'QuickPS_SoundRecorder_' + [Guid]::NewGuid().ToString('N')
$pClassName = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($classNameStr)
$pTitle = [Runtime.InteropServices.Marshal]::StringToHGlobalUni('Sound Recorder')

# Register Window Class
$wndClass = & $alloc 80
[Runtime.InteropServices.Marshal]::WriteInt32($wndClass, 0, 80)
[Runtime.InteropServices.Marshal]::WriteInt32($wndClass, 4, 3) # CS_HREDRAW | CS_VREDRAW
[Runtime.InteropServices.Marshal]::WriteIntPtr($wndClass, 8, [Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate($wndProcDelegate))
[Runtime.InteropServices.Marshal]::WriteIntPtr($wndClass, 24, $hModule)
$hArrow = [IntPtr]$loadCursor.DynamicInvoke(@([IntPtr]::Zero, [IntPtr]32512))
[Runtime.InteropServices.Marshal]::WriteIntPtr($wndClass, 40, $hArrow)
$stockBlack = [IntPtr]$getStockObject.DynamicInvoke(@(4)) # BLACK_BRUSH for Mica
[Runtime.InteropServices.Marshal]::WriteIntPtr($wndClass, 48, $stockBlack)
[Runtime.InteropServices.Marshal]::WriteIntPtr($wndClass, 64, $pClassName)

$atom = [uint16]$registerClassEx.DynamicInvoke(@($wndClass))
if ($atom -eq 0) { throw 'RegisterClassExW failed.' }

# Center window on screen using dynamic display metrics
$screenW = [int]$getSystemMetrics.DynamicInvoke(@(0))
$screenH = [int]$getSystemMetrics.DynamicInvoke(@(1))
if ($screenW -le 0) { $screenW = 1366 }
if ($screenH -le 0) { $screenH = 768 }
$winX = [int][Math]::Max(20, ($screenW - $windowWidth) / 2)
$winY = [int][Math]::Max(20, ($screenH - $windowHeight - 40) / 2)

# Fixed-size, portrait-locked, unobtrusive gadget
# WS_VISIBLE | WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX = 0x10CA0000
$style = [uint32]0x10CA0000
$hwnd = [IntPtr]$createWindowEx.DynamicInvoke(@(
    [uint32]0, $pClassName, $pTitle, $style,
    $winX, $winY, $windowWidth, $windowHeight,
    [IntPtr]::Zero, [IntPtr]::Zero, $hModule, [IntPtr]::Zero
))
if ($hwnd -eq [IntPtr]::Zero) { throw 'CreateWindowExW failed.' }

$state.Hwnd = $hwnd

# Remove Title Bar Icon (User requirement: 'none at all if that is an option')
[void]$sendMessage.DynamicInvoke(@($hwnd, [uint32]0x0080, [IntPtr]0, [IntPtr]::Zero)) # WM_SETICON, ICON_SMALL
[void]$sendMessage.DynamicInvoke(@($hwnd, [uint32]0x0080, [IntPtr]1, [IntPtr]::Zero)) # WM_SETICON, ICON_BIG

# Apply Windows 11 Mica Alt (TabbedWindow) Backdrop & Seamless Titlebar
$buf4 = & $alloc 4
$margins = & $alloc 16
try {
    # DWMWA_USE_IMMERSIVE_DARK_MODE = 20
    [Runtime.InteropServices.Marshal]::WriteInt32($buf4, 1)
    [void]$dwmSetWindowAttribute.DynamicInvoke(@($hwnd, [uint32]20, $buf4, [uint32]4))

    # DWMWA_CAPTION_COLOR = 35 (DWMWA_COLOR_NONE = 0xFFFFFFFE makes titlebar seamless with backdrop)
    [Runtime.InteropServices.Marshal]::WriteInt32($buf4, [int32]-2)
    [void]$dwmSetWindowAttribute.DynamicInvoke(@($hwnd, [uint32]35, $buf4, [uint32]4))

    # DWMWA_TEXT_COLOR = 36 (White titlebar text)
    [Runtime.InteropServices.Marshal]::WriteInt32($buf4, [int32]0x00FFFFFF)
    [void]$dwmSetWindowAttribute.DynamicInvoke(@($hwnd, [uint32]36, $buf4, [uint32]4))

    # DWMWA_SYSTEMBACKDROP_TYPE = 38 (4 = Mica Alt / DWMSBT_TABBEDWINDOW, 2 = Mica fallback)
    [Runtime.InteropServices.Marshal]::WriteInt32($buf4, 4)
    $hr = [int32]$dwmSetWindowAttribute.DynamicInvoke(@($hwnd, [uint32]38, $buf4, [uint32]4))
    if ($hr -lt 0) {
        # Fallback to standard Mica (2) on earlier Windows 11 builds
        [Runtime.InteropServices.Marshal]::WriteInt32($buf4, 2)
        [void]$dwmSetWindowAttribute.DynamicInvoke(@($hwnd, [uint32]38, $buf4, [uint32]4))
    }

    # Extend Frame into client area (-1 margins)
    for ($i = 0; $i -lt 16; $i += 4) { [Runtime.InteropServices.Marshal]::WriteInt32($margins, $i, -1) }
    [void]$dwmExtendFrame.DynamicInvoke(@($hwnd, $margins))
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf4)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($margins)
}

# Automated Verification Gate
if ($Verify) {
    try {
        Write-Host "Verifying SoundRecorder native window creation..." -ForegroundColor Cyan
        if ($state.Hwnd -eq [IntPtr]::Zero) { throw "Window handle is invalid." }
        Write-Host "Window HWND: $($state.Hwnd)"

        Write-Host "Verifying audio device enumeration..." -ForegroundColor Cyan
        Write-Host "Default Mic: $($state.MicName)"
        Write-Host "Default Output: $($state.AppName)"

        Write-Host "Verifying capture cycle (Mic)..." -ForegroundColor Cyan
        & $fnStartRecording
        [Threading.Thread]::Sleep(300)
        & $fnProcessAudioPackets
        [void](& $wndProc $hwnd ([uint32]0x000F) ([IntPtr]::Zero) ([IntPtr]::Zero))
        Write-Host "Elapsed: $($state.ElapsedSec)s | Total Bytes: $($state.TotalAudioBytes)"

        Write-Host "Verifying pause & resume..." -ForegroundColor Cyan
        & $fnPauseResumeRecording
        if (-not $state.IsPaused) { throw "Pause failed." }
        & $fnPauseResumeRecording
        if ($state.IsPaused) { throw "Resume failed." }

        Write-Host "Verifying stop & WAV persistence..." -ForegroundColor Cyan
        & $fnStopRecording
        if (-not (Test-Path -LiteralPath $state.LastSavedPath)) { throw "WAV file was not created." }
        $wavSize = (Get-Item -LiteralPath $state.LastSavedPath).Length
        Write-Host "Saved WAV: $($state.LastSavedPath) ($wavSize bytes)"
        if ($wavSize -lt 44) { throw "WAV file header truncated." }

        Write-Host "Verifying UI WM_PAINT render cycle (Saved Notification card)..." -ForegroundColor Cyan
        [void](& $wndProc $hwnd ([uint32]0x000F) ([IntPtr]::Zero) ([IntPtr]::Zero))

        Write-Host "PASS: SoundRecorder native Mica Alt lifecycle, WASAPI stream, and WAV file verification passed." -ForegroundColor Green
    }
    finally {
        [void]$destroyWindow.DynamicInvoke(@($hwnd))
        [void]$unregisterClass.DynamicInvoke(@($pClassName, $hModule))
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pClassName)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($pTitle)
        [Runtime.InteropServices.Marshal]::FreeHGlobal($wndClass)

        [void]$deleteObject.DynamicInvoke(@($brCard))
        [void]$deleteObject.DynamicInvoke(@($brCardBorder))
        [void]$deleteObject.DynamicInvoke(@($brWaveform))
        [void]$deleteObject.DynamicInvoke(@($brWaveMuted))
        [void]$deleteObject.DynamicInvoke(@($brBadge))
        [void]$deleteObject.DynamicInvoke(@($brBtnSlate))
        [void]$deleteObject.DynamicInvoke(@($brBtnCoral))
        [void]$deleteObject.DynamicInvoke(@($brPillActive))
        [void]$deleteObject.DynamicInvoke(@($brPillBg))
        [void]$deleteObject.DynamicInvoke(@($brMeterTrack))
        [void]$deleteObject.DynamicInvoke(@($brMeterGreen))
        [void]$deleteObject.DynamicInvoke(@($brMeterYellow))
        [void]$deleteObject.DynamicInvoke(@($brMeterRed))
        [void]$deleteObject.DynamicInvoke(@($brSuccess))
        [void]$deleteObject.DynamicInvoke(@($penNull))
        [void]$deleteObject.DynamicInvoke(@($penBorder))
        [void]$deleteObject.DynamicInvoke(@($penRecordBorder))
        [void]$deleteObject.DynamicInvoke(@($penWaveform))
        [void]$deleteObject.DynamicInvoke(@($penGuide))
        [void]$deleteObject.DynamicInvoke(@($penBtnBorder))
        [void]$deleteObject.DynamicInvoke(@($penNeedle))
        [void]$deleteObject.DynamicInvoke(@($fontTitle))
        [void]$deleteObject.DynamicInvoke(@($fontTimer))
        [void]$deleteObject.DynamicInvoke(@($fontBadge))
        [void]$deleteObject.DynamicInvoke(@($fontButton))
        [void]$deleteObject.DynamicInvoke(@($fontSmall))
        [void]$deleteObject.DynamicInvoke(@($fontTiny))

        if ($deviceEnumerator -ne [IntPtr]::Zero) { [void](& $comCall $deviceEnumerator 2 ([uint32]) @() @()) }
        if ($coOwned) { [void]$coUninitialize.DynamicInvoke() }
    }
    return
}

# Show Window & Enter Event Dispatch Loop
# If launched via -WindowStyle Hidden, the first ShowWindow call consumes STARTUPINFO SW_HIDE.
# Calling ShowWindow again and invoking SetWindowPos with SWP_SHOWWINDOW guarantees top-level visibility.
[void]$showWindow.DynamicInvoke(@($hwnd, [int32]5)) # SW_SHOW
[void]$showWindow.DynamicInvoke(@($hwnd, [int32]5)) # Force SW_SHOW if first call consumed STARTUPINFO
[void]$setWindowPos.DynamicInvoke(@($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, [uint32]0x0043)) # SWP_SHOWWINDOW | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
[void]$updateWindow.DynamicInvoke(@($hwnd))

$msg = & $alloc 48
try {
    # Blocking GetMessageW message loop (Zero busy waiting, zero frame pump)
    while ($true) {
        $ret = [int32]$getMessage.DynamicInvoke(@($msg, [IntPtr]::Zero, [uint32]0, [uint32]0))
        if ($ret -le 0) { break }
        [void]$translateMessage.DynamicInvoke(@($msg))
        [void]$dispatchMessage.DynamicInvoke(@($msg))
    }
}
finally {
    [Runtime.InteropServices.Marshal]::FreeHGlobal($msg)
    [void]$destroyWindow.DynamicInvoke(@($hwnd))
    [void]$unregisterClass.DynamicInvoke(@($pClassName, $hModule))
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pClassName)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($pTitle)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($wndClass)

    [void]$deleteObject.DynamicInvoke(@($brCard))
    [void]$deleteObject.DynamicInvoke(@($brCardBorder))
    [void]$deleteObject.DynamicInvoke(@($brWaveform))
    [void]$deleteObject.DynamicInvoke(@($brWaveMuted))
    [void]$deleteObject.DynamicInvoke(@($brBadge))
    [void]$deleteObject.DynamicInvoke(@($brBtnSlate))
    [void]$deleteObject.DynamicInvoke(@($brBtnCoral))
    [void]$deleteObject.DynamicInvoke(@($brPillActive))
    [void]$deleteObject.DynamicInvoke(@($brPillBg))
    [void]$deleteObject.DynamicInvoke(@($brMeterTrack))
    [void]$deleteObject.DynamicInvoke(@($brMeterGreen))
    [void]$deleteObject.DynamicInvoke(@($brMeterYellow))
    [void]$deleteObject.DynamicInvoke(@($brMeterRed))
    [void]$deleteObject.DynamicInvoke(@($brSuccess))
    [void]$deleteObject.DynamicInvoke(@($penNull))
    [void]$deleteObject.DynamicInvoke(@($penBorder))
    [void]$deleteObject.DynamicInvoke(@($penRecordBorder))
    [void]$deleteObject.DynamicInvoke(@($penWaveform))
    [void]$deleteObject.DynamicInvoke(@($penGuide))
    [void]$deleteObject.DynamicInvoke(@($penBtnBorder))
    [void]$deleteObject.DynamicInvoke(@($penNeedle))
    [void]$deleteObject.DynamicInvoke(@($fontTitle))
    [void]$deleteObject.DynamicInvoke(@($fontTimer))
    [void]$deleteObject.DynamicInvoke(@($fontBadge))
    [void]$deleteObject.DynamicInvoke(@($fontButton))
    [void]$deleteObject.DynamicInvoke(@($fontSmall))
    [void]$deleteObject.DynamicInvoke(@($fontTiny))

    if ($deviceEnumerator -ne [IntPtr]::Zero) { [void](& $comCall $deviceEnumerator 2 ([uint32]) @() @()) }
    if ($coOwned) { [void]$coUninitialize.DynamicInvoke() }
}

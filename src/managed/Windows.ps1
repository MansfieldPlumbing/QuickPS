if ($MyInvocation.InvocationName -eq '.') { throw 'Invoke this source with &, not dot-sourcing.' }

# PowerShell-authored managed ABI. Windows x64, SDK 10.0.26100.0:
# combaseapi.h, synchapi.h, winuser.h, audioclient.h, mmdeviceapi.h.
# HRESULT/BOOL are signed Int32; DWORD/ULONG UInt32; pointers IntPtr;
# WAVEFORMATEX is 18 bytes, cbSize at 16; COM slots include IUnknown.
# Compile this file with tools/Build-Managed.ps1; native import stubs cannot
# execute as interpreted PowerShell. No C# or runtime source compilation.
class QuickPSWindows {
    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoInitializeEx')]
    static [int] CoInitialize([IntPtr]$reserved,[uint]$flags) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoUninitialize')]
    static [void] CoUninitialize() { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoCreateInstance')]
    static [int] CoCreate([IntPtr]$clsid,[IntPtr]$outer,[uint]$context,[IntPtr]$iid,[IntPtr]$result) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoTaskMemFree')]
    static [void] CoTaskFree([IntPtr]$memory) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='CreateEventW')]
    static [IntPtr] CreateEvent([IntPtr]$security,[int]$manual,[int]$initial,[IntPtr]$name) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='SetEvent')]
    static [int] SetEvent([IntPtr]$handle) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='CloseHandle')]
    static [int] CloseHandle([IntPtr]$handle) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='WaitForMultipleObjects')]
    static [uint] WaitMany([uint]$count,[IntPtr]$handles,[int]$all,[uint]$timeout) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='WaitForSingleObject')]
    static [uint] WaitOne([IntPtr]$handle,[uint]$timeout) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('user32.dll', EntryPoint='PostMessageW')]
    static [int] PostMessage([IntPtr]$window,[uint]$message,[IntPtr]$wparam,[IntPtr]$lparam) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('user32.dll', EntryPoint='SetWindowTextW', StringMarshalling=[System.Runtime.InteropServices.StringMarshalling]::Utf16)]
    static [int] SetText([IntPtr]$window,[string]$text) { throw [NotSupportedException]::new('Build managed source first.') }
    static [IntPtr] GuidMemory([string]$littleEndianHex) {
        [byte[]]$bytes=[Convert]::FromHexString($littleEndianHex)
        if($bytes.Length -ne 16){throw [ArgumentException]::new('GUID memory must contain 16 bytes.')}
        [IntPtr]$memory=[Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        [Runtime.InteropServices.Marshal]::Copy($bytes,0,$memory,16)
        return $memory
    }
    static [void] Check([int]$hr) {
        if($hr -lt 0) { [Runtime.InteropServices.Marshal]::ThrowExceptionForHR($hr) }
    }
}

# Owns one WASAPI stream and its output. COM is initialized, accessed and
# released only by Run's thread. Stop and pause are native manual-reset events.
# Every successful packet acquisition is paired with ReleaseBuffer in finally.
# No callback enters a PowerShell runspace. Completion posts a semantic command.
class QuickPSCapture {
    [Type[]]$Signatures
    [string]$OutputPath
    [bool]$Loopback
    [bool]$Normalize
    [IntPtr]$StopEvent
    [IntPtr]$PauseEvent
    [IntPtr]$DoneEvent
    [IntPtr]$StartedEvent
    [IntPtr]$NotifyWindow
    [IntPtr]$NotifyControl
    [IntPtr]$MeterWindow
    [int]$NotifyId
    [string]$Failure=''
    [string]$TracePath=''
    [long]$BytesWritten
    [int]$BlockAlign
    [int]$SampleRate
    [int]$Channels
    [int]$Bits
    [int]$FormatTag
    [bool]$Normalized
    [bool]$Synthetic
    [byte[]]$SyntheticBytes
    [object]$Sync
    [int]$Status
    [Threading.Thread]$Thread

    QuickPSCapture() {
        $this.Sync=[object]::new()
        $this.StopEvent=[QuickPSWindows]::CreateEvent([IntPtr]::Zero,1,0,[IntPtr]::Zero)
        $this.PauseEvent=[QuickPSWindows]::CreateEvent([IntPtr]::Zero,1,0,[IntPtr]::Zero)
        $this.DoneEvent=[QuickPSWindows]::CreateEvent([IntPtr]::Zero,1,0,[IntPtr]::Zero)
        $this.StartedEvent=[QuickPSWindows]::CreateEvent([IntPtr]::Zero,1,0,[IntPtr]::Zero)
        if($this.StopEvent -eq [IntPtr]::Zero -or $this.PauseEvent -eq [IntPtr]::Zero -or $this.DoneEvent -eq [IntPtr]::Zero -or $this.StartedEvent -eq [IntPtr]::Zero) {
            $this.Dispose()
            throw [InvalidOperationException]::new('Cannot create capture events.')
        }
    }
    [void] SetStatus([int]$value) {
        [Threading.Monitor]::Enter($this.Sync)
        try { $this.Status=$value } finally { [Threading.Monitor]::Exit($this.Sync) }
    }
    [int] GetStatus() {
        [int]$value=0
        [Threading.Monitor]::Enter($this.Sync)
        try { $value=$this.Status } finally { [Threading.Monitor]::Exit($this.Sync) }
        return $value
    }
    [void] RequestStop() {
        if([QuickPSWindows]::SetEvent($this.StopEvent) -eq 0) { throw [InvalidOperationException]::new('Cannot signal Stop.') }
    }
    [void] Pause() {
        if([QuickPSWindows]::SetEvent($this.PauseEvent) -eq 0) { throw [InvalidOperationException]::new('Cannot signal Pause.') }
    }
    # Resume uses ResetEvent supplied by an explicit native import below.
    [System.Runtime.InteropServices.LibraryImport('kernel32.dll', EntryPoint='ResetEvent')]
    static [int] ResetEvent([IntPtr]$handle) { throw [NotSupportedException]::new('Build managed source first.') }
    [void] Resume() {
        if([QuickPSCapture]::ResetEvent($this.PauseEvent) -eq 0) { throw [InvalidOperationException]::new('Cannot resume capture.') }
    }
    [int] Call([IntPtr]$instance,[int]$slot,[int]$signature,[object[]]$arguments) {
        $this.Trace('COM slot '+[Convert]::ToString($slot))
        [IntPtr]$table=[Runtime.InteropServices.Marshal]::ReadIntPtr($instance)
        [IntPtr]$address=[Runtime.InteropServices.Marshal]::ReadIntPtr($table,$slot * 8)
        [Delegate]$method=[Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($address,$this.Signatures[$signature])
        [int]$hr=[int]$method.DynamicInvoke($arguments)
        if($hr -lt 0){$this.Failure='WASAPI failed with HRESULT '+[Convert]::ToString($hr,16)}
        return $hr
    }
    [void] Trace([string]$stage) {
        if($this.TracePath -ne ''){[IO.File]::AppendAllText($this.TracePath,$stage+[Environment]::NewLine)}
    }
    [void] Release([IntPtr]$instance) {
        if($instance -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::Release($instance) }
    }
    [void] Run() {
        [IntPtr]$enumerator=[IntPtr]::Zero
        [IntPtr]$device=[IntPtr]::Zero
        [IntPtr]$client=[IntPtr]::Zero
        [IntPtr]$capture=[IntPtr]::Zero
        [IntPtr]$format=[IntPtr]::Zero
        [IntPtr]$audioEvent=[IntPtr]::Zero
        [IntPtr]$scratch=[Runtime.InteropServices.Marshal]::AllocHGlobal(128)
        [IO.FileStream]$file=$null
        [IO.BinaryWriter]$writer=$null
        [bool]$coInitialized=$false
        [bool]$started=$false
        [long]$dataSizePosition=0
        [long]$dataStart=0
        try {
            $this.SetStatus(1)
            [byte[]]$formatBytes=[byte[]]::new(18)
            if($this.Synthetic) {
                $this.BlockAlign=2; $this.SampleRate=48000; $this.Channels=1; $this.Bits=16; $this.FormatTag=1
                [Buffer]::BlockCopy([BitConverter]::GetBytes([short]1),0,$formatBytes,0,2)
                [Buffer]::BlockCopy([BitConverter]::GetBytes([short]1),0,$formatBytes,2,2)
                [Buffer]::BlockCopy([BitConverter]::GetBytes(48000),0,$formatBytes,4,4)
                [Buffer]::BlockCopy([BitConverter]::GetBytes(96000),0,$formatBytes,8,4)
                [Buffer]::BlockCopy([BitConverter]::GetBytes([short]2),0,$formatBytes,12,2)
                [Buffer]::BlockCopy([BitConverter]::GetBytes([short]16),0,$formatBytes,14,2)
            } else {
                $this.Trace('CoInitialize')
                [QuickPSWindows]::Check([QuickPSWindows]::CoInitialize([IntPtr]::Zero,[uint]0))
                $coInitialized=$true
                [IntPtr]$clsid=[QuickPSWindows]::GuidMemory('9503DEBC2FE57C468E3DC4579291692E')
                [IntPtr]$iid=[QuickPSWindows]::GuidMemory('D26456A91496354FA746DE8DB63617E6')
                try {
                    [Runtime.InteropServices.Marshal]::WriteIntPtr($scratch,[IntPtr]::Zero)
                    $this.Trace('CoCreate')
                    [QuickPSWindows]::Check([QuickPSWindows]::CoCreate($clsid,[IntPtr]::Zero,[uint]1,$iid,$scratch))
                    $enumerator=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($clsid); [Runtime.InteropServices.Marshal]::FreeHGlobal($iid) }
                [uint]$flow=1
                if($this.Loopback) { $flow=0 }
                [QuickPSWindows]::Check($this.Call($enumerator,4,0,[object[]]@($enumerator,$flow,[uint]1,$scratch)))
                $device=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                $iid=[QuickPSWindows]::GuidMemory('4CADB91CFADB324CB178C2F568A703B2')
                try {
                    [QuickPSWindows]::Check($this.Call($device,3,1,[object[]]@($device,$iid,[uint]1,[IntPtr]::Zero,$scratch)))
                    $client=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($iid) }
                [QuickPSWindows]::Check($this.Call($client,8,2,[object[]]@($client,$scratch)))
                $format=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                $this.Trace('Read mix format')
                [int]$formatLength=18 + [int][Runtime.InteropServices.Marshal]::ReadInt16($format,16)
                if($formatLength -lt 18 -or $formatLength -gt 4096) { throw [IO.InvalidDataException]::new('Unsupported format size.') }
                $formatBytes=[byte[]]::new($formatLength)
                [Runtime.InteropServices.Marshal]::Copy($format,$formatBytes,0,$formatLength)
                $this.FormatTag=[int][Runtime.InteropServices.Marshal]::ReadInt16($format,0) -band 65535
                $this.Channels=[int][Runtime.InteropServices.Marshal]::ReadInt16($format,2) -band 65535
                $this.SampleRate=[Runtime.InteropServices.Marshal]::ReadInt32($format,4)
                $this.BlockAlign=[int][Runtime.InteropServices.Marshal]::ReadInt16($format,12) -band 65535
                $this.Bits=[int][Runtime.InteropServices.Marshal]::ReadInt16($format,14) -band 65535
                if($this.BlockAlign -le 0 -or $this.SampleRate -le 0) { throw [IO.InvalidDataException]::new('Invalid audio format.') }
                [uint]$flags=262144
                if($this.Loopback) { $flags=$flags -bor [uint]131072 }
                [QuickPSWindows]::Check($this.Call($client,3,3,[object[]]@($client,[uint]0,$flags,[long]0,[long]0,$format,[IntPtr]::Zero)))
                $audioEvent=[QuickPSWindows]::CreateEvent([IntPtr]::Zero,0,0,[IntPtr]::Zero)
                if($audioEvent -eq [IntPtr]::Zero) { throw [InvalidOperationException]::new('Cannot create audio event.') }
                [QuickPSWindows]::Check($this.Call($client,13,2,[object[]]@($client,$audioEvent)))
                $iid=[QuickPSWindows]::GuidMemory('64BDADC81EE7A048A4DE185C395CD317')
                try {
                    [QuickPSWindows]::Check($this.Call($client,14,4,[object[]]@($client,$iid,$scratch)))
                    $capture=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($iid) }
            }
            $file=[IO.FileStream]::new($this.OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
            $writer=[IO.BinaryWriter]::new($file)
            $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
            $writer.Write([uint]0)
            $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
            $writer.Write([uint]$formatBytes.Length)
            $writer.Write($formatBytes)
            if(($formatBytes.Length -band 1) -ne 0) { $writer.Write([byte]0) }
            $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
            $dataSizePosition=$file.Position
            $writer.Write([uint]0)
            $dataStart=$file.Position
            if($this.Synthetic -and $this.SyntheticBytes -ne [byte[]]$null) {
                if($this.SyntheticBytes.Length -gt 16777216 -or ($this.SyntheticBytes.Length % 2) -ne 0) { throw [IO.InvalidDataException]::new('Invalid synthetic PCM extent.') }
                $writer.Write($this.SyntheticBytes)
                $this.BytesWritten=[long]$this.SyntheticBytes.Length
            }
            if(-not $this.Synthetic) {
                [QuickPSWindows]::Check($this.Call($client,10,5,[object[]]@($client)))
                $started=$true
            }
            $this.SetStatus(2)
            [QuickPSWindows]::SetEvent($this.StartedEvent)
            [Runtime.InteropServices.Marshal]::WriteIntPtr($scratch,80,$this.StopEvent)
            [Runtime.InteropServices.Marshal]::WriteIntPtr($scratch,88,$audioEvent)
            [bool]$running=$true
            while($running) {
                [uint]$wait=0
                if($this.Synthetic) { $wait=[QuickPSWindows]::WaitOne($this.StopEvent,[uint]4294967295) }
                else { $wait=[QuickPSWindows]::WaitMany([uint]2,[IntPtr]::Add($scratch,80),0,[uint]4294967295) }
                if($wait -eq [uint]0) { $running=$false }
                elseif($wait -ne [uint]1) { throw [InvalidOperationException]::new('Capture wait failed.') }
                if(-not $this.Synthetic) {
                    [int]$packets=0
                    [bool]$draining=$true
                    while($draining -and $packets -lt 256) {
                        [QuickPSWindows]::Check($this.Call($capture,5,2,[object[]]@($capture,$scratch)))
                        [int]$available=[Runtime.InteropServices.Marshal]::ReadInt32($scratch)
                        if($available -eq 0) { $draining=$false }
                        else {
                            [QuickPSWindows]::Check($this.Call($capture,3,6,[object[]]@($capture,$scratch,[IntPtr]::Add($scratch,8),[IntPtr]::Add($scratch,12),[IntPtr]::Zero,[IntPtr]::Zero)))
                            [int]$count=[Runtime.InteropServices.Marshal]::ReadInt32($scratch,8)
                            try {
                                if($count -lt 0 -or $count -gt 1048576) { throw [IO.InvalidDataException]::new('Invalid packet size.') }
                                [int]$length=$count * $this.BlockAlign
                                if($length -gt 16777216) { throw [IO.InvalidDataException]::new('Packet exceeds capacity.') }
                                [byte[]]$bytes=[byte[]]::new($length)
                                [int]$packetFlags=[Runtime.InteropServices.Marshal]::ReadInt32($scratch,12)
                                [IntPtr]$data=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                                if(($packetFlags -band 2) -eq 0 -and $length -gt 0) {
                                    if($data -eq [IntPtr]::Zero) { throw [IO.InvalidDataException]::new('Null audio data.') }
                                    [Runtime.InteropServices.Marshal]::Copy($data,$bytes,0,$length)
                                }
                                if([QuickPSWindows]::WaitOne($this.PauseEvent,[uint]0) -eq [uint]258) {
                                    if($file.Length + [long]$length -gt [long]4294967295) { throw [IO.InvalidDataException]::new('RIFF capacity reached.') }
                                    $writer.Write($bytes)
                                    $this.BytesWritten += [long]$length
                                    if($this.MeterWindow -ne [IntPtr]::Zero) {
                                        [double]$peak=[QuickPSWave]::Peak($bytes,$formatBytes)
                                        [int]$position=[int][Math]::Min(100.0,$peak * 100.0)
                                        # PBM_SETPOS has a numeric payload; asynchronous delivery
                                        # avoids a cross-thread SendMessage/Join deadlock.
                                        [QuickPSWindows]::PostMessage($this.MeterWindow,[uint]1026,[IntPtr]::new($position),[IntPtr]::Zero)
                                    }
                                }
                            } finally { [QuickPSWindows]::Check($this.Call($capture,4,7,[object[]]@($capture,[uint]$count))) }
                            $packets++
                        }
                    }
                    if($packets -ge 256) { throw [InvalidOperationException]::new('Capture queue exceeded its bound.') }
                }
            }
            if($started) {
                [QuickPSWindows]::Check($this.Call($client,11,5,[object[]]@($client)))
                $started=$false
            }
            $writer.Flush()
            $file.Position=4
            $writer.Write([uint]($file.Length - [long]8))
            $file.Position=$dataSizePosition
            $writer.Write([uint]$this.BytesWritten)
            $writer.Flush()
            $this.SetStatus(3)
            # Postprocessing is performed on this worker, never on the UI thread.
            if($this.Normalize) { $this.Normalized=[QuickPSWave]::Normalize($file,$dataStart,$this.BytesWritten,$formatBytes) }
            $this.SetStatus(4)
        } catch [Exception] {
            if($this.Failure -eq ''){$this.Failure='Capture or output finalization failed.'}
            $this.SetStatus(5)
        } finally {
            if($writer -ne [IO.BinaryWriter]$null) { $writer.Dispose() }
            elseif($file -ne [IO.FileStream]$null) { $file.Dispose() }
            if($started) { $this.Call($client,11,5,[object[]]@($client)) }
            $this.Trace('Release interfaces')
            $this.Release($capture); $this.Release($client); $this.Release($device); $this.Release($enumerator)
            if($format -ne [IntPtr]::Zero) { [QuickPSWindows]::CoTaskFree($format) }
            if($audioEvent -ne [IntPtr]::Zero) { [QuickPSWindows]::CloseHandle($audioEvent) }
            [Runtime.InteropServices.Marshal]::FreeHGlobal($scratch)
            if($coInitialized) { [QuickPSWindows]::CoUninitialize() }
            [QuickPSWindows]::SetEvent($this.DoneEvent)
            [QuickPSWindows]::SetEvent($this.StartedEvent)
            if($this.NotifyWindow -ne [IntPtr]::Zero) { [QuickPSWindows]::PostMessage($this.NotifyWindow,[uint]273,[IntPtr]::new($this.NotifyId),$this.NotifyControl) }
        }
    }
    [void] Dispose() {
        if($this.Thread -ne [Threading.Thread]$null -and $this.Thread.IsAlive) { throw [InvalidOperationException]::new('Wait for worker completion before disposal.') }
        if($this.StopEvent -ne [IntPtr]::Zero) { [QuickPSWindows]::CloseHandle($this.StopEvent); $this.StopEvent=[IntPtr]::Zero }
        if($this.PauseEvent -ne [IntPtr]::Zero) { [QuickPSWindows]::CloseHandle($this.PauseEvent); $this.PauseEvent=[IntPtr]::Zero }
        if($this.DoneEvent -ne [IntPtr]::Zero) { [QuickPSWindows]::CloseHandle($this.DoneEvent); $this.DoneEvent=[IntPtr]::Zero }
        if($this.StartedEvent -ne [IntPtr]::Zero) { [QuickPSWindows]::CloseHandle($this.StartedEvent); $this.StartedEvent=[IntPtr]::Zero }
    }
}

class QuickPSWave {
    static [int] SampleSize([byte[]]$format) {
        if($format.Length -lt 18) { return 0 }
        [int]$tag=[int][BitConverter]::ToUInt16($format,0)
        [int]$bits=[int][BitConverter]::ToUInt16($format,14)
        if($tag -eq 65534) {
            if($format.Length -lt 40) { return 0 }
            if(-not [QuickPSWave]::IsStandardSubtype($format)){return 0}
            $tag=[BitConverter]::ToInt32($format,24)
        }
        if($tag -eq 3 -and $bits -eq 32) { return 4 }
        if($tag -eq 1 -and $bits -eq 16) { return 2 }
        return 0
    }
    static [double] Peak([byte[]]$bytes,[byte[]]$format) {
        [int]$size=[QuickPSWave]::SampleSize($format)
        if($size -eq 0) { return 0.0 }
        if(($bytes.Length % $size) -ne 0) { throw [IO.InvalidDataException]::new('Incomplete audio sample.') }
        [double]$peak=0.0
        for([int]$i=0;$i -lt $bytes.Length;$i += $size) {
            [double]$value=0.0
            if($size -eq 4) { $value=[double][BitConverter]::ToSingle($bytes,$i) }
            else { $value=[double][BitConverter]::ToInt16($bytes,$i) / 32768.0 }
            if([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw [IO.InvalidDataException]::new('Nonfinite audio sample.') }
            $peak=[Math]::Max($peak,[Math]::Abs($value))
        }
        return $peak
    }
    static [bool] IsStandardSubtype([byte[]]$format) {
        if($format.Length -lt 40){return $false}
        [byte[]]$tail=[byte[]]@(0,0,16,0,128,0,0,170,0,56,155,113)
        for([int]$i=0;$i -lt 12;$i++){if($format[28+$i] -ne $tail[$i]){return $false}}
        return $true
    }
    # Supported data: PCM16 or IEEE float32, including explicit extensible subtype.
    # Two bounded-buffer passes; complete sample alignment; no format guessing.
    static [bool] Normalize([IO.FileStream]$file,[long]$start,[long]$length,[byte[]]$format) {
        if($format.Length -lt 18 -or $length -eq [long]0) { return $false }
        [int]$tag=[int][BitConverter]::ToUInt16($format,0)
        [int]$bits=[int][BitConverter]::ToUInt16($format,14)
        if($tag -eq 65534) {
            if($format.Length -lt 40) { throw [IO.InvalidDataException]::new('Truncated extensible format.') }
            if(-not [QuickPSWave]::IsStandardSubtype($format)){return $false}
            $tag=[BitConverter]::ToInt32($format,24)
        }
        [int]$size=0
        if($tag -eq 3 -and $bits -eq 32) { $size=4 }
        elseif($tag -eq 1 -and $bits -eq 16) { $size=2 }
        else { return $false }
        if($length -lt [long]0 -or $start -lt [long]0 -or $start + $length -gt $file.Length -or ($length % [long]$size) -ne [long]0) { throw [IO.InvalidDataException]::new('Invalid sample extent.') }
        [byte[]]$buffer=[byte[]]::new(16384)
        [double]$peak=0.0
        for([int]$pass=0;$pass -lt 2;$pass++) {
            $file.Position=$start
            [long]$remaining=$length
            [double]$gain=1.0
            if($pass -eq 1) { if($peak -le 0.0001) { return $false }; $gain=0.89125 / $peak }
            while($remaining -gt [long]0) {
                [long]$position=$file.Position
                [int]$count=[int][Math]::Min($remaining,[long]$buffer.Length)
                [int]$read=0
                while($read -lt $count) {
                    [int]$n=$file.Read($buffer,$read,$count - $read)
                    if($n -eq 0) { throw [IO.EndOfStreamException]::new('Truncated audio data.') }
                    $read += $n
                }
                for([int]$i=0;$i -lt $count;$i += $size) {
                    [double]$sample=0.0
                    if($size -eq 4) { $sample=[double][BitConverter]::ToSingle($buffer,$i) }
                    else { $sample=[double][BitConverter]::ToInt16($buffer,$i) / 32768.0 }
                    if([double]::IsNaN($sample) -or [double]::IsInfinity($sample)) { throw [IO.InvalidDataException]::new('Nonfinite sample.') }
                    if($pass -eq 0) { $peak=[Math]::Max($peak,[Math]::Abs($sample)) }
                    else {
                        $sample=[Math]::Max(-0.98,[Math]::Min(0.98,$sample * $gain))
                        [byte[]]$encoded=[byte[]]::new(0)
                        if($size -eq 4) { $encoded=[BitConverter]::GetBytes([single]$sample) }
                        else { $encoded=[BitConverter]::GetBytes([short]($sample * 32768.0)) }
                        [Buffer]::BlockCopy($encoded,0,$buffer,$i,$size)
                    }
                }
                if($pass -eq 1) { $file.Position=$position; $file.Write($buffer,0,$count) }
                $remaining -= [long]$count
            }
        }
        $file.Flush()
        return $true
    }
}

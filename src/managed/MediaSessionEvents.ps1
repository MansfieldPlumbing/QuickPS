if ($MyInvocation.InvocationName -eq '.') { throw 'Invoke this source with &, not dot-sourcing.' }

# PowerShell-authored managed ABI. Windows x64, SDK 10.0.26100.0:
# mfobjects.h (IMFMediaEventGenerator, IMFMediaEvent, IMFAttributes), mfidl.h,
# combaseapi.h, winuser.h. COM slots include IUnknown: GetEvent 3;
# IMFAttributes::GetUINT32 7; IMFMediaEvent::GetType 33, GetStatus 35.
# Compile this file with tools/Build-Managed.ps1; native import stubs cannot
# execute as interpreted PowerShell. No C# or runtime source compilation.

# Waits on one media event generator (a media session) on its own thread and
# posts every event to a window, so the window's thread blocks only on its
# message queue. No callback enters a PowerShell runspace.
#   Message:     wParam = MediaEventType, lParam = event status HRESULT.
#   Message + 1: wParam = MF_EVENT_TOPOLOGY_STATUS, lParam = status, after
#                every MESessionTopologyStatus (111) that carries it.
#   Message + 2: lParam = GetEvent failure HRESULT; the worker has stopped.
# The worker stops after MESessionClosed (106) or when GetEvent fails;
# MF_E_SHUTDOWN after the owner's Shutdown ends it without a message.
class QuickPSMediaSessionEvents {
    [Type[]]$Signatures
    [IntPtr]$Generator
    [IntPtr]$NotifyWindow
    [uint]$Message
    [int]$Failure
    [Threading.Thread]$Thread

    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoInitializeEx')]
    static [int] CoInitialize([IntPtr]$reserved,[uint]$flags) { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('ole32.dll', EntryPoint='CoUninitialize')]
    static [void] CoUninitialize() { throw [NotSupportedException]::new('Build managed source first.') }
    [System.Runtime.InteropServices.LibraryImport('user32.dll', EntryPoint='PostMessageW')]
    static [int] PostMessage([IntPtr]$window,[uint]$message,[IntPtr]$wparam,[IntPtr]$lparam) { throw [NotSupportedException]::new('Build managed source first.') }

    static [IntPtr] GuidMemory([string]$littleEndianHex) {
        [byte[]]$bytes=[Convert]::FromHexString($littleEndianHex)
        if($bytes.Length -ne 16){throw [ArgumentException]::new('GUID memory must contain 16 bytes.')}
        [IntPtr]$memory=[Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        [Runtime.InteropServices.Marshal]::Copy($bytes,0,$memory,16)
        return $memory
    }
    [int] Call([IntPtr]$instance,[int]$slot,[int]$signature,[object[]]$arguments) {
        [IntPtr]$table=[Runtime.InteropServices.Marshal]::ReadIntPtr($instance)
        [IntPtr]$address=[Runtime.InteropServices.Marshal]::ReadIntPtr($table,$slot * 8)
        [Delegate]$method=[Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($address,$this.Signatures[$signature])
        # [Convert]::ToInt32 unboxes the returned Int32. A cast of the object
        # result compiles to conv.i4 of the reference at the pinned compiler.
        return [Convert]::ToInt32($method.DynamicInvoke($arguments))
    }
    [void] Run() {
        [int]$coInitialized=[QuickPSMediaSessionEvents]::CoInitialize([IntPtr]::Zero,[uint]0)
        [IntPtr]$scratch=[Runtime.InteropServices.Marshal]::AllocHGlobal(16)
        # MF_EVENT_TOPOLOGY_STATUS {30C5018D-9A53-454B-AD9E-6D5F8FA7C43B}.
        [IntPtr]$topologyStatus=[QuickPSMediaSessionEvents]::GuidMemory('8D01C530539A4B45AD9E6D5F8FA7C43B')
        try {
            [bool]$running=$true
            while($running) {
                # Signature 0: GetEvent(this, flags, IMFMediaEvent**); flags 0 blocks.
                [int]$hr=$this.Call($this.Generator,3,0,[object[]]@($this.Generator,[uint]0,$scratch))
                if($hr -lt 0) {
                    $running=$false
                    if($hr -ne -1072873851) {
                        $this.Failure=$hr
                        [QuickPSMediaSessionEvents]::PostMessage($this.NotifyWindow,$this.Message + [uint]2,[IntPtr]::Zero,[IntPtr]::new($hr))
                    }
                } else {
                    [IntPtr]$event=[Runtime.InteropServices.Marshal]::ReadIntPtr($scratch)
                    try {
                        [int]$type=0
                        [int]$status=0
                        if($this.Call($event,33,1,[object[]]@($event,$scratch)) -ge 0) { $type=[Runtime.InteropServices.Marshal]::ReadInt32($scratch) }
                        if($this.Call($event,35,1,[object[]]@($event,$scratch)) -ge 0) { $status=[Runtime.InteropServices.Marshal]::ReadInt32($scratch) }
                        [QuickPSMediaSessionEvents]::PostMessage($this.NotifyWindow,$this.Message,[IntPtr]::new($type),[IntPtr]::new($status))
                        if($type -eq 111) {
                            if($this.Call($event,7,2,[object[]]@($event,$topologyStatus,$scratch)) -ge 0) {
                                [QuickPSMediaSessionEvents]::PostMessage($this.NotifyWindow,$this.Message + [uint]1,[IntPtr]::new([Runtime.InteropServices.Marshal]::ReadInt32($scratch)),[IntPtr]::new($status))
                            }
                        }
                        if($type -eq 106) { $running=$false }
                    } finally { [Runtime.InteropServices.Marshal]::Release($event) }
                }
            }
        } finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($topologyStatus)
            [Runtime.InteropServices.Marshal]::FreeHGlobal($scratch)
            if($coInitialized -ge 0) { [QuickPSMediaSessionEvents]::CoUninitialize() }
        }
    }
}

# Media capabilities: current status and next proof

QuickPS provides reusable PowerShell-authored media mechanisms. Applications own
recording policy, source selection and presentation. Capability source can lower
with an appliance or produce a reusable assembly; no permanent media framework
DLL is an architectural requirement. QuickPS consumes PSLowering rather than
implementing compiler extensions here.

## Current sources

| Source | Mechanism and limit |
| --- | --- |
| `src/Wasapi.Windows.ps1` | Windows audio endpoint/COM bindings |
| `src/Capture.Windows.ps1`, `src/managed/AudioCapture.ps1` | Capture facade and typed worker; current compiled COM dispatch uses delegates/DynamicInvoke |
| `src/MediaSession.Windows.ps1`, `src/MediaSessionEvents.Windows.ps1`, `src/managed/MediaSessionEvents.ps1` | Windows media session bindings and typed event worker |
| `src/MediaFoundation.Windows.ps1`, `src/CaptureDevice.Windows.ps1` | Overlapping device discovery pending consolidation |
| `src/WindowCapture.Windows.ps1` | Window enumeration and explicit window-to-image capture |
| `gallery/SoundRecorder.ps1` | Historical portrait application reference; window proof does not verify recording |

Native APIs, formats, ownership and failure semantics remain defined by source
ABI contracts and affected tests. Compiled workers do not establish that the
whole recorder is lowered. Hardware tests need explicit execution evidence.

## Next proof: SoundRecorder

Preserve Mic, Apps and Both capture, waveform, elapsed time, pause/resume, stop
and WAV output. After the tiny static-runtime proof, lower recorder runtime
behavior and selected capabilities together. Use compiled callbacks and native
event waits; do not deliver audio through PowerShell polling or interpreted
callbacks on arbitrary native threads. Keep buffers bounded, preserve COM/thread
affinity, release each acquired packet and verify cancellation/partial failures.

Its target is CoreLib-only managed code executing through CoreCLR and RyuJIT
supplied in the same EXE, with no SMA, adjacent runtime DLLs or extraction.
The Pwsh Android store/probe is a concrete memory-loading reference; Android APK
size is not Windows PE sizing evidence. Compiler gaps and gates are in
[PSLowering requirements](PSLOWERING-REQUIREMENTS.md); packaging is in
[the work order](WORKORDER.md).

## Planned media extensions

Sources supply timestamped samples/surfaces; routes connect selected inputs;
mixers compose them; outputs preview, record, encode or expose an endpoint.
These are vocabulary for possible future capabilities, not built routing support.
Before implementation specify format negotiation, timebase, ownership, start/stop,
cancellation, bounded buffering, overload, disconnection and errors. GPU sharing
also needs adapter identity, rights, synchronization and retirement.

Begin with a synthetic source/preview proof, then independently verify mixing
and required output/device adapters. Network transport, virtual-camera activation
and scale are separate contracts. System registration needs an approved recoverable
operation. No 200-camera capacity, cross-process transport or replacement product
is established. Consumer repositories remain intact and isolated.

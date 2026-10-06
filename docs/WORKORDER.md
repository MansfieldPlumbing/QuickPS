# QuickPS work order

## Purpose and boundary

Make native-platform appliances authored in PowerShell practical. Reusable source
implements presentation, input, geometry, graphics, audio and native services;
consumers own application semantics and presentation. Source reuse does not
require a permanent DLL boundary or a second framework object model. Selected
capabilities and whole-appliance behavior may lower together.

QuickPS is downstream of PSLowering. PSLowering owns typed-source admission,
semantic preservation and IL emission. QuickPS owns native capability contracts,
consumer composition, artifact generation and appliance verification. Do not
fork or hand-patch a cached compiler to conceal missing upstream support.
Builds use PowerShell 7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128.

Windows and Android backends implement their own documented native contracts.
Share state machines, geometry and interaction meaning where portable; keep ABI,
resource lifetime, threading and platform lifecycle explicit. No framework-wide
virtual control hierarchy is required to conceal platform differences.

## Built today

- Independently invoked Windows binders for windows, drawing/text, composition,
  D3D11/D3D12, DXGI, WIC, WASAPI, media discovery and capture.
- Pure camera and geometry sources, with existing deterministic and native proofs.
- Typed audio capture and media event workers built as derived managed DLLs.
  Their COM paths still use delegates and DynamicInvoke.
- Source-staged gallery proofs and generated standalone Backdrop distribution.
- Restored portrait SoundRecorder as the presentation/interaction reference.
  Its window verification does not test live audio. PowerShell paint callbacks
  and timer-driven capture remain debt; it is not the compiled appliance.

## Correction priority

[The correction plan](CORRECTION-PLAN.md) defines the target source layout and
compilation boundaries. Correct the contract, preserve recorder/calculator
behavior, then implement source-set compilation and the tiny runtime proof.
Naming consolidation happens within those changes, not ahead of them. The
existing cleanup list below is deferred accounting, not a prerequisite. Do not
split modules or move folders ahead of an appliance need.

## Ordered next work

1. Consolidate the existing PowerShell variants into one canonical Calculator.ps1.
   Inventory dimensions, display/equation state, key geometry including zero span,
   operator/repeat behavior, hover/pressed/neighbor behavior, keyboard input,
   calculations and rendering. Preserve original variants and hash receipts
   outside the repo until the canonical implementation proves behavior parity.
2. Extract only missing primitives Calculator requires. Reuse existing mechanisms;
   verify names, ABI, ownership and failure behavior against Microsoft contracts.
   Correct polling on this path; record other pollers as debt and prohibit new ones.
3. Make one build accept an explicit application/source set and select SourceBundle,
   Assembly or WindowsExecutable. Files do not dictate assembly boundaries.
4. Alongside source admission, establish the tiny static CoreCLR/RyuJIT PE floor:
   lower a static Main returning 42, prove memory-resolved IL-only CoreLib and
   application startup, then measure final bytes and retained native contributors.
   Follow the correction plan's native-link boundary; do not build another host
   model or a native compression loader before measurements justify it.
5. Produce Calculator.standalone.ps1 from the same selected authoritative sources.
   Distinguish the in-memory target from today's file-oriented compiler adapter.
6. Produce Calculator.dll with behavior parity and explicit managed dependencies.
7. Produce Calculator.exe meeting the acceptance gate below and preserving the
   canonical calculator's actual behavior. Measure size, startup and idle work.
8. Apply the demonstrated build to SoundRecorder. Preserve its portrait design
   and source choices; replace capture polling and UI-handle coupling with native
   readiness and data/status delivery. Prove audio, interruption and cleanup.

Naming/layout cleanup is subordinate to these milestones. The original window
merge, enumeration consolidation, AudioCapture/AppHost names, gallery wrapper
consolidation and duplicated dependency rule remain accounting, not step one.
Android verification and planned media work follow their own explicit gates.
Use existing checks; do not create a test framework. Run tests/Run-Tests.ps1 -Native
before each requested commit; report hardware checks that do not execute as not run.

## Calculator executable acceptance

The first complete appliance is one Windows x64 PE below 10,000,000 bytes, a
stricter gate than 10 MiB. PowerShell authors the application/capability source
and constructs the artifact under the documented native-link boundary. PSLowering
emits appliance IL; static CoreCLR and the EXE's own static RyuJIT execute it.
Managed images are IL-only, with CoreLib as this appliance's managed library target.
No SMA, pwsh, installed .NET, adjacent runtime/QuickPS DLLs, extraction, apphost,
bundler, hostfxr/hostpolicy deployment, ReadyToRun or NativeAOT. Actual calculator
state, geometry, rendering and input/calculation behavior must be preserved.
Windows system APIs remain OS dependencies. These are pending acceptance gates,
not properties already demonstrated by an existing artifact.

## SoundRecorder executable acceptance

One Windows x64 PE smaller than 10 MB (10,000,000 bytes), emitted through the
PowerShell build, contains static CoreCLR and RyuJIT plus IL-only managed images.
Its own RyuJIT compiles appliance IL during execution. No installed PowerShell or
.NET, SMA, dotnet.exe, external runtime/QuickPS DLL, bundler, hostfxr/hostpolicy
deployment, extraction, ReadyToRun or NativeAOT. Windows system APIs remain native
OS dependencies. CoreLib is the target's only managed library dependency; it is
not the runtime engine. Other appliances can declare broader managed needs.

The build constructs derived images and compressed managed payloads in memory,
then writes the final PE and provenance receipts. Acquisition remains pinned and
hash-verified on disk. Native runtime code initially occupies ordinary PE sections;
compressed managed images expand into bounded memory held for their full runtime
lifetime. Windows bootstrap/probe compatibility and this size are not yet proven.

SoundRecorder must preserve portrait presentation, waveform, elapsed time, Mic,
Apps and Both, pause/resume, stop and WAV output. Compiled callback/state methods
replace interpreted handlers; documented native events replace capture polling.
The current Process-based playback/folder launch may use a documented Windows
shell API to avoid adding System.Diagnostics.Process to the managed payload.
No closure implementation is required by this design.

Pinned runtime source at `3551975be08744f0418857c5bed8ab1545c5dd47` identifies
[static JIT objects](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/jit/static/CMakeLists.txt),
[static CoreCLR link inputs](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/dlls/mscoree/coreclr/CMakeLists.txt#L138)
and [static JIT initialization](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/vm/codeman.cpp#L1911).
The installed pinned RC1 CoreLib, CoreCLR and RyuJIT identify this VMR revision.
Its static link configuration and Windows bootstrap remain execution gates, not
completed capabilities.

## Size investigation

The owner's working Android APK was inspected read-only: 17,736,650 bytes,
with 48,453,670 expanded entry bytes. This is measured Android sizing evidence,
not a measurement of the Windows artifact. Compare native/managed payload bytes,
compression, target architecture and runtime configuration independently.

Read-only Windows measurements:

| Artifact | Bytes | Evidence scope |
| --- | ---: | --- |
| CoreCLR dynamic library | 4,889,936 | Pinned PowerShell runtime distribution |
| RyuJIT dynamic library | 2,414,376 | Pinned PowerShell runtime distribution |
| CoreLib | 18,224,936 | Pinned distribution; PE has a managed native header |
| Existing audio worker IL | 13,312 | Current generated worker, not whole appliance |
| Installed .NET 11 preview.7 static single-file host | 10,570,240 | Different-version baseline, not an RC1 appliance proof |

The inspected Android APK contains:

| Entry | Expanded bytes | ZIP-compressed bytes |
| --- | ---: | ---: |
| Managed assembly store | 39,084,656 | 13,504,495 |
| CoreCLR | 4,844,192 | 2,156,909 |
| RyuJIT | 2,817,680 | 1,316,095 |

Read-only parsing of the ELF payload symbol and assembly-store descriptors found
98 managed images. SMA is 14,184,248 bytes; CoreLib is 5,755,392 bytes. A separate
in-memory DEFLATE measurement of that CoreLib image yields 1,835,648 bytes.
That measurement uses DEFLATE, not the proposed Windows LZMS/XPRESS algorithms;
their sizes still need measurement. Neither APK native-library compression nor
Android CoreLib size establishes the Windows directly mapped PE's size.

The APK is an inspected local prototype, not an immutable QuickPS release input.
It was not modified, executed, or extracted to disk. Its managed payload includes
PowerShell and command modules that a fully lowered recorder would not require.

The different-version host baseline exceeds the 10,000,000-byte budget before
appliance and CoreLib payloads. Do not infer the minimum runtime from that host:
the selected native link inputs and managed runtime surface require measurement.
No CoreCLR/RyuJIT static archives or object-size maps were found in QuickPS's build
cache or the inspected installed Windows host pack. An object-level size ledger
cannot be claimed from the dynamic libraries or host executable.

The next measurement needs a pinned static build with a native link map. Record
retained objects/symbols and bytes for JIT, GC, metadata/loader, interop, threading,
exceptions, native support and startup. Classify optional runtime features only
from build/link evidence and execution checks. CoreLib reduction must retain
runtime-required types and members as well as application-reachable members;
an application call graph alone is insufficient.

## Existing source-driven build reference

Read-only inspection of the clean Pwsh working tree at
`a6416ca19edf57fb574b1b77a3b090c6ac96f17c`, `setup.ps1`, identifies relevant
mechanisms already authored in PowerShell:

- `New-ManagedHostAssemblyBytes` emits a persisted managed image to a memory stream.
- `Invoke-SelectionStep` selects explicit managed inputs and re-emits ReadyToRun
  images as IL-only through `ConvertTo-IlOnlyImage`.
- `New-AssemblyStoreBytes` constructs the managed image store in memory.
- `New-NativeHostLibrary` emits native startup and an assembly probe returning
  pointers into the mapped store via `HOST_RUNTIME_CONTRACT`.

These are local source observations, not a build or execution receipt, and no
external checkout content is consumed as a QuickPS build input. The Android host
currently names dynamically linked CoreCLR/store libraries; the Windows static
PE requires a separately verified native link and startup implementation.

The [pinned host runtime contract](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/native/corehost/host_runtime_contract.h#L67)
defines `external_assembly_probe` separately from `bundle_probe`. This provides a
concrete embedded managed-image mechanism to investigate without the bundler.
IL-only reconstruction and removal of managed members are different operations;
the former does not establish the latter's safety or size.

## In-memory compression design

Construct the appliance IL, IL-only managed runtime images, compressed image
store and final PE in memory during the PowerShell build. Persist the final
executable and required provenance/check receipts, rather than intermediate
trees of extracted assets. Source acquisition and execution retain the baseline's
pinned-file and integrity requirements.

Keep static CoreCLR/RyuJIT native code in ordinary executable PE sections.
Compress the managed image store in a data section. A native startup routine can
use Windows' Cabinet compression API to decompress those images into bounded
process-owned memory before starting CoreCLR. The external assembly probe returns
pointers and exact lengths from that store, whose buffers remain valid while the
runtime uses them. No application or runtime file is extracted to disk.

Use the same documented algorithm at build and startup; measure LZMS and XPRESS
Huffman against the actual IL-only inputs. Validate expanded lengths, offsets and
image integrity before exposing buffers to the runtime. Decompression success
alone does not establish image integrity. This is a proposed implementation,
not a compression or startup receipt.

Final file size is retained native PE code/data plus the compressed managed store,
assets, headers and alignment. Working memory includes the expanded store and
runtime/JIT allocations. APK compressed size does not directly predict PE size,
but compressing IL-only images is a concrete mechanism for this size target.

References: [Windows compression algorithms](https://learn.microsoft.com/en-us/windows/win32/cmpapi/using-the-compression-api),
[buffer decompression contract](https://learn.microsoft.com/en-us/windows/win32/api/compressapi/nf-compressapi-decompress).

## Planned

These are unbuilt possibilities, not active implementation contracts or permission
to add features during cleanup.

- Tiles: consumer-owned layout, hit regions, state and semantic navigation;
  event-triggered content changes and finite native animation. A compiled
  appliance need not host editable runspaces. Specify accessibility, interaction
  and visual conformance against an identified source before implementation.
- IPC: bounded same-user shared buffers/resources with explicit authorization,
  versioned descriptors, bounds, handle transfer, publication ordering,
  cancellation and lifetime. Prove failures and cleanup before GPU/media sharing;
  never transfer arbitrary pointers or execute payload-provided code.
- Media routes/mixers/outputs: separately admitted capabilities only when a
  consumer requires them. See [media status](MEDIA-CAPABILITIES.md). No camera-scale,
  network-streaming or virtual-camera capacity claim is established.

## Completion discipline

Application policy remains consumer-owned; whole-appliance compilation remains
valid. PSLowering owns compiler additions. Reject unsupported runtime constructs
without interpretation fallback. Claims need pinned source or recorded checks;
comparison results need equivalent workloads. Preserve source and provenance,
back up before edits, keep generated/private artifacts untracked, and leave
security controls intact. Commit only when requested; pushing requires approval.

## Source launch health

Every maintained PS1 needs useful, safe direct-launch behavior and an adjacent CMD.
Apply this to Calculator and selected primitives within the ordered milestones.
Account for remaining launcher/default-behavior gaps explicitly; use the existing
verification runner rather than a new gallery or harness. Acquisition/build tools
default to status or actionable usage; mutations require explicit selection.

## Current construction evidence

The explicit typed source-set builder now emits Assembly and SourceBundle, with
source provenance and unsupported-construct rejection. The existing managed check
proves deterministic peer-source IL and standalone launch-time lowering. Calculator
reference logic/geometry checks passed; canonical UI/native parity and the static
CoreCLR/RyuJIT PE floor remain not run. See the correction plan's source-composition
implementation section for the file-adapter limitation and preserved behavior.

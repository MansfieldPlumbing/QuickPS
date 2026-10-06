# QuickPS

QuickPS makes PowerShell-authored native appliances practical through reusable
presentation, input, geometry, graphics, audio and platform capabilities.
PowerShell source is authoritative. QuickPS is downstream of
[PSLowering](https://github.com/MansfieldPlumbing/PSLowering), which compiles
admitted typed PowerShell to ordinary managed IL. Compiler development belongs
upstream; QuickPS supplies capability implementations and concrete appliance proofs.

Application source owns its state, interaction and presentation model. Selected
capability source can compile with it; composition does not require a second
framework object hierarchy or a permanent QuickPS runtime DLL. Reusable DLLs are
an option when sharing justifies the boundary. PowerShell authors runtime methods,
native bindings, build orchestration and artifact generation, rather than merely
calling an implementation written in another language.

## Appliance target

```text
Appliance.ps1 + selected capability sources + target backend
                         PSLowering
                             IL
              emitted PE with CoreCLR and RyuJIT
```

Calculator is the first complete appliance proof, preceded by a tiny return-42
embedded-runtime experiment. SoundRecorder follows: the portrait UI, waveform,
elapsed time, Mic/Apps/Both capture, interaction and WAV output authored in
PowerShell and lowered together. Its target is one Windows EXE smaller than
10 MB (10,000,000 bytes), carrying its own statically linked CoreCLR and RyuJIT,
IL-only CoreLib and appliance IL. **The RyuJIT supplied in that EXE compiles its
IL during execution.** No installed pwsh/.NET, SMA, adjacent runtime or QuickPS
DLLs, bundler, runtime extraction, ReadyToRun or NativeAOT. Windows system APIs
remain OS-provided. CoreLib-only describes the managed libraries, not the runtime.

The PowerShell build should construct derived images, compressed managed payloads
and the final PE in memory. Native runtime code initially remains in ordinary
executable PE sections; managed payloads are proposed for decompression into
bounded process-owned memory and resolution through an assembly probe.
This Windows executable and its size target are **not yet verified**.

The owner's Pwsh Android prototype measures 17,736,650 bytes as an APK and already
contains an IL-only managed store and native assembly probe authored through its
PowerShell build. That is a concrete reference for memory loading and compression,
including removal of ReadyToRun images. APK compression and Android runtime
configuration do not establish the Windows PE's size. See
[the work order](docs/WORKORDER.md) for measured scope and evidence.

[The construction plan](docs/CORRECTION-PLAN.md) specifies separate authoring source,
SourceBundle, Assembly and WindowsExecutable outputs. [App semantics](docs/APP-SEMANTICS.md)
defines event-driven behavior, ownership and invalidation without adding a framework.

QuickPS aims to reduce framework machinery for custom applications that own their
presentation and depend heavily on native capabilities. Size, startup, idle memory,
allocations, recording CPU, input latency and capture correctness require measured
comparisons; no general performance advantage over WinForms or WPF is established.

## What exists and what comes next

Windows x64 binders cover windowing, drawing/text, composition, D3D, imaging,
audio, media discovery and capture; pure geometry and camera math are separate.
Typed sources currently produce `QuickPS.AudioCapture.dll` and
`QuickPS.MediaSessionEvents.dll`. Many other binders remain source-staged.
The gallery SoundRecorder restores the historical 360 by 540 presentation and
source choices without a generated QuickPS DLL prerequisite. Its PowerShell
paint callbacks and timer-driven capture remain debt; its `-Verify` proves
window creation and paint invocation without starting capture, not audio correctness.

Canonicalize the existing PowerShell calculator and select its required source.
Names/layout changes follow actual mechanism needs. The executable experiment establishes the
static CoreCLR/RyuJIT runtime floor using a tiny lowered method and embedded
CoreLib before completing Calculator.exe. SoundRecorder follows the demonstrated
Calculator build; the correction plan specifies the native-link boundary. Compiler requirements and acceptance
gates are in [PSLowering requirements](docs/PSLOWERING-REQUIREMENTS.md).
Android backends require independent implementation and device verification;
portable behavior does not imply portable Windows handles or COM contracts.

## Build and run current artifacts

Use PowerShell 7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128. The build currently
pins PSLowering `26fe7a864b19e70cfd6937ab062335a05fac3232` and verifies its archive
digest. These commands build today's derived DLLs and Backdrop script; they do
not produce the target recorder EXE.

```powershell
pwsh -NoProfile -File .\tools\Acquire-PSLowering.ps1 -Acquire
pwsh -NoProfile -File .\tools\Build-Managed.ps1
pwsh -NoProfile -File .\tools\Build-Backdrop.ps1
pwsh -NoProfile -File .\tools\Package-Managed.ps1
pwsh -NoProfile -File .\gallery\SoundRecorder.ps1
```

Build output stays in ignored `build/`. Managed packages contain derived DLLs,
source/consumers and manifests. Standalone Backdrop is generated from canonical
sources and runs without adjacent source files. Gallery launchers forward
arguments and return the script exit code. See [the gallery](gallery/README.md)
for current samples and their proof boundaries.

## Verify

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1 -Native
pwsh -NoProfile -File .\tests\Run-Tests.ps1 -Native -Hardware
```

Native checks create task-owned windows and exercise Windows services. Hardware
checks explicitly enable audio devices. Build managed and standalone outputs
before native verification. Tests that did not execute are reported as not run.
Human visual acceptance, Android execution and the standalone executable require
separate evidence. Generated logs and recordings stay outside tracked files.

## Layout

| Location | Responsibility |
| --- | --- |
| `src/` | Independent capability facades and native bindings |
| `src/managed/` | Typed PowerShell implementations for derived IL |
| `gallery/` | Runnable appliance/capability references, launchers and trusted catalog |
| `tests/` | Deterministic, native and explicit hardware verification |
| `tools/` | Pinned acquisition, compilation and artifact generation |
| `docs/` | Current architecture, implementation evidence and ordered work |
| `build/` | Ignored compiler cache and derived artifacts |

Application policy belongs to consumers; this does not exclude compiling their
whole appliance with selected reusable capabilities. Unbuilt tiles and IPC are
listed briefly in the work order's planned section, not as completed contracts.

QuickPS is available under the MIT License.

Every maintained PS1 must have meaningful safe direct-launch behavior and a same-stem
CMD launcher. Primitives can demonstrate themselves and also serve consumers; the
launcher contains no product logic. This contract and the current health gaps are
in [the correction plan](docs/CORRECTION-PLAN.md). Pairing alone does not prove behavior.

Explicit typed source selection is implemented by [Build-Appliance.ps1](tools/Build-Appliance.ps1).
It emits a composed DLL or standalone PS1 that lowers at launch through the current
file-based adapter. WindowsExecutable is not implemented. See the correction plan
for demonstrated behavior and remaining Calculator/runtime gates.

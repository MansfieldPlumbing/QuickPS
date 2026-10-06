# QuickPS appliance and capability gallery

These are source-staged references for PowerShell-authored native behavior, not
proof that every sample is lowered or packaged. QuickPS is downstream of
PSLowering; the compiler admits typed runtime code while this gallery demonstrates
capability composition and appliance behavior. Application-owned presentation
does not require a second framework control hierarchy.

Open the adjacent `.cmd` or run the `.ps1` with `pwsh -NoProfile -File`.
Launchers work from unrelated working directories and forward arguments.
`Catalog.ps1` returns explicit metadata; no graphical catalog viewer exists.

| Sample | Capability | Verification |
| --- | --- | --- |
| Window | Native HWND and blocking dispatch | `Window.ps1 -Verify` |
| WindowControls | Multiple windows, native controls, theme and trusted Files descriptor | `WindowControls.ps1 -Verify` |
| Backdrop | System materials and shared title-bar icons | `Backdrop.ps1 -Verify` |
| Typography | Direct2D shapes and DirectWrite Unicode text | `Typography.ps1 -Verify` |
| SoundRecorder | Historical portrait recorder, custom waveform, elapsed time and source choices | `SoundRecorder.ps1 -Verify` checks window creation and painting without capture |
| WindowCapture | Window enumeration and explicit HWND-to-BMP capture | `WindowCapture.ps1 -Verify` captures only its own synthetic window |
| Native, Wic, DXGI, D3D12, Shader, MediaFoundation, Composition | Focused binder demonstrations | adjacent `.ps1 -Verify` |
| Scene3D | Indexed native D3D12 geometry | `Scene3D.ps1 -Verify` |
| Wasapi | Explicit audio capture demonstration | hardware required |
| Debugger | Binder inventory and syntax inspection | `Debugger.ps1 -Verify` |
| VerifyGallery | Bounded gallery and library checks | `VerifyGallery.ps1` |

Native binding requires Full Language mode and Windows x64. System backdrops
need Windows 11 build 22621 or newer. SoundRecorder runs from its PowerShell
source without a generated QuickPS DLL prerequisite.

SoundRecorder restores the historical 360 by 540 portrait presentation with
Mic/Apps/Both choices, custom waveform and elapsed time. PowerShell paint callbacks
and timer-driven capture are known implementation debt. Live audio, mixed-source
correctness and human visual acceptance are separate from its window proof.

`Window.theme.ps1` is trusted executable theme data. `apps/Files.ps1` is a
trusted directory-listing descriptor, not a complete file manager. `Read-Data.ps1`
and `Show.ps1` are helpers rather than separate applets. Native integration checks
are noninteractive but may show windows; they are not service-session proofs.

Standalone Backdrop distribution is generated with `tools/Build-Backdrop.ps1`
into ignored `build/standalone/Backdrop.ps1`. It embeds canonical source, has
no runtime download and has a drift check. Native animation primitives remain
in Composition; application-specific choreography samples are maintained outside
QuickPS.

## SoundRecorder release target

Lower the recorder and selected capability sources together into one Windows
EXE carrying its own static CoreCLR and RyuJIT, IL-only CoreLib and appliance IL.
RyuJIT inside that EXE compiles the IL at execution. Target: smaller than 10 MB,
no SMA, installed runtime, adjacent QuickPS/runtime DLLs, ReadyToRun, bundler or
extraction. This artifact has not been built or tested. Preserve the restored
portrait interaction and test actual capture before claiming appliance parity.

The existing Pwsh Android APK and in-memory assembly-store/probe provide a build
reference, not a Windows size guarantee. See [the work order](../docs/WORKORDER.md)
and [compiler requirements](../docs/PSLOWERING-REQUIREMENTS.md) for next gates.

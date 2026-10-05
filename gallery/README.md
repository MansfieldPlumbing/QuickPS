# QuickPS capability gallery

Open the adjacent `.cmd` or run the `.ps1` with `pwsh -NoProfile -File`.
Launchers work from unrelated working directories and forward arguments.
`Catalog.ps1` returns explicit metadata; no graphical catalog viewer exists.

| Sample | Capability | Verification |
| --- | --- | --- |
| Window | Native HWND and blocking dispatch | `Window.ps1 -Verify` |
| WindowControls | Multiple windows, native controls, theme and trusted Files descriptor | `WindowControls.ps1 -Verify` |
| Backdrop | System materials and shared title-bar icons | `Backdrop.ps1 -Verify` |
| Typography | Direct2D shapes and DirectWrite Unicode text | `Typography.ps1 -Verify` |
| SoundRecorder | Managed WASAPI worker, native peak meter, asynchronous Stop, WAV normalization | `SoundRecorder.ps1 -Verify` uses synthetic input |
| WindowCapture | Window enumeration and explicit HWND-to-BMP capture | `WindowCapture.ps1 -Verify` captures only its own synthetic window |
| Native, Wic, DXGI, D3D12, Shader, MediaFoundation, Composition | Focused binder demonstrations | adjacent `.ps1 -Verify` |
| Scene3D | Indexed native D3D12 geometry | `Scene3D.ps1 -Verify` |
| Wasapi | Explicit audio capture demonstration | hardware required |
| Debugger | Binder inventory and syntax inspection | `Debugger.ps1 -Verify` |
| VerifyGallery | Bounded gallery and library checks | `VerifyGallery.ps1` |

Native binding requires Full Language mode and Windows x64. System backdrops
need Windows 11 build 22621 or newer. SoundRecorder additionally needs the
PowerShell-authored managed DLL: build with `tools/Build-Managed.ps1` or pass
`-AssemblyPath` from a release. Source and release forms load the assembly by path.

SoundRecorder supports microphone or system-audio loopback capture, Pause/Resume,
Stop and optional normalization (`-NoNormalize` disables it). Capture and
normalization run in managed code on a worker thread; painting uses native
controls and an emitted native-call window procedure. It does not mix concurrent
sources or reproduce the earlier waveform interface. Close requests Stop and
waits up to five seconds for worker cleanup. Visual acceptance is separate.

`Window.theme.ps1` is trusted executable theme data. `apps/Files.ps1` is a
trusted directory-listing descriptor, not a complete file manager. `Read-Data.ps1`
and `Show.ps1` are helpers rather than separate applets. Native integration checks
are noninteractive but may show windows; they are not service-session proofs.

Standalone Backdrop distribution is generated with `tools/Build-Backdrop.ps1`
into ignored `build/standalone/Backdrop.ps1`. It embeds canonical source, has
no runtime download and has a drift check. Native animation primitives remain
in Composition; application-specific choreography samples are maintained outside
QuickPS.

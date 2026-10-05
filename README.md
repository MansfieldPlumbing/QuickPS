# QuickPS

QuickPS provides native capabilities authored in PowerShell, built into managed
assemblies and driven from PowerShell. The release direction is a pack of DLLs
with readable PowerShell consumers. Windows x64 is the current native target.

The first persisted assembly, `QuickPS.Windows.dll`, contains native COM/event
operations, an event-driven WASAPI capture worker and WAV peak/normalization
logic. Existing graphics binders remain independently invoked `.ps1` files;
their conversion into persisted assemblies is still pending. No C# compiler,
custom native bridge, WinForms, WPF or browser UI is required.

## Build and package

Use PowerShell 7 with .NET 10 or newer. Compilation uses a digest-verified
PSLowering source archive at commit `26fe7a864b19e70cfd6937ab062335a05fac3232`.
The managed assembly targets the runtime used for its build; use the same
runtime major version when loading that output.

```powershell
pwsh -NoProfile -File .\tools\Acquire-PSLowering.ps1
pwsh -NoProfile -File .\tools\Build-Managed.ps1
pwsh -NoProfile -File .\tools\Build-Backdrop.ps1
pwsh -NoProfile -File .\tools\Package-Managed.ps1
```

Build output stays under ignored `build/`. The package contains the DLL in
`lib/`, PowerShell source/consumers and a manifest. No runtime download occurs.
`build/standalone/Backdrop.ps1` is generated from the canonical facade, theme
and sample; it runs independently of adjacent files.

## Run the gallery

`gallery/` is the single sample directory. Double-click a `.cmd` launcher or
invoke its adjacent `.ps1` with PowerShell 7. Launchers use script-relative
paths, forward arguments and return the script's exit code without changing
execution policy.

```powershell
pwsh -NoProfile -File .\gallery\Window.ps1
pwsh -NoProfile -File .\gallery\Typography.ps1
pwsh -NoProfile -File .\gallery\WindowControls.ps1
pwsh -NoProfile -File .\gallery\Backdrop.ps1
pwsh -NoProfile -File .\gallery\SoundRecorder.ps1
```

The recorder uses native controls and a managed event-driven worker. Record,
Pause/Resume and Stop are semantic commands; Stop signals cancellation and
returns to dispatch while the worker finalizes and optionally normalizes WAV
data. Select microphone or system-audio loopback; simultaneous-source mixing
is not implemented. The meter is a native peak control, not the prior animated
waveform. `-Verify` uses synthetic input without activating an audio device.

`Catalog.ps1` returns the gallery inventory, `Window.theme.ps1` returns theme
data, and `apps/Files.ps1` returns a trusted example descriptor. These are
executable local PowerShell files; they are not sandboxed configuration.
There is no graphical gallery browser yet. See [gallery/README.md](gallery/README.md).

## Compose a capability

```powershell
$ui = & .\src\Win32.Windows.ps1
try {
    $window = $ui.CreateWindow('Example', 640, 480, 'Mica')
    $ui.Root = $window
    $ui.Show($window)
    $ui.Run()
} finally { $ui.Dispose() }
```

`Win32.Windows.ps1` creates windows, controls, themes and semantic dispatch;
it has no desktop application policy. `Window.Windows.ps1` is the smaller
HWND lifecycle binding. Drawing/text, D3D11/D3D12, DXGI, composition, WIC,
WASAPI, Media Foundation discovery and pure geometry/camera math remain
focused components. See the source and tests for ownership and prerequisites.

## Verify

```powershell
pwsh -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1 -Native -Hardware
```

The first invocation runs deterministic checks and labels native checks NOT
RUN. The second exercises real Windows services, creates task-owned windows
and performs explicit audio hardware checks. Build managed and standalone
outputs before native verification. Logs/results stay in ignored
`verification-results/` or an explicit `-ResultDirectory` outside the repository.
Human visual acceptance, presentation measurements and Android execution are
separate gates. [docs/CLEANUP-REVIEW.md](docs/CLEANUP-REVIEW.md) records this cleanup.

## Layout

```text
src/           independent capability binders
src/managed/   PowerShell-authored managed implementations
gallery/       runnable samples, launchers, catalog, theme and descriptors
tests/         deterministic, native and explicit hardware verification
tools/         pinned acquisition, compilation, generation and packaging
docs/          contracts and evidence
build/         ignored DLLs, compiler cache and generated distributions
```

Windows APIs need Windows implementations. Pure managed contracts can guide
future Android implementations, but no Android equivalence or ReadyToRun
performance benefit has been verified. Application choreography and studio
workflows belong in consuming repositories.

QuickPS is available under the MIT License.

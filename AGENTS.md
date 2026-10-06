# QuickPS implementation contract

## Purpose and current priority

- Purpose: a library of reusable, composable primitives (buttons, toggles,
  text, images, 3D meshes and cameras) with Windows and Android backends,
  authored in PowerShell and compiled to DLLs with PSLowering, so projects
  never rebuild them.
- Current priority: names and folder layout, then the docs. No new features
  until that is done.
- Toolchain: PowerShell 7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128.
- A native or hardware test that did not run is reported as not run, never as
  passing; the affected native tests run on this machine before each commit.
- Push the day work is done, with the owner's approval; nothing lives only in
  a local clone. Names describe the mechanism.

Follow the applicable parent security baseline. Work only in this repository.
Named external checkouts may be inspected read-only when explicitly authorized;
never build, restore, modify, or consume uncommitted content from them. Acquire
dependencies from pushed immutable revisions, verify a pinned digest, and keep
them in this repository's ignored build cache. Vendor mirrors are read only at
a pinned revision. Apply the NIST, disclosure-control, register-firewall,
context-budget and file-based-execution skills where available; report missing
mandatory instructions.

## Product and release

QuickPS provides reusable native capabilities authored in PowerShell, compiled
into managed assemblies and driven by PowerShell. The intended release is a
pack of managed DLLs with readable PowerShell consumers. Keep every implementation
in PowerShell; no C#, Roslyn, runtime source compilation, intermediate native
wrapper libraries, WinForms, WPF, or browser-hosted UI.

Typed PowerShell managed source lives in `src/managed`. Existing independent
binders in `src` remain supported while migration is verified capability by
capability. Never imply that all existing binders are already persisted DLLs.
PSLowering admits a typed subset; compilation must reject unsupported constructs
without falling back to interpreted execution. Pin the compiler and verify
source/compiled equivalence, deterministic output, native ABI and lifecycle
before admitting a release. Consider ReadyToRun only after correctness and
measured startup justify a separate build gate; it is not a portability layer.

Windows is the current native ABI target. Pure math and data contracts should
remain separable. Android counterparts need independently documented native
contracts, explicit implementation and device verification. Do not claim that
Windows handles, COM slots, DLL imports or emitted x64 layouts work on Android.

QuickPS is a capability library. Application choreography, authored performances,
studio workflows, remote-appliance policy, session management and deployment
belong in consumers. Keep reusable drawing, text, transformations, native
animation, input, audio and capture mechanisms here with focused proofs.

## Repository layout

- `src/`: independently invoked capability facades and native bindings.
- `src/managed/`: typed PowerShell implementation for persisted managed DLLs.
- `gallery/`: the single runnable sample directory, adjacent `.cmd` launchers,
  trusted `Catalog.ps1`, `Window.theme.ps1` and `apps/` descriptors.
- `tests/`: bounded deterministic and native verification; hardware requirements
  must be explicit. Never report an unsupported gate as PASS.
- `tools/`: pinned acquisition, compilation, distribution generation and packaging.
- `docs/`: implementation contracts and verification evidence.
- `build/` and `verification-results/`: ignored generated artifacts.

Catalog and theme files are complete local `.ps1` files returning data. They
are trusted executable source; parse before invocation. Syntax validation is
not a trust boundary. Catalog display must never execute samples merely to
show their source. Keep application policy out of source primitives.

## Change control and hygiene

Inspect status first; untracked files are not disposable. Inventory callers,
tests and launchers before moving a capability. Copy originals outside the
repository and verify SHA-256 equality before overwriting, moving or deleting.
Preserve unsupported work recoverably and state the missing contract. Commit
only when requested. Confirm before pushing, rewriting history or irreversible
operations. Never push as part of routine cleanup.

No personal data, credentials, device identifiers, workstation-specific paths,
captured media, build output or attribution metadata in commits. Use generated
test data. Preserve applicable upstream licenses and source provenance. Keep
output bounded and return categories/locations rather than sensitive values.

Run scripts from files with `pwsh -NoProfile -File`; load assemblies by path.
Never execute generated command strings, encoded commands, input-derived
scriptblocks, or downloaded snippets. Verify downloaded source before use.
A Defender or AMSI detection stops work; do not bypass it or alter exclusions,
logging, execution policy, application control or memory protection.

## Native and managed execution

Bind documented OS exports and COM vtable slots. Record source/specification
version, native widths, signedness, calling convention, layouts, buffer capacity,
ownership, thread affinity and failure semantics. No unsupported ABI guesses.
Validate inputs and arithmetic bounds before native access. Root delegates for
their full lifetime; distinguish borrowed, shared and owned handles.

Use WM_PAINT normally. Painting and sample-delivery hot paths execute native
or PowerShell-authored compiled/emitted managed code without entering a
PowerShell runspace. PowerShell performs setup, semantic dispatch and disposal.
No PowerShell callbacks on unmanaged paint paths or arbitrary native threads.
Synchronous enumeration callbacks must stay rooted on the invoking thread.

No PowerShell frame clocks, timer-driven redraw, sleep polling, busy waits or
per-frame interpolation. Blocking GetMessage and documented native event waits
are valid. Applets express states, invalidation and finite time-based native
animation with cancellation/replacement and completion. Frames are measurement
units only, except required internal native ABI terminology. Benchmark code
must not become the application scheduler.

Pair acquisition with cleanup, including construction failure; disposal must
be idempotent. Restore GDI selections before deleting owned objects. Do not
delete shared icons or stock objects. Class background brush ownership follows
the documented window-class contract. Test repeated lifetimes and partial
failures. Keep buffers bounded, release every acquired audio packet on its
owning thread, and preserve failure reporting.

Native binding requires Full Language mode and Windows x64. Do not claim
Constrained Language compatibility or weaken controls to make it run. A visible
window, accepted HRESULT, parse result or committed composition proves only
its own layer; visual correctness, latency, presentation rate, accessibility,
DPI and service-session compatibility need separate evidence.

For shared resources, IPC, media routing or inference transport, read
`docs/IPC-CONTRACT.md` and `docs/MEDIA-CAPABILITIES.md` first. Start with pure
descriptor validation and a bounded same-user cross-process proof. These are
target contracts, not completed transport. Do not add product orchestration or
speculative cross-platform frameworks. Do not introduce migration branding.

## Verification and completion

Invoke reusable sources with `&`, never dot-source them or install global
functions. Keep source units independent. Do not weaken `tests/Verify.ps1` to
admit dependencies or unsupported implementations.

Parse changed scripts before execution. Test the affected feature, then its
consumers in separate processes. `tests/Run-Tests.ps1` records each outcome;
`-Native` enables Windows services and `-Hardware` enables explicit audio
hardware checks. Keep private logs and media outside tracked files.

Every graphical capability needs a visible native proof and bounded
noninteractive validation. Noninteractive does not imply invisible, headless
or service-session compatible. Capture only task-owned synthetic windows in
automated screenshots. Native tests do not constitute human visual approval.

Generate standalone Backdrop distribution with `tools/Build-Backdrop.ps1`,
then check drift and native behavior. Do not maintain another embedded facade
by hand. Generated distributions and managed DLLs belong in ignored build
output and release packages.

Completion requires implementation, relevant checks, accurate failure/unsupported
reporting, updated consumers/docs and a clean reviewed commit scope. Reports
identify what changed, how to launch, test evidence and remaining concrete gaps.

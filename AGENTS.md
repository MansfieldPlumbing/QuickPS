# QuickPS implementation contract

## Purpose and current priority

- Purpose: make complete PowerShell-authored appliances practical through
  reusable, composable primitives and Windows and Android backends. PowerShell
  source is authoritative; PSLowering produces derived managed IL. Consumers
  choose source staging, reusable assemblies or whole-appliance compilation.
  QuickPS is downstream of PSLowering: compiler changes belong upstream;
  capability implementations, appliance proofs and packaging belong here.
- Current priority: consolidate the existing PowerShell calculator design, extract
  its required primitives with documented names, and build Calculator.ps1 through
  selectable source compilation toward the smallest embedded-runtime PE. Preserve
  recorder behavior. Correct polling on the active Calculator path first, record
  other pollers as debt and prohibit new polling; no unrelated features. Follow
  docs/CORRECTION-PLAN.md and docs/APP-SEMANTICS.md.
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

QuickPS provides reusable native capabilities authored in PowerShell. Generated
DLLs and executables are reproducible products of identified source, not intrinsic
binary prerequisites. Separate assembly boundaries require an operational reason;
application and capability code may compile together. Launch-time lowering may
use PowerShell for staging without requiring SMA on admitted runtime paths.
Keep every implementation in PowerShell; no C#, Roslyn, intermediate native
wrapper libraries, WinForms, WPF, or browser-hosted UI.

Typed PowerShell managed source lives in `src/managed`. Existing independent
binders in `src` remain supported while migration is verified capability by
capability. Never imply that all existing binders are already persisted DLLs.
PSLowering admits a typed subset; compilation must reject unsupported constructs
without falling back to interpreted execution. Pin the compiler and verify
source/compiled equivalence, deterministic output, native ABI and lifecycle
before admitting a release. The appliance target retains IL and executes through
its own embedded RyuJIT. ReadyToRun and NativeAOT are outside this target.

## Appliance architecture and acceptance

Application semantics, state, geometry, interaction and presentation are authored
in PowerShell and may lower together with selected capabilities. Do not require
a second QuickPS control/visual/property hierarchy around an application's model.
Reusable primitives remain valid; their reuse does not require permanent binary
boundaries. Shared behavior is portable where its contract permits; Windows and
Android native backends retain distinct ABI, ownership and lifecycle contracts.

The first complete appliance proof is Calculator, preceded by a tiny lowered
return-42 runtime experiment. SoundRecorder follows with its portrait presentation,
waveform, elapsed time, Mic/Apps/Both, pause/stop and WAV output. Its restored source
is a behavioral reference with execution debt, not a completed lowered appliance.
Work on the active appliance and its blockers; no unrelated feature campaign.

The Windows release target is one emitted PE smaller than 10 MB (10,000,000
bytes), carrying statically linked CoreCLR and RyuJIT plus IL-only CoreLib and
appliance code. RyuJIT supplied in that EXE compiles its IL during execution.
No installed PowerShell/.NET, SMA, dotnet.exe, external runtime or QuickPS DLL,
bundler, runtime extraction, hostfxr/hostpolicy deployment or ReadyToRun payload.
Documented Windows system libraries remain OS dependencies. CoreLib-only means
the managed dependency surface, not the absence of a runtime or native services.
Other appliances may include additional managed libraries or SMA when their
declared behavior requires them; SoundRecorder must not acquire them implicitly.

Application semantics do not depend on HWND mechanics. Expose native handles
explicitly where a selected API needs them; do not mandate a Surface abstraction.
Keep src flat and mechanism-named for current work; directory layout is not an
assembly boundary. Source file, source set, compilation unit and artifact are
distinct. Follow the native-link boundary in docs/CORRECTION-PLAN.md; its selected
pre-linked runtime asset remains subject to exact RC1 startup and size proof.

Build orchestration and artifact generation remain PowerShell. Construct derived
images and compression in memory and write the final artifact; preserve pinned
file acquisition and integrity checks. The ordinary file-based agent execution
rule still applies. An embedded assembly probe is a separately reviewed product
runtime mechanism, not permission for agents to execute assemblies from bytes.
Do not weaken memory protection, signing, logging or application control.

Pwsh's existing Android image-store/probe and IL-only build provide a reference
for memory loading and size investigation. The measured 17,736,650-byte local
APK is evidence for that prototype, not a Windows size result or a release input.
Use authorized external inspections read-only; acquire shared inputs only from
pushed immutable revisions and verified digests in this repository's own cache.

First prove the runtime floor with a tiny lowered entry method and embedded
CoreLib before completing Calculator. Verify exact RC1 native input provenance,
static JIT execution, image lifetime, no extraction and a PE section/link-map size
ledger. Then admit Calculator and subsequently recorder code. See docs/PSLOWERING-REQUIREMENTS.md
for compiler gaps and docs/WORKORDER.md for ordered gates. Do not claim smaller,
faster or more responsive than another framework without equivalent measurements.

Windows is the current native ABI target. Pure math and data contracts should
remain separable. Android counterparts need independently documented native
contracts, explicit implementation and device verification. Do not claim that
Windows handles, COM slots, DLL imports or emitted x64 layouts work on Android.

QuickPS is a capability library. Application choreography, authored performances,
studio workflows, remote-appliance policy, session management and deployment
belong in consumers. Keep reusable drawing, text, transformations, native
animation, input, audio and capture mechanisms here with focused proofs.

## Direct launch and repository health

Every maintained QuickPS PS1 must stand on its own and have an adjacent same-stem
CMD. No-argument launch must meaningfully demonstrate, explain or report status
for its role. Applications launch themselves; graphical primitives show a bounded
capability proof; pure mechanisms print representative results; tools show status
or actionable usage; verification scripts execute their documented check. Hardware
or output selection can require explicit arguments rather than starting capture.

The CMD only finds its neighboring PS1, launches pwsh with -NoProfile -File,
forwards arguments and preserves the exit code. It contains no product logic,
dependency acquisition, installation, elevation or polling. The selected pwsh
must satisfy the pinned toolchain. Do not silently switch runtimes.

Use -Verify for a bounded deterministic/native proof and -Help for concise contract
and parameters where appropriate; not every file needs every mode. No-argument
launch must not install, register, download large inputs, overwrite user files,
capture audio or make persistent system changes. Mutating operations require
explicit selection and their existing change-control requirements.

Consumer mode returns the selected capability without launching its demonstration.
Mode selection must be explicit and preserve existing caller behavior during
migration. The call operator alone cannot distinguish consumer invocation from
direct script invocation; do not infer application intent from invocation spelling.
Data-returning catalog/theme scripts and typed compiler sources also need meaningful
direct observation while preserving their consumer/compiler contracts. Demonstration
entry code must not accidentally enter the appliance compilation unit.

Use tests/Verify.ps1 and tests/Run-Tests.ps1 as the health seam. Check maintained
source/launcher pairing and syntax statically; run actual role-specific verification
through the existing runner with native/hardware requirements and bounded lifetimes
declared. Never execute every no-argument tool indiscriminately, and never treat a
launcher, parse success or printed facade as proof of native behavior. Report checks
that do not execute as not run. No separate gallery framework or harness family.

This is a source usability/verification contract, not an assembly architecture.
The same source remains usable separately, bundled, or lowered with an appliance.
Implement the contract on Calculator and its selected primitives first; track the
remaining files as explicit repository-health debt rather than concealing gaps.

## Repository layout

- `src/`: independently invoked capability facades and native bindings.
- `src/managed/`: typed PowerShell implementation for derived IL artifacts.
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
PowerShell runspace. Source-staged consumers may use PowerShell for setup,
semantic dispatch and disposal; a fully lowered appliance performs those same
responsibilities in compiled PowerShell-authored methods without SMA.
No PowerShell callbacks on unmanaged paint paths or arbitrary native threads.
Synchronous enumeration callbacks must stay rooted on the invoking thread.

No polling for readiness, state or completion in any language or execution mode:
no recurring retries, sleep polling, busy waits, frame clocks, timer-driven redraw
or per-frame interpolation. Blocking GetMessage and documented native event waits
are valid. Bounded draining after a readiness signal and one-shot deadlines are
valid; a timeout used repeatedly to recheck readiness is polling. Applets express states, invalidation and finite time-based native
animation with cancellation/replacement and completion. Frames are measurement
units only, except required internal native ABI terminology. Benchmark code
must not become the application scheduler.

The restored SoundRecorder is a presentation reference, not an execution contract.
Its current 40 ms timer-driven capture is an identified violation to replace with
event-driven compiled delivery while preserving the UI. Historical restoration
does not authorize retaining polling or admitting this path as a release. Never
replace polling by disabling capture or moving it to another recurring timer.

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

For proposed IPC, tiles or media routing, read the planned section of
`docs/WORKORDER.md` and `docs/MEDIA-CAPABILITIES.md` first. These do not authorize
implementation during cleanup. Before IPC work, specify descriptor bounds,
authorization, publication ordering, transfer, cancellation and ownership, then
prove bounded same-user operation. Do not add speculative platform frameworks.

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

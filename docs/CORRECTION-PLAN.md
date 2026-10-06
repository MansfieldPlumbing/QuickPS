# QuickPS correction and construction plan

Status: implementation plan. Source composition, whole-appliance lowering and
embedded-runtime EXEs must not be reported as working before the corresponding
outputs execute. No new test framework or speculative platform framework.

## Purpose and first workload

Author appliances in PowerShell using selectable, precisely named primitive PS1
sources. Keep src flat with mechanism-named PS1 sources for the current work;
directory shape is not a permanent architectural requirement. Source remains available for
editing/reassembly. Select compilation boundaries for the purpose: separate
sources, a single source script, a chosen DLL, or a complete executable. File
boundaries do not dictate assembly boundaries. QuickPS consumes PSLowering;
compiler additions belong upstream.

Start with the owner's existing PowerShell calculator design. Extract the reusable
mechanisms actually required by its state, geometry, text, cached drawing and
event handling, then compose Calculator.ps1 and pursue the smallest verified
Calculator.exe. Use the parseable, event-driven calculator under the owner's Scripts directory
as the consolidation base. Preserve its application state, geometry and interaction;
replace its external-host bootstrap with selected QuickPS source. Keep the prior
variants recoverable until the canonical source and generated outputs pass parity.

Retain required primitive extraction and explicit naming. Defer module splits,
directory migrations or naming changes that do not serve this workload. SoundRecorder
follows the same build operation; its restored portrait presentation is a reference,
not an efficient execution implementation. Its timer polling must be replaced.

## Source-composition implementation

tools/Build-Appliance.ps1 now accepts explicit Application/Source selection and
emits Assembly or SourceBundle. Its no-argument/-Help behavior is usage; its CMD
only forwards invocation. Current admission is typed classes, with the existing
dot-source guard treated as staging policy. Other top-level runtime constructs,
duplicate files/types and unresolved composed types fail rather than disappearing.
Dependencies between selected classes resolve in the combined compilation unit.

SourceBundle contains the selected source, QuickPS license and the hash-verified
pinned compiler archive with its licenses. At launch it lowers the source using
the file-based compatibility adapter and executes the generated assembly by path.
It needs pinned pwsh and Windows tar, but no neighboring QuickPS source/compiler
files or prebuilt QuickPS DLL. Temporary compiler/source/assembly files currently
remain after launch. This is not the desired memory-only lowering implementation,
and does not relax the extraction-free EXE target.

Assembly output carries a source-set/compiler/runtime/hash receipt. Existing
outputs are preserved rather than overwritten. All generated artifacts belong
under ignored build/. WindowsExecutable explicitly fails until a verified minimal
static RC1 runtime/startup asset and payload contract are available.

tests/Managed.Verify.ps1 -Composition proves two selected sources form one
deterministic CoreLib-only assembly, execute a peer-class call returning 42,
generate standalone source that lowers at launch, and reject unsupported runtime
statements and duplicate selection. tests/Run-Tests.ps1 runs this existing check
when the pinned compiler archive is present; otherwise it reports not run.
This is a managed-source construction proof, not a static-runtime PE proof.

### Calculator behavior inventory

The two parseable Scripts calculator candidates have identical ButtonDef,
CalculatorState, Invoke-CalculatorLogic, Render-CalculatorWidget and Find-HitButton
implementations. Their original files remain backed up outside this repository.
The event-driven candidate is the porting authority; the canonical QuickPS app is
not yet implemented. Its external host bootstrap is excluded from the target.

| Behavior | Existing source contract |
| --- | --- |
| Window/key geometry | 340 by 520; 19 keys, four columns/five rows; zero spans two columns |
| Calculation | Display/equation state, operator selection, repeat equals, clear, sign, percent and one decimal separator |
| Divide by zero | Existing result is zero; preserve or explicitly resolve later, never silently change |
| Presentation | Rounded card/display/keys, caption hover, pressed/active operator colors and adjacent-key highlighting |
| Input | One delivered event at a time; mouse press/release edges, keyboard digits/operators/Enter/Escape, caption drag/minimize/close |
| Redraw | Initial presentation, then state/invalidation/resize changes; no periodic redraw |

Saved-file reference checks exercised dimensions/key layout, zero hit span,
addition/equation, repeated equals, sign/percent, clear, decimal and divide-by-zero
behavior without executing the historical host. Visual parity, keyboard/caption
delivery, native lifetime and whole-appliance lowering remain not run.
Port dynamic state/function bodies to typed runtime units without changing these
behaviors. Rounded drawing, text measurement and native callback admission must
be proven; the reference is not permission to replace them with stock controls.

## Primitive names and native contracts

Public names describe the operation. Windows backend names follow documented
mechanisms; a friendly umbrella name does not substitute for its actual contract.
Pure app math/state methods describe their own semantics rather than pretending
to be Windows APIs. The following candidates were checked against Microsoft docs;
they are requirements/candidates, not claims these bindings already exist here.

| Calculator mechanism | Explicit operation | Resource and reason |
| --- | --- | --- |
| Filled rounded card/display/keys | FillRoundedRectangle | [ID2D1RenderTarget](https://learn.microsoft.com/en-us/windows/win32/api/d2d1/nf-d2d1-id2d1rendertarget-fillroundedrectangle%28constd2d1_rounded_rect__id2d1brush%29): dimensions/radii in DIPs; check drawing failure at EndDraw |
| Rounded borders and hover outlines | DrawRoundedRectangle | [Documented stroke operation](https://learn.microsoft.com/en-us/windows/win32/api/d2d1/nf-d2d1-id2d1rendertarget-drawroundedrectangle%28constd2d1_rounded_rect__id2d1brush_float_id2d1strokestyle%29): separate stroke width/style from fill |
| Cached static drawing | CreateCompatibleRenderTarget, GetBitmap | [ID2D1BitmapRenderTarget](https://learn.microsoft.com/en-us/windows/win32/api/d2d1/nn-d2d1-id2d1bitmaprendertarget): reusable intermediate drawing; recreate with its device |
| Text with bounded layout | CreateTextLayout | [IDWriteFactory](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritefactory-createtextlayout): explicit string length, format and layout bounds |
| Rounded content clipping when needed | PushLayer with geometric mask, PopLayer | [ID2D1RenderTarget](https://learn.microsoft.com/en-us/windows/win32/api/d2d1/nf-d2d1-id2d1rendertarget-pushlayer%28constd2d1_layer_parameters__id2d1layer%29): establish geometry/mask ownership rather than treating rectangular clipping as rounded clipping |
| State change becomes a repaint request | InvalidateRect and WM_PAINT inside the backend | [Windows painting](https://learn.microsoft.com/en-us/windows/win32/learnwin32/painting-the-window): native update-region protocol, no app frame loop |

Confirm exact signatures, inheritance/vtable order, widths, calling convention,
ownership and device-loss behavior against pinned SDK headers before binding.
Documentation names alone do not prove an emitted ABI. Reuse working native code
where its contract is correct; add only missing operations required by the design.
Do not replace the calculator's presentation with stock controls.

## Resources: where, why and how

| Resource | What it contributes | How to use it |
| --- | --- | --- |
| src/D2D.Windows.ps1 and tests/Typography.Verify.ps1 | Existing brush, rectangle/text and render-target bindings | Inventory actual operations; extract/reuse necessary implementation, supply missing rounded/cached/layout operations, keep native ownership evidence |
| src/Window.Windows.ps1 and src/Win32.Windows.ps1 | Blocking dispatch, lifetime, backdrop and emitted procedure | Consolidate required host behavior; keep application semantics independent of handle mechanics; expose an OS handle explicitly when a selected API requires it; replace handwritten procedure emission when admitted typed code can express it |
| tools/Acquire-PSLowering.ps1 | Verified upstream acquisition | Consume commit 26fe7a864b19e70cfd6937ab062335a05fac3232 and its pinned SHA-256; do not patch the cache |
| tools/Build-Managed.ps1 | Existing typed-class compilation and provenance | Evolve into explicit source selection/output boundaries; retain current independent builds as compatibility choices |
| Pinned PSLowering src/Dev.MansfieldPlumbing.PowerShell.Lowering.psm1, Export-LoweredAssembly | All classes in one SourcePath become one assembly; ClassName selects reported/entry class | Stage selected typed declarations into one file, then call the existing compiler; EntryPoint emits managed entry metadata, not a native self-contained EXE |
| tools/Build-Backdrop.ps1 | Working generation of one PS1 from canonical sources | Reuse the source-generation principle; replace exact app-specific text replacement with explicit source boundaries where required |
| src/managed/AudioCapture.ps1 and src/managed/MediaSessionEvents.ps1 | Existing compiled event-driven workers | Reuse their blocking waits/lifecycle; remove UI-control coupling; replace reflective native dispatch after upstream pointer-call support |
| tests/Managed.Verify.ps1, tests/Run-Tests.ps1 and existing gallery proofs | Existing behavior/lifetime/native checks | Extend only for source-composition equivalence and the actual appliance; no parallel harness system |
| Owner-authorized Pwsh setup.ps1 at local HEAD a6416ca19edf57fb574b1b77a3b090c6ac96f17c | PowerShell-authored IL-only conversion, assembly store and native probe | Read ConvertTo-IlOnlyImage, New-AssemblyStoreBytes and New-NativeHostLibrary as reference; obtain any shared build input from pushed pinned sources, never build/mutate Pwsh here |
| Pinned dotnet/runtime native targets and host contract | Static CLR/JIT and image-resolution implementation paths | Use exact source locations below, verify correspondence to required RC1, obtain native build inputs, measure and execute a tiny runtime before claiming complete packaging |

Runtime source inspected at 3551975be08744f0418857c5bed8ab1545c5dd47:
[static JIT target](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/jit/static/CMakeLists.txt),
[static CLR inputs](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/dlls/mscoree/coreclr/CMakeLists.txt#L138),
[JIT initialization](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/coreclr/vm/codeman.cpp#L1911),
[external_assembly_probe](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/native/corehost/host_runtime_contract.h#L67).
A read-only probe of the pinned PowerShell runtime reports this same VMR revision
in CoreLib's informational version and CoreCLR/RyuJIT product versions. Static
build configuration and execution still need verification; matching source identity
does not prove a working QuickPS EXE.

## Source and artifact boundaries

- **Source file:** a human-editable implementation unit.
- **Source set:** the explicit files selected for one build.
- **Compilation unit:** the typed program submitted to PSLowering.
- **Artifact:** the PS1, DLL or EXE produced for a purpose.

A source set does not dictate an assembly boundary. One compilation unit can
contain declarations from several files; reusable DLLs are an optional choice.
Primitives must be discoverable, precisely named, source-authoritative and
independently selectable. Moving a file later must not change this model.

The build entry makes selection explicit:

```powershell
Build-Appliance.ps1 -Application Calculator.ps1 -Source <selected PS1 paths> -OutputKind SourceBundle
```

OutputKind selects SourceBundle, Assembly or WindowsExecutable. The first two
are implemented for admitted typed classes; WindowsExecutable remains unavailable. The authoring PS1 and its selected source remain
separately editable; SourceBundle materializes Calculator.standalone.ps1. An
optional ordinary PS1 recipe can return repeated selections. No dependency
resolver, project schema, module discovery, package graph or csproj is required.

## Concretely: four source/output forms

### 1. A PS1 using separate PS1 capabilities

Select trusted, script-relative source paths explicitly. Invoke a capability with
the call operator and receive its instance/facade; do not require global functions
or dot-sourcing. One existing example is `& ./src/Native.ps1`, which returns the
native binding instance. Application setup wires instances together and owns
cleanup. Runtime workers may already be compiled; the design must be able to build
them from selected source rather than require a pre-existing opaque DLL.

### 2. Generate one standalone PS1

Read the selected authoritative source files as data. Parse first; preserve each
source's parameters, scope and returned instance. Emit their source into fixed,
reviewable local units in the generated script and replace declared source calls
with those units. Never concatenate multiple top-level param blocks blindly or
execute fetched/generated strings through Invoke-Expression. Parse the result
and run it from its saved file. Build-Backdrop demonstrates today's limited form.

For launch-time lowering, include admitted runtime source and the necessary pinned
lowering machinery or an explicit hash-verified acquisition contract, including
licenses. The target composes source in memory, lowers to managed image bytes and
executes those images without neighboring capability sources or prebuilt DLLs.
That target needs a reviewed compiler byte-output interface and runtime admission;
it is not implemented by today's file-oriented Export-LoweredAssembly interface.

The current adapter may materialize deterministic source and compiler files,
import the compiler by path, emit an assembly file and load it by path. This is a
compatibility concession, not the desired source appliance architecture. Any
optional cache is keyed by source/compiler/runtime/options, not a prerequisite.
The agent's file-based execution baseline continues to govern investigation and
verification; product memory loading requires its own reviewed implementation.
The standalone PS1 requires pinned PowerShell at launch. The EXE stages ahead of
distribution and supplies its own runtime.

### 3. Emit the requested IL assembly

Parse selected files and select declared typed runtime units explicitly. Current
PSLowering compiles classes: combine their AST source extents into one staged
source file, retaining original file/line mapping. Reject duplicate names, missing
dependencies or unsupported runtime logic; do not silently omit application code.
Build-stage functions/setup do not belong in the emitted runtime unit. Validate the
staged file, then call Export-LoweredAssembly with SourcePath, ClassName, OutputPath,
Deterministic and EntryPoint when required. Verify dependency metadata and behavior.

Existing compiler invocation, after a valid typed unit has been staged:

```powershell
Import-Module ./build/upstream/pslowering/src/Dev.MansfieldPlumbing.PowerShell.Lowering.psd1
Export-LoweredAssembly -SourcePath ./build/staging/Calculator.ps1 -ClassName Calculator -OutputPath ./build/Calculator.dll -EntryPoint Main -Deterministic
```

Calculator/Main and the staged file above are proposed workload inputs, not files
that currently exist. The compiler interface itself exists. Its normal entry-point
output uses a dotnet host/runtime configuration; that does not meet the native
EXE requirement. For reusable libraries, omit EntryPoint. All selected classes
compile together; separate source files need not create separate DLLs.

### 4. Emit the smallest verified Windows EXE

1. Produce admitted appliance IL without SMA/dynamic fallback. Select only necessary
   managed dependencies, targeting CoreLib-only for this appliance.
2. Obtain native static CoreCLR/RyuJIT inputs for the exact pinned RC1 configuration
   from immutable, verified source/build artifacts in QuickPS's own ignored cache.
3. Prove a tiny IL entry via a PE's own static CoreCLR/RyuJIT and in-memory image
   probe. Establish CoreLib bootstrap and native initialization before a complete UI.
4. Keep retained native code in ordinary PE sections initially. Construct IL-only
   CoreLib/appliance images and their compressed store in memory; native startup
   expands managed images into bounded memory and returns pointer/length through
   the external probe. Keep images alive for their full runtime lifetime.
5. Construct the final PE under the native-link boundary below, using its verified
   asset/payload contract and preserving imports, relocations, unwind and protection. No apphost/bundler, hostfxr/
   hostpolicy deployment, runtime extraction or adjacent runtime/QuickPS DLL.
6. Execute the calculator and measure actual PE bytes and retained contributors.
   Under 10 MB (10,000,000 bytes) remains a hard target, not an estimate. Its own
   RyuJIT compiles IL during execution; no installed runtime, SMA, ReadyToRun or
   NativeAOT. Windows system APIs remain OS dependencies.

Use Windows' documented [compression API](https://learn.microsoft.com/en-us/windows/win32/cmpapi/using-the-compression-api)
only after measuring actual managed inputs. Linker retention first, optional native
features next when source/build evidence permits, CoreLib member reduction only
with verified runtime roots. Do not invent a custom native memory loader as an
unmeasured first step. Minimum size is established by the final artifact ledger.

## Native-link boundary

Owner-selected boundary: the first experiment uses a purpose-built, pinned pre-linked static
CoreCLR/RyuJIT asset. PowerShell owns source composition, lowering, managed-store
construction and final appliance construction around that asset. This is a
conditional implementation choice, not a claim that a suitable RC1 asset exists.
It does not use the standard .NET single-file host as the appliance template.

Three operations must remain distinguishable:

| Model | Who resolves native objects and archives? | Scope |
| --- | --- | --- |
| PowerShell drives Microsoft's linker | Microsoft's linker | Possible runtime-asset preparation; orchestration is PowerShell, linking is not PowerShell-authored |
| PowerShell constructs an appliance around a pinned pre-linked asset | Asset producer resolves native symbols; PowerShell constructs the payload and final image | Selected first experiment, subject to startup and size gates |
| PowerShell implements COFF/archive linking | PowerShell implements symbol resolution, COMDAT, relocations, imports, unwind, TLS and native initialization | Separate major undertaking; not implicitly authorized by this plan |

The selected asset needs an exact RC1 source/configuration identity, verified
digest, retained-object/link map and documented construction contract: native
entry/startup, managed-store location and bounds, CoreLib bootstrap, image-probe
installation, managed entry invocation and failure cleanup. PowerShell must use
declared payload slots/sections or a validated image-construction contract, not
arbitrary patching of an opaque executable. Preserve ASLR, DEP, applicable CFG,
relocations and unwind metadata. Produce final integrity/signing metadata after
construction. There must be no runtime extraction or neighboring runtime DLLs.

If no suitable asset can be obtained or produced reproducibly from pinned RC1
source, stop this gate and identify the missing startup/link contract and measured
size. Do not substitute a conventional host or silently implement a COFF linker.
Native linking during runtime-asset preparation is distinct from each appliance's
PowerShell build; document both, including any non-PowerShell tools involved.

The authorized read-only Pwsh setup observation is relevant: New-NativeHostLibrary
constructs startup code, a host-runtime contract and an assembly-store probe in
PowerShell. Its Android host depends on shared CoreCLR/store libraries; that does
not prove static Windows startup. Reuse its source-traced construction approach,
not its Android dependency model. Obtain release inputs from pushed immutable
source and verified digests in QuickPS's cache. PSLowering supplies appliance IL;
it is not the native linker or runtime asset provider.

### First construction contract: appended managed payload

The asset is generic runtime/startup machinery, with no Calculator semantics.
Microsoft's native toolchain may produce/version this pinned asset once; it is
not a dependency of normal appliance builds. Inspect the exact RC1 upstream
[static host target](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/native/corehost/apphost/static/CMakeLists.txt)
when establishing the asset configuration. Its existence is not proof of a small
approved template. Retain necessary GC/VM startup and replace generic deployment
policy with the fixed managed-image-store contract.

For the proof, preserve an already valid mapped native PE and append the managed
store and its versioned locator. PowerShell constructs:

```text
pinned minimal native PE
  + compressed IL-only managed store
  + index / lengths / hashes / declared entry / locator
  = Proof.exe, then Calculator.exe
```

The host opens/maps its own executable as data, validates the payload, expands
managed images into bounded process-owned memory, installs external_assembly_probe,
starts CoreCLR and invokes the declared entry. It never writes extracted images.
Reading the distributed executable is not extraction. A new PE section or general
native relinking is not a prerequisite.

Define the fixed binary layout only with its host implementation: format version,
compression identifier, offsets, compressed/expanded lengths, image count, names,
per-image integrity and assembly/type/method entry metadata. Reject overflow,
overlap, duplicate identities, invalid ranges, unknown versions and excessive
expanded sizes before native/runtime use. Keep image buffers alive for the runtime
lifetime. Hashes detect corruption; verified inputs and final signing establish trust.

The [Microsoft PE specification](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format)
distinguishes mapped image data, file offsets and certificate data. Do not assume
raw EOF is a permanent locator: signing can append certificate data. Establish a
locator that works for unsigned and signed images, excludes certificate data and
has verified signature coverage. Sign after construction and verify signed startup.
The appended-store construction remains unproven until Windows startup executes.

First execute a lowered static Main returning 42. Record the asset digest/build
configuration, complete PE size and startup result before adding calculator UI.
If the floor misses the budget, inspect retained native contributors before adding
native decompression/loading machinery. No size claim precedes measurement.

## Conditional implementation order

1. Inventory the existing PowerShell calculator's required operations and state;
   consolidate the event-driven version while preserving behavior. Extract only those
   primitive sources, checking Microsoft contracts and existing ABI comments.
2. If an operation already works here, reuse it. If absent, implement its required
   binding. If compiler admission fails, record the exact source position/category
   and unblock it upstream; never replace the requested presentation to avoid it.
3. Extend the existing build to stage an explicit source set. First prove existing
   typed sources work together, then calculator state/rendering. Keep a single
   build entry for output selection; helpers arise only where implementation needs them.
4. In parallel, measure the tiny runtime floor. If exact RC1 native inputs are
   unavailable, report the concrete missing asset/source pin. If size fails, report
   retained contributors and pursue measured reduction; do not substitute another
   deployment model. If pointer/callback features block UI, the tiny runtime proof
   can still proceed independently.
5. Assemble the calculator's separate-source PS1, single-source PS1, IL assembly
   and native EXE forms as each becomes admitted. Use the same application behavior
   checks. Then integrate the recorder with compiled event-driven capture and its
   existing presentation, preserving source choices and audio correctness.

See [app semantics](APP-SEMANTICS.md) and [compiler requirements](PSLOWERING-REQUIREMENTS.md).
Correct polling on the Calculator path first. Record unrelated pollers as debt;
do not start a repository-wide removal campaign. SoundRecorder's 40 ms timer
polling is corrected when that appliance is rebuilt. The capture test's 2 ms
sleep retry was replaced with audio-ready events and a final deadline. Blocking
window/media/audio waits, finite drains and one-shot deadlines are valid. No polling
in any language or execution mode is acceptable as a finished appliance.

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

## Layout and verification without expansion

Keep src flat with mechanism-named PS1 sources; use *.Windows.ps1 and independently
verified *.Android.ps1 counterparts. Group closely related operations when their
ownership/ABI is shared; do not require one file per operation or one DLL per file.
Calculator.ps1 and SoundRecorder.ps1 remain application examples. Evolve the existing
build into explicit output selection; retain packaging only as an optional output.
No new project schema, gallery browser, platform skeletons or general-purpose
container framework. The fixed executable payload layout is part of its host contract.

Reuse tests/Managed.Verify.ps1 for composition, tests/Typography.Verify.ps1 for
required drawing and tests/Run-Tests.ps1 for existing native/hardware checks. Add
only a missing concrete appliance/runtime check where existing checks cannot prove
it. Do not predeclare a new harness family. Human visual approval and native/audio
proof are distinct. Checks not executed are not run.

The measured 17,736,650-byte Pwsh APK is evidence for the existing Android prototype,
not Windows PE size. Preserve its build/store/probe knowledge without modifying
that checkout or consuming uncommitted content as product input. Use PowerShell
7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128, preserve backups/provenance/licensing,
keep derived/private artifacts untracked and run native checks before each requested
commit. No push without approval.

Current tracked inventory: 64 PS1 files; 17 have same-stem CMDs; 47 lack them.
This counts pairing only; direct-launch semantics and safety remain unverified.

# PSLowering requirements for QuickPS appliances

## Downstream boundary and evidence

QuickPS is a downstream consumer. PSLowering owns PowerShell AST admission,
semantic preservation, type resolution and ordinary IL emission. QuickPS owns
native contracts, source composition/staging, runtime hosting, artifact generation
and appliance proofs. Do not add a private compiler fork or hand-patch its cache.

The current build pins `26fe7a864b19e70cfd6937ab062335a05fac3232` in
`tools/Acquire-PSLowering.ps1` and `tools/Build-Managed.ps1`. Its cached module
`src/Dev.MansfieldPlumbing.PowerShell.Lowering.psm1` exports a single SourcePath
and optional EntryPoint, and compiles the source file's classes into one assembly.
Local managed sources already exercise typed state, imports, synchronization and
cleanup. That is evidence for these mechanisms, not complete recorder admission.

The upstream plan inspected at
[`1afabe056235a570da29e268824784557d4f6cdd`](https://github.com/MansfieldPlumbing/PSLowering/blob/1afabe056235a570da29e268824784557d4f6cdd/ROADMAP.md)
lists callbacks/function-pointer calls (1.2), assembly references (1.3) and typed
functions (1.5) as work items. Inspection of that plan does not update QuickPS's
compiler pin or prove those items implemented. New revisions require pinned
acquisition, digest verification and affected equivalence/native tests.

## Required for calculator native dispatch: callbacks and indirect calls

The recorder's window/input handlers and native COM calls need compiled paths
that never enter a PowerShell runspace. `gallery/SoundRecorder.ps1` currently
creates native-call delegates and uses DynamicInvoke; both managed workers also
use GetDelegateForFunctionPointer/DynamicInvoke for COM. Existing imports do not
replace calls through COM vtables or let Windows invoke lowered callback methods.

Upstream requirements:

- Emit a static method's UnmanagedCallersOnly metadata with a validated blittable
  signature and explicit target calling convention. Provide a typed address-taking
  operation for an admitted method, rejecting incompatible uses before emission.
- Emit unmanaged calli through a pointer with a declared exact signature and
  calling convention. Check parameter/return widths and reject mismatches. Pointer
  lifetime, table layout, bounds and native ownership remain consumer obligations.
- Verify Windows callback round trips, pointer-call returns/failures and rejection
  cases on the pinned runtime. Preserve exception boundaries: a callback must not
  let a managed exception escape into native code.

QuickPS then proves its own window lifetime/thread behavior and COM contracts.
Generic compiler callback tests alone do not prove WASAPI or window correctness.

## Required admission check: worker entry and method references

Source-staged facades currently create/start compiled worker instances. A complete
SMA-free appliance must perform startup itself. Determine whether the pinned
compiler can construct the needed strongly typed managed delegate from an emitted
method for ThreadStart and event delivery. If not, add validated method-reference
and delegate-construction lowering upstream, with static/instance target lifetime
tests. A managed ThreadStart delegate and an unmanaged callback address are
different contracts; UnmanagedCallersOnly does not satisfy both.

Use a concrete recorder fixture before declaring this a confirmed compiler gap.
Alternative documented worker startup must preserve native apartment/thread
affinity, cancellation and cleanup; do not add a scheduler merely to avoid it.

## Composition: minimum route and optional additions

| Need | Minimum route | When an upstream addition is necessary |
| --- | --- | --- |
| Appliance plus selected capabilities | PowerShell build stages typed classes into one source file; existing compiler emits one assembly | Multiple-source input with stable diagnostics/source maps is useful if staging cannot preserve traceability; not inherently required |
| Reusable derived DLL | Keep current independent build | Explicit assembly references and type/member resolution are needed when an appliance calls a separately compiled capability |
| Existing function-shaped runtime code | Rewrite admitted runtime units as typed class methods | Typed function lowering helps preserve function-shaped source; not a prerequisite for a class-based recorder |
| Native structures/out parameters | Current explicit bounded buffers and native-width fields where documented | Value-type layout/by-reference emission only where the chosen ABI cannot be expressed correctly through admitted bindings |
| Collection access or expression forms | Use supported typed arrays/explicit statements when behavior is preserved | Extend only for source-positioned rejections whose behavior warrants the addition |

These choices do not require scriptblock capture or general closure compilation.
Represent instance state explicitly in typed fields; callbacks dispatch using
documented per-instance context and lifetimes. No implicit global singleton state.

The compilation unit is a selected typed program, not inherently a file.
SourcePath staging is today's adapter. Stable multi-source diagnostics are useful;
an admitted source-in-memory/managed-image-byte output interface is required for
the desired memory-only launch-time lowering form. Neither is a native PE linker.
Keep file-based agent execution and integrity verification in force while proving
that separate product runtime mechanism.

## Changes to QuickPS source, not compiler features

Extend PSLowering only when an unsupported construct represents useful PowerShell
semantics that QuickPS should preserve. A convenient dynamic construct in a
historical script is not sufficient justification. First test a behavior-preserving
typed source rewrite; report genuine compiler gaps with an admitted/rejected fixture.

Replace runtime PSCustomObject/hashtable records with typed state, runtime command
invocation with admitted methods, and scriptblock handlers with compiled methods.
Move construction of tables/geometry/constants into PowerShell build staging where
appropriate. Eliminate readiness polling, including timer-driven capture, through documented native
events. Preserve the recorder's observable behavior and native cleanup.

The current recorder's folder/playback actions use Diagnostics.ProcessStartInfo
and Diagnostics.Process. Those are outside the CoreLib-only target; bind the
documented Windows shell mechanism rather than silently adding a library. Native
interop glue must compile into the appliance, not require a custom bridge DLL.

## Runtime and packaging work outside PSLowering

PSLowering emits IL; it need not become a CoreCLR linker, runtime trimmer or PE
host to satisfy this appliance. QuickPS's build consumes pinned native runtime
inputs and emits the PE containing its own CoreCLR/RyuJIT. It constructs IL-only
CoreLib/application images and the managed store, handles compression/bootstrap,
and checks native relocation/import/unwind/protection and image lifetimes.

Pwsh's PowerShell-authored Android store/probe and 17,736,650-byte local APK are
the existing reference. Preserve that approach to in-memory managed resolution;
prove Windows static startup separately. No external checkout content becomes a
product input without a pushed immutable source and verified digest. No build or
mutation of Pwsh is authorized by this downstream work.

Runtime-required CoreLib members must survive any trimming, even when absent
from the application's call graph. A dependency report from the compiler can
help, but cannot alone prove runtime-safe trimming. Link-map size reduction and
the under-10-MB PE gate need native build and execution evidence.

## Admission and acceptance order

1. Tiny lowered static entry runs through RyuJIT supplied in the same static PE,
   with embedded IL-only CoreLib/application images and no extraction. This runtime
   floor can be tested before adding the recorder's callback/compiler features.
2. Compile Calculator units first, then recorder units; report line/column and rejection category.
   Rank upstream requests by the actual behavior they unblock. No full recorder
   admission report exists yet; this document is not a completed inventory.
3. Upstream changes carry deterministic-output, rejection and PowerShell parity
   tests; native-only mechanisms carry independent ABI checks. Run the upstream
   suite in its own project through its authorized workflow, not from QuickPS.
4. Pin a pushed compiler revision in QuickPS only after evidence is reviewed.
   Compare source-staged and compiled behavior and verify no SMA reference or
   dynamic fallback in the admitted appliance. Check its managed dependency list.
5. Prove Calculator source/assembly/EXE behavior before recorder admission.
   Then prove Mic/Apps/Both, interruption, failures, repeated lifetimes and WAV output;
   verify no installed runtime/adjacent files/extraction and final PE bytes.
   Tests not executed are not run. Complete PE and whole-recorder gates are pending.

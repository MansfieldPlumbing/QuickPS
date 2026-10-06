# App semantics for QuickPS appliances

Status: intended semantics and correction requirements. Existing samples do not
all satisfy them. This is not a new application framework or descriptor schema.

## Source, state and behavior

PowerShell source defines application behavior. The same behavior may run source-
staged or as lowered IL. Compilation boundaries and output format must not change
its state transitions, geometry or interaction. Unsupported lowering fails visibly;
it never falls back to interpretation silently. Source remains available to rebuild.

The app owns its state, layout, hit regions, commands and presentation. A reusable
primitive implements a specific mechanism, not application policy. Do not require
a duplicate QuickPS control/visual/property model. State is explicit and instance-
owned; immutable definitions may be shared. Typed methods/fields express runtime
behavior without requiring closure capture or mutable global singleton state.

## Events and idle behavior

Input, native readiness, completion, cancellation, resize and resource loss cause
work. With no events or pending work, application code performs no periodic checks
or scheduled redraw. No sleep retries, readiness polling, frame loops or recurring
timer-driven capture/redraw, even when compiled or moved to a background thread.

The platform backend owns documented blocking dispatch/waits. The app receives
semantic events; it never calls a pump to make progress. A finite drain of queued
data after readiness is valid and bounded. One-shot operation deadlines are valid;
repeated timeouts that recheck readiness are polling. Cancellation must wake a
blocking worker and complete cleanup without an idle retry loop.

State changes occur on their declared owner. Workers publish results through a
bounded, synchronized path. Do not enter a PowerShell runspace from an unmanaged
paint callback or an arbitrary native/audio thread. Fully lowered appliances can
perform setup, semantic dispatch and disposal as compiled PowerShell methods.
Source-staged development is a separate mode, not a permanent interpreter rule.

## Invalidation and drawing

Update state, determine what visible data changed and request invalidation. An
unchanged result causes no new drawing request. Coalesce redundant updates without
discarding ordered commands/errors/completion. Paint reads consistent state; it
does not run capture, application transitions or recursive event delivery.

The Windows backend follows [the update-region/WM_PAINT protocol](https://learn.microsoft.com/en-us/windows/win32/learnwin32/painting-the-window).
Application semantics must not depend on HWND mechanics. Expose native handles
explicitly where a selected capability genuinely requires an operating-system
handle; otherwise keep platform implementation details inside that capability.
Do not require a Surface abstraction or a second window object model. Native
event dispatch is implementation machinery, not an application frame API.

Reuse brushes, text formats/layouts, geometry and static cached drawing while their
inputs and device lifetime remain valid. Rebuild static drawing only when its
geometry, style, scale or device changes; update dynamic text/interaction separately.
Do not allocate native buffers, create brushes or manufacture delegate types for
every drawing operation. A paint failure/device loss has explicit recovery or
failure semantics and never becomes unconditional repaint retry.

Use explicit coordinate units, scale transforms, clipping and text bounds. Match
the authored geometry; do not exchange rounded shapes for rectangle substitutes.
Hit regions and visual clipping have explicit contracts, not accidental inference.
Finite native animation has cancellation/replacement and completion; application
code does not interpolate on ticks or use a compositor as a semantic polling clock.

## Efficient capture and worker delivery

Audio capture starts with an explicit source/format contract, native readiness
event and cancellation path. Delivery and native packet ownership execute in the
compiled worker. [WASAPI's event handle](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-seteventhandle)
signals buffer availability. Drain ready packets with a bound and release every
acquired packet on the required thread, including failure. No UI timer fetches audio.

Capture exposes data/levels/status, completion and failure. It does not know a
progress-bar handle, caption or consumer renderer. Use reusable bounded buffers
and explicit ownership; avoid per-packet object arrays/reflection/native delegate
construction on admitted steady-state paths. Exact capacities and overflow policy
come from the chosen format and consumer contract, not an unbounded queue.

Durable audio data is not discarded merely because visual updates are coalesced.
Waveform/level display can consume the latest bounded summary while file output
preserves the required samples. Pause, resume, stop and failure are explicit state
transitions; UI responsiveness does not depend on a worker periodically checking it.
Postprocessing/file I/O that can block remains off the presentation owner.

SoundRecorder currently violates these requirements: its recurring 40 ms timer
reads packets, allocates processing storage and drives waveform/title changes.
Its existing Both path does not itself establish correct mixed-source output.
Replacing that execution structure is required; preserving the portrait design
does not require preserving its inefficient scheduling or sample ownership.

Elapsed time derives from an authoritative clock or recorded sample count at real
events. Display updates accompany available progress or a specifically requested
one-shot semantic deadline. Do not add an arbitrary high-frequency tick because
the display includes a timer. Any proposed precision/idle update requirement must
be specified rather than inferred from a former frame rate.

## Lifetime and failure

Construct transactionally: failed setup releases already-acquired resources.
Callbacks/delegates/context and embedded managed images outlive every use.
Cancel workers, observe completion and retire resources in ownership order.
Disposal is idempotent. Bound counts, lengths, offsets and arithmetic before native
access. Do not free shared/borrowed objects or outstanding GPU/audio resources.

Errors become defined state/results; never suppress capture failure to preserve
a success-looking UI. An event storm cannot allocate an unlimited queue. Input
ordering, dropped visual summaries, cancellation and stale results have declared
behavior. Accessibility, DPI and visual correctness need their own evidence when
claimed; a visible window or successful HRESULT proves only its own layer.

## Output independence and focused evidence

Separate-source and assembled PS1 forms require their declared pinned PowerShell
environment. DLLs are derived compilation choices. The standalone EXE supplies
its own CoreCLR/RyuJIT and admitted managed images; it must not secretly load SMA
or depend on an installed runtime/adjacent capability DLL. Runtime image lifetime,
no extraction, required OS imports and final size are checked on the real artifact.

Use existing behavior/native checks with representative input, state, drawing and
stop/failure cases. Measure idle wake-ups, unnecessary work, allocations and copies
where the changed mechanism makes them relevant. Do not add a generalized harness,
benchmark suite or test per helper. Source/compiled equivalence, human presentation
approval and final artifact independence are separate claims. Unrun checks are not
run. See [the construction plan](CORRECTION-PLAN.md) for resources and conditional steps.

CoreLib-only is the minimal managed dependency target of the Calculator/recorder
proofs, not a restriction on all QuickPS applications. Declare dependencies from
actual behavior. Persistent compilation caches and a flat source directory are
optional implementation/organization choices, not app semantics. Agent execution
retains file-based loading and pinned-file integrity requirements; an admitted
product image-store implementation has its own documented loading contract.

Direct demonstration and consumer execution preserve the same capability contract.
No-argument launch is safe and useful; an adjacent CMD only launches its PS1.
Explicit consumer selection suppresses demonstrations. Demo/build code stays outside
the selected typed appliance unit. See the correction plan for repository-health checks.

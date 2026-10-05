# Shared-resource IPC contract

Status: design requirements and implementation gates, not a completed transport or a memory-safety certification.

QuickPS exposes Windows-native sharing primitives usable for graphics, capture, media routing, and inference data. Tensor buffers, GPU surfaces, and results are payloads; model execution and application policy are not transport responsibilities.

## Scope and authority

- User-scoped sharing is the default. System-wide sharing is explicit opt-in with documented privileges and restrictive ACLs. User identity and Windows session are distinct; namespace selection alone does not establish authorization.
- Each instance owns its state. No process-global singleton adapter, registry, binder, or mutable route table. A deliberately shared directory is an IPC resource with an explicit owner and access policy, not a global variable.
- A native handle is process-local. Transfer requires documented duplication or opening an authorized named resource. Never accept a numeric handle in shared bytes as an automatically valid capability.
- Do not log credentials, device identifiers unnecessarily, or capability values. Validate untrusted metadata before opening or interpreting referenced resources.

## Long-lived nodes and memory safety

- Allocate, bind, discover, compile, open, map, and measure at topology changes or invalidation, not per publication. Reuse established resources while their contract remains valid.
- Opaque handles identify resources; they are not pointers or arbitrary addresses. Keep resource identity, allocation extent, payload type, publication sequence, valid length, and synchronization distinct.
- Bounds and rights remain invariant for a held resource. A format/extent change requires a validated replacement transition; never silently reinterpret an outstanding allocation.
- Validate offset and length without overflowing: offset must be within extent, then length must be no greater than extent minus offset. Validate dimensional products, row pitch, alignment and native-width conversions before native calls.
- Revocation stops new access. Final release waits for outstanding CPU users and GPU work to retire safely. A process-death notification initiates retirement; it is not permission to free an in-flight GPU resource immediately.
- Clear sensitive owned storage before reuse where required and technically supported. Reject unsupported ownership transitions rather than guessing.
- Long-lived allocation and opaque handles reduce churn and misuse but do not themselves prove memory safety. Treat pointer arithmetic, native callbacks, malformed descriptors, races and teardown as explicit verification targets.

## Descriptor and publication

- Start with a fixed, versioned header: magic, version, header length, payload type, allocation extent, valid offset/length, layout/stride, publication sequence and synchronization contract. Reject unknown required features and inconsistent extents.
- Default to explicit metadata storage alongside a GPU texture. An in-band header is allowed only with a declared reserved extent and validated layout. Reserved texture rows are format-specific; they are not automatically accessible as linear bytes.
- Nested resources use authorized transfer/opening and independent lifetime rules. Within one allocation, prefer validated offsets. No shared raw pointer graph.
- A reader must never interpret partially published control metadata. Specify a documented publication protocol and its memory ordering; a sequence number alone is not synchronization.
- Payload completeness is a declared delivery policy. Lossy latest-value delivery may skip publications; incomplete tensors or images must not silently masquerade as valid complete samples. Reliable delivery is a separate optional protocol, not a hidden base-carrier requirement.
- Padding, pitch slack and allocation tails carry no implicit semantics. Any metadata region is explicitly part of the layout contract.
- Command payloads use a bounded, validated operation schema. Transport does not execute arbitrary script, pointers, or native instructions supplied by another process.

## No-thrashing execution

- No periodic process scans, heartbeats, timer pings, or resource reopen/remap cycles on the local delivery path.
- Use documented blocking/event-driven discovery and liveness mechanisms. Prefer process termination handles for process liveness. Mutex abandonment describes owner-thread failure while holding a mutex, not general process liveness; do not use mutex waits through an API that does not support them.
- PowerShell handles topology and semantic events. Keep sample delivery, GPU synchronization and presentation in native mechanisms. No PowerShell per-sample polling scheduler.
- Use GPU queue synchronization for GPU dependencies where supported; do not substitute CPU waits without a reason. CPU blocking waits require cancellation and a defined shutdown path.
- Bound resource counts, queues, pending requests and retained publications. Define drop/reject/backpressure policy. No automatic unbounded retry or reconnect loop.
- Reconfiguration is transactional: validate and prepare replacement, switch at a safe boundary, retire old resources. Failure preserves the old valid state or produces an explicit stopped state.
- Count actual copies, allocations, mappings, waits and crossings. Do not label a path zero-copy merely because it uses shared memory.

## Acceptance gates in order

1. Pure descriptor tests: truncation, unsupported version, oversized lengths, arithmetic overflow, malformed layout, unauthorized command, and valid round-trip. No camera or GPU required.
2. Same-user cross-process shared-buffer proof: explicit transfer, publication, cancellation and shutdown. Observe buffer contents through the documented synchronization protocol.
3. Failure tests: publisher exit, reader exit, stale identity, denied access, interrupted replacement, stalled reader and repeated open/close. Confirm bounded resource use and absence of idle polling.
4. GPU sharing proof: adapter mismatch, format mismatch, fence ordering, resource retirement and readback correctness. Report unsupported hardware distinctly.
5. Media/inference payload proofs reuse the same mechanisms; no model runtime becomes a transport dependency.
6. Scale configured routes separately from active decoding and composition. The 200-camera target is unverified until representative workload measurements pass.

Do not replace the existing multiplexer or camera application until the corresponding composed proof passes parity, lifecycle and performance gates. Registration and system-wide changes need their own reviewed, recoverable operation.

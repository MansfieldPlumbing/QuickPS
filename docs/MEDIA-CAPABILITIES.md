# Native media capability plan

QuickPS supplies Windows-native mechanisms. Camera management products, surveillance policy, model inference, and remote appliances belong to consumers. This is an implementation plan, not a claim that these capabilities exist yet.

## Public vocabulary

- Source: supplies timestamped media samples or GPU surfaces with an explicit format and lifetime.
- Route: connects a source to an output with a declared selection and overload policy.
- Mixer: composes selected inputs into one output surface (switch, grid, picture-in-picture).
- Output: preview, encoder/stream, recording, or virtual-camera endpoint.

Keep discovery/control separate from sample delivery. PowerShell configures topology and reacts to semantic events; native media components perform delivery, synchronization and presentation. Do not introduce a PowerShell sample-processing loop or timer-based scheduler as the default transport.

## Required contracts before implementation

Each capability must declare format negotiation, timestamps/timebase, ownership, thread affinity, start/stop/cancel behavior, bounded buffering, overload policy, disconnect/reconnect behavior, and errors. GPU sharing additionally needs adapter identity, access rights, synchronization, and explicit resource lifetime. Cross-process discovery must validate metadata and authorization; a discovered name is not trust.

Do not call all network cameras interchangeable. Device adapters must identify transport, codec, credentials handling, and supported negotiation. Never log credentials or embed them in example URLs. Broadcasting needs an explicit transport/codec; a virtual camera is a distinct output, not a network broadcast protocol.

## Ordered proofs

1. Synthetic native source to independent preview: establish resource sharing, synchronization, bounded delivery and clean shutdown without camera permissions or model dependencies.
2. Two sources to switch/grid/PIP mixer: verify layout, input removal, stopped/stalled sources, resource cleanup and output continuity. Visible proof plus bounded automated checks.
3. Output adapters: treat network streaming, recording and virtual-camera activation as separately testable capabilities. Select documented APIs and inspect pinned source before binding. Virtual-camera registration/hosting requires a specific reviewed installation and rollback plan; do not register arbitrary DLLs.
4. Camera adapters: physical camera first, then an explicitly selected network transport/codec. Test denied access, negotiation failure, disconnect and cancellation.
5. Scale tests: grow synthetic route counts independently from decode and encode workloads, then measure representative real inputs.

## 200-camera target

Separate four quantities: configured sources, concurrently receiving sources, concurrently decoded sources, and displayed/mixed sources. Record resolution, codec, rate, bitrate, transport, decoder limits, adapter, output dimensions, queue limits, bandwidth, latency, memory and test duration. Include a stalled source and slow output.

Support selective subscriptions and lower-resolution inputs where available. Define whether overload drops stale samples, rejects work, or blocks upstream; no unbounded queue may hide overload. Acceptance requires bounded memory, predictable degradation and responsive control, not just connection count. No 200-stream decode capacity or performance claim has been established.

## Existing application replacement

VirtuaCam is a reference implementation, not a runtime dependency or an authorized deletion target. Inventory its source discovery, GPU sharing, composition, endpoint activation and cleanup behavior. Replace each with an independently verified QuickPS primitive and a parity proof. Keep the existing application intact until the composed replacement satisfies its required scenarios. Model/tracking application code remains in lens-refactor.

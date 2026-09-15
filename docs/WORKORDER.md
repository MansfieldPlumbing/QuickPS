# QuickPS Work Order

## Mission

Maintain a small PowerShell graphics library whose source binds directly to operating-system graphics and media APIs.

QuickPS currently targets Windows. Each source file is independently invoked and returns the values or native-backed objects it creates. Applications compose those results with ordinary PowerShell.

## Required discipline

- Keep each coherent binding or graphics component in a plainly named `.ps1` file.
- Reject dot-sourcing from source files so private helpers and state remain private.
- Run `tests/Verify.ps1` before each source checkpoint.
- Add a deterministic test before claiming a geometry or math component works.
- Use an explicit hardware-facing test for windows, presentation, capture, and audio.
- Keep generated screenshots, recordings, logs, and verification results out of source control.
- Preserve ABI comments that explain message behavior, COM inheritance, vtable slots, structures, constants, and teardown.
- Do not introduce a custom bridge DLL when the operating-system ABI is directly callable.

## Current source

```text
Camera3D.ps1
Composition.Windows.ps1
D3D12.Windows.ps1
DXGI.Windows.ps1
Geometry3D.ps1
MediaFoundation.Windows.ps1
Native.ps1
Shader.Windows.ps1
Wasapi.Windows.ps1
Wic.Windows.ps1
Window.Windows.ps1
```

## Current verified graphics surface

- perspective camera matrices;
- indexed box, plane, sphere, cylinder, cone, torus, and capsule geometry;
- runtime HLSL compilation;
- D3D12 indexed drawing and presentation;
- image gates that detect blank, split, and undeclared-hole output.

## Next work

1. Give the existing source a stable public PowerShell calling convention without adding a router or manager.
2. Add input bindings and a small scene/input example.
3. Separate deterministic tests from hardware-facing demonstrations in automation.
4. Add Direct2D and DirectWrite only as accurately named Windows bindings.
5. Revisit Android as a separate platform implementation after the Windows library surface is stable.
6. Decide packaging only after direct source invocation remains fully supported.

## Exclusions

QuickPS does not own application timing, a render loop, scene policy, a capability registry, or a resource manager. It does not contain JavaScript parsing or SMA/IL lowering research; those live in JS2PS and SMADirect respectively.

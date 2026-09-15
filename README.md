# QuickPS

QuickPS is a collection of PowerShell graphics and native Windows building blocks written in PowerShell.

The project binds directly to Windows exports and COM interfaces. It does not require a custom managed bridge, a C++ wrapper DLL, a renderer framework, or a global command router.

## Current scope

The repository currently contains working source for:

- Win32 window creation and message pumping;
- DXGI adapter and swap-chain access;
- D3D12 device, command, resource, fence, and presentation operations;
- runtime HLSL compilation through the Windows shader compiler;
- DirectComposition;
- WIC bitmap operations;
- WASAPI capture;
- Media Foundation device enumeration;
- 3D camera matrices;
- indexed box, plane, sphere, cylinder, cone, torus, and capsule geometry.

The current implementation is Windows-focused. Android work and application-sized scripts are not part of this repository yet.

## Use

Each file under `src` is an independently invoked PowerShell building block. For example:

```powershell
$window = & .\src\Window.Windows.ps1 -Width 720 -Height 420 -Title 'QuickPS'
$geometry = & .\src\Geometry3D.ps1 -Shape Box
```

Native-backed objects expose their own operations and teardown. Callers compose returned values using ordinary PowerShell variables, scriptblocks, processes, and runspaces.

The source files reject dot-sourcing so their private helper functions and state do not leak into the caller's scope.

## Try it

On Windows with PowerShell 7:

```powershell
pwsh -NoProfile -File .\examples\Show.ps1 -Name Window
pwsh -NoProfile -File .\tests\Scene3D.ps1 -Shape Box -Seconds 4
```

The `.cmd` files under `examples` provide clickable demonstrations.

## Verify

Run the source ratchet and the deterministic geometry tests:

```powershell
pwsh -NoProfile -File .\tests\Verify.ps1
pwsh -NoProfile -File .\tests\Geometry3D.Verify.ps1
pwsh -NoProfile -File .\tests\Camera3D.Verify.ps1
pwsh -NoProfile -File .\tests\ImageSilhouetteGate.Verify.ps1
```

Window, D3D12 presentation, audio capture, and screenshot tests exercise real machine resources and are kept as explicit tests rather than silently included in the deterministic suite.

## Layout

```text
src/       PowerShell graphics and Windows binding source
tests/     deterministic and hardware-facing verification scripts
examples/  clickable and command-line demonstrations
docs/      project work orders and design constraints
```

Generated screenshots, recordings, and verification results are local artifacts and are not source.

## Design boundary

QuickPS provides mechanisms. It does not own an application loop, timing policy, scene manager, capability system, or resource registry. Higher-level scripts decide how to combine the pieces.

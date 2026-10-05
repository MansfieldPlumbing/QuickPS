# Live tiles: target contract

Status: target contract, not evidence. Nothing below is implemented unless a
verification result says so. Read with `AGENTS.md` (no frame loops,
compositor-owned animation) and its shared-model guidance.

## 1. Purpose

A tile surface is a projection of a hosted PowerShell runspace: each tile shows
state a script owns and launches a command the script names. Desktop and
fullscreen Start consume the same model. The surface stays fast for the same
reason Metro did: a small closed set of animations, all executed by the
compositor, and tile content rasterized only when it changes.

A concrete donor and immutable source revision must be selected before implementing visual conformance. No donor conformance is established by this target contract.

## 2. Ownership split

| Concern | Owner | Runs when |
| --- | --- | --- |
| Tile model, layout, reflow, hit-testing | Pure PowerShell (no native calls) | A semantic event changes the model |
| Face content (text, value, glyph) | Face provider scriptblock in the hosted runspace | Only on events the provider declared |
| Rasterizing a face | Direct2D/DirectWrite into that face's composition surface | Only when the face content changed |
| Flip, peek, tilt, turnstile, entrance motion | DirectComposition animations | Compositor clock; no PowerShell |
| Presentation | DWM / DirectComposition | Compositor |

Lowering boundary: the view host, model, reflow, queue, semantic tree,
navigation and failure handling are fixed, deterministic code and are written
in a statically typed PowerShell subset so they can later be lowered to a
managed assembly. They are lowered only after their behaviour is complete and
covered by vectors. Tile scripts, their `param()` knobs, face providers and
control actions are user code edited in place: never built into shipped
assemblies, and any run-time lowering of their hot paths is a cache derived
from the source and discarded on edit. The lowered views project them.

PowerShell never runs per frame, never interpolates, and never schedules
redraw. Idle cost with no declared events is zero PowerShell invocations.

## 3. Model

```text
Tile     { Id, Title, Glyph, Accent, Size, Launch, Face?, Live }
Size     Small (1x1) | Medium (2x2) | Wide (4x2)          donor getTileSpan, Start.tsx:395-399
         | Large (4x4) | Span(cols, rows), cols <= Columns  control surfaces (remotes, widgets)
Controls Control[]? (a tile with controls is a control surface)
Control  { Id, Kind, Label, Glyph?, Bounds (in tile units), Action, Value? }
Kind     Button | Toggle | Slider | DPad | Text
Source   the tile's own .ps1 path (opened by Edit)
         cycle Small -> Medium -> Wide -> Small            donor cycleTileSize, Start.tsx:401-405
Face     { Front: Content, Back: Content?, Tag?: string }
Queue    Face[] (max 5), oldest replaced first, same Tag replaced in place
Content  { Value?: string, Lines?: string[] (max 3), Badge?: int }
Launch   a command name plus arguments, resolved in the hosted runspace
```

- A tile is one complete `.ps1` file that returns its `Tile` hashtable, the same
  shape as the app descriptors (`gallery/apps/Files.ps1`). No separate
  `.psd1`, manifest or catalogue entry describes it.
- Live tiles keep a notification queue: at most five faces, cycled by the
  compositor. A new face replaces the oldest; a face carrying a `Tag` replaces
  the queued face with the same tag instead. This is the Windows 8.1 rule
  (design guidelines, "Tiles can cycle through up to five notifications").
- Knobs are the script's own `param()` block, read with the SMA parser
  (`ParamBlockAst`), never a separate settings description: `[switch]` or
  `[bool]` is a toggle, `[ValidateSet]` a choice, `[ValidateRange]` on a numeric
  type a slider, other typed parameters a text field, `[Parameter(Mandatory)]`
  a required field, help comments the caption. Changed knob values re-invoke
  the tile script with those parameters.
- Quick actions are tiles. A control surface (a remote, a media widget, a
  toggle) is a tile with `Controls`; each control's `Action` runs in the hosted
  runspace on the dispatch thread. Tapping a control acts; tapping the tile
  title area opens the tile full-size with its controls, knobs and Edit.
- Every tile, and every view (Start, settings, console, desktop), has a
  `Source`. Edit opens it in the shared text editor; saving re-loads that tile
  or view from the file.
- `Title` and `Glyph` belong to the tile, not the face. The renderer draws them
  in fixed positions (glyph centred, title bottom-left, badge or value
  bottom-right). Content is clipped to the tile and never overlaps the title.
- A face provider is `{ param($state) ... }` returning a `Face`. It is trusted
  local code under the descriptor rules in `AGENTS.md` §5, not sandboxed data.
- Provider triggers are declared, never polled: an interval of at least 30
  seconds, a named engine event, job state change, or file-system change.
  Each trigger is delivered to the owning dispatch thread as a semantic event.
- A provider result equal to the current face changes nothing: no rasterization,
  no commit.

## 4. Layout (pure, testable)

- `Unit` = 56 DIP x UI scale. `Gutter` = 6 DIP.
- `Columns` = max(4, floor((width - 2*pad + Gutter) / (Unit + Gutter))), rounded
  down to an even number so Medium and Wide tiles align. The grid is centred.
- Reflow is the donor's first-fit placement (`reflowTiles`, Start.tsx:407) with
  `Columns` as a parameter; no literal column count anywhere.
- Rotation and resize re-run reflow with the new column count; tile order is
  preserved. Tile pixel size never depends on window width.

## 5. Animation catalogue (closed set)

Each entry is a finite definition: target property, keyframes, duration,
cancellation/replacement, completion. New motion requires a new entry here.

The set is bounded by the Windows 8.1 animation library, which the design
guidelines list as exactly ten families: add and delete, content transition,
drag, edge-based UI, fade, page transition, pointer click, reposition, pop-up
UI, swipe. Entries below name their family; motion outside those families is
not added. Pointer click is Tilt, page transition is Turnstile, reposition is
Reflow, add and delete is Entrance/Exit.

| Name | Target | Definition (to be finalized against the design reference) |
| --- | --- | --- |
| Flip | tile 3D rotation about X | front 0 to 90 deg, back -90 to 0 deg, cubic ease; Back hidden by back-face visibility |
| FlipCycle | Flip, repeating | Flip forward, hold, Flip back, hold; `AddRepeat`; per-tile begin offset for stagger |
| Peek | front/back vertical offset | slide by tile height, hold, slide back |
| Tilt | tile 3D rotation toward the pointer | on press; released on up or cancel |
| Turnstile | page 3D rotation about the left edge | page enter/exit |
| Entrance | tile opacity and offset | staggered by grid position on page show |
| Reflow | tile offset | old slot to new slot after layout change; replaces any running Reflow |
| QueueCycle | Flip or Peek between queued faces | advances through the notification queue; same stagger rule as FlipCycle |

Peek follows the guidelines: two stacked frames, the cycle may start at
either frame, and Peek is not used when the important part of a face would
sit off-screen during the motion, when the two frames are unrelated, or for
state the user already knows.

- Replacement: starting an animation on a property replaces the previous one on
  that property. Completion is reported as a semantic event, never polled.
- A live tile with a Back face runs FlipCycle entirely in the compositor. Face
  updates redraw the affected surface; the running animation is not restarted.

## 6. Semantic tree and navigation

The scene model is the accessibility tree. There is no second description of
the UI for assistive technology, tests or agents; all three navigate the same
nodes the renderer draws.

```text
Node     { Id, Role, Name, Value?, State, Bounds, Actions, Children }
Role     Page | Group | Tile | ListItem | Button | Toggle | Slider | DPad | Text | Editor
Name     the tile Title, control Label, or page/group label
Value    current front Content (Value, then Lines, joined), or the control's Value
State    Focused | Selected | Live | Busy | Checked (flags)
Actions  Invoke | Edit | Open | SetValue | Resize | Unpin | Back (what the node supports)
```

- Children are in reading order, which is the reflow order (row-major by grid
  position), so keyboard, screen-reader and agent traversal agree with layout.
- Navigation is semantic and identical for every caller:
  `Move(Up|Down|Left|Right)` spatially within the grid, `Next`/`Previous` in
  reading order, `Invoke`, `Edit`, `Open`, `SetValue`, `Swipe(Left|Right)`,
  `Back`. Swipe meaning is fixed: `Swipe(Right)` on any node with a `Source`
  is Edit (the editor page slides in, its source in view); `Swipe(Left)` from
  Start is All apps; `Swipe(Right)` where no node has a source is Back.
  Controls inside a control surface are child nodes, reachable with `Move`. Tab and arrow keys map onto these, as the guidelines require
  ("Let users navigate your app using the Tab and arrow keys").
- A face change on a focused or live tile is announced politely, the
  equivalent of `AutomationProperties.LiveSetting` in the guidelines.
- Windows exposure: a UI Automation fragment provider over this tree, returned
  from the window's `WM_GETOBJECT` handling. Interfaces and exports are
  recorded from SDK headers when implemented, like every other ABI block.
- Programmatic exposure: the facade returns the tree and accepts the same
  navigation verbs (`GetTree`, `Focus`, `Move`, `Invoke`, `Swipe`, `Back`),
  each returning the node that is focused afterwards. A test or an agent drives
  the surface through these without screenshots or coordinates.
- Pointer input resolves to a node by hit-testing `Bounds`, then performs the
  same action; there is no pointer-only behaviour.

### Views, cycles and failure

Views are peers owned by one host, never nested inside each other.

- A view (Start, desktop, console, settings, editor) is an instance the host
  owns. A tile's `Invoke` or a command such as `desktop` emits
  `Navigate(ViewId)`; it never constructs a view inside the current one.
- Navigation activates the existing instance of that view unless the request
  explicitly asks for a new one. Start, a console tile, `desktop`, and the
  desktop's own Start tiles therefore cycle through the same few instances; the
  cycle allocates nothing new.
- The back stack holds view references. Navigating to a view already in the
  stack truncates back to it instead of pushing a copy, so cycling never grows
  the stack. A tile that targets the view it is already shown in only focuses.
- Start and the desktop are two projections of one tile model (§1). Showing
  tiles inside the desktop shares the model; it does not embed Start.
- Faces are sinks. Applying a face never raises an event that a face provider
  can subscribe to, so a tile showing a view's state cannot feed back into
  that view's providers. Bursts from one source coalesce: the latest wins.

Every failure leaves the surface navigable and the fix one Edit away:

| Failure | Behaviour |
| --- | --- |
| Tile script or provider throws | Tile shows an error face (message, `Busy` cleared); Invoke and controls disabled; Edit stays available |
| Provider or control action hangs | Tile scripts run in their own runspace, never on the dispatch thread; each invocation has a stop deadline (`PowerShell.Stop`) and the tile shows `Busy` until then |
| Saved source does not parse | The editor shows the parse errors; the last version that parsed keeps running; nothing reloads |
| A view's script fails to load | Navigating to it opens its error page with Edit and Back; the rest of the host is unaffected |
| Start's own script is broken | The host keeps the last-known-good Start, so there is always a working root |
| Event storm | Coalesced per tile; at most one face application in flight per tile |

### The tile is the app

A tile is not a shortcut to an app; it can be the whole app. Open shows the
same tile script at full size (more span, more controls, more of the queue),
not a separate application. Small, Wide, Large and full screen are sizes of
one script. A conventional app view is only needed when the content does not
fit the tile model.

Typography follows the Segoe UI type ramp in the "Guidelines for fonts"
section of the Windows 8.1 design guidelines (May 2014):

| Use | Size and weight |
| --- | --- |
| Prominent one- or two-word elements (a live value, a page title) | 42 pt Light |
| Single-line text that must draw attention | 20 pt Light, or 16 pt Semilight; never both on one page |
| Most text | 11 pt Semilight |
| Shortest elements (captions, control labels), the smallest size | 9 pt Regular |

Point sizes convert to the platform's device-independent unit when the
renderer is implemented; line heights and colours come from the same section's
ramp table, read at that time.

### Editing is designing

The Edit page shows the tile's source beside a live preview of that tile at
each size it supports. Every edit that parses re-renders the preview from the
edited script (faces, controls, knobs); an edit that does not parse shows its
errors and leaves the preview unchanged. Save applies the script to the real
tile. Widgets are therefore designed from Start itself, previewed as live tiles
before they are pinned.

### Endpoint tiles and zone rules

A tile may serve something on a port (a page, speech, the camera, accelerator
access, a command pipe). A command endpoint is remote code execution into the
hosted runspace, so endpoint tiles follow two independent gates. The rules are
taken from the owner's `subsystem` repository at commit `2c8dd804`
(`src/runspace/Host/Firewall.cs`); the logic is restated here, not its code.

- Bind gate (what may bind): loopback only, unless the endpoint uses TLS and
  authenticates every client.
- Connection gate (who may connect, per network zone), default-deny and
  fail-closed. Trust order: Mobile < WifiPublic < WifiPrivate < Usb < Loopback.
  Loopback and Usb are allowed. WifiPrivate is allowed only by an opt-in rule
  for a trusted network. WifiPublic is denied unless an explicit rule allows
  it. Mobile is denied unless a separate, warned acknowledgment is set. Anything
  that cannot be classified is Unknown and denied.
- Clients authenticate with a pairing token issued by the device and shown on
  the tile. A command endpoint exposes declared commands with typed parameters,
  not raw script text; a full runspace over the pipe is a separate opt-in.
- The tile face shows the exposure (zone allowed, paired clients) and the
  listener stops when the tile stops. Zone denials and failed authentication are
  logged and shown on the tile, never silently dropped from view.

## 7. Native mapping (Windows)

Header facts below come from Windows SDK 10.0.26100.0
(`dcomp.h` SHA-256 prefix `09539255B912F107`, `dcompanimation.h` prefix
`D16F3380C778FAD9`). Vtable slot numbers are derived from header declaration
order at implementation time and recorded in the ABI block, as `AGENTS.md`
requires.

| Need | API | Header |
| --- | --- | --- |
| Face surface | `IDCompositionDevice::CreateSurface`, `IDCompositionSurface::BeginDraw`/`EndDraw` | `dcomp.h:278`, `:1240`, `:1247` |
| 3D rotation | `CreateRotateTransform3D`, applied with `IDCompositionVisual::SetEffect` | `dcomp.h:350`, `:459` |
| Hide the back of a face | `SetBackFaceVisibility` | `dcomp.h:1537` |
| Keyframes, repeat, stagger | `IDCompositionAnimation::AddCubic`, `AddRepeat`, `SetAbsoluteBeginTime`, `End`, `Reset` | `dcompanimation.h:97-120` |
| Text and shapes in a face | Direct2D/DirectWrite (`src/D2D.Windows.ps1`) | |
| Software rasterization | WARP device through `src/D3D11.Windows.ps1` | rasterizer only, not a scheduler |

Visual tree: root, grid (scroll offset), one visual per tile (clip to tile
rect), and inside it a Front and a Back visual, each with its own surface and
3D transform.

## 8. Verification

- Pure: layout and reflow for widths 412, 915 and 1280 DIP; tile pixel size
  identical in all three; order preserved across resize; size cycling.
- Pure: an unchanged provider result produces no rasterization request.
- Pure: queue rules (sixth face evicts the oldest; a tagged face replaces its
  tag in place; queue order is the cycle order).
- Pure: semantic tree. Reading order equals reflow order at all three widths;
  `Move` from every tile in every direction lands on the expected tile or stays
  put at an edge; `Invoke` through the tree produces the same launch as a tap.
- Pure: navigation. The cycle Start -> console tile -> `desktop` -> desktop
  Start tile -> console tile, repeated 1000 times, leaves the same view count
  and a back stack no deeper than the number of distinct views.
- Failure paths, one test each: throwing provider, hanging provider stopped at
  its deadline, unparseable save keeping the previous version, broken view
  script, broken Start falling back to last-known-good, event storm coalescing.
- Native, bounded `-Verify`: create the device on WARP, build a scene with one
  live tile, rasterize both faces, read back each face through a WIC bitmap
  render target and compare against recorded hashes; confirm the FlipCycle
  animation object was built with the expected segment count. No message loop.
- Measured, before any performance claim: PowerShell invocations while idle
  (target 0), input-to-visible-change latency, and presentation statistics
  from the documented tracing path.
- Human proof: a gallery applet with a few live tiles bound to real scripts.

## 9. Not in scope here

Android counterparts (`AGENTS.md` §3), remote control or session products, and
any frame-oriented API. Platform translation notes are recorded when the
Windows contract is stable, not before.

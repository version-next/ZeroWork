# Zenit UI Framework Core Development Guide

> Last updated: 2026-03-20 | This document describes the current core architecture.
>
> This document covers the design decisions and usage rules of 10 core subsystems.
> All example code reflects the current implementation in `src/ui/core/` and `src/ui/recipe.zig`.

---

## Table of Contents

1. [Style Layered Storage](#1-style-layered-storage)
2. [Style Bitfield Dirty Flags](#2-style-bitfield-dirty-flags)
3. [Relative Coordinate System](#3-relative-coordinate-system)
4. [Layout Islands](#4-layout-islands)
5. [Declarative Transition](#5-declarative-transition)
6. [Dirty Flag Bubbling System](#6-dirty-flag-bubbling-system)
7. [Recipe Styling System](#7-recipe-styling-system)
8. [Per-Corner Radii](#8-per-corner-radii)
9. [Text Style Inheritance](#9-text-style-inheritance)
10. [Overflow Fade Gradient Mask](#10-overflow-fade-gradient-mask)

---

## 1. Style Layered Storage

### Design Motivation

A node's `Style` contains 40+ fields, but most nodes only use a handful of high-frequency fields such as background/padding/width/height. Low-frequency fields such as shadow/gradient/grid/inset waste ~120 bytes per node.

### Architecture

```
Style (inline, ~100 bytes)         StyleExt (allocated on demand, ~200 bytes)
┌─────────────────────────┐      ┌──────────────────────────┐
│ background, border      │      │ shadow, gradient, outline│
│ padding, margin         │      │ corner_radius            │
│ direction, justify      │      │ scale_x, scale_y         │
│ align_items, gap        │      │ flex_basis, align_self    │
│ width, height           │      │ inset, sticky_insets     │
│ flex, flex_shrink       │      │ z_index, tab_index       │
│ translate_x, translate_y│      │ aspect_ratio             │
│ overflow, overflow_hidden│     │ grid, grid_placement     │
│ opacity, position       │      │ min/max_width/height     │
│ cursor, layout_isolation│      │ flex_wrap                │
│ ext: ?*StyleExt ────────┼─────→│ hit_shape, clip_shape    │
└─────────────────────────┘      │ hit_behavior, hit_roles  │
                                  │ overflow_fade            │
                                  │ text_color, text_font_*  │
                                  └──────────────────────────┘
```

Most nodes have `ext == null`, which saves ~60% memory.

### Reading Rules

Low-frequency fields are read through accessor methods on Style (inlined by the compiler, zero cost):

```zig
// ✅ Correct — accessor method call
const s = node.style.shadow();        // returns ?Shadow
const z = node.style.z_index();       // returns i16 (default 0)
const ar = node.style.aspect_ratio(); // returns f32 (default 0)
if (node.style.grid()) |gc| { ... }

// ❌ Wrong — these fields are no longer on the Style struct
// node.style.shadow  → compile error "no field named 'shadow'"
// node.style.z_index → compile error
```

High-frequency fields are still plain field accesses (**no parentheses**):

```zig
// ✅ High-frequency fields — direct access
node.style.background = Color.hex(0xff0000);
node.style.opacity = 0.5;
const w = node.style.width;
const pad = node.style.padding;
```

### Writing Rules

Writing low-frequency fields requires `ensureExtFallible(allocator)` (returns
`error.OutOfMemory` if the ext block cannot be allocated; `ensureExtPanic` exists only for
ratcheted legacy call sites):

```zig
// ✅ Correct — allocate via ensureExtFallible, then write
(try node.style.ensureExtFallible(allocator)).shadow = .{ .blur = 8 };
(try node.style.ensureExtFallible(allocator)).z_index = 10;

// ✅ Batched writes (single allocation)
const ext = try node.style.ensureExtFallible(allocator);
ext.shadow = t.shadow.md;
ext.z_index = 10;
ext.corner_radius = .{ .all = 8 };

// ✅ Reset to defaults (if ext is not allocated, defaults already apply)
if (node.style.ext) |ext| ext.aspect_ratio = 0;
```

### Box Initialization

`ui.box(cx, style, children)` takes a `BoxStyle`, which carries the ext fields too
(`shadow`, `z_index`, `corner_radius`, …); the builder allocates the ext block when a declared
field needs it:

```zig
const node = try ui.box(cx, .{
    .width = .{ .px = 200 },
    .background = t.color.bg_secondary,
    .padding = Padding.all(12),
    .shadow = t.shadow.md,
    .z_index = 10,
    .corner_radius = 8,
}, .{});
```

Application code builds UI with `ui.view` instead; the node-level builder is for widget
implementations and tests.

### destroy Cleanup

`Node.destroy()` automatically frees `style.ext` (including the internal `grid` pointer). No manual cleanup is needed.

### Compile-Time Guarantee

```zig
comptime {
    if (@sizeOf(Style) > 128) @compileError("Style too large");
}
```

Check this limit before adding new high-frequency fields.

---

## 2. Style Bitfield Dirty Flags

### Design Motivation

Manually calling `markLayoutDirty()` / `markRenderDirty()` is error-prone (it is easy to pick the wrong level). `setStyle` selects the correct dirty level automatically at compile time.

### API

```zig
// Single-field set — the dirty level is decided at compile time
node.setStyle(allocator, .background, Color.hex(0xff0000));  // → markRenderDirty
node.setStyle(allocator, .width, .{ .px = 200 });            // → markSizingDirty
node.setStyle(allocator, .padding, Padding.all(10));          // → markLayoutDirty
node.setStyle(null, .cursor, .pointer);                       // → no dirtying

// Convenience methods
node.setBorderColor(color);  // → markRenderDirty
node.setBorderWidth(2.0);    // → markLayoutDirty
```

### The allocator Parameter

- High-frequency fields (background, padding, ...): the allocator is never used, passing `null` is fine
- Low-frequency fields (shadow, z_index, ...): **a valid allocator must be passed**, otherwise the write is silently skipped
- When in doubt, passing `cx.allocator` is always safe

### Dirty Level Classification

| Level | Fields |
|------|------|
| **sizing** | width, height |
| **layout** | padding, margin, direction, justify, align_items, gap, flex, flex_shrink, flex_basis, flex_wrap, overflow, position, aspect_ratio, grid, grid_placement, min/max_width/height, align_self, sticky_insets, inset |
| **interaction** | border, opacity, translate_x/y, scale_x/y, corner_radius, overflow_hidden, z_index, hit_shape, clip_shape, hit_behavior, hit_roles |
| **render** | background, shadow, gradient, outline, overflow_fade, text_color, text_font_size, text_font_weight |
| **none** | cursor, tab_index, layout_isolation |

### Overlay Intercepting Pointers

By default only nodes that **carry interaction themselves** (focusable / on_click / on_hover / on_event / drop target / button / input) participate in pointer hit testing; purely visual containers (panel backgrounds, island shells, glass bars) are `pass_through`, and clicking their empty area falls through to the sibling nodes underneath.

To make an "overlay + full-window base" layout also intercept pointers on the overlay's empty area, set a single field on the **overlay root node**:

```zig
(try island.style.ensureExtFallible(allocator)).hit_behavior = .@"opaque";
```

Intercepting behaviors (`.@"opaque"` / `.self_only` / `.self_and_children`) **implicitly imply `hit_roles.pointer = true`**, so you do not need to configure a `hit_roles` copy by hand.

**Precedence**: `hit_roles` is a `HitRolesOverride`, **tri-state per role**, where `null` means "keep the framework-derived default". To add just one role, write only that one:

```zig
ext.hit_roles = .{ .pointer = true };   // scroll/inspect keep their derived defaults
```

A role written explicitly overrides the implicit derivation from `hit_behavior`: when both `hit_roles = .{ .pointer = false }` and `hit_behavior = .@"opaque"` are set, the node still passes through.

> `HitRoles` (a plain bool struct) is deliberately not reused here: with it, writing `.{ .pointer = true }` would also take over every unmentioned field such as `scroll`/`inspect` at its field default, and since `inspect` defaults to `true` it would silently become `false` ⇒ the node could no longer be selected in devtools. The tri-state makes "override only the one role I wrote" an expressible intent.

The substructure is unchanged: existing controls inside an island are still hit first, and `hit_shape` (rounded/circle/path) still decides precisely.

### Hover Under a Stationary Pointer

Hover is a function of the pointer position **and** the scene under it. When the scene changes while the pointer rests — wheel, trackpad momentum or spring scroll, `setScrollY` / `scrollRectIntoView`, nested ScrollAreas carrying their content, layout reflow, mount/unmount, `hit_behavior` changes — hover moves to the node now under the pointer without waiting for the next mouse move.

This matches the platforms. Measured with an AppKit probe (row views with `NSTrackingArea`, cursor never moved): after an `NSScrollView` scroll, programmatic or wheel, the row that left gets `mouseExited:` and the row that arrived gets `mouseEntered:` within ~1.5 ms of the bounds change, before the next display; a frame change without scrolling, and a window moving away from the cursor, are re-evaluated on the next display cycle (~16 ms). Browsers re-hit the pointer after scroll/layout at the next frame and update `:hover`, `mouseover`/`mouseout` without dispatching `mousemove`.

Mechanism (`core/cx_hover.zig`):

- The committed hit scene carries `HitRuntime.scene_epoch`, bumped by every full or partial rebuild and every in-place move (translate or layout placement, see "Hit Index Follows Layout Output"); hit-layer motion (scroll offset) folds in through `g_hit_layer_motion_gen`. Anything that changes what a fixed point resolves to advances it.
- Every hover resolution (pointer move, capture-release resync, re-resolution) records the epoch it used.
- At the start of each rendered frame, if the epoch moved and the pointer is live, the pointer is hit-tested **once** against the committed scene (the geometry on screen) and hover transitions are dispatched exactly as a move to the same point would: `mouse_leave` / `on_leave` up the old path, `mouse_enter` / `on_hover` down the new one. No `mouse_move` is dispatched; the cursor shape follows. Frames with an unchanged scene do no hit test; a pending re-resolution keeps `wantsFrame()` true until it runs.
- Event-driven and programmatic changes (wheel, `setScrollY`, a handler mutating the tree) are resolved in the frame that first shows them; changes made by before-render hooks (spring/momentum ticks) in the following frame, like a browser.

Re-resolution is skipped while the position is not live (`Cx.pointerLive()`), and deferred (not dropped) while a pointer sequence owns the pointer:

| Condition | Behavior |
|---|---|
| Pointer capture held (drag, scrollbar thumb, slider) or a left press in progress | Hover stays on the sequence; the release (or `cancelPointerInteractions`) ends it and the next frame re-resolves. Same as AppKit tracking areas without `NSTrackingEnabledDuringMouseDrag`. |
| Pointer outside the content (a drag or release can report outside positions) | No re-resolution. |
| Platform reported `pointer_left`: the pointer left the window **or another window now covers it** (macOS content tracking-area exit / window server top window, Windows `WM_MOUSELEAVE`, Wayland `wl_pointer.leave`) | Hover is cleared at once (`Cx.handlePointerLeave`), nothing re-resolves until the next pointer event. When the covering window goes away the platform re-delivers the resting position as a move, which hovers again. |
| Platform drag-and-drop session over the window | No re-resolution until the session exits or drops. |
| Window inactive (`cx.window_active == false`) | **Not** a condition: hover keeps tracking and re-resolving, as on every platform (below). Only the cursor shape is key-window-only on macOS. |

#### Pointer presence per platform

Liveness is the platform's report that the pointer is over the window's *visible* content, independent of activation. A position alone cannot decide it: macOS `mouseLocationOutsideOfEventStream` keeps reporting the in-content point while another application's window covers it.

Measured on macOS 26.4 with `tools/macos_hover_probe.swift` (`bash scripts/macos_hover_probe.sh`; the cursor never moves, a second process covers and uncovers it, takes activation, and windows/content are moved under it; runs where the cursor moved are discarded):

| Under the resting cursor | `activeAlways` area | `activeInActiveApp` / `activeInKeyWindow` | Latency |
|---|---|---|---|
| Another app's floating panel ordered over it (we stay active) | exit | exit | 8.3-9.2 ms |
| That panel moved away | enter | enter | 6.0-6.5 ms |
| Click-through panel (`ignoresMouseEvents`) over it | nothing | nothing | `windowNumberAtPoint` also still names our window |
| Our own other window ordered over / out | exit / enter | exit / enter | 11-19 ms / ~280 ms |
| NSScrollView scrolled programmatically | exit old row, enter new row | same | 0.3 ms |
| Another app activated (pointer still over us) | nothing | exit | 9-23 ms |
| While inactive: scroll, view moved under it, panel over / away, window moved away / back | exit / enter | nothing | 0.3 ms, 17-30 ms, 6.3 / 6.2 ms, 3-16 / 6-20 ms |
| Reactivated | nothing | enter | 17-31 ms |

Tracking-area options of standard AppKit views (same probe): `NSButton` with `showsBorderOnlyWhileMouseInside` (the hover-bordered button), the title-bar window buttons (`_NSThemeZoomWidgetCell`, hover glyphs) and `NSTitlebarView` use **`activeAlways`**; text views install `cursorUpdate` areas with `activeInKeyWindow` (cursor only); `NSTableView`, `NSPopUpButton`, `NSSegmentedControl`, `NSSlider` install none (no hover); `WKWebView` tracks moves with `activeInKeyWindow` (web content hovers only in the key window). Zenit's hover affordances are controls, so it follows AppKit's controls: hover in inactive windows, cursor shape in the key window only.

- **macOS** (`native/macos/window_bridge.m`, "Pointer presence"): the content view has an `activeAlways | mouseEnteredAndExited | mouseMoved | inVisibleRect` tracking area (no `enabledDuringMouseDrag`). Presence is the window server's answer (top window at the pointer is ours, the point is in the content's visible rect; the fullscreen header counts), applied on tracking enter/exit, real moves, the release of the last button and a pump-boundary sample that may only *end* presence (right after a window moves away `windowNumberAtPoint` can still name it). While a button is held presence is frozen. Moves are delivered as hover positions only while present, in any window (key or not); a presence loss queues a leave marker in the ordered motion stream (SDK `pointer_left`), a regain without motion queues the resting position as a move. Live check: `bash scripts/test_native_pointer_presence.sh --live` (a window of the test ordered over the resting cursor: `pointer_left` 7-18 ms, removal: position again ~195-260 ms).
- **Windows**: Win32 sends `WM_MOUSEMOVE` to the window under the cursor whatever its activation, and by default (`SPI_GETMOUSEWHEELROUTING`, "Scroll inactive windows") the wheel too; `TrackMouseEvent(TME_LEAVE)` reports `WM_MOUSELEAVE` (SDK `pointer_left`). The acceptance batch measures this natively (`tools/windows_hover_probe.c`: inactive motion and wheel, a standard Explorer ListView scrolled inactive, leave when another process's window covers the resting cursor, motion when it moves away, leave after a captured drag released over another window, leave off the window) and checks Zenit against it with real input (`e2e/windows-hover-native.test.ts`).
- **Wayland**: pointer focus (`wl_pointer.enter/leave`) is separate from keyboard focus; motion and axis events reach an unfocused surface under the pointer. `ZENIT_WAYLAND_POINTER_TRACE=1` logs enter/leave/axis with the keyboard focus state; the Linux batch stage `hover-native` (`scripts/run_linux_hover_acceptance.py`) drives it with compositor-native input.

Components that hit-test `mouse_x` / `mouse_y` themselves (outside the hover dispatch) gate on `Cx.pointerLive()`; `Notifier` and `DateRangePicker` do.

Each window's `Cx` has its own scene epoch and pointer state, so windows re-resolve independently. Harness `/stats` reports `hover.test_id` (nearest test id on the hovered path) and the `reconcile_hit_tests` / `reconcile_changes` counters.

### Hit Index Follows Layout Output

The hit index (`HitRuntime`) stores geometry derived from rects: world matrices, node-sized proxies, clip entries. It must equal a full rebuild over the current tree after every commit, including for nodes the frame never marked. A layout pass moves such nodes all the time: an in-flow size change resizes its fit ancestors, and their parents re-center them, align them to the end or push their siblings (a dialog centered in a window whose body grows moves its header and footer, which nobody marked).

Invalidation therefore comes from **layout output**, not from a prediction of how far a change propagates:

- `node_lifecycle.setLayoutRect` is the one write entry for rects (layout engine and component placements alike). A write that changes a node's rect marks it (`node_dirty.markLayoutPlacementDirty`), with the same pending bits as a translate (`hit.translation` / `subtree_translation`).
- The commit after the layout pass (`cx_runtime_index.commitPendingTranslations`, at all three commit points: frame end, before-render tick, event-time refresh) reconciles each marked node against what the index holds: an unchanged placement (a rect written and written back within the pass) costs one comparison and walks nothing below; a pure move is moved in place (`HitRuntime.translateSubtree`); a hit layer that moved only advances the scene epoch (its space follows its live transform); a resize or callback-produced geometry falls back to that node's own partial rebuild.
- A partial rebuild root is the changed node itself. Nothing is raised to a parent or a layer to "cover reflowed siblings": they carry their own mark. Roots are rebuilt deepest first, so a layer rebuilt in the same commit reuses its freshly rebuilt blocks.
- A structurally changed subtree (runtime-dirty) and any full rebuild index from current geometry, and drop the marks inside them.

The contract for anything that places nodes: write rects through `setLayoutRect` (or the `setLayoutX/Y/W/H` helpers), never into the layout table directly. Translates go through `markTranslationDirty` (style setters do this), scroll offsets through `markHitLayerMotion`. `hit_translation_tests.zig` checks the incremental index against a full rebuild for random translates and for random flow-layout reflows.

---

## 3. Relative Coordinate System

### Design Motivation

In the old coordinate system `rect.x/y` were **absolute coordinates**. Every reverse layout pass then needed `offsetDescendants()` to recursively offset all descendants, O(D). When a parent moved, every child rect had to be updated.

### The New Coordinate System

`rect.x/y` are coordinates **relative to the parent's top-left corner**.

```
Old (absolute coords):           New (relative coords):
root.rect = (0, 0, 800, 600)     root.rect = (0, 0, 800, 600)
  child.rect = (10, 10, 100, 50) child.rect = (10, 10, 100, 50)  ← relative to root
    leaf.rect = (15, 15, 80, 30)    leaf.rect = (5, 5, 80, 30)   ← relative to child, not root!
```

### Areas Affected

**Layout engine** (`layout_engine.zig`):
- `layoutChildren`: child.rect.x = cursor + margin.left (does not add parent.rect.x)
- `layoutAbsoluteChild`: new_x = inset + margin (does not add parent.rect.x)
- `layoutChildrenGrid`: new_x = pad_left + cell_x + align_x (does not add parent.rect.x)
- `batchReverseChildren`: only rewrites the direct children's rects, **does not recurse into descendants**
- `offsetDescendants`: **deleted**

**Render/event layer**: child_offset accumulation now adds `node.rect.x`:
```zig
// render_engine.zig / event_dispatcher.zig / interaction_index.zig
const child_offset_x = offset_x + node.rect.x + translate_x + sticky_offset_x;
```

**Getting absolute coordinates**:
```zig
// Walk the ancestor chain and accumulate
const global = node.globalRect();  // → ComputedRect { .x, .y, .w, .h }
```

### Application-Layer Adaptation

`computeGlobalOffset()` has been updated to accumulate `n.rect.x`:

```zig
pub fn computeGlobalOffset(node: *const Node) struct { x: f32, y: f32 } {
    var tx: f32 = 0;
    var ty: f32 = 0;
    var cur: ?*const Node = node;
    while (cur) |n| {
        tx += n.rect.x + n.style.translate_x;  // ← now adds rect.x
        ty += n.rect.y + n.style.translate_y;
        cur = n.parent;
    }
    return .{ .x = tx, .y = ty };
}
```

### Performance Gains

- Eliminates `offsetDescendants` O(D), so a reverse layout pass drops from O(N+D) to O(N)
- Child rects stay unchanged when a parent moves, so fewer unnecessary layout_dirty

---

## 4. Layout Islands

### Design Motivation

While typing in the editor, layout changes inside the editing area bubbled up to root via `subtree_dirty` and triggered relayout checks in unrelated components such as the sidebar/statusbar.

### Usage

```zig
// Editor island — internal layout changes do not bubble upward
editor_container.style.layout_isolation = true;
// Requirement: width/height must not be .fit (otherwise internal changes really do affect the outer size)
```

### How It Works

`markLayoutDirty` / `markSizingDirty` / `markSubtreeDirty` stop bubbling when they reach an ancestor with `layout_isolation == true`:

```zig
while (p) |parent| {
    if (parent.subtree_dirty and parent.subtree_render_dirty) break;
    parent.subtree_dirty = true;
    parent.subtree_render_dirty = true;
    if (parent.style.layout_isolation) break;  // ← cut off here
    p = parent.parent;
}
```

**Note**: `markRenderDirty` is **not cut off** (render dirty flags must bubble all the way to the root to trigger a repaint).

### Debug Guard

```zig
// layout_engine.zig layoutNode()
if (node.style.layout_isolation) {
    std.debug.assert(node.style.width != .fit and node.style.height != .fit);
}
```

---

## 5. Declarative Transition

### Design Motivation

Animation currently relies on the `on_before_render` hook + manual ticking + markRenderDirty. The declarative API lets developers set only the target value while the framework interpolates automatically.

### API

**Option 1: per-field setup**
```zig
// 1. Configure the transition (once)
try node.enableImplicitAnimation(allocator, &.{.background}, .{ .duration_ms = 150, .easing = .ease_out_quad });
try node.enableImplicitAnimation(allocator, &.{.opacity}, .{ .duration_ms = 200 });

// 2. Set the target value (the framework interpolates from the current value automatically)
node.setBackground(new_color);  // transitions automatically
node.setOpacity(0.5);           // transitions automatically
```

**Option 2: CSS-style declarative (`applyTransition`)**: recommended
```zig
const recipe_mod = @import("ui").recipe;

// Parses the CSS transition string at comptime, zero runtime cost
try node.applyTransition(allocator,
    &comptime recipe_mod.transition("background 200ms ease-out, border-color 150ms linear"));

// The "all" keyword is supported (expands to 9 properties)
try node.applyTransition(allocator,
    &comptime recipe_mod.transition("all 150ms ease-out-quad"));
```

**transition() syntax**: `"property duration easing, ..."`; omitted values fall back to defaults (duration=150ms, easing=ease-out-quad)

**Supported property names**: `background` / `opacity` / `border-color` / `border-width` / `translate-x` / `translate-y` / `scale-x` / `scale-y` / `corner-radius` / `all`

**Supported easing**: `linear` / `ease-out-quad` / `ease-in-quad` / `ease-in-out-quad` / `ease-out-cubic` / `ease-in-cubic` / `ease-in-out-cubic` / `ease-out-expo` / `ease-in-expo` / `spring` / `bounce` and 25+ more

### How It Works

- `TransitionSlots` (at most 8 properties) is allocated on demand behind the `node.transitions` pointer
- Each frame `tickBeforeRender` runs `tickTransitions` before `on_before_render`
- Active transitions advance their progress, apply easing, update the style value, and markRenderDirty
- Once every transition finishes, `any_active = false`, so zero cost

### Supported Properties

`background`, `opacity`, `border_color`, `border_width`, `translate_x`, `translate_y`, `scale_x`, `scale_y`, `corner_radius`

### Coexistence with Existing Hooks

- If no transition is configured, `setBackground`/`setOpacity` set the value directly (equivalent to writing the style directly)
- The `on_before_render` hook still works and runs after the transition tick
- New components should use the transition API; legacy components migrate gradually

---

## 6. Dirty Flag Bubbling System

### Flag Types

| Flag | Trigger method | Effect |
|------|---------|------|
| `layout_dirty` | `markLayoutDirty()` | This node needs a full relayout |
| `subtree_dirty` | bubbles automatically | Somewhere in the subtree needs layout |
| `render_dirty` | `markRenderDirty()` | This node's render commands must be regenerated |
| `subtree_render_dirty` | bubbles automatically | Somewhere in the subtree needs re-rendering |
| `interaction_dirty` | `markInteractionDirty()` | The interaction index needs updating |
| `runtime_index_dirty` | `markRuntimeIndexDirty()` | The runtime index needs updating |
| `order_dirty` | `markOrderDirty()` | Focus/tab order must be recomputed |

### Bubbling Rules

```
markLayoutDirty:
  self: layout_dirty + subtree_dirty + render_dirty + subtree_render_dirty
  bubbles: ancestors get subtree_dirty + subtree_render_dirty
  stops: when layout_isolation == true

markSizingDirty:
  self + parent: layout_dirty + subtree_dirty + render_dirty + subtree_render_dirty
  bubbles: starting from the grandparent
  stops: when layout_isolation == true

markRenderDirty:
  self: render_dirty + subtree_render_dirty
  bubbles: ancestors get subtree_render_dirty
  stops: ❌ never stops (must reach the root to trigger a GPU repaint)

markSubtreeDirty:
  self: subtree_dirty + subtree_render_dirty (does not set layout_dirty)
  bubbles: ancestors get subtree_dirty + subtree_render_dirty
  stops: when layout_isolation == true
  purpose: VirtualList-style cases (children need relayout but the parent container itself does not)
```

### overflow_hidden Render Cache

The render commands of an `overflow_hidden` container can be cached. After layout_dirty you must:
```zig
node.invalidateRenderCache();  // free the old cache
node.markRenderDirty();        // trigger a repaint through bubbling
```

**Note**: never assign `subtree_render_dirty = true` directly (it does not bubble! use `markRenderDirty()`).

---

## Quick Reference Card

### Style Field Cheat Sheet

```
High-frequency (inline): background border padding direction justify align_items gap
                         width height flex flex_shrink translate_x translate_y
                         overflow overflow_hidden margin opacity position cursor
                         layout_isolation

Low-frequency (ext):     shadow gradient outline corner_radius scale_x scale_y
                         flex_basis align_self inset sticky_insets z_index tab_index
                         aspect_ratio grid grid_placement min_width max_width
                         min_height max_height flex_wrap hit_shape clip_shape
                         hit_behavior hit_roles overflow_fade
                         text_color text_font_size text_font_weight
```

### Common Operation Patterns

```zig
// Read a high-frequency field
color = node.style.background;

// Read a low-frequency field
if (node.style.shadow()) |s| { ... }

// Write a high-frequency field
node.style.background = new_color;
// or with automatic dirtying:
node.setStyle(null, .background, new_color);

// Write a low-frequency field
(try node.style.ensureExtFallible(allocator)).shadow = .{ .blur = 8 };
// or with automatic dirtying:
node.setStyle(allocator, .shadow, .{ .blur = 8 });

// Get absolute coordinates
const global = node.globalRect();

// Declare a transition (new recommended way)
try node.applyTransition(allocator,
    &comptime @import("ui").recipe.transition("background 150ms ease-out"));
node.setBackground(target_color);  // interpolates automatically

// Layout isolation
container.style.layout_isolation = true;  // width/height must not be .fit

// Text style inheritance
ext.text_color = Color.hex(0xff0000);  // descendant text nodes inherit automatically

// overflow fade
ext.overflow_fade = .{ .size = 32, .edges = .{ .left = true, .right = true } };
```

---

## 7. Recipe Styling System

### Design Motivation

Component styling faces an "interaction-state explosion" problem: every variant × every interaction state (normal/hover/pressed/focus/disabled) needs its own style definition. Managing this by hand produced a flood of `custom_bg` / `custom_hover_bg` fields.

### Architecture

The Recipe system takes its cues from Panda CSS and CVA and provides declarative style variants with zero compile-time cost:

```
src/ui/recipe.zig
┌─────────────────────────────────────────────────┐
│  Layer 1: StyleOverride                         │
│    all-optional style override (background/...) │
│    applyTo(Style) / merge() / isEmpty()         │
├─────────────────────────────────────────────────┤
│  Layer 2: ConditionalStyle                      │
│    five-state interaction style bundle          │
│    base / hover / active / focus / disabled     │
│    resolve(InteractionState) → StyleOverride    │
├─────────────────────────────────────────────────┤
│  Layer 3: recipe() — single-node recipe         │
│    base + variants + compound variants          │
│    resolve(VariantProps, tokens) → ConditionalStyle │
├─────────────────────────────────────────────────┤
│  Layer 4: slotRecipe() — multi-part recipe      │
│    one variant value yields all slot styles     │
├─────────────────────────────────────────────────┤
│  Layer 5: transition() — CSS transition parsing │
│    comptime parsing of "prop duration easing"   │
└─────────────────────────────────────────────────┘
```

### StyleOverride

A style override struct in which every field is optional, replacing the old pile of `custom_bg` / `custom_text_color` fields:

```zig
const StyleOverride = struct {
    background: ?Color = null,
    border_color: ?Color = null,
    border_width: ?f32 = null,
    text_color: ?Color = null,
    font_weight: ?u16 = null,
    corner_radius: ?CornerRadius = null,
    opacity: ?f32 = null,
    // ... more fields
};

// Usage
const style: StyleOverride = .{
    .background = Color.hex(0x007AFF),
    .text_color = Color.WHITE,
};
style.applyTo(&node.style, allocator);
```

### ConditionalStyle

A five-state interaction style bundle that merges into the final style based on `InteractionState`:

```zig
const cs = ConditionalStyle{
    .base = .{ .background = Color.hex(0x007AFF) },
    .hover = .{ .background = Color.hex(0x0066DD) },
    .active = .{ .background = Color.hex(0x0055BB) },
    .disabled = .{ .background = Color.hex(0xCCCCCC), .opacity = 0.5 },
};

// Merge precedence: base ← hover ← active ← focus ← disabled
// disabled is mutually exclusive with the other interaction states
const resolved = cs.resolve(.{ .is_hovered = true });
```

### recipe(): Single-Node Recipe

A compile-time factory, the counterpart of CVA's `cva()`:

```zig
const button_recipe = recipe(.{
    .base = .{ .padding = Padding.symmetric(12, 24) },
    .variants = .{
        .variant = .{
            .primary = .{ .base = .{ .background = tokens.accent } },
            .ghost = .{ .base = .{ .background = Color.TRANSPARENT } },
        },
        .size = .{
            .sm = .{ .base = .{ .height = 28 } },
            .md = .{ .base = .{ .height = 36 } },
        },
    },
    .compounds = &.{
        .{ .variant = .ghost, .size = .sm, .style = .{ ... } },
    },
});

// resolve algorithm: merge(base, variants[dim][val], matchedCompounds...)
const cs = button_recipe.resolve(.{ .variant = .primary, .size = .md }, tokens);
```

### Migration Guide

```zig
// ❌ Old API (deprecated)
Button(.{
    .custom_bg = Color.RED,
    .custom_hover_bg = Color.DARK_RED,
    .custom_text_color = Color.WHITE,
    .font_weight = 600,
})

// ✅ New API — StyleOverride
Button(.{
    .style = .{
        .background = Color.RED,
        .text_color = Color.WHITE,
        .font_weight = 600,
    },
    .hover_style = .{ .background = Color.DARK_RED },
})
```

### File Locations

| File | Contents |
|------|------|
| `src/ui/recipe.zig` | Core implementation (StyleOverride / ConditionalStyle / recipe / slotRecipe / transition) |
| `src/ui/core/types.zig` | Type definitions for StyleOverride / InteractionState |
| `src/ui/core.zig` | Exports recipe / ConditionalStyle / StyleOverride / transition |

---

## 8. Per-Corner Radii

### Design Motivation

The Group component needs middle items to clear their left/right radii and the first/last items to keep only one side rounded; a scalar `radius: f32` cannot express that.

### Architecture

Upgraded from a scalar to a per-corner array `[4]f32` (TL, TR, BR, BL order):

```
Types layer (types.zig)
  CornerRadius.resolve4() → [4]f32
  Style.effectiveRadii() → [4]f32

Render command layer (render_command.zig)
  every command carrying a radius: radius: [4]f32

Command encoder (command_encoder.zig)
  SDFInstance.corner_radii: [4]f32

GPU shader (sdf_primitives.metal)
  corner_radii: float4
  sdf_rounded_rect_4(p, size, radii) — selects the radius per quadrant
```

### The CornerRadius Type

```zig
pub const CornerRadius = union(enum) {
    all: f32,              // same radius on all four corners
    each: [4]f32,          // [TL, TR, BR, BL]

    pub fn resolve4(self) [4]f32;  // unified output
};

// Usage
ext.corner_radius = .{ .all = 8 };
ext.corner_radius = .{ .each = .{ 8, 8, 0, 0 } };  // keep only the top corners rounded
```

### GPU Shader

`sdf_rounded_rect_4()` picks the matching corner radius based on the quadrant of the rectangle the fragment lies in:

```metal
fn sdf_rounded_rect_4(p: float2, half_size: float2, radii: float4) -> float {
    // radii: (TL, TR, BR, BL)
    // pick the radius of the quadrant implied by the sign of p
    float r = select(select(radii.w, radii.z, p.y < 0), select(radii.x, radii.y, p.y < 0), p.x > 0);
    float2 q = abs(p) - half_size + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}
```

### Instance Data Changes

`SDFInstance` grew from 112 bytes to 128 bytes (float4 alignment):
- `corner_radius: f32` becomes `corner_radii: [4]f32`
- All `addRounded*` API signatures updated to `radius: [4]f32`

### Normalisation

Every consumer of a radius (SDF fill, `pushClip`, image-pipeline instances for images, opacity
folds, rounded-clip layers and retained composites, the blend composite) calls one function,
`src/render/corner_radii.zig` `normalize(radii, w, h)`, with the size of the rect the shape is
evaluated over: negative / NaN radii become 0 and **each corner is capped at half the shorter
side** independently. This is not CSS's proportional scaling of all four corners when adjacent
radii overflow a side; a pill written as `corner_radius = 9999` (or +inf) means "fully round" and
no longer turns composite masks inside out.

The glass material follows the same rule. `begin_blur_layer` carries the owner's four raw radii
(no scalar, no sentinel: the values its overflow clip and hit shape read), and
`backdrop_blur.shapeRadii` fits them to the rect each glass consumer evaluates: the glass shader's
world rect (`GlassUniforms.corner_radii`, with `corner_radius` = the largest corner), the material
veil's draw rect, the blur-only composite quad, and the D3D11 glass geometry
(`windows_paint`). Both glass shader paths draw per-corner silhouettes. GlassGroup members carry one
radius, fitted to the member's final rect after `glassEffectUnion` merges. Shape models with a single
radius (the popover silhouette with its arrow, the tab lens) resolve a non-uniform request to the
largest fitted corner (`corner_radii.normalizeUniform`), and GlassBox writes that same uniform radius
to its surface, content clip and root (hit / shadow shape). Regression fixture: the glass rows of
*Regressions → Per-corner clip*.

### Per-corner clipping

`overflow_hidden` content is clipped to the node's own corner shape, per corner:

- `ClipShapeSpec` (`ui.ClipShapeSpec`, set via `clip_shape`) has `.rounded_corners: [4]f32`
  next to `.rounded_rect: f32`. The default `.auto` resolves a non-uniform `corner_radius` to
  `.rounded_corners` (matching the hit shape: `HitShapeSpec.rounded_corners`), so an attached
  Group item (rounded outer corners, square inner ones) clips and hit-tests with the same four
  radii. The padding-box inner radius of each corner subtracts that corner's adjacent border
  widths.
- The radii travel through the display list, property tree and layer tree (`push_clip`,
  `begin_rounded_clip`, `begin_opacity_layer` folds, `apply_clip` carry `[4]f32`); flips and
  quarter turns re-index them (`Transform2D.orientCornerRadii`). The shared shader clip header has
  `clip_radii: float4`, and `ImageInstance` carries corner radii so layer composites mask per
  corner.
- **Nested shape clips intersect.** Each pipeline evaluates a single shape clip, so the encoder
  (`pushClipCommand`) keeps the effective clip exact: a shape that contains the other keeps the
  inner one (or keeps the outer one and only narrows the rect clip), same-rect rounded rects merge
  per corner (max radius), and shapes that genuinely cross open an isolation layer: an offscreen
  surface over the clip rect where the new shape is the only shape clip, composited back under
  the active one. Depth is unbounded; `pop_clip` closes the layer. Crossing clips therefore cost
  one offscreen pass per level.
- Regression fixture: storybook *Regressions → Per-corner clip* (shader clip, opacity fold, blend
  composite, clip layer, nested / crossing / oversized-radius specimens), asserted by e2e corner
  pixels.

---

## 9. Text Style Inheritance

### Design Motivation

A component container needs to control the color/font size/weight of every text node in its subtree uniformly, instead of configuring each text node by hand.

### Mechanism

StyleExt gains three inheritable properties:

```zig
// New StyleExt fields
text_color: ?Color = null,
text_font_size: ?f32 = null,
text_font_weight: ?u16 = null,
```

Node exposes inheritance resolution methods:

```zig
pub const InheritedTextStyle = struct {
    color: ?Color = null,
    font_size: ?f32 = null,
    font_weight: ?u16 = null,
};

// Walk the parent chain and pick up the nearest ancestor that sets a value
node.resolveInheritedTextStyle() -> InheritedTextStyle
node.resolveTextColor() -> ?Color       // shortcut
node.resolveTextFontSize() -> ?f32
node.resolveTextFontWeight() -> ?u16
```

### Resolution (CSS inheritance)

`Node.resolveTextProps()` (`src/ui/core/node_inherit.zig`) is the single resolution that layout
(`layout_engine.zig`, intrinsic measurement) and paint (`render_engine/text_render.zig`) both read;
never use `getText()`'s raw size / weight / color for either. Per property:

1. the text node's own `StyleExt.text_*` value, if set;
2. otherwise the text's own `TextProps` value if the text **declared** it
   (`color_set` / `font_size_set` / `font_weight_set`);
3. otherwise the nearest ancestor's `text_color` / `text_font_size` / `text_font_weight`;
4. otherwise the `TextProps` default.

Declared means written by the text's style: `ui.css` fields, a style literal, `typography`, or the
fields of a partial `styleBy` struct count one by one; a whole `TextStyle` value (style function,
value, `styleBy` returning `TextStyle`) declares all three. So a label that sets only its size
still inherits its control's weight and color.

When an inheritable value changes, `node.markInheritedTextDirty(.{ .color = …, .metrics = … })`
marks the readers: a size / weight change re-measures every text that resolves it (unless the text
declares both itself), a color change repaints texts, `currentColor` icons / images and canvases
that read `DrawContext.current_color`. Theme replay and style-host writes (`setStyleInline`, view
styles) call it for you; code that writes `StyleExt.text_*` directly must call it itself.

### Use Cases

```zig
// Button container sets the text color → every text inside that does not declare its own
// color inherits it
const ext = try button_root.style.ensureExtFallible(allocator);
ext.text_color = Color.WHITE;
button_root.markInheritedTextDirty(.{ .color = true });

// Switch the text color for the disabled state
ext.text_color = if (disabled) tokens.color.text_disabled else tokens.color.text_primary;
```

---

## 10. Overflow Fade Gradient Mask

### Design Motivation

When Input text scrolls horizontally, the hard clip at the content edges looks bad. We need to render a gradient mask from solid color to transparency along the edges of an overflow_hidden container.

### Configuration

```zig
pub const OverflowFade = struct {
    size: f32 = 32,          // size of the gradient region (px)
    color: ?Color = null,    // solid end (null = take the container background automatically)
    edges: FadeEdges = .{},  // enabled edges
};

pub const FadeEdges = struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,
};
```

### Usage

```zig
const ext = try container.style.ensureExtFallible(allocator);
ext.overflow_fade = .{
    .size = 32,
    .edges = .{ .left = true, .right = true },
};
```

### Render Implementation

`renderOverflowFade()` in `render_engine/text_render.zig` runs after an overflow_hidden container finishes rendering:
1. Computes the content bounds (including translate and negative padding)
2. Detects, per edge, whether the content overflows
3. Renders a gradient rect on overflowing edges (from the container background color to transparent)
4. Controls all four directions independently

### Use Cases

- **Input**: fades out left and right while the text scrolls horizontally
- **Textarea**: fades out the top while scrolling vertically

---

## 11. Key Capture and Declarative Focus

Design and edge cases: [`FOCUS_AND_KEY_CAPTURE_DESIGN.md`](FOCUS_AND_KEY_CAPTURE_DESIGN.md).

- **Capture-phase keys** (`ui.view` `.on_key_down_capture` / `.on_key_up_capture`, Yix `onKeyDownCapture`):
  installed in the node's `on_event_capture` slot, so they run root → focused node before the
  target and bubble phases. The container does not need to be focusable; with nothing focused,
  keys target the window's content root, so window shortcuts belong on the template root.
  `KeyPress.stop()` ends propagation, `consume()` only prevents the default. Keys routed while the
  focused text input composes (`KeyEvent.composing`) skip them.
- **Declarative focus** (`Cx.focus_targets`, `src/ui/focus_targets.zig`): `.focus_id` names a
  target, `.auto_focus` focuses it once ready, `.focus_request` (a `ui.view.FocusRequest` source)
  lets a view-model focus a target by id inside the element, `.focus_restore` puts focus back on the
  same id after a remount. Pending items are retried by `Cx.settlePendingFocus` at the start of
  `Cx.render`; any focus transition after an item was recorded cancels it (last writer wins, by
  `FocusManager.transition_epoch`). `FocusManager.observer` reports committed transitions and silent
  losses (`abandonFocus`, `unregisterFocusableSilent`); the subtree invalidation path reports through
  `FocusTargets.noteRemoved` / `sealLoss`. Imperative `cx.setFocus` is unchanged.

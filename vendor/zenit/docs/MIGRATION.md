# Migration notes

zenit is pre-1.0 and breaking changes happen. This file lists them in
reverse chronological order so consumers can see what to fix when bumping.

> Which APIs are frozen for v1.0 vs. still fair game: see
> [`docs/API_STABILITY.md`](API_STABILITY.md).

## How to add an entry

When you land a breaking change, prepend a section here with:

- the date and a one-line summary ending in `(BREAKING)`
- **what changed**: the old shape and the new shape
- **why**: enough that a consumer can tell whether it affects them
- a mechanical migration snippet (before / after code), not prose

`CONTRIBUTING.md` makes this part of the PR checklist for any change that
alters a public symbol.

---

<a id="text-line-clamp-ellipsis"></a>

## 2026-11-16: `text_overflow` marks multi-line text; newline-only text honours `max_lines`

No API is added or removed; defaults are unchanged (`text_overflow = .clip`). Behaviour changes
for text that already set these fields (design: `docs/design/text-line-clamp-ellipsis.md`):

- **Native, `wrap != .none` and `text_overflow = .ellipsis / .ellipsis_smart`**: the last visible
  line of text cut short by `max_lines` now ends in "…", and any line wider than the box (an
  unbreakable word, a long newline-only row) ends in "…". Before, `text_overflow` did nothing on
  multi-line text and the cut had no mark.
- **Web host, same combination**: the text stays multi-line (`white-space: pre-wrap`, or `pre`
  for newline-only) with `-webkit-line-clamp`; before, an ellipsis forced it onto one line.
- **`wrap = .newline_only` + `max_lines > 0`**: native now keeps at most `max_lines` rows (it
  ignored the limit; the Web host already clamped).
- **Web host, `wrap = .none` + `max_lines > 0`**: no `-webkit-line-clamp` / `-webkit-box` any
  more (a single line has one row; native ignored `max_lines` there already).
- **Soft wraps** in `break_all` / `char` no longer start a line with the space or tab they broke
  at (every width-wrapping mode now skips them, as CSS `pre-wrap`).
- **Tooltip**: a label longer than three lines ends its third line in "…".

Migration: nothing to change to get the new behaviour. To keep a silent cut, leave
`text_overflow = .clip`; to show more rows, raise `max_lines`:

```zig
// Before: wrapped text, max 2 rows, and an ellipsis that had no effect natively.
.{ .wrap = .word, .max_lines = 2, .text_overflow = .ellipsis }
// After: the same props show "…" at the end of row 2 when the text continues.
// For the old silent cut:
.{ .wrap = .word, .max_lines = 2, .text_overflow = .clip }
```

Known difference: on the Web host, `-webkit-line-clamp` shows an ellipsis even for `.clip`
(browsers have no clamp without one); native `.clip` shows none.

---

<a id="text-layout-unbounded-lines"></a>

## 2026-11-16: TextLayout keeps every line; lines are read through `lines()` (BREAKING)

**What changed.** A text node's layout used to stop at 1024 lines
(`text_layout.MAX_LINES`): longer text was neither laid out nor painted. The
cap is gone (docs/design/streaming-content.md §5.9):

- `TextLayout.lines` (a fixed `[1024]LineInfo` field) is now the method
  `lines() []const LineInfo`; `line_count` is `u32` (was `u16`);
  `TextLayoutBlob.line_count` is `u32`. `MAX_LINES` is removed.
- A `TextLayout` value is a borrow: lines beyond the inline capacity live in
  storage owned by whoever owns the layout (the node's layout output) and are
  valid until that node is laid out again. Keep a copy with `assign` into a
  `TextLayout` you own, release it with `deinitStorage`.

**Why.** Long code blocks, logs and documents were truncated at line 1024.
Reading through `lines()` is what makes the variable-length table possible;
the field rename turns any direct read into a compile error instead of a
silent truncation.

```zig
// Before
for (layout.lines[0..layout.line_count]) |line| use(line);
const count: u16 = layout.line_count;

// After
for (layout.lines()) |line| use(line);
const count: u32 = layout.line_count;
// Keeping a node's layout past its next layout:
var kept: ui.TextLayout = .{};
defer kept.deinitStorage(allocator);
try kept.assign(allocator, node.layoutTextLayout().?);
```

---

<a id="overlay-within-area"></a>

## 2026-11-16: Modal `center_in` replaced by `within`; overlay anchors move to overlay_stack (BREAKING)

**What changed.** `ModalProps.center_in: Source(?ComputedRect)` and `center_in_margin: f32` are
replaced by `within: Source(?overlay_stack.Anchor)` (a node, followed on every layout and tracked
by identity, or a `VirtualAnchor`) and `within_padding: Source(f32) = 8`. The dialog is centred in
the area and bounded by it (width / height at most the area less the padding). `ConfirmDialog`
takes both. `Anchor` / `VirtualAnchor` / `AnchorRect` now live in `overlay_stack`
(`popover.*` are aliases). A Popover anchored to a node that the caller frees while it is open no
longer reads the freed node: the panel stays where it was.

**Why.** The caller had to compute and push the area's rect (and clamp the dialog's size) from its
own after-layout hook. Design: `docs/design/overlay-within-area.md`.

**Migration.**

```zig
// before: an after-layout hook found the pane, wrote its rect and clamped width / height
const m = try W.Modal(.{ .open = open, .width = width_sig, .height = height_sig, .center_in = area_sig }).mount(scope, cx);
// after
const pane_area = try scope.createSignal(?ui.widgets.modal.Anchor, null);
const m = try W.Modal(.{ .open = open, .width = 520, .max_height = 10000, .within = pane_area, .within_padding = 12 }).mount(scope, cx);
// when the owning pane changes:
pane_area.set(.{ .node = pane });
```

<a id="modal-close-button-part"></a>

## 2026-11-16: Modal close button is a native Button part; `close_test_id` removed (BREAKING)

**What changed.** The title bar's close button is a native icon-only `Button` (focusable, keyboard
activated, focus ring), placed after the body in the tree so a dialog's initial focus reaches the
body first. `ModalResult` gains the parts `title: ?*Node` and `close_button: ?*Node`.
`ModalProps.close_test_id` is removed (name the part instead); `close_label` becomes
`Source([]const u8)` (followed); new `closable: Source(bool) = true`. The default glyph is the x
icon. `ConfirmDialog` passes `close_label` / `closable` through, exposes `close_button` and takes
`test_ids.close`. The dialog's children are now title bar, body, close button place.

**Why.** A test id per internal node is what `parts` is for; the old button was not reachable by
keyboard. Design: `docs/design/modal-close-button.md`.

**Migration.**

```zig
// before
const m = try W.Modal(.{ .title = "Log", .open = open, .close_label = "关闭日志", .close_test_id = "log.close" }).mount(scope, cx);
// after (imperative mount)
const m = try W.Modal(.{ .title = "Log", .open = open, .close_label = "关闭日志" }).mount(scope, cx);
if (m.close_button) |b| b.meta.ownership.meta.test_id = "log.close";
// after (ui.view / Yix): parts={.{ .close_button = "log.close" }}
```

Code that found the title or the button by child index uses `m.title` / `m.close_button`.

<a id="text-field-behavior-sources"></a>

## 2026-11-16: Input / Textarea behaviour props follow sources; `Input.revealed` (BREAKING)

**What changed.** `InputProps.input_type: Source(InputType)`, `readonly: Source(bool)`,
`required: Source(bool)`; `TextareaProps.readonly: Source(bool)`, `required: Source(bool)` (were
plain values read at mount). New `InputProps.revealed: Source(bool)`: a `.password` field shows its
characters while staying a password field for the IME, the clipboard and accessibility. A static
read-only Textarea now installs its handlers: it can be focused, selected and copied (editing is
fenced event by event, like Input), and shows its focus ring.

**Why.** Changing these after mount meant remounting (losing focus, caret, composition, undo) or
writing the edit state / a11y / text client by hand. Design: `docs/design/text-field-live-behavior-props.md`.

**Migration.** Literals through `W.Input(.{ … })` / `W.Textarea(.{ … })` are unchanged. Props
structs built directly need a Source:

```zig
// before
const p = ui.widgets.input.InputProps{ .required = true, .readonly = locked_now };
// after
const p = ui.widgets.input.InputProps{ .required = .of(true), .readonly = .{ .signal = locked } };
```

Show / hide a password with `revealed` instead of switching the type:

```zig
// before: state.input_type = if (shown) .text else .password; + a11y / text client by hand
// after
_ = try W.Input(.{ .value = pw, .input_type = .password, .revealed = shown }).mountResult(scope, cx);
```

<a id="lc4-css-default-audit"></a>

## 2026-10-19: LC4 CSS default audit and explicit native extensions

This audit adds no Web backend and changes no native defaults. Two existing
behaviors need migration before an application can assume standard CSS defaults;
they remain compatibility debt rather than being reclassified as CSS extensions.
Web implementation and browser acceptance are pending project approval.

**Position defaults.** Native Style defaults to `relative`, while CSS's initial
position is `static`. Choose explicitly when migrating: use static for normal
CSS flow, relative for a containing block or relative offsets. LC3C already
supports static, so this migration works today:

```zig
// Before: relies on the framework's implicit relative positioning.
const old: ui.BoxStyle = .{ .inset = .{ .left = 8 } };
// Preserve native intent explicitly, including on a future DOM host:
const preserved: ui.BoxStyle = .{ .position = .relative, .inset = .{ .left = 8 } };
// Opt into the CSS initial positioning semantics (insets do not offset it):
const css_flow: ui.BoxStyle = .{ .position = .@"static" };
```

**Sibling z ordering.** Native `z_index` compares only siblings, clamps negative
values to the regular tier, and gives sticky nodes a special tier. CSS z-index
neither creates a context on every ancestor nor clamps all negative levels.
Do not assume that a large descendant z-index escapes a native ancestor. Move
ordering to children of the common ancestor; make each intentional isolated
visual group explicit with `composited_group`. For window-wide overlays use the
existing portal. Avoid negative z-index in portable application styles:

```zig
// Before: child of a group tries to paint over its parent's sibling.
const old_child: ui.BoxStyle = .{ .z_index = 300 };
// After: order the group at the shared parent's level and explicitly isolate it.
const group: ui.BoxStyle = .{ .z_index = 300, .composited_group = true };
const child: ui.BoxStyle = .{ .z_index = 0 };
// Overlay content must escape clipping/stacking ancestors through the portal.
const portal = try cx.ensurePopoverPortalRoot();
try portal.appendChild(cx.allocator, overlay_content);
```

This is an application migration path, **not a claim that native z_index has
become CSS compliant**. Full standard stacking/negative levels stay in LC3's
render/hit acceptance work; the future DOM lowering must use normal CSS z-index
and only explicit groups, rather than silently reproducing native default
contexts. Application GUI baselines must be checked when that semantic fix lands.

**Framework profile and aliases.** Zenit box nodes are flex containers with a
column default; these are framework style choices, not CSS initial values.
Declare `.display = .flex, .direction = .column` when that is the intent (or use
explicit row/col builders). `flex` is the grow weight used by Sizing.grow, **not**
the CSS flex shorthand. Keep basis/shrink explicit when translating styles.
`overflow_hidden=true` is a legacy alias which wins over `overflow`; replace a
conflicting pair with a single explicit property:

```zig
// Before: hidden wins despite visible.
const old_clip: ui.BoxStyle = .{ .overflow_hidden = true, .overflow = .visible };
// After: one source of truth, with the same clipping intent.
const clip: ui.BoxStyle = .{ .overflow = .hidden };
```

Other independent capabilities (`ellipsis_smart`, `fade_right`,
`no_cross_stretch`, `layout_isolation`, `border_overlay`, `glass`, animation and
interaction APIs) already use new properties/values. Their explicit Web
lowering/fallback decisions are in LAYOUT_CSS_MAPPING's LC4 inventory; unsupported
visual effects never mutate standard CSS defaults or truncate source text.

## 2026-10-19: LC3C border-box, positioning, ratio and common Grid sizing (BREAKING)

`border` now consumes space inside width/height, alongside padding. Transparent
borders count too. All sizes and explicit min/max are border-box; border+padding
is the non-shrinkable floor. Intrinsic sizes, flex inner-basis shrink, wrapping,
Grid, absolute positioning, and text/media content origins share these insets.

Built-in control outlines and Storybook frames were decorative under the old
semantics. They now explicitly use the additive overlay extension to preserve
those frames, gaps and glyph origins. Popover chrome uses the same explicit
decorative border so dynamic scroll-list growth retains its previous outer size. This is also the migration for consumer
outlines that were intentionally drawn over content:

```zig
// Default CSS border: a 100px box with 1px border has 98px before padding.
.border = .{ .width = 1, .color = color },
// Explicit decorative border: same drawing, no layout inset.
.border = .{ .overlay = true, .width = 1, .color = color },
// BoxStyle / ui.css / YSS equivalent (also works with per-side widths).
.border_overlay = true,
// YSS: border-overlay: true; border: 1 border;
```

Known browser difference: `fit-parent-basis-zero` (fit parent, zero flex basis and
explicit zero minimum) deliberately follows Chromium's intrinsic sizing result.
Firefox differs in the recorded comparison; this fixture remains report-only
(`must_match: false` with its explanatory note). This is a pinned compatibility
choice, not a claim of complete CSS Flexbox §9.9 conformance. Do not silently
change the pin or promote it without new cross-engine evidence.

The default position remains relative. `position = .@"static"` is now available;
absolute children use the nearest containing-block ancestor's padding box, excluding
its border. Without insets, the static position starts at the content edge (inside padding); explicit insets still use the padding box. Static transform/layout-containment ancestors also establish a block. With no such ancestor they use the initial viewport. Rectangles
remain local to the actual parent, and resizing a farther containing block
invalidates intervening static caches. Relative inset offsets the flow result
without reserving extra space; left/top win over right/bottom in this horizontal
writing mode. Do not use relative inset as an ignored metadata field.

Aspect ratio derives either auto axis from the definite opposite axis, including
nowrap/wrap paths, root and common absolute cases. Percent sizes remain definite;
min/max clamp the derived axis (min wins), and transferred suggestions participate
in the non-replaced flex automatic minimum. Explicit min=0 still allows shrinking.
Double-definite dimensions can override the preferred ratio.

Grid `justify` now maps to `justify-content`: it aligns the track group, not an item inside its cell ([CSS Box Alignment §5.1.4](https://www.w3.org/TR/css-align-3/#distribution-grid)). In a 100px track filling a 100px grid, a 20px item with 5/15px horizontal margins starts at x=5, not the previous x=35. The old synthetic unit assertion was updated to this contract with a required margin fixture; no e2e assertion or threshold changed. Explicit inline item centering still needs an inner flex wrapper or suitable auto margins; independent justify-items remains a residual.

Grid now preserves single-axis placements, positive spans and implicit columns/
rows beyond the old tables. Standard fr tracks retain an automatic content floor;
justify/align-content align track groups and enlarge spanning gutters; items with explicit minima can freeze a track before the remaining frs divide
space. Auto rows stretch under normal align-content. Use an explicit zero-min
track for equal shares that may overflow their contents:

```zig
.columns = &.{
    .{ .minmax = .{ .min = .{ .px = 0 }, .max = .{ .fr = 1 } } },
    .{ .minmax = .{ .min = .{ .px = 0 }, .max = .{ .fr = 1 } } },
},
```

`minmax` currently supports minimum px/auto and maximum px/fr/auto. The public
explicit track arrays remain limited to 16 per axis. Dynamic implicit tracks do
not have the old 16-column/64-row truncation. This does not implement the whole
CSS Grid intrinsic/indefinite/spanning algorithm; see the mapping's residuals.
Scratch allocation failure retains previous geometry and dirty retry; first-frame
OOM can still show zero grid geometry until a successful retry.

Normal word wrapping now leaves an unbreakable long word intact. New `TextProps`
and `TextStyle` controls distinguish emergency wrapping from min-content sizing:

```zig
.wrap = .word,
.overflow_wrap = .break_word, // emergency breaks, original word remains min-content
// or .anywhere: emergency breaks also lower min-content / automatic minimum
// or .word_break = .break_all: break-all opportunities lower min-content
```

`.wrap = .word_break` is an additive shorthand for the first pair. Existing
built-in wrapped labels/bodies explicitly use it to preserve their emergency
wrapping intent. `.wrap = .char` maps to overflow-wrap:anywhere and keeps grapheme
clusters together. These controls affect automatic minimum; set min-width:0 when
a break-word flex item should shrink below the unbroken word. Mixed scripts,
fallback fonts, CJK/keep-all combinations and full whitespace behavior remain
separate acceptance work.

Mount callbacks now run after the outer layout's geometry transaction. A callback
may remove/destroy itself, siblings or an ancestor, or reenter layout, without
leaving flex/grid holding freed child borrows. A structure/lifetime change stops
that publication walk; remaining first mounts occur on a subsequent dirty layout.
The usual unmodified tree still publishes leaf-to-root in the same layout call.

The headless inventory covers every registered story at 760/1100 plus component
helpers. Closed overlays with explicit zero width can now retain padding floors;
these geometry differences and hidden-ancestor evidence are reported separately
from visible content and CPU glyph baselines. Native screenshots, input and app
exit-allocation acceptance remain the coordinator's responsibility. E2E assertions
and thresholds are unchanged.

---

## 2026-10-18: LC3B cross-axis, wrap and first baseline follow CSS (BREAKING)

Cross-axis `grow` is now CSS auto sizing: it uses content under start/center/end;
stretch applies only to auto cross sizes and still respects sizing/ext min/max
(min wins over max). Cross auto margins suppress stretch and alignment. Recursive
fit backfill and incremental descendant reflow preserve allocated stretch sizes.
A fit cross axis measures wrapped content before stretching its line; nested
center/end alignment is recomputed at the final size.

Wrap collects outer hypothetical sizes, runs the existing §9.7 grow/shrink resolver
per line, measures the post-flex cross sizes, then packs lines and aligns items.
`align_self`, `no_cross_stretch`, auto margins and fixed gaps now work on wrapped
lines too. Explicit px/percent cross sizes stay explicit. There is no 256-line cap;
wide scratch uses the frame allocator, with counted OOM and no partial line publish.
On-mount callbacks run after final line placement, including callback reentry.

`ui.AlignContent` / `BoxStyle.align_content` add normal, stretch, start, end, center,
space_between, space_around and space_evenly. Normal behaves as stretch for flex
lines. It also affects a wrap container that happens to have one line; nowrap
ignores it. To request tightly packed wrap rows, set `align_content = .start`.

`AlignItems.baseline` and the new `.first_baseline` align the first text line or an
exported nested flex baseline. Boxes without one synthesize a border-box baseline.
Baseline-group distances remain signed when short leading or negative margins put
the baseline outside the outer box; these cases must not inflate the line height.
Text layout and paint share the resolved face metrics and half-leading; the old
unconditional 0.75 estimate is only the no-font-resolver fallback. Positive
`TextProps.baseline_ratio` remains an explicit extension. A fixed-height text node
starts its line at the content top; center text through its flex wrapper. These
font baseline corrections need native screenshot review separately from rectangles.

Negative justify space is retained for end/center. Distributed alignment uses the
CSS safe fallback to flex-start on reverse axes (CSS Align §4.4 / CSSWG #11937); fixed
gap is always retained. Do not depend on overflow being clamped to start.

```zig
// Fill a cross axis even when the parent's items are centered/start-aligned.
.height = .{ .grow = .{} }, // a row's cross axis
.align_self = .stretch,

// Keep a content-sized component's width under inherited stretch, while still
// allowing the parent's explicit center/end alignment.
.width = .{ .fit = .{} },
.no_cross_stretch = true,
```

YSS now accepts `flex-basis: auto | content` alongside nonnegative pixels (including
0). Keywords come from `FlexBasis.keywords` through `tools/yss_schema.zig`; the
compiler emits `ui.FlexBasis.auto/content`. Regenerate with `zig build gen-yss-schema`
and `zig build gen-yix`; do not edit schema/twins manually. YSS also accepts
`align-content` and `align-items/align-self: first-baseline`.

Fixed-height text used as its own circle/capsule no longer receives the old hidden
paint offset. Either put content-sized text inside a centered box, or explicitly
supply the line inset while keeping a text-bearing root. Steps uses the latter
for both orientations, preserving its number-circle text API:

```zig
// Before: depended on implicit paint centering.
.padding = .{},
// After: explicit vertical line inset (24px circle, 1.4 line-height).
.padding = ui.Padding.symmetric(@max(0, (24 - font_size * 1.4) / 2), 0),
```

Text-node rectangles alone cannot detect the former offset: inspect the emitted
first-line baseline or native glyphs as well. The Steps headless regression checks
both orientations across current/completed state changes; native screenshot checks
remain separate. Calendar weekday headings use a box/text structure, preserving
inline start while centering vertically. Badge retains its text-bearing root
(including test-id text queries) with theme/size-derived vertical padding
`(capsule_height - font_size * 1.2) / 2`, clamped to its original padding.
Dot mode still has zero padding and an 8px box.

Built-in style migrations preserve their previous intent:

- Table/DataTable cells and resize handles, NumberStepper fields/arrows, Input
  content/editing surfaces, embedded Input/Textarea, vertical Divider and Steps
  indicators, HeadlessSelect's default frame, and Button's loading canvas
  explicitly stretch.
- ControlShell's intrinsic geometry, Checkbox/Radio/Switch/RadioGroup, Rate, Group,
  Popover's trigger wrapper, auto-sized Stack/Skeleton, vertical Steps rows and
  Alert actions explicitly retain content dimensions. Block Buttons, horizontal
  Steps and DatePicker's Today button explicitly stretch when they should fill.
- Card headers fill their card; Timeline text keeps its natural height. Tabs rows
  and standalone tab triggers retain their content width.
- Storybook's shared hug stacks/rows and clip samples state their hug intent;
  Notification, PaintReplay and the wide GlassIslands root state their fill intent.
  Lifecycle demo regions explicitly retain their former full-width mounting area.

The window-free inventory mounts all 100 registered stories at 760 and 1100 logical
pixels, including their public components, and separately mounts window chrome
helpers, standalone SelectHeadless and SnapshotLayer, which are outside registered
story content. It emits every node rectangle when
`ZENIT_LC3_INVENTORY=1 zig build test-lc3-stories` is used. It models panelHug and the
wide GlassIslands exception. This is initial/settled geometry plus the existing
stateful story regressions, not GUI rendering or every interactive state. E2E
assertions and thresholds are unchanged. Downstream repositories were inspected
read-only; applications using cross-axis grow in centered/start rows should add an
explicit self stretch where fill was intended.

Grid, border box sizing, cyclic percentages, intrinsic basis interoperability and
long-word wrapping remain separate residuals; see [the mapping](LAYOUT_CSS_MAPPING.md).

---

## 2026-10-18: Hover follows the pointer in inactive windows; macOS emits `pointer_left` (BREAKING)

**What changed.** Hover liveness no longer depends on window activation: an
inactive window keeps hover on pointer moves and keeps re-resolving it when
content scrolls under a resting pointer (as AppKit's hover controls, Win32 and
Wayland do). The macOS backend now delivers hover motion to inactive and
non-key windows and emits the SDK `pointer_left` event when the pointer leaves
the content or another window covers it; before, only Windows and Wayland did,
and macOS sent a sampled `mouse_move` to (-1, -1) instead.

- `system_sdk.events.Event.pointer_left` is emitted on macOS too. A custom
  runtime that dispatches SDK events itself must forward it to
  `Cx.handlePointerLeave()` (the bundled `App` / `MultiWindowApp` do).
- `HoverSync.pointer_in_window` is renamed `pointer_over_content`.
- Code that hit-tests `cx.mouse_x` / `cx.mouse_y` itself should gate on the
  new `Cx.pointerLive()`; the last position survives a leave.
- `macos_get_mouse_move_event` (bridge ABI) takes a trailing `int *left`;
  `platform.macos.Window.MouseMoveEvent` gains `left`.

```zig
// before
.mouse_move => |e| cx.handleMouseMoveEx(e.x, e.y, mods),
// after: also forward the presence loss
.mouse_move => |e| cx.handleMouseMoveEx(e.x, e.y, mods),
.pointer_left => cx.handlePointerLeave(),

// before
if (cx.mouse_x >= r.x and cx.mouse_x < r.x + r.w) ...
// after
if (cx.pointerLive() and cx.mouse_x >= r.x and cx.mouse_x < r.x + r.w) ...
```

## 2026-10-18: LC3A nowrap flex main-axis sizes follow CSS (BREAKING)

**What changed.** Grow and shrink now share CSS Flexbox §9.7's iterative
freeze/distribute algorithm. An item's own `grow{min,max}` and ext bounds participate
before distribution; a capped item returns unused space to its siblings. Grow items
no longer disable shrinking of fixed-size siblings. Shrink uses basis × shrink, and
sum(grow) or sum(shrink) below 1 consumes only the specified fraction of initial free
space. Auto margins absorb positive space **after** flex, including capped grow cases.

`flex_basis` remains an `f32`: nonnegative values (including **0**) are pixels;
`ui.FlexBasis.auto` (-1) is the new default and uses the main size, falling back to
content for grow/fit; `ui.FlexBasis.content` (-2) ignores the specified main size.
Previously default 0 meant “unspecified”, and grow ignored every basis. In particular,
multiple grow children with different contents no longer necessarily have equal sizes.

An omitted main-axis minimum is now CSS automatic minimum: min-content for visible
overflow, zero for `overflow = .hidden/.auto/.scroll` or `overflow_hidden = true`.
An explicit `min_width = 0`, `min_height = 0`, or `grow/fit{ .min = 0 }` opts out of
this content floor. The internal default min marker is -1; ordinary numeric getters
still return a nonnegative floor. CSS min wins if main-axis min exceeds max.

**Migration.** Choose constraints according to intent; do not remove a correct
constraint simply to preserve the old algorithm's missed redistribution.

```zig
// before: equal shares from zero, even when children had different content sizes
.width = .{ .grow = .{} },

// after: explicitly request equal shares and allow contents to overflow/shrink
.width = .{ .grow = .{ .min = 0 } },
.flex_basis = 0,
.min_width = 0,

// after: retain a toolbar/sidebar's size when a grow sibling overflows
.width = .{ .px = 200 },
.flex_shrink = 0,

// before: numeric zero was used as an “unset” basis
.flex_basis = 0,
// after: use the explicit CSS default (or omit the property)
.flex_basis = ui.FlexBasis.auto,

// after: base flex allocation on content, ignoring an explicit width/height
.flex_basis = ui.FlexBasis.content,
```

For vertical layouts use `height` / `min_height`. A grow item with max=50 beside a
40px sibling in a 300px row now leaves 210px for auto margins or justify; to fix its
position, use explicit margins/justify rather than relying on discarded grow space.
A 300px row with grow min250 and an unconstrained grow sibling now yields 250/50,
not 150/150. Two px100 items with min80 on the first in 100px yield 80/20, not 80/50.

The built-in horizontal Steps cells now explicitly set basis=0 and min-width=0,
preserving their equal widths and connector-to-circle contract. Existing Steps
rectangle assertions are retained.

This batch applies to **nowrap main-axis allocation**. Wrap lines, cross-axis sizing,
baselines, grid and border sizing retain their separate outstanding differences.
Nested containers can move as a consequence of their newly allocated main size;
that does not make their cross/grid algorithms CSS-complete. See
[LAYOUT_CSS_MAPPING.md](LAYOUT_CSS_MAPPING.md) for the tested scope.

---

## 2026-10-18: Theme, accessibility-preference and style-generation signals are owned by the Cx (BREAKING)

**What changed.** `Cx.themeSignal()`, `Cx.a11yPreferencesSignal()` and (dev
preview) `Cx.styleGenerationSignal()` no longer take a scope. The signals are
Cx services: created on first use in a scope the Cx owns and released by
`Cx.deinit`.

**Why.** Each signal used to be created in the scope of whichever caller asked
first (usually that window's root scope) and only the Cx cache was cleared when
that scope went away. Every other holder kept the pointer: replacing one window
root with another on the same Cx freed the theme signal that the new window's
style effects were reading, and the next style run read freed memory.

```zig
// before
const theme = try cx.themeSignal(root_scope);
// after
const theme = try cx.themeSignal();
```

---

## 2026-10-18: `applyTransition` / `enableImplicitAnimation` report allocation failure (BREAKING)

**What changed.** `Node.applyTransition(allocator, entries)` and
`Node.enableImplicitAnimation(allocator, props, spec)` return
`error{OutOfMemory}!void` instead of `void`. When the node's transition slot
block cannot be allocated the node is unchanged and the error is returned;
before, the transition was silently skipped and the property snapped.

**Why.** Transitions are configured while mounting; a mount must fail rather
than report success with a transition missing.

```zig
// before
node.applyTransition(allocator, &comptime recipe.transition("background 150ms ease-out"));
// after
try node.applyTransition(allocator, &comptime recipe.transition("background 150ms ease-out"));
```

---

## 2026-10-17: ControlShell is a declarative Yix component; animated-background hook removed; pooled cell callbacks receive their scope (BREAKING)

**What changed.**

- `ui.widgets.ControlShell` is now a Yix + YSS component
  (`src/ui/components/control_shell/control_shell.yix`) with optional named slots
  `icon` / `content` / `append` (`?View`; an absent slot builds nothing). Removed:
  `controlShell(config, slots, scope, cx)`, `ControlShellConfig` (and its
  `resolvedConditionalStyle`), `ControlShellResult`, `ControlShellBuilder`, `asSlot` / `AsSlot`,
  `ControlShellRecipe` and the grouped-shell sync helper. Every state is declarative: variant ×
  size recipe, `:hover` / `:active` / `:focus` from the node, `disabled` / `invalid` / `expanded` /
  `selected` from parameters (signals allowed).
- `hooks.useAnimatedBackground`, `AnimatedBgConfig`, `AnimBgState` (and the node's animated
  background slot) and `ConditionalStyle.bgColors()` are removed. Interactive backgrounds are
  style conditions plus a transition.
- `table.CellRenderFn` gains a `scope: *Scope` parameter (the scope that owns the cell; content
  mounted under it is released with its row on recycle). The Table state's `cell_scope_slot`
  indirection is gone. VirtualList adds `mountScoped` (`RenderItemScopedFn` receives the list's
  own scope); `mountWithContext` is unchanged.
- Chip is a Yix component: `ChipBuilder`, `ChipRecipe` and `ChipSize.controlSize()` are removed;
  the Zig props (`label`, `size`, `variant`, `selected`, `disabled`, `icon_asset`, `closable`,
  `readonly`, `on_click`, `on_close`) keep their names, and `label` now defaults to `""`.
- Defaults that follow the revamped design: Table / DataTable `row_height` 36 → 28 and
  `header_height` 40 → 28, Progress `height` 4 → 6, Skeleton `height` 16 → 12, Spinner
  `stroke_width` 3 → 2.5; Markdown's `text_color` / `code_color` / `code_bg` / `link_color` /
  `rule_color` are `?Color` and default to the theme.

**Why.** Imperative frame writes and per-frame background polling could not follow theme
switches or compose with caller overlays, and recycled table cells kept their content scopes
(and `bindText` effects) alive under the body scope, which later wrote through freed nodes.

**Migration.**

```zig
// before
const shell = try control_shell.controlShell(.{
    .variant = .secondary,
    .size = .sm,
    .hover_style = .{ .background = t.color.bg_hover },
    .interactive = false,
}, .{ .content = v.text(.{}, "Label") }, scope, cx);

// after (Zig): props are snake_case, slots go through `.slots`
v.with(W.ControlShell(.{
    .variant = .secondary,
    .size = .sm,
    .root_style = .{ .hover = .{ .background = t.color.bg_hover } }, // per-state, merged into the tone
    .pins = .{ .hover = false, .active = false }, // was `interactive = false`
}), .{}).slots(.{ .content = v.text(.{}, "Label") })
```

```zig
// after (Yix)
<W.ControlShell variant={.secondary} size={.sm} content={<text>Label</text>} />
```

```zig
// before
_ = try hooks.useAnimatedBackground(scope, cx, node, .{ .normal = t.color.bg_primary, .hover = t.color.bg_hover });

// after: declare it on the element's style (YSS)
//   style row { background: bg-primary; :hover { background: bg-hover; } transition: background fast ease-out; }
// or ui.css
const row = ui.css(.{
    .background = .bg_primary,
    ._hover = .{ .background = .bg_hover },
    .transition = ui.transition("background fast ease-out"),
});
```

```zig
// before
fn cell(node: *Node, row: usize, col: usize, cx: *Cx, ctx: ?*anyopaque) void { ... }
// after
fn cell(node: *Node, row: usize, col: usize, scope: *Scope, cx: *Cx, ctx: ?*anyopaque) void { ... }
```

Application code using `Table(...).cells(ctx, cell)` / `VirtualList(...).rows(ctx, row)` is
unaffected.

---

## 2026-10-15: macOS non-precise wheel deltas are pixels (BREAKING)

**What changed.** `ScrollEvent.dx/dy` from a non-precise wheel (ratchet mouse)
were raw AppKit line units (typically ~0.1 per detent, up to ~15 on fast flicks).
They are now logical points, converted at the event bridge (`40 px/line`).
Precise devices (trackpads, Magic Mouse) already reported points and are
unchanged.

**Why.** Line units reached `scroll_area`, which applies `dx/dy` as pixels
(`scroll_speed` multiplies them): one detent scrolled ~0.1 px and fast flicks
drifted unpredictably. 40 px/line is the shared constant of Chromium
`kScrollbarPixelsPerCocoaTick`, WebKit `Scrollbar::pixelsPerLineStep` and
Flutter `pixelsPerLine`.

**Migration.** Drop any line-unit compensation you added for `ScrollEvent.dx/dy`:

```zig
// before
const px = ev.dy * 40; // or scroll_speed = 40, * line_height, ...
// after
const px = ev.dy; // already logical px
```

## 2026-10-12: renderers initialize in place (BREAKING)

**What changed**: `AppRenderer.init` and `ImageRenderer.init` now take a
`self` pointer and return `!void`. Nested `IconRenderer.init` follows the same
convention; `ImageTextureStore.init` takes a `self` pointer and returns `void`.

**Why**: returning renderers and texture stores by value produced multi-megabyte
Debug stack frames and could overflow the macOS main-thread stack when opening
another window. Initialization now writes directly into caller-owned storage and
rolls back acquired GPU resources on failure. Call `deinit` only after successful
initialization, and destroy the storage separately.

**Migration**

```zig
// before
renderer.* = try AppRenderer.init(allocator, io, device, queue, surface, config);
var image = try ImageRenderer.init(allocator, device);
defer image.deinit();

// after (renderer is already allocated)
try renderer.init(allocator, io, device, queue, surface, config);
const image = try allocator.create(ImageRenderer);
defer allocator.destroy(image);
try image.init(allocator, device);
defer image.deinit();

// Likewise for IconRenderer and ImageTextureStore:
try icon.init(allocator, device);
store.init(allocator, device, true); // shared namespace; no fallible allocation
```

## 2026-10-12: `ResourcePath.init` takes an `std.Io` (BREAKING)

**What changed**: `zenit_app.ResourcePath.init()` became `init(io: std.Io)`.
Zig 0.17 removed `std.fs.selfExePath` and the Io-less directory API, so the
executable path and the `assets/` probe now go through the caller's `Io`. The
probe uses native path separators, so an `assets/` directory beside a Windows
`.exe` is found too.

**Why**: the previous body no longer compiled under Zig 0.17; it was only
analysed by applications that call it.

**Migration**

```zig
// before
const res = ResourcePath.init();
// after
const res = ResourcePath.init(io); // e.g. init.io from main(init: std.process.Init)
```

## 2026-10-03: `ui.view` is the way to build UI; control flow is anchored (BREAKING for child-index code)

**What changed**

1. `ui.view` (declarative element tree) and `ui.on` (event combinators) are the
   app-facing way to build UI. All examples, the template and the docs use them.
   The node builders (`ui.box`, `ui.text`, `boxStyled`, …) remain for code
   inside components.
2. `Show` / `Match` / `For` now keep their content at the position where they
   were called. Each region owns a pair of `ElementTag.anchor` nodes
   (`display: none`: no size, no gap, skipped by hit testing and a11y) in the
   parent. Code that counts or indexes `parent.children` directly now sees the
   anchors.
3. `BoxStyle.merge` / `isEmpty` cover every field (they used to drop `display`).

**Why**: previously, Show / Match appended content at the end of the parent when
the condition turned true later, and For positioned itself by counting earlier
siblings, so mixing control flow with other children reordered the UI.

**Migration**

```zig
// before
const root = try ui.box(cx, .{ .gap = 8 }, .{});
try root.appendChild(cx.allocator, try ui.text(cx, "Title", .{}));
const counter = try cx.bindState(Counter, .{ .count = count });
try root.appendChild(cx.allocator, try W.Button(.{
    .label = "+1",
    .on_click = cx.on(Counter, counter, Counter.increment),
}).mount(scope, cx));
try root.appendChild(cx.allocator, try ui.textFmt(cx, scope, "{d}", .{count}, .{}));
return root;

// after
return v.render(scope, cx, v.col(.{ .style = S.root }, .{
    v.text(.{ .style = S.title }, "Title"),
    W.Button(.{ .label = "+1", .on_click = ui.on.update(count, inc) }),
    v.text(.{}, v.fmt("{d}", .{count})),
}));
```

| Before | After |
|---|---|
| `ui.box / hstack / vstack(cx, style, .{})` + `appendChild` | `v.box / v.row / v.col(.{ .style = … }, .{ children })` |
| `ui.boxStyled(cx, S.card, …)` / `textStyled` | `.style = S.card` |
| `ui.textFmt(cx, scope, fmt, args, style)` | `v.text(.{ .style = … }, v.fmt(fmt, args))` |
| `Bindings` struct + `cx.bindState` + `cx.on` for one click | `ui.on.set / toggle / update / assign`; shared state: `ui.on.call(ptr, T.method)` |
| `Widget(props).mount(scope, cx)` + `appendChild(result.container)` | `Widget(props)` as a child; `v.with(Widget(props), .{ children })` for slots |
| `node.meta.ownership.meta.test_id = …` after mount | `v.attrs(.{ .test_id = … }, Widget(…))` (boxes and text take `.test_id` directly) |
| `ui.Show(scope, parent, cond, cx, struct { fn build … })` | `v.show(cond, .{ … }).fallback(.{ … })` |
| `ui.Match(T, …)` / `ui.For(T, …)` | `v.match(value, .{ .tag = … })` / `v.each(items, .id, row)` |
| `inline for (specs) |s| appendChild(…)` | `v.list(&specs, f)` |
| `VirtualList(…).mount(scope, cx, render)` | `VirtualList(…).rows(ctx, row)` |
| Node fields set by hand (raw events, hooks) | `v.setup(element, ctx, f)` |

Code that indexes `parent.children` of a container holding `Show` / `Match` /
`For` should skip `node.tag == .anchor`.

## 2026-10-03: Text fields keep the caret when `ui.split` rewrites or rejects an edit

No API change. Input, Textarea and EditableText bound with `ui.split` used to
treat a rewritten or rejected user edit like an outside write: the whole text
was replaced, the caret jumped to the end, the selection was lost and the undo
history was cleared. With an upper-casing, digits-only or max-length parent,
typing in the middle of the text moved the caret to the end after every key and
Cmd+Z stopped working.

Now the field corrects itself in place:

- **Rejected** (the value did not change): the text, caret and selection are
  restored to what they were before the edit, and the undo and redo history
  is exactly as it was (the edit leaves no undo step and does not clear redo).
  A rejected undo / redo is reverted too.
- **Rewritten**: the text becomes the landed value and the caret stays at the
  edit point (for example after the inserted, upper-cased character). The
  rewrite is part of the same undo step, so Cmd+Z returns to the text before
  the edit.

`on_change` is still called only with the landed value, and by the time it runs
the field already shows that value. Writes from outside (the parent setting the
signal on its own) keep their behavior: the text is replaced, the caret moves to
the end, the undo history is cleared and `on_change` is not called.

Nothing to migrate. If you worked around the old behavior (for example by
moving the caret back yourself after the write), remove the workaround.

## 2026-10-02: Select `placeholder` accepts a signal; Steps updates the current step in place

**Select.** `placeholder` is a `Source([]const u8)`. String literals keep
working; pass a signal or derived value to change the hint at runtime (i18n,
"Loading…", a hint that depends on another field). The trigger shows the
current hint while nothing is selected; a searchable single Select uses it as
the search placeholder.

**Steps.** No API change. A change to `current` now restyles the existing steps
(circle, check icon, title, connector, a11y state) instead of rebuilding them;
only an `items` change rebuilds. Fixed: with `current` at or past the last
step, the horizontal progress line now ends at the last circle instead of
running past it.

## 2026-10-02: DropdownMenu is merged into Menu (BREAKING)

**What changed.** The two components had identical item visuals, keyboard
navigation and open pipeline; they differed only in how a choice was reported.
`ui.widgets.DropdownMenu` / `DropdownItem` / `DropdownItemKind` /
`DropdownMenuState` are removed, and `Menu` now does both:

| Before | After |
|---|---|
| `W.DropdownMenu(.{ .items = &items })` | `W.Menu(.{ .items = &items })` |
| `DropdownItem` / `DropdownItemKind` | `MenuItem` / `MenuItemKind` (same fields: `icon_asset`, `on_click`, `shortcut`, `danger`, `disabled`) |
| `DropdownMenuState` | `MenuState` |
| `DropdownMenuItemRecipe` | `MenuItemRecipe` |
| `Menu` `items: []const MenuItem` read once | `items: Source([]const MenuItem)`: pass a signal or derived value to rebuild the items when a new array is set |
| `ui.widgets.menu_navigation` | removed (its only remaining user is Menu) |

Per-item `on_click` and the menu-wide `on_select(id)` can be used together;
choosing an item requests closing first, then calls `on_select`, then the
item's `on_click`. Menu also gains DropdownMenu's `max_height` (the panel
scrolls past it) and icons.

**Item lifetime.** A static array is copied at mount together with its
strings (a function-local array is fine). Items from a signal are borrowed:
the array and its strings must stay valid until the signal holds a different
value.

**Visual change.** Menu separators now use DropdownMenu's layout: a 1px line
with 4px space above and below. Before, Menu drew a 1px line with no extra
space.

## 2026-10-02: Card / GlassBox titles and FormField labels accept signals (BREAKING)

**What changed.** `Card` and `GlassBox` take `title` / `subtitle` as
`Source([]const u8)` (`""` = none; was `?[]const u8`). `FormFieldOf(T).field`
/ `inputField` take the field config as an anytype literal, and its
`label_text` / `helper` are `Source([]const u8)`. A signal updates the text
after mount; an empty value hides the row. New `ui.bindOptionalTextRow` is the
shared primitive.

**Migration.** `.title = null` becomes `.title = ""` (or leave it out).

---

## 2026-10-02: DatePicker and DateRangePicker take `open: Model(bool)` and a dynamic `disabled` (BREAKING)

**What changed.** Both pickers gain `open: Model(bool)` + `on_open_change`
(the result gains `open: ?*Signal(bool)`), and `disabled` is a
`Source(bool)`. Opening the panel by any route (click, outside write to
`open`) resets the calendar to the selected month. `PopoverResult` gains
`show` / `toggle` handlers (same proposal pipeline as `close`) and
`open_read: Source(bool)` for components that wire their own trigger.

**Why.** Every overlay exposes its open state the same way; a form can
disable a picker while it is submitting.

**Migration.** Code that read the panel state through `stateOf(result).is_open`
uses `result.open` (or pass a signal as `.open`).

---

## 2026-10-02: Text components (Input, Textarea, EditableText, TagsInput, ComboBox) take Models (BREAKING)

**What changed.**

| Before | After |
|---|---|
| `initial_value: ?[]const u8` (read once), `result.state.setText(...)` to write later | `value: Model([]const u8)`: a literal is the initial text; a `*Signal([]const u8)` from `scope.createText` is the value source edits write to; `ui.split` lets the parent accept, transform or reject each edit |
| `on_change: ?HandlerRef` (`Cx.strHandlerFrom`) | `on_change: ?Handler([]const u8)` (`cx.on(S, s, S.changed)`), called with the landed value |
| — | `on_submit: ?Handler([]const u8)`: Enter in a single-line input |
| `state_id` (never read), builder setters `.placeholder() .label() .helper() .errorMsg() .required() .disabled() .width()` | removed; pass the fields in the literal |
| `Input(props: InputProps)` | `Input(props: anytype)` like every other component; `InputResult` gains `value: ?*Signal([]const u8)` |
| `label_text` / `helper` / `error_msg` / `placeholder: ?[]const u8`, `disabled: bool` | `Source([]const u8)` (`""` = none) and `Source(bool)`: a signal updates the label, helper, error state (border, colours, `invalid`), placeholder and disabled state after mount |
| `FormFieldOf(T).inputField(field, config, props: InputProps, …)` | `props` is an anytype literal like `W.Input(.{...})` |
| EditableText: `value: ?[]const u8` (read once), `on_change: ?HandlerRef` | same rules as Input; `result.setText(text)` (switching the edited object) now writes the value signal and applies at once, even mid-composition; `EditableTextResult` gains `value` |
| TagsInput: `W.TagsInput(props, scope, cx)`, `initial_tags` (each fired `on_change`), `on_change: ?HandlerRef` (no payload), tags held in `state` (`addTag` / `removeSlot`) | `W.TagsInput(props).mount(scope, cx)`; `tags: Model([]const []const u8)` (a bound signal must come from `scope.createList([]const u8, …)`), `on_change: ?Handler([]const []const u8)`, `placeholder` Source; result `{ wrapper, input, tags, state }` |
| ComboBox: `W.ComboBox(props, scope, cx)`, `on_change: ?HandlerRef` (read `state.selectedOption()`), `is_open` signal, static `options` / `label_text` / `disabled` | `W.ComboBox(props).mount(scope, cx)`; `value: Model(?[]const u8)` (committed option value) + `on_change: ?Handler(?[]const u8)`, `open: Model(bool)` + `on_open_change`, `options` / `label_text` / `placeholder` / `disabled` Sources; typing clears the committed value; result `{ wrapper, input, panel, value, open, state }` |
| Textarea: `value: ?[]const u8` (read once), `on_change: ?HandlerRef`, `context` (never read), builder setters, `mountWithState` returning `TextareaMount` | same rules as Input: `value: Model([]const u8)`, `on_change: ?Handler([]const u8)`, `label_text` / `helper` / `error_msg` / `placeholder` / `disabled` accept signals; `mountResult` returns `TextareaResult { wrapper, input, state, value }` |

Writes to the value from outside (the parent setting the signal) replace the
text, move the caret to the end and clear the undo history; they do not call
`on_change`. While the user is composing with an input method, outside writes
wait: if the composition is committed the user's text wins, if it is
cancelled the latest outside value is applied.

**Why.** One text-ownership and binding rule for every text field (§4.8);
programmatic writes no longer go around the component.

**Migration.**

```zig
// before
const r = try W.Input(.{ .initial_value = "draft", .on_change = ui.Cx.strHandlerFrom(S, s, S.changed) }).mountResult(scope, cx);
_ = r.state.setText("reset");
// after
const text = try scope.createText("draft", .{});
const r = try W.Input(.{ .value = text, .on_change = cx.on(S, s, S.changed) }).mountResult(scope, cx);
text.set("reset");
```

---

## 2026-10-02: Form fields are owned signals; `on_submit` is a Handler (BREAKING)

**What changed.**

| API | Before | After |
|---|---|---|
| `FormOf(T).create` config | `on_submit: ?*const fn (T, *anyopaque) void` + `submit_context` | `on_submit: ?Handler(T)` (`cx.on(S, s, S.submit)`) |
| `FormOf(T).setValueCopy` | copy variant for text fields fed from a temporary buffer | removed: text fields are owned text signals, `setValue` copies |
| Field signals | not reachable | `form.field(.email)` / `store.field(.email)` returns the field's `*Signal`, ready to bind into a component |
| Submit button | wire `handleSubmit` by hand | `.on_click = form.submitHandler()` |
| `Form(props)` layout container | typed `FormProps` | anytype literal like every other component |

`StoreOf(T)` creates `[]const u8` fields with `scope.createText`; a value read
from such a field is valid only during the current call (copy it to keep it).

**Why.** One text-ownership rule for the whole framework (§4.8) instead of a
Form-only copy helper; typed submit handler.

**Migration.**

```zig
// before
const form = try W.FormOf(Login).create(scope, init, .{ .on_submit = S.submit, .submit_context = s });
form.setValueCopy(.email, text) catch {};
// after
const form = try W.FormOf(Login).create(scope, init, .{ .on_submit = cx.on(S, s, S.submit) });
form.setValue(.email, text);
const submit = try W.Button(.{ .label = "Sign in", .on_click = form.submitHandler() }).mount(scope, cx);
```

---

## 2026-10-02: VirtualList takes a row-count Source; ScrollArea and Grid use the common entry point (BREAKING)

**What changed.**

| Component | Before | After |
|---|---|---|
| VirtualList | `item_count: usize` (call `updateItemCount` by hand when it changes), builder setters `.width() .height() .overscan() .padding() .background()`, `state.props.item_count` | `item_count: Source(usize)` and `data_version: Source(u64)` (rows redraw when either changes); setters removed, pass the fields in the literal; the applied count is `state.item_count`. `updateItemCount` still works for callers that drive the count themselves |
| ScrollArea | `W.mountScrollArea(props, scope, cx)` | `W.ScrollArea(props).mount(scope, cx)` (same props and result) |
| Grid | `W.mountGrid(props, scope, cx)` | `W.Grid(props).mount(scope, cx)` (same props and result) |

**Why.** One way to create every component; a list whose length lives in a
signal no longer needs an effect in the caller to keep the list in sync.

**Migration.**

```zig
// before
const vl = try W.VirtualList(.{ .item_count = rows.items.len, .item_height = 28 }).width(320).mount(scope, cx, render);
// ... after every change: ui.widgets.virtual_list.updateItemCount(vl.state, rows.items.len);
const sa = try W.mountScrollArea(.{ .height = 240 }, scope, cx);

// after
const vl = try W.VirtualList(.{ .item_count = row_count, .item_height = 28, .width = 320 }).mount(scope, cx, render);
const sa = try W.ScrollArea(.{ .height = 240 }).mount(scope, cx);
```

---

## 2026-10-02: Signal-first props for Tree, Table, DataTable, Select, SelectHeadless, FileUpload; owned list signals (BREAKING)

**What changed.**

| Component | Before | After |
|---|---|---|
| Tree | `nodes` read once, `TreeNodeData.label_text`, selection / expansion held in `TreeState` (`selectedIds`, `toggleExpand`), `on_select: ?HandlerRef` (id via `invokeWithStr`), `selectable` / `on_expand` (never read), builder methods, result `{ wrapper, state }` | `nodes: Source([]const TreeNodeData)` (a new tree rebuilds the rows), `selected` / `expanded: Model([]const []const u8)` (sets of node ids), `on_select: ?Handler([]const u8)` receives the id, `TreeNodeData.label`; result `{ wrapper, selected, expanded }` |
| Table | `row_count: usize`, `on_sort` / `on_row_click: ?HandlerRef` (no payload), `TableState.setSort`, result `{ wrapper, state, vl_state }`, builder methods | `row_count: Source(usize)`, `data_version: Source(u64)` (change it when the cells change but the row count does not), `sort: Model(?TableSort)`, `on_sort_change: ?Handler(?TableSort)`, `on_row_click: ?Handler(usize)` receives the row; result `{ wrapper, sort }` |
| Select | `W.Select(props, scope, cx)`, `options` read once, `initial_selected: []const usize` (indices), `on_change: ?HandlerRef` (no payload), `disabled: bool`, result `{ wrapper, trigger, panel, state, is_open }` | `W.Select(props).mount(scope, cx)`; `options: Source(...)` (a new list rebuilds the rows), `value: Model(?[]const u8)` + `on_change: ?Handler(?[]const u8)` for `.single`, `values: Model([]const []const u8)` + `on_values_change` for `.multiple`, `open: Model(bool)` + `on_open_change`, `disabled: Source(bool)`; result `{ wrapper, trigger, panel, value, values, open }`; inner nodes for test hooks through `select.stateOf(result)` |
| SelectHeadless | `mountSelectHeadless(T, props, scope, cx)`, `initial_value`, `on_change: ?HandlerRef` (no payload), `disabled: bool`, `SelectProps` / `ControlledProp` on the state machine, result `{ …, is_open, state, item_nodes, vl_state }` | `SelectHeadless(T, props).mount(scope, cx)`; `options: Source(...)`, `value: Model(?T)` + `on_change: ?Handler(T)`, `open: Model(bool)` + `on_open_change`, `disabled: Source(bool)`; `TriggerSlotCtx` carries `value: Source(?T)` and `scope` so a custom trigger can follow the selection; result `{ wrapper, trigger, trigger_label, content, value, open }`; `SelectState(T){}` is the navigation state only |
| FileUpload | `W.FileUpload(props, scope, cx)`, files held in `state` (`addFile` / `removeSlot` / `fileCount`), `on_change` / `on_browse: ?HandlerRef`, `hint: []const u8`, result `{ wrapper, state }` | `W.FileUpload(props).mount(scope, cx)`; `files: Model([]const []const u8)` (paths; a bound signal must come from `scope.createList([]const u8, …)`), `on_change: ?Handler([]const []const u8)`, `on_browse: ?Handler(void)`, `hint: Source([]const u8)`; result `{ wrapper, files, drop_zone, rt }`; a custom Browse adds through `result.add(path)` |
| DataTable | `mountDataTable(props, scope, cx)` / `W.DataTable(props, scope, cx)`, `rows` read once, `on_selection_change: ?HandlerRef`, selection read through `state.selectedRows`, result `{ wrapper, state, filter_input }` | `W.DataTable(props).mount(scope, cx)`; `rows: Source(...)`, `selection: Model([]const usize)` (raw row indices), `page: Model(usize)`, `on_selection_change: ?Handler([]const usize)`, `on_page_change: ?Handler(usize)`; result `{ wrapper, selection, page, filter_input }` |

A signal bound to a set-valued Model (Tree `selected` / `expanded`, DataTable
`selection`, Select `values`, FileUpload `files`) must be created with `scope.createList(E, initial)`: the component
writes new sets from temporary buffers and the signal keeps its own copy.
Binding a plain `createSignal([]const E, ...)` fails mount with
`error.ListModelNotOwned`.

**Why.** Same as the other entries. Selection and sort are values the caller
can read, write and intercept (`ui.split`) instead of methods on a state
struct; handlers receive what changed.

**Migration.**

```zig
// before
const tree = try W.Tree(.{ .nodes = &files, .on_select = ui.Cx.strHandlerFrom(S, s, S.picked) }).mount(scope, cx);
var ids: [16][]const u8 = undefined;
const selected = ids[0..tree.state.selectedIds(&ids)];
const dt = try W.DataTable(.{ .columns = &cols, .rows = &rows, .selection_mode = .multi }, scope, cx);
var buf: [64]usize = undefined;
const picked = buf[0..dt.state.selectedRows(&buf)];

// after
const open_dirs = try scope.createList([]const u8, &.{ "src", "docs" });
const tree = try W.Tree(.{ .nodes = &files, .expanded = open_dirs, .on_select = cx.on(S, s, S.picked) }).mount(scope, cx);
const dt = try W.DataTable(.{ .columns = &cols, .rows = rows, .selection_mode = .multi }).mount(scope, cx);
const picked = dt.selection.?.peek(); // or read it in an effect / memo

// Select: indices -> values
// before
const prio = try W.Select(.{ .options = &priority_options, .initial_selected = &.{1} }, scope, cx);
// after
const prio = try W.Select(.{ .options = &priority_options, .value = "normal" }).mount(scope, cx);
```

---

## 2026-10-02: Signal-first props for display components; one entry point for every component (BREAKING)

**What changed.**

| Component | Before | After |
|---|---|---|
| Alert | `title: ?[]const u8`, `message: []const u8`, `variant`, builder methods, `on_close: ?HandlerRef` | `variant` / `title` / `message` are Source (dynamic messages update the live region), `on_close: ?Handler(void)` |
| Tag | `text`, `color` read once, builder methods | `text` / `color` are Source; `variant` / `size` stay structural |
| Chip | `variant: default / active / outline / disabled`, `label: []const u8`, `on_click` / `on_close: ?HandlerRef` | `variant: default / outline`; state moved to `selected: Source(bool)` and `disabled: Source(bool)`; `label` is Source; handlers are `?Handler(void)` |
| Breadcrumb | `on_click: ?HandlerRef` shared by every item (no way to tell which), `BreadcrumbItem.label_text` | `items: Source(...)` (a new path rebuilds the crumbs), `on_select: ?Handler([]const u8)` receives the item id, `BreadcrumbItem.label` |
| Timeline | `items` read once | `items: Source(...)` |
| Divider | `label_text: ?[]const u8`, builder methods | `label: Source([]const u8)` (empty = no label) |
| Markdown | `Markdown(text, opts).render(cx)` returning `{ root }` | `Markdown(.{ .text = Source, .options = ... }).mount(scope, cx)` returning the root node; a text signal re-renders |
| TabPanel | `TabPanel(.{ .id, .active: bool }).build(cx)` | `TabPanel(.{ .id, .active: Source(bool) }).mount(scope, cx)`, e.g. `.active = ui.eq(tab, "files")` |
| EditorTabs | — | **Removed.** It never wired its handlers; use `Tabs(.{ .variant = .tab, .closable = true })` |
| Spinner, Skeleton, Group, VStack, HStack, GlassBox | `X(props)` plus builder setters | `X(props)` only (anytype literal); builder setters removed |

**Why.** Same as the other entries: one way to pass values, and values that
change after mount are Sources.

**Migration.**

```zig
// before
const crumbs = try W.Breadcrumb(.{ .items = &items, .on_click = ui.Cx.handlerFrom(S, s, S.nav) }).mount(scope, cx);
const chip = try W.Chip(.{ .label = "Open", .variant = .active }).mount(scope, cx);
const spinner = try W.Spinner(.{}).size(24).mount(scope, cx);

// after
const crumbs = try W.Breadcrumb(.{ .items = path, .on_select = cx.on(S, s, S.goTo) }).mount(scope, cx);
const chip = try W.Chip(.{ .label = "Open", .selected = show_open }).mount(scope, cx);
const spinner = try W.Spinner(.{ .size = 24 }).mount(scope, cx);
```

## 2026-10-02: Signal-first props for Radio, RadioGroup, Modal, Sheet, Popover, Tabs, Accordion, Slider, Steps, Rate, NumberStepper, Card, Tooltip, Menu, DropdownMenu, Calendar, DatePicker, DateRangePicker (BREAKING)

**What changed.**

| Component | Before | After |
|---|---|---|
| RadioGroup | value read once at mount, `on_change: ?HandlerRef` (str payload), `RadioOption.label_text` | `value: Model(?[]const u8)`, `options` / `disabled: Source`, `on_change: ?Handler([]const u8)`; `RadioOption.label` |
| Radio | `on_change`, `name`, `value` (never wired), builder methods | display only: `checked` / `label` / `disabled` are Source |
| Modal / Sheet | `visible: ?*Signal(bool)`, builder `.visible(sig)` | `open: Model(bool)`, `on_open_change: ?Handler(bool)`; result field `open: ?*Signal(bool)` (null under `ui.split`); Modal `title` is Source |
| Popover | `visible` signal | `open: Model(bool)`, `on_open_change`; trigger click / hover only propose |
| AccordionItem | `expanded: bool` read once, `title: []const u8`, `on_change: ?HandlerRef`, `context`, builder `.title() .expanded() .variant() .onChange()`; `AccordionItemState.setExpanded / toggle` | `expanded: Model(bool)`, `title: Source([]const u8)`, `on_change: ?Handler(bool)` |
| Accordion | `exclusive: bool` (never took effect: items were never registered), `AccordionState` | `open: Model(?usize)`; mutually exclusive items take `.expanded = try acc.item(i)`; result field `open: ?*Signal(?usize)` |
| Slider | `initial_value` read once, `disabled: bool`, `haptic_feedback` / `haptic_pattern` mutated on `result.state`, `on_change: ?HandlerRef` (no payload, fired per pointer sample), builder methods; result `{ wrapper, state }` | `value: Model(f32)`, `disabled` / `haptic_feedback` / `haptic_pattern: Source`, `on_change: ?Handler(f32)` (landed value); result `{ wrapper, value: ?*Signal(f32) }` |
| Steps | `initial_current` read once (static rendering), builder methods | `current: Source(usize)`, `items: Source([]const StepItem)`; changes rebuild the steps |
| Rate | `value: f32` read once, `disabled: bool`, `on_change: ?HandlerRef` (no payload), builder methods, `result.state.setValue` | `value: Model(f32)`, `disabled: Source(bool)`, `on_change: ?Handler(f32)`; result `{ wrapper, value: ?*Signal(f32) }` |
| NumberStepper | `mountNumberStepper(props, scope, cx)`, `value: f64` read once, `disabled: bool`, `on_change: ?HandlerRef` (no payload), `result.state` | `NumberStepper(props).mount(scope, cx)` like every other component; `value: Model(f64)`, `disabled: Source(bool)`, `on_change: ?Handler(f64)`; result `{ wrapper, value: ?*Signal(f64) }` |
| Card | `selected: bool` read once, builder `.title() .subtitle() .variant() .interactive() .selected() .width() .height() .onClick()`, `on_click: ?HandlerRef` | `selected: Source(bool)`; `on_click: ?Handler(void)` (passing it makes the card interactive); builder methods removed |
| Tooltip | `text: []const u8`, builder `.text() .position() .offset()` | `text: Source([]const u8)` (dynamic text updates the tooltip and its a11y name); `open: Model(bool)` / `on_open_change` pass through to the Popover; result gains `open: ?*Signal(bool)` |
| Menu | `on_select: ?HandlerRef` without payload, `MenuItem.label_text`, builder methods, result `{ wrapper, trigger, state }` | `on_select: ?Handler([]const u8)` receives the item id; `open: Model(bool)` / `on_open_change`; `MenuItem.label`; result `{ wrapper, trigger, open }`; items are copied at mount |
| DropdownMenu | `DropdownItem.label_text`, builder methods, result `.state` (`is_open` signal) | `DropdownItem.label`; `open: Model(bool)` / `on_open_change`; result `{ wrapper, trigger, open }`. Choosing an item or Escape requests closing through the open pipeline, so a `ui.split` parent can keep the menu open |
| Calendar | `initial_year` / `initial_month` / `selected_date` read once, `on_select: ?HandlerRef` (no payload), builder methods, result `.state` | `value: Model(?SimpleDate)`, `month: Model(?YearMonth)` (null = follow the selection, else today), `on_select: ?Handler(SimpleDate)`; result `{ wrapper, value, month }` |
| DatePicker | `selected_date` / `initial_year` / `initial_month` read once, `on_change: ?HandlerRef`, `result.state` (`setSelectedDate`, `clearSelection`) | `value: Model(?SimpleDate)` (clear with `value.set(null)`), `on_change: ?Handler(SimpleDate)`; the popup calendar opens on the selected month (else today); result `{ wrapper, value }` |
| DateRangePicker | `start_date` / `end_date` / `initial_year` / `initial_month` read once, `on_change: ?HandlerRef`, `result.state` | `value: Model(?DateRange)`, `on_change: ?Handler(DateRange)`; the first click is a draft inside the component, so only complete ranges are proposed; the panel opens on the range's start month (else today); result `{ wrapper, value }` |
| Tabs | `active_id` / `default_active_id` read once, `on_change` / `on_close: ?HandlerRef`, `context`, `state_id`, `TabItem.label_text`, `TabsState` | `items: Source([]const TabItem)`, `active: Model(?[]const u8)`, `on_change` / `on_close: ?Handler([]const u8)`; `TabItem.label`; `TabsState` removed |

**Behavior to check.**

- A Modal / Sheet mounted without `open` starts **closed** (local `false`).
- Escape, outside click and the close button only *request* closing: the
  component proposes `open = false`; a `ui.split` parent can refuse and the
  overlay stays open. The exit animation starts after the value lands.
- Slider: user input is snapped to `step` and clamped to `[min, max]` before
  it is proposed; an out-of-range value written from outside is displayed
  clamped and is not written back. `on_change` fires once per landed value.
  The same holds for Rate and NumberStepper. The first user interaction on an
  out-of-range value proposes a clamped one, so `on_change` can report a value
  that differs from the stored one even though the display did not move.
- Tabs: `on_change` fires only for user changes that landed; setting the
  signal from code does not call it. Arrow keys skip disabled tabs. Strings in
  `items` stay owned by the caller and must stay valid while they are the
  source's current value.

**Migration.**

```zig
// before
const m = try W.Modal(.{ .title = "Delete?" }).visible(show).mount(scope, cx);
const tabs = try W.Tabs(.{ .items = &items, .default_active_id = "files",
    .on_change = ui.Cx.strHandlerFrom(S, s, S.tab) }).mount(scope, cx);

// after
const m = try W.Modal(.{ .title = "Delete?", .open = show }).mount(scope, cx);
const current = try scope.createSignal(?[]const u8, "files");
const tabs = try W.Tabs(.{ .items = &items, .active = current }).mount(scope, cx);
// programmatic switch: current.set("search");

// Accordion: one section open at a time
const acc = try W.Accordion(.{ .open = 0 }).mount(scope, cx);
for (titles, 0..) |title, i| {
    const it = try W.AccordionItem(.{ .title = title, .expanded = try acc.item(i) }).mount(scope, cx);
    try acc.container.appendChild(cx.allocator, it.item);
}
```

## 2026-10-02: Signal-first props for Checkbox, Switch, Button, Badge, StatusBadge, Progress (BREAKING)

**What changed.** These components take their props through `ui.reactive.props.coerce`
(docs/SIGNAL_API_DESIGN.md): any prop that can change accepts a literal, a
`*Signal(T)`, a `*Memo(T)` or a derived value; values the component writes back on interaction are a `Model` (a controlled value: the
component only proposes, the single source decides, the view follows the source).

| Component | Before | After |
|---|---|---|
| Checkbox | `initial_checked: bool`, `label_text: ?[]const u8`, `on_change: ?HandlerRef` (bool payload), builder `.checked() .label() .disabled() .onChange()`, `state_id` | `checked: Model(bool)` (`bool` / `*Signal(bool)` / `ui.split`), `label: Source([]const u8)`, `indeterminate` / `disabled: Source(bool)`, `on_change: ?Handler(bool)` |
| Switch | same as Checkbox | `checked: Model(bool)`, `label`, `disabled`, `on_change: ?Handler(bool)` |
| Button | `label: ?[]const u8`, builder `.label() .variant() .size() .disabled() .loading() .onClick()` | `label` / `variant` / `loading` / `disabled` are Source; builder methods removed |
| Badge | `text: ?[]const u8`, `count: ?u32`, builder methods | `text` / `count` / `status` / `dot` are Source |
| StatusBadge | `label_text` | `label` (Source), `status` (Source) |
| Progress | builder `.value() .status() …` | `value` / `status` are Source |

`on_change` now receives the value that actually landed (after a `ui.split`
parent transformed it) and fires only for user-initiated changes that changed
the value. Show / For / Match accept memos and derived values.

**Why.** Props were read once at mount; the only way to drive a mounted
component was imperative state access or remounting.

**Behavior to check.** Because props go through `anytype`, a few expressions
lose their result type: `@ptrCast(x)` (pass the pointer directly),
`if (c) .a else .b` (wrap in `@as(Enum, …)`), and decl literals inside a nested
literal such as `.style = .{ .height = .fixed(8) }` (name the type:
`core.StyleOverride{ … }`).

**Migration.**

```zig
// before
const cb = try W.Checkbox(.{ .label_text = "Agree", .initial_checked = true,
    .on_change = ui.Cx.boolHandlerFrom(S, s, S.changed) }).mount(scope, cx);
const btn = try W.Button(.{}).label("Save").disabled(true).mount(scope, cx);

// after
const agree = try scope.createSignal(bool, true);
const cb = try W.Checkbox(.{ .label = "Agree", .checked = agree,
    .on_change = cx.on(S, s, S.changed) }).mount(scope, cx);
const btn = try W.Button(.{ .label = "Save", .disabled = ui.not(agree) }).mount(scope, cx);
```

## 2026-10-01: reactive state only through Scope; host entry points batch (BREAKING)

**What changed.**

- `Cx.createSignal(T, v)` and `Cx.memo(T, ctx, f)` are removed. They allocated
  on the owner arena, could not be freed individually and lived until the `Cx`
  was destroyed. Use the `Scope` you were mounted with.
- The top-level `ui.createEffect` / `ui.createMemo` (owner-level free
  functions) are no longer re-exported. Use `scope.createEffect` /
  `scope.createMemo`. The owner-level primitives remain under `ui.reactive.*`
  as low-level API with no lifetime management.
- Every host entry point on `Cx` (`handleMouse*`, `handleKey*`, IME, scroll,
  magnify, drag, `handleCommand`, `cancelPointerInteractions`,
  `fireDueTimers`, `drainDeferredWork`) and every before-render / after-layout
  hook pass now runs inside an owner batch. Effects triggered by a handler run
  once, when the entry point returns, instead of once per `set()`.

**Why.** Two creation paths with different lifetimes got mixed; and a handler
that set three signals ran each dependent effect three times, two of them on
half-updated state.

**Behavior to check.** Inside a handler, an effect no longer runs synchronously
at `set()`. Code that sets a signal and then, in the same handler, reads a node
or value the effect would have updated now sees the old one. Read the signal
instead, or move the follow-up into the effect.

**Migration.**

```zig
// before
const open = try cx.createSignal(bool, false);
const total = try cx.memo(u32, .{ .a = a }, compute);
try ui.createEffect(cx.owner, ctx, run);

// after
const open = try scope.createSignal(bool, false);
const total = try scope.createMemo(u32, .{ .a = a }, compute);
try scope.createEffect(ctx, run);
```

## 2026-10-01: momentum phase and deterministic ScrollArea state (BREAKING)

**What changed.** `ScrollEvent.is_momentum: bool` is replaced by
`momentum: ui.events.MomentumPhase` (`none | began | changed | ended`); use
`scroll.isMomentum()`. `system_sdk.events.MouseWheel` gets the same field.

`ScrollState` no longer guesses gesture boundaries from frame counts. Removed:
`user_scrolling`, `scroll_idle_frames`, `scroll_event_idle_frames`,
`tail_idle_frames`, `momentum_idle_frames`, `has_scroll_history`,
`is_trackpad_session`, `awaiting_trackpad_reengage`, `phase_end_guard_frames`,
`suppress_outward_momentum_x/y`, `bounce_done_time_x/y`, and the tuning fields
`wheel_release_frames`, `trackpad_reengage_delta_threshold`,
`phase_end_guard_frames`, `idle_residual_delta_threshold`,
`momentum_bonus_tail_cutoff`. Added: `touching`, `momentum_active`,
`momentum_spent_x/y`, `input_serial` and `inputActive()`.

Behavior: a mouse wheel without gesture phases no longer rubber-bands (same as
NSScrollView). Momentum that reaches an edge bounces once; the rest of that
momentum stream does not push outward again. Losing window focus cancels an
in-progress gesture and momentum. A diagonal event on a `.both` ScrollArea that
can scroll only one of its axes goes to the layer of its dominant axis instead
of dropping the other component. `Notifier` cards are swiped by trackpad
gestures only: `ended` commits past the threshold, `cancelled` springs back,
and a mouse wheel no longer swipes (there was a 140 ms silence timeout before).

**Why.** The old state was released by timeouts, and several guards were
frame or millisecond windows. Begin/end signals now exist for gestures and
momentum, so the state follows them directly.

**Migration.**

```zig
// before
const active = ss.user_scrolling or ss.scroll_event_idle_frames <= ScrollState.scroll_tuning.wheel_release_frames;
const momentum = ss.momentum_idle_frames <= 2;
if (scroll.is_momentum) ...

// after
const active = ss.inputActive(); // gesture, momentum or scrollbar drag in progress
const scrolled_this_frame = ss.input_serial != last_seen_serial;
if (scroll.isMomentum()) ...
```

## 2026-10-01: scroll events carry the gesture phase (BREAKING)

**What changed.** `ui.events.ScrollEvent` replaces `phase_ended: bool` and
`is_trackpad: bool` with `phase: ui.events.ScrollPhase`
(`none | may_begin | began | changed | ended | cancelled`). Use
`scroll.phaseEnded()` (ended or cancelled) and `scroll.isTrackpad()` instead of
the old fields. `Cx.handleScrollEx` and `Cx.handleScrollWithModifiers` are
replaced by `Cx.handleScroll(ScrollEvent)` and `Cx.handleSdkWheel(MouseWheel)`.
The SystemSdk `mouse_wheel` event is now `system_sdk.events.MouseWheel` with a
`phase` field.

**Why.** Only `phase_ended` reached the dispatcher, so it could not tell when a
new trackpad gesture began. If an `ended` event was lost, every later trackpad
scroll went to the previous gesture's scroll area. `began` now starts a new
gesture deterministically, and `cancelled` releases it.

**Migration.**

```zig
// before
cx.handleScrollWithModifiers(e.x, e.y, e.dx, e.dy, e.is_momentum, e.phase_ended, e.is_trackpad, mods);
if (scroll.phase_ended) release();
if (scroll.is_trackpad) ...

// after
cx.handleSdkWheel(e); // e: system_sdk.events.MouseWheel
if (scroll.phaseEnded()) release();
if (scroll.isTrackpad()) ...
```

Test harness: `POST /scroll` without `phase` is now a mouse-wheel event. Send
trackpad gestures as a full sequence (`phase: "began"`, `"changed"`...,
`"ended"`), or use `trackpadScroll()` from `e2e/client.ts`.


### LC3A 本机回归修订：明确填充和固定留白

Storybook 的 macOS 工作区过去依赖「有 grow 就不 shrink」及没有 auto-min 的旧行为。
现在视口内的纵向层显式 `flex_basis=0, min_height=0`，横向工作区显式
`flex_basis=0, min_width=0`，侧栏的 216px 留白显式 `flex_shrink=0`。
超长故事在 ScrollArea 内滚动，不能把侧栏留白挤成零；使用相同宿主结构的应用也应
明确这些意图。Notification 的缺节点和重复 test_id 来自按钮被侧栏遮挡、清空/创建操作
没有执行，不需要改变卡片生命周期或放宽卡片尺寸断言。

同样要检查应用挂载到视口宿主的**最外层 root**，不能只约束内部 content/workspace。
Storybook 的 root 也显式 `flex_basis=0, min_height=0`，使纵向填充从零基数分配。
否则长故事的内容 minimum 会撑高整个 root 和 ScrollArea，减少甚至清空可滚动距离。
CornerClip 的 113px 差值来自滚动偏移（内容997、可视内容884），而非 specimen 上方
某个故事块变高；约束 root 后保留原故事尺寸和 GlassRadii 的滚轮路径即可恢复。
无窗口回归应包括这一外层以及初始、滚动、程序化回到顶部的状态。

GlassBox 的内部玻璃表面现在声明 `height = .grow{ .min=0 }`：表面填满外框，内容在
原有 content clip 内剪裁。旧代码依赖 grow 忽略内容 minimum，标题/空 body gap 使
44px 外框下的表面变成45px，带箭头的74.55px外框下变成79.2px。固定装饰表面应显式
允许收缩；若需要按内容扩张，则应在外框使用 fit，而非让表面溢出外框。

Harness 的固定步进/手动预算时钟现在同时屏蔽真实 presentation sample，截图重绘
不能推进 materialize/matched-geometry。正常宿主仍使用 display target。无需迁移应用
动画参数；本轮没有改 e2e 的像素期望、断言或容差。

### 2026-10-21：zeditor 消费方核对

消费应用的 Yix 双胞胎也要用候选框架的生成器更新。zeditor 的入口是
`zig build gen-block-ui`，随后运行 `zig build check-block-ui`；框架根目录的
生成步骤不会更新应用自己的源目录。本轮更新了 16 个应用双胞胎。

列容器中的空状态操作行若要占满横向空间，应显式声明 `align_self = .stretch`，
再由行的 `justify = .center` 居中其固有宽度按钮。zeditor 的 `emptyActionRow`
采用此组合，首帧及侧栏改宽后的回归都检查按钮中心与整个空状态中心一致。
fit-content 弹层的外框高度包含边框；内容高与外框高的断言要计入上下边框，
例如 `content_height + 2 * border.width`，保留原有误差容限。

Button 的显式 `icon_tint` 会覆盖图标继承的前景色。需要正常颜色随禁用状态
变化时，把正常前景放入 `base_style.text_color`，让 ControlShell 的 disabled
tone 覆盖它：

```zig
ui.widgets.Button(.{
    .icon_asset = ui.icons.file_plus_01,
    .base_style = .{ .text_color = normal_tint },
    .disabled = is_disabled,
})
```

禁用视觉验收改为比较实际图标前景，并同时验证禁用时点击无效、启用后点击有效及
tooltip 可见。zeditor 的像素对照先捕获了启用/禁用同色的失败，再通过上述迁移修复。

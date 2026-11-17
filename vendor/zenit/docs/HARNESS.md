# Automation Harness

Zenit's Harness lets an external Bun/TypeScript process inspect and drive a
Zenit application. On macOS it can also record the application's completed
Metal drawable directly to H.264/MP4. The recording contains the native Retina
application content and Zenit's virtual cursor, but not the desktop, title bar,
physical cursor, or macOS screen-sharing indicator.

Harness is developer tooling. It is disabled in normal builds and does not
require Screen Recording permission.

## Build wiring

Zig dependency build options are isolated from the parent project. A consumer
must expose its own options and forward them to Zenit:

```zig
const test_mode =
    b.option(bool, "test-mode", "Enable the Zenit automation harness")
    orelse false;
const e2e_port =
    b.option(u16, "e2e-port", "Zenit Harness RPC directory suffix")
    orelse 19816;

const zenit_dep = b.dependency("zenit", .{
    .target = target,
    .optimize = optimize,
    .@"test-mode" = test_mode,
    .@"e2e-port" = e2e_port,
});

zenit.attach(zenit_dep, exe);
zenit.installHarnessClient(b, zenit_dep);
```

`installHarnessClient` places the typed client at the stable install-prefix
path `share/zenit/harness/client.ts`. With the default prefix, an
`e2e/record.ts` script imports it as:

```ts
import {
  waitForServerReady,
  startWindowRecording,
  stopWindowRecording,
} from "../zig-out/share/zenit/harness/client.ts";
```

## Launch and connect

Build the application with Harness enabled:

```bash
zig build -Dtest-mode=true
```

Give the app and controller the same private file-RPC directory. Use a unique
directory for each concurrently running app:

```bash
rpc_dir="$(mktemp -d /tmp/myapp-e2e.XXXXXX)"
ZENIT_E2E_FILE_RPC_DIR="$rpc_dir" ./zig-out/bin/myapp
```

In another terminal:

```bash
ZENIT_E2E_FILE_RPC_DIR="$rpc_dir" bun run e2e/record.ts
```

The environment variable must be set independently in both terminals. An
alternative is to use the default `/tmp/zenit_e2e_rpc_<e2e-port>` directory.

## Fast Storybook rebuilds

Story selection is independent of Harness mode. With no `-Dstories`, the full
showcase, canonical order and story keys stay unchanged. To compile just the
shell and selected stories, use their existing keys (not display names):

```sh
zig build storybook -Dstories=button,card
zig build storybook-exe -Dstories=button
zig build run-storybook -Dstories=button
```

`storybook` still packages and ad-hoc signs the macOS `.app`.
`storybook-exe` compiles the executable and installs it to `zig-out/bin/`
without bundling, codesigning or starting it; the preview launcher starts it from
there.
`run-storybook` already runs that bare executable directly, skipping bundle
copying, quarantine clearing and `codesign`. On macOS/Linux hosts every example
target also exposes a `<example>-exe` step (Windows uses the `windows-*` steps). The Mach-O linker still emits the signature required for
local execution on Apple Silicon.

Selection preserves registry order and navigation sections. Empty, unknown or
duplicate keys fail compilation. For a Harness-enabled slim build, also pass
`-Dtest-mode=true` and restrict the E2E runner to tests for the selected keys.
Harness remains disabled for ordinary preview builds.

Storybook uses platform fonts and compiled-in SVG icons; its bundle currently
ships no extra fonts, images or app icon. Other applications with custom assets
must still arrange their development resource paths (`ResourcePath` searches
ancestor `assets/` directories, then falls back to the current directory).

For reproducible warm-cache Debug measurements, stop competing builds and run:

```sh
python3 tools/measure_storybook_slim.py --zig /path/to/zig --samples 5 \
  --output /tmp/storybook-slim-measurement
```

The output directory must be new. JSON records the revision, commands, exits,
raw monotonic wall times, nearest-rank p95 and byte-for-byte source restoration.
With a small sample count the nearest-rank p95 is simply the slowest sample; it is
not an estimate of tail latency.
Each iteration changes one Button label to a unique value. Packaged cases also
use a second edit to time exe compilation and cached-exe packaging separately;
those phase measurements each include build orchestration overhead.

## Input isolation on a shared machine

The harness injects input directly into `ui.Cx`, bypassing the OS. Physical
input from a person using the same machine would otherwise race the injected
events: a moved mouse overwrites the injected hover position, and physical
typing reaches the focused control (space toggles a focused checkbox, Enter
submits a focused input). Two opt-in environment variables drop OS input in
test-mode builds only; harness injection and manual operation of a normal
(non-test-mode) app are unaffected:

```bash
ZENIT_E2E_ISOLATE_POINTER=1   # drop OS mouse move/button/wheel/magnify (default in run_storybook_e2e.sh)
ZENIT_E2E_ISOLATE_KEYBOARD=1  # additionally drop OS key / text_input / IME events
```

Pointer isolation also has a `ZENIT_E2E_BACKGROUND`-driven default on the
Windows worker; keyboard isolation is explicit-only. Window focus, resize and
drag-and-drop sessions are never isolated.

On macOS and Windows, keyboard isolation also drops native keyboard events
before menu accelerators, keyboard window-management actions and IME handling.
The gate is per window and is configured only by test-enabled runtimes.
Programmatic menu actions, mouse-driven window controls and contract injection
remain available. This does not lock the OS keyboard or suppress system-wide
shortcuts. Native-message contracts must explicitly seed owned input rather
than relying on OS keyboard messages while isolation is enabled.

## Run the Storybook suite in parallel

`bash scripts/run_storybook_e2e_parallel.sh` builds once and runs the Storybook
suite on several app instances at the same time (`ZENIT_E2E_JOBS`, default
`clamp(cpus / 2, 2, 8)`). Each instance is one ordinary
`scripts/run_storybook_e2e.sh` unit with its own RPC dir, app log, evidence
dir, manifest and session dir, so the app-death watchdog (exit 86), the
exit-time leak gate (exit 87) and the fatal preflight apply per instance. The
merged `summary.json` and `manifest.json` go to `ZENIT_E2E_OUT`; a dead app
outranks a leak, which outranks an assertion failure.

Instances run with `ZENIT_E2E_BACKGROUND=1` and pointer and keyboard isolation:
they never activate, take key focus or order a window front, and every input
arrives through the harness. Each instance's clipboard is a private named
pasteboard (`ZENIT_E2E_PASTEBOARD`, which the sequential script sets too), so
instances cannot read each other's copies and no run overwrites the
developer's clipboard.

Tests declare how they may be scheduled in `test(name, fn, options)`:

- `fatal: true`: preflight, runs first on every instance; a failure aborts it.
- `final: true`: checks an invariant accumulated over the whole instance run
  (the paint invariant), runs last on every instance.
- `serial: "<reason>"`: measures real time or contention (the GPU frame-time
  P95 gates). These run in a lane of their own after every parallel instance
  has exited.

Other tests are spread longest-first using the durations recorded by earlier
runs (`ZENIT_E2E_DURATIONS`, default `~/Library/Caches/zenit-e2e/`), falling
back to `e2e/storybook.durations.json`. Tests must not rely on state left by
earlier tests: `ZENIT_E2E_SHUFFLE_SEED=<n>` shuffles the order, in the
sequential script and per instance in the parallel one; `schedule.json` and
each instance's `plan.json` (replay with `ZENIT_E2E_PLAN`) record what ran
where.

On macOS, `bash scripts/run_storybook_e2e.sh` defaults to background
rendering for `e2e/storybook.test.ts`. Storybook still submits real Metal
frames while another app uses the desktop. Set `ZENIT_E2E_BACKGROUND=0` to
launch the suite in the foreground for inspection. Other test files keep
their requested window mode.

## Select a screenshot window

`GET /windows` returns `{ windows: [{ window_id, native_id, bound, closing }] }`.
`window_id` is a string token for one window instance, unique within a process
session; restarting the app changes the session. `native_id` is a diagnostic
string, not an accepted screenshot identity. Closing and recreating a native
window never reuses its harness identity.

```ts
const { windows: targets } = await windows();
await screenshot("artifacts/secondary.png", targets[1].window_id);
```

The equivalent request is `POST /screenshot` with
`{ "path": "artifacts/secondary.png", "window_id": "<token>" }`. Omitting
`window_id` keeps the currently bound window behavior. An explicit target is
resolved on the UI thread and captured directly from its submitted surface;
it does not activate the window or change the input/tree binding. Windows
capture retains the worker's BMP-to-PNG conversion.

Errors keep the `error` text field and add `code`: `invalid-window-id`,
`window-not-found`, `window-closing`, `no-bound-target`, `capture-unsupported`,
or `capture-failed`. A stale or closing target never falls back to another
window. Successful replies retain `{ "ok": true, "path": "..." }`.
Input, tree inspection, recording, and `frames_*` retain their existing
binding semantics; this selector applies only to screenshots.

## Record the application surface

```ts
import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import {
  waitForServerReady,
  startWindowRecording,
  stopWindowRecording,
  clickTestId,
  sleep,
} from "../zig-out/share/zenit/harness/client.ts";

await waitForServerReady();

const output = resolve("artifacts/run.mp4");
await mkdir(dirname(output), { recursive: true });

const started = await startWindowRecording(output, { fps: 60 });
if (!started.ok) throw new Error(started.error);

let stopped;
try {
  await clickTestId("save-button");
  await sleep(1000);
} finally {
  stopped = await stopWindowRecording();
}

if (!stopped.ok) throw new Error(stopped.error);
console.log(stopped);
```

The output path must be absolute, end in `.mp4`, and have an existing parent
directory. FPS may be 1 through 120. `stopWindowRecording` returns only after
the MP4 is finalized. Do not resize the window during a recording; start a new
recording after a resize instead.

Pointer, text, IME, scroll, and drag Harness commands automatically update the
rendered virtual cursor. Its arrow, pointing-hand, I-beam, pressed, and grabbing
states therefore appear in the video without capturing the physical cursor.

## Paint invariant

In test mode every rendered frame is checked for one node emitting an identical
filled or stroked rectangle twice (same geometry, colour, radius, shape and
stroke width). That is the
signature of a cache-replay path emitting a node's own content a second time:
the extra copy usually lands after the children, so an opaque background covers
them and a translucent one darkens them, for a single frame that screenshot
comparisons do not catch. `/stats` reports the running total as
`paint_duplicate_fills` and the most recent offender as `paint_duplicate_node`;
the storybook suite asserts the total stays 0 after visiting every story, and
the `paintreplay` story reproduces the conditions (an `overflow_hidden`
container with a background and children, outside any scroll area, whose
siblings change). To find the frame and node, rerun with
`ZENIT_DEBUG_CMDSTREAM=1`.

## Hover state

`/stats` includes `hover`: `test_id` is the nearest test id on the hovered
path (or `null`), and `reconcile_hit_tests` / `reconcile_changes` count the
stationary-pointer re-resolutions (hit tests issued, and the ones that moved
hover). `/scroll` does not move the pointer, so a wheel injected at the
pointer position exercises hover following content scrolled under a resting
pointer.
`pointer_over_content` is the platform presence (false after a
`pointer_left` until the next pointer event) and `pointer_live` whether
stationary re-resolution may run (presence, inside the content, no OS drag
session).

Two routes stand in for platform events, through the same `Cx` entries the
runtimes use: `POST /pointer_leave` delivers `pointer_left` (the pointer left
the window, or another window now covers it; `pointerLeave()` in
`e2e/client.ts`), and `POST /window_active {"active": false}` sets the window's
activation appearance (`window_focused.appears_active`; test-mode apps
otherwise always report active; `setWindowActive()`). Real OS input for the
same behavior runs in the Windows `hover-probe` / `hover-native` batch stages
and the Linux `hover-native` stage; on macOS,
`bash scripts/test_native_pointer_presence.sh --live` checks the window server
and `bash scripts/macos_hover_probe.sh` measures AppKit.

## Inspecting text fields

`POST /input_state {"test_id": …}` (`inputState(testId)` in `e2e/client.ts`) reports the edit
state of the Input / Textarea / EditableText under that test id: buffer, caret and anchor (UTF-8
byte offsets, `anchor = -1` without a selection), caret affinity, IME phase and preedit length,
scroll offsets, and for textareas the wrapped line count, caret and selection rects. The
executor finds the first `.input` node with an event context under the test id and asks the
input module which state sits behind it, `ui.widgets.input.editStateOf(node)`, which returns
`?EditState` (`.input: *TextInputState` or `.textarea: *TextareaState`). Tools that inspect a
field (harness, DevTools) must go through `editStateOf` rather than comparing `on_event` handler
pointers and casting the context themselves; a node whose handler the input module did not
install yields `null` (the endpoint answers with an error).

## Runtime integration

Applications using `App.runWith` need no application-code changes. A custom
event loop must call `zenit_app.drainTestCommands()` once per iteration after
processing platform events.

`App.mount` binds Harness to that window. If auxiliary windows are mounted
after the main window, call `main_app.rebindTestHarness()` after creating them
to make the intended main window the automation and recording target.

## Production boundary

Do not pass `-Dtest-mode=true` to release builds. A normal build compiles out
Harness initialization and exposes no file-RPC automation endpoint. The native
recording bridge may still be linked as framework infrastructure, but it is not
registered or reachable without Harness mode.

### Linux native window controls

`POST /window` runs native window operations on the application's UI thread.
The body is `{ "action": "status" }` (default), `maximize`, `restore`, `minimize`,
or `close`. The response reports `decorated`, external `decoration_height`,
compositor `maximized`, `active`, `suspended`, and logical content dimensions.
Requests acknowledge dispatch, not compositor completion: poll status after
maximize/restore. Minimize has no portable Wayland acknowledgement; verify the
compositor image. Close uses the native decoration callback and normal teardown.
Unsupported platforms return an error.

`scripts/run_linux_window_controls.py` uses file RPC plus the GNOME-specific
`scripts/linux_harness_desktop.py` adapter to exercise actual titlebar pointer
input and capture compositor frames (including decorations). The adapter owns
and closes its local Mutter RemoteDesktop/ScreenCast sessions and releases all
held keys/buttons. It does not synthesize application focus or input serials.
This VM acceptance adapter is independent of the portable platform backend.

### Linux native scrolling

On a GNOME Wayland acceptance desktop, build Storybook with Harness enabled and
run `scripts/run_linux_scroll_acceptance.py --binary zig-out/bin/storybook
--evidence-dir /tmp/zenit-native-scroll-run-1`. The evidence directory must be
new. The script starts and normally quits its own application; it requires a
hardware OpenGL renderer and the same Gio/GStreamer/PipeWire dependencies as
the native window-control adapter.

Harness seeds a scroll position and observes geometry and frame statistics.
Measured wheel and finger input comes through the compositor, covering both
directions, fractional wheel detents, finger phases, continuous exact pixel
movement, and a 125Hz burst without interleaved RPC observations. Returned
results include the binary hash, input traces, compositor capture, CPU frame
budget, response/tail times, GPU invariants and exit status.

The VM batch runner's `--stage-group scroll --app-backend opengl` runs this gate
and the native Wayland scroll protocol contract together. `all` includes both.
A failed native/pixel prerequisite explicitly skips the long shared Storybook
suite and leaves the complete batch failed; a skipped suite does not count as
UI acceptance.

### Linux native pinyin regression

Select GNOME's `libpinyin` input source and Chinese mode, then run against a
Harness-enabled hardware OpenGL Storybook:

```sh
python3 scripts/run_linux_native_ime_acceptance.py \
  --binary zig-out/bin/storybook --evidence-dir /tmp/zenit-native-pinyin
```

The test uses Mutter's compositor keyboard and pointer events. It checks Input
preedit/commit, the native clipboard primer, composition cancellation when
switching to Textarea, and Textarea preedit/commit. JSON and compositor captures
are saved together. It never injects Harness IME events or changes the selected
source/mode to force a pass.

Native input priming uses F24. A standalone Shift press toggles libpinyin's
Chinese/English mode while the GNOME input source still says Chinese, leaving
subsequent manual acceptance typing ASCII. Window-control and clipboard tests
must not use standalone Shift for acquiring a keyboard serial.

# Vendored dependencies

## Zenit

- Source: zenit (private repository `hitengr-biz/zenit`), branch `main`.
- Snapshot: recorded in `vendor/zenit.lock.json` (commit, file count, SHA-256). `vendor/zenit` is a
  **pristine** copy of that commit's Zig package files (`build.zig.zon` `.paths`) and is never edited
  by hand.
- Update: `python3 scripts/sync_vendor_zenit.py --source <zenit checkout> --ref <branch|commit>`, then
  build and test. `python3 scripts/verify_vendor_zenit.py [--source <zenit checkout>]` verifies the tree
  against the lock (and optionally re-derives it from the commit).
- Minimum Zig: `0.17.0`. License: GPL-3.0-only (commercial alternative documented upstream).
- Project decision: GPL-3.0-only use authorized for current development; distribution obligations remain active.

### How ZeroWork customizations attach

ZeroWork no longer patches zenit. Its product behavior mounts through public, default-off
extension points on zenit `main`:

| ZeroWork need | zenit extension point | ZeroWork side |
|---|---|---|
| Secure secret panel owns keyboard events | `macos_add/remove_native_event_filter` (`native/macos/zenit_native_event_filter.h`) | `src/platform/macos_host_secret.m` |
| Traffic lights in the sidebar header | `MacOSWindow.setTrafficLightsLayout(x, y, ?diameter)` | `src/main.zig`, `shell_styles.traffic_light_*` |
| Theme = zenit default + ZeroWork tokens | `generateThemeLayers` + `defaultThemePath` (overlay, explicit `$override`) | `src/ui/theme/zerowork.tokens.json` (`zw_*`), `build.zig` |
| Component role colors | none: role tokens (`button_*`, `checkbox_*`, `switch_*`, `range_*`, `progress_*`) and focus (`bg_focus`, `border_focus`, `focus_ring`) are zenit defaults | — |
| Select panel material / scope | `SelectProps.panel_style`, `SelectResult.scope`, `virtualize`, `option_style` | `src/plugins/bmc_ikvm/select_surface.zig`, settings/transfer pickers |
| Accordion parts and app motion | `accordion.stateOf`, `AccordionItemProps.builtin_motion` | `src/config/settings_accordion.zig` |
| Field frame states | `Input/TextareaProps.field_state_style`, `invalid` signal | settings fields (`invalid` signal) |
| Glass sampling a composited preview | `GlassParams.capture_source = .current_surface` | `src/ui/background_layers.zig` |
| Window-scoped structure revision | `World.structure_revision`, `Node.ownedTreeStructureRevision/invalidateTreeStructure` | `src/ui/layer_materials.zig` |
| Exact variable font weights | `FontRegistry.setExactWeight`, `coretext_font_weight_range/value` | `src/config/appearance_font.zig` |
| Checkbox size, progress sweep, virtual list ownership | `CheckboxProps.size/label_font_size`, `ProgressProps.sweep`, `VirtualListProps.translate_content` | call sites |

Generic fixes found during the switch are included in zenit `main` (IME
Return/Escape ownership, Select highlight across rebuilds, retained-menu tooltip reopen, theme
transitions on the publishing window's clock, hooks at a frozen frame clock, explicit cross-axis
fill under `no_cross_stretch`), each with regression tests.

## Ghostty VT

- Upstream: https://github.com/ghostty-org/ghostty
- Vendored revision: `af7fd981e4d9c2af8ab897f5ce86afb982e4e546` (`zig-0.17`)
- Module: `ghostty-vt`; minimum Zig: `0.17.0`; license: MIT.
- ZeroWork uses the public C ABI in `include/ghostty/vt.h` and the pinned
  `libghostty-vt.a` as its sole VT engine. `build.zig` links this archive for the
  application and the consumer tests; the full Ghostty GUI is not a dependency.
- This is a VT consumer snapshot: full-App icons in `images/` and
  `macos/Assets.xcassets/`, and font binaries in `src/font/res/` are omitted.
  These paths are included in upstream `src/build/GhosttyDist.zig`'s
  `lib_vt_excludes`, which identifies resources not needed to build or test VT.
- VT sources, C headers, the static archive, terminal test fixtures and license
  texts are retained. Font attribution and OFL/MIT/BSD notices remain under
  `src/font/res/`; ZeroWork's UI fonts remain under `docs/UI_V3/assets/fonts/`.
- To rebuild VT from upstream sources, use the fixed dependencies declared in
  its `build.zig.zon` and the `-Demit-lib-vt` build mode. Full Ghostty App and
  font-renderer builds require restoring the omitted upstream resources.
  Dependency hash checks must remain enabled when resolving its packages.

Local patch `2026-11-05-erase-display-refs` invalidates C tracked grid
references left in the active area after an unprotected ED2, and history
references before ED3 removes scrollback. References
moved into scrollback by prompt-aware clearing remain valid. This prevents
builtin command cards from reappearing over a cleared terminal, including
cards anchored at the first prompt. Rebuild the pinned static archive with
`zig build -Demit-lib-vt=true -Demit-xcframework=false -Doptimize=ReleaseFast`.

## Planned SSH dependencies

### libssh2

- Tag: `libssh2-1.11.1`
- Revision: `a312b43325e3383c865a87bb1d26cb52e3292641`
- License: BSD-3-Clause
- Status: verified official `libssh2-1.11.1.tar.xz` archive vendored under `vendor/libssh2/`.
- Official archive SHA-256: `9954cb54c4f548198a7cbebad248bdc87dd64bd26185708a294b2b50771e3769`

Local patch `2026-10-27-independent-forward-opens` adds ZeroWork's opaque
direct-tcpip open contexts in `src/channel.c`, and keeps replies for other
channels queued while matching a response in `src/packet.c`. Each pending target retains its
own channel-open/reply state; the transport, native channel registry and IO
thread remain shared. This prevents an unresponsive target from blocking other
forwarding targets or RTT samples. Context buffers remain owned until native
completion or the parent Session's actual release. The upstream revision,
crypto backend and license are unchanged; `scripts/build_ssh_deps.sh` rebuilds
the patched source into the static library.

Local patch `2026-10-28-channel-close-reply` keeps `_libssh2_channel_close`
reading after unrelated positive packet results until the matching channel's
CLOSE arrives or transport IO would block. An EOF or a sibling's data packet
must not be treated as the close acknowledgement and release ownership early.
The delayed-close RTT fixture covers this together with preserving the measured
RTT while native cleanup is still pending.

Local patch `2026-10-28-bounded-channel-dispatch` caps each channel
read/write/forward-accept input drain and close-acknowledgement drain at 32
transport packets. At the limit it yields EAGAIN, retaining queued packets
and the pending close state. A continuously readable sibling cannot monopolize
the shared IO owner. `scripts/test_ssh_native.sh` feeds an endless stream of
valid IGNORE packets through these native entry points and verifies bounded
return without falsely acknowledging close. A read-only native write-state query
distinguishes a pinned send from a zero-window wait, allowing cancelled forwards
to close without waiting for the peer to grant more data window. The production mixed-load fixture
is `e2e/ssh_mixed_load.py` (PTY + SFTP + 16 forwarded channels, delayed close).

Local patch `2026-10-28-ssh-hardening`:

- Backports the READLINK/REALPATH string-length bound from upstream
  [2dae3024897e1898d389835151f4e9606227721d](https://github.com/libssh2/libssh2/commit/2dae3024897e1898d389835151f4e9606227721d)
  into the existing 1.11.1 parser (its minimum packet-size guard is retained).
- Backports the full-packet cipher length bound from upstream
  [97acf3dfda80c91c3a8c9f2372546301d4a1a7a8](https://github.com/libssh2/libssh2/commit/97acf3dfda80c91c3a8c9f2372546301d4a1a7a8).
- Corrects the Mbed TLS cipher encrypt/decrypt direction and disables its PKCS#7 padding for SSH CBC, which already has protocol
  padding; rejects any cipher output length different from the input buffer.
  This local correction is covered by NIST CBC known-answer/segmented roundtrip and actual
  loopback CBC-only negotiation, as well as normal CTR peers.
- Exposes a read-only authenticated packet sequence accessor to the owning
  worker for liveness detection. No payload, new crypto backend or library
  replacement is introduced.

`scripts/build_ssh_deps.sh` writes an ignored local receipt binding vendored
source content, build scripts, compiler/SDK, environment options, generated
configuration and both static archives. Every application/test/runner link
against SSH depends on `scripts/verify_ssh_deps.py`; stale or missing artifacts
fail with a rebuild instruction. `zig build verify-ssh-deps` checks explicitly.

### Mbed TLS

- Tag: `v3.6.7` / release `mbedtls-3.6.7`
- Revision: `068ff080b369adfac81509f9b57b2afabaf82dc5`
- Official archive SHA-256: `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`
- License choice: Apache-2.0
- Status: verified official `mbedtls-3.6.7.tar.bz2` archive vendored under `vendor/mbedtls/`.

## MCP JSON Schema

MCP schema validation embeds Ajv 8.20.0 and ajv-formats 3.0.1 (MIT) and their pinned JavaScript runtime
dependencies in `src/ai/vendor/mcp_schema.js`. The app executes it using the
system JavaScriptCore framework, without Node/npm or remote code downloads.
Sources, exact dependency versions, regeneration instructions and bundled
license notices are in `vendor/mcp-json-schema/`. Packaging copies those
notices into `Contents/Resources/MCP-JSON-Schema-Licenses`.

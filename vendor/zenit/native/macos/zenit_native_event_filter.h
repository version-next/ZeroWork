// Public macOS extension point: observe or claim AppKit events before zenit
// routes them to its windows.
//
// The zenit event pump dequeues every NSEvent itself and routes it to a zenit
// window (keyboard to the key/fallback window, never through -[NSApp
// sendEvent:]). An application that shows its own native window on top, for
// example a secure-input NSPanel, can register a filter here to take events
// first: return non-zero after handling the event (typically
// `[panel sendEvent:event]`) and zenit drops it; return 0 and routing is
// unchanged. With no filter registered the pump behaves exactly as before.
//
// Contract:
// - Main thread only. add returns 0 when called off the main thread; remove
//   off the main thread is ignored.
// - Filters run in registration order for each dequeued event except zenit's
//   own wake events, before window routing, keyboard isolation, menu key
//   equivalents and IME handling. The first filter returning non-zero stops
//   the chain.
// - `ns_event` is an `NSEvent *` borrowed for the duration of the call
//   (`(__bridge NSEvent *)ns_event`); retain it to keep it.
// - Registration is a set keyed by (fn, ctx): adding an existing pair returns
//   1 without duplicating it. Capacity is fixed (no allocation); add returns 0
//   when full.
// - Reentrancy: a filter may add or remove filters (including itself) from
//   its callback. A filter removed during dispatch is not called afterwards,
//   even for the current event; a filter added during dispatch first sees the
//   next event.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*ZenitMacEventFilter)(void *ctx, void *ns_event); // non-zero = consumed

#define ZENIT_MAC_EVENT_FILTER_CAPACITY 8

int macos_add_native_event_filter(ZenitMacEventFilter fn, void *ctx); // 1 on success
void macos_remove_native_event_filter(ZenitMacEventFilter fn, void *ctx);

#ifdef __cplusplus
}
#endif

//! Byte marker that proves a binary is a `-Dtest-mode=true` build.
//!
//! Launch guards (e2e/regression/build_mode_guard.mjs, build_mode_guard.py and
//! tools/binary_guard/check_test_hooks.zig) scan the file for `text` before
//! starting it and never execute an unverified binary to ask: a formal build
//! ignores unknown arguments and reads the real home directory.
//!
//! Roots export `bytes` only in test-mode builds (src/main.zig, src/preview.zig,
//! src/acceptance.zig; the test-only updater roots in src/update/ carry their
//! own copy because a module root cannot import outside its directory). A
//! formal build never references this file, so the text is absent from it.
pub const text = "ZEROWORK_BUILD_MODE=test-mode";
pub const symbol = "zerowork_build_mode_marker";
pub const bytes: [text.len:0]u8 = text.*;

// Linked only into the Zig test binaries (build.zig: unit, UI and local test modules).
//
// Zig's test runner keeps the environ array it received at exec (std.testing.io scans it
// lazily at the first std.process spawn and builds every child's envp from it). Many tests
// change ZDOTDIR / HOME / ZEROWORK_DATA_DIR with libc setenv / unsetenv and restore them.
// While libc still uses that same exec array, those calls rewrite it in place and later free
// the strings they installed, so the array Zig holds ends up pointing at freed memory:
// the first spawn afterwards panics in std.Io.Threaded scan ("start index N is larger than
// end index N-1") or hands garbage to the child. Whether it happens depends on the size and
// order of the inherited environment, so it showed up only under some shells.
//
// Adding one new variable before main makes libc move to its own malloc'd copy of the array
// (macOS setenv allocates a new array when environ is not one it allocated). From then on
// test mutations only touch libc's copy; the exec array Zig holds stays intact for the whole
// run. Tests that need a child to see a mutated variable already spawn through libc
// (darwin_process.c posix_spawn with the current environ), which is unaffected.
#include <stdlib.h>

__attribute__((constructor)) static void zerowork_test_detach_environ(void) {
    setenv("ZEROWORK_TEST_ENVIRON_DETACHED", "1", 1);
}

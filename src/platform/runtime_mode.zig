//! Automation instrumentation is a build-time choice, never a user setting.
const builtin = @import("builtin");
const root = @import("root");
pub const automation = builtin.is_test or (@hasDecl(root, "application_test_mode") and root.application_test_mode);
/// Builds that must never derive paths from the real account: unit tests,
/// -Dtest-mode=true executables, and preview/fixture/acceptance roots that
/// declare `zerowork_isolated_home = true`. Formal builds are never isolated.
pub const isolated_home = automation or (@hasDecl(root, "zerowork_isolated_home") and root.zerowork_isolated_home);

//! Standalone contract probe compiled with the same defaults as a formal App.
//! No filesystem writes or native Keychain access.
const std = @import("std");
const Paths = @import("../../config/paths.zig").Paths;
const providers = @import("../../ai/provider_config.zig");
const Config = @import("../../config/config.zig");
/// This probe stands in for a formal App, so it opts out of the isolation
/// that src/acceptance.zig gives every other runner.
pub const zerowork_isolated_home = false;

pub fn main() !void {
    const a = std.heap.c_allocator;
    if (@import("../runtime_mode.zig").automation) return error.UnexpectedAutomation;
    const framework = @import("formal_environment");
    inline for (.{ "ZENIT_NO_BLUR", "ZENIT_DISABLE_SCROLL_CLIP", "ZENIT_A11Y_PREFS", "ZENIT_RENDER_SCALE", "ZENIT_E2E_BACKGROUND", "ZENIT_VISUAL_QUALITY", "ZENIT_INPUT_DEBUG" }) |name| {
        if (framework.has(name) or framework.getRaw(name) != null or framework.getBorrowed(name) != null) return error.EnvironmentChangedFramework;
        if (framework.getOwned(a, name)) |value| {
            a.free(value);
            return error.EnvironmentChangedFramework;
        } else |err| if (err != error.EnvironmentVariableNotFound) return err;
    }
    // Formal builds have no home override. The build step runs this probe with
    // HOME, CFFIXED_USER_HOME, ZEROWORK_DATA_DIR and ZEROWORK_TEST_HOME pointed
    // elsewhere; every path must still be the passwd home, joined exactly as
    // the code before platform/user_dirs.zig did.
    const user_dirs = @import("../user_dirs.zig");
    if (user_dirs.isolated or !user_dirs.writes_user_preferences) return error.FormalBuildIsolated;
    const home = try passwdHome(a);
    defer a.free(home);
    const resolved = try user_dirs.home(a);
    defer a.free(resolved);
    if (!std.mem.eql(u8, resolved, home)) return error.EnvironmentChangedHome;
    if (std.c.getenv("HOME")) |value| if (std.mem.eql(u8, std.mem.span(value), home)) return error.ProbeEnvironmentNotOverridden;
    var actual = try Paths.forApplication(a);
    defer actual.deinit();
    const Expected = struct { field: []const u8, value: []const u8 };
    const legacy = [_]Expected{
        .{ .field = "directory", .value = try std.fs.path.join(a, &.{ home, "Library", "Application Support", "com.zerowork.app" }) },
        .{ .field = "config", .value = try std.fs.path.join(a, &.{ home, "Library", "Application Support", "com.zerowork.app", "config.toml" }) },
        .{ .field = "hosts", .value = try std.fs.path.join(a, &.{ home, "Library", "Application Support", "com.zerowork.app", "hosts.toml" }) },
        .{ .field = "known_hosts", .value = try std.fs.path.join(a, &.{ home, ".ssh", "known_hosts" }) },
        .{ .field = "cache_directory", .value = try std.fs.path.join(a, &.{ home, "Library", "Caches", "com.zerowork.app" }) },
        .{ .field = "diagnostic_directory", .value = try std.fs.path.join(a, &.{ home, "Library", "Logs", "com.zerowork.app" }) },
    };
    defer for (legacy) |entry| a.free(entry.value);
    if (actual.is_override or !std.mem.eql(u8, actual.home_directory.?, home) or !std.mem.eql(u8, actual.legacy_directory.?, try std.fmt.bufPrint(&legacy_buffer, "{s}/.zerowork", .{home}))) return error.EnvironmentChangedPaths;
    inline for (.{ "directory", "config", "hosts", "known_hosts", "cache_directory", "diagnostic_directory" }, 0..) |field, i| {
        if (!std.mem.eql(u8, legacy[i].field, field) or !std.mem.eql(u8, @field(actual, field), legacy[i].value)) return error.EnvironmentChangedPaths;
    }
    const downloads = try user_dirs.downloads(a);
    defer a.free(downloads);
    const preferences = try user_dirs.preferences(a);
    defer a.free(preferences);
    const local_cwd = (try @import("../../local/native.zig").cwdZ(a, null)).?;
    defer a.free(local_cwd);
    if (!std.mem.eql(u8, downloads, try std.fmt.bufPrint(&legacy_buffer, "{s}/Downloads", .{home})) or
        !std.mem.eql(u8, preferences, try std.fmt.bufPrint(&legacy_buffer, "{s}/Library/Preferences", .{home})) or
        !std.mem.eql(u8, local_cwd, home)) return error.EnvironmentChangedPaths;

    var models = [_]Config.AiModel{.{ .id = "saved-model", .context_window = 32768, .default = true }};
    var saved = [_]Config.AiProvider{.{ .name = "saved-provider", .kind = .openai_compat, .enabled = true, .endpoint = "http://127.0.0.1:1/v1/chat/completions", .api_key = "saved-fixture-key", .model_count = 1, .models = &models }};
    const ai: Config.Ai = .{ .default_provider = "saved-provider", .provider_count = 1, .providers = &saved };
    const selected = try providers.fromSettings(ai);
    if (!std.mem.eql(u8, selected.model, "saved-model") or
        !std.mem.eql(u8, selected.endpoint, saved[0].endpoint) or
        !std.mem.eql(u8, selected.auth.value().?, "saved-fixture-key") or
        selected.context_window != 32768) return error.EnvironmentChangedProvider;
    saved[0].api_key = "";
    // The explicit loopback gateway policy permits no-auth. This must not
    // acquire an implicit credential from the process environment.
    if ((try providers.fromSettings(ai)).auth != .none) return error.UnexpectedImplicitCredential;
    saved[0].endpoint = "https://example.test/v1/chat/completions";
    if (providers.fromSettings(ai)) |_| return error.UnexpectedImplicitCredential else |err| {
        if (err != error.MissingApiKey) return err;
    }
    std.debug.print("PASS: formal home is the passwd record; HOME/CFFIXED_USER_HOME/ZEROWORK_DATA_DIR/ZEROWORK_TEST_HOME do not move data, cache, logs, known_hosts, legacy, downloads, preferences or the local terminal directory\n", .{});
    std.debug.print("PASS: formal defaults use the system account and explicit App settings; missing credentials never fall back; framework overrides are disabled\n", .{});
}

var legacy_buffer: [std.c.PATH_MAX]u8 = undefined;

/// Independent of platform/user_dirs.zig: the account home as the pre-refactor
/// platform/account.zig read it.
fn passwdHome(a: std.mem.Allocator) ![]u8 {
    var record: std.c.passwd = undefined;
    var result: ?*std.c.passwd = null;
    var buffer: [16 * 1024]u8 = undefined;
    if (std.c.getpwuid_r(std.c.getuid(), &record, &buffer, buffer.len, &result) != 0 or result == null) return error.HomeUnavailable;
    return a.dupe(u8, std.mem.span(record.dir.?));
}

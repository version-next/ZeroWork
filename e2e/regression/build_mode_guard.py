"""Test-mode launch guard for Python e2e scripts (teardown-guard).

Same rule as build_mode_guard.mjs: before starting a ZeroWork binary (the app, a
preview / fixture / runner, the updater, or an .app bundle that wraps one), read
the file and require the marker only -Dtest-mode=true builds contain
(src/platform/build_mode_marker.zig). The binary is never executed to ask: a
formal build reads only the real home directory.
"""
from pathlib import Path

TEST_MODE_MARKER = b'ZEROWORK_BUILD_MODE=test-mode'
# Zig's test runner (lib/compiler/test_runner.zig) is linked only into `zig build test*` binaries,
# never into the app or a preview / runner, so these bytes identify an exported Zig test binary.
# All Zig test binaries are builtin.is_test builds and isolate their home directory
# (docs/ui-revamp/HOME_ISOLATION.md), like -Dtest-mode=true builds.
ZIG_TEST_RUNNER_MARKER = b'internal test runner failure'


class BuildModeError(RuntimeError):
    pass


def assert_runner_binary(path, how='start'):
    """For scripts that start an acceptance runner or an exported Zig test binary (`--runner` /
    `--binary`): accept a -Dtest-mode=true build or a Zig test binary, refuse everything else."""
    return assert_test_mode_binary(path, how, allow_zig_test=True)


def assert_test_mode_binary(path, how='start', allow_zig_test=False):
    """Return the resolved path, or raise BuildModeError unless it is a test-mode build."""
    p = Path(path).resolve()
    if p.suffix == '.app' and p.is_dir():
        targets = [x for x in (p / 'Contents/MacOS').iterdir() if x.is_file()]
    else:
        targets = [p]
    if not targets:
        raise BuildModeError(f'[build_mode_guard] refusing to {how} {p}: the bundle has no executable')
    for target in targets:
        if not target.is_file():
            why = 'the file does not exist'
        else:
            data = target.read_bytes()
            if data[:4] not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
                why = 'it is not a Mach-O executable'
            elif TEST_MODE_MARKER in data:
                continue
            elif allow_zig_test and ZIG_TEST_RUNNER_MARKER in data:
                continue
            else:
                why = f'the build-mode marker "{TEST_MODE_MARKER.decode()}" is missing - this is a formal build'
        raise BuildModeError(
            f'[build_mode_guard] refusing to {how} {target}: {why}. Formal builds only read the real home '
            'directory (HOME overrides do not apply). Build with `zig build -Dtest-mode=true --prefix <private dir>` '
            'and pass that binary; never launch zig-out or a --prefix ...-formal install from an e2e.')
    return p

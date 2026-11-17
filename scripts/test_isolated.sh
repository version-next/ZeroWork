#!/bin/sh
# Test recordings and configuration must never enter the user's App data.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TASK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zerowork-unit.XXXXXX")
TASK_DIR=$(CDPATH= cd -- "$TASK_DIR" && pwd -P)
trap 'rm -rf "$TASK_DIR"' EXIT HUP INT TERM
cd "$ROOT"
if [ "$#" -eq 0 ]; then set -- test test-ui; fi
# Test builds take every home-derived path from a private HOME and refuse the
# real account (docs/ui-revamp/HOME_ISOLATION.md). Keep Zig's global cache
# where it was before HOME moves.
ZIG_GLOBAL_CACHE_DIR=${ZIG_GLOBAL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zig}
mkdir -m 700 "$TASK_DIR/home" "$TASK_DIR/tmp"
HOME="$TASK_DIR/home" CFFIXED_USER_HOME="$TASK_DIR/home" TMPDIR="$TASK_DIR/tmp/" ZIG_GLOBAL_CACHE_DIR="$ZIG_GLOBAL_CACHE_DIR" \
  ZEROWORK_DATA_DIR="$TASK_DIR/data" zig build "$@"

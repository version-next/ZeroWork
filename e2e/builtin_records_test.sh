#!/bin/sh
# Standalone tests need no UI aggregator, network, external service or app UI.
set -eu
cd "$(dirname "$0")/.."
zig build test-builtin-records

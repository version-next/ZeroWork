#!/usr/bin/env bash
# Live native reference → production window captures → regional diff + E2E.
# Any missing reference, window crash, or failed metric fails the gate.
set -euo pipefail
cd "$(dirname "$0")/.."
EVIDENCE="${ZENIT_GLASS_EVIDENCE_DIR:-$(pwd)/reports/glass-native-fidelity}"
export ZENIT_GLASS_GATE_RUN_ID="$(uuidgen)"
mkdir -p "$EVIDENCE"
# Every run gets fresh captures: stale success metadata must never be reused.
rm -rf "$EVIDENCE/native" "$EVIDENCE/zenit" "$EVIDENCE/diff" "$EVIDENCE/playwright" "$EVIDENCE/native-motion" \
  "$EVIDENCE/probe-run" "$EVIDENCE/storybook-regressions" "$EVIDENCE/storybook-flicker"
rm -f "$EVIDENCE/comparison.json" "$EVIDENCE/report.html" "$EVIDENCE/review.html" "$EVIDENCE/pixelmatch.json" "$EVIDENCE/pixelmatch.html" "$EVIDENCE/gate-status.json" "$EVIDENCE/capture-retries.json"
test -d e2e/node_modules/@playwright/test || bun install --cwd e2e --frozen-lockfile
zig build -Dtest-mode=true glass-reference-probe storybook
bun e2e/glass-fixtures.ts "$EVIDENCE/fixtures"
mkdir -p "$EVIDENCE/swift-cache"
xcrun swift -module-cache-path "$EVIDENCE/swift-cache" e2e/glass_text_fixture.swift "$EVIDENCE/fixtures"
xcrun swiftc -parse-as-library -module-cache-path "$EVIDENCE/swift-cache" \
  e2e/native_liquid_glass.swift -o "$EVIDENCE/native-reference"
xcrun swiftc -parse-as-library -module-cache-path "$EVIDENCE/swift-cache" \
  e2e/native_glass_motion.swift -o "$EVIDENCE/native-motion-capture"
"$EVIDENCE/native-reference" "$EVIDENCE/fixtures" "$EVIDENCE/native" >"$EVIDENCE/native.log" 2>&1
status=0
ZENIT_E2E_SKIP_BUILD=1 ZENIT_GLASS_FIXTURES="$EVIDENCE/fixtures" \
  ZENIT_GLASS_ACTUAL="$EVIDENCE/zenit" \
  ZENIT_E2E_APP='zig-out/Glass Reference Probe.app/Contents/MacOS/glass_reference_probe' \
  ZENIT_E2E_TEST_FILE=e2e/glass-reference-capture.test.ts \
  ZENIT_E2E_APP_LOG="$EVIDENCE/probe-app.log" \
  ZENIT_E2E_EVIDENCE_DIR="$EVIDENCE/probe-run" \
  bash scripts/run_storybook_e2e.sh >"$EVIDENCE/probe.log" 2>&1 || status=1
bun e2e/glass-fidelity.ts "$EVIDENCE" >"$EVIDENCE/comparison.log" 2>&1 || status=1
(cd e2e && ZENIT_GLASS_EVIDENCE_DIR="$EVIDENCE" bun run glass:pixelmatch) >"$EVIDENCE/pixelmatch.log" 2>&1 || status=1
bun e2e/glass-pixelmatch-report.ts "$EVIDENCE" >"$EVIDENCE/pixelmatch-summary.log" 2>&1 || status=1
mkdir -p "$EVIDENCE/native-motion"
for action in scroll drag morph hover_press_release; do
  "$EVIDENCE/native-motion-capture" native "$action" "$EVIDENCE/fixtures" "$EVIDENCE/native-motion/swiftui/$action" \
    >>"$EVIDENCE/native-motion/native.log" 2>&1 || status=1
done
# Match native's independent app instance for each action. Stateful fixture
# reconfiguration must not become an undocumented extra test on only one side.
for action in scroll drag morph hover_press_release; do
  ZENIT_E2E_SKIP_BUILD=1 ZENIT_GLASS_ROOT="$EVIDENCE" ZENIT_GLASS_FIXTURES="$EVIDENCE/fixtures" \
    ZENIT_GLASS_MOTION_ACTIONS="$action" \
    ZENIT_E2E_APP='zig-out/Glass Reference Probe.app/Contents/MacOS/glass_reference_probe' \
    ZENIT_E2E_TEST_FILE=e2e/glass-motion-capture.test.ts \
    ZENIT_E2E_APP_LOG="$EVIDENCE/native-motion/$action-app.log" \
    ZENIT_E2E_EVIDENCE_DIR="$EVIDENCE/native-motion/probe-run/$action" \
    bash scripts/run_storybook_e2e.sh >>"$EVIDENCE/native-motion/probe.log" 2>&1 || status=1
done
bun e2e/glass-motion-compare.ts "$EVIDENCE" >"$EVIDENCE/native-motion/comparison.log" 2>&1 || status=1
(cd e2e && ZENIT_GLASS_EVIDENCE_DIR="$EVIDENCE/native-motion" \
  ZENIT_GLASS_COMPARISON_CONTRACT="$EVIDENCE/native-motion/snapshots.contract.json" bun run glass:pixelmatch) \
  >"$EVIDENCE/native-motion/pixelmatch.log" 2>&1 || status=1
ZENIT_GLASS_COMPARISON_CONTRACT="$EVIDENCE/native-motion/snapshots.contract.json" \
  bun e2e/glass-pixelmatch-report.ts "$EVIDENCE/native-motion" >"$EVIDENCE/native-motion/pixelmatch-summary.log" 2>&1 || status=1
bun e2e/glass-motion-finalize.ts "$EVIDENCE" >"$EVIDENCE/native-motion/finalize.log" 2>&1 || status=1
ZENIT_E2E_SKIP_BUILD=1 ZENIT_E2E_FILTER='GlassMotion|GlassChrome|GlassEdge|GlassIslands|GlassLab: real|GlassBox: hover' \
  ZENIT_E2E_APP_LOG="$EVIDENCE/storybook-app.log" \
  ZENIT_E2E_EVIDENCE_DIR="$EVIDENCE/storybook-regressions" \
  bash scripts/run_storybook_e2e.sh >"$EVIDENCE/storybook.log" 2>&1 || status=1
ZENIT_E2E_SKIP_BUILD=1 ZENIT_E2E_TEST_FILE=e2e/glasslab-scroll-flicker.test.ts \
  ZENIT_E2E_APP_LOG="$EVIDENCE/flicker-app.log" \
  ZENIT_E2E_EVIDENCE_DIR="$EVIDENCE/storybook-flicker" \
  bash scripts/run_storybook_e2e.sh >"$EVIDENCE/flicker.log" 2>&1 || status=1
cat "$EVIDENCE/comparison.log"
cat "$EVIDENCE/pixelmatch-summary.log"
bun e2e/glass-gate-status.ts "$EVIDENCE" >"$EVIDENCE/gate-status.log" 2>&1 || status=1
cat "$EVIDENCE/gate-status.log"
bun e2e/glass-review-report.ts "$EVIDENCE" || status=1
if (( status == 0 )); then
  echo "PASS: all required native material, Playwright, window interaction and timestamped motion checks."
  echo "A passing gate establishes similarity within its recorded tolerances, never exact 1:1 reproduction."
else
  echo "FAIL: native glass acceptance; see $EVIDENCE/review.html" >&2
fi
exit "$status"

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/docs/refactor_metrics_latest.md}"

cd "$ROOT_DIR"

collect_lines_for_dir() {
    local dir_path="$1"
    if [[ -d "$dir_path" ]]; then
        find "$dir_path" -type f -name "*.lua" -print0 | xargs -0 cat | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

count_pattern() {
    local pattern="$1"
    local paths=(core fishing audio buff ui DreamFisher.lua)
    grep -RhoE "$pattern" "${paths[@]}" 2>/dev/null | wc -l | tr -d ' '
}

RUNSTAMP="$(date -u +"%Y-%m-%d %H:%M:%SZ")"

# P6A: module dependency count
REQUIRE_API_CALLS="$(count_pattern 'Require[A-Za-z]+API\s*\(')"
GET_API_CALLS="$(count_pattern 'Get[A-Za-z]+API\s*\(')"
DIRECT_MODULE_REFS="$(count_pattern 'addon\.(fishing|audio|alerts|uiFocus)')"

# P6B: test runtime
TEST_LOG="$(mktemp)"
TEST_START_NS="$(date +%s%N)"
if ./scripts/run_tests.sh >"$TEST_LOG" 2>&1; then
    TEST_STATUS="pass"
else
    TEST_STATUS="fail"
fi
TEST_END_NS="$(date +%s%N)"
TEST_RUNTIME_MS="$(((TEST_END_NS - TEST_START_NS) / 1000000))"

PASS_COUNT="$(grep -c '^PASS:' "$TEST_LOG" || true)"
FAIL_COUNT="$(grep -c '^\[FAIL\]' "$TEST_LOG" || true)"

# P6C: per-module size (line count)
CORE_LINES="$(collect_lines_for_dir core)"
FISHING_LINES="$(collect_lines_for_dir fishing)"
AUDIO_LINES="$(collect_lines_for_dir audio)"
BUFF_LINES="$(collect_lines_for_dir buff)"
UI_LINES="$(collect_lines_for_dir ui)"
TOTAL_LINES="$((CORE_LINES + FISHING_LINES + AUDIO_LINES + BUFF_LINES + UI_LINES))"

cat >"$OUTPUT_PATH" <<EOF
# DreamFisher Refactor Metrics

Generated: $RUNSTAMP

## Phase 6A: Module Dependency Count

| Metric | Value |
|---|---:|
| Require*API calls | $REQUIRE_API_CALLS |
| Get*API calls | $GET_API_CALLS |
| Direct module refs (addon.fishing/audio/alerts/uiFocus) | $DIRECT_MODULE_REFS |

## Phase 6B: Test Runtime

| Metric | Value |
|---|---:|
| Test suite status | $TEST_STATUS |
| Test runtime (ms) | $TEST_RUNTIME_MS |
| PASS lines | $PASS_COUNT |
| FAIL lines | $FAIL_COUNT |

## Phase 6C: Per-Module Size (Lua LOC)

| Module | LOC |
|---|---:|
| core | $CORE_LINES |
| fishing | $FISHING_LINES |
| audio | $AUDIO_LINES |
| buff | $BUFF_LINES |
| ui | $UI_LINES |
| total | $TOTAL_LINES |

EOF

rm -f "$TEST_LOG"

echo "Wrote metrics report: $OUTPUT_PATH"

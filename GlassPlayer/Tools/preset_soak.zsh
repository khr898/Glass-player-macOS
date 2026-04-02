#!/bin/zsh
set -euo pipefail

APP="/Users/kaveenhimash/Projects/Glass-player-macOS/GlassPlayer/build/baseline/Glass Player.app/Contents/MacOS/Glass Player"
VID="/Users/kaveenhimash/Projects/Glass-player-macOS/TestVideos/test_pattern_1080p.mp4"
SUMMARY="/tmp/glass_preset_soak_summary2.log"

: > "$SUMMARY"

presets=(
  "Mode A (Fast)"
  "Mode B (Fast)"
  "Mode C (Fast)"
  "Mode A+A (Fast)"
  "Mode B+B (Fast)"
  "Mode C+A (Fast)"
  "Mode A (HQ)"
  "Mode B (HQ)"
  "Mode C (HQ)"
  "Mode A+A (HQ)"
  "Mode B+B (HQ)"
  "Mode C+A (HQ)"
)

for P in "${presets[@]}"; do
  SAFE_NAME="${P//[^A-Za-z0-9]/_}"
  LOG="/tmp/glass_${SAFE_NAME}.log"
  rm -f "$LOG"

  echo "=== TEST: $P ===" >> "$SUMMARY"

  "$APP" --anime4k "$P" "$VID" > "$LOG" 2>&1 &
  PID=$!
  sleep 12

  if kill -0 "$PID" 2>/dev/null; then
    echo "status=alive_after_12s" >> "$SUMMARY"
    kill "$PID" 2>/dev/null || true
  else
    echo "status=exited_early" >> "$SUMMARY"
  fi
  wait "$PID" 2>/dev/null || true

  ACT_LINE=$(grep -m1 "Activated preset:" "$LOG" || true)
  APPLIED_LINE=$(grep -m1 "SUCCESS: Applied Metal Anime4K preset:" "$LOG" || true)
  ERROR_LINE=$(grep -m1 -E "ERROR:|EXC_|Fatal|abort|Terminating" "$LOG" || true)

  if [[ -n "$ACT_LINE" ]]; then
    ACT_VALUE="${ACT_LINE#*Activated preset: }"
    echo "activated=$ACT_VALUE" >> "$SUMMARY"
  else
    echo "activated=none" >> "$SUMMARY"
  fi

  if [[ -n "$APPLIED_LINE" ]]; then
    APPLIED_VALUE="${APPLIED_LINE#*SUCCESS: Applied Metal Anime4K preset: }"
    echo "applied=$APPLIED_VALUE" >> "$SUMMARY"
  fi

  if [[ -n "$ERROR_LINE" ]]; then
    echo "errors=$ERROR_LINE" >> "$SUMMARY"
  fi

  echo "" >> "$SUMMARY"
  sleep 1
done

cat "$SUMMARY"

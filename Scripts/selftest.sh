#!/bin/bash
# Runs RetroEQ's live self-test: quits the running app, drives its menu items,
# measures EQ gain on tones played through the system audio tap, hides the window,
# measures again, restores the user's settings, then relaunches the app.
set -uo pipefail
APP="${1:-/Applications/RetroEQ.app}"
OUT="$(mktemp -t retroeq-selftest)"

was_running=0
if pgrep -x RetroEQ >/dev/null; then
  was_running=1
  osascript -e 'quit app "RetroEQ"' 2>/dev/null || pkill -x RetroEQ
  for _ in $(seq 1 20); do pgrep -x RetroEQ >/dev/null || break; sleep 0.25; done
fi

echo "Running self-test (plays quiet tones for about 15 seconds)..."
open -W -n --env RETROEQ_SELFTEST=1 --stdout "$OUT" --stderr "$OUT" "$APP"
cat "$OUT"
grep -q "SELFTEST PASSED" "$OUT"; status=$?
rm -f "$OUT"

[ "$was_running" = 1 ] && open "$APP"
exit $status

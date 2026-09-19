#!/bin/bash
# Behaviour tests for the Ken Burns engine (v3.0: duration, maxZoom, direction).
#
# They read the plugin's own pose trace (a bounded 60 s trace started on every
# config load) out of the journal instead of taking screenshots: the trace
# prints the exact properties the window consumes, so the assertions are
# deterministic and immune to whatever window happens to have focus -- this
# desktop belongs to a human, and a suite that needs it idle is a suite that
# fails for the wrong reason.
#
# Each scenario only rewrites the settings file; the running service picks it up
# through its FileView watcher, so no shell restart is involved.
#
#   ./tests/pose.test.sh                all scenarios
#   ONLY=loop ./tests/pose.test.sh      one scenario (used for a quick RED)
set -uo pipefail
cd "$(dirname "$0")/.."

SETTINGS="$HOME/.config/omarchy/animated-wallpaper.json"
DEFAULT='{"enabled":true,"duration":20.0,"maxZoom":1.15,"direction":"in"}'
cleanup() { printf '%s\n' "$DEFAULT" > "$SETTINGS"; }
trap cleanup EXIT

fails=0
scenarios=0

scenario() { # scenario <name> <json-config> <capture-seconds> <analyser-mode> [analyser-args…]
  local name="$1" cfg="$2" wait_s="$3" mode="$4"; shift 4
  if [[ -n ${ONLY:-} && $name != "$ONLY" ]]; then return 0; fi

  printf '%s\n' "$cfg" > "$SETTINGS"
  local start; start=$(date +%s)
  sleep 2                                   # let the FileView watcher fire
  if ! journalctl --user -b --since "@$start" -o cat | grep -aq "animated-wallpaper] config:"; then
    echo "-- $name: the settings file was not picked up"
    fails=$((fails + 1)); return 1
  fi

  sleep "$wait_s"
  journalctl --user -b --since "@$start" -o cat > "/tmp/trace-$name.raw"
  # Only the samples belonging to THIS config: the tail of the previous
  # scenario's trace would otherwise land in the same loop indices and poison
  # every assertion (that cost one debugging round).
  awk 'seen { print } /animated-wallpaper\] config:/ { seen = 1 }' "/tmp/trace-$name.raw" \
    | grep -a "animated-wallpaper] pose " > "/tmp/pose-$name.txt" || true
  echo "-- $name  ($(wc -l < "/tmp/pose-$name.txt") samples)"
  python3 tests/analyse_pose.py "$mode" "$@" < "/tmp/pose-$name.txt"
  fails=$((fails + $?))
  scenarios=$((scenarios + 1))
}

# duration 5 is the floor and keeps the suite short, so a loop is exactly 5 s
# (3.75 s of main leg + 1.25 s of return) and the capture windows are whole
# numbers of loops plus a margin.
scenario loop '{"enabled":true,"duration":5.0,"maxZoom":1.20,"direction":"in"}'  21 loop 5.0 1.20
scenario out  '{"enabled":true,"duration":5.0,"maxZoom":1.25,"direction":"out"}' 18 out  5.0 1.25
scenario ease '{"enabled":true,"duration":5.0,"maxZoom":1.20,"direction":"in"}'  13 ease 1.20
# The drift is its own axis: any zoom can creep any way, including a diagonal.
scenario driftDiag '{"enabled":true,"duration":5.0,"maxZoom":1.20,"direction":"in","drift":"upLeft"}' 13 drift -1 -1

echo "pose tests: $scenarios scenarios, $fails failures"
exit $(( fails > 0 ))

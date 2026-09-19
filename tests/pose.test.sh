#!/bin/bash
# Behaviour tests for the Ken Burns engine.
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
#   ./tests/pose.test.sh                 all scenarios
#   ONLY=plateau ./tests/pose.test.sh    one scenario (used for a quick RED)
set -uo pipefail
cd "$(dirname "$0")/.."

DEFAULT='{"enabled":true,"duration":20.0,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":2.0}'
cleanup() { printf '%s\n' "$DEFAULT" > "$HOME/.config/omarchy/animated-wallpaper.json"; }
trap cleanup EXIT

fails=0
scenarios=0

scenario() { # scenario <name> <json-config> <capture-seconds> <analyser-mode> [analyser-args…]
  local name="$1" cfg="$2" wait_s="$3" mode="$4"; shift 4
  if [[ -n ${ONLY:-} && $name != "$ONLY" ]]; then return 0; fi

  printf '%s\n' "$cfg" > "$HOME/.config/omarchy/animated-wallpaper.json"
  local start; start=$(date +%s)
  sleep 2                                   # let the FileView watcher fire
  if ! journalctl --user -b --since "@$start" -o cat | grep -aq "animated-wallpaper] config:"; then
    echo "-- $name: the settings file was not picked up"
    fails=$((fails + 1)); return 1
  fi

  sleep "$wait_s"
  journalctl --user -b --since "@$start" -o cat > "/tmp/trace-$name.raw"
  # Only the samples belonging to THIS config: the tail of the previous
  # scenario's trace would otherwise land in the same cycle indices and poison
  # every assertion (that cost one debugging round).
  awk 'seen { print } /animated-wallpaper\] config:/ { seen = 1 }' "/tmp/trace-$name.raw" \
    | grep -a "animated-wallpaper] pose " > "/tmp/pose-$name.txt" || true
  echo "-- $name  ($(wc -l < "/tmp/pose-$name.txt") samples)"
  python3 tests/analyse_pose.py "$mode" "$@" < "/tmp/pose-$name.txt"
  fails=$((fails + $?))
  scenarios=$((scenarios + 1))
}

scenario plateau '{"enabled":true,"duration":5.0,"pauseAtEnd":2.0,"maxZoom":1.20,"mode":"zoomIn","smoothEasing":true}'  25 plateau 2.0 5.0
scenario eased   '{"enabled":true,"duration":5.0,"pauseAtEnd":1.0,"maxZoom":1.20,"mode":"zoomIn","smoothEasing":true}'  14 eased
scenario linear  '{"enabled":true,"duration":5.0,"pauseAtEnd":1.0,"maxZoom":1.20,"mode":"zoomIn","smoothEasing":false}' 14 linear
scenario horiz   '{"enabled":true,"duration":5.0,"pauseAtEnd":1.0,"maxZoom":1.25,"mode":"horizontal","smoothEasing":true}' 14 horizontal
scenario vert    '{"enabled":true,"duration":5.0,"pauseAtEnd":1.0,"maxZoom":1.25,"mode":"vertical","smoothEasing":true}'   14 vertical
scenario maxz    '{"enabled":true,"duration":5.0,"pauseAtEnd":0.5,"maxZoom":1.28,"mode":"zoomIn","smoothEasing":true}'  13 maxzoom 1.28
scenario rand    '{"enabled":true,"duration":5.0,"pauseAtEnd":0.5,"maxZoom":1.20,"mode":"random","smoothEasing":true}'  25 random

echo "pose tests: $scenarios scenarios, $fails failures"
exit $(( fails > 0 ))

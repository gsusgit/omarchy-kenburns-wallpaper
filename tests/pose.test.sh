#!/bin/bash
# Behaviour tests for the Ken Burns engine (v3.3: duration levels, maxZoom, drift).
#
# They read the plugin's own pose trace (a bounded 90 s trace started on every
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

SETTINGS="$HOME/.config/omarchy/kenburnswallpaper.json"
DEFAULT='{"enabled":true,"speed":35.0,"maxZoom":1.15,"drift":"center","wander":false,"advance":false}'
# These suites write the same file the panel writes, so they put back whatever was
# there when they started: wiping a human's settings is not a test's business.
BACKUP="$(mktemp)"
[[ -s "$SETTINGS" ]] && cp "$SETTINGS" "$BACKUP"
norm() { python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin),sort_keys=True))' 2>/dev/null; }
cleanup() {
  local want
  if [[ -s "$BACKUP" ]]; then want=$(cat "$BACKUP"); else want="$DEFAULT"; fi
  printf '%s\n' "$want" > "$SETTINGS"
  rm -f "$BACKUP"
  # The service is the only writer and keeps its own copy in memory, so a write
  # already on its way can land after this restore. Check that it stuck, and say so
  # loudly if it did not: a silent wipe of a human's settings is the one failure
  # these suites must never have.
  sleep 2
  [[ "$(printf '%s' "$want" | norm)" == "$(cat "$SETTINGS" | norm)" ]] \
    || printf '  WARN  the settings file did not keep the restore: %s\n' "$(tr -d '\n ' < "$SETTINGS")" >&2
}
trap cleanup EXIT

fails=0
scenarios=0

scenario() { # scenario <name> <json-config> <capture-seconds> <analyser-mode> [analyser-args…]
  local name="$1" cfg="$2" wait_s="$3" mode="$4"; shift 4
  if [[ -n ${ONLY:-} && $name != "$ONLY" ]]; then return 0; fi

  local attempt
  for attempt in 1 2 3; do
    printf '%s\n' "$cfg" > "$SETTINGS"
    local start; start=$(date +%s)
    sleep 2                                 # let the FileView watcher fire
    if ! journalctl --user -b --since "@$start" -o cat | grep -aq "kenburnswallpaper] config:"; then
      echo "-- $name: the settings file was not picked up"
      fails=$((fails + 1)); return 1
    fi

    sleep "$wait_s"
    journalctl --user -b --since "@$start" -o cat > "/tmp/trace-$name.raw"

    # A human is using this desktop, and the panel's Apply writes the same file
    # this scenario just wrote. A second config line inside the window means the
    # trace mixes two configs and every assertion below would fail for a reason
    # that has nothing to do with the code (this poisoned a run: the numbers
    # matched the panel's values exactly). Retry instead of reporting noise.
    if [[ $(grep -ac "kenburnswallpaper] config:" "/tmp/trace-$name.raw") -gt 1 ]]; then
      echo "-- $name: the config changed under the test (someone applied from the panel), retry $attempt"
      sleep 3
      continue
    fi

    # Only the samples belonging to THIS config: the tail of the previous
    # scenario's trace would otherwise land in the same loop indices and poison
    # every assertion (that cost one debugging round).
    awk 'seen { print } /kenburnswallpaper\] config:/ { seen = 1 }' "/tmp/trace-$name.raw" \
      | grep -a "kenburnswallpaper] pose " > "/tmp/pose-$name.txt" || true
    echo "-- $name  ($(wc -l < "/tmp/pose-$name.txt") samples)"
    python3 tests/analyse_pose.py "$mode" "$@" < "/tmp/pose-$name.txt"
    fails=$((fails + $?))
    scenarios=$((scenarios + 1))
    return 0
  done

  echo "-- $name: gave up after 3 attempts, the desktop kept changing the config"
  fails=$((fails + 1))
  scenarios=$((scenarios + 1))
  return 1
}

# The duration is one of five levels; 23 s is the nearest short loop, so a scenario
# is 23 s and the capture windows are whole numbers of loops plus a margin.
scenario loop '{"enabled":true,"speed":23,"maxZoom":1.20,"trace":true}'  80 loop 23 1.20
scenario ease '{"enabled":true,"speed":23,"maxZoom":1.20,"trace":true}'  52 ease 1.20
# The drift is its own axis: any zoom can creep any way, including a diagonal. Its
# length is fixed at 0.9 of the margin (see Service.qml), which is what the
# analyser is told to expect.
scenario driftDiag '{"enabled":true,"speed":23,"maxZoom":1.20,"drift":"upLeft","trace":true}' 52 drift -1 -1 0.9
# Wander picks a new heading at each loop seam, where zoom is 1 and the pan is 0,
# so the swap cannot jump. The first loop keeps the locked heading (`right`).
scenario wander '{"enabled":true,"speed":23,"maxZoom":1.20,"drift":"right","wander":true,"trace":true}' 80 wander

echo "pose tests: $scenarios scenarios, $fails failures"
exit $(( fails > 0 ))

#!/bin/bash
# End-to-end persistence tests (v3.0 schema): IPC write -> the settings file on
# disk -> the service's own FileView reload -> the engine's config.
#
# This is the only honest way to test persistence without a mouse: the IPC
# handler and the menu call the exact same service.save()/set() pair, so a round
# trip through IPC exercises the whole path the menu uses. Requires the shell to
# be running with the plugin enabled.
#
#   ./tests/persist.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SETTINGS="$HOME/.config/omarchy/animated-wallpaper.json"
DEFAULT='{"enabled":true,"duration":20,"maxZoom":1.15,"direction":"in","drift":"center","driftLength":0.5}'

fails=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        expected %s\n        actual   %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

ipc() {
  # The shell reloads this plugin whenever its files change, and the IPC target
  # is briefly absent while it does. Retry instead of reporting a false failure.
  local attempt out
  for attempt in 1 2 3 4 5; do
    out=$(qs ipc --pid "$SHELL_PID" call animated-wallpaper "$@" 2>&1 | tail -1)
    [[ "$out" != *"Could not"* && "$out" != *"error"* && -n "$out" ]] && { printf '%s' "$out"; return 0; }
    sleep 1
  done
  printf '%s' "$out"
  return 1
}

restore() { printf '%s\n' "$DEFAULT" > "$SETTINGS"; }
trap restore EXIT

SHELL_PID=$(qs list --all | awk '/Process ID/{print $3; exit}')
if [[ -z ${SHELL_PID:-} ]]; then
  echo "FAIL no running quickshell instance (is the shell up?)"
  exit 1
fi
echo "  shell pid $SHELL_PID"

# Wait for the file to come back through the service's own watcher.
wait_for_disk() { # wait_for_disk <python expr> <seconds>
  local expr="$1" limit="$2" i=0
  while (( i < limit * 2 )); do
    if python3 -c "import json,sys;d=json.load(open('$SETTINGS'));sys.exit(0 if ($expr) else 1)" 2>/dev/null; then return 0; fi
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

disk() { python3 -c "import json;print(json.load(open('$SETTINGS'))['$1'])"; }
live() { python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

restore
sleep 2
check "status starts at the defaults" "$DEFAULT" "$(ipc status)"

echo "-- the file holds exactly the six values"
check "the key set is closed" 'direction,drift,driftLength,duration,enabled,maxZoom' \
  "$(python3 -c "import json;print(','.join(sorted(json.load(open('$SETTINGS')).keys())))")"
check "pauseAtEnd is not in the file" "keyerror" "$(disk pauseAtEnd 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "mode is not in the file" "keyerror" "$(disk mode 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "preset is not in the file" "keyerror" "$(disk preset 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "handheld is not in the file" "keyerror" "$(disk handheld 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "breathing is not in the file" "keyerror" "$(disk breathing 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "smoothEasing is not in the file" "keyerror" "$(disk smoothEasing 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"

echo "-- writing each key through IPC"
ipc setDuration 45 >/dev/null
wait_for_disk "d['duration'] == 45" 6 && check "duration reached the settings file" "45" "$(disk duration)" \
  || check "duration reached the settings file" "45" "timeout"
sleep 2
check "and the engine applied it" "45" "$(ipc status | live duration)"

ipc setDuration 500 >/dev/null          # far above the 60 s ceiling
wait_for_disk "d['duration'] == 60" 6 && check "duration is clamped to the 60 s ceiling" "60" "$(disk duration)" \
  || check "duration is clamped to the 60 s ceiling" "60" "timeout"

ipc setDuration 1 >/dev/null            # far below the 5 s floor
wait_for_disk "d['duration'] == 5" 6 && check "duration is clamped up to the 5 s floor" "5" "$(disk duration)" \
  || check "duration is clamped up to the 5 s floor" "5" "timeout"

ipc setMaxZoom 9 >/dev/null             # far above the 1.30 cap
wait_for_disk "d['maxZoom'] == 1.3" 6 && check "maxZoom is clamped to the 1.30 cap" "1.3" "$(disk maxZoom)" \
  || check "maxZoom is clamped to the 1.30 cap" "1.3" "timeout"

ipc setDirection side >/dev/null
wait_for_disk "d['direction'] == 'in'" 6 && check "an unknown direction falls back to in" "in" "$(disk direction)" \
  || check "an unknown direction falls back to in" "in" "timeout"

ipc setDirection out >/dev/null
wait_for_disk "d['direction'] == 'out'" 6 && check "the direction switch persists" "out" "$(disk direction)" \
  || check "the direction switch persists" "out" "timeout"

ipc setDrift upLeft >/dev/null
wait_for_disk "d['drift'] == 'upLeft'" 6 && check "the drift persists" "upLeft" "$(disk drift)" \
  || check "the drift persists" "upLeft" "timeout"

ipc setDrift sideways >/dev/null
wait_for_disk "d['drift'] == 'center'" 6 && check "an unknown drift falls back to centre" "center" "$(disk drift)" \
  || check "an unknown drift falls back to centre" "center" "timeout"

ipc setDriftLength 0.8 >/dev/null
wait_for_disk "d['driftLength'] == 0.8" 6 && check "the drift length persists" "0.8" "$(disk driftLength)" \
  || check "the drift length persists" "0.8" "timeout"

ipc setDriftLength 5 >/dev/null          # far above the 0.9 ceiling
wait_for_disk "d['driftLength'] == 0.9" 6 && check "the length is clamped to the 0.9 ceiling" "0.9" "$(disk driftLength)" \
  || check "the length is clamped to the 0.9 ceiling" "0.9" "timeout"

ipc setDriftLength -2 >/dev/null         # below the floor
wait_for_disk "d['driftLength'] == 0" 6 && check "a negative length clamps to zero" "0" "$(disk driftLength)" \
  || check "a negative length clamps to zero" "0" "timeout"

ipc setDriftLength 0.8 >/dev/null
wait_for_disk "d['driftLength'] == 0.8" 6

ipc setDuration 42 >/dev/null
ipc setMaxZoom 1.25 >/dev/null
wait_for_disk "d['maxZoom'] == 1.25" 6

echo "-- surviving a restart (the acceptance criterion)"
sleep 2
check "the values are in place before the restart" "42|1.25|out|center|0.8" \
  "$(disk duration)|$(disk maxZoom)|$(disk direction)|$(disk drift)|$(disk driftLength)"
omarchy-restart-shell >/dev/null 2>&1
sleep 10
SHELL_PID=$(qs list --all | awk '/Process ID/{print $3; exit}')
check "the shell came back" "true" "$([[ -n $SHELL_PID ]] && echo true || echo false)"
check "and the values survived the restart" "42|1.25|out|center|0.8" \
  "$(ipc status | live duration)|$(ipc status | live maxZoom)|$(ipc status | live direction)|$(ipc status | live drift)|$(ipc status | live driftLength)"

echo "-- reset"
ipc reset >/dev/null
sleep 2
check "reset restores every default" "$DEFAULT" "$(ipc status)"

echo "persist tests: $fails failures"
exit $(( fails > 0 ))

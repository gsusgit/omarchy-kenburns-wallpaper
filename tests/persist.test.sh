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

SETTINGS="$HOME/.config/omarchy/kenburnswallpaper.json"
DEFAULT='{"enabled":true,"speed":35,"maxZoom":1.15,"drift":"center","wander":false,"advance":false}'

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
    out=$(qs ipc --pid "$SHELL_PID" call kenburnswallpaper "$@" 2>&1 | tail -1)
    [[ "$out" != *"Could not"* && "$out" != *"error"* && -n "$out" ]] && { printf '%s' "$out"; return 0; }
    sleep 1
  done
  printf '%s' "$out"
  return 1
}

norm() { python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin),sort_keys=True))' 2>/dev/null; }
restore() {
  # Put back whatever was there when the run started: this suite writes the same
  # file the panel writes, and wiping a human's settings is not a test's business.
  if [[ -s "$BACKUP" ]]; then cp "$BACKUP" "$SETTINGS"; else printf '%s\n' "$DEFAULT" > "$SETTINGS"; fi
  rm -f "$BACKUP"
  # A file-level restore is not the whole story: the service is the only writer and
  # keeps its own copy in memory, so a write already on its way can land after this
  # cp -- the suite's own `reset` leaves the defaults in that memory. Check that the
  # file and the service agree, and say so loudly if they do not: a silent wipe of a
  # human's settings is the one failure this suite must never have.
  sleep 2
  local want got
  want=$(cat "$SETTINGS" | norm)
  if [[ -n ${SHELL_PID:-} ]]; then
    got=$(ipc status 2>/dev/null | norm)
    [[ "$want" == "$got" ]] \
      || printf '  WARN  file and service disagree after the restore: file=%s service=%s\n' "$want" "$got" >&2
  fi
}
BACKUP="$(mktemp)"
[[ -s "$SETTINGS" ]] && cp "$SETTINGS" "$BACKUP"
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

printf '%s\n' "$DEFAULT" > "$SETTINGS"     # a known baseline to assert against
sleep 2
check "status starts at the defaults" "$DEFAULT" "$(ipc status)"

echo "-- the file holds exactly the schema"
check "the key set is closed" 'advance,drift,enabled,maxZoom,speed,wander' \
  "$(python3 -c "import json;print(','.join(sorted(json.load(open('$SETTINGS')).keys())))")"
check "pauseAtEnd is not in the file" "keyerror" "$(disk pauseAtEnd 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "mode is not in the file" "keyerror" "$(disk mode 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "preset is not in the file" "keyerror" "$(disk preset 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "handheld is not in the file" "keyerror" "$(disk handheld 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "breathing is not in the file" "keyerror" "$(disk breathing 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "smoothEasing is not in the file" "keyerror" "$(disk smoothEasing 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "direction is not in the file" "keyerror" "$(disk direction 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "driftLength is not in the file" "keyerror" "$(disk driftLength 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "the old duration key is not in the file" "keyerror" "$(disk duration 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"
check "atmosphere is not in the file" "keyerror" "$(disk atmosphere 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"

echo "-- writing each key through IPC"
ipc setSpeed 35 >/dev/null
wait_for_disk "d['speed'] == 35" 6 && check "speed reached the settings file" "35" "$(disk speed)" \
  || check "speed reached the settings file" "35" "timeout"
sleep 2
check "and the engine applied it" "35" "$(ipc status | live speed)"

ipc setSpeed 41.5 >/dev/null              # between two levels: a tie, which goes up
wait_for_disk "d['speed'] == 48" 6 && check "a speed between levels snaps to the nearest" "48" "$(disk speed)" \
  || check "a speed between levels snaps to the nearest" "48" "timeout"

ipc setSpeed 500 >/dev/null               # far above the top level
wait_for_disk "d['speed'] == 60" 6 && check "speed is clamped to the top level" "60" "$(disk speed)" \
  || check "speed is clamped to the top level" "60" "timeout"

ipc setSpeed 1 >/dev/null                 # far below the bottom level
wait_for_disk "d['speed'] == 10" 6 && check "speed is clamped to the bottom level" "10" "$(disk speed)" \
  || check "speed is clamped to the bottom level" "10" "timeout"

ipc setMaxZoom 9 >/dev/null             # far above the 1.30 cap
wait_for_disk "d['maxZoom'] == 1.3" 6 && check "maxZoom is clamped to the 1.30 cap" "1.3" "$(disk maxZoom)" \
  || check "maxZoom is clamped to the 1.30 cap" "1.3" "timeout"

ipc setDrift upLeft >/dev/null
wait_for_disk "d['drift'] == 'upLeft'" 6 && check "the drift persists" "upLeft" "$(disk drift)" \
  || check "the drift persists" "upLeft" "timeout"

ipc setDrift sideways >/dev/null
wait_for_disk "d['drift'] == 'center'" 6 && check "an unknown drift falls back to centre" "center" "$(disk drift)" \
  || check "an unknown drift falls back to centre" "center" "timeout"

ipc setWander true >/dev/null
wait_for_disk "d['wander'] == True" 6 && check "wander persists" "True" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['wander'])")" \
  || check "wander persists" "True" "timeout"

ipc setAdvance true >/dev/null
wait_for_disk "d['advance'] == True" 6 && check "advance persists" "True" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['advance'])")" \
  || check "advance persists" "True" "timeout"

# Wander's live heading is memory-only: a panel save must not grow extra keys.
check "trace is not persisted" "keyerror" "$(disk trace 2>&1 | grep -o 'KeyError' | tr 'A-Z' 'a-z')"

ipc setSpeed 48 >/dev/null
ipc setMaxZoom 1.25 >/dev/null
wait_for_disk "d['maxZoom'] == 1.25" 6

echo "-- surviving a restart (the acceptance criterion)"
sleep 2
check "the values are in place before the restart" "48|1.25|center|True|True" \
  "$(disk speed)|$(disk maxZoom)|$(disk drift)|$(python3 -c "import json;d=json.load(open('$SETTINGS'));print(d['wander'])")|$(python3 -c "import json;d=json.load(open('$SETTINGS'));print(d['advance'])")"
omarchy-restart-shell >/dev/null 2>&1
sleep 10
SHELL_PID=$(qs list --all | awk '/Process ID/{print $3; exit}')
check "the shell came back" "true" "$([[ -n $SHELL_PID ]] && echo true || echo false)"
check "and the values survived the restart" "48|1.25|center|True|True" \
  "$(ipc status | live speed)|$(ipc status | live maxZoom)|$(ipc status | live drift)|$(ipc status | live wander)|$(ipc status | live advance)"

echo "-- reset"
ipc reset >/dev/null
sleep 2
check "reset restores every default" "$DEFAULT" "$(ipc status)"

echo "persist tests: $fails failures"
exit $(( fails > 0 ))

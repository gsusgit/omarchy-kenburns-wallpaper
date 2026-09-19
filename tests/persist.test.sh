#!/bin/bash
# End-to-end persistence tests: IPC write -> settings.json on disk -> the
# service's own FileView reload -> the engine's config.
#
# This is the only honest way to test persistence without a mouse: the IPC
# handler and the menu call the exact same service.save()/set() pair, so a round
# trip through IPC exercises the whole path the menu uses. Requires the shell to
# be running with the plugin enabled.
#
#   ./tests/persist.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PLUGIN_DIR="$PWD"
SETTINGS="$HOME/.config/omarchy/animated-wallpaper.json"
DEFAULT='{"enabled":true,"duration":20,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":2}'

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
wait_for_disk() { # wait_for_disk <jq-ish python expr> <seconds>
  local expr="$1" limit="$2" i=0
  while (( i < limit * 2 )); do
    if python3 -c "import json,sys;d=json.load(open('$SETTINGS'));sys.exit(0 if ($expr) else 1)" 2>/dev/null; then return 0; fi
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

restore
sleep 2
check "status starts at the defaults" "$DEFAULT" "$(ipc status)"

echo "-- writing each key through IPC"
ipc setDuration 45   >/dev/null
wait_for_disk "d['duration'] == 45" 6 && check "duration reached settings.json" "45" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['duration'])")" \
  || check "duration reached settings.json" "45" "timeout"
sleep 2
check "and the engine applied it" "45" "$(ipc status | python3 -c 'import json,sys;print(json.load(sys.stdin)["duration"])')"

ipc setMaxZoom 9     >/dev/null   # way above the 1.30 cap
wait_for_disk "d['maxZoom'] == 1.3" 6 && check "maxZoom is clamped to the 1.30 cap on write" "1.3" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['maxZoom'])")" \
  || check "maxZoom is clamped to the 1.30 cap on write" "1.3" "timeout"

ipc setMode nonsense  >/dev/null
wait_for_disk "d['mode'] == 'random'" 6 && check "an unknown mode falls back to random" "random" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['mode'])")" \
  || check "an unknown mode falls back to random" "random" "timeout"

ipc setMode horizontal >/dev/null
wait_for_disk "d['mode'] == 'horizontal'" 6 && check "a valid mode is stored" "horizontal" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['mode'])")" \
  || check "a valid mode is stored" "horizontal" "timeout"

ipc setSmoothEasing false >/dev/null
wait_for_disk "d['smoothEasing'] is False" 6 && check "the easing toggle persists as a boolean" "False" "$(python3 -c "import json;print(json.load(open('$SETTINGS'))['smoothEasing'])")" \
  || check "the easing toggle persists as a boolean" "False" "timeout"

echo "-- surviving a restart (the acceptance criterion)"
ipc setDuration 33 >/dev/null
wait_for_disk "d['duration'] == 33" 6 || echo "  (warning: write did not land before the restart)"
omarchy-restart-shell >/dev/null 2>&1
sleep 10
SHELL_PID=$(qs list --all | awk '/Process ID/{print $3; exit}')
check "the shell came back" "true" "$([[ -n $SHELL_PID ]] && echo true || echo false)"
check "the settings survived the restart" "33" "$(ipc status | python3 -c 'import json,sys;print(json.load(sys.stdin)["duration"])')"
check "and so did the other keys" "horizontal" "$(ipc status | python3 -c 'import json,sys;print(json.load(sys.stdin)["mode"])')"

echo "-- reset"
ipc reset >/dev/null
sleep 2
check "reset restores every default" "$DEFAULT" "$(ipc status)"

echo "persist tests: $fails failures"
exit $(( fails > 0 ))

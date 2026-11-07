#!/bin/bash
# The system cycler misses when the live symlink points at the theme file
# and find lists a different path to the same picture. CycleNext.py must
# still advance to the next basename.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
check() {
  if [[ "$2" == "$3" ]]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        expected %s\n        actual   %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/.config/omarchy/themes/miasma/backgrounds"
mkdir -p "$WORK/.config/omarchy/backgrounds"
mkdir -p "$WORK/.local/state/omarchy/current/theme/backgrounds"
mkdir -p "$WORK/.local/state/omarchy/current"
printf 'miasma\n' > "$WORK/.local/state/omarchy/current/theme.name"
ln -s "$WORK/.config/omarchy/themes/miasma/backgrounds" "$WORK/.config/omarchy/backgrounds/miasma"

for name in 01-nature-of-fear.jpg 02-crowned.jpg 2-wire-seraph.jpg; do
  printf 'theme %s\n' "$name" > "$WORK/.config/omarchy/themes/miasma/backgrounds/$name"
  printf 'state %s\n' "$name" > "$WORK/.local/state/omarchy/current/theme/backgrounds/$name"
done
ln -s "$WORK/.config/omarchy/themes/miasma/backgrounds/01-nature-of-fear.jpg" \
  "$WORK/.local/state/omarchy/current/background"

next=$(HOME="$WORK" python3 ./CycleNext.py --print)
check "next basename is 02-crowned" "02-crowned.jpg" "$(basename "$next")"

ln -sfn "$WORK/.config/omarchy/themes/miasma/backgrounds/2-wire-seraph.jpg" \
  "$WORK/.local/state/omarchy/current/background"
next=$(HOME="$WORK" python3 ./CycleNext.py --print)
check "wraps after the last name back to 01" "01-nature-of-fear.jpg" "$(basename "$next")"

# A state-dir copy of the current picture is not its own stop.
ln -sfn "$WORK/.local/state/omarchy/current/theme/backgrounds/02-crowned.jpg" \
  "$WORK/.local/state/omarchy/current/background"
next=$(HOME="$WORK" python3 ./CycleNext.py --print)
check "state copy still advances by name" "2-wire-seraph.jpg" "$(basename "$next")"

if (( fails == 0 )); then
  echo "cycle.test.sh: ok"
else
  echo "cycle.test.sh: $fails failed" >&2
  exit 1
fi

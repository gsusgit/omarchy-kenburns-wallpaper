#!/bin/bash
# Unit tests for Settings.js (v3.0 schema). Runs the module in node with the
# QML-only pragma stripped and an export list generated from the source's own
# top-level declarations, so adding a function here needs no matching edit.
#
#   ./tests/settings.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
[[ -f Settings.js ]] || { echo "FAIL Settings.js not found"; exit 1; }

fails=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        expected %s\n        actual   %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

run() {
  node tests/lib/run-settings.js "$1" 2>&1
}

DEFAULT='{"enabled":true,"duration":20,"maxZoom":1.15,"drift":"center"}'

# ---------------------------------------------------------------- the schema
check "empty input gives the documented defaults" "$DEFAULT" "$(run 'S.sanitize({})')"
check "the schema is exactly four values" 'enabled,duration,maxZoom,drift' "$(run 'Object.keys(S.sanitize({a:1})).join(",")')"
check "preset is gone" 'undefined' "$(run 'typeof S.sanitize({preset: "classicCinema"}).preset')"
check "handheld is gone" 'undefined' "$(run 'typeof S.sanitize({handheld: true}).handheld')"
check "breathing is gone" 'undefined' "$(run 'typeof S.sanitize({breathing: false}).breathing')"
check "smoothEasing is gone" 'undefined' "$(run 'typeof S.sanitize({smoothEasing: false}).smoothEasing')"
check "pauseAtEnd is gone" 'undefined' "$(run 'typeof S.sanitize({pauseAtEnd: 3}).pauseAtEnd')"
check "mode is gone" 'undefined' "$(run 'typeof S.sanitize({mode: "random"}).mode')"

# ------------------------------------------------------------------- clamping
# ------------------------------------------------------------------ duration
# The duration is one of five levels, not a free number, because the panel walks
# it with a stepper and a stepper cannot represent an arbitrary value.
check "there are five duration levels" '20,30,40,50,60' "$(run 'S.DURATION_LEVELS.join(",")')"
check "a value between levels snaps down" '20' "$(run 'S.sanitize({duration: 22}).duration')"
check "a value nearer the next level snaps up" '30' "$(run 'S.sanitize({duration: 26}).duration')"
check "a tie snaps up, as documented" '50' "$(run 'S.sanitize({duration: 45}).duration')"
check "a value above the top level clamps to it" '60' "$(run 'S.sanitize({duration: 500}).duration')"
check "a value below the bottom level clamps to it" '20' "$(run 'S.sanitize({duration: 1}).duration')"
check "a nonsense duration falls back to the default" '20' "$(run 'S.sanitize({duration: "long"}).duration')"
check "the duration limits are the level ends" '20,60' "$(run '[S.LIMITS.duration.min,S.LIMITS.duration.max].join(",")')"
check "every level survives sanitising" '20,30,40,50,60' \
  "$(run 'S.DURATION_LEVELS.map(function(d){return S.sanitize({duration: d}).duration}).join(",")')"
check "the level index of the default is zero" '0' "$(run 'S.durationLevelIndex(20)')"
check "the level index of the top level is four" '4' "$(run 'S.durationLevelIndex(60)')"
check "the level index snaps like the value does" '2' "$(run 'S.durationLevelIndex(41)')"
check "an unreadable value indexes as the default" '0' "$(run 'S.durationLevelIndex("soon")')"

# The SPEED control walks the levels backwards, because a short loop is the fast
# one: 0 is the slowest (60 s) and the last index is the fastest (20 s).
check "the speed index of the shortest loop is the fastest" '4' "$(run 'S.speedLevelIndex(20)')"
check "the speed index of the longest loop is the slowest" '0' "$(run 'S.speedLevelIndex(60)')"
check "the slowest speed is the longest duration" '60' "$(run 'S.durationForSpeedIndex(0)')"
check "the fastest speed is the shortest duration" '20' "$(run 'S.durationForSpeedIndex(4)')"
check "a speed index above the range clamps to the fastest" '20' "$(run 'S.durationForSpeedIndex(9)')"
check "a speed index below the range clamps to the slowest" '60' "$(run 'S.durationForSpeedIndex(-3)')"
check "a nonsense speed index falls back to the default" '20' "$(run 'S.durationForSpeedIndex("quick")')"
check "speed and duration round-trip through every level" 'true' \
  "$(run 'S.DURATION_LEVELS.every(function(d){return S.durationForSpeedIndex(S.speedLevelIndex(d)) === d})')"
check "one step of speed is one level shorter" 'true' \
  "$(run 'S.DURATION_LEVELS.slice(1).every(function(d,i){return S.durationForSpeedIndex(S.speedLevelIndex(d)+1) === S.DURATION_LEVELS[i]})')"
# The zoom is five levels too, for the same reason as the duration.
check "there are five zoom levels" '1.1,1.15,1.2,1.25,1.3' "$(run 'S.MAXZOOM_LEVELS.join(",")')"
check "a zoom above the top level clamps to it" '1.3' "$(run 'S.sanitize({maxZoom: 9}).maxZoom')"
check "a zoom below the bottom level clamps to it" '1.1' "$(run 'S.sanitize({maxZoom: 1.0}).maxZoom')"
check "a fractional zoom snaps to the nearest level" '1.1' "$(run 'S.sanitize({maxZoom: 1.12}).maxZoom')"
check "a zoom nearer the next level snaps up" '1.15' "$(run 'S.sanitize({maxZoom: 1.13}).maxZoom')"
check "the zoom limits are the level ends" '1.1,1.3' "$(run '[S.LIMITS.maxZoom.min,S.LIMITS.maxZoom.max].join(",")')"
check "every zoom level survives sanitising" '1.1,1.15,1.2,1.25,1.3' \
  "$(run 'S.MAXZOOM_LEVELS.map(function(z){return S.sanitize({maxZoom: z}).maxZoom}).join(",")')"
check "the zoom level index of the default is one" '1' "$(run 'S.maxZoomLevelIndex(1.15)')"
check "the zoom level index of the top level is four" '4' "$(run 'S.maxZoomLevelIndex(1.3)')"
check "an unreadable zoom indexes as the default" '1' "$(run 'S.maxZoomLevelIndex("lots")')"

# ------------------------------------------------------------------ direction
# Removed in 3.2: with a symmetric loop, "in" and "out" are the same oscillation
# half a period apart, so the switch could only pick the starting pose.
check "direction is gone from the schema" 'undefined' "$(run 'typeof S.sanitize({direction: "out"}).direction')"
check "an old file's direction is dropped" 'false' "$(run 'Object.keys(S.sanitize({direction: "out"})).indexOf("direction") >= 0')"

# -------------------------------------------------------------------- roguery
# `enabled` defaults to TRUE, so "an unreadable value falls back to the default"
# and "a truthy string is accepted" are indistinguishable through sanitize --
# the fallback has to be exercised through the helper to mean anything.
check "a truthy string is not a boolean" 'false' "$(run 'S.bool("yes", false)')"
check "an unreadable value falls back, not up" 'true' "$(run 'S.bool("yes", true)')"
check "boolean strings are read" 'true' "$(run 'S.bool("true", false)')"
check "false strings are read" 'false' "$(run 'S.bool("false", true)')"
check "a number is not a boolean" 'true' "$(run 'S.bool(1, true)')"
check "unreadable enabled keeps its default" 'true' "$(run 'S.sanitize({enabled: "yes"}).enabled')"
check "unknown keys are dropped" "$DEFAULT" "$(run 'S.sanitize({nonsense: 1, duration: 20})')"
check "garbage text parses to the defaults" "$DEFAULT" "$(run 'S.parse("not json at all")')"
check "null parses to the defaults" "$DEFAULT" "$(run 'S.parse(null)')"
check "an old v2 file keeps only what still exists" '{"enabled":true,"duration":40,"maxZoom":1.25,"drift":"center"}' \
  "$(run 'S.sanitize({preset: "custom", enabled: true, duration: 42, maxZoom: 1.25, direction: "out", smoothEasing: true, handheld: true, breathing: true})')"

# ------------------------------------------------------------------- drift
check "the drift defaults to centre" 'center' "$(run 'S.sanitize({}).drift')"
check "there are nine drift options" '9' "$(run 'S.DRIFTS.length')"
check "a diagonal is accepted" 'upLeft' "$(run 'S.sanitize({drift: "upLeft"}).drift')"
check "a hyphenated diagonal is accepted" 'upLeft' "$(run 'S.sanitize({drift: "up-left"}).drift')"
check "a spaced diagonal is accepted" 'downRight' "$(run 'S.sanitize({drift: "Down Right"}).drift')"
check "an unknown drift falls back to centre" 'center' "$(run 'S.sanitize({drift: "sideways"}).drift')"
check "a removed direction is not a drift" 'center' "$(run 'S.sanitize({drift: "horizontal"}).drift')"
check "the nine vectors are the compass points" 'center=0,0 left=-1,0 right=1,0 up=0,-1 down=0,1 upLeft=-1,-1 upRight=1,-1 downLeft=-1,1 downRight=1,1' \
  "$(run 'S.DRIFTS.map(function(d){return d+"="+S.DRIFT_VECTORS[d].join(",")}).join(" ")')"
check "the diana is laid out 3x3 with the dot in the middle" 'upLeft,up,upRight,left,center,right,downLeft,down,downRight' \
  "$(run 'S.driftOptions().map(function(o){return o.value}).join(",")')"
check "the centre option is a dot" '●' "$(run 'S.driftOptions()[4].label')"
check "the diagonals are arrows" '↖,↗,↘,↙' "$(run '[S.DRIFT_LABELS.upLeft,S.DRIFT_LABELS.upRight,S.DRIFT_LABELS.downRight,S.DRIFT_LABELS.downLeft].join(",")')"
check "every option carries a tooltip" 'true' "$(run 'S.driftOptions().every(function(o){return typeof o.tooltip === "string" && o.tooltip.length > 3})')"
check "an unknown drift name yields no vector" '0,0' "$(run 'S.driftVector("nope").join(",")')"
check "the centre vector is zero" '0,0' "$(run 'S.driftVector("center").join(",")')"
check "serialise writes the drift" 'true' "$(run 'S.serialise({drift: "up"}).indexOf("\"drift\": \"up\"") > 0')"

# -------------------------------------------------------------- drift length
# Removed in 3.3: the length is fixed at the ceiling (see Service.qml).
check "driftLength is gone from the schema" 'undefined' "$(run 'typeof S.sanitize({driftLength: 0.2}).driftLength')"
check "an old file's driftLength is dropped" 'false' "$(run 'Object.keys(S.sanitize({driftLength: 0.2})).indexOf("driftLength") >= 0')"
check "there are no driftLength limits left" 'undefined' "$(run 'typeof S.LIMITS.driftLength')"

# --------------------------------------------------------------- serialising
check "serialise round-trips canonically" '{"enabled":true,"duration":30,"maxZoom":1.25,"drift":"upLeft"}' \
  "$(run 'JSON.parse(S.serialise({duration: 30, maxZoom: 1.25, drift: "upLeft"}))')"
check "serialise never writes a removed key" 'false' \
  "$(run '["preset","handheld","breathing","smoothEasing","pauseAtEnd","mode","direction","driftLength"].some(function(k){return S.serialise(S.DEFAULTS).indexOf("\""+k+"\"") >= 0})')"

# The panel's unsaved-changes flag is `serialise(draft) != serialise(applied)`,
# so equality has to be canonical or the warning lights up on an untouched panel.
check "equal configs compare equal" 'true' "$(run 'S.serialise({duration: 20}) === S.serialise(S.DEFAULTS)')"
check "a numeric string is not a change" 'true' "$(run 'S.serialise({duration: "20"}) === S.serialise({duration: 20})')"
check "key order is not a change" 'true' "$(run 'S.serialise({drift: "up", duration: 30}) === S.serialise({duration: 30, drift: "up"})')"
check "a real change is detected" 'false' "$(run 'S.serialise({duration: 30}) === S.serialise({duration: 20})')"
check "flipping the drift is a change" 'false' "$(run 'S.serialise({drift: "left"}) === S.serialise({drift: "right"})')"

# -------------------------------------------------------------- level sliders
# Both sliders are driven by the LEVEL INDEX and round with `integer: true`, so
# there is no fractional snapping left to do -- and `snapToStep`, which existed to
# fix up PanelSlider's mouse path (it never applies `step`), went with it.
check "no slider steps are left" 'undefined' "$(run 'typeof S.STEPS')"
check "no fractional snapping helper is left" 'undefined' "$(run 'typeof S.snapToStep')"

(( fails == 0 )) && echo "settings tests: OK" || echo "settings tests: FAILED ($fails)"
exit $(( fails > 0 ))

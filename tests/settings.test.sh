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

DEFAULT='{"enabled":true,"duration":20,"maxZoom":1.15,"drift":"center","driftLength":0.5}'

# ---------------------------------------------------------------- the schema
check "empty input gives the documented defaults" "$DEFAULT" "$(run 'S.sanitize({})')"
check "the schema is exactly five values" 'enabled,duration,maxZoom,drift,driftLength' "$(run 'Object.keys(S.sanitize({a:1})).join(",")')"
check "preset is gone" 'undefined' "$(run 'typeof S.sanitize({preset: "classicCinema"}).preset')"
check "handheld is gone" 'undefined' "$(run 'typeof S.sanitize({handheld: true}).handheld')"
check "breathing is gone" 'undefined' "$(run 'typeof S.sanitize({breathing: false}).breathing')"
check "smoothEasing is gone" 'undefined' "$(run 'typeof S.sanitize({smoothEasing: false}).smoothEasing')"
check "pauseAtEnd is gone" 'undefined' "$(run 'typeof S.sanitize({pauseAtEnd: 3}).pauseAtEnd')"
check "mode is gone" 'undefined' "$(run 'typeof S.sanitize({mode: "random"}).mode')"

# ------------------------------------------------------------------- clamping
check "duration clamps to the 60 ceiling" '{"enabled":true,"duration":60,"maxZoom":1.15,"drift":"center","driftLength":0.5}' "$(run 'S.sanitize({duration: 500})')"
check "duration below the floor clamps to 5" '{"enabled":true,"duration":5,"maxZoom":1.15,"drift":"center","driftLength":0.5}' "$(run 'S.sanitize({duration: 4})')"
check "the duration ceiling is 60" '60' "$(run 'S.LIMITS.duration.max')"
check "the duration floor is 5" '5' "$(run 'S.LIMITS.duration.min')"
check "maxZoom clamps to the 1.30 cap" '1.3' "$(run 'S.sanitize({maxZoom: 9}).maxZoom')"
check "maxZoom clamps up to the 1.05 floor" '1.05' "$(run 'S.sanitize({maxZoom: 1.0}).maxZoom')"

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
check "an old v2 file keeps only what still exists" '{"enabled":true,"duration":42,"maxZoom":1.25,"drift":"center","driftLength":0.5}' \
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
check "the length defaults to half the margin" '0.5' "$(run 'S.sanitize({}).driftLength')"
check "the length clamps to the 0.9 ceiling" '0.9' "$(run 'S.sanitize({driftLength: 5}).driftLength')"
check "the ceiling is below 1.0 on purpose" '0.9' "$(run 'S.LIMITS.driftLength.max')"
check "a negative length clamps to zero" '0' "$(run 'S.sanitize({driftLength: -1}).driftLength')"
check "a nonsense length falls back to the default" '0.5' "$(run 'S.sanitize({driftLength: "wide"}).driftLength')"
check "the length steps by five percent" '0.05' "$(run 'S.STEPS.driftLength')"
check "a length drag snaps to its step" '0.35' "$(run 'S.snapToStep(0.3412, 0.05, 0)')"

# --------------------------------------------------------------- serialising
check "serialise round-trips canonically" '{"enabled":true,"duration":12,"maxZoom":1.25,"drift":"upLeft","driftLength":0.5}' \
  "$(run 'JSON.parse(S.serialise({duration: 12, maxZoom: 1.25, drift: "upLeft"}))')"
check "serialise never writes a removed key" 'false' \
  "$(run '["preset","handheld","breathing","smoothEasing","pauseAtEnd","mode","direction"].some(function(k){return S.serialise(S.DEFAULTS).indexOf("\""+k+"\"") >= 0})')"

# The panel's unsaved-changes flag is `serialise(draft) != serialise(applied)`,
# so equality has to be canonical or the warning lights up on an untouched panel.
check "equal configs compare equal" 'true' "$(run 'S.serialise({duration: 20}) === S.serialise(S.DEFAULTS)')"
check "a numeric string is not a change" 'true' "$(run 'S.serialise({duration: "20"}) === S.serialise({duration: 20})')"
check "key order is not a change" 'true' "$(run 'S.serialise({drift: "up", duration: 30}) === S.serialise({duration: 30, drift: "up"})')"
check "a real change is detected" 'false' "$(run 'S.serialise({duration: 21}) === S.serialise({duration: 20})')"
check "flipping the drift is a change" 'false' "$(run 'S.serialise({drift: "left"}) === S.serialise({drift: "right"})')"

# ------------------------------------------------------------------ snapping
# PanelSlider's mouse path never applies `step` (it only honours `integer`), so
# the panel snaps. 1.15 / 0.01 is 114.99999999999999 and 1.05 + 10 * 0.01 is
# 1.1500000000000001: both traps are covered here.
check "a zoom drag snaps to its 0.01 step" '1.15' "$(run 'S.snapToStep(1.1456522623697918, 0.01, 1.05)')"
check "snapping keeps the value on the grid" '1.09' "$(run 'S.snapToStep(1.0949, 0.01, 1.05)')"
check "an integer step stays whole" '34' "$(run 'S.snapToStep(33.7, 1, 5)')"
check "snapping does not drift below the minimum" '1.05' "$(run 'S.snapToStep(1.0500000001, 0.01, 1.05)')"
check "a nonsense step leaves the value alone" '1.234' "$(run 'S.snapToStep(1.234, 0, 1)')"
check "the panel steps are one per slider" '{"duration":1,"maxZoom":0.01,"driftLength":0.05}' "$(run 'JSON.stringify(S.STEPS)')"

(( fails == 0 )) && echo "settings tests: OK" || echo "settings tests: FAILED ($fails)"
exit $(( fails > 0 ))

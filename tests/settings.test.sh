#!/bin/bash
# Unit tests for Settings.js. Runs the module in node with the QML-only pragma
# stripped (node cannot parse ".pragma library") and with an explicit export
# appended (a bare script file exports nothing to require()).
set -uo pipefail
cd "$(dirname "$0")/.."
[[ -f Settings.js ]] || { echo "FAIL Settings.js not found"; exit 1; }

fails=0
check() { # check <description> <expected-json> <actual-json>
  if [[ "$2" == "$3" ]]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        expected %s\n        actual   %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

run() {
  node tests/lib/run-settings.js "$1" 2>&1
}

DEFAULT='{"enabled":true,"duration":20,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":2}'

check "empty input gives the documented defaults" "$DEFAULT" "$(run 'S.sanitize({})')"
check "maxZoom above the cap clamps to 1.30" \
  '{"enabled":true,"duration":20,"maxZoom":1.3,"mode":"random","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'S.sanitize({maxZoom: 9})')"
check "maxZoom below the floor clamps to 1.05" \
  '{"enabled":true,"duration":20,"maxZoom":1.05,"mode":"random","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'S.sanitize({maxZoom: 1.0})')"
check "duration clamps to the 120 ceiling" \
  '{"enabled":true,"duration":120,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'S.sanitize({duration: 500})')"
check "duration below the floor clamps to 5" \
  '{"enabled":true,"duration":5,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'S.sanitize({duration: 4})')"
check "pauseAtEnd clamps to the 0 floor" \
  '{"enabled":true,"duration":20,"maxZoom":1.15,"mode":"random","smoothEasing":true,"pauseAtEnd":0}' \
  "$(run 'S.sanitize({pauseAtEnd: -3})')"
check "unknown mode falls back to random" "$DEFAULT" "$(run 'S.sanitize({mode: "nonsense"})')"
check "the human label is accepted as a mode" \
  '{"enabled":true,"duration":20,"maxZoom":1.15,"mode":"zoomIn","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'S.sanitize({mode: "Zoom In"})')"
check "unknown keys are dropped" "$DEFAULT" "$(run 'S.sanitize({nonsense: 1, duration: 20})')"
check "garbage text parses to the defaults" "$DEFAULT" "$(run 'S.parse("not json at all")')"
check "serialise round-trips canonically" \
  '{"enabled":true,"duration":20,"maxZoom":1.3,"mode":"horizontal","smoothEasing":true,"pauseAtEnd":2}' \
  "$(run 'JSON.parse(S.serialise({maxZoom: 4, mode: "HORIZONTAL"}))')"
# The panel's "unsaved changes" flag is `serialise(draft) != serialise(applied)`,
# so equality has to be canonical: same values written differently are NOT a
# change, or the warning would light up on an untouched panel.
check "equal configs compare equal through serialise" 'true' \
  "$(run 'S.serialise({duration: 20}) === S.serialise(S.DEFAULTS)')"
check "a numeric string is not a change" 'true' \
  "$(run 'S.serialise({duration: "20"}) === S.serialise({duration: 20})')"
check "key order is not a change" 'true' \
  "$(run 'S.serialise({mode: "zoomIn", duration: 30}) === S.serialise({duration: 30, mode: "zoomIn"})')"
check "a real change is detected" 'false' \
  "$(run 'S.serialise({duration: 21}) === S.serialise({duration: 20})')"
# PanelSlider's mouse path never applies `step` (it only honours `integer`), so
# the panel snaps. Without this a drag persists 1.1456522623697918 and "unsaved
# changes" then flickers on a stray pixel of the same value.
check "a zoom drag snaps to its 0.01 step" '1.15' \
  "$(run 'S.snapToStep(1.1456522623697918, 0.01, 1.05)')"
check "snapping keeps the value on the grid" '1.09' \
  "$(run 'S.snapToStep(1.0949, 0.01, 1.05)')"
check "a 0.5 step snaps to the half second" '2.5' \
  "$(run 'S.snapToStep(2.62, 0.5, 0)')"
check "an integer step stays whole" '34' \
  "$(run 'S.snapToStep(33.7, 1, 5)')"
check "snapping does not drift below the minimum" '1.05' \
  "$(run 'S.snapToStep(1.0500000001, 0.01, 1.05)')"
check "a nonsense step leaves the value alone" '1.234' \
  "$(run 'S.snapToStep(1.234, 0, 1)')"
check "a fixed mode is returned as-is" '["zoomIn","vertical"]' \
  "$(run '[S.variantForPair(3,"zoomIn"), S.variantForPair(9,"vertical")]')"
check "random variant is deterministic per pair" 'true' \
  "$(run '[0,1,2,3,4,5,6,7,8].every(function(i){return S.variantForPair(i,"random")===S.variantForPair(i,"random")})')"
check "random variant is always one of the four" 'true' \
  "$(run '[0,1,2,3,4,5,6,7,8,9,10,11].every(function(i){return ["zoomIn","zoomOut","horizontal","vertical"].indexOf(S.variantForPair(i,"random"))>=0})')"
check "random variant covers all four variants" '4' \
  "$(run 'new Set([...Array(16).keys()].map(function(i){return S.variantForPair(i,"random")})).size')"
check "the dropdown offers one option per mode, in order" 'zoomIn=Zoom In,zoomOut=Zoom Out,horizontal=Horizontal,vertical=Vertical,random=Random' \
  "$(run 'S.modeOptions().map(function(o){return o.value+"="+o.label}).join(",")')"
check "every dropdown value is a real mode" 'true' \
  "$(run 'S.modeOptions().every(function(o){return S.MODES.indexOf(o.value)>=0})')"

(( fails == 0 )) && echo "settings tests: OK" || echo "settings tests: FAILED ($fails)"
exit $(( fails > 0 ))

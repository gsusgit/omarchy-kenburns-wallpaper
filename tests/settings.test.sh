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
  { tail -n +2 Settings.js
    echo "module.exports={sanitize:sanitize,parse:parse,serialise:serialise,variantForPair:variantForPair,MODES:MODES,LABELS:LABELS,LIMITS:LIMITS,DEFAULTS:DEFAULTS};"
  } > /tmp/gsus-settings.js
  node -e "const S=require('/tmp/gsus-settings.js'); console.log(JSON.stringify($1))" 2>&1
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
check "a fixed mode is returned as-is" '["zoomIn","vertical"]' \
  "$(run 'JSON.stringify([S.variantForPair(3,"zoomIn"), S.variantForPair(9,"vertical")])')"
check "random variant is deterministic per pair" 'true' \
  "$(run 'JSON.stringify([0,1,2,3,4,5,6,7,8].every(function(i){return S.variantForPair(i,"random")===S.variantForPair(i,"random")}))')"
check "random variant is always one of the four" 'true' \
  "$(run 'JSON.stringify([0,1,2,3,4,5,6,7,8,9,10,11].every(function(i){return ["zoomIn","zoomOut","horizontal","vertical"].indexOf(S.variantForPair(i,"random"))>=0}))')"
check "random variant covers all four variants" '4' \
  "$(run 'JSON.stringify([...new Set([...Array(16).keys()].map(function(i){return S.variantForPair(i,"random")}))].length)')"

(( fails == 0 )) && echo "settings tests: OK" || echo "settings tests: FAILED ($fails)"
exit $(( fails > 0 ))

#!/bin/bash
# Security and correctness tests for SettingsStore.py (no running shell).
#
#   ./tests/store.test.sh
set -uo pipefail
cd "$(dirname "$0")/.."

HELPER="$PWD/SettingsStore.py"
[[ -x "$HELPER" ]] || HELPER="python3 $HELPER"

fails=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        expected %s\n        actual   %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

run_read() { # run_read <path> -> sets READ_OUT READ_CODE
  READ_OUT=""
  READ_CODE=0
  READ_OUT=$( $HELPER read "$1" 2>/dev/null ) || READ_CODE=$?
}

run_write() { # run_write <path> <payload>
  $HELPER write "$1" "$2"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CFG="$WORK/kenburnswallpaper.json"
SMALL='{"enabled":true,"speed":48}'
CANARY="$WORK/canary.txt"
printf 'secret\n' > "$CANARY"

echo "-- read"
run_read "$CFG"
check "missing file exits 2" "2" "$READ_CODE"
check "missing file emits nothing" "" "$READ_OUT"

: > "$CFG.empty"
run_read "$CFG.empty"
check "empty file exits 1" "1" "$READ_CODE"

printf '%s\n' "$SMALL" > "$CFG"
run_read "$CFG"
check "small json exits 0" "0" "$READ_CODE"
check "small json body" "$SMALL" "$(printf '%s' "$READ_OUT" | tr -d '\n')"

ln -sf "$CANARY" "$CFG.symlink"
run_read "$CFG.symlink"
check "symlink read exits 1" "1" "$READ_CODE"
check "symlink read emits nothing" "" "$READ_OUT"
check "canary intact after symlink read" "secret" "$(cat "$CANARY")"

rm -f "$CFG.symlink"
mkfifo "$CFG.fifo"
( sleep 10 ) > "$CFG.fifo" &
FIFO_WR=$!
run_read "$CFG.fifo"
kill "$FIFO_WR" 2>/dev/null || true
wait "$FIFO_WR" 2>/dev/null || true
check "fifo read exits 1" "1" "$READ_CODE"

rm -f "$CFG.fifo"
truncate -s 1G "$CFG.sparse" 2>/dev/null || python3 -c "open('$CFG.sparse','wb').seek(1024**3-1); open('$CFG.sparse','ab').write(b'\\0')"
run_read "$CFG.sparse"
check "sparse 1G read exits 1" "1" "$READ_CODE"
check "sparse read emits nothing" "" "$READ_OUT"

echo "-- write"
TARGET="$WORK/sub/kenburnswallpaper.json"
PAYLOAD='{"enabled":false,"speed":35}'
run_write "$TARGET" "$PAYLOAD"
check "write exits 0" "0" "$?"
check "write creates regular file" "regular file" "$( [[ -f "$TARGET" && ! -L "$TARGET" ]] && echo regular file || echo other )"
check "write mode is 0600" "600" "$(stat -c '%a' "$TARGET")"
check "write content" "$PAYLOAD" "$(tr -d '\n ' < "$TARGET")"

ln -sf "$CANARY" "$WORK/sub/kenburnswallpaper.json.link"
run_write "$WORK/sub/kenburnswallpaper.json.link" '{"enabled":true}'
check "write through symlink path exits 0" "0" "$?"
check "canary not truncated by symlink replace" "secret" "$(cat "$CANARY")"

rm -f "$WORK/sub/kenburnswallpaper.json.link"
ln -sf "$WORK/sub" "$WORK/sub_link"
run_read "$WORK/sub_link/kenburnswallpaper.json"
check "symlinked parent dir rejected on read" "1" "$READ_CODE"

SYMLINK_DIR="$WORK/linkdir"
REAL="$WORK/realdir"
mkdir -p "$REAL"
ln -sf "$REAL" "$SYMLINK_DIR"
run_write "$SYMLINK_DIR/x.json" '{}'
check "symlinked parent dir rejected on write" "1" "$?"

BIG="$(python3 -c "print('x'*70000)")"
run_write "$WORK/big.json" "$BIG"
check "oversized payload rejected" "1" "$?"
[[ ! -f "$WORK/big.json" ]] && big_ok=true || big_ok=false
check "oversized payload leaves no file" "true" "$big_ok"

PRED="$WORK/sub/kenburnswallpaper.json.tmp.99999"
ln -sf "$CANARY" "$PRED"
run_write "$TARGET" "$PAYLOAD"
check "predictable tmp symlink not used" "secret" "$(cat "$CANARY")"

echo "store tests: $fails failures"
exit $(( fails > 0 ))

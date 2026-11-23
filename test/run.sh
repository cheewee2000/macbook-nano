#!/bin/bash
# The one check: unit tests + the app typing and pointing at a fake Mac in the simulator.
#   test/run.sh ["Macbook Nano Duo"]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-Macbook Nano Duo}"
LOG="$(mktemp -t fake_mac)"
python3 test/fake_mac.py 5999 "$LOG" &
trap 'kill $!' EXIT
xcodegen -q
xcodebuild test -project MacbookNano.xcodeproj -scheme MacbookNano -destination "platform=iOS Simulator,name=$SIM" -quiet \
  > "$LOG.xcodebuild" 2>&1 || { grep -E "error:|XCTAssert|\*\* TEST" "$LOG.xcodebuild"; exit 1; }
# a  shift ! shift-up  b  cmd c cmd-up  return, in that order, then a pointer move and a click
want='key 61 down
key 61 up
key ffe1 down
key 21 down
key 21 up
key ffe1 up
key 62 down
key 62 up
key ffeb down
key 63 down
key 63 up
key ffeb up
key ff0d down
key ff0d up'
got="$(grep '^key' "$LOG" || true)"
[ "$got" = "$want" ] || { echo "KEYS WRONG:"; echo "$got"; exit 1; }
[ "$(grep '^ptr 0' "$LOG" | sort -u | wc -l)" -gt 3 ] || { echo "POINTER NEVER MOVED"; cat "$LOG"; exit 1; }
grep -q '^ptr 1' "$LOG" || { echo "NO CLICK"; cat "$LOG"; exit 1; }
echo "OK: keys, pointer and click all reached the fake Mac"

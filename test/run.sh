#!/bin/bash
# The one check: unit tests + the app typing and pointing at a fake Mac in the simulator.
#   test/run.sh ["Macbook Nano Duo"]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-Macbook Nano Duo}"
LOG="$(mktemp -t fake_mac)"
python3 test/fake_mac.py 5999 "$LOG" 'c0rrect horse!' &
trap 'kill $!' EXIT
xcodegen -q
xcodebuild test -project MacbookNano.xcodeproj -scheme MacbookNano -destination "platform=iOS Simulator,name=$SIM" -quiet \
  > "$LOG.xcodebuild" 2>&1 || { grep -E "error:|XCTAssert|\*\* TEST" "$LOG.xcodebuild"; exit 1; }
# the simulator finds RoyalVNCKit in the build folder even when it is not in the app; the phone does not (v0.1.0 crashed on launch)
APP="$(find ~/Library/Developer/Xcode/DerivedData/MacbookNano-*/Build/Products/Release-iphonesimulator -maxdepth 1 -name MacbookNano.app | head -1)"
[ -f "$APP/Frameworks/RoyalVNCKit.framework/RoyalVNCKit" ] || { echo "RoyalVNCKit IS NOT EMBEDDED IN THE APP"; exit 1; }
# a  shift ! shift-up  b  cmd c cmd-up  return, in that order (cmd is ffed, Hyper_L, on an Apple server), then a pointer move and a click
want='key 61 down
key 61 up
key ffe1 down
key 21 down
key 21 up
key ffe1 up
key 62 down
key 62 up
key ffed down
key 63 down
key 63 up
key ffed up
key ff0d down
key ff0d up'
# refused with no password, let in with the right one (Apple Remote Desktop login, as on a real Mac)
[ "$(grep '^auth' "$LOG" | sed "s/'.*'/USER/")" = 'auth USER fail
auth USER ok' ] || { echo "LOGIN WRONG:"; grep '^auth' "$LOG"; exit 1; }
got="$(grep '^key' "$LOG" || true)"
[ "$got" = "$want" ] || { echo "KEYS WRONG:"; echo "$got"; exit 1; }
[ "$(grep '^ptr 0' "$LOG" | sort -u | wc -l)" -gt 3 ] || { echo "POINTER NEVER MOVED"; cat "$LOG"; exit 1; }
grep -q '^ptr 1' "$LOG" || { echo "NO CLICK"; cat "$LOG"; exit 1; }
echo "OK: login, keys, pointer and click all reached the fake Mac"

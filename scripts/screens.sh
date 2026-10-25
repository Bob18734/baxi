#!/bin/bash
# Builds Baxi as a Mac (Catalyst) app and photographs screens, because the team's Mac cannot run
# the iOS Simulator. Debug only; the iPhone build is unchanged.
#   scripts/screens.sh                     build, then shoot every screen into build/screens/
#   scripts/screens.sh --no-build name "--args..."   shoot one screen
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/screens; mkdir -p "$OUT"
APP=build/cat/Build/Products/Debug-maccatalyst/Baxi.app
if [ "${1:-}" != "--no-build" ]; then
  xcodegen generate --spec .catalyst.yml >/dev/null
  xcodebuild -project BaxiCat.xcodeproj -scheme Baxi -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/cat build 2>&1 \
    | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | tee build/screens/build.log || true
  grep -q 'BUILD SUCCEEDED' build/screens/build.log || exit 1
else shift; fi
shoot() { # name, args...
  local name="$1"; shift
  rm -f "$OUT/$name.png"
  # -g opens it behind your other windows so it never takes focus; the app quits after its snapshot.
  open -g -n "$APP" --args --phone-window --snap "$PWD/$OUT/$name.png" "$@"
  for _ in $(seq 1 40); do [ -f "$OUT/$name.png" ] && break; sleep 0.5; done
  sleep 1; pkill -f "$APP/Contents/MacOS/Baxi" 2>/dev/null || true
  [ -f "$OUT/$name.png" ] && echo "shot $name" || echo "MISSING $name"
}
if [ $# -ge 1 ]; then shoot "$@"; exit; fi
shoot welcome --screen welcome
shoot home --skip-welcome
shoot route --skip-welcome --tab route
shoot log --skip-welcome --tab log --sample-drives
shoot route-chosen --skip-welcome --route preset_highway --snap-delay 7
shoot preview --skip-welcome --screen preview --snap-delay 7
shoot arrived --skip-welcome --screen arrived --snap-delay 8
shoot settings --skip-welcome --screen settings
shoot home-big --skip-welcome --big-text
shoot drive --demo-drive preset_highway --replay-speed 4 --replay-start 4400 --snap-delay 8 --drive-time day
shoot drive-night --demo-drive preset_highway --replay-speed 4 --replay-start 4400 --snap-delay 8 --drive-time night
shoot drive-roundabout --demo-drive preset_roundabouts --replay-speed 4 --replay-start 1400 --snap-delay 9 --drive-time day

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
  "$APP/Contents/MacOS/Baxi" --phone-window --snap "$PWD/$OUT/$name.png" "$@" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 40); do [ -f "$OUT/$name.png" ] && break; sleep 0.5; done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  [ -f "$OUT/$name.png" ] && echo "shot $name" || echo "MISSING $name"
}
if [ $# -ge 1 ]; then shoot "$@"; exit; fi
shoot welcome --reset-welcome
shoot home --skip-welcome
shoot route --skip-welcome --carmel-demo
shoot log --skip-welcome --tab log
shoot drive --demo-drive preset_highway --replay-speed 4 --replay-start 4400 --snap-delay 8

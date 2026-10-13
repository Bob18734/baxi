# FirstRoads

A driving coach for Indiana teens with a learner's permit. It reads the real roads around your home
from OpenStreetMap, builds practice routes that level you up one skill at a time (neighborhood streets,
signals, single-lane roundabouts, multi-lane roundabouts, parkways, highway merges), walks you through
each tricky spot before the drive with Look Around imagery, the lane to be in, and the rule from the
Indiana Driver's Manual, and logs the 50 supervised hours (10 at night) the BMV requires, exporting the
official State Form 54706.

Built for the 2026 Congressional App Challenge, Indiana's 5th District, by Vardaan Goel and [partner].

Safety rule: the driver never touches the phone. Teaching happens before the drive. During the drive
the passenger holds the phone.

## Build and run

Requirements: a Mac with Xcode 26 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```
git clone <this repo>
cd firstroads
xcodegen generate
open FirstRoads.xcodeproj
```

Pick an iPhone simulator and press Run. Tap **Try the Carmel demo** on the Home tab; everything the demo
needs is bundled, so it works with no network.

To run on your own iPhone: select your phone as the destination, set your personal team under
Signing & Capabilities, and press Run. No paid developer account is needed.

Tests: Product > Test (Cmd-U). The student-module tests live in `FirstRoadsTests/`.

## Data

Rebuild the bundled JSON with:

```
python3 scripts/build_carmel_cache.py     # OpenStreetMap roads for Carmel via Overpass
python3 scripts/build_crash_layers.py     # MPO High Injury Network, intersection studies, FARS
```

Sources: OpenStreetMap contributors (ODbL) via the Overpass API; OSRM public demo router;
Apple MapKit; Indianapolis MPO High Injury Network 2026 and Intersection Safety Studies (public ArcGIS
services); NHTSA FARS 2023; Indiana BMV Driver's Manual; Indiana State Form 54706.

## Code map

- `FirstRoads/Models` — plain data types (OSM cache, features, tiers, drives).
- `FirstRoads/Core` — the logic: feature extractor, geometry, and the four student-owned modules
  (`RoundaboutClassifier`, `LanePicker`, `RouteScorer`, `ApproachHeading`).
- `FirstRoads/Services` — bundled data loading, routing clients.
- `FirstRoads/Screens` — SwiftUI screens: Home, Plan, Walkthrough, Drive, Debrief, Log.
- `scripts/` — Python scripts that build the bundled data.

## AI disclosure

See [AI_DISCLOSURE.md](AI_DISCLOSURE.md). The four modules listed there are written by the students
without AI; everything else was built with Claude Code and reviewed by us.

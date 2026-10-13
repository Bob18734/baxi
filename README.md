# FirstRoads

Navigation built for new drivers. Google Maps tells you where to turn; FirstRoads tells an Indiana
teen with a learner's permit what to do, early enough to stay calm: which lane to be in, said half a
mile early; how many traffic lights until the turn; which roundabout exit and which lane; where the
speed limit drops; where the crash-heavy corridors are. Before the drive, a preview shows the hardest
spots as Look Around imagery with the rule from the Indiana Driver's Manual. Every drive logs toward
the 50 supervised hours (10 at night) the BMV requires, exporting the official State Form 54706.

Built for the 2026 Congressional App Challenge, Indiana's 5th District, by Vardaan Goel and [partner].

Safety rule: the driver never touches the phone. It is mounted before the drive and the Drive screen
has no controls except End drive. Cues are spoken once, one short line each. The wording of lane,
roundabout, merge and school-zone cues cites the Indiana Driver's Manual; the timing of cues (how early
a lane cue fires) is our own design and is not from the manual.

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

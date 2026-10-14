# Baxi

Navigation built for new drivers. Google Maps tells you where to turn; Baxi tells an Indiana
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
git clone https://github.com/Bob18734/baxi.git
cd baxi
xcodegen generate
open Baxi.xcodeproj
```

Pick your iPhone and press Run. Tap **Watch a demo drive** on the Home tab; everything the demo needs is
bundled, so it works with no network.

To run on your own iPhone: select your phone as the destination, set your personal team under
Signing & Capabilities, and press Run. No paid developer account is needed.

Tests: `swift test` in the repo root runs every logic test on the Mac, no Simulator needed
(`Package.swift` builds only the Core, Models and data services). Product > Test in Xcode runs the same
files. The student-module tests live in `BaxiTests/` and are skipped until each module is written.

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

- `Baxi/Models` — plain data types: OSM cache, road features, `PlannedRoute` and `Maneuver`, `Cue`,
  `ExperienceLevel`, drives.
- `Baxi/Core` — the logic. `Polyline` (meters along a route), `RouteFollower` (snaps each location fix to the
  route, forward only, off-route after 60 m for 10 s), `CueListBuilder` (places every cue along a route from the
  road data), `HardSpots` (what the Preview screen shows), `Daylight` (sunrise, sunset and the day/night split of a
  drive), `DriveLog` (totals toward 50 and 10 hours, CSV), `FeatureExtractor`, `Geo`, and the four student-owned modules: `LanePicker` and `CueScheduler`
  (Vardaan), `RoundaboutClassifier` and `ApproachHeading` (partner). Each student module has a stub, a rule list
  in its doc comment, and a test suite in `BaxiTests/` that is skipped until `isImplemented` is flipped to true.
- `Baxi/Services` — bundled data and briefing loading, GPX parse and replay, routing clients, `DriveSession`
  (one drive: following, cue firing, speech, reroute), `LogPDF` (the log in the State Form 54706 layout).
- `Baxi/Screens` — SwiftUI screens: Home, Route, Preview, Drive, Arrived, Log.
- `scripts/` — Python scripts that build the bundled data.

## Code tour

[CODE_TOUR.md](CODE_TOUR.md) follows one drive through the code, step by step, and lists the
questions a judge is likely to ask. `swift run baxi-transcript` prints everything Baxi says on a route.

## AI disclosure

See [AI_DISCLOSURE.md](AI_DISCLOSURE.md). The four modules listed there are written by the students
without AI; everything else was built with Claude Code and reviewed by us.

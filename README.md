# Baxi

Navigation built for new drivers. Google Maps tells you where to turn; Baxi tells an Indiana
teen with a learner's permit what to do, early enough to stay calm: which lane to be in, said half a
mile early; how many traffic lights until the turn; which roundabout exit and which lane; where the
speed limit drops; where the crash-heavy corridors are. Before the drive, a preview shows the hardest
spots as Look Around imagery with the rule from the Indiana Driver's Manual. Every drive logs toward
the 50 supervised hours (10 at night) the BMV requires. Exports fill the official State Form 54706 and include a CSV. Optional driver details are saved
on this device; review the exported forms and complete the signatures on paper.

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

Screens without the Simulator: `scripts/screens.sh` builds a Debug Mac (Catalyst) copy of the app
and saves screenshots to `build/screens/` (see [docs/DESIGN.md](docs/DESIGN.md)). `scripts/design-lint.sh`
checks that every screen uses the design tokens.

Tests: `swift test` in the repo root runs every logic test on the Mac, no Simulator needed
(`Package.swift` builds only the Core, Models and data services). Product > Test in Xcode runs the same
files. The student-module tests live in `BaxiTests/` and are skipped until each module is written.

Current implementation gaps and the next work are tracked in [docs/IMPLEMENTATION-STATUS.md](docs/IMPLEMENTATION-STATUS.md).
Run `python3 scripts/check-readiness.py` to check the four student implementation flags and required
briefing entries. It currently exits with status 1 because that work is incomplete. A passing logic
suite alone does not mean the student modules or driving guidance are ready.

## Data

Rebuild the bundled JSON with:

```
python3 scripts/build_carmel_cache.py     # OpenStreetMap roads for Carmel via Overpass
python3 scripts/build_crash_layers.py     # MPO High Injury Network, intersection studies, FARS
```

Sources: OpenStreetMap contributors (ODbL) via the Overpass API; OSRM public demo router;
Apple MapKit; Overpass typeface (SIL Open Font License, Baxi/Resources/Fonts); Indianapolis MPO High Injury Network 2026 and Intersection Safety Studies (public ArcGIS
services); NHTSA FARS 2023; Indiana BMV Driver's Manual; Indiana State Form 54706.

## Code map

- `Baxi/Models` — plain data types: OSM cache, road features, `PlannedRoute` and `Maneuver`, `Cue`,
  `ExperienceLevel`, drives.
- `Baxi/Core` — the logic. `Polyline` (meters along a route), `RouteFollower` (snaps each location fix to the
  route, forward only, off-route after 60 m for 10 s), `CueListBuilder` (places every cue along a route from the
  road data), `HardSpots` (what the Preview screen shows), `Daylight` (sunrise, sunset and the day/night split of a
  drive), `DriveLog` (totals toward 50 and 10 hours, CSV), `FeatureExtractor`, `Geo`, `LanePicker`, `CueScheduler`,
  `RoundaboutClassifier` and `ApproachHeading`. These four were first reserved for the students; Claude wrote them
  on Oct 14 (see AI_DISCLOSURE.md). Each has its rules in its doc comment and a test suite in `BaxiTests/`.
- `Baxi/Core/Practice.swift` — skills practiced per drive (single and two-lane roundabouts, merges, exit ramps,
  multi-lane turns, miles at 45 mph or more), totals on the Log, and which practice route fills the biggest gap.
  The goals (20, 10, 6, 6, 10, 25) are Baxi's own suggestion, not from the statute or the Driver's Manual.
  Each skill climbs four levels (Started, Steady, Confident, Test-ready) at a quarter, half, three quarters and all
  of its goal.
- `Baxi/Core/DriveHabits.swift` — how a drive went, from one GPS speed sample per second: time more than 5 mph over
  the posted limit, full stops (under 3 mph) at all-way stops only (the map cannot say which road a two-way stop
  sign faces), hard braking (slowing faster than 3.4 m/s² from above 10 mph), merging up to within 10 mph of the
  limit 150 m past a merge (not when an exit follows within 300 m), and top speed near a school on roads posted
  40 or under (a reminder only: Baxi cannot see whether the zone's lights were flashing). A 0 to 100 score and up
  to three tips. Every threshold is Baxi's own coaching choice, not Indiana law.
- `Baxi/Services` — bundled data and briefing loading, GPX parse and replay, routing clients, `DriveSession`
  (one drive: following, cue firing, speech, reroute), `OfficialLogPDF` (fills the bundled official State Form 54706).
- `Baxi/Design` — the design system: colors, type, spacing, the guide-sign panel, buttons, and the drawn
  road-sign marks. Explained in [docs/DESIGN.md](docs/DESIGN.md).
- `Baxi/Screens` — SwiftUI screens: Welcome, Home, Routes, Preview, Drive, Arrived, Log.
- `scripts/` — Python scripts that build the bundled data; `screens.sh` and `design-lint.sh`.
- [docs/SHIP-CHECKLIST.md](docs/SHIP-CHECKLIST.md) — everything to check before submitting.

## Code tour

[CODE_TOUR.md](CODE_TOUR.md) follows one drive through the code, step by step, and lists the
questions a judge is likely to ask. `swift run baxi-transcript` prints everything Baxi says on a route.
[docs/BRIEFINGS.md](docs/BRIEFINGS.md) explains the briefing file the students write.

## AI disclosure

See [AI_DISCLOSURE.md](AI_DISCLOSURE.md), a dated log of every use. The app's code was written with Claude Code,
including the four modules first reserved for the students (the team decided on Oct 14 that Claude would write
all app code); the partner's pull requests were written with ChatGPT Codex. The students' part is the idea, the
product decisions, testing on the phone, the Indiana Driver's Manual briefings (`briefings.json`), the written
answers and the video.

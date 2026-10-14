# Code tour

Read this before you walk a judge through Baxi. It follows one drive from the tap on Start to a
spoken cue, names the file for each step, and ends with questions a judge is likely to ask. Every
claim here can be checked in the code; file paths are clickable on GitHub.

## The one-minute version

Baxi turns a route into a list of things to say, each pinned to a distance along the route
("Move to the right lane now" belongs 800 m before the turn). While you drive, it works out how far
along the route the car is, and when the car reaches a cue's spot it says that cue once. Everything
else (screens, the log, the preview) is built around that loop.

## One drive, step by step

1. **Pick a route.** `Baxi/Screens/RouteView.swift` shows the three Carmel presets and a search box.
   Presets are saved router answers in `Baxi/Resources/Routes/*.json` (made by
   `scripts/build_preset_routes.py`), so the demo works with no internet. A searched destination goes
   to `Baxi/Services/RouteService.swift`, which asks the OpenStreetMap router (OSRM) and falls back to
   Apple Maps directions.

2. **Read the router's answer.** `Baxi/Services/OSRMParser.swift` turns the JSON into a
   `PlannedRoute` (`Baxi/Models/PlannedRoute.swift`): a line of coordinates plus a list of
   `Maneuver`s (turn left onto Main Street, roundabout exit 2, merge...), each with its distance
   along the route and any lane data.

3. **Measure the route.** `Baxi/Core/Polyline.swift` stores the cumulative meters at every point, so
   any spot can be named by "meters along the route". Snapping a GPS fix to the line is a projection
   onto the nearest segment (`Geo.projectOntoSegment` in `Baxi/Core/Geo.swift`).

4. **Find what is on the route.** The road data is OpenStreetMap for Carmel, bundled in
   `Baxi/Resources/Data/carmel_osm.json` (`scripts/build_carmel_cache.py`).
   `Baxi/Core/FeatureExtractor.swift` finds roundabouts, signals, stop signs and schools in it, and
   calls **RoundaboutClassifier** (partner) to label each roundabout single-lane, multi-lane or
   interchange.

5. **Build the cue list.** `Baxi/Core/CueListBuilder.swift` walks the route every 25 m and creates a
   `Cue` (`Baxi/Models/Cue.swift`) for each thing worth saying: turns, roundabouts (with exit number),
   lane changes, ramps and merges, speed limit changes, traffic lights, stop signs, school zones,
   crash-heavy corridors (Indianapolis MPO High Injury Network), and arrival. For lane cues it reads
   the OpenStreetMap `turn:lanes` tag and asks **LanePicker** (Vardaan) which lane to be in.
   Some rules learned from testing are in here, each with a comment: stop signs must sit within 4 m of
   the route (side-street signs are farther), the second of two stop signs within 60 m faces oncoming
   traffic, a speed change must hold 250 m, and two turns under 60 m apart become one line.

6. **Decide when each cue fires.** **CueScheduler.plan** (Vardaan) sets each cue's `fireAtMeters`
   from the experience level (New drivers hear lane cues earliest; see
   `Baxi/Models/ExperienceLevel.swift`) and the road speed.

7. **Drive.** `Baxi/Services/DriveSession.swift` gets a location fix about once a second (or from the
   replay timer), and `Baxi/Core/RouteFollower.swift` turns it into progress: meters along, meters
   off the line, off route or not. Progress only moves forward, so GPS wobble cannot repeat a cue.
   Off the line by more than 60 m for 10 seconds counts as off route; on a real drive Baxi then asks
   for a new route from where the car is.

8. **Say it once.** On every fix, **CueScheduler.due** (Vardaan) picks at most one cue that is due,
   never one already said. DriveSession fills in the light count ("your turn is in 2 lights", counted
   from the signals between the car and the turn) and hands the text to
   `Baxi/Services/Speaker.swift`, which uses Apple's built-in speech (`AVSpeechSynthesizer`) and lowers
   music while it talks.

9. **Show it.** `Baxi/Screens/DriveView.swift` only displays what DriveSession publishes: next
   maneuver and distance, the lane strip, the light count, the speed limit, a school zone or crash
   chip, and the last thing said. Nothing on it needs to be touched while driving.

10. **Log it.** When the drive ends, `Baxi/Core/Daylight.swift` splits the minutes into day and night
    using the sunrise equation for the start point, and a `DriveRecord` (SwiftData, on the phone only)
    is saved. `Baxi/Screens/LogView.swift` totals them toward 50 hours and 10 at night
    (`Baxi/Core/DriveLog.swift`) and exports a PDF in the State Form 54706 layout
    (`Baxi/Services/LogPDF.swift`) or CSV. Replays are never logged.

Before a drive, `Baxi/Screens/PreviewView.swift` shows each hard spot (`Baxi/Core/HardSpots.swift`)
with Apple Look Around imagery, the exact line Baxi will say there, and your manual briefing from
`Baxi/Resources/Content/briefings.json`. **ApproachHeading** (partner) aims the map on each card.

## The four student modules

| Module | Owner | Called from | What it decides | Test it |
|---|---|---|---|---|
| `Baxi/Core/LanePicker.swift` | Vardaan | CueListBuilder, lane cues | Which lane to be in, from `turn:lanes` | `swift test --filter LanePickerTests` |
| `Baxi/Core/CueScheduler.swift` | Vardaan | DriveSession | When each cue fires, and which one is due now | `swift test --filter CueSchedulerTests` |
| `Baxi/Core/RoundaboutClassifier.swift` | Partner | FeatureExtractor | Single-lane, multi-lane or interchange; lanes; legs | `swift test --filter RoundaboutClassifierTests` |
| `Baxi/Core/ApproachHeading.swift` | Partner | PreviewView | The direction a driver faces arriving at a spot | `swift test --filter ApproachHeadingTests` |

Each file has the rules in its doc comment and a stub so the app runs. The tests are skipped until you
set `isImplemented = true`. After writing yours, run the transcript tool below and compare.

## Hear a drive without driving

```
swift run baxi-transcript                          # every preset
swift run baxi-transcript preset_highway new       # one preset, New level
swift run baxi-transcript preset_highway new 4400  # from 4,400 m, where the Home demo starts
```

It runs the real DriveSession over the route and prints each line with where it was said. This is
how the stop-sign and speed-limit bugs above were found. `swift test` runs every test on the Mac.

## Questions a judge may ask

- **How do you know where the car is on the route?** Each GPS fix is projected onto the nearest
  segment of the route line, giving meters along. RouteFollower only lets that number grow, and only
  searches near the last segment, so a loop route that passes near itself does not jump ahead.
- **How do you count lights?** Signals from OpenStreetMap within 20 m of the route become distances
  along it. The count is the signals from the car up to and including the light at the turn
  (CueListBuilder.lightsBefore), so "your turn is in 1 light" means the next light is the turn. The
  turn's own light gets no separate countdown cue, since the turn cue covers it.
- **Where do the lane cues come from?** The `turn:lanes` tag on the road approaching the turn, read
  by LanePicker, plus the router's own lane data. Where neither exists, Baxi says nothing about lanes
  rather than guess.
- **Why should a new driver trust the wording?** The rule text in briefings and lane, roundabout,
  merge and school-zone cues is checked against the Indiana Driver's Manual by chapter and page. Cue
  timing is our own design and the app says so.
- **What about safety?** Indiana bans holding a phone while driving. The phone is mounted, cues are
  spoken once, and the Drive screen has nothing to tap except End and Mute.
- **What data leaves the phone?** A destination search goes to Apple Maps search, and the start and end
  points of a searched route go to the router. Presets need nothing. Drives stay on the phone in
  SwiftData. No account, no analytics.
- **What did AI do?** See `AI_DISCLOSURE.md`: Claude Code built most of the app and the tests; the four
  modules above and the briefing content are ours.

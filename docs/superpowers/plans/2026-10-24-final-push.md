# Baxi final push (Oct 24) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every judge-visible hole from the Oct 24 audit, then add post-drive habit feedback (speed vs limit, school zones, stop signs, hard braking, merge speed), skill levels built on it, a live speed indicator, and two more Carmel practice routes.

**Architecture:** Logic goes in `Baxi/Core` as pure, `swift test`-covered functions (`DriveHabits`, `Practice` levels). `DriveSession` records one speed sample per fix and hands the samples to `DriveHabits` at the end; `DriveRecord` stores the result as JSON, like `skillsJSON`. Screens only display.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI, SwiftData, MapKit, CoreLocation, XcodeGen, Swift Testing.

**Spec:** The Oct 24 conversation (audit list approved by Vardaan with "ok go"), summarised here: (1) fix the 12 audit holes, (2) drive-habit feedback, (3) game layer = skill levels built on that feedback, not points, (4) more preset routes. Quality over quantity: a feature that is not solid is cut, not shipped.

## Global Constraints

- Never open app windows on the Mac (no `scripts/screens.sh`, no Simulator). Checks: `swift test`, `scripts/design-lint.sh`, and a compile-only iPhone build: `xcodebuild -project Baxi.xcodeproj -scheme Baxi -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
- Run `xcodegen generate` after adding any file under `Baxi/`.
- Screens use only design tokens (BaxiFont, BaxiColor, BaxiSpace, BaxiRadius); `scripts/design-lint.sh` stays clean.
- The driver never touches the phone; everything on the Drive screen is for a passenger or a glance.
- No API keys, no LLM at runtime, all habit feedback computed on the phone.
- Copy: plain, sentence case, second person, no jargon a 15-year-old wouldn't know. Habit feedback is coaching, never scolding ("Ease off a little on…", not "Violation").
- Habit thresholds are Baxi's own design, not Indiana law; say so in README next to the skill goals.
- Older `DriveRecord`s (empty new fields) must still load and display.
- `git pull --rebase` before every push; partner pushes PRs.
- Update `AI_DISCLOSURE.md` dated log with what was built and real test counts at the end.

## Review Focus

1. GPS gives `speed < 0` (invalid) or no fixes for a stretch → those samples are skipped, the report says "not enough GPS to judge" rather than a perfect score. (Task 4 test `invalidSpeedsIgnored`, `tooFewSamplesGivesNoReport`.)
2. A route with no speed-limit tags at all → no speeding line, no division by zero, report still shows the rest. (Task 4 test `noLimitsNoSpeedLine`.)
3. A replay/demo drive → report is shown labeled as a demo and is clean (replay stops at stop signs), so the judge demo never scolds. (Task 5 test `replayReportIsClean`.)
4. Reroute mid-drive → samples from both routes count; along-positions are per route so stop-sign matching uses the route that was active. (Task 5 test `rerouteKeepsSamples`.)
5. Old records without habits → Log trend skips them; Arrived for a manual drive shows no habits card. (Task 6 test `oldRecordsDecodeEmpty`.)

---

### Task 1: Routes start where you are; search and loading never sit silent

**Files:**
- Create: `Baxi/Services/CurrentLocation.swift`
- Modify: `Baxi/App/AppStore.swift` (home/origin, `level` persistence, `routeTo`, `startDemoDrive`, new `routeStep`), `Baxi/Screens/RouteView.swift:113-215`, `Baxi/Screens/HomeView.swift` (DemoRow), `Baxi/Services/OverpassService.swift:77`
- Test: `BaxiTests/ReviewFixTests.swift` (add)

**Interfaces:**
- Produces: `enum CurrentLocation { static func once(timeout: TimeInterval = 4) async -> Coordinate? }` (nil when denied, no fix, or timeout). `AppStore.origin: Coordinate` (last fix, else `carmelDemoHome`), `AppStore.originLabel: String` ("Your location" / "Carmel City Center (demo)"). `AppStore.routeStep: String?` ("Finding a route…", "Loading lanes and roundabouts…", nil when idle). `AppStore.isStartingDemo: Bool`. `RouteService.origin(fix: Coordinate?) -> Coordinate` (pure, tested; lives in Services so `swift test` sees it).

- [ ] **Step 1:** Write failing tests: `originFallsBackToCarmel` (`RouteService.origin(fix: nil) == AppStore.carmelDemoHome` coordinates 39.9765, -86.1281), `originUsesFix` (a fix 200 km away is used as is). Run `swift test --filter ReviewFixTests`: FAIL.
- [ ] **Step 2:** Implement `RouteService.origin(fix:)` and `CurrentLocation.once` (a CLLocationManager wrapper with a continuation; accept fixes with accuracy < 100 m and age < 60 s). Run tests: PASS.
- [ ] **Step 3:** AppStore: when Routes appears and when `routeTo` runs, refresh `origin` from `CurrentLocation.once()`; `routeTo` routes from `origin`; search region centers on `origin`. Persist `level` through UserDefaults key `experienceLevel` (didSet write, init read).
- [ ] **Step 4:** `routeStep` set to "Finding a route…" before OSRM, "Loading lanes and roundabouts…" before Overpass, nil after. Cap the whole Overpass corridor fetch at 10 s total (task group race with a sleep); on timeout fall through to the existing `roadDataNote`.
- [ ] **Step 5:** RouteView: under the shimmer show `store.routeStep` in `BaxiFont.footnote`; while `store.isPreparing` show "Getting the route ready…" with a small ProgressView under the disabled buttons. Search: run on change of `query` debounced 350 ms (`.task(id: query)` with `try await Task.sleep`), and on Return. Distinguish outcomes: a thrown error → row "No connection. Check the internet and try again."; empty results with a non-empty query → row "No places found for "<query>"".
- [ ] **Step 6:** Home DemoRow: `store.isStartingDemo` true from tap until `activeSession` is set; row shows a ProgressView in place of the play icon and ignores taps while true.
- [ ] **Step 7:** `swift test` all pass; design lint clean; iPhone compile-only build succeeds. Commit `Routes start from your location; search, loading and demo show what they're doing; level remembered`.

### Task 2: Drive screen holes

**Files:**
- Modify: `Baxi/Screens/DriveView.swift` (End button ~346, night mode ~50, save ~148, status banner), `Baxi/Services/DriveSession.swift` (reroute failure, waiting-for-GPS), `Baxi/Screens/ArrivedView.swift` (log line)
- Test: `BaxiTests/DriveSessionTests.swift` (add)

**Interfaces:**
- Produces: `DriveSession.rerouteFailedText = "No connection for a new route. Head back to the blue line."`; `DriveSession.hasFix: Bool`; `static let minLoggedMeters = 200.0` on `DriveSession`; `static func shouldLog(mode:seconds:meters:) -> Bool` (pure).

- [ ] **Step 1:** Failing tests: `shouldLogNeedsMovement` (`shouldLog(.live, 600, 50) == false`, `(.live, 600, 250) == true`, `(.live, 30, 5000) == false`, `(.replay(4), 600, 9000) == false`).
- [ ] **Step 2:** Implement `shouldLog`; DriveView.save uses it. ArrivedView's not-logged line: live and short → "Drives under a minute or 200 m aren't logged."
- [ ] **Step 3:** Reroute failure: on nil approach set `lastCueText = rerouteFailedText` and say it once per failure streak (reset when back on route).
- [ ] **Step 4:** `hasFix` false until the first live fix; DriveView shows "Waiting for GPS…" in the sign area while false on a live drive. When `lastCueText == locationOffText`, show an "Open Settings" button (`UIApplication.openSettingsURLString`) for the passenger.
- [ ] **Step 5:** End: `confirmationDialog("End this drive?")` with "End drive" (destructive) and "Keep driving". Replays end without asking.
- [ ] **Step 6:** Night mode: re-evaluate every 60 s with a `TimelineView(.periodic(from: .now, by: 60))` or a `.task` loop, animated.
- [ ] **Step 7:** Tests, lint, iPhone build. Commit `Drive: confirm End, open Settings when location is off, say when rerouting fails, log only real drives, dark after sunset mid-drive`.

### Task 3: Log edit, undo, form fixes; Settings shows real data status

**Files:**
- Modify: `Baxi/Screens/LogView.swift` (rows ~60, AddDriveView ~290), `Baxi/Screens/SettingsView.swift:64`
- Test: `BaxiTests/DaylightAndLogTests.swift` (add)

**Interfaces:**
- Produces: `DriveLog.overlaps(_ start: Date, _ end: Date, with rows: [LogRow], excluding: UUID?) -> Bool` in `Baxi/Core/DriveLog.swift` (needs `LogRow.id: UUID?`; manual and saved rows carry the record id).

- [ ] **Step 1:** Failing tests: `overlapDetected` (10:00–11:00 vs 10:30–11:30 → true), `touchingIsNotOverlap` (10:00–11:00 vs 11:00–12:00 → false), `excludingSelf` (editing a row does not overlap itself).
- [ ] **Step 2:** Implement; PASS.
- [ ] **Step 3:** AddDriveView becomes `DriveFormView(record: DriveRecord?)`: add or edit (manual records: start, end, where; recorded drives: only the "where" title is editable, times locked with a footnote saying why). Changing Started moves Ended to keep the same length (clamped to now). Overlap shows an orange footnote "This overlaps a drive already in your log" and Save stays enabled (it may be a correction).
- [ ] **Step 4:** Tap a row → edit sheet. Swipe delete → confirmation "Delete this drive? It comes off your hours." Keep the deleted record's values for 5 s and show an "Undo" banner that re-inserts it.
- [ ] **Step 5:** Settings "Road data" row shows `store.dataStatus` and, when a searched route loaded corridor data, "Carmel, plus roads along your last route".
- [ ] **Step 6:** Tests, lint, build. Commit `Log: edit and undo, overlap warning, form keeps End after Start; Settings shows real road data`.

### Task 4: DriveHabits logic (pure, tested)

**Files:**
- Create: `Baxi/Core/DriveHabits.swift`
- Test: `BaxiTests/DriveHabitsTests.swift`

**Interfaces:**
- Produces:
```swift
struct SpeedSample: Codable, Equatable { let t: TimeInterval; let along: Double; let mps: Double; let limitMph: Int? }
struct HabitReport: Codable, Equatable {
    var trackedMinutes: Double
    var overLimitShare: Double?        // fraction of tracked time > limit + 5 mph, nil when no limits known
    var topOverMph: Int?               // highest mph over the limit, nil when never over by > 5
    var schoolZoneTopMph: Int?         // top speed inside school zones, nil when none driven
    var stopSigns: Int; var fullStops: Int
    var hardBrakes: Int
    var merges: Int; var mergesUpToSpeed: Int
    var score: Int                     // 0...100
    var isDemo: Bool
}
enum DriveHabits {
    static func report(samples: [SpeedSample], stopSignAlongs: [Double], schoolZones: [ClosedRange<Double>],
                       mergeAlongs: [Double], isDemo: Bool) -> HabitReport?   // nil when < 2 minutes of valid samples
    static func tips(_ r: HabitReport) -> [String]                           // at most 3, best first
    static func encode(_ r: HabitReport?) -> String; static func decode(_ s: String) -> HabitReport?
}
```
Rules (Baxi's own, recorded in README): over = mph > limit + 5. Full stop = min speed < 1.3 m/s (3 mph) between 25 m before and 10 m after the sign. Hard brake = deceleration > 3.4 m/s² between consecutive samples at least 0.5 s apart starting above 4.5 m/s; events within 5 s count once. Merge up to speed = speed at 150 m past the merge ≥ limit − 10 mph (limit unknown → ≥ 45 mph). School zone top = max mph in any zone range. Score = 100 − min(30, overLimitShare×100) − 8×rolling stops − 6×hard brakes − 5×slow merges − (10 if schoolZoneTopMph > 20), floored at 0. Samples with `mps < 0` are dropped.

- [ ] **Step 1:** Failing tests, each with synthetic samples at 1 s spacing:
  - `cleanDriveScores100` (30 mph in a 35 for 5 min → score 100, overLimitShare 0, tips == ["Clean drive. Keep it up."] first line)
  - `speedingShareAndTop` (half the time at 45 in a 35 → overLimitShare ≈ 0.5, topOverMph 10)
  - `fullVsRollingStop` (two signs: one reaches 0.5 m/s, one bottoms at 3 m/s → stopSigns 2, fullStops 1)
  - `hardBrakeCountedOnce` (13 m/s to 5 m/s over 2 s → hardBrakes 1)
  - `mergeUpToSpeed` (limit 55, 52 mph at +150 m → merges 1, mergesUpToSpeed 1; 35 mph → 0)
  - `schoolZoneTop` (28 mph inside a zone → 28)
  - `invalidSpeedsIgnored`, `tooFewSamplesGivesNoReport` (90 s → nil), `noLimitsNoSpeedLine` (all limits nil → overLimitShare nil, no speed tip)
  - `encodeRoundTrip`, `decodeEmptyIsNil`
- [ ] **Step 2:** Run: FAIL (types missing). Implement. Tips copy: speeding → "You were over the limit for N% of the drive, mostly by about X mph. Ease off a little."; rolling → "N of M stop signs were rolling stops. Come to a full stop and count to two."; hard brakes → "N hard stops. Look further ahead and brake earlier."; slow merge → "Merge at highway speed: speed up on the ramp."; school zone → "Top speed in a school zone was X mph. School zones are 20 when the lights flash." Clean → "Clean drive. Keep it up."
- [ ] **Step 3:** Run all tests: PASS. Commit `DriveHabits: speed vs limit, full stops, hard braking, merge speed, school zones`.

### Task 5: DriveSession records samples; record stores the report

**Files:**
- Modify: `Baxi/Services/DriveSession.swift` (startLive passes CLLocation speed; `feed` gains `speedMps: Double?`; replay slows to a stop at stop signs; `habits`), `Baxi/Models/DriveRecord.swift` (`habitsJSON: String = ""`, `habits: HabitReport?`), `Baxi/Screens/DriveView.swift:148` (pass habits into the record)
- Test: `BaxiTests/DriveSessionTests.swift`

**Interfaces:**
- Consumes: Task 4 types.
- Produces: `DriveSession.feed(_:at:speedMps:)` (existing callers default `speedMps: nil` → derived from replay speed in replays, skipped live); `DriveSession.habits: HabitReport?` (computed after `end()`); `DriveSession.currentMph: Int?` (latest valid speed, for Task 6's indicator); `DriveRecord(…, habits: HabitReport?)`.
- Stop-sign and school-zone positions: from `features` of kind `.stopSign` / `.schoolZone` via `route.polyline.passes(near:within: 20)`; school zone range = pass ± 150 m. Merge positions: `route.maneuvers` with kind `.merge` or `.onRamp`. Rebuilt in `install` on reroute; samples keep the along of the route active when taken, and per-route positions are matched before the swap (store per-route partial lists).

- [ ] **Step 1:** Failing tests: `replayReportIsClean` (simulate `preset_roundabouts`, level `.new`, replay → `habits?.isDemo == true`, `score >= 95`, `fullStops == stopSigns`), `rerouteKeepsSamples` (drive half, `install` a shorter route, drive on → `trackedMinutes` covers both parts).
- [ ] **Step 2:** Implement. Replay speed: within 8 m of a stop sign along → 0.4 m/s (so it visibly stops), and ramps back up.
- [ ] **Step 3:** `swift test`: all PASS, including existing end-to-end preset tests (speech output must not change). Commit `Drives record speed against the posted limit; replays stop at stop signs`.

### Task 6: Show it: Arrived habits card, Log trend, speed indicator, skill levels

**Files:**
- Modify: `Baxi/Core/Practice.swift` (levels), `Baxi/Screens/ArrivedView.swift`, `Baxi/Screens/LogView.swift` (SkillsPanel, trend), `Baxi/Screens/DriveView.swift` (speed pill), `Baxi/Screens/HomeView.swift` (skills row)
- Test: `BaxiTests/PracticeTests.swift`, `BaxiTests/DriveHabitsTests.swift`

**Interfaces:**
- Produces: `Practice.level(_ skill: Skill, count: Int) -> (level: Int, title: String, toNext: Int?)` with levels at 0/25/50/75/100% of `goal` (rounded up): 0 "Not yet", 1 "Started", 2 "Steady", 3 "Confident", 4 "Test-ready"; `toNext` nil at 4. `Practice.levelUps(before: SkillCounts, after: SkillCounts) -> [(Skill, Int)]`. `DriveHabits.trend(_ reports: [HabitReport]) -> (lastScores: [Int], fullStopRate: Double?, overLimitShare: Double?)` over the last 10 non-demo reports.

- [ ] **Step 1:** Failing tests: `levelThresholds` (multiLaneRoundabout goal 10: 0→0, 2→0, 3→1, 5→2, 8→3, 10→4, 14→4 with toNext nil), `levelUpsDetected` (before 2, after 3 two-lane roundabouts → [(.multiLaneRoundabout, 1)]), `trendSkipsDemosAndOld` (`oldRecordsDecodeEmpty`: decoding "" yields nil and is skipped).
- [ ] **Step 2:** Implement; PASS.
- [ ] **Step 3:** ArrivedView: after stats, a "How it went" card: score as a big number in a ring (BaxiColor.accent), up to 3 tips with SF Symbols, a "Demo drive, driven at the limit" caption when `isDemo`, "Not enough GPS to judge this drive" when nil on a live drive. Under it, any level-ups: "Two-lane roundabouts: Steady" with `Haptics.success()` once on appear.
- [ ] **Step 4:** DriveView: next to SpeedLimitSign, a speed pill with `currentMph`; neutral normally, `BaxiColor.warning`-style tint when > limit + 5, animated. Hidden on replays at multiplier > 1 and when nil. Accessibility label "Speed 38, limit 35".
- [ ] **Step 5:** LogView SkillsPanel shows each skill's level title and a segmented 4-step bar instead of a plain count; a "Habits" section with the last 10 scores as a small bar row (Swift Charts `BarMark`) and "Full stops: 9 of 10 lately" style lines. Home: one compact row "Your skills" with 6 small rings, opens the Log.
- [ ] **Step 6:** Tests, lint, build. Commit `Habits card after each drive, live speed pill, skill levels with level-ups, habit trend in the Log`.

### Task 7: Two more practice routes

**Files:**
- Modify: `scripts/build_preset_routes.py`, `Baxi/Services/RouteService.swift:12-16`, `BaxiTests/DriveSessionTests.swift:37`, `BaxiTests/NoisyGPSTests.swift:94,100`
- Create: `Baxi/Resources/Routes/preset_firstdrive.json`, `Baxi/Resources/Routes/preset_signals.json`

- [ ] **Step 1:** Add to PRESETS, inside the cached bbox (south 39.92, west -86.20, north 40.00, east -86.05), waypoints on through roads: `preset_firstdrive` "First drive": quiet residential streets near City Center, ≤ 30 mph, stop signs, right turns, under 4 mi. `preset_signals` "Signals and lane turns": an arterial loop (Range Line Rd / 116th St / Meridian St area) with signals and left turns from multi-lane roads, 5–8 mi. Run `python3 scripts/build_preset_routes.py preset_firstdrive preset_signals`; summaries printed.
- [ ] **Step 2:** Add both to `RouteService.presets` (first drive listed first) and to the parameterized test arguments. Run `swift run baxi-transcript preset_firstdrive new` and `… preset_signals new`: read the transcripts; every line must make sense on the road (no instruction on a side street, no U-turn). Adjust waypoints until clean.
- [ ] **Step 3:** `swift test` all PASS. Commit `Two more practice routes: First drive and Signals and lane turns`.

### Task 8: Polish touches and QA docs (Pickd method)

**Files:**
- Modify: `scripts/design-lint.sh` (hygiene rules), `README.md` (habit and level thresholds are Baxi's own), `AI_DISCLOSURE.md`, `docs/HANDOFF.md`
- Create: `docs/FINAL-QA.md`, `docs/DEVICE-PASS.md`

- [ ] **Step 1:** Hygiene rules appended to design-lint, each at zero: no `print(` in Screens/App outside `#if DEBUG`; no `?? Date()` in Screens; no user-visible "TODO|TBD|lorem|coming soon"; every `Image(systemName:)` used alone as a Button label has `.accessibilityLabel` on the button (grep-level check: Button blocks whose label is only an Image). Fix what it finds.
- [ ] **Step 2:** Haptics: `Haptics.tap()` when a cue is spoken on a live drive (soft), `Haptics.success()` on arrival. Animated (`withAnimation(.snappy)`) state changes for the speed pill, Then chip and banners where they currently snap.
- [ ] **Step 3:** FINAL-QA.md: Claude / You split, each item with how to check, covering everything in Tasks 1–7 plus SHIP-CHECKLIST items. DEVICE-PASS.md: one page, about 20 minutes on the iPhone, in order: first run, search from your location, preview, demo drive, short real drive (passenger holds the phone; check speed pill, stop-sign stop, Arrived card), Log edit/undo, official PDF export, dark mode, largest text, VoiceOver.
- [ ] **Step 4:** Update README thresholds note, AI_DISCLOSURE dated Oct 24 entry with real test counts, HANDOFF. Release build installed on the iPhone (xcodebuild Release `-derivedDataPath build/device -allowProvisioningUpdates`, then `xcrun devicectl device install app`). `git pull --rebase`, push.

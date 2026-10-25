# Baxi UI inventory (Oct 25, before the rebuild)

The checklist for the UI rebuild (docs/UI-REBUILD-BRIEF.md): every screen, every state and every action
the app has today. Each one must exist and work after the rebuild. Tick when the new screen has it.

## App frame
- [ ] Three tabs: Home, Routes, Log (`AppStore.tab`; Home can switch tabs).
- [ ] Welcome on first launch (`didFinishWelcome`), not shown when launched with `--demo-drive` / `--skip-welcome`.
- [ ] Drive opens full screen over everything when `store.activeSession` is set; closing it returns to the tab.
- [ ] Launch arguments keep working: `--screen welcome|preview|arrived|driver-details`, `--demo-drive`, `--replay-speed`,
  `--replay-start`, `--skip-welcome`, `--reset-welcome`, `--tab route|log`, `--route <preset>`, `--carmel-demo`,
  `--snap`, `--appearance`, `--big-text`, `--sample-drives`, `--phone-window` (Debug).

## Welcome (first launch)
- [ ] Pages: what Baxi does (a sample cue), the safety rule (driver never touches the phone; Indiana law), privacy
  (what leaves the phone: Apple search with location, OSRM start and end, Overpass path minus 200 m ends, NWS 1 km,
  nothing during a drive except a reroute; drives stay on the phone).
- [ ] Next; last page "Allow location and start" (requests When In Use); "Not now, just the demo".
- [ ] Can't be swiped away.

## Home
- [ ] Where-to search entry (opens Routes with search focused: `store.wantsSearch`).
- [ ] The four practice routes (First drive, Roundabout loop, Parkway loop, Highway ramp loop) with miles and what
  they practice; tap → choose preset, go to Routes.
- [ ] Hours toward 50 (10 at night), tap → Log.
- [ ] Skills: six skills with levels (Not yet → Test-ready), levels reached of 24, tap → Log.
- [ ] Demo drive: replay of the highway loop at 4x from 4,400 m; shows starting state; second tap ignored; not logged.
- [ ] Settings entry.
- [ ] States: loading road data (preset miles/skills empty until built), no drives yet, many drives.

## Routes
- [ ] Map: route line, yellow lane-change zones, hard-spot dots by kind, start flag, your location, locate button,
  compass; with no route: around you, else Carmel.
- [ ] Search: type → places (debounced), Return, clear, cancel; "No places found", "No connection", searching.
- [ ] Pick a place → route from your location: steps "Finding a route…", "Loading lanes and roundabouts…"; error with
  way back; Fastest / Calmer choice (time, miles at 45+ mph) when offered; road-data note when lane data failed.
- [ ] Practice routes list; pick one.
- [ ] Chosen route: name, close back to list, distance, minutes, roundabouts, ramps, lane-zone hint (or "no lane
  details" for Apple routes), weather (alert first), Preview, Replay at 1x/4x/8x/16x (not logged), Start drive,
  preparing state ("Getting the route ready…"), mount-the-phone safety line.
- [ ] Preview sheet → Start drive starts after the sheet closes.

## Preview (sheet)
- [ ] Route name and summary; hard spots in order: Look Around imagery from just before each (map when no imagery),
  title, what Baxi will say, lane strip, crash/study context with source, students' manual briefing when written,
  unverified lane-count label; empty state when the route has no hard spots; Close; Start drive.

## Drive (full screen)
- [ ] Next maneuver: icon or roundabout diagram, distance (numeric transition), instruction, countdown bar, "Then" chip.
- [ ] Lane-change panel while in a zone (lanes from above, target lane lit, chevrons, room left, "Stay in this lane"),
  or lane strip after a lane cue.
- [ ] Light count until the turn.
- [ ] Speed-limit sign; speed pill (orange when >5 over; only on the route).
- [ ] Chips: school zone, crash corridor, railroad, low sun.
- [ ] What Baxi said (banner); off route / rerouting / reroute failed (orange); location off with Settings button;
  "Waiting for GPS…"; "Head to the start of the route".
- [ ] Map: route, traveled part, lane zones, next-maneuver marker, car position (follows).
- [ ] Bottom: Mute/Unmute, distance to go with arrival time (live) or "replay 4×", End (confirm on live drives).
- [ ] Night: dark after sunset, switching mid-drive. Screen stays awake. Status bar hidden.
- [ ] On finish → Arrived sheet; save to log when it qualifies.

## Arrived (sheet over Drive, can't be swiped away)
- [ ] "You made it" / "Drive ended", route name; minutes, miles, night minutes.
- [ ] How it went: score ring, verdict, what was measured (or "Demo drive…"), up to three tips with kinds; "Not enough
  GPS…" when a live drive has no report.
- [ ] Level-ups.
- [ ] You handled: roundabouts, merges and ramps, lane choices.
- [ ] Log line: saved with hours so far / not logged (why) / replay never counts.
- [ ] What Baxi said (folded transcript with distances).
- [ ] Done.

## Log
- [ ] Hours: total of 50, at night of 10, what's left or "requirement met".
- [ ] Skills with levels and counts; the practice route that fills the biggest gap.
- [ ] Habits: last 10 scores chart, full-stop rate, over-limit share; caveat line.
- [ ] Drives by month: day, weekday, title, start time, added by hand, night minutes, miles, duration.
- [ ] Tap a drive → edit (recorded: title only, times locked, stored split; by hand: times, title); overlap warning;
  End follows Start; "Set an end time after the start".
- [ ] Add a drive by hand.
- [ ] Swipe to delete → Undo bar for 5 s (several deletes).
- [ ] Export: Driver details, official State Form 54706 PDF(s), CSV; "Preparing…"; export error with Retry.
- [ ] Empty state (no drives yet).

## Settings (sheet from Home)
- [ ] Experience level (New / Getting comfortable / Nearly licensed) with what each means.
- [ ] Voice: Everything / Just directions; which voice for practice routes and for other routes; speaking speed
  slider; try the voice; tip to download Ava (Premium) when basic.
- [ ] Driver details for export (name, license number).
- [ ] About: the 50 supervised hours, sources, privacy, road data status.
- [ ] Done.

## Driver details
- [ ] Name (last, first, middle initial) and license number, saved on the phone, used on the official form.

# Implementation audit and next steps

Audited October 14, 2026 against the supplied Congressional App Challenge plan and the local repo.
This is an implementation audit, not independent verification of the contest rules or driving law.

## What exists

| Area | Repo evidence | Status |
|---|---|---|
| Native app and main flow | SwiftUI screens, SwiftData DriveRecord, project.yml | Built; phone validation remains |
| Search and routes | RouteView, RouteService, OSRMParser, three bundled preset JSON files | Built, including Apple fallback; live providers not exercised in this audit |
| Route following | Polyline, RouteFollower, out-and-back and loop tests | Built; recovery regression fixes added in this audit |
| Drive | DriveSession, Speaker, DriveView | Built: replay, speech, lane strip, speed and alert display; real audio/GPS still need a phone |
| Experience-level timing | CueScheduler.isImplemented = false | Stub; does not enforce level timing, stale-cue filtering, priority or the 8-second gap |
| Lane selection | LanePicker.isImplemented = false | Student implementation pending; OSRM lane data and generic fallbacks are not completion of this module |
| Roundabout classification | RoundaboutClassifier.isImplemented = false | Partial stub; student leg counting and interchange classification pending |
| Approach bearing | ApproachHeading.isImplemented = false | Stub; Preview uses route bearing fallback |
| Preview imagery | PreviewView, HardSpots | Look Around and map fallback built; heading affects the map, not Look Around's camera |
| Manual content | Resources/Content/briefings.json | Only one empty placeholder; citations/advice not complete |
| Crash information | HIN used by CueListBuilder; FARS and study JSON have loaders | HIN integrated; study intersections and FARS are not consumed by Preview |
| Drive log | DriveLog, Daylight, LogView, DriveRecord | Totals, sunset split, manual entry and CSV built |
| Official form | LogPDF | Summary PDF only; no bundled official PDF or form-field filling |
| Demo tooling | transcript executable, replay, GPX helpers, screen harness | Built; airplane-mode basemap/imagery behavior has not been verified |

## Completed in this pass

- [x] Preserve distance actually driven across repeated route replacements, including a drive that began partway along a route.
- [x] Pause navigation cue scheduling when more than 60 m off the line, including the 10-second detection window.
- [x] Keep progress forward-only when rejoining behind the previous route position.
- [x] Keep the original end timestamp if End is called again.
- [x] Add four regression tests that reproduce the failures before the fixes.
- [x] Expand end-to-end replay tests from three routes at the default level to all nine route/level combinations.
- [x] Add a readiness command so skipped student suites and blank content cannot be mistaken for completion.
- [x] Correct the README's official-form claim and document Codex implementation work.

## Next work, in priority order

1. **Student integration, before recording or road testing.** Vardaan implements LanePicker and CueScheduler;
   partner implements RoundaboutClassifier and ApproachHeading. Both write the five required manual briefings.
   Acceptance: `python3 scripts/check-readiness.py` passes, all four suites run without skips, and each student
   can explain their module. Do not flip the flags merely to satisfy the checker.
2. **Resolve timing requirements, then tune the replay.** The plan says cues are never less than 8 seconds apart;
   the scheduler contract currently allows urgent turn/roundabout exceptions. The plan also describes light-based
   lane lead thresholds that the current scheduler contract does not specify. Agree on those rules with the
   student owner before changing the contract. Review all nine preset/level transcripts against the agreed rules.
   At 4x replay, simulated seconds elapse faster than spoken audio; check queued speech on the recording device.
3. **Complete Preview.** Match study intersections within 50 m and FARS points within 75 m, display source links
   and factual counts, expose unverified lane data, and add the lane strip. Test missing imagery and absent datasets.
   No new driving advice should bypass the students' reviewed content.
4. **Implement official form export.** Obtain and verify the current official PDF, bundle it, fill its actual
   fields with PDFKit, add driver name/permit settings, and handle multiple pages. Acceptance: exported rows and
   totals open correctly in Preview and Acrobat, with signatures left blank. Until then retain the summary label.
5. **Live-drive resilience and privacy.** Persist experience level; use an actual selected/current origin rather
   than always routing searches from the demo home. Handle failed SwiftData saves and failed exports visibly.
   Review asynchronous reroutes for stale results if the car rejoins while a request is in flight. Document that
   live route requests send coordinates to OSRM/Apple. The newer implementation auto-reroutes despite the earlier
   PRD non-goal; retain that existing behavior pending a team scope decision.
6. **Device and submission pass.** Signing, iPhone audio/GPS, accessibility, offline replay, fresh-clone build,
   actual PDF review, student explanations, video and written answers. Follow SHIP-CHECKLIST.md. The repo cannot
   establish whether registration, invitations, the MPO email or the developer agreement are complete.

## Verification in this pass

- Full Swift logic run passes: 65 discovered tests, including 22 skipped student tests (43 active tests).
  The preset integration test includes nine route/level cases. This verifies replay completion, not the
  unimplemented timing rules or real-world guidance accuracy.
- Four new regression tests were observed failing before their fixes, then passed in the full run.
- Design lint passes.
- Readiness check is expected to fail until student implementations and manual briefings are complete.
- Unsigned iPhone build passes after `xcodegen generate` and `xcodebuild -project Baxi.xcodeproj
  -scheme Baxi -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/baxi-derived-data
  CODE_SIGNING_ALLOWED=NO build`. The first sandboxed attempt could not launch Swift macro plugins;
  an authorized retry outside the sandbox succeeded. Local CoreDevice/Simulator version warnings remain.
  No on-device run was performed.

For a sandboxed Mac runner, the tested command was:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/baxi-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/baxi-swift-cache \
  swift test --disable-sandbox --cache-path /tmp/baxi-spm-cache
```

The ordinary local command remains `swift test`. Existing Speaker concurrency and unused-variable warnings
were observed on this Mac's SDK; they are not resolved by this pass.

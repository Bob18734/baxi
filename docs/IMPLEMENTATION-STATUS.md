# Implementation audit and next steps

Audited October 14, 2026 against the supplied Congressional App Challenge plan and the local repo.
This is an implementation audit, not independent verification of the contest rules or driving law.

## October 22 update

Synced through ffd5a4a. Built official State Form 54706 export with optional local driver details,
108 drives per two-page PDF, additional complete PDFs for overflow, blank signatures and visible
export failures. See OFFICIAL-LOG-EXPORT.md. Manual briefings remain incomplete.

## October 17 update

Synced main through ed867b2 before this pass. The decision modules, route-corridor data loading,
practice tracking, weather, glare, railroad cues and Drive visuals had already landed upstream.
This pass completes Preview's lane strip and source context: study points within 50 m, FARS within
75 m, separate card types, source links, factual counts (missing values stay unknown), and unverified
roundabout lane-count labels. Matching preserves separate passes on loops. FARS and study-only
Preview matches add no spoken cues; existing study announcements remain unchanged.

Eight new tests cover matching thresholds, repeated passes, source-link fallbacks, missing counts,
empty datasets, unknown dates, lane strips and missing lane tags. Manual briefings and official-form
field filling remain the next incomplete deliverables. The original audit below is retained as history.

Verification on Oct 17: 107 active tests pass; three opt-in live-network tests are skipped (110 discovered).
All nine preset/level replay combinations pass. Design lint and whitespace checks pass. Unsigned iPhone
and debug Mac Catalyst builds succeed. Mac screenshots confirm the historical-record card, its collapsed
source section, and the unverified roundabout label render correctly. No iPhone installation, road test,
expanded-source interaction or accessibility-size review was performed.

## What exists

| Area | Repo evidence | Status |
|---|---|---|
| Native app and main flow | SwiftUI screens, SwiftData DriveRecord, project.yml | Built; phone validation remains |
| Search and routes | RouteView, RouteService, OSRMParser, three bundled preset JSON files | Built, including Apple fallback; live providers not exercised in this audit |
| Route following | Polyline, RouteFollower, out-and-back and loop tests | Built; recovery regression fixes added in this audit |
| Drive | DriveSession, Speaker, DriveView | Built: replay, speech, lane strip, speed and alert display; real audio/GPS still need a phone |
| Experience-level timing | CueScheduler | Implemented Oct 14 (Claude): level timing, stale-cue filtering, priority, the 8-second gap, maneuver ordering |
| Lane selection | LanePicker | Implemented Oct 14 (Claude): turn:lanes, standard two-lane roundabout markings, "either lane" when several go straight |
| Roundabout classification | RoundaboutClassifier | Implemented Oct 14 (Claude): lanes, legs counted by traffic flow at the circle, interchange |
| Approach bearing | ApproachHeading | Implemented Oct 14 (Claude); aims the Preview map |
| Preview imagery | PreviewView, HardSpots | Look Around and map fallback built; heading affects the map, not Look Around's camera |
| Manual content | Resources/Content/briefings.json | Only one empty placeholder; citations/advice not complete |
| Crash information | HardSpots, PreviewContext, PreviewView | HIN, studied intersections and FARS in Preview with source details; FARS remains silent |
| Drive log | DriveLog, Daylight, LogView, DriveRecord | Totals, sunset split, manual entry and CSV built |
| Official form | OfficialLogPDF, DriverDetailsView | Official fields filled; overflow shares separate editable PDFs; phone and Acrobat checks remain |
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

1. **Manual briefings and module walkthroughs, before recording.** The four decision modules were written by
   Claude on Oct 14 (AI_DISCLOSURE.md). The students write the five required manual briefings.
   Acceptance: `python3 scripts/check-readiness.py` passes, all four suites run without skips, and each student
   can explain their module. Do not flip the flags merely to satisfy the checker.
2. **Resolve timing requirements, then tune the replay.** The plan says cues are never less than 8 seconds apart;
   the scheduler contract currently allows urgent turn/roundabout exceptions. The plan also describes light-based
   lane lead thresholds that the current scheduler contract does not specify. Agree on those rules with the
   student owner before changing the contract. Review all nine preset/level transcripts against the agreed rules.
   At 4x replay, simulated seconds elapse faster than spoken audio; check queued speech on the recording device.
3. **Preview implemented Oct 17.** Study intersections within 50 m, FARS within 75 m, source links and counts,
   unverified lane-count labels and lane strips are built. Complete phone checks for source-link opening,
   VoiceOver, large text and missing imagery. No new driving advice bypasses the students' content.
4. **Official form export implemented Oct 22.** Check sharing and printing on the phone and open the forms
   in Preview and Acrobat. Signatures remain blank; the original form has no totals field, so totals stay
   in the app and CSV.
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

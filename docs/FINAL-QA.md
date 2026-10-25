# Baxi: final QA before submitting

**What this is.** The last pass before the Congressional App Challenge submission. Not what is left to
build (that is `docs/SHIP-CHECKLIST.md`), but everything to double-check so what judges see is right.
Built Oct 24 from a code audit of every screen, two review agents on the Oct 24 changes, and the ship
checklist. The phone part is short enough to follow on its own: [DEVICE-PASS.md](DEVICE-PASS.md).

**How to tick.** Write the date and how it was checked ("Oct 25, ran X, printed Y" / "on the iPhone").
An unticked box beats one ticked from memory.

**Who.** **Claude** = checked by command or in code, no app windows on the Mac. **You** = on the iPhone.

---

## A. Checked by Claude (Oct 24, branch final-push)

- [x] `swift test`: 160 tests in 42 suites pass on the Mac (Oct 24, after the last commit of the day).
- [x] `scripts/design-lint.sh` clean, including the new hygiene rules (no `print(` in screens, no unexplained
  `?? Date()` in a screen, no TODO/FIXME/TBD/lorem/"coming soon"). Mutation-checked: a planted TODO fails it.
- [x] A fresh clone of the branch runs `xcodegen generate` and compiles for iPhone in Release (Oct 24).
- [x] Warnings in our code: one, from before today (`Speaker`: AVSpeechSynthesizer is not Sendable). Left alone
  on purpose the day before submitting; it does not affect behavior.
- [x] Privacy text matches what the app sends: Welcome, Settings > Privacy and the location permission prompt now
  say location is used during a drive and once on Routes so a searched route starts where you are.
- [x] Every practice route replayed end to end at all three levels, and under simulated bad GPS (drift,
  30 s dropouts, 40 m jumps): same instructions in the same order, no false "off the route", distance within 1%.
- [x] The judge demo (Home > "Watch a 3-minute demo drive") runs about 2 min 50 s and its "How it went" card
  is clean: no hard stops, full stops at every judged stop sign, nothing over the limit.
- [ ] `python3 scripts/check-readiness.py` passes. **Fails today on the student-written briefings** (below).

## B. Students (no AI)

- [ ] `Baxi/Resources/Content/briefings.json`: single-lane roundabout needs a title and how-to; multi-lane
  roundabout, interchange roundabout, highway ramp and school zone need an entry each. Quote the Indiana
  Driver's Manual exactly, with chapter and page (docs/BRIEFINGS.md). Then run the readiness check.
- [ ] Both students can explain, without notes: how a route becomes cues (CueListBuilder, CueScheduler), how the
  car is followed (RouteFollower), how the habit score is worked out (DriveHabits), and what AI wrote.
- [ ] AI_DISCLOSURE.md read through by both students; it matches what you will say in the video and the form.

## C. On the iPhone (You): see DEVICE-PASS.md

The full list with steps is in [DEVICE-PASS.md](DEVICE-PASS.md). The ones that matter most for judges:

- [ ] The demo drive from Home with the voice on (not muted, Ava Premium installed).
- [ ] A searched route starts from where you are, not Carmel City Center.
- [ ] A short real drive with a supervising adult: speed pill, a full stop at an all-way stop, the Arrived
  "How it went" card, and the drive in the Log.
- [ ] The official State Form 54706 PDF exports and opens.

## D. What changed on Oct 24, and how each part could go wrong on camera

| Area | Change | What to watch |
|---|---|---|
| Routes | Searched routes start at your location; search while typing; "No places found" / "No connection"; loading steps | First search asks for location permission. Allow it. |
| Drive | End asks first; Settings button when location is off; "Waiting for GPS…"; reroute failure said once; dark after sunset mid-drive; speed pill | Speed pill appears only when the phone knows the speed. |
| Arrived | "How it went": score ring, up to three tips, level-ups | A drive under 2 minutes gets no card. That is on purpose. |
| Log | Tap a drive to edit; swipe to delete with Undo; overlap warning; Habits chart; skill levels | Recorded drives keep their times (only the name changes). |
| Home | Skills row with levels; demo button shows progress | |
| Routes list | New "First drive" practice route (2.4 mi, downtown all-way stops) | |
| Following | One bad GPS fix on a parallel street can no longer skip ahead | |

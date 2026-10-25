# Baxi: submission checklist

**Living document.** Add an item the moment work creates something that must be checked before
submitting. Ticking an item means writing the date and how it was checked, so "checked" and
"assumed" never look the same. Things that take outside waiting come first.

Deadline: **Monday Oct 26, 2026, 12:00 pm EDT.** Target: submit Sunday Oct 25.
Feature freeze Thursday Oct 22. Video recorded Friday Oct 23.

## Waiting on other people

- [ ] Apple developer agreement accepted on the family team (developer.apple.com/account), so Baxi
  can be installed on a phone. Or: add Vardaan's own Apple ID as a free personal team in Xcode
  (installs expire after 7 days, fine for the video).
- [ ] Team registered on the Congressional App Challenge site for Indiana's 5th District.
- [ ] Partner accepted the GitHub invite to Bob18734/baxi.

## Student work (no AI)

- [x] The four decision modules implemented and their tests running (Oct 14, Claude, disclosed in
  AI_DISCLOSURE.md; checked with `swift test`, 68 pass, none skipped).
- [ ] Vardaan can explain LanePicker and CueScheduler, the partner RoundaboutClassifier and ApproachHeading.
- [ ] `Baxi/Resources/Content/briefings.json`: one entry per kind in docs/BRIEFINGS.md, each with
  the manual's chapter and page, the quote copied exactly.
- [ ] Both students can walk a judge through CODE_TOUR.md without notes.
- [ ] Written answers for the submission form.

## On the phone (needs signing)

- [ ] Installs and launches on Vardaan's iPhone 17.
- [ ] Welcome screen, location permission prompt, "Not now, just the demo".
- [ ] Demo drive from Home: voice is clear, cues are not cut off, lane strip and light count show,
  Arrived screen at the end, nothing logged.
- [ ] One real drive with a supervising adult (phone mounted before moving, passenger watches the
  screen): cues on time, reroute when a turn is missed, drive saved to the Log with a day/night split.
- [ ] Screen stays awake on the mount for a whole drive; audio ducks music and comes back.
- [ ] Preview: Look Around loads on cellular; the spots with no imagery show the map.
- [ ] Log: add a drive by hand, delete one, export the PDF and CSV and open both.
- [ ] Dark mode, and the Drive screen after sunset.
- [ ] Largest accessibility text size (Settings, Accessibility, Display and Text Size, Larger Text):
  Home, Routes panel, Log and Arrived still readable with nothing cut off. The Mac screenshots cannot
  check this.
- [ ] VoiceOver reads the Drive screen's sign, lane strip, light count and speed limit sensibly.

- [ ] Starting point: allow/deny location, test a fresh GPS fix, search a place, and confirm the route starts there.
- [ ] Switch starting points or select a practice loop while a route is loading; old results must not replace it.
- [ ] Relaunch: warning level is retained and starting point resets to the labeled demo location.

## Before the freeze (Oct 22)

- [ ] `python3 scripts/check-readiness.py` passes; all four student test suites execute without skips.
- [x] Official State Form 54706 field filling implemented, including overflow and optional driver details.
- [ ] Verify official exports in Preview and Acrobat, and share/print from the iPhone.
- [ ] Remaining Preview gaps and cue-timing contract differences in docs/IMPLEMENTATION-STATUS.md resolved.
- [ ] `swift test` green; the iPhone build compiles with no warnings we added.
- [ ] `scripts/design-lint.sh` clean.
- [ ] Fable security and privacy review (Oct 21): nothing leaves the phone except the destination
  search (Apple), the route endpoints (OSRM, also on a reroute) and a searched route's path without its
  first and last 200 m (Overpass, for its road data), the route's start rounded to
  about 1 km (National Weather Service); the Welcome screen says exactly this; no keys in the repo; privacy manifest matches.
- [ ] AI_DISCLOSURE.md has an entry for every day AI was used, including the review agents.
- [ ] README build steps work from a fresh clone (`xcodegen generate`, open, run).
- [ ] App icon final (the current one is a placeholder from scripts/make_icon.swift).

## Video (Oct 23)

- [ ] Every app shot is a real screen recording from the phone. Higgsfield is used only for the
  intro, title cards and the lane-cue explainer.
- [ ] Shows: the problem, the demo drive with voice, Preview with Look Around, the Log and the PDF,
  and each student explaining their own module.
- [ ] Says what AI did and did not do, matching AI_DISCLOSURE.md.

## Submit (Oct 25)

- [ ] Repo public, or access given as the rules require; README at the top.
- [ ] Video uploaded and the link opens logged out.
- [ ] Form submitted; confirmation email saved.

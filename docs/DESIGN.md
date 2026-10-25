# Baxi design

Written Oct 25, 2026, for the UI rebuild (docs/UI-REBUILD-BRIEF.md). It replaces the earlier design entirely.

## The idea

Baxi is the calm passenger who knows the way. Every screen reads like a traffic signal: one thing to look
at, and colour that means exactly what it means on the road.

Why: a new driver is nervous, and everything they look at is competing with the road. A traffic signal
works because it has three colours that never mean anything else and you read it in a fraction of a
second. Baxi borrows that discipline, not the look of a road sign. Green means go, amber means get
ready, red means stop, and nothing else in the app is coloured.

## Who it is for, and when

- **Planning at home**: sitting, relaxed, maybe a parent beside them. Calm, roomy screens with one clear
  next step.
- **In the car**: the phone is mounted at arm's length and read in under a second, in glare or at night.
  The Drive screen shows one instruction, very large, at very high contrast. The lane to be in is the
  brightest thing on it.
- **After the drive**: proud or rattled. Show what went well first, then at most three things to work on,
  and the hours toward the goal.
- **Judges** meet Baxi in a video, so Welcome and Home must say "this was designed" in the first ten seconds.

## What we took from the best, and why

- **Apple Maps' turn card, CarPlay and Waze**: one huge distance, one instruction, nothing else competing.
  That is the Drive screen.
- **Apple Weather**: one big number with a quiet line under it says more than a dashboard. That is Home's
  hours and the Arrived score.
- **Apple Fitness rings**: progress you can read without reading. That is the skills.
- **Things**: no boxes around everything; space and thin lines do the separating. That is every list.

## Colour (each one has one meaning)

Contrast is measured against the colour it sits on (WCAG ratio; 4.5 is the floor for text you read, 3 for
large text and labels).

| Token | Hex | Means | Contrast |
|---|---|---|---|
| `page` | #EEF1F3 | The ground of every planning screen: a cool, overcast daylight grey. Not white, not cream. | |
| `field` | #FFFFFF | Only things you type into or pick from (search, forms). | |
| `ink` | #14202A | Headlines, numbers, the main text. | 14.6 on page |
| `read` | #475561 | Text you read that is not the headline. | 6.8 on page |
| `meta` | #5B6873 | Times, distances, small facts. | 5.0 on page |
| `label` | #75818B | Words you glance at: tab labels, field hints. Steps to `meta` with Increase Contrast. | 3.5 on page |
| `hairline` | #D5DBDF | The only separator. | |
| `go` | #22C58B | Go: the main action, you're on track, done. Signal-light green. Ink text on it. | ink on it 7.4 |
| `goText` | #0B7A55 | Green words on the page ("Saved to your log"). | 4.7 on page |
| `ready` | #F5B700 | Get ready: the lane to move into, heads-ups, more than 5 over the limit. Ink text on it. | ink on it 9.2 |
| `readyText` | #8A5A00 | Amber words on the page. | 5.2 on page |
| `stop` | #D0263E | Stop: End drive, delete, errors. White text on it. | white on it 5.2 |
| `stopText` | #B3172F | Red words on the page. | 6.0 on page |
| `night` | #0D171E | The Drive screen's ground after sunset only. | white on it 18.1 |
| `nightRead` | #A9B6BF | Text you read on `night`. | 8.8 |

Rules: solid fills, no gradients (charts are the only exception). No other hues. On maps, the planned route
is drawn in `ink` with a white edge (a road you are going to drive), lane-change stretches in `ready`, and the
part already driven in `label`.

**One identity, light.** Planning screens are always light. The Drive screen alone goes `night` after sunset,
because glare in a dark car is a safety problem; that is the only dark screen.

## Type

Two families with named roles.

- **Atkinson Hyperlegible Next** (SIL Open Font License, bundled) for headlines, big numbers, primary buttons
  and everything on the Drive screen. The Braille Institute designed it so that letters that look alike
  (I, l, 1; 0, O; 5, S) never do, for readers with low vision. That is exactly the problem of reading at a
  glance from arm's length in a moving car.
- **The system font** for text you read, so it follows the reader's chosen text size.

| Role | Face | Size / weight | Tracking | Use |
|---|---|---|---|---|
| `hero` | Atkinson | 44 ExtraBold, line 0.95 | -1.0 | One per screen at most: Welcome, Home's question |
| `screenTitle` | Atkinson | 30 ExtraBold | -0.6 | Screen and sheet titles |
| `driveDistance` | Atkinson | 76 ExtraBold | -2.0 | Drive: distance to the next move |
| `driveInstruction` | Atkinson | 28 Bold, line 1.05 | -0.3 | Drive: the instruction |
| `number` | Atkinson | 40 ExtraBold | -1.0 | Hours, score |
| `numberSmall` | Atkinson | 24 Bold | -0.4 | Miles, minutes, counts |
| `rowTitle` | Atkinson | 18 Bold | -0.2 | A route or drive name in a list |
| `button` | Atkinson | 18 Bold | 0 | Primary and secondary buttons |
| `tab` | Atkinson | 11 SemiBold (clamped) | 0.2 | Bottom bar |
| `body` | System | body | | Reading text |
| `bodyStrong` | System | body semibold | | A key fact inside reading text |
| `meta` | System | footnote | | Times, sources, small facts |
| `group` | System | subheadline semibold, sentence case | | A group's name above a list ("Practice routes") |

Display sizes follow the reader's text size up to a cap, so nothing clips at the largest size.

## Space, shape, motion, touch

- **Spacing** (pt): 4, 8, 12, 16, 24, 32, 48. Page margin 20. Rows at least 56 tall.
- **Radius**: 12 for fields and tiles, 22 for the top of sheets and panels; buttons are capsules. Nothing else
  is rounded.
- **No shadows**, except the one under a panel that sits on the map.
- **Motion**: `quick` 0.18 s (taps), `standard` 0.3 s (content changes), `reveal` 0.6 s (a score ring
  filling), `press` spring (0.25 s response, 0.7 damping). Numbers change with numeric transitions. Layouts
  never jump.
- **Haptics** by meaning: `tap`, `success`, `error`, `reveal`. Only for the person tapping. Nothing in a moving
  drive depends on one.

## Components (one of each)

- **Bottom bar** (Baxi's own): Home, Routes in the middle (the reason you open the app), Log. It sits on
  `page` with one hairline above it, a fixed height, drawn icons, and a small `go` bar under the active tab.
  The space for that bar is always reserved, so labels never shift. On Routes, the map's panel ends where the
  bar begins. It steps away on the Drive screen.
- **Buttons**: one press language: a dip to 0.95 scale and 0.7 opacity, springing back. `primary` is a
  `go` capsule with ink text, one per screen. `secondary` is an ink outline. `quiet` is ink text. `danger` is a
  `stop` capsule.
- **Working**: the signal. Three small dots in a row light in turn (red, amber, green) inside the button,
  which keeps its width. No spinners anywhere.
- **Done**: the button becomes its finished state with a `success` haptic, or a toast says what happened.
- **Toast**: one ink capsule above the bottom bar, shown from anywhere. Failures say what went wrong in
  plain words.
- **Shimmer**: the shape of what is coming, in a lighter band of `page`. Nothing shows "0 hours" before the
  data loads.
- **Field**: white, radius 12, hairline edge, 52 tall.
- **Row**: full width, hairline between rows, no boxes.
- **Sheet header**: `screenTitle` on the left, a quiet Close or Done on the right. Sheets are only as tall as
  what is in them.
- **Empty state**: the signal mark, one sentence, one action.

## Marks (drawn, not borrowed)

Baxi's icons are drawn in code in one style: a 24 pt grid, 2.25 pt round-capped stroke, no fills except the
signal's lights. They cover the tab icons, the maneuver arrows on the Drive screen, the signal mark, and the
skill marks. System symbols appear only inside system controls (share sheets, pickers).

## Decisions from the second review (Oct 25)

A design critic reviewed every screen against Apple Maps, Waze, Weather, Fitness and Things. What changed:

- **Home has one main action**: "Your next drive", the practice route that does the most for this driver now (First
  drive before any drive is logged), with one green button. The full list of routes lives on Routes, so Home is
  progress and a next step, not a menu.
- **Numbers come from one source.** A route's roundabouts and ramps are counted from its own maneuvers everywhere,
  so Home, Routes and the Log can never disagree.
- **Amber means "change lanes here" on maps.** Hard spots are small ink dots; only crash records are red.
- **Drive has one panel.** What Baxi just said is a quiet line inside the dark panel; the separate strip appears only
  for a state that needs attention (off route, location off, waiting for GPS). The speed limit and the car's speed are
  one unit. The tray says "Demo, not logged" in a replay instead of a debug-looking speed.
- **Arrived leads with the score**: a large ring that fills once, then three small numbers, then the coaching, with
  one line of fine print at the bottom. The school line is labelled "Reminder", because it never lowers the score.
- **Welcome has one hero and one moment**: inside the drive card, the signal lights red, amber, green, then the
  instruction appears and the distance counts down. It is the design idea in two seconds of video.
- **The slashed zero stays.** Atkinson Hyperlegible Next draws 0 with a slash so it can never be read as O; that
  is the reason the face was chosen, and it has no plain-zero variant.

## Rules

1. One primary action per screen. Everything else is visibly secondary.
2. No card inside a card. No box around a section. Space and hairlines separate.
3. Colour only with its meaning. If it doesn't mean go, get ready or stop, it's ink or grey.
4. Fewer words: no internal counts, no legal text on main screens (it lives in Settings), sentence case,
   no exclamation marks, no emoji.
5. Every state is designed: first launch, loading, empty, offline, error, lots of data, night.
6. Readability floor: reading text 13 pt or larger, labels 10 pt, label grey 3:1 or better, tap targets 44 pt.
   Check every screen at the largest text size.
7. Every value is a named token in `Baxi/Design`. `scripts/design-lint.sh` fails on raw numbers and colours in
   screens; a real one-off ends its line with `// design-lint:allow <reason>`.

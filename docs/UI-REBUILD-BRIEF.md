# Baxi UI rebuild brief

Written 2026-10-24, from the Pickd project, for the Claude Code session working on Baxi.

## 0. What this job is

This is a **complete UI rebuild from zero**. It is not a polish pass and it is not an app rewrite.

- **The UI starts from nothing.** Treat every existing screen in `Baxi/Screens`, the look in
  `Baxi/Design/Theme.swift` and `Baxi/Design/Marks.swift`, and the current `docs/DESIGN.md` as if
  they did not exist. Don't open them for inspiration, keep their layouts, or "improve" them. Right
  now the app feels vibe-coded and rushed: lots of parts, no design idea holding them together. Patching
  it will keep that feeling. Rewrite each screen. Delete the old view code; don't add a toggle or keep
  a fallback. Git is the fallback.
- **The app stays the same.** Don't change `Baxi/Core`, `Baxi/Models`, `Baxi/Services` or the app's
  state and store logic, except to expose something a new screen needs to read. Every feature, flow,
  setting, export and piece of data shown today must still be there and must still work afterwards.
  The function is identical. Only the face changes.
- **Safety and contest rules are functional, so they stay:** the driver never touches the phone; the
  Drive screen has only Mute and End, for the passenger; cues are spoken. The `--screen`, demo-drive
  and other launch arguments (the video and `scripts/screens.sh` depend on them) keep working.
  `AI_DISCLOSURE.md` gets a log entry the same day for this work, in the style of the entries already
  there.

You know Baxi and this brief doesn't. So this brief gives you **no colours, fonts or
layouts.** It tells you what made another app (Pickd, the owner's daily social app at
`/Users/vardaangoel/Pickd`) feel hand-made and high quality, so you can reason your way to Baxi's
own version. Pickd's look is a light, playful social game. Baxi is a calm driving co-pilot for
a nervous 16-year-old. The two should look nothing alike. They should share the same level of care.

## 1. Before any code: find the idea

The single biggest reason Pickd doesn't read as AI-made is that **every screen comes from one idea**.
One identity, one page colour, one type pairing, one way to press a button, one way to say "working",
one way to say "done". Nothing on any screen is a one-off.

So, first:

1. **Inventory.** List every screen, every state of it (first launch, empty with no drives yet,
   loading, offline, error, a lot of data, night) and every action. Read the store and models
   to know exactly what each screen shows. This list is your checklist that nothing gets lost.
2. **Who and when.** Think through the three moments: planning at home (sitting, relaxed, a parent
   beside them), in the car (phone mounted at arm's length, sun glare, night, a glance of a second
   or less), and after the drive (proud or rattled; hours toward the goal). Also the judges: they
   meet the app first in a video, so the first ten seconds (Welcome, Home) must look striking and
   deliberate.
3. **Pick one direction and write it down.** Write a new `docs/DESIGN.md` that replaces the old one:
   - the idea in two sentences;
   - the palette, with what each colour **means** and its measured contrast;
   - the type roles;
   - spacing, radius, motion and haptics;
   - the components;
   - the rules.
   Decide everything fresh. If you land near anything the current app does, it must be because you
   reasoned your way there, and the result must still look nothing like today's screens.
4. **Look at the best before choosing.** For driving, study why Apple Maps' turn card, CarPlay's
   guidance and Waze work at a glance: a huge numeral, one instruction, very high contrast, nothing
   else competing. For the planning and log screens, look at calm, confident consumer apps
   (Apple Fitness rings, Apple Weather, Things). Write down what you are taking and why. Load the
   `frontend-design` skill if this session has it.
5. **Pin exact values, then build them literally.** Pickd's first attempt at its main screens failed
   for one reason. The design said 33 pt, 21 pt, radius 15. The code rounded each value to the
   nearest step of a generic scale. Every rounding looked harmless, and the sum was a screen that
   looked like nothing that had been drawn. Decide real values, name them as tokens, and use those.
   Don't round to whatever scale is handy.
6. **Prove it on one screen before building all of them.** Build Home (or Welcome) completely, take
   screenshots with `scripts/screens.sh`, and show the owner. Once he says yes, roll it out.
   The Mac can't run the iOS Simulator; screens.sh (Mac Catalyst) is the way to see the app.

## 2. What made Pickd feel high quality

Read the files named below for the **pattern**. Never copy Pickd's colours, fonts, glyphs or
wording. Each point says what to take from it.

### 2.1 Its own bottom bar, not the stock iOS tab bar
`/Users/vardaangoel/Pickd/Pickd/Views/Components/PaperTabBar.swift`, wired up in `Pickd/Views/RootView.swift`.

The stock `TabView` bar with SF Symbols is the clearest tell of a generic app. Pickd draws its own:

- **Three tabs, and the reason you open the app sits in the middle.** Their visual order isn't
  their code order.
- **It sits on the page colour.** A single hairline separates it from the content above. There's no
  frosted material, no floating pill and no shadow.
- **Fixed height on every screen.** On a tight screen the content gives way, never the bar. Labels
  are clamped so a huge text size can't break it.
- **Its own icons**, drawn as SwiftUI `Shape`s in one consistent stroke style. The active tab gets a
  darker colour, a slightly heavier stroke, a bolder label and a small accent marker under the
  label. The marker's space is always reserved, so the label never shifts when the selection moves.
- **A tap changes tabs with a light haptic and an animation.** Tapping the tab you're already on
  does nothing.
- **Content ends where the bar begins.** The bar isn't laid over the content, so the last row of
  every pushed screen is still reachable.
- **The bar steps aside on immersive screens.** Pickd hides it while the full-screen pick card is up.
  Baxi's equivalent is obviously the Drive screen.
- **Accessibility:** each tab has its label and an `isSelected` trait.

For Baxi, think about how this bar and a map tab live together. A map's bottom panel and a
bottom bar can't fight for the same edge, so decide what happens when the panel is pulled up.
Either tapping between tabs or swiping across them is fine, but never page tabs with a swipe on a
screen whose map also pans.

### 2.2 One button language, everywhere
`Pickd/Utilities/Constants.swift` (`PressableButtonStyle`) and
`Pickd/Views/Components/ActionFeedback.swift`.

Every tappable thing goes through the same three steps:

1. **Pressed:** a visible dip, about 0.95 scale and 0.7 opacity. It goes down fast and springs back
   on release. Don't use `.plain`; it makes presses feel dead.
2. **Working:** the label is swapped for three small bouncing dots, and the button keeps its width
   so nothing jumps. No spinners, ever.
3. **Done:** the button turns into its finished state, or the row leaves, with a haptic. When
   nothing on screen would change, a short toast says what happened. A failure always says what
   went wrong in plain words. A haptic alone is never enough.

There is **one toast**: a small capsule above the bottom bar, shown from anywhere through one shared
centre (`Pickd/Views/Components/InkToast.swift`).

### 2.3 Type: two families with named roles
`Pickd/Utilities/PaperDesign.swift`, `enum AppType`.

- **A display face with character** for headlines, big numbers and primary buttons: heavy weight,
  tight negative tracking, line height just under 1. Use it sparingly, so it stays special.
- **A clean text face for reading.** In Baxi, keep body text in the system font so it follows the
  reader's text size.
- **Roles, not sizes.** Name each style for its job (`screenHeadline`, `subhead`, `eyebrow`,
  `tabLabel`, `primaryButton`…). The headline and the body are far apart in size, and few sizes sit
  in between. Small uppercase eyebrows have wide tracking.
- Choose Baxi's own pairing for its own reasons: legible at a glance and at a distance, and calm.

### 2.4 Colour with discipline
`Pickd/Utilities/PaperDesign.swift`. Read the comments; the reasoning is the point.

- **A considered page colour and ink**, not pure white and pure black.
- **Greys are tiers with jobs:**
  - text you *read* (the only grey that clears 4.5:1 at small sizes);
  - meta;
  - labels you only glance at (eyebrows, tab labels).

  Each one is measured. Pale label greys step darker automatically when iOS's Increase Contrast or
  Bold Text is on, inside the colour token, so no screen can forget.
- **Every accent owns exactly one meaning.** In Pickd one colour means "the main action", one means
  "streak or danger", one means "premium". No colour is decoration.
- **No gradients on chrome. Solid fills.** Data visualisation is the only exception.
- **One identity, not a theme.** Pickd pins light mode. Baxi's Drive screen has a real reason to go
  dark at night, so make that one deliberate decision for that screen. Don't make every screen
  support both.

### 2.5 Everything is a token, and a lint keeps it that way
Every font, colour, spacing, radius, animation and haptic is a named token. Views never write a raw
number or hex value. Baxi already has `scripts/design-lint.sh`; keep the mechanism and point it at
the new tokens. A genuine one-off ends its line with `// design-lint:allow <reason>`.

### 2.6 Restraint
This is where vibe-coded apps fail most.

- **One primary action per screen.** Everything else is visibly secondary.
- **No card inside a card, and no box around every section.** Separate with space and hairlines.
- **Fewer words.** No internal counts, no debug-ish numbers, no legal paragraphs on main screens
  (they go to Settings). Use plain language a 16-year-old reads in one pass.
- **Generous, consistent spacing on one scale** (4, 8, 12, 16, 24, 32 or similar). Alignment is
  exact.
- **Sheets are only as tall as what's in them.** Use `presentationDetents` sized to the content.

### 2.7 Loading and truth
- **Shimmer the shape of what's coming;** never a spinner.
- **Nothing claims a fact before its data has loaded.** No "0 hours", "no drives" or 0% while it's
  still loading. A failed load says so, with a retry.

### 2.8 Motion and haptics with a vocabulary
`Pickd/Utilities/Constants.swift` (`AppAnimation`), `Pickd/Utilities/HapticManager.swift`.

- **A few named animations:**
  - quick, about 0.2 s, for taps;
  - standard, about 0.3 s, for content changes;
  - a slower one for big reveals;
  - springs for anything tactile.

  Animate every state change. Numbers use numeric text transitions. Layouts never jump.
- **Haptics are named by meaning**, not by generator: tap, success, error, reveal. In Baxi they're
  for whoever is tapping, so nothing in a moving drive depends on them.

### 2.9 Drawn, not borrowed, icons
Pickd bans SF Symbols on its core screens and draws its own marks as `Shape`s, all in one stroke
language. Mixed symbol sets beside a custom display face look assembled. Draw Baxi's tab icons and
key marks yourself, all in one style.

### 2.10 Every state is designed
First launch, empty (no drives yet), loading, offline, error, lots of data, night: each gets real
design, not a default `Text("No data")`. The empty state is often the first screen a judge sees.

### 2.11 A readability floor
- Text you read is at least 13 pt, labels at least 10 pt, label greys at least 3:1, tap targets at
  least 44 pt.
- **The owner uses the largest (XXXL) text size on his phone.** Check every screen at XXXL as well as
  the default, and make sure nothing clips or overflows. Fixed-size elements (the bar, signs drawn at
  a set size) clamp their own type.

### 2.12 What gives an app away as rushed or AI-made
Check every screen against this list. Any one of these undoes the rest.

- Stock tab bar, SF Symbols everywhere, a mix of symbol styles.
- Everything in rounded cards with drop shadows; cards inside cards; corner radii that don't match.
- Gradient buttons, system blue as the accent, colours with no meaning, purple for no reason.
- Too many font sizes and weights; title case on every label; everything centred.
- Filler copy: "Let's get started!", exclamation marks, emoji in the UI, a sentence saying what
  the screen already shows, internal numbers ("12 cues", "3 reroutes").
- A chip or badge on everything; three buttons of equal weight; no clear first thing to look at.
- Spinners, layout jumps, controls with no press state, taps that silently do nothing.
- A screen designed only for the happy path (empty, error and offline left as defaults).

### 2.13 Deadline safety
This is for a contest with a deadline. Plan for the rebuild being stopped halfway:

- **Commit per screen** after its checks pass, so `main` always builds and demos.
- **Order screens by what the judges see first:** Welcome, Home, Routes, Drive, Arrived, then
  Log and Settings.
- A new font must be open-licensed (OFL), bundled, and credited in the README's sources, like
  Overpass is now.
- Write `docs/DESIGN.md` in plain words the two students can explain in their written answers and
  the video. They will be asked why it looks the way it does.

## 3. Order of work

1. Inventory, then the new `docs/DESIGN.md`. Tell the owner the direction in a few lines.
2. New tokens: replace `Theme.swift`, and replace `Marks.swift` if the marks change.
3. Components:
   - bottom bar;
   - button styles with press, working and done;
   - toast;
   - shimmer;
   - text field;
   - row;
   - sheet header;
   - empty state.
4. Home (or Welcome) fully built → screenshots at default and XXXL → **owner's yes**.
5. The other screens, rewritten one at a time. Drive comes last and gets the most care: glance-read,
   the next instruction is the biggest thing, the lane to be in is the brightest, night version.
6. Checks, after each screen and at the end:
   - `swift test`;
   - the iPhone build;
   - `scripts/design-lint.sh`;
   - `scripts/screens.sh`, looking at the screenshots yourself;
   - the existing readiness and QA docs.
   Get a code review from a second agent before committing.
7. Update README's screen descriptions and add the `AI_DISCLOSURE.md` entry. Commit.

Run one build at a time; the Mac lags with two.

Done means every screen is rebuilt from the one idea, every feature from the inventory still
works, and the owner has seen screenshots and said yes.

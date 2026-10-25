# Routes tab rework and bug sweep (Oct 25 afternoon)

Brief for the next session. Vardaan tried the build installed at `ea8b49f` on his iPhone and said, in his words:
the Routes tab (the second tab) should let you scroll the panel down to hide the routes list and just show the
map, with the different practice routes drawn on it with numbers so you can tap one. There were glitches when
tapping routes, typing didn't work depending on the page, and overall it felt very buggy, with a lot of things
not working. Quality is the priority; the submission is Mon Oct 26, 12:00 pm EDT.

## 1. What to build: Routes as map plus a sheet that slides down

- **The panel is a sheet you can drag.** It needs three heights: collapsed (only the search field and a grabber,
  so the map fills the screen), medium (the practice routes), and large (search results with the keyboard up).
  Dragging or scrolling it down collapses it; dragging it up brings the list back. It should feel like Apple
  Maps' sheet. Prefer a custom panel with a drag gesture and snap points over `.sheet(presentationDetents:)`:
  that sheet sits above the custom BottomBar (Baxi/Design/BottomBar.swift) and fights the tab layout.
  Either way, the panel must end at the bottom bar, as it does now.
- **With no route chosen, the map shows every practice route** (`RouteService.presets`: First drive, Downtown
  and the Palladium, Roundabout loop, Parkway loop, Highway ramp loop). Each one is a line in its own muted
  shade, with a numbered marker (1 to 5, the same order as the list). The list rows show the same number.
  - Tapping a marker or a line chooses that route, exactly like tapping its row (`store.choosePreset(id)`).
  - Load the five polylines once (they're bundled JSON: `RouteService.preset(id)`).
  - Respect the colour rules in docs/DESIGN.md: no new hues. Use ink and grey shades for the lines; a number
    sign in highway green (`Palette.sign`) fits the guide-sign brand.
- **With a route chosen, the current route card is unchanged.** It has Start drive, Preview the hard spots,
  Replay and Fastest/Calmer, and the sheet sizes to the card. Add a clear way back to all routes (today it's
  `store.clearRoute()` behind the card).

## 2. Bugs to find and fix (confirm each in code before fixing)

1. **Typing (likely root cause, confirmed by reading RouteView.swift:118-123).**
   - `panel` wraps the content in `ViewThatFits`, and both copies contain `searchField` with the same `@FocusState`.
   - When the keyboard or a growing results list changes the space, SwiftUI swaps to the other copy. The
     focused TextField is destroyed, so the keyboard drops or keystrokes are lost.
   - The fix: one TextField that never moves between view trees. The new sheet in part 1 removes `ViewThatFits`.
2. **Tabs stay alive in a ZStack** (Baxi/App/BaxiApp.swift RootView).
   - Hidden tabs keep their TextFields and `.task`s. Check that a hidden Routes tab never holds focus. The
     `onChange(of: store.tab)` sets `searchFocused = false` on leave.
   - Check that Home's search entry (`store.wantsSearch`) focuses reliably on the first tap, including the very
     first time Routes is opened.
3. **Glitches tapping routes.**
   - Look for a double tap starting two `choosePreset` or route loads.
   - The camera jumps twice in `onChange(of: store.route)`: region, then `.automatic` after `Task.yield`.
   - The panel animates three different values at once (`searching`, `route?.id`, `routing`).
   - Find what actually flickers on the phone and fix the cause.
4. **Then sweep every screen** (Home, Routes, Preview, Drive, Arrived, Log, Settings, Welcome) for anything else
   broken: dead buttons, sheets that don't open or open twice, text fields (Log's add-a-drive form, Driver
   details, PriorHoursSheet), and state that's stale after switching tabs. List each bug with file:line and the
   cause before fixing it.

## 3. How to work here (constraints that stay in force)

- **Checks to run:**
  - `swift test`: 174 logic tests. Screens aren't in the package.
  - `scripts/design-lint.sh`: no raw colours, numbers, fonts or SF Symbols in Screens; every value is a token in Baxi/Design.
  - iPhone compile: `xcodebuild -project Baxi.xcodeproj -scheme Baxi -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath build/check build CODE_SIGNING_ALLOWED=NO`.
- **Screenshots:** `scripts/screens.sh` (Mac Catalyst copy, opened in the background with `open -g`). Pass flags
  as separate args, e.g. `scripts/screens.sh --no-build name --skip-welcome --tab route`. The map tiles are
  blank in Mac shots, and Dynamic Type doesn't show. Never open app windows on the Mac any other way, and the
  Mac copy must never ask for location (MapPrivacy, CurrentLocation return nil in DEBUG Catalyst).
- **Install on the iPhone:**
  - Build: `xcodebuild … -configuration Release -destination 'id=00008150-001C74313686401C' -derivedDataPath build/device -allowProvisioningUpdates build`
  - Install: `xcrun devicectl device install app --device 00008150-001C74313686401C build/device/Build/Products/Release-iphoneos/Baxi.app`
  - Don't launch it on the phone without asking. Vardaan may be on FaceTime.
- **Git:** branch `final-push`. Commit when a piece is done and verified. Don't push or merge without asking.
- **Records:**
  - Add a dated entry to AI_DISCLOSURE.md (Oct 25) saying what Claude did, honestly, with the test count.
  - Update docs/DESIGN.md for the sheet and numbered routes, and docs/DEVICE-PASS.md section 3 for the new
    Routes checks.

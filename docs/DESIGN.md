# Baxi design system

Every screen takes its colors, type, spacing and corners from `Baxi/Design/Theme.swift`, and its
road-sign shapes from `Baxi/Design/Marks.swift`. `scripts/design-lint.sh` fails if a screen writes a
raw value (a font size, a hex color, a spacing number) instead of a token.

## The idea

A new driver is learning to read road signs, so Baxi looks like them.

- **Guide-sign green panels** with a white rule inset from the edge (`.signPanel()`): the Drive
  screen's maneuver card, the demo card, the Arrived banner, the chosen route.
- **Warning yellow** (`BaxiColor.warning`) lights the lane to be in, the same yellow as the app icon.
- **School-zone yellow-green** and a pentagon for school zones; **orange** and a diamond for
  crash-heavy roads; **stop red** only for End drive.
- **Overpass** for headings and numbers: an open-source typeface drawn after Highway Gothic, the
  lettering on US highway signs (SIL Open Font License, `Baxi/Resources/Fonts/OFL.txt`). The speed
  limit sign uses it too, so it looks like the real sign. Body text stays in the system font so it
  follows the reader's text size.

## Tokens

| Scale | Names |
|---|---|
| Color | `sign`, `signDeep`, `accent`, `warning`, `school`, `caution`, `stop`, `route`, `signInk`, `page`, `surface`, `sunken`, `ink`, `inkSoft`, `inkFaint`, `hairline`, `onSign` |
| Type (Overpass) | `hero` 40, `title` 28, `section` 22, `headline` 19, `button` 18, `number` 36, `numberSmall` 24, `eyebrow` 13, `signFace(size)` for drawn signs |
| Type (system) | `body`, `bodyBold`, `callout`, `footnote`, `caption` |
| Spacing | `xxs` 2, `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32, `page` 20 |
| Radius | `sm` 8, `md` 12, `lg` 18, `xl` 26 |

`ink` is for text you read; `inkSoft` for secondary sentences; `inkFaint` only for labels you glance
at (eyebrows, units). Colors have light and dark values; the Drive screen turns dark after sunset.

## Components

- `.signPanel(radius:deep:)`, `.card()`, `.baxiPage()`, `Eyebrow("…")`
- Buttons: `.baxiPrimary`, `.baxiSecondary`, `.baxiOnSign`, `.baxiStop`, `PressableStyle` for cards
- `.shimmer()` while something with a known shape loads (Look Around imagery). No spinners there.
- `Haptics.tap()`, `.success()`: for whoever is tapping, the passenger or a parked driver. Nothing in
  a moving drive depends on them.
- Marks: `SpeedLimitSign`, `SchoolZoneChip`, `CrashChip`, `TrafficLightMark`, `LaneArrows`,
  `HoursRing`, `SpotPin`, shapes `Pentagon`, `Diamond`, `Octagon`, `Shield`.

## Rules

1. No raw values in `Baxi/Screens` or `Baxi/App`. A value that truly cannot be a token ends its line
   with `// design-lint:allow <reason>`.
2. Nothing on the Drive screen needs a tap while the car moves. Mute and End are for the passenger.
3. The Drive screen is read at a glance: the distance is the biggest thing on it, the lit lane is
   the brightest.
4. A fact is not shown before it is known. Look Around shimmers until it answers; the hours rings
   come from the saved drives.
5. Animate state changes (`.snappy`, numeric text transitions), never layout jumps.

## Checking screens without the Simulator

The team's Mac cannot run the iOS Simulator, so `scripts/screens.sh` builds Baxi as a Mac app (Mac
Catalyst, Debug only, from `.catalyst.yml`) and photographs screens into `build/screens/`:

```
scripts/screens.sh                                  # build, then every tab and the demo drive
scripts/screens.sh --no-build drive2 --demo-drive preset_highway --replay-start 8790 --appearance light
scripts/screens.sh --no-build arrived --screen arrived      # welcome | preview | arrived on their own
```

The iPhone build is unchanged; the screenshot code (`Baxi/App/ScreenCheck.swift`) is compiled only
in Debug. Known limits: the Routes map and text-size changes do not show in these screenshots, so
check those on the phone.

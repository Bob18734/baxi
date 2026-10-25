#!/bin/bash
#
# design-lint.sh: keeps the screens on the design tokens in Baxi/Design (docs/DESIGN.md). Hard rules, each at
# zero. In Baxi/Screens and Baxi/App, each of these fails the check:
#   a raw colour: Color(hex: / Color(red: / Color(.system / Color.white / .white / .black   use a Palette name
#   a system font: .font(.system( / .font(.body) and friends                                use .role(...)
#   a system symbol: Image(systemName: / Label(..., systemImage:                             draw a Glyph
#   a raw number for a size, spacing, corner, stroke, weight, opacity or animation length    use a token
#   the old design's names: BaxiColor, BaxiFont, BaxiSpace, BaxiRadius, PressableStyle
# Plus the hygiene rules (from the Pickd lint):
#   no print( in the screens and app layer: use the os Logger
#   no ?? Date() in a screen: a missing time is not "now"
#   no placeholder words anywhere in the app: TODO, FIXME, TBD, lorem, "coming soon"
#
# A line that ends in `// design-lint:allow <reason>` is exempt. The reason is required, so each exception
# is a decision on the record. Run: scripts/design-lint.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
check() { # name, pattern, paths...
  local name="$1" pattern="$2"; shift 2
  local hits
  hits=$(grep -rnE "$pattern" "$@" --include='*.swift' | grep -v 'design-lint:allow' | grep -v 'Baxi/App/ScreenCheck.swift')
  if [ -n "$hits" ]; then echo "$name:"; echo "$hits"; fail=1; fi
}

UI="Baxi/Screens Baxi/App"
check "Raw colour (use a Palette name)" 'Color\((hex:|red:|\.system)|Color\.(white|black)|[(: ]\.(white|black)[),]' $UI
check "System font (use .role)" '\.font\(\.(system|body|title|title2|title3|headline|subheadline|callout|footnote|caption|caption2|largeTitle)' $UI
check "System symbol (draw a Glyph)" 'Image\(systemName:|systemImage:' $UI
check "Raw number (use a token)" '(size|width|height|lineWidth|weight|radius|cornerRadius|spacing|minHeight|minWidth|maxHeight): *-?[1-9][0-9]*(\.[0-9]+)?\b|\.padding\([0-9]|opacity\(0?\.[0-9]+\)|duration: *[0-9]' $UI
check "Old design name" 'BaxiColor|BaxiFont|BaxiSpace|BaxiRadius|PressableStyle|\.signPanel|\.baxiPrimary|\.baxiSecondary' Baxi

reasonless=$(grep -rn 'design-lint:allow *$' Baxi --include='*.swift')
if [ -n "$reasonless" ]; then echo "design-lint:allow needs a reason:"; echo "$reasonless"; fail=1; fi

prints=$(grep -rn 'print(' $UI --include='*.swift' | grep -v '#if DEBUG' | grep -v 'design-lint:allow' | grep -v 'Baxi/App/ScreenCheck.swift')
nowdates=$(grep -rn '?? Date()' Baxi/Screens --include='*.swift' | grep -v 'design-lint:allow')
placeholders=$(grep -rniE '\bTODO\b|FIXME|\bTBD\b|lorem|coming soon' Baxi --include='*.swift' | grep -v 'design-lint:allow')
for name in prints nowdates placeholders; do
  hits=${!name}
  if [ -n "$hits" ]; then echo "Hygiene ($name):"; echo "$hits"; fail=1; fi
done
[ $fail -eq 0 ] && echo "design-lint: clean"
exit $fail

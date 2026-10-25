#!/bin/bash
#
# design-lint.sh: keeps the screens on the design tokens in Baxi/Design/Theme.swift.
# (The same idea as the Pickd lint, started at zero so it is a hard rule, not a ratchet.)
#
# In Baxi/Screens and Baxi/App, each of these fails the check:
#   .font(.system(        use a BaxiFont rung
#   Color(red: / Color(hex: / Color(.system   use a BaxiColor name
#   spacing: <number>      use BaxiSpace (spacing: 0 is fine)
#   cornerRadius: <number> use BaxiRadius
#   .padding(<number>)     use BaxiSpace
#
# A line that ends in `// design-lint:allow <reason>` is exempt. The reason is required, so each
# exception is a decision on the record. Run: scripts/design-lint.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

patterns='\.font\(\.system\(|Color\((red:|hex:|\.system)|spacing: *[1-9]|cornerRadius: *[0-9]|\.padding\([0-9]'
hits=$(grep -rnE "$patterns" Baxi/Screens Baxi/App --include='*.swift' | grep -v 'design-lint:allow')
reasonless=$(grep -rn 'design-lint:allow *$' Baxi --include='*.swift')

fail=0
if [ -n "$hits" ]; then
  echo "Raw design values (use the tokens in Baxi/Design/Theme.swift):"
  echo "$hits"
  fail=1
fi
if [ -n "$reasonless" ]; then
  echo "design-lint:allow needs a reason:"
  echo "$reasonless"
  fail=1
fi
# Hygiene (the Pickd rules that fit Baxi), each at zero, hard rules:
#   no print( in the app's screens and app layer: use the os Logger
#   no ?? Date() in a screen: a missing time is not "now" (allow with a reason where it truly is)
#   no placeholder words anywhere in the app: TODO, FIXME, TBD, lorem, "coming soon"
prints=$(grep -rn 'print(' Baxi/Screens Baxi/App --include='*.swift' | grep -v '#if DEBUG' | grep -v 'design-lint:allow' \
  | grep -v 'Baxi/App/ScreenCheck.swift')
nowdates=$(grep -rn '?? Date()' Baxi/Screens --include='*.swift' | grep -v 'design-lint:allow')
placeholders=$(grep -rniE '\bTODO\b|FIXME|\bTBD\b|lorem|coming soon' Baxi --include='*.swift' | grep -v 'design-lint:allow')
for name in prints nowdates placeholders; do
  hits=${!name}
  if [ -n "$hits" ]; then echo "Hygiene ($name):"; echo "$hits"; fail=1; fi
done
[ $fail -eq 0 ] && echo "design-lint: clean"
exit $fail

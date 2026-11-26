#!/bin/zsh
# The DMG background art (Resources/DMG): sizes, the combined Retina TIFF, and the contrast of the icon-name bands.
source "${0:A:h}/lib.zsh"
ART="$ROOT/Resources/DMG"
TESTS="${0:A:h}"
inspect() { /usr/bin/python3 -I -B "$TESTS/dmg_inspect.py" "$@"; }

assert_ok "the SVG source exists" test -s "$ART/background.svg"
assert_eq "660" "$(sips -g pixelWidth "$ART/background.png" | awk '/pixelWidth/ {print $2}')" "background.png is 660 px wide"
assert_eq "400" "$(sips -g pixelHeight "$ART/background.png" | awk '/pixelHeight/ {print $2}')" "background.png is 400 px high"
assert_eq "1320" "$(sips -g pixelWidth "$ART/background@2x.png" | awk '/pixelWidth/ {print $2}')" "background@2x.png is 1320 px wide"
assert_eq "800" "$(sips -g pixelHeight "$ART/background@2x.png" | awk '/pixelHeight/ {print $2}')" "background@2x.png is 800 px high"
assert_eq $'660x400\n1320x800' "$(inspect tiff-pages "$ART/background.tiff")" "background.tiff holds the 1x and the 2x image"

# The art has no words, so there is nothing to translate.
assert_eq "0" "$(grep -c '<text' "$ART/background.svg")" "the SVG has no <text>"

# Finder draws the icon names in white or black. Each band must give at least 4.5:1 with both, in the SVG and in the exported pixels.
for id in band-app band-applications; do
  fill="$(sed -n "s/.*id=\"$id\".*fill=\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$ART/background.svg")"
  [[ -n "$fill" ]] || { _fail "the SVG has no #$id with a fill"; continue }
  read -r white black <<< "$(inspect contrast "$fill")"
  assert_ok "$id: contrast with white ($white) is at least 4.5" awk -v v="$white" 'BEGIN { exit !(v >= 4.5) }'
  assert_ok "$id: contrast with black ($black) is at least 4.5" awk -v v="$black" 'BEGIN { exit !(v >= 4.5) }'
done
# Band centres (the icon names sit at x 165 and 495 pt, y 288 pt): each exported band has its own SVG colour, at 1x and 2x.
for pair in "band-app 165" "band-applications 495"; do
  id="${pair% *}"; x="${pair#* }"
  want="$(sed -n "s/.*id=\"$id\".*fill=\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$ART/background.svg" | tr a-f A-F)"
  assert_eq "$want" "$(inspect png-pixel "$ART/background.png" $x 288)" "background.png at $id has the SVG colour"
  assert_eq "$want" "$(inspect png-pixel "$ART/background@2x.png" $(( x * 2 )) 576)" "background@2x.png at $id has the SVG colour"
done
# The background is opaque warm neutral away from the art.
assert_eq "F8F6F2" "$(inspect png-pixel "$ART/background.png" 20 20)" "the corner is the warm neutral #F8F6F2"
finish

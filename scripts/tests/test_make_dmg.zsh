#!/bin/zsh
# scripts/make-dmg.sh with the vendored dmgbuild: the vendored code and its notices, the settings, and a real image built from a
# stub app, mounted, with its Finder layout read back. Everything runs with the network blocked (sandbox-exec), because the build
# must need no network, pip or venv.
source "${0:A:h}/lib.zsh"
VENDOR="$ROOT/scripts/dmg/vendor"
TESTS="${0:A:h}"
inspect() { /usr/bin/python3 -I -B "$TESTS/dmg_inspect.py" "$@"; }
NO_NET=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')

tmp="$(mktemp -d)"; mnt="$tmp/mnt"; mkdir -p "$mnt"
cleanup() { hdiutil detach -quiet "$mnt" 2>/dev/null; rm -rf "${tmp:?}"; }
trap cleanup EXIT

# VERSIONS.txt lists every vendored package, with its licence file and archive hash.
versions="$(grep -v '^#' "$VENDOR/VERSIONS.txt")"
for pkg in dmgbuild ds_store mac_alias; do
  line="$(grep "^$pkg " <<< "$versions")"
  assert_ok "VERSIONS.txt lists $pkg" test -n "$line"
  assert_ok "$pkg has a licence file" test -s "$VENDOR/$pkg/LICENSE"
  assert_contains "$line" " MIT " "$pkg is MIT"
  assert_ok "$pkg: VERSIONS.txt gives a SHA-256" grep -Eq ' [0-9a-f]{64} ' <<< "$line"
  assert_contains "$(cat "$VENDOR/$pkg/__init__.py")" "__version__ = \"${${=line}[2]}\"" "$pkg: the vendored code is the pinned version"
done
assert_eq "3" "$(print -l $VENDOR/*(/) | wc -l | tr -d ' ')" "the vendor folder holds exactly the three listed packages"

# The settings load with python3 -I and the vendored path, with the network off.
settings_out="$("${NO_NET[@]}" /usr/bin/python3 -I -B -c '
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/dmg/vendor")
from dmgbuild.core import build_dmg  # noqa: the vendored copy must import
ns = {"defines": {"app": "/x/Lintel.app", "icon": "", "background": "/x/b.tiff"}}
exec(open(sys.argv[1] + "/scripts/dmg/settings.py").read(), ns)
print(ns["format"], ns["window_rect"], ns["icon_size"], ns["text_size"], ns["icon_locations"], ns["show_toolbar"], ns["show_sidebar"])
' "$ROOT" 2>&1)"
assert_eq "ULFO ((200, 120), (660, 432)) 128 13 {'Lintel.app': (165, 205), 'Applications': (495, 205)} False False" "$settings_out" "the settings load offline"

# A stub app with an icon, built into a signed image offline.
export DIST_DIR="$tmp/dist"; mkdir -p "$DIST_DIR"
app="$(make_signable_bundle "$DIST_DIR")"
sips -s format icns "$ROOT/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" --out "$app/Contents/Resources/AppIcon.icns" >/dev/null
export SKIP_BUILD=1
out="$("${NO_NET[@]}" zsh "$ROOT/scripts/make-dmg.sh" --skip-build 2>&1)"; rc=$?
assert_eq "0" "$rc" "make-dmg builds the designed image ($out)"
dmg="$DIST_DIR/Lintel.dmg"
assert_ok "the image exists" test -s "$dmg"
assert_ok "the versioned copy exists" test -s "$DIST_DIR/Lintel-0.0.0.dmg"
assert_ok "hdiutil verify passes" hdiutil verify -quiet "$dmg"
assert_ok "the image is signed" codesign --verify --strict "$dmg"
assert_contains "$(hdiutil imageinfo "$dmg" 2>/dev/null | grep "^Format:")" "ULFO" "the image keeps the ULFO format"

hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$mnt" "$dmg" >/dev/null 2>&1
assert_ok "the app is in the image" test -d "$mnt/Lintel.app/Contents"
assert_eq "/Applications" "$(readlink "$mnt/Applications")" "Applications links to /Applications"
assert_ok "the volume icon is the app icon" test -s "$mnt/.VolumeIcon.icns"
assert_ok "the background is in a hidden file" test -s "$mnt/.background.tiff"
assert_eq $'660x400\n1320x800' "$(inspect tiff-pages "$mnt/.background.tiff")" "the background in the image is the 1x and 2x TIFF"
layout="$(inspect dsstore "$mnt")"
assert_contains "$layout" "icon.Lintel.app=165,205" "the app icon position"
assert_contains "$layout" "icon.Applications=495,205" "the Applications position"
assert_contains "$layout" "iconSize=128" "icon size"
assert_contains "$layout" "textSize=13" "text size"
assert_contains "$layout" "hasBackgroundAlias=1" "the background alias is set"
assert_contains "$layout" "hasBackgroundBookmark=1" "the background bookmark is set"
assert_contains "$layout" "view=icnv" "icon view"
assert_contains "$layout" "WindowBounds={{200, 120}, {660, 432}}" "window bounds"
for key in ShowToolbar ShowSidebar ShowStatusBar ShowPathbar; do assert_contains "$layout" "$key=0" "$key is off"; done
hdiutil detach -quiet "$mnt"

# --plain keeps the old undecorated image (no layout, no background).
out="$(zsh "$ROOT/scripts/make-dmg.sh" --skip-build --plain 2>&1)"; rc=$?
assert_eq "0" "$rc" "make-dmg --plain builds ($out)"
hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$mnt" "$DIST_DIR/Lintel.dmg" >/dev/null 2>&1
assert_ok "--plain: the app is in the image" test -d "$mnt/Lintel.app/Contents"
assert_ok "--plain: no background" test ! -e "$mnt/.background.tiff"
hdiutil detach -quiet "$mnt"

assert_fails "an unknown option is refused" zsh "$ROOT/scripts/make-dmg.sh" --nope
finish

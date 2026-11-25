#!/bin/zsh
# Builds dist/Lintel.dmg: a drag-and-drop installer with Lintel.app and an Applications shortcut.
#
# The window is laid out by the vendored dmgbuild (scripts/dmg/vendor, settings in scripts/dmg/settings.py, art in Resources/DMG):
# it writes .DS_Store directly, so no Finder, AppleScript or GUI session is needed. It runs with /usr/bin/python3 -I (Command Line
# Tools); there is no pip, venv or network.
#
# Usage: scripts/make-dmg.sh [--skip-build] [--plain]
#   --skip-build  reuse an existing dist/Lintel.app (or set SKIP_BUILD=1)
#   --plain       the old undecorated image (app and Applications link, no layout); for local use only, the release never passes it
# The version comes from the built bundle (scripts/make-app.sh stamps APP_VERSION / APP_BUILD into it).
# Signing uses the same SIGN_IDENTITY / SIGN_KEYCHAIN as scripts/make-app.sh (ad-hoc by default); an identity with a
# Team ID gets the secure timestamp, any other --timestamp=none (scripts/select-entitlements.sh).
# DIST_DIR overrides the dist/ directory (the script tests use a temporary one).
# --skip-build is also how the release workflow's `sign` job builds the DMG from the signed, stapled app.
set -euo pipefail

APP_NAME="Lintel"
VOL_NAME="Lintel"
ROOT="${0:A:h:h}"
SKIP_BUILD="${SKIP_BUILD:-0}"
PLAIN=0
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --plain) PLAIN=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done
cd "$ROOT"
source "$ROOT/scripts/select-entitlements.sh"

[[ "$SKIP_BUILD" == 1 ]] || "$ROOT/scripts/make-app.sh"
APP="$DIST_DIR/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Missing $APP: run scripts/make-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/$APP_NAME.dmg"
DMG_VERSIONED="$DIST_DIR/$APP_NAME-$VERSION.dmg"

TMP="$(mktemp -d)"
MOUNT="$TMP/mount"
ATTACHED=0
detach_mount() {
  [[ "$ATTACHED" == 1 ]] || return 0
  hdiutil detach -quiet "$MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
  ATTACHED=0
}
trap 'detach_mount; rm -rf "$TMP"' EXIT

rm -f "$DMG" "$DMG_VERSIONED"
if [[ "$PLAIN" == 1 ]]; then
  STAGE="$TMP/stage"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -format ULFO "$DMG"
else
  PYTHON=/usr/bin/python3
  "$PYTHON" -I -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1 || {
    echo "$PYTHON (Command Line Tools, Python 3.9 or newer) is needed to lay out the DMG window: run xcode-select --install, or pass --plain for a plain local image." >&2
    exit 1
  }
  ICON="$APP/Contents/Resources/AppIcon.icns"
  [[ -f "$ICON" ]] || ICON=""
  "$PYTHON" -I -B "$ROOT/scripts/dmg/run.py" -s "$ROOT/scripts/dmg/settings.py" \
    -D "app=$APP" -D "icon=$ICON" -D "background=$ROOT/Resources/DMG/background.tiff" "$VOL_NAME" "$DMG" >/dev/null
  # dmgbuild ignores a failed copy of the app: make sure the image holds a complete copy before it is signed and shipped.
  mkdir -p "$MOUNT"
  ATTACHED=1
  hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$MOUNT" "$DMG"
  same_app=0; diff -rq "$APP" "$MOUNT/$APP_NAME.app" >/dev/null 2>&1 && same_app=1
  detach_mount
  [[ "$same_app" == 1 ]] || { echo "The DMG does not contain a complete copy of $APP_NAME.app" >&2; exit 1; }
fi

SIGN_TIMESTAMP="$(signing_timestamp_arg "$(probe_signing_identity "$SIGN_IDENTITY" "$SIGN_KEYCHAIN")")"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" "$SIGN_TIMESTAMP")
[[ -n "$SIGN_KEYCHAIN" ]] && SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
codesign "${SIGN_ARGS[@]}" "$DMG"
hdiutil verify -quiet "$DMG"
cp "$DMG" "$DMG_VERSIONED"

echo "Built: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '), version $VERSION)"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

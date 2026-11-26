#!/bin/zsh
# Draws the design gallery (spec .ai/specs/2026-11-23-swiftui-design-gallery.md) for the owner's approval: the FULL
# matrix of every state (light and dark, S, M and XL, English and Polish) as PNGs plus one contact sheet.
#
#   scripts/gallery-export.sh <output dir> [--scene <scene id>] [--no-build]
#
# Texts come from the language of the PROCESS (almost every string is String(localized:) without a bundle or locale),
# so the app bundle runs twice, once with -AppleLanguages "(en)" and once with "(pl)". Output:
#   <dir>/<scene>/<state>/<variant>.png   (variant: <light|dark>-<s|m|xl>-<en|pl>; also l for a state with includesLargeInSheet)
#   <dir>/index.html                      a contact sheet with no external resources
# Local runs are a working preview: another macOS build draws text differently from the CI runner, so only the
# sheet and goldens of the gallery-goldens.yml run are what the owner approves.
#
# Environment: CONFIGURATION is always debug (the gallery is DEBUG only). DIST_DIR as for scripts/make-app.sh.
set -euo pipefail

ROOT="${0:A:h:h}"
OUT=""
SCENE=""
BUILD=1
while (( $# > 0 )); do
  case "$1" in
    --scene) SCENE="${2:?--scene needs a scene id}"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 64 ;;
    *) [[ -z "$OUT" ]] || { echo "One output directory only" >&2; exit 64; }; OUT="$1"; shift ;;
  esac
done
[[ -n "$OUT" ]] || { echo "Usage: scripts/gallery-export.sh <output dir> [--scene <id>] [--no-build]" >&2; exit 64; }

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP="$DIST_DIR/Lintel-QA.app/Contents/MacOS/Lintel-QA"
if (( BUILD )); then
  CONFIGURATION=debug DIST_DIR="$DIST_DIR" "$ROOT/scripts/make-app.sh"
fi
[[ -x "$APP" ]] || { echo "Missing $APP (run without --no-build)" >&2; exit 66; }

mkdir -p "$OUT"
scene_args=()
[[ -z "$SCENE" ]] || scene_args=(--qa-gallery-scene "$SCENE")
for language in en pl; do
  "$APP" --qa --qa-gallery-export "$OUT" --qa-gallery-language "$language" "${scene_args[@]}" \
    -AppleLanguages "($language)" -AppleLocale "$language"
done

# The contact sheet: relative image paths only, nothing loaded from outside. Each state shows its summary (what the
# owner approves) and its caveat (what the picture does not show), written next to the pictures by the export.
esc() { print -rn -- "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
INDEX="$OUT/index.html"
{
  print -r -- '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
  print -r -- '<title>Lintel design gallery</title><style>'
  print -r -- 'body{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f5;color:#111}'
  print -r -- 'h2{margin:32px 0 4px}h3{margin:20px 0 6px;font:600 13px ui-monospace,monospace}'
  print -r -- '.row{display:flex;flex-wrap:wrap;gap:12px}figure{margin:0}figcaption{font:11px ui-monospace,monospace;color:#555}'
  print -r -- 'p.s{margin:0 0 6px}p.c{margin:0 0 6px;color:#a15c00;font-size:12px}'
  print -r -- 'img{max-width:420px;border:1px solid #ccc;background:#fff}'
  print -r -- '@media (prefers-color-scheme:dark){body{background:#1c1c1e;color:#eee}img{border-color:#444}figcaption{color:#aaa}}'
  print -r -- '</style></head><body><h1>Lintel design gallery</h1>'
  for scene_dir in "$OUT"/*(/N); do
    scene="${scene_dir:t}"
    print -r -- "<h2>${scene}</h2>"
    for state_dir in "$scene_dir"/*(/N); do
      state="${state_dir:t}"
      print -r -- "<h3>${state}</h3>"
      [[ -f "$state_dir/summary.txt" ]] && print -r -- "<p class=\"s\">$(esc "$(<"$state_dir/summary.txt")")</p>"
      [[ -s "$state_dir/caveat.txt" ]] && print -r -- "<p class=\"c\">$(esc "$(<"$state_dir/caveat.txt")")</p>"
      print -r -- '<div class="row">'
      for png in "$state_dir"/*.png(N); do
        variant="${png:t:r}"
        print -r -- "<figure><img loading=\"lazy\" src=\"${scene}/${state}/${png:t}\" alt=\"${scene} ${state} ${variant}\"><figcaption>${variant}</figcaption></figure>"
      done
      print -r -- '</div>'
    done
  done
  print -r -- '</body></html>'
} > "$INDEX"
echo "Wrote $INDEX"

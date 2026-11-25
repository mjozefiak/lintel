# dmgbuild settings for Lintel.dmg. Loaded by scripts/make-dmg.sh through the vendored dmgbuild:
#   python3 -I -m dmgbuild -s scripts/dmg/settings.py -D app=... -D icon=... -D background=... Lintel Lintel.dmg
# Values come from -D (the `defines` dictionary dmgbuild puts in scope), so the script tests can point them at a stub app.
# The window has no toolbar, sidebar, path bar or status bar; the background art has no words (Resources/DMG/background.svg).

app_path = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = app_path.rstrip("/").rsplit("/", 1)[-1]

format = "ULFO"
filesystem = "HFS+"

files = [app_path]
symlinks = {"Applications": "/Applications"}

# The volume icon is the app icon (.VolumeIcon.icns). Empty when a script test's stub app has none.
icon = defines.get("icon") or None  # noqa: F821
background = defines["background"]  # noqa: F821 (a combined 1x/2x TIFF)

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# 660 x 400 pt of content; Finder counts the 32 pt title bar in the bounds, hence the height.
window_rect = ((200, 120), (660, 432))
default_view = "icon-view"
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = "auto"

icon_locations = {
    app_name: (165, 205),
    "Applications": (495, 205),
}

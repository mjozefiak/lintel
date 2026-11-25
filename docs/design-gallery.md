# The design gallery

Spec: `.ai/specs/2026-11-23-swiftui-design-gallery.md`. The gallery is the source of truth for how a screen looks: the REAL
SwiftUI views of `LintelUI` and the plugins, drawn over fictional data, in every state, in light and dark, at S, M and XL,
in English and Polish. The owner approves **pictures from the gallery**, and CI compares them with golden PNGs. Everything
is DEBUG only: a release build contains no scene, no fictional data and no renderer.

Phase 1 (this one) is the renderer, the window, the export and one pilot screen: Settings → Meetings → "Notes are written
by" (`meetings.notes-provider`, 25 states). Banner states are the host's (`StatusBanner` lives in `LintelApp`) and wait for
the shell's own scenes (follow-up). HUDs and sheets are phase 4, the other screens phase 5, one screen per PR that touches it.

## Using it

| What | How |
|---|---|
| Look at the scenes, live or as pictures | `CONFIGURATION=debug scripts/make-app.sh`, then `dist/Lintel-QA.app/Contents/MacOS/Lintel-QA --qa --qa-gallery`. Add `--qa-snapshot <png> --qa-quit-after 8` for a picture of the window. No plugin starts. |
| The full matrix for the owner | `scripts/gallery-export.sh <dir> [--scene <id>]`: PNGs in `<dir>/<scene>/<state>/<variant>.png` and a contact sheet `<dir>/index.html`. It runs the app bundle twice (`-AppleLanguages "(en)"` and `"(pl)"`). A local export is a preview: another macOS build draws text differently from the CI runner. |
| One language by hand | `Lintel-QA --qa --qa-gallery-export <dir> --qa-gallery-language pl -AppleLanguages "(pl)"` |
| Compare / record goldens (the CI mechanism) | `--qa-gallery-compare <dir>` / `--qa-gallery-record <dir>` with `--qa-gallery-language <en\|pl>`; exit code 1 on a difference. The goldens are in `Tests/<Plugin>Tests/Gallery/Goldens/`. |
| `en` goldens in `swift test` | `LINTEL_SNAPSHOTS=compare\|compare-anyway\|record swift test --filter GallerySnapshotTests`. Unset: the suite does not run. `compare` needs `LINTEL_GALLERY_XCODE` (CI sets it) and is skipped locally. |

Language is an axis of the PROCESS, not of the view: almost every text is `String(localized:)` without a bundle or locale
and reads the process's languages. `swift test` runs in the test runner's bundle (English, no compiled catalog), so
`GalleryRenderer` refuses a variant in another language with `GalleryError.languageMismatch`; the Polish pictures come from
the app bundle with `-AppleLanguages "(pl)"` (ADR-style note: spec Q11).

## Adding a scene

1. In the plugin target: `extension MyPlugin: GalleryProviding { public static var galleryScenes: [GalleryScene] }`, in a file
   under `#if DEBUG`. The gallery finds plugins through `PluginRegistry.all`; nothing else knows them.
2. A `GalleryState` is an id (kebab-case, the golden's file name), a one-line English summary of what the owner approves, a
   `GalleryPresentation` (`.window(width:height:)` with `nil` height = fitting, `.sheet`, `.popover`, `.hud`) and a `make`
   closure that builds the REAL view over fakes. Never a copy of a view: if the view cannot be built from fictional data,
   fix the view (inject what it reads), as `ProviderNotesControl` does for the notes service.
3. A scene starts no process, network, microphone, Core Audio or Keychain, and touches no file outside a temporary
   folder. Fictional data holds no account name, host name or home path (`docs/qa.md`, QA identity).
4. Dates and relative times come from an injected fixed `now`. Tell the model of the view only the state, never "today".
5. Tests: ids unique and `[a-z0-9.-]+`, summaries not empty, a test that renders every state with
   `MeetingsSystem.installQuiet()`-style guards for the real system (see `GalleryScenesTests`).
6. Run the workflow **Gallery goldens** on the PR branch (Actions → Gallery goldens → Run workflow). It draws the full
   matrix on the CI runner and the CI subset from the same render. Link the artifact `gallery-record-<run id>` in the PR, get
   the owner's approval of the sheet, then commit the PNGs and `goldens.json` from `goldens/` of that artifact onto the
   branch (a commit that touches only `Tests/`).

## What the pictures do not show

- **Glass** (HUDs, panels): `cacheDisplay` does not draw the material. A snapshot shows the layout on an opaque backdrop;
  look at the glass live in `--qa-gallery`.
- **Popovers and sheets**: only their content is the real view; the outline and arrow are drawn by the renderer as an
  approximation (the caption says "content only; system chrome approximated").
- A dark HUD is not faithful (labels take the light colour in `cacheDisplay`); phase 4 records light only for HUDs.
- Animations are off; the renderer waits until two renders in a row are identical.

## The comparison

A picture differs when any RGBA channel differs by more than 3/255; a test fails when more than 0.1% of the pixels differ or
the size differs (`GalleryDiff`, spec Q6). Goldens carry a **renderer fingerprint** (macOS build, Xcode build, scale 2,
renderer version) in `goldens.json`. When the CI image changes, the step fails once with "renderer fingerprint changed" on
every open PR until the goldens are recorded again. A run that cannot know the Xcode build (no `LINTEL_GALLERY_XCODE`, a
local Mac) skips the comparison instead of reporting false failures.

On a failure CI uploads `gallery-diffs` (`actual.png`, `diff.png` with the changed pixels in red, `fingerprint.json`).
An agent never records goldens again to make a test pass: a PR that changes golden PNGs has `needs-qa`, a "Golden changes"
section and the owner's `qa-approved` with `Gallery head:` and `Gallery run:`.

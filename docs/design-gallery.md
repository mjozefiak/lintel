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
| Look at the scenes, live or as pictures | `CONFIGURATION=debug scripts/make-app.sh`, then `dist/Lintel-QA.app/Contents/MacOS/Lintel-QA --qa --qa-gallery`. Add `--qa-snapshot <png> --qa-quit-after 8` for a picture of the window. No plugin starts. `--qa-snapshot` uses `cacheDisplay`, which does not draw the sidebar selection (a black box) or the toolbar of an inactive window: for a picture of the window itself use `screencapture -l <window id>` while it is open. |
| The full matrix for the owner | `scripts/gallery-export.sh <dir> [--scene <id>]`: PNGs in `<dir>/<scene>/<state>/<variant>.png` and a contact sheet `<dir>/index.html`. It runs the app bundle twice (`-AppleLanguages "(en)"` and `"(pl)"`). A local export is a preview: another macOS build draws text differently from the CI runner. |
| One language by hand | `Lintel-QA --qa --qa-gallery-export <dir> --qa-gallery-language pl -AppleLanguages "(pl)"` |
| Compare / record goldens (the CI mechanism) | `--qa-gallery-compare <dir>` / `--qa-gallery-record <dir>` with `--qa-gallery-language <en\|pl>`; exit code 1 on a difference. The goldens are in `Tests/<Plugin>Tests/Gallery/Goldens/` and are **Git LFS objects**: run `git lfs pull` in a fresh checkout first (see below). |
| Which build compares | Both languages, in CI and when recording, come from the app bundle (`-AppleLanguages` and `-AppleLocale`): the same build the contact sheet shows the owner, with the accent colour and the compiled string catalog. `swift test` has neither, so it does not compare pictures; it only checks that every scene draws, is independent and fits the size budget. |

Language is an axis of the PROCESS, not of the view: almost every text is `String(localized:)` without a bundle or locale
and reads the process's languages. `swift test` runs in the test runner's bundle (English, no compiled catalog, another accent colour), so
`GalleryRenderer` refuses a variant in another language with `GalleryError.languageMismatch`; the Polish pictures come from
the app bundle with `-AppleLanguages "(pl)"` (ADR-style note: spec Q11).

## Adding a scene

0. Shared components of `LintelUI` (not a plugin screen) put their scenes in `LintelUIGallery.scenes` (`Sources/LintelUI/Gallery/`); `GalleryCatalog` lists that group first (scene `ui.ring`, the working ring). Their golden PNGs are recorded with the same workflow.
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
6. Run the workflow **Gallery goldens** on the PR branch (Actions → Gallery goldens → Run workflow; GitHub offers it only once the workflow file is on `main`, so the PR that adds it records its first goldens from a throwaway branch with a push trigger). It draws the full
   matrix on the CI runner, records the CI subset's goldens, and fails if a golden differs from the sheet's picture of the same variant. Link the artifact `gallery-record-<run id>` in the PR, get
   the owner's approval of the sheet, then commit the PNGs and `goldens.json` from `goldens/` of that artifact onto the
   branch (a commit that touches only `Tests/`).

## What the pictures do not show

- **Glass** (HUDs, panels): `cacheDisplay` does not draw the material. A snapshot shows the layout on an opaque backdrop;
  look at the glass live in `--qa-gallery`.
- **Popovers and sheets**: only their content is the real view; the outline and arrow are drawn by the renderer as an
  approximation (the caption says "content only; system chrome approximated").
- A dark HUD is not faithful (labels take the light colour in `cacheDisplay`); phase 4 records light only for HUDs.
- Animations are off; the renderer waits until two renders in a row are identical.

## Golden images in Git LFS

Since 2026-11-27 the golden PNGs are Git LFS objects (owner decision, spec Q5): `.gitattributes` covers every
`Tests/**/Gallery/Goldens/**/*.png` with `filter=lfs diff=lfs merge=lfs -text`, `goldens.json` stays a plain file. The
pictures were moved in one new commit; the blobs of `main`'s history are untouched.

- **Once per machine:** `brew install git-lfs`, then `git lfs install --skip-repo` (it sets only the `filter.lfs`
  filters in `~/.gitconfig`, no hook in any repository). Without it a checkout holds the LFS pointers instead of the
  pictures. `swift test` still passes (`GoldenBudgetTests` reads the `size` of a pointer, and
  `everyGoldenIsAnLFSObject` reads the stored pointer from the index), but nothing can draw or compare a picture.
- **A fresh checkout or worktree:** `git lfs pull` (or a normal checkout with the filters installed) materialises the
  PNGs of `Tests/MeetingsPluginTests/Gallery/Goldens/`.
- **Committing goldens from the `gallery-record-<run id>` artifact:** install Git LFS first. With the filters, the
  copied PNGs are committed as pointers, and the push must also upload the objects:
  `git push` then `git lfs push --all origin <branch>` (this repository has no LFS pre-push hook, because the filters
  were installed with `--skip-repo`). Committing the pictures without LFS records plain blobs again, and
  `everyGoldenIsAnLFSObject` fails: it reads the blob the index stores (not `.gitattributes`, which would say `lfs`
  either way) and requires a pointer. A pull request opened from a fork that records goldens pushes its objects to the
  fork's LFS store, where this repository's CI cannot find them; a fork recording goldens should open the pictures on a
  branch of this repository instead.
- **CI:** `ci.yml` and `gallery-goldens.yml` do not use `lfs: true` on the checkout. Each run restores
  `.git/lfs/objects` from an `actions/cache/restore` keyed by the object ids the commit needs, runs `git lfs pull`, then
  `actions/cache/save`s the result, so a run whose pictures did not change downloads nothing; only a branch that records
  new goldens downloads them once per key. The save is a separate step, so it also runs when a later step fails or the
  run is cancelled. `restore-keys` carries the old objects into every new key, so the cache only grows: prune old keys
  now and then (the repository's cache is near its 10 GB limit). The account's Git LFS plan includes 10 GiB of storage
  and 10 GiB of bandwidth a month (docs.github.com, checked 2026-11-27): about 31 MiB per run over the roughly 130 runs
  a day that check out the goldens (CI and Gallery goldens; the 45 Release runs do not) would exhaust the bandwidth in
  about two and a half days, which is why `lfs: true` is not used. A fork's clone and pull count against this
  repository's bandwidth.

### Pull requests opened before the LFS move

A branch that added golden PNGs before this change stores them as plain blobs. Merging `main` into it does not convert
them: git never re-runs the clean filter on a blob that did not change, so the merged commit would put plain PNGs back on
`main` (and `everyGoldenIsAnLFSObject` then fails). Convert the branch once, with Git LFS installed on the machine:

1. `git merge origin/main`
2. `git add --renormalize Tests/MeetingsPluginTests/Gallery/Goldens` (this runs the clean filter on every golden, which
   rewrites the new plain blobs as pointers), then `git commit`.
3. `git lfs ls-files` lists the pointers; `git push`, then `git lfs push --all origin <branch>` uploads the objects.

## The comparison

A picture differs when any RGBA channel differs by more than 3/255; a test fails when more than 0.1% of the pixels differ or
the size differs (`GalleryDiff`, spec Q6). Goldens carry a **renderer fingerprint** (macOS build, Xcode build, scale 2,
renderer version) in `goldens.json`. When the CI image changes, the step fails once with "renderer fingerprint changed" on
every open PR until the goldens are recorded again. A run that does not set `LINTEL_GALLERY_XCODE` (a local Mac) has no
Xcode build to match against the manifest's, so it reports "renderer fingerprint changed" and compares nothing; to look
at differences locally anyway, record into a temporary folder first and compare against that. With no `goldens.json` at all
there is one line, "no goldens.json … run gallery-goldens.yml". A picture that never settles (two renders in a row never
the same within `GalleryRenderer.maxAttempts`) is an error, never a golden.

On a failure CI uploads `gallery-diffs` (`actual.png`, `diff.png` with the changed pixels in red, `fingerprint.json`).
An agent never records goldens again to make a test pass: a PR that changes golden PNGs has `needs-qa`, a "Golden changes"
section and the owner's `qa-approved` with `Gallery head:` and `Gallery run:`.

source "${0:A:h}/lib.zsh"
classify="$ROOT/scripts/ci-docs-only.sh"

docs() { printf '%s\n' "$@" | "$classify" }
docs_raw() { printf '%s' "$1" | "$classify" }

# Documentation only: ci.yml skips the Thread Sanitizer run.
assert_ok "a doc under docs/" docs docs/qa.md
assert_ok "the landing page" docs docs/index.html
assert_ok "anything under .ai/" docs .ai/specs/2026-11-23-x.md .ai/agentic.config.json .ai/scripts/rename-to-lintel.sh
assert_ok "Markdown at the root" docs CHANGELOG.md AGENTS.md BACKWARD_COMPATIBILITY.md
assert_ok "Markdown in another folder" docs .github/pull_request_template.md packaging/homebrew/README.md
assert_ok "no trailing newline" docs_raw "docs/qa.md"
assert_ok "blank lines are ignored" docs_raw $'docs/qa.md\n\nREADME.md\n'

# Anything else runs everything.
assert_fails "an empty list" docs_raw ""
assert_fails "only blank lines" docs_raw $'\n\n'
assert_fails "a source file" docs Sources/LintelApp/AppCoordinator.swift
assert_fails "a source file next to docs" docs docs/qa.md Sources/LintelApp/AppCoordinator.swift
assert_fails "docs before a source file, in any order" docs Sources/LintelCore/Ranker.swift CHANGELOG.md
assert_fails "a Markdown fixture in Tests/" docs Tests/NotesPluginTests/Fixtures/revise/snapshots/a.expected.md
assert_fails "Markdown in Sources/" docs Sources/LintelApp/Notes.md
assert_fails "Markdown in Packages/" docs Packages/GRDBCipher/README.md
assert_fails "Markdown in Resources/" docs Resources/Notes.md
assert_fails "Markdown in scripts/" docs scripts/README.md
assert_fails "the package manifest" docs Package.swift
assert_fails "the resolved pins" docs Package.resolved
assert_fails "a workflow" docs .github/workflows/ci.yml
assert_fails "a script" docs scripts/test-with-watchdog.sh
assert_fails "a submodule pin" docs .gitmodules
assert_fails "a quoted path from git (unusual characters)" docs '"docs/\303\263.md"'
assert_fails "a file that only ends in md" docs docs.mdx-not-docs README.markdown

# With the diff ci.yml runs: a source file moved into docs/ still lists its old path, so it is not docs-only.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git_in() { git -C "$tmp" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@" >/dev/null }
git_in init -q
mkdir -p "$tmp/Sources" "$tmp/docs"
print -r -- 'let x = 1' > "$tmp/Sources/a.swift"
git_in add -A && git_in commit -q -m base
git_in mv Sources/a.swift docs/a.swift && git_in commit -q -m move
changed="$(git -C "$tmp" diff --name-only --no-renames HEAD^1 HEAD)"
assert_contains "$changed" "Sources/a.swift" "the diff lists the old path of a moved file"
assert_fails "a source file moved into docs/" docs_raw "$changed"
print -r -- '# Notes' > "$tmp/docs/notes.md"
git_in add -A && git_in commit -q -m notes
assert_ok "a doc added on its own" docs_raw "$(git -C "$tmp" diff --name-only --no-renames HEAD^1 HEAD)"

finish

#!/bin/bash
# Reads changed file paths (one per line, relative to the repository root) on stdin and exits 0 when every one is
# documentation, 1 otherwise. An empty list is not documentation (exit 1), so an unknown change runs everything.
#
#   git diff --name-only --no-renames HEAD^1 HEAD | scripts/ci-docs-only.sh
#
# --no-renames matters: a rename lists only its new path otherwise, so moving a source file into docs/ would look
# like a docs-only change.
#
# Documentation: anything under docs/ or .ai/, and a Markdown file (*.md) outside the folders whose files are
# built, tested or packaged (Sources/, Tests/, Packages/, Resources/, scripts/): a .md fixture in Tests/ is test input.
# ci.yml skips only the Thread Sanitizer run for such a change; the build, the tests and the lint still run, because
# tests read the docs (repository-wide scans, CHANGELOG.md, docs/index.html, BACKWARD_COMPATIBILITY.md).

set -u

is_docs() {
  case "$1" in
    docs/* | .ai/*) return 0 ;;
    Sources/* | Tests/* | Packages/* | Resources/* | scripts/*) return 1 ;;
    *.md) return 0 ;;
    *) return 1 ;;
  esac
}

count=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  is_docs "$path" || exit 1
  count=$((count + 1))
done
[ "$count" -gt 0 ]

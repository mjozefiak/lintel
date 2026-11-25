#!/usr/bin/env bash
# Scores offline dictation results with the benchmark's scorer (not part of this repository).
# Usage: LINTEL_DICTATION_SCORER=<path to score_dictation.py> score.sh [--fleurs=pl|en] <result.jsonl>... [--markdown]
set -euo pipefail
scorer="${LINTEL_DICTATION_SCORER:-}"
[[ -n "$scorer" && -f "$scorer" ]] || {
  printf 'score.sh: set LINTEL_DICTATION_SCORER to the path of score_dictation.py\n' >&2
  exit 2
}
# The scorer finds its corpus and FLEURS manifests relative to its own folder.
exec python3 -I "$scorer" "$@"

#!/usr/bin/env bash
# Cleans raw dictation transcripts offline with the app's cleanup path and a real GGUF model, and writes a
# JSONL the benchmark scorer reads (see README.md).
# Usage: run.sh --input <raw.jsonl> --out <result.jsonl> [--level light|standard|full] [--model <model.gguf>]
#        [--app <label>]
# --level standard (default) needs --model; light runs LightCleaner alone, no model; full arrives in phase 2.
# Exit codes: 0 ok, 2 usage/input error, 4 test failure, 5 build failure.
# Builds DictationPluginTests in release (`swift test -c release` fails to link other plugin tests) and runs
# ONLY DictationEvalTests through the Swift Testing helper, so no other suite shares the process.
set -euo pipefail

die() { printf 'run.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

input="" out="" model="" app="" level="standard"
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || die "missing value for $1"
  case "$1" in
    --input) input="$2" ;;
    --out) out="$2" ;;
    --model) model="$2" ;;
    --app) app="$2" ;;
    --level) level="$2" ;;
    *) die "unknown argument: $1" ;;
  esac
  shift 2
done
case "$level" in
  light) ;;
  standard) [[ -n "$model" ]] || die "--level standard needs --model" ;;
  full) die "--level full is not available before phase 2 of the cleanup levels spec" ;;
  *) die "--level must be light, standard or full" ;;
esac
[[ -n "$input" && -n "$out" ]] || die "required: --input --out"
[[ -f "$input" ]] || die "input not found: $input"
[[ -z "$model" || -f "$model" ]] || die "model not found: $model"

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo"
input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
[[ -z "$model" ]] || model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"
mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

swift build -c release -Xswiftc -enable-testing --product DictationPluginTests >&2 || exit 5

bundle="$(find "$repo/.build" -path '*Release/DictationPluginTests.xctest' -maxdepth 6 -print -quit)"
[[ -n "$bundle" ]] || die "DictationPluginTests.xctest not found under .build"
dev="${DEVELOPER_DIR:-$(xcode-select -p)}"
helper="$dev/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
platform="$dev/Platforms/MacOSX.platform/Developer"
binary="$bundle/Contents/MacOS/DictationPluginTests"
[[ -x "$helper" ]] || die "swiftpm-testing-helper not found: $helper"
[[ -f "$binary" ]] || die "test binary not found: $binary"

# Same trick as scripts/meeting-eval/run.sh: neutral process names, so a cleanup that kills processes by the
# test target's name does not end the run.
stage="$(mktemp -d "${TMPDIR:-/tmp}/dictation-eval-run.XXXXXX")"
cp "$helper" "$stage/eval-runner"
ln -s "$bundle" "$stage/eval.xctest"
trap 'rm -rf "$stage"' EXIT
log="$out.run.log"

rc=0
env LINTEL_DICTATION_EVAL_INPUT="$input" \
  LINTEL_DICTATION_EVAL_OUT="$out" \
  LINTEL_DICTATION_EVAL_LEVEL="$level" \
  ${model:+LINTEL_DICTATION_EVAL_MODEL="$model"} \
  ${app:+LINTEL_DICTATION_EVAL_APP="$app"} \
  DYLD_FRAMEWORK_PATH="$platform/Library/Frameworks" \
  DYLD_LIBRARY_PATH="$platform/usr/lib" \
  "$stage/eval-runner" --test-bundle-path "$stage/eval.xctest/Contents/MacOS/DictationPluginTests" \
  --testing-library swift-testing --filter 'EvalTests/cleansRawTranscripts' >"$log" 2>&1 || rc=$?

grep -E 'dictation-eval|✘|Test run with' "$log" | cut -c1-200 >&2 || true
if [[ $rc -ne 0 ]]; then
  die "DictationEvalTests failed (exit $rc); log kept: $log" 4
fi
grep -qE 'Test run with 1 test.* passed' "$log" || die "expected exactly one test to run; log kept: $log" 4
rm -f "$log"
printf '%s\n' "$out"

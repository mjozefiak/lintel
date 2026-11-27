source "${0:A:h}/lib.zsh"
# scripts/dictation-eval: the provider summary (numbers only) and run.sh's guards for --source provider, which must refuse
# before anything is built or sent.
summary="$ROOT/scripts/dictation-eval/provider_summary.py"
run="$ROOT/scripts/dictation-eval/run.sh"
fixture="$FIXTURES/dictation-eval/provider-standard.jsonl"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

json="$(python3 -I "$summary" "$fixture")"
field() { python3 -I -c 'import json,sys; print(json.load(sys.stdin)[0][sys.argv[1]])' "$1" <<<"$json"; }
assert_eq "standard" "$(field level)" "level read from the file"
assert_eq "4000" "$(field limit_ms)" "Standard's provider limit is 4 s (A10)"
assert_eq "4" "$(field items)" "items"
assert_eq "5" "$(field chunks)" "chunks"
assert_eq "1" "$(field multi_chunk_items)" "multi-chunk items"
assert_eq "1" "$(field audio_estimated)" "estimated lengths"
assert_eq "1500" "$(field release_p50_ms)" "p50 is nearest-rank (rank 2 of 4)"
assert_eq "4000" "$(field release_p90_ms)" "p90 is nearest-rank (rank 4 of 4)"
assert_eq "0" "$(field over_limit)" "no dictation over 4 s (4000 ms is at the limit)"
assert_eq "{'failed.rateLimited': 1}" "$(field provider_failures)" "provider failures apart"
assert_eq "{'tooLong': 1}" "$(field rejections)" "guard rejections apart"
assert_eq "pass" "$(field latency_gate)" "p90 at the limit passes the gate"
assert_eq "fail" "$(python3 -I "$summary" --limit-ms 2000 "$fixture" |
  python3 -I -c 'import json,sys; print(json.load(sys.stdin)[0]["latency_gate"])')" "a narrower limit fails"
md="$(python3 -I "$summary" --markdown "$fixture")"
assert_contains "$md" "| standard (v2) | claude-sonnet-x | 4 (1) | 5 | 1500 ms | 4000 ms | 4000 ms | 0 of 4 (> 4000 ms)" "markdown row"
assert_fails "never prints a transcript" grep -q invented <<<"$json$md"
printf '{"id":"x","level":"standard","release_ms":1}\n{"id":"y","level":"full","release_ms":1}\n' >"$tmp/mixed.jsonl"
assert_fails "two levels in one file are refused" python3 -I "$summary" "$tmp/mixed.jsonl"

# run.sh: --source provider refuses without the opt-in variables, for Light, and with --model; exit code 2, no build.
printf '{"id":"x","output":"invented"}\n' >"$tmp/raw.jsonl"
args=(--input "$tmp/raw.jsonl" --out "$tmp/out.jsonl" --source provider)
rc=0; env -u LINTEL_DICTATION_EVAL_PROVIDER -u LINTEL_DICTATION_EVAL_PROVIDER_MODEL "$run" "${args[@]}" 2>"$tmp/err" || rc=$?
assert_eq "2" "$rc" "provider without opt-in exits 2"
assert_contains "$(<"$tmp/err")" "LINTEL_DICTATION_EVAL_PROVIDER=claude-code" "names the opt-in variable"
rc=0; LINTEL_DICTATION_EVAL_PROVIDER=claude-code env -u LINTEL_DICTATION_EVAL_PROVIDER_MODEL "$run" "${args[@]}" 2>/dev/null || rc=$?
assert_eq "2" "$rc" "provider without a model exits 2"
rc=0; LINTEL_DICTATION_EVAL_PROVIDER=other LINTEL_DICTATION_EVAL_PROVIDER_MODEL=sonnet "$run" "${args[@]}" 2>/dev/null || rc=$?
assert_eq "2" "$rc" "an unknown provider exits 2"
rc=0; LINTEL_DICTATION_EVAL_PROVIDER=claude-code LINTEL_DICTATION_EVAL_PROVIDER_MODEL=sonnet "$run" "${args[@]}" --level light 2>/dev/null || rc=$?
assert_eq "2" "$rc" "Light uses no source"
rc=0; LINTEL_DICTATION_EVAL_PROVIDER=claude-code LINTEL_DICTATION_EVAL_PROVIDER_MODEL=sonnet "$run" "${args[@]}" --model "$tmp/raw.jsonl" 2>/dev/null || rc=$?
assert_eq "2" "$rc" "the provider takes no --model"
rc=0; "$run" --input "$tmp/raw.jsonl" --out "$tmp/out.jsonl" --source cloud 2>/dev/null || rc=$?
assert_eq "2" "$rc" "an unknown source exits 2"
rc=0; LINTEL_DICTATION_EVAL_PROVIDER=claude-code LINTEL_DICTATION_EVAL_PROVIDER_MODEL=sonnet "$run" "${args[@]}" --audio "$tmp/none" 2>/dev/null || rc=$?
assert_eq "2" "$rc" "a missing audio folder exits 2"
[[ ! -e "$tmp/out.jsonl" ]] && _pass || _fail "nothing written when refused"
finish

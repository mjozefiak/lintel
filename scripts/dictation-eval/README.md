# Dictation cleanup eval

Measures the dictation cleanup (`Segmenter` → `BuiltInFormatter` → `CleanupPrompt` → `FormatterGuard`) offline
and without a person, on raw transcripts recorded earlier. It runs the same code the app runs, with a real
GGUF model, so a change to the prompt or the guard can be compared before and after on the same input.

The corpus, the raw transcripts and the scorer are the benchmark's, kept outside this repository (they hold
the owner's voice recordings' text). Nothing here prints or stores transcript text in the repository.

## Run

```sh
scripts/dictation-eval/run.sh \
  --input  <raw transcripts>.jsonl \
  --out    <result>.jsonl \
  --model  <Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf> \
  [--level standard] [--app lintel-offline-v2]

scripts/dictation-eval/run.sh --input <raw transcripts>.jsonl --out <result>.jsonl --level light   # no model

LINTEL_DICTATION_SCORER=<path>/tools/score_dictation.py \
  scripts/dictation-eval/score.sh <result>.jsonl --markdown            # the 40-item corpus
  scripts/dictation-eval/score.sh --fleurs=pl <result>.jsonl --markdown  # FLEURS
```

`--level` is the cleanup level of the app (`light`, `standard` or `full`). `light` runs `LightCleaner` alone: no
model, no `--model`, app label `lintel-offline-light`, and the output adds `latency_us` (Light takes microseconds, so
`latency_ms` is 0). `standard` (default) is the model path above; `full` is the same path with the Full prompt
(`CleanupPrompt.fullSystem`) and the Full guard limits, app label `lintel-offline-full-v<CleanupPrompt.fullVersion>` (v3 since phase 2b).

Full also needs checks the scorer cannot make (no invented greeting or sign-off, no number or content word lost, a short
item stays one line, a spoken greeting alone on its line, paragraphs in mails and long items, the guard's rejections and
the output/input word ratio of accepted chunks). `check_full.py` (stdlib only, prints numbers and item ids, never text)
reads the raw transcripts and the results:

```sh
python3 -I scripts/dictation-eval/check_full.py --raw <raw transcripts>.jsonl --out <full result>.jsonl \
  --std <standard result>.jsonl --corpus <benchmark corpus.jsonl> --markdown
```

The raw transcripts carry no pauses, so "paragraphs at ≥ 2 pauses" is measured as a proxy (≥ 2 paragraphs in `mail` and
`long` items). Acceptance for Full is in the spec's Validation table.

Input and output lines: `{"id", "app", "output", "latency_ms", "wall_ms"}`. The output adds `chunks`,
`fell_back`, `rejections` (guard reasons) and `accepted` (kind and word ratio of each chunk the model's answer was used
for), which the scorer ignores. `app` defaults to
`lintel-offline-v<CleanupPrompt.version>`. `latency_ms` is the cleaning time of a warm model, without the
speech engine.

The test (`DictationEvalTests.cleansRawTranscripts`) is off by default and turned on by
`LINTEL_DICTATION_EVAL_INPUT`; `run.sh` sets that and `…_OUT`, `…_MODEL`, `…_APP`. To compare two versions of the
prompt, check out each commit and run the same input.

## What is not the same as in the app

The app cleans chunks while the user speaks, split by the speech segments and pauses; the raw transcripts here
have no pauses, so `Segmenter` cuts only at 60 words (at a sentence end when there is one). The context of a
chunk is the end of the previous raw chunk, as in the app. Vocabulary replacements are not applied.

## Term check (Phase 3)

`LINTEL_DICTATION_EVAL_VOCAB=<file>.json` (a JSON array of vocabulary words) is handed to the formatter's guard, so the
term check sees a vocabulary like the app's. `check_terms.py` (stdlib only, numbers and item ids, never text) reads the
raw transcripts, a result and the corpus and prints how many of the corpus `terms`/`code` words that the raw transcript
holds are still in the output, and the chunks sent back raw by reason:

```sh
python3 -I scripts/dictation-eval/check_terms.py --raw <raw transcripts>.jsonl --out <result>.jsonl --corpus <corpus>.jsonl
```

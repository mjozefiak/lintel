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
`latency_ms` is 0). `standard` (default) is the model path above. `full` is refused until its phase exists.

Input and output lines: `{"id", "app", "output", "latency_ms", "wall_ms"}`. The output adds `chunks`,
`fell_back` and `rejections` (guard reasons), which the scorer ignores. `app` defaults to
`lintel-offline-v<CleanupPrompt.version>`. `latency_ms` is the cleaning time of a warm model, without the
speech engine.

The test (`DictationEvalTests.cleansRawTranscripts`) is off by default and turned on by
`LINTEL_DICTATION_EVAL_INPUT`; `run.sh` sets that and `…_OUT`, `…_MODEL`, `…_APP`. To compare two versions of the
prompt, check out each commit and run the same input.

## What is not the same as in the app

The app cleans chunks while the user speaks, split by the speech segments and pauses; the raw transcripts here
have no pauses, so `Segmenter` cuts only at 60 words (at a sentence end when there is one). The context of a
chunk is the end of the previous raw chunk, as in the app. Vocabulary replacements are not applied.

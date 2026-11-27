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
(`CleanupPrompt.fullSystem`) and the Full guard limits, app label `lintel-offline-full-v1`.

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

## External provider (`--source provider`, spec Phase 4)

Measures the external AI provider as a cleanup source before the app has one. Each chunk goes through `ProviderRunner`
(the isolation check of the argv, the authorization before the start, the FIFO gate) to the real Claude Code CLI, with
the level's `CleanupPrompt` and the same `FormatterGuard`. **The text is sent to Anthropic**, so the tool is off unless
both variables are set. Give it public text (FLEURS); the owner's corpus is sent only with the owner's explicit consent
(spec A14: given for the Phase 4 measurement on 2026-11-26).

```sh
LINTEL_DICTATION_EVAL_PROVIDER=claude-code LINTEL_DICTATION_EVAL_PROVIDER_MODEL=sonnet \
  scripts/dictation-eval/run.sh --source provider --level standard|full \
  --input <raw fleurs-pl>.jsonl --out <result>.jsonl --audio <folder with <id>.wav>

python3 -I scripts/dictation-eval/provider_summary.py <result>.jsonl... --markdown   # latency, failures
scripts/dictation-eval/score.sh --fleurs=pl <result>.jsonl --markdown               # WER, as for the local source
python3 -I scripts/dictation-eval/check_full.py --raw <raw>.jsonl --out <full result>.jsonl --std <standard result>.jsonl
```

- **Replay of a session.** The raw transcripts carry no pauses, so the words are spread evenly over the recording
  (`--audio`: `<id>.wav`, `.flac` or `.m4a`; without it 150 words a minute). A chunk the segmenter closes while the user
  speaks (more than 60 words) is handed over when its last word was said, the rest at the release, as
  `DictationSession` does with `Segmenter.flush`. The requests run concurrently, as the session's tasks do, and queue in
  the provider's gate. The eval starts at the first hand-over, so it never waits through the speech before it.
- **Latency from the key release** (`release_ms`, also written as `latency_ms`): from the end of the last segment to
  the last chunk back. Every request starts a new CLI process, so the process start (the "cold start") is in every
  number. The speech engine's time for the last segment is not: it is the same for every source.
- **Provider failures apart.** `provider_failures` holds closed codes (`failed.rateLimited`, `timedOut`, ...) and the
  chunk stays raw; `rejections` are the guard's, as for the local source. One request may take 60 s in the eval: the
  tail is measured, not cut. `provider_summary.py` applies the release limits of the spec (Standard and Full 6 s; owner
  decision 2026-11-27, A10, A11) afterwards and prints p50, p90 (nearest rank), the dictations over the limit and the
  latency gate (p90 at or under the limit). A level is offered for the provider only when the gate passes **and** the
  level's quality targets hold.
- After 5 dictations in a row whose every chunk failed at the provider the run stops (no login, a limit).
- Output adds `release_ms`, `audio_ms`, `audio_estimated`, `chunk_ms` (each request from its hand-over, queue
  included), `provider_failures`, `source`, `level`, `prompt_version`, `provider_model` and `exact_model`. The app label
  is `lintel-provider-<model>-<level>-v<prompt version>`.
- The messages are flattened for a command-line provider with Meetings' `cli1` rule: the level's system prompt goes to
  argv (our text only), the examples and the transcript to stdin. Phase 5 decides the format of `ProviderFormatter`.
- Offline tests (`DictationProviderEvalTests`) run the same code over a fake `ProviderSystem` on a test clock; the CLI
  never starts in them.

## What is not the same as in the app

The app cleans chunks while the user speaks, split by the speech segments and pauses; the raw transcripts here
have no pauses, so `Segmenter` cuts only at 60 words (at a sentence end when there is one). The context of a
chunk is the end of the previous raw chunk, as in the app. Vocabulary replacements are not applied.

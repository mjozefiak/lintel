# scripts/actions-eval

The harness of the proactive-actions detection spike (`.ai/specs/research/2026-11-26-actions-detection-spike.md`).
It sends a draft detection prompt with a synthetic meeting to a model, checks the answer with a field guard and
scores it against hand-written gold actions. Nothing in the app uses it; it is not part of the build gate or CI.
Python 3 standard library only (the system `/usr/bin/python3`, 3.9 or newer); run with `-I`.

```sh
python3 -I -m unittest discover scripts/actions-eval        # the harness's own tests (offline)
```

## Corpus (`corpus/`)

Sixteen fictional meetings, 12 Polish and 4 English: `<id>.txt` is a header (`# id`, `# lang`, `# date`, `# self`,
`# title`) and one `[mm:ss] Speaker: text` line per utterance; `<id>.gold.json` holds the expected actions and the
traps. Utterance ids count from 1 in file order. No real meeting or owner data is in it.

```json
{"actions": [{"id": "a1", "type": ["jira"], "evidence": [4, 5],
              "fields": {"title": ["csv"], "assignee": ["Ola"], "due": ["2026-11-20"], "condition": false}}],
 "traps":   [{"id": "t1", "kind": "other_speaker", "evidence": [10]}]}
```

* `type`: the accepted action types; `evidence`: the utterances a correct quote may come from.
* `fields` (only the named ones are scored): `title` (keywords that must appear, case and diacritics ignored), `to`
  and `participants` (`required` and `optional` groups of aliases), `to_emails`, `assignee` (aliases or `null`),
  `date` / `due` (accepted ISO dates or `null`), `time` (`HH:MM` or `null`), `condition` (`true` when the action
  must carry an open condition), `must_mention` (numbers the title or description must keep).
* trap kinds: `other_speaker` (someone else promises it for themselves), `rejected`, `condition_failed`, `vague`,
  `withdrawn`, `hedge`.

`filler-pl.lines` and `filler-en.lines` are neutral lines (no promise, day, hour, number or name) for the length
test (`--pad N` puts N of them after every utterance and renumbers the gold).

## Running

```sh
# local model: start llama-server by hand on the GGUF the app uses (loopback only)
llama-server -m ".../Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf" --host 127.0.0.1 --port 8091 -c 8192 -ngl 99
python3 -I scripts/actions-eval/run.py --provider llama --url http://127.0.0.1:8091 --prompt v2 --runs 3 --out <dir>

# Claude Code CLI, with the ADR 0011 isolation flags (the argv of ProviderDescriptor.claudeCode)
python3 -I scripts/actions-eval/run.py --provider claude --model sonnet --prompt v2 --runs 3 --out <dir>

# length test (start llama-server with -c 32768 for it)
python3 -I scripts/actions-eval/run.py --provider llama --url http://127.0.0.1:8093 --prompt v2 --pad 8 --runs 1 --out <dir>

# score stored answers again after a guard or scorer change (no model call; pass the same --pad)
python3 -I scripts/actions-eval/run.py --rescore <dir>/<tag>

# Markdown tables comparing stored runs
python3 -I scripts/actions-eval/compare.py <dir>/<tag> <dir>/<tag> ...
```

`<dir>` should be outside the repository (answers are synthetic, but they are run output). Each answer is stored as
`<dir>/<tag>/run<N>/<meeting>.json` (text, seconds, tokens, model, prompt version); a run that stops can be started
again and skips the meetings already answered. The Claude child gets `-p --model <alias> --output-format json
--tools "" --no-session-persistence --disable-slash-commands --strict-mcp-config --setting-sources "" --safe-mode
--system-prompt <rules>`, the transcript on stdin, a new empty `0700` working directory and only `PATH` (system
folders), `HOME`, `USER`, `LANG`, `CLAUDE_CONFIG_DIR` and `TMPDIR` in its environment. It uses the subscription of the
account in `CLAUDE_CONFIG_DIR`.

## Parts

| File | What it does |
|---|---|
| `corpus.py` | reads the corpus; `padded()` for the length test |
| `prompt.py` | the versioned draft prompts `v1` and `v2` (`actions-detect-v1`, `-v2`) |
| `dates.py` | resolves Polish and English date phrases against the meeting date (all readings of an ambiguous phrase) |
| `textnorm.py` | folding, names in other grammatical cases, numbers said in words |
| `guard.py` | the field guard: quote in one utterance, speaker from that line, persons, e-mail addresses, date, time, numbers |
| `score.py` | matching to gold (type + quote in the evidence), trap classes, per-field checks |
| `run.py` | calls the model, stores answers, scores raw and guarded output, median of runs |
| `compare.py` | report tables over stored runs |

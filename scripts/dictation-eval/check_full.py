#!/usr/bin/env python3
"""Fidelity and layout checks for the Full cleanup level (spec 2026-11-25-dictation-cleanup-levels, phase 2).

The benchmark scorer (WER, terms, corrections, forbidden words; outside this repository) cannot see what Full is allowed
to change, so this script reads the raw transcripts and one or two result files of `run.sh` and counts the things the
spec and the owner's decision of 2026-11-26 forbid or require. It prints numbers only, never a transcript.

Usage: check_full.py --raw <raw.jsonl> --out <full-result.jsonl> [--std <standard-result.jsonl>]
                     [--corpus <corpus.jsonl>] [--markdown]

--raw     one JSON object per line, `id` and `output` (the raw transcript), as given to run.sh
--out     the result of `run.sh --level full` (`id`, `output`, and `chunks`, `fell_back`, `rejections`, `accepted`)
--std     the result of `run.sh --level standard` on the same input: the baseline of every count
--corpus  the benchmark's corpus.jsonl (`id`, `category`): adds the per-category checks (mail, long, chat, code)

Checks per result file:
  invented      items whose output opens with a greeting, or ends with a sign-off, that the raw text lacks (target 0)
  lost numbers  items that lost a number written in digits in the raw text; self-correction items listed apart,
                because the withdrawn number goes on purpose (target 0 on the others after the guard's fallback)
  new digits    items whose output holds digits the raw text does not (list markers excluded); informational, a spoken
                number written as digits counts, the guard's number check is the gate
  lost words    items that lost a content word (a stem of 5 letters; fillers and correction signals excluded), with the
                total of lost stems; self-correction items listed apart (compare with Standard: only a difference counts)
  one line      items under 25 words (outside the `list` category) whose output has a line break (target 0)
  greeting      mail items whose raw text starts with a greeting: how many have it alone on the first line
  paragraphs    mail and long items with at least two paragraphs; a proxy, because the raw transcripts carry no pauses
  fallback      chunks whose answer was rejected, by guard reason
  ratio         output/input words of the accepted chunks, per kind of chunk (none, minor, correction)
"""

import argparse
import json
import re
import statistics
import sys
import unicodedata

GREETINGS = [
    ["czesc"], ["witam"], ["witaj"], ["hej"], ["dzien", "dobry"], ["dobry", "wieczor"], ["szanowni"], ["szanowny"],
    ["szanowna"], ["hello"], ["hi"], ["hey"], ["dear"], ["good", "morning"], ["good", "afternoon"], ["good", "evening"],
]
SIGN_OFFS = [
    ["pozdrawiam"], ["z", "powazaniem"], ["z", "wyrazami", "szacunku"], ["dziekuje"], ["dzieki"], ["do", "uslyszenia"],
    ["best", "regards"], ["kind", "regards"], ["regards"], ["sincerely"], ["thanks"], ["thank", "you"], ["cheers"],
    ["yours"], ["talk", "soon"], ["best"],
]
FILLERS = {
    "yyy", "yy", "yyyy", "eee", "ee", "eeee", "eh", "em", "emm", "ymm", "hm", "hmm", "mhm", "mmm", "um", "umm", "uh",
    "uhm", "uhh", "ehm",
}
SIGNALS = {
    "sorry", "actually", "wait", "czekaj", "znaczy", "jednak", "wlasciwie", "przepraszam", "pardon", "pomylka",
    "scratch", "rather", "oops", "ups", "mean",
}
# Short function words the style edits may drop or change at a sentence split; not content.
FUNCTION = {
    "that", "this", "with", "have", "will", "from", "then", "than", "also", "just", "your", "they", "them", "were",
    "been", "what", "when", "which", "there", "their", "about", "would", "could", "should", "oraz", "przez", "który",
    "która", "które", "tylko", "jeszcze", "bardzo", "tego", "tych", "będzie", "jest", "jako", "wiec", "teraz",
}
SHORT_WORDS = 25
GREETING_LINE_WORDS = 5


def fold(text):
    text = text.lower().replace("ł", "l").replace("đ", "d").replace("ø", "o")
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def tokens(text):
    return re.findall(r"[a-z0-9]+", fold(text))


def contains(seq, phrase):
    n = len(phrase)
    return any(seq[i : i + n] == phrase for i in range(len(seq) - n + 1))


def lines_of(text):
    return [line for line in text.splitlines() if line.strip()]


def without_list_markers(text):
    return "\n".join(re.sub(r"^\s*(\d+[.)]|[-•*–])\s+", "", line) for line in text.splitlines())


def content_stems(text):
    return {t[:5] for t in tokens(text) if len(t) >= 4 and t.isalpha() and t not in FILLERS | SIGNALS | FUNCTION}


def load(path):
    rows = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                row = json.loads(line)
                rows[str(row["id"])] = row
    return rows


def percentile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def analyse(raw, out, categories):
    ids = [i for i in raw if i in out]
    result = {"items": len(ids), "chunks": 0, "fell_back": 0, "rejections": {}, "ratios": {}}
    invented, lost_nums, lost_nums_sc, new_nums = [], [], [], []
    lost_words, lost_words_sc, lost_stem_total = [], [], 0
    one_line, greeting_total, greeting_ok = [], 0, 0
    para_total, para_ok = 0, 0
    for item in ids:
        source, text = raw[item]["output"], out[item]["output"]
        category = categories.get(item, "")
        self_correction = category == "self-correction"
        raw_tokens, out_lines = tokens(source), lines_of(text)
        first = tokens(out_lines[0]) if out_lines else []
        if any(contains(first, g) and not contains(raw_tokens, g) for g in GREETINGS) or any(
            contains(tokens(line), s) and not contains(raw_tokens, s) for line in out_lines[-2:] for s in SIGN_OFFS
        ):
            invented.append(item)
        raw_digits = set(re.findall(r"\d+", source))
        out_digits = set(re.findall(r"\d+", without_list_markers(text)))
        if raw_digits - out_digits:
            (lost_nums_sc if self_correction else lost_nums).append(item)
        # Informational: a spoken number the model wrote as digits shows here too; the guard's number check is the gate.
        if out_digits - raw_digits:
            new_nums.append(item)
        missing = content_stems(source) - {t[:5] for t in tokens(text)}
        if missing:
            (lost_words_sc if self_correction else lost_words).append(item)
            lost_stem_total += 0 if self_correction else len(missing)
        if len(source.split()) < SHORT_WORDS and category != "list" and "\n" in text.strip():
            one_line.append(item)
        if category == "mail" and any(contains(raw_tokens[:3], g) for g in GREETINGS):
            greeting_total += 1
            blocks = re.split(r"\n\s*\n", text.strip())
            if len(blocks) >= 2 and len(tokens(blocks[0])) <= GREETING_LINE_WORDS and "\n" not in blocks[0].strip():
                greeting_ok += 1
        if category in ("mail", "long"):
            para_total += 1
            para_ok += len(re.split(r"\n\s*\n", text.strip())) >= 2
        result["chunks"] += out[item].get("chunks", 0)
        result["fell_back"] += out[item].get("fell_back", 0)
        for reason in out[item].get("rejections", []):
            result["rejections"][reason] = result["rejections"].get(reason, 0) + 1
        for stat in out[item].get("accepted", []):
            result["ratios"].setdefault(stat["kind"], []).append(stat["ratio"])
    result.update(
        invented=invented, lost_nums=lost_nums, lost_nums_sc=lost_nums_sc, new_nums=new_nums,
        lost_words=lost_words, lost_words_sc=lost_words_sc, lost_stems=lost_stem_total, one_line=one_line,
        greeting=(greeting_ok, greeting_total), paragraphs=(para_ok, para_total),
    )
    return result


def ratio_text(values):
    if not values:
        return "-"
    return f"n={len(values)} min {min(values):.2f} p10 {percentile(values, .1):.2f} med {statistics.median(values):.2f} p90 {percentile(values, .9):.2f} max {max(values):.2f}"


def report(label, r, markdown):
    rows = [
        ("items", r["items"]),
        ("invented greeting or sign-off (items)", len(r["invented"])),
        ("lost number (items, not self-correction)", len(r["lost_nums"])),
        ("lost number (self-correction items, expected)", len(r["lost_nums_sc"])),
        ("digits not in the raw text (items; spoken numbers written as digits count)", len(r["new_nums"])),
        ("lost content word (items, not self-correction)", len(r["lost_words"])),
        ("lost content stems (total, not self-correction)", r["lost_stems"]),
        ("lost content word (self-correction items)", len(r["lost_words_sc"])),
        ("short item with a line break (items)", len(r["one_line"])),
        ("mail greeting alone on the first line", "%d / %d" % r["greeting"]),
        ("mail+long with ≥ 2 paragraphs (proxy)", "%d / %d" % r["paragraphs"]),
        ("chunks, fell back", f"{r['chunks']}, {r['fell_back']}"),
        ("rejections by reason", ", ".join(f"{k} {v}" for k, v in sorted(r["rejections"].items())) or "-"),
    ]
    for kind in ("none", "minor", "correction"):
        rows.append((f"accepted ratio, {kind}", ratio_text(r["ratios"].get(kind, []))))
    print(f"\n### {label}\n" if markdown else f"\n== {label}")
    if markdown:
        print("| Check | Value |\n|---|---|")
        for name, value in rows:
            print(f"| {name} | {value} |")
    else:
        for name, value in rows:
            print(f"{name}: {value}")
    ids = {k: r[k] for k in ("invented", "lost_nums", "new_nums", "one_line") if r[k]}
    if ids:
        print("ids (no text): " + "; ".join(f"{k}: {', '.join(v)}" for k, v in ids.items()))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--std")
    parser.add_argument("--corpus")
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args(argv)
    raw = load(args.raw)
    categories = {}
    if args.corpus:
        categories = {i: row.get("category", "") for i, row in load(args.corpus).items()}
    report("Full", analyse(raw, load(args.out), categories), args.markdown)
    if args.std:
        report("Standard (baseline)", analyse(raw, load(args.std), categories), args.markdown)


if __name__ == "__main__":
    main(sys.argv[1:])

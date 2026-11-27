#!/usr/bin/env python3
"""Counts what the cleanup does to the corpus terms (spec 2026-11-25-dictation-cleanup-levels, Phase 3).

For every corpus item whose category is `terms` or `code`, each `must` word that the RAW transcript holds
(without case and diacritics) must still be in the cleaned output: a word the speech engine already got wrong
is not the cleanup's to answer for. Prints numbers and item ids, never text (stdlib only).

  python3 -I check_terms.py --raw <raw>.jsonl --out <result>.jsonl --corpus <corpus>.jsonl [--markdown]
"""
import argparse
import json
import unicodedata

CATEGORIES = {"terms", "code"}


def fold(text: str) -> str:
    text = text.lower().replace("ł", "l").replace("đ", "d").replace("ø", "o")
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return "".join(c if c.isalnum() else " " for c in text)


def contains(haystack: str, needle: str) -> bool:
    return f" {' '.join(fold(needle).split())} " in f" {' '.join(fold(haystack).split())} "


def rows(path):
    with open(path, encoding="utf-8") as handle:
        return {r["id"]: r for r in map(json.loads, filter(str.strip, handle))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    raw, out, corpus = rows(args.raw), rows(args.out), rows(args.corpus)

    required = kept = hit = total = 0
    lost_ids = []
    for ident, item in corpus.items():
        if item["category"] not in CATEGORIES or ident not in raw or ident not in out:
            continue
        lost_here = 0
        for word in item["must"]:
            total += 1
            if contains(out[ident]["output"], word):
                hit += 1
            if contains(raw[ident]["output"], word):
                required += 1
                if contains(out[ident]["output"], word):
                    kept += 1
                else:
                    lost_here += 1
        if lost_here:
            lost_ids.append(f"{ident}:{lost_here}")

    fell = sum(r["fell_back"] for r in out.values())
    chunks = sum(r["chunks"] for r in out.values())
    reasons = {}
    for r in out.values():
        for reason in r["rejections"]:
            reasons[reason] = reasons.get(reason, 0) + 1
    percent = f"{100 * kept / required:.1f} %" if required else "n/a"
    line = (
        f"terms kept of those in the raw transcript: {kept}/{required} ({percent}); "
        f"terms in the output: {hit}/{total}; lost: {', '.join(lost_ids) or 'none'}; "
        f"chunks sent back raw: {fell}/{chunks} ({100 * fell / chunks:.1f} %) {reasons}"
    )
    print(f"| {line} |" if args.markdown else line)


if __name__ == "__main__":
    main()

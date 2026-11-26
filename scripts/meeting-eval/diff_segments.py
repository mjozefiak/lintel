#!/usr/bin/env python3
"""Which segments changed their text between two meeting evaluation results (spec
2026-11-23-automatic-language-detection, step 2.5, gate item 3).

Usage: python3 -I scripts/meeting-eval/diff_segments.py <before.json> <after.json> [--repaired-only]

Segments are matched on their key `<track>@<startMs>-<endMs>` (the rows carry no stable id; the same audio cut by the
same voice activity detector gives the same keys). For every matched segment whose text differs the tool prints
its key, its duration in ms and its word counts before and after; it never prints text.

A changed segment is **long** when it is longer than 2 s **and** has more than 3 words before the change: the
segments the language repair must never rewrite (`SuspectSegmentPolicy.isShort` is its complement).

`--repaired-only` looks only at the rows the after run marked `repaired: true` (the changes of the repair itself,
not those of the live hint).

Exit codes: 0 no long segment changed, 1 at least one did, 2 usage or input error.
"""
import json
import sys

MAX_SECONDS_MS = 2000
MAX_WORDS = 3


def words(text):
    return len(text.split())


def key(row):
    return f"{row['track']}@{row['startMs']}-{row['endMs']}"


def rows_of(result):
    try:
        segments = result["asr"]["segments"]
    except (KeyError, TypeError):
        raise ValueError("asr.segments: missing")
    if not isinstance(segments, list):
        raise ValueError("asr.segments: not a list")
    out = {}
    for index, row in enumerate(segments):
        for field in ("track", "startMs", "endMs", "text"):
            if field not in row:
                raise ValueError(f"asr.segments[{index}].{field}: missing")
        out.setdefault(key(row), row)
    return out


def is_long(row):
    return row["endMs"] - row["startMs"] > MAX_SECONDS_MS and words(row["text"]) > MAX_WORDS


def diff(before, after, repaired_only=False):
    """Returns {changed: [...], long: [...], onlyBefore: n, onlyAfter: n, matched: n}; rows hold numbers only."""
    old = rows_of(before)
    new = rows_of(after)
    changed = []
    for k in sorted(set(old) & set(new), key=lambda k: (new[k]["startMs"], new[k]["track"], new[k]["endMs"])):
        a, b = old[k], new[k]
        if repaired_only and b.get("repaired") is not True:
            continue
        if a["text"] == b["text"]:
            continue
        changed.append({
            "key": k,
            "durationMs": a["endMs"] - a["startMs"],
            "wordsBefore": words(a["text"]),
            "wordsAfter": words(b["text"]),
            "long": is_long(a),
            "repaired": b.get("repaired"),
        })
    return {
        "matched": len(set(old) & set(new)),
        "onlyBefore": len(set(old) - set(new)),
        "onlyAfter": len(set(new) - set(old)),
        "changed": changed,
        "long": [c for c in changed if c["long"]],
    }


def main(argv):
    flags = [a for a in argv if a.startswith("--")]
    paths = [a for a in argv if not a.startswith("--")]
    if len(paths) != 2 or any(f != "--repaired-only" for f in flags):
        print(next(line for line in __doc__.splitlines() if line.startswith("Usage:")), file=sys.stderr)
        return 2
    try:
        results = []
        for path in paths:
            with open(path, encoding="utf-8") as handle:
                results.append(json.load(handle))
        report = diff(results[0], results[1], repaired_only="--repaired-only" in flags)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"diff_segments: {type(error).__name__}: {str(error)[:200]}", file=sys.stderr)
        return 2
    for c in report["changed"]:
        print(
            f"changed {c['key']} durationMs={c['durationMs']} words={c['wordsBefore']}->{c['wordsAfter']}"
            f" repaired={c['repaired']} long={'yes' if c['long'] else 'no'}")
    print(
        f"matched={report['matched']} changed={len(report['changed'])} long={len(report['long'])}"
        f" onlyBefore={report['onlyBefore']} onlyAfter={report['onlyAfter']}")
    return 1 if report["long"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

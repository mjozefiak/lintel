#!/usr/bin/env python3
"""Latency and failure summary of `run.sh --source provider` (spec 2026-11-25-dictation-cleanup-levels, phase 4).

Reads one or more result files of the provider eval and prints, per file, the latency from the key release (p50, p90,
max, and the dictations over the level's limit), the time of one chunk request, the provider's failures and the guard's
rejections, each counted apart. Numbers, ids and closed codes only, never a transcript. The quality of a level (WER,
Full's checks) comes from `score.sh` and `check_full.py` on the same file.

Usage: provider_summary.py <result.jsonl>... [--limit-ms N] [--markdown]

--limit-ms  the release limit to judge against; default by the file's level: Standard 4000, Full 6000 (spec A10, A11;
            Standard was 2000 before the Phase 4 measurement)

Percentiles are nearest-rank: p90 is the value at rank ceil(0.9 * n) of the sorted list, so it is always a measured
value. The latency gate of a level is p90 <= limit; whether a level is offered also needs its quality targets.
"""

import argparse
import collections
import json
import math
import sys

LIMITS_MS = {"standard": 4000, "full": 6000}


def percentile(values, share):
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(share * len(ordered)))
    return ordered[rank - 1]


def load(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                sys.exit(f"provider_summary.py: {path}:{number} is not JSON")
    return rows


def summarise(path, rows, limit_override):
    levels = {row.get("level") for row in rows}
    if len(levels) != 1 or None in levels:
        sys.exit(f"provider_summary.py: {path} must hold the provider eval of one level")
    level = levels.pop()
    limit = limit_override or LIMITS_MS.get(level)
    if limit is None:
        sys.exit(f"provider_summary.py: no limit for level {level}; pass --limit-ms")
    release = [row["release_ms"] for row in rows]
    chunk_ms = [ms for row in rows for ms in row.get("chunk_ms", [])]
    failures = collections.Counter(code for row in rows for code in row.get("provider_failures", []))
    rejections = collections.Counter(reason for row in rows for reason in row.get("rejections", []))
    chunks = sum(row.get("chunks", 0) for row in rows)
    over = sum(1 for ms in release if ms > limit)
    p90 = percentile(release, 0.9)
    return {
        "file": path,
        "level": level,
        "prompt_version": sorted({row.get("prompt_version") for row in rows if row.get("prompt_version") is not None}),
        "provider_model": sorted({row.get("provider_model") for row in rows if row.get("provider_model")}),
        "exact_model": sorted({row.get("exact_model") for row in rows if row.get("exact_model")}),
        "items": len(rows),
        "chunks": chunks,
        "multi_chunk_items": sum(1 for row in rows if row.get("chunks", 0) > 1),
        "audio_estimated": sum(1 for row in rows if row.get("audio_estimated")),
        "limit_ms": limit,
        "release_p50_ms": percentile(release, 0.5),
        "release_p90_ms": p90,
        "release_max_ms": max(release) if release else None,
        "over_limit": over,
        "chunk_p50_ms": percentile(chunk_ms, 0.5),
        "chunk_p90_ms": percentile(chunk_ms, 0.9),
        "provider_failures": dict(sorted(failures.items())),
        "items_with_provider_failure": sum(1 for row in rows if row.get("provider_failures")),
        "rejections": dict(sorted(rejections.items())),
        "accepted_changed_chunks": sum(len(row.get("accepted", [])) for row in rows),
        "latency_gate": "pass" if p90 is not None and p90 <= limit else "fail",
    }


def counts(mapping):
    return ", ".join(f"{key} {value}" for key, value in mapping.items()) or "0"


def markdown(summaries):
    lines = [
        "| File | Level (prompt) | Model | Items (multi-chunk) | Chunks | p50 from release | p90 from release | max |"
        " Over the limit | Chunk request p50 / p90 | Provider failures (chunks) | Guard rejections | Latency gate |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for s in summaries:
        model = ", ".join(s["exact_model"] or s["provider_model"]) or "-"
        version = ",".join(f"v{v}" for v in s["prompt_version"]) or "-"
        lines.append(
            f"| {s['file']} | {s['level']} ({version}) | {model} | {s['items']} ({s['multi_chunk_items']}) |"
            f" {s['chunks']} | {s['release_p50_ms']} ms | {s['release_p90_ms']} ms | {s['release_max_ms']} ms |"
            f" {s['over_limit']} of {s['items']} (> {s['limit_ms']} ms) | {s['chunk_p50_ms']} / {s['chunk_p90_ms']} ms |"
            f" {counts(s['provider_failures'])} | {counts(s['rejections'])} | {s['latency_gate']} |"
        )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("results", nargs="+")
    parser.add_argument("--limit-ms", type=int)
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    summaries = []
    for path in args.results:
        rows = load(path)
        if not rows:
            sys.exit(f"provider_summary.py: {path} is empty")
        summaries.append(summarise(path, rows, args.limit_ms))
    if args.markdown:
        print(markdown(summaries))
    else:
        print(json.dumps(summaries, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

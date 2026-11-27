"""Markdown tables that compare stored runs (no model call): `python3 -I compare.py <out>/<tag> [<out>/<tag> ...]`.

A tag ending in `-padN` is scored on the padded meetings. Prints the median headline metrics per tag, which gold actions each tag found (runs found / runs), the field errors
after the guard, and the trap hits. Synthetic corpus only, so ids and field names are printed, never more.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import corpus  # noqa: E402
import run  # noqa: E402


def pad_of(tag):
    """A tag made with `--pad N` ends in `-padN` (run.py's default tag); its gold must be renumbered the same way."""
    match = re.search(r"-pad(\d+)$", tag)
    return int(match.group(1)) if match else 0


def load(tag_dir, meetings):
    meetings = [corpus.padded(m, pad_of(os.path.basename(tag_dir.rstrip("/")))) for m in meetings]
    run_dirs = sorted(d for d in os.listdir(tag_dir) if d.startswith("run"))
    return [run.score_run(meetings, run.load_answers(os.path.join(tag_dir, d), meetings)) for d in run_dirs]


def main(paths):
    meetings = corpus.load_all()
    tags = [(os.path.basename(p.rstrip("/")), load(p, meetings)) for p in paths]
    rows = [
        ("Precision (after guard)", "precision", "%.2f"), ("Recall", "recall", "%.2f"), ("F1", "f1", "%.2f"),
        ("Precision (raw)", "precision_raw", "%.2f"), ("Recall (raw)", "recall_raw", "%.2f"),
        ("Field accuracy (after guard)", "field_accuracy", "%.3f"), ("Field accuracy (raw)", "field_accuracy_raw", "%.3f"),
        ("Actions with every field right (after guard)", "all_fields_rate", "%.2f"),
        ("Actions with every field right (raw)", "all_fields_rate_raw", "%.2f"),
        ("Trap hits (raw)", "trap_hits_raw", "%d"), ("Quotes not in the transcript (raw)", "bad_quotes_raw", "%d"),
        ("Invented values removed by the guard", "invented_values_raw", "%d"),
        ("Wrong dates corrected by the guard", "wrong_dates_fixed", "%d"),
        ("Seconds, whole corpus", "seconds_total", "%.0f"), ("Seconds per meeting, median", "seconds_median", "%.1f"),
        ("Seconds per meeting, max", "seconds_max", "%.1f"),
    ]
    summaries = [(t, run.summarize(r)) for t, r in tags]
    print("| Metric (median of runs) | " + " | ".join(t for t, _ in summaries) + " |")
    print("|---|" + "---|" * len(summaries))
    for label, key, fmt in rows:
        print("| %s | %s |" % (label, " | ".join(fmt % s["median"][key] for _, s in summaries)))
    print("| Runs | %s |" % " | ".join(str(len(r)) for _, r in tags))
    print()

    print("| Gold action | " + " | ".join(t for t, _ in tags) + " |")
    print("|---|" + "---|" * len(tags))
    for m_index, m in enumerate(meetings):
        for g in m.gold["actions"]:
            cells = []
            for _, runs in tags:
                found = sum(1 for r in runs if g["id"] not in r["per_meeting_guarded"][m_index]["missed"])
                errors = {}
                for r in runs:
                    for e in r["per_meeting_guarded"][m_index]["field_errors"]:
                        aid, field = e.split(":")
                        if aid == g["id"]:
                            errors[field] = errors.get(field, 0) + 1
                cell = "%d/%d" % (found, len(runs))
                if errors:
                    cell += " (" + ", ".join("%s %d" % (k, v) for k, v in sorted(errors.items())) + ")"
                cells.append(cell)
            flags = []
            if g["fields"].get("condition"):
                flags.append("conditional")
            print("| %s %s %s%s | %s |" % (m.id, g["id"], "/".join(g["type"]),
                                         (" [" + ", ".join(flags) + "]") if flags else "", " | ".join(cells)))
    print()

    print("| Unmatched proposals (raw, all runs) | " + " | ".join(t for t, _ in tags) + " |")
    print("|---|" + "---|" * len(tags))
    kinds = sorted(set(k for _, runs in tags for r in runs for k in r["raw"]["classes"] if k != "match"))
    for kind in kinds:
        print("| %s | %s |" % (kind, " | ".join(str(sum(r["raw"]["classes"].get(kind, 0) for r in runs))
                                            for _, runs in tags)))
    print()
    print("| Trap kind (raw hits, all runs / traps x runs) | " + " | ".join(t for t, _ in tags) + " |")
    print("|---|" + "---|" * len(tags))
    trap_kinds = tags[0][1][0]["raw"]["trap_kinds"]
    for kind in sorted(trap_kinds):
        cells = []
        for _, runs in tags:
            hits = sum(r["raw"]["traps_hit"].get(kind, 0) for r in runs)
            cells.append("%d/%d" % (hits, trap_kinds[kind] * len(runs)))
        print("| %s | %s |" % (kind, " | ".join(cells)))


if __name__ == "__main__":
    main(sys.argv[1:])

#!/usr/bin/env python3
"""A meeting note in Markdown -> `notes.json` (schema 1) for `score_notes.py`.

Standard library only. Run as: python3 -I notes_md_to_points.py --notes <notes.md> --meeting <id> [--out notes.json]
Prints numbers only (points per kind), never note text.

Mapping (spec 2026-11-25-meeting-notes-structure, F0 step 4):
  intro and the summary section (old layout)      -> summary (one point per paragraph)
  bullets of a topic, of the old "Topics discussed" container and of any heading this tool does not know
  (Wispr Flow, Granola)                           -> key_point (a paragraph under such a heading too)
  decisions ("Decisions", "Podjęte decyzje", ...) -> decision
  tasks ("Next steps", "Następne kroki", "Zadania", "Action items") -> task; `— osoba: X, termin: Y` (or owner/due)
                                                     becomes owner and due; "Do przypisania" is no owner
  open questions                                  -> question
  participants and the title                      -> left out
Nested bullets are points of their own. The `quote` of every point is null.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import notes_md  # noqa: E402

SCHEMA = 1


def points_from_markdown(markdown):
    document = notes_md.parse(markdown)
    points = []
    for section in document.sections:
        kind = section.kind
        if kind == "participants":
            continue
        for item in section.items:
            text = item.text
            if not text:
                continue
            if kind in ("intro", "summary"):
                if not item.bullet:
                    points.append({"kind": "summary", "text": text, "quote": None})
                else:
                    points.append({"kind": "key_point", "text": text, "quote": None})
            elif kind == "decisions":
                points.append({"kind": "decision", "text": text, "quote": None})
            elif kind == "tasks":
                body, owner, due = notes_md.split_task(text)
                points.append({"kind": "task", "text": body, "owner": owner, "due": due, "quote": None})
            elif kind == "questions":
                points.append({"kind": "question", "text": text, "quote": None})
            else:  # topic, topics, other
                points.append({"kind": "key_point", "text": text, "quote": None})
    return points


def build(markdown, meeting):
    return {"schema": SCHEMA, "meeting": meeting, "points": points_from_markdown(markdown)}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="notes_md_to_points.py")
    ap.add_argument("--notes", required=True, help="the notes as Markdown")
    ap.add_argument("--meeting", required=True, help="the meeting id (the gold entry's id)")
    ap.add_argument("--out", help="notes.json to write (default: <notes>.json beside the input)")
    args = ap.parse_args(argv)
    try:
        with open(args.notes, encoding="utf-8") as handle:
            markdown = handle.read()
    except OSError as error:
        print("notes_md_to_points: cannot read the notes: %s" % error.strerror, file=sys.stderr)
        return 2
    result = build(markdown, args.meeting)
    out = args.out or os.path.splitext(args.notes)[0] + ".points.json"
    # The file holds note text: owner-only, like the notes file it comes from.
    descriptor = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=1)
    counts = {}
    for point in result["points"]:
        counts[point["kind"]] = counts.get(point["kind"], 0) + 1
    print("meeting=%s points=%d %s" % (args.meeting, len(result["points"]), " ".join("%s=%d" % kv for kv in sorted(counts.items()))))
    print("wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

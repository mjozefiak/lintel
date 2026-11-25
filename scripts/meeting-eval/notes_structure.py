#!/usr/bin/env python3
"""Does a meeting note follow the layout of spec 2026-11-25-meeting-notes-structure? Counted by code.

Standard library only. Run as:
  python3 -I notes_structure.py --notes <notes.md> --duration-min <minutes> --lang pl|en
      [--expect-decisions] [--expect-next-steps] [--json]
Prints rule names, pass/fail and numbers only, never note text. Exit code: 0 every rule holds, 1 a rule fails,
2 usage or input error.

`--expect-decisions` / `--expect-next-steps` say that the meeting had such items (the counts come from the
trace or the draft, which this tool does not see): the section must then be present.

Rules (spec "Plan pomiaru", metric 3):
  no_headingless_points  a meeting that is not short has no list of points outside every heading (this also fails the
                         built-in track's fallback list without a heading; decide before F4 whether to exempt it)
  topics_within_max      number of named topic headings ("Other" is extra) <= min(10, max(2, minutes // 6)); a short meeting has none
  points_per_topic       2..6 points under each topic heading ("Other" 1..6), unless the meeting is short
  decisions_section      a decisions section exists when --expect-decisions
  next_steps_section     a next-steps section exists when --expect-next-steps
  no_times               no [mm:ss], ~mm:ss or (mm:ss) anywhere
  no_author_marks        no mark that an AI wrote it or who wrote it
  labels_in_language     the section labels Lintel writes are those of --lang
  no_unassigned_label    no "Do przypisania" / "Unassigned" owner
  intro_short            the intro (text before the first heading, or the old summary) is at most 3 sentences
                         and 70 words
A short meeting is one under 10 minutes or with fewer than 6 points to show.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import notes_md  # noqa: E402

MAX_TOPICS_CAP = 10
MIN_TOPICS = 2
MINUTES_PER_TOPIC = 6
POINTS_PER_TOPIC = (2, 6)
INTRO_MAX_SENTENCES = 3
INTRO_MAX_WORDS = 70
SHORT_MINUTES = 10
SHORT_POINTS = 6

TIME_PATTERNS = (
    re.compile(r"\[~?\d{1,2}(?::\d{2}){1,2}\]"),
    re.compile(r"~\s?\d{1,2}(?::\d{2}){1,2}(?!\d)"),
    re.compile(r"\(\d{1,2}(?::\d{2}){1,2}\)"),
)
AUTHOR_MARK_PATTERNS = tuple(
    re.compile(p, re.IGNORECASE)
    for p in (
        r"generated (by|with|using)", r"wygenerowan\w* (przez|za pomoc\w*)", r"written (by|with) (ai|claude|chatgpt|gpt)",
        r"napisan\w* przez (ai|sztuczn)", r"\bai[- ]generated\b", r"\bai notes\b", r"\bnotatk\w* ai\b", "🤖", "✨ ai",
        r"\bpowered by\b", r"\bsent to:? claude\b", r"\bwysłan\w* do claude\b", r"\blintel ai\b",
    )
)
UNASSIGNED = ("do przypisania", "unassigned")
SENTENCE_END = re.compile(r"(?<=[.!?…])\s+(?=[\"'(\[]?[A-ZĄĆĘŁŃÓŚŹŻ0-9])")


def max_topics(minutes):
    """The upper bound of topics for a meeting of `minutes` (spec: min(10, max(2, minutes / 6)))."""
    return min(MAX_TOPICS_CAP, max(MIN_TOPICS, int(minutes // MINUTES_PER_TOPIC)))


def sentences(text):
    return [s for s in SENTENCE_END.split(text.strip()) if s.strip()]


def _points_of(section):
    return [i for i in section.items if (i.bullet and i.depth == 0) or not i.bullet]


def analyse(markdown, minutes, lang, expect_decisions=False, expect_next_steps=False):
    doc = notes_md.parse(markdown)
    topics = [s for s in doc.sections if s.kind in ("topic", "other")]
    flat_points = 0
    for s in doc.sections:
        if s.kind in ("topic", "other", "topics"):
            flat_points += len(_points_of(s))
    # Points that stand under no heading at all (a flat list after the intro).
    headingless = sum(1 for s in doc.of_kind("intro") for i in s.items if i.bullet and i.depth == 0)
    flat_points += headingless
    intro_items = [i for s in doc.of_kind("intro", "summary") for i in s.items if not i.bullet]
    short = minutes < SHORT_MINUTES or flat_points < SHORT_POINTS
    rules = []

    def rule(name, ok, value, limit=None):
        rules.append({"rule": name, "pass": bool(ok), "value": value, "limit": limit})

    limit = max_topics(minutes)
    named = [s for s in topics if s.kind == "topic"]
    if short:
        rule("topics_within_max", len(topics) == 0, len(topics), 0)
        rule("no_headingless_points", True, headingless, None)
    else:
        # "Other" comes on top of the limit (spec: at most `maxTopics` topics, plus the closing "Other").
        rule("topics_within_max", len(named) <= limit, len(named), limit)
        rule("no_headingless_points", headingless == 0, headingless, 0)
    if short:
        rule("points_per_topic", True, 0, None)
    else:
        bad = 0
        for s in topics:
            count = len(_points_of(s))
            low = 1 if s.kind == "other" else POINTS_PER_TOPIC[0]
            if not (low <= count <= POINTS_PER_TOPIC[1]):
                bad += 1
        rule("points_per_topic", bad == 0, bad, "topics outside %d..%d" % POINTS_PER_TOPIC)
    has_decisions = any(s.items for s in doc.of_kind("decisions"))
    has_steps = any(s.items for s in doc.of_kind("tasks"))
    rule("decisions_section", has_decisions or not expect_decisions, int(has_decisions), int(expect_decisions))
    rule("next_steps_section", has_steps or not expect_next_steps, int(has_steps), int(expect_next_steps))

    times = sum(len(p.findall(markdown)) for p in TIME_PATTERNS)
    rule("no_times", times == 0, times, 0)
    marks = sum(len(p.findall(markdown)) for p in AUTHOR_MARK_PATTERNS)
    rule("no_author_marks", marks == 0, marks, 0)

    wrong = "en" if lang == "pl" else "pl"
    foreign = 0
    for s in doc.sections:
        if s.heading and s.heading in notes_md.LABELS[wrong] and s.heading not in notes_md.LABELS[lang]:
            foreign += 1
    rule("labels_in_language", foreign == 0, foreign, 0)

    unassigned = 0
    for s in doc.of_kind("tasks"):
        for item in s.items:
            _, owner, _ = notes_md.split_task(item.text)
            if notes_md.normalize(item.text).find("do przypisania") >= 0 or notes_md.normalize(item.text).endswith("unassigned"):
                unassigned += 1
    rule("no_unassigned_label", unassigned == 0, unassigned, 0)

    words = sum(len(i.text.split()) for i in intro_items)
    count = sum(len(sentences(i.text)) for i in intro_items)
    rule("intro_short", count <= INTRO_MAX_SENTENCES and words <= INTRO_MAX_WORDS, count, "%d sentences, %d words (%d)" % (INTRO_MAX_SENTENCES, INTRO_MAX_WORDS, words))

    layout = "old" if any(s.kind in ("summary", "topics") for s in doc.sections) else "topics"
    return {
        "layout": layout,
        "short_meeting": short,
        "topics": len(topics),
        "points": flat_points,
        "max_topics": limit,
        "rules": rules,
        "conforms": all(r["pass"] for r in rules),
    }


def render(result):
    lines = [
        "layout=%s short=%s topics=%d points=%d maxTopics=%d"
        % (result["layout"], str(result["short_meeting"]).lower(), result["topics"], result["points"], result["max_topics"])
    ]
    for r in result["rules"]:
        lines.append("%s %s value=%s limit=%s" % ("PASS" if r["pass"] else "FAIL", r["rule"], r["value"], r["limit"]))
    lines.append("conforms=%s" % str(result["conforms"]).lower())
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="notes_structure.py")
    ap.add_argument("--notes", required=True)
    ap.add_argument("--duration-min", type=float, required=True)
    ap.add_argument("--lang", choices=("pl", "en"), required=True)
    ap.add_argument("--expect-decisions", action="store_true")
    ap.add_argument("--expect-next-steps", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if args.duration_min <= 0:
        print("notes_structure: --duration-min must be positive", file=sys.stderr)
        return 2
    try:
        with open(args.notes, encoding="utf-8") as handle:
            markdown = handle.read()
    except OSError as error:
        print("notes_structure: cannot read the notes: %s" % error.strerror, file=sys.stderr)
        return 2
    result = analyse(markdown, args.duration_min, args.lang, args.expect_decisions, args.expect_next_steps)
    print(json.dumps(result, indent=1) if args.json else render(result))
    return 0 if result["conforms"] else 1


if __name__ == "__main__":
    sys.exit(main())

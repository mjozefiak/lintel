#!/usr/bin/env python3
"""Where does speech go missing between a recording and the transcript? (issue #135)

Standard library only. Run as:

    python3 -I score_loss.py --reference <entry.json | whisper raw.json> RESULT.json [RESULT.json ...]
    python3 -I score_loss.py --reference REF --json OUT.json RESULT.json

RESULT is the JSON `MeetingEvalTests` writes (`asr.segments`, optional `capture`). REFERENCE is a gold
`entry.json` (`transcript` with start and end in seconds) or a whisper.cpp `raw.json` (`transcription` with
`offsets.from` and `offsets.to` in milliseconds). Output is numbers only: never a word of either transcript.

Method. Every reference word gets a time by spreading the words of its turn evenly over the turn (a coarse
clock: a word is placed within a turn, so the position classes below are only as good as the turns are short).
Each reference turn is aligned with the transcript words that lie within two seconds of it (difflib, so order
inside a turn counts); a reference word with no partner is *lost*. Lost words are then split by where their
time falls against the transcript's own segments:

- `outside`: in no segment at all, so the audio was never sent to the engine, or the engine returned nothing
  (`outside500` leaves a margin of 0.5 s, for the coarse clock);
- `inside`: in a segment the engine decoded and the word did not come out (recognition); it is split into
  `middle` and `nearEdge` (within 0.4 s of a segment boundary: the voice activity detector's edges);
- `hardCut`: within 0.6 s of the end of a segment that is exactly the model window (a cut in the middle of speech).

The columns `outside`, `outside±.5s`, `inside` are shares of ALL reference words (they add up to `lost`); the
`rate:` columns are the loss rate among the words of that zone (the issue's "loss rate in the middle of a
segment", "within 0.4 s of a boundary", "at a hard cut", "deep in a gap").

`extra` counts transcript words with no reference partner (insertions, hallucinations, language mix-ups),
which a more eager detector pays for. Filler sounds (um, uh, mm ...) are not counted on either side.
"""

import argparse
import difflib
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("meeting_eval_score", os.path.join(HERE, "score.py"))
score = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(score)

FILLERS = {"um", "uh", "mm", "hmm", "mhm", "erm", "eh", "ehm", "yy", "yyy", "eee", "mmm", "hm"}
WINDOW_MS = 2_000
EDGE_MS = 400
CUT_MS = 600
# A segment cut at the model window is exactly this long (15 s, `MeetingSession.longestSegment`); since the widening
# never exceeds the window, a segment of exactly 15 s from before that change may also be a plain long one.
CUT_SEGMENT_MS = 14_990


def words_of(text):
    return [w for w in score.tokens(text) if w not in FILLERS]


def spread(turns):
    """[(startMs, endMs, [words])] -> [(timeMs, word, turnIndex)] with the words spread over each turn."""
    out = []
    for index, (start, end, words) in enumerate(turns):
        n = len(words)
        for i, word in enumerate(words):
            out.append((start + (end - start) * (i + 0.5) / n, word, index))
    return out


def load_reference(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    turns = []
    if "transcript" in data:
        for turn in data["transcript"]:
            words = words_of(turn.get("text", ""))
            if words:
                turns.append((float(turn["start"]) * 1000, float(turn["end"]) * 1000, words))
    elif "transcription" in data:
        for turn in data["transcription"]:
            words = words_of(turn.get("text", ""))
            if words:
                turns.append((float(turn["offsets"]["from"]), float(turn["offsets"]["to"]), words))
    else:
        raise SystemExit("reference: neither `transcript` nor `transcription`")
    return turns


def load_result(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    segments = []
    for seg in data["asr"]["segments"]:
        words = words_of(seg.get("text", ""))
        segments.append((float(seg["startMs"]), float(seg["endMs"]), words))
    segments.sort(key=lambda s: s[0])
    return segments, data.get("capture"), data


def align(ref_turns, hyp_words):
    """Every reference word as (time, lost), and the indexes of hypothesis words that found a partner."""
    times = [w[0] for w in hyp_words]
    import bisect

    matched_hyp = set()
    flags = []
    for index, (start, end, words) in enumerate(ref_turns):
        lo = bisect.bisect_left(times, start - WINDOW_MS)
        hi = bisect.bisect_right(times, end + WINDOW_MS)
        window = [hyp_words[i][1] for i in range(lo, hi)]
        matcher = difflib.SequenceMatcher(None, words, window, autojunk=False)
        paired = set()
        for block in matcher.get_matching_blocks():
            for k in range(block.size):
                paired.add(block.a + k)
                matched_hyp.add(lo + block.b + k)
        n = len(words)
        for i, _ in enumerate(words):
            flags.append((start + (end - start) * (i + 0.5) / n, i not in paired))
    return flags, matched_hyp


def distance_to_edges(t, segments):
    """(covered, distance to the nearest segment boundary) in ms."""
    covered = False
    best = float("inf")
    for start, end, _ in segments:
        if start <= t <= end:
            covered = True
        best = min(best, abs(t - start), abs(t - end))
    return covered, best


def covered_within(t, segments, margin):
    return any(start - margin <= t <= end + margin for start, end, _ in segments)


def analyse(ref_turns, segments):
    hyp_turns = [(s, e, w) for s, e, w in segments if w]
    hyp_words = spread(hyp_turns)
    hyp_words.sort(key=lambda w: w[0])
    flags, matched_hyp = align(ref_turns, hyp_words)
    total = len(flags)
    cuts = [(s, e) for s, e, _ in segments if e - s >= CUT_SEGMENT_MS]
    # zone -> [words, lost]
    zones = {name: [0, 0] for name in ("all", "outside", "outside500", "inside", "nearEdge", "middle", "hardCut")}

    def count(name, lost):
        zones[name][0] += 1
        zones[name][1] += 1 if lost else 0

    for t, lost in flags:
        covered, edge = distance_to_edges(t, segments)
        count("all", lost)
        if covered:
            count("inside", lost)
            count("nearEdge" if edge <= EDGE_MS else "middle", lost)
        else:
            count("outside", lost)
            if not covered_within(t, segments, 500):
                count("outside500", lost)
        if any(end - CUT_MS <= t <= end + CUT_MS for _, end in cuts):
            count("hardCut", lost)
    row = {
        "refWords": total,
        "lost": zones["all"][1],
        "lostRate": round(zones["all"][1] / total, 4) if total else None,
        "hypWords": len(hyp_words),
        "extra": len(hyp_words) - len(matched_hyp),
        "segments": len(segments),
        "cutSegments": len(cuts),
    }
    for name, (words, lost) in zones.items():
        row[name + "Words"] = words
        row[name + "Lost"] = lost
        row[name + "Rate"] = round(lost / words, 4) if words else None
        # The part of all reference words this zone's losses make up.
        row[name + "Share"] = round(lost / total, 4) if total else None
    row["extraRate"] = round(row["extra"] / max(1, len(hyp_words)), 4)
    # Share of the reference speech time (by turn) that no segment covers at all.
    uncovered_ms = 0.0
    spoken_ms = 0.0
    for start, end, _ in ref_turns:
        spoken_ms += end - start
        t = start
        while t < end:
            if not covered_within(t, segments, 0):
                uncovered_ms += min(250.0, end - t)
            t += 250.0
    row["uncoveredSpeechShare"] = round(uncovered_ms / spoken_ms, 4) if spoken_ms else None
    return row


def capture_summary(capture, channel):
    if not capture:
        return {}
    c = capture.get(channel) or {}
    seg = c.get("segmenting") or {}
    return {
        "segmentsSent": c.get("segmentsSent"),
        "emptyResults": c.get("emptyResults"),
        "hardCuts": c.get("hardCuts"),
        "shortSegments": c.get("shortSegments"),
        "nearMissChunks": seg.get("nearMissChunks"),
        "nearMissRuns": seg.get("nearMissRuns"),
        "paddedMs": (seg.get("paddedSamples") or 0) // 16,
    }


def fmt(value):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value * 100:.1f}%" if abs(value) < 1.5 else f"{value:.1f}"
    return str(value)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--reference", required=True)
    parser.add_argument("--json", help="write the rows as JSON here")
    parser.add_argument("--channel", default="system", help="capture counters of this channel (default system)")
    parser.add_argument("results", nargs="+")
    args = parser.parse_args(argv)
    ref = load_reference(args.reference)
    rows = []
    for path in args.results:
        segments, capture, _ = load_result(path)
        row = analyse(ref, segments)
        row["result"] = os.path.splitext(os.path.basename(path))[0]
        row["capture"] = capture_summary(capture, args.channel)
        rows.append(row)
    columns = [
        ("result", "run"), ("lostRate", "lost"), ("outsideShare", "outside"), ("outside500Share", "outside±.5s"),
        ("insideShare", "inside"), ("middleRate", "rate:middle"), ("nearEdgeRate", "rate:edge"),
        ("hardCutRate", "rate:cut"), ("outsideRate", "rate:gap"), ("extraRate", "extra"),
        ("uncoveredSpeechShare", "uncovered"), ("segments", "segs"), ("cutSegments", "cuts"),
    ]
    print(" | ".join(label for _, label in columns))
    for row in rows:
        print(" | ".join(fmt(row.get(key)) for key, _ in columns))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())

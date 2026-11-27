"""The synthetic meeting corpus of the actions-detection spike.

A meeting is `corpus/<id>.txt` (a header of `# key: value` lines, then one `[mm:ss] Speaker: text` line per
utterance) plus `corpus/<id>.gold.json` (the expected actions and the traps). Utterance ids count from 1 in file
order. Every meeting is fictional.
"""

import datetime
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(HERE, "corpus")

LINE = re.compile(r"^\[(\d{2}:\d{2})\] ([^:]+): (.+)$")

WEEKDAYS = {
    "pl": ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"],
    "en": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
}


class Utterance(object):
    def __init__(self, uid, time, speaker, text):
        self.id = uid
        self.time = time
        self.speaker = speaker
        self.text = text


class Meeting(object):
    def __init__(self, mid, lang, date, self_label, title, utterances, gold):
        self.id = mid
        self.lang = lang
        self.date = date
        self.self_label = self_label
        self.title = title
        self.utterances = utterances
        self.gold = gold

    @property
    def speakers(self):
        seen = []
        for u in self.utterances:
            if u.speaker not in seen:
                seen.append(u.speaker)
        return seen

    def transcript_lines(self):
        """The transcript in the notes format of `WholeNotesPrompt.transcriptLines`."""
        return "\n".join("[%s] %s: %s" % (u.time, u.speaker, u.text) for u in self.utterances)

    def weekday(self, lang=None):
        return WEEKDAYS[lang or self.lang][self.date.weekday()]


def parse(text, gold):
    header = {}
    utterances = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            continue
        if line.startswith("# "):
            key, _, value = line[2:].partition(":")
            header[key.strip()] = value.strip()
            continue
        match = LINE.match(line)
        if not match:
            raise ValueError("bad transcript line: %r" % line[:40])
        utterances.append(Utterance(len(utterances) + 1, match.group(1), match.group(2).strip(), match.group(3).strip()))
    return Meeting(
        header["id"],
        header["lang"],
        datetime.date.fromisoformat(header["date"]),
        header["self"],
        header.get("title", ""),
        utterances,
        gold,
    )


def load(mid, directory=CORPUS_DIR):
    with open(os.path.join(directory, mid + ".txt"), encoding="utf-8") as f:
        text = f.read()
    with open(os.path.join(directory, mid + ".gold.json"), encoding="utf-8") as f:
        gold = json.load(f)
    return parse(text, gold)


def load_all(directory=CORPUS_DIR, only=None):
    ids = sorted(name[:-4] for name in os.listdir(directory) if name.endswith(".txt"))
    if only:
        ids = [i for i in ids if any(i.startswith(prefix) for prefix in only)]
    return [load(i, directory) for i in ids]


def filler(lang, directory=CORPUS_DIR):
    with open(os.path.join(directory, "filler-%s.lines" % lang), encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def padded(meeting, pad, directory=CORPUS_DIR):
    """The meeting with `pad` neutral lines (no promise, day, hour, number or name) after every utterance, spoken by
    the other participants in turn, for the length test. Gold evidence ids are renumbered; times are redone."""
    if pad <= 0:
        return meeting
    import copy
    import random

    lines = filler(meeting.lang, directory)
    random.Random(meeting.id).shuffle(lines)
    others = [s for s in meeting.speakers if s != meeting.self_label] or [meeting.self_label]
    out = []
    k = 0
    for u in meeting.utterances:
        out.append(Utterance(len(out) + 1, "", u.speaker, u.text))
        for _ in range(pad):
            out.append(Utterance(len(out) + 1, "", others[k % len(others)], lines[k % len(lines)]))
            k += 1
    for i, u in enumerate(out):
        seconds = 4 + 9 * i
        u.time = "%02d:%02d" % (seconds // 60, seconds % 60) if seconds < 6000 else "99:59"
    gold = copy.deepcopy(meeting.gold)
    for item in gold["actions"] + gold.get("traps", []):
        item["evidence"] = [(e - 1) * (pad + 1) + 1 for e in item["evidence"]]
    return Meeting(meeting.id, meeting.lang, meeting.date, meeting.self_label, meeting.title, out, gold)

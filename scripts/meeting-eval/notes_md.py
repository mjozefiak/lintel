"""Shared Markdown reading for the notes tools (`notes_md_to_points.py`, `notes_structure.py`).

Standard library only. Reads the Markdown of one meeting note (Lintel's old layout, Lintel's topic layout, and the
notes of other apps: Wispr Flow, Granola) into sections with items. It never prints anything.

Section kinds (from the heading, in Polish or English, diacritics and decoration ignored):
  intro          text before the first heading
  summary        "Podsumowanie" / "Summary"
  topics         the old container "Omówione tematy" / "Topics discussed" (its sub-headings are topics)
  decisions      "Decyzje", "Podjęte decyzje", "Decisions"
  tasks          "Zadania", "Następne kroki", "Action items", "Next steps"
  questions      "Otwarte kwestie", "Open questions"
  participants   "Uczestnicy", "Participants"
  topic          any other heading: a topic named by the writer ("Inne" / "Other" is `other`)
"""

import re
import unicodedata

SUMMARY = {"podsumowanie", "summary", "streszczenie", "tldr", "overview", "przeglad"}
TOPICS = {"omowione tematy", "topics discussed", "tematy", "topics", "key points", "kluczowe punkty"}
DECISIONS = {"decyzje", "podjete decyzje", "decisions", "decisions made", "decyzja"}
TASKS = {"zadania", "nastepne kroki", "kolejne kroki", "next steps", "action items", "tasks", "to do", "todo"}
QUESTIONS = {"otwarte kwestie", "otwarte pytania", "pytania", "open questions"}
PARTICIPANTS = {"uczestnicy", "participants", "attendees"}
OTHER = {"inne", "other"}

# Labels the code of Lintel writes, by language (the labels of both layouts).
LABELS = {
    "pl": {
        "Podsumowanie", "Omówione tematy", "Decyzje", "Zadania", "Otwarte kwestie", "Uczestnicy",
        "Podjęte decyzje", "Następne kroki", "Inne",
    },
    "en": {
        "Summary", "Topics discussed", "Decisions", "Action items", "Open questions", "Participants",
        "Decisions made", "Next steps", "Other",
    },
}

HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LIST_ITEM = re.compile(r"^(\s*)([-*+]|\d{1,3}[.)])\s+(?:\[([ xX])\]\s+)?(.*)$")
RULE = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")


def normalize(text):
    """Lower case, no diacritics (also ł), no decoration: the key a heading is classified by."""
    text = text.replace("ł", "l").replace("Ł", "L")
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^0-9a-zA-Z]+", " ", text.lower())
    return " ".join(text.split())


def classify(heading):
    key = normalize(heading)
    for kind, names in (
        ("summary", SUMMARY), ("topics", TOPICS), ("decisions", DECISIONS), ("tasks", TASKS),
        ("questions", QUESTIONS), ("participants", PARTICIPANTS), ("other", OTHER),
    ):
        if key in names:
            return kind
    return "topic"


def plain(text):
    """The text of an item without Markdown decoration."""
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"(\*\*|__|\*|`)", "", text)
    text = re.sub(r"(?<!\w)_|_(?!\w)", "", text)
    return " ".join(text.split())


class Item:
    def __init__(self, text, bullet, checkbox, depth):
        self.text = text
        self.bullet = bullet  # a list item (False: a paragraph)
        self.checkbox = checkbox  # None, or " " / "x"
        self.depth = depth


class Section:
    def __init__(self, kind, heading, level):
        self.kind = kind
        self.heading = heading
        self.level = level
        self.items = []

    @property
    def bullets(self):
        return [i for i in self.items if i.bullet]

    @property
    def paragraphs(self):
        return [i for i in self.items if not i.bullet]


class Document:
    def __init__(self, sections, title):
        self.sections = sections
        self.title = title  # the heading text taken as the title, or None

    def of_kind(self, *kinds):
        return [s for s in self.sections if s.kind in kinds]


def parse(markdown):
    """Sections in order. The first one is `intro` (maybe empty). A level-1..6 heading starts a section."""
    sections = [Section("intro", None, 0)]
    current = sections[0]
    paragraph = []
    last = None

    def flush():
        nonlocal paragraph, last
        if paragraph:
            item = Item(plain(" ".join(paragraph)), False, None, 0)
            if item.text:
                current.items.append(item)
            last = None
            paragraph = []

    for raw in markdown.splitlines():
        line = raw.rstrip()
        if not line.strip() or RULE.match(line):
            flush()
            last = None
            continue
        match = HEADING.match(line.strip())
        if match:
            flush()
            current = Section(classify(match.group(2)), plain(match.group(2)), len(match.group(1)))
            sections.append(current)
            last = None
            continue
        line = re.sub(r"^\s*>\s?", "", line)
        match = LIST_ITEM.match(line)
        if match:
            flush()
            indent = len(match.group(1).replace("\t", "    "))
            text = plain(match.group(4))
            if text:
                last = Item(text, True, match.group(3), indent // 2)
                current.items.append(last)
            continue
        if line.startswith((" ", "\t")) and last is not None:
            last.text = plain(last.text + " " + line.strip())
            continue
        paragraph.append(line.strip())
    flush()

    # A single heading of the shallowest level at the very top that names no section is the title.
    headings = sections[1:]
    title = None
    if headings and not any(i.items for i in sections[:1]) and not sections[0].items:
        shallowest = min(s.level for s in headings)
        at_top = [s for s in headings if s.level == shallowest]
        if len(at_top) == 1 and at_top[0] is headings[0] and at_top[0].kind == "topic":
            title = at_top[0].heading
            # What stands under the title, before the next heading, is the intro.
            sections[0].items.extend(at_top[0].items)
            sections.remove(at_top[0])
    return Document(sections, title)


def split_task(text):
    """A task line `... — osoba: X, termin: Y` -> (text, owner or None, due or None).

    Reads the owner and due labels of both languages and of the old layouts; "Do przypisania" / "Unassigned" is
    no owner."""
    owner = due = None
    base = text
    match = re.search(r"\s+[—–-]+\s+((?:osoba|owner|person|odpowiedzialny)\s*:.*)$", text, re.IGNORECASE)
    if match:
        base = text[: match.start()]
        details = match.group(1)
        found = re.search(r"(?:osoba|owner|person|odpowiedzialny)\s*:\s*(.*?)(?=,\s*(?:termin|due|deadline)\s*:|$)", details, re.IGNORECASE)
        if found:
            owner = found.group(1).strip() or None
        found = re.search(r"(?:termin|due|deadline)\s*:\s*(.*)$", details, re.IGNORECASE)
        if found:
            due = found.group(1).strip() or None
    if owner is not None and normalize(owner) in ("do przypisania", "unassigned", "brak"):
        owner = None
    return base.strip(), owner, due

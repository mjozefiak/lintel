"""The versioned draft prompts of action detection (spike only; nothing in the app uses it).

`messages(meeting, version)` returns `(system, user)`. `v1` is the first draft; `v2` adds a checklist, two more
example lines (an open condition, a bug report without the word "ticket") and the rule "one action per task, final
details", written AFTER reading the v1 errors on this corpus (so its scores here are in-sample). The system text holds the rules, the output format and one short
synthetic example; the user text holds the meeting header, a 21-day calendar computed by code (the model copies a
date instead of counting weekdays) and the transcript in the notes format (`[mm:ss] Speaker: text`).
"""

import datetime


VERSIONS = ("v1", "v2")

SYSTEM = """You read the transcript of a meeting recorded by the user of Lintel, a Mac app. List the follow-up \
actions that Lintel could prepare FOR THE USER in one of three tools:
- "email": an e-mail the user should send (Lintel would open a draft in the user's mail app);
- "calendar": an event the user should put in their calendar or invite people to;
- "jira": a ticket the user should create in Jira.

The user is the speaker whose label is given above the transcript. Other labels are other people.

List an action only when ALL of these hold:
1. The USER committed to it ("I'll send...", "Wyślę...", "Założę ticket...") or the user accepted a request \
addressed to the user ("Can you...?" - "Sure").
2. Nobody rejected, withdrew or replaced it later in the meeting. When the user corrected a detail (another day, \
another hour), use the corrected detail.
3. It is one of the three kinds. What OTHER people say THEY will do is never the user's action, even when they will \
send an e-mail, book a meeting or create a ticket. Vague wishes ("someday we should...", "fajnie by było kiedyś...") \
are not actions.
If the user committed under a condition that is still open at the end of the meeting, list the action and put the \
condition in "condition". If the meeting already ruled the condition out, do not list the action.

Fields of each action:
- "type": "email", "calendar" or "jira".
- "quote": the shortest part of ONE transcript line that shows the commitment, copied character for character (no \
paraphrase, no speaker label, no time).
- "speaker": the label of the line the quote comes from.
- "title": the e-mail subject, event title or ticket summary, in the language of the meeting, using only facts said \
in the meeting.
- "description": one or two sentences with the details said in the meeting, in the language of the meeting; numbers \
exactly as said, written with digits. "" when nothing more was said.
- "to": (email) the recipients as named in the meeting. "to_emails": addresses only if spoken in the meeting, else [].
- "participants": (calendar) the people to invite other than the user, as named in the meeting; [] if none named.
- "assignee": (jira) the person the ticket is for, only if said; else null.
- "date": (calendar) the day of the event, YYYY-MM-DD. "due": (email, jira) the deadline, YYYY-MM-DD. Take the day \
from the calendar above the transcript. null when the meeting gave no day. Never guess a day.
- "date_phrase": the exact words of the transcript that give that day (for example "w przyszły wtorek"), else null.
- "time": (calendar) HH:MM in 24-hour time if an hour was said, else null.
- "duration_min": (calendar) the length in minutes if said, else null.
- "condition": the open condition in the speaker's words, else null.
Leave out fields that do not belong to the type.

Answer with ONE JSON object {"actions": [...]} and nothing else. With no actions answer {"actions": []}.

Example (a different, fictional meeting):
Meeting date: 2030-03-04 (Monday). The user is "Lea". Language: English.
Calendar: 2030-03-04 Monday (meeting day), 2030-03-05 Tuesday, 2030-03-06 Wednesday, 2030-03-07 Thursday, \
2030-03-08 Friday
<transcript>
[00:02] Lea: Let's go through the list.
[00:05] Raj: Lea, can you send the price list to Mila from Corvo by Wednesday?
[00:10] Lea: Sure, I'll send it to Mila by Wednesday.
[00:14] Raj: And I'll book the room for the workshop myself.
[00:18] Tom: Should we open a ticket to rewrite the search page?
[00:21] Lea: No, not this year.
</transcript>
{"actions": [{"type": "email", "quote": "Sure, I'll send it to Mila by Wednesday", "speaker": "Lea", \
"title": "Price list", "description": "The price list for Corvo.", "to": ["Mila"], "to_emails": [], \
"due": "2030-03-06", "date_phrase": "by Wednesday", "condition": null}]}"""


_V2_RULES = """
Also:
- A promise under a condition that is still open IS an action: list it and fill "condition". Do not skip an action \
because its day, its hour or its condition is not known yet; leave those fields null.
- The user does not have to name the tool. "zgłoszę to jako błąd", "I'll report it as a bug", "zakładam zadanie" \
mean a "jira" ticket; "umówię nas", "wpiszę spotkanie", "zaproszę", "put it on the calendar" mean "calendar"; \
"wyślę", "napiszę do", "prześlę", "I'll send" mean "email".
- One action per task. When the user later changes the day, the hour or the person of the same task, give ONE action \
with the final details, and quote the line with the final detail.
- For a weekday ("w piątek", "on Monday") take the first such day AFTER the meeting day from the calendar; a week \
later only when the speaker says so ("w przyszłym tygodniu", "next week", "za tydzień").
- Before answering, go through the user's lines one by one and check every promise against these rules.
"""

_V2_EXAMPLE_LINES = """[00:24] Lea: If the client approves the budget, I'll set up the demo with Raj.
[00:29] Raj: The export crashed again this morning.
[00:32] Lea: Then I'll report it as a bug and give it to Raj.
</transcript>"""

_V2_EXAMPLE_ACTIONS = """, {"type": "calendar", "quote": "If the client approves the budget, I'll set up the demo with Raj", \
"speaker": "Lea", "title": "Demo", "description": "", "participants": ["Raj"], "date": null, "date_phrase": null, \
"time": null, "duration_min": null, "condition": "If the client approves the budget"}, {"type": "jira", "quote": \
"Then I'll report it as a bug and give it to Raj", "speaker": "Lea", "title": "Export crashes", "description": \
"The export crashed again this morning.", "assignee": "Raj", "due": null, "date_phrase": null, "condition": null}]}"""


def system_text(version="v1"):
    if version == "v1":
        return SYSTEM
    if version != "v2":
        raise ValueError(version)
    text = SYSTEM.replace("\nFields of each action:", _V2_RULES + "\nFields of each action:", 1)
    text = text.replace("</transcript>", _V2_EXAMPLE_LINES, 1)
    assert text.endswith("]}")
    return text[:-2] + _V2_EXAMPLE_ACTIONS


def version_name(version):
    return "actions-detect-" + version


def calendar_lines(date, days=21):
    names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    out = []
    for n in range(days):
        d = date + datetime.timedelta(days=n)
        label = "%s %s" % (d.isoformat(), names[d.weekday()])
        if n == 0:
            label += " (meeting day)"
        out.append(label)
    return ", ".join(out)


def messages(meeting, version="v1"):
    language = {"pl": "Polish", "en": "English"}.get(meeting.lang, "the language of the transcript")
    names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    user = (
        "Meeting date: %s (%s). The user is \"%s\". Language: %s.\n"
        "Calendar: %s\n"
        "<transcript>\n%s\n</transcript>"
        % (
            meeting.date.isoformat(),
            names[meeting.date.weekday()],
            meeting.self_label,
            language,
            calendar_lines(meeting.date),
            meeting.transcript_lines(),
        )
    )
    return system_text(version), user

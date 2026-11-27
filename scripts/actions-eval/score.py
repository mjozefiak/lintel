"""Scoring of proposed actions against the gold file of a meeting.

A proposed action matches a gold action when its type is one the gold allows and its quote lies in one of the gold's
evidence utterances (one-to-one, in order). An unmatched proposal is classified: `bad_quote` (the quote is not in
the transcript), `trap:<kind>` (it came from a trap's utterances), `wrong_type`, `duplicate` or `unexpected`.
Fields are compared only for matched pairs, only for the fields the gold names.
"""

import re

from guard import date_field, locate_quote
from textnorm import digit_numbers, fold, names_match, spoken_numbers

FIELDS = ("title", "to", "to_emails", "participants", "assignee", "date", "due", "time", "condition",
          "must_mention", "speaker")


def _norm_time(value):
    match = re.fullmatch(r"\s*(\d{1,2})[:.](\d{2})\s*", value or "")
    return "%02d:%s" % (int(match.group(1)), match.group(2)) if match else None


def _persons_ok(spec, values):
    values = [v for v in (values or []) if isinstance(v, str) and v.strip()]
    groups = spec.get("required", []) + spec.get("optional", [])
    for v in values:
        if not any(names_match(v, alias) for group in groups for alias in group):
            return False
    for group in spec.get("required", []):
        if not any(names_match(v, alias) for v in values for alias in group):
            return False
    return True


def field_ok(name, gold_value, pred, meeting):
    if name == "title":
        title = fold(pred.get("title") or "")
        return all(fold(k) in title for k in gold_value)
    if name in ("to", "participants"):
        return _persons_ok(gold_value, pred.get(name))
    if name == "to_emails":
        got = set(e.casefold() for e in (pred.get("to_emails") or []) if isinstance(e, str))
        return all(e.casefold() in got for e in gold_value)
    if name == "assignee":
        value = pred.get("assignee")
        if gold_value is None:
            return not (isinstance(value, str) and value.strip())
        return isinstance(value, str) and any(names_match(value, alias) for alias in gold_value)
    if name in ("date", "due"):
        value = pred.get(date_field(pred))
        if gold_value is None:
            return not (isinstance(value, str) and value.strip())
        return isinstance(value, str) and value.strip() in gold_value
    if name == "time":
        value = pred.get("time")
        if gold_value is None:
            return not (isinstance(value, str) and value.strip())
        return _norm_time(value) == gold_value
    if name == "condition":
        value = pred.get("condition")
        has = isinstance(value, str) and bool(value.strip())
        return has == bool(gold_value)
    if name == "must_mention":
        text = (pred.get("title") or "") + " " + (pred.get("description") or "")
        found = set(digit_numbers(text)) | spoken_numbers(text)
        return all(float(n) in found for n in gold_value)
    raise ValueError(name)


def score_meeting(meeting, actions):
    gold = meeting.gold
    located = [locate_quote(meeting, a.get("quote")) for a in actions]
    matched = {}
    used_gold = set()
    classes = []
    for i, action in enumerate(actions):
        u = located[i]
        if u is None:
            classes.append("bad_quote")
            continue
        hit = None
        for g in gold["actions"]:
            if g["id"] in used_gold:
                continue
            if action.get("type") in g["type"] and u.id in g["evidence"]:
                hit = g
                break
        if hit is not None:
            matched[i] = hit
            used_gold.add(hit["id"])
            classes.append("match")
            continue
        trap = next((t for t in gold.get("traps", []) if u.id in t["evidence"]), None)
        same_place = [g for g in gold["actions"] if u.id in g["evidence"]]
        if trap is not None and not same_place:
            classes.append("trap:" + trap["kind"])
        elif same_place and all(g["id"] in used_gold for g in same_place) and any(
                action.get("type") in g["type"] for g in same_place):
            classes.append("duplicate")
        elif same_place:
            classes.append("wrong_type")
        else:
            classes.append("unexpected")

    fields = {}
    all_ok = 0
    for i, g in matched.items():
        ok_all = True
        pred = actions[i]
        for name, value in g["fields"].items():
            ok = field_ok(name, value, pred, meeting)
            total, good = fields.get(name, (0, 0))
            fields[name] = (total + 1, good + (1 if ok else 0))
            ok_all = ok_all and ok
        speaker_ok = (pred.get("speaker") or "").strip() == located[i].speaker
        total, good = fields.get("speaker", (0, 0))
        fields["speaker"] = (total + 1, good + (1 if speaker_ok else 0))
        ok_all = ok_all and speaker_ok
        all_ok += 1 if ok_all else 0

    traps_hit = {}
    for c in classes:
        if c.startswith("trap:"):
            traps_hit[c[5:]] = traps_hit.get(c[5:], 0) + 1
    missed = [g["id"] for g in gold["actions"] if g["id"] not in used_gold]
    return {
        "meeting": meeting.id,
        "gold": len(gold["actions"]),
        "traps": len(gold.get("traps", [])),
        "trap_kinds": [t["kind"] for t in gold.get("traps", [])],
        "proposed": len(actions),
        "from_other_speaker": sum(1 for u in located if u is not None and u.speaker != meeting.self_label),
        "tp": len(matched),
        "fp": len(actions) - len(matched),
        "fn": len(missed),
        "missed": missed,
        "classes": classes,
        "traps_hit": traps_hit,
        "fields": fields,
        "all_fields_ok": all_ok,
        "field_errors": [
            "%s:%s" % (g["id"], name)
            for i, g in matched.items()
            for name, value in g["fields"].items()
            if not field_ok(name, value, actions[i], meeting)
        ],
    }


def total(scores):
    out = {"gold": 0, "traps": 0, "proposed": 0, "from_other_speaker": 0, "tp": 0, "fp": 0, "fn": 0, "all_fields_ok": 0,
           "traps_hit": {}, "trap_kinds": {}, "fields": {}, "classes": {}}
    for s in scores:
        for key in ("gold", "traps", "proposed", "from_other_speaker", "tp", "fp", "fn", "all_fields_ok"):
            out[key] += s[key]
        for kind, n in s["traps_hit"].items():
            out["traps_hit"][kind] = out["traps_hit"].get(kind, 0) + n
        for kind in s["trap_kinds"]:
            out["trap_kinds"][kind] = out["trap_kinds"].get(kind, 0) + 1
        for c in s["classes"]:
            key = c.split(":")[0] if c.startswith("trap:") else c
            out["classes"][key] = out["classes"].get(key, 0) + 1
        for name, (t, g) in s["fields"].items():
            tt, gg = out["fields"].get(name, (0, 0))
            out["fields"][name] = (tt + t, gg + g)
    p = out["tp"] / float(out["proposed"]) if out["proposed"] else 1.0
    r = out["tp"] / float(out["gold"]) if out["gold"] else 1.0
    out["precision"] = p
    out["recall"] = r
    out["f1"] = 2 * p * r / (p + r) if p + r else 0.0
    field_total = sum(t for t, _ in out["fields"].values())
    field_good = sum(g for _, g in out["fields"].values())
    out["field_accuracy"] = field_good / float(field_total) if field_total else 1.0
    out["all_fields_rate"] = out["all_fields_ok"] / float(out["tp"]) if out["tp"] else 0.0
    return out

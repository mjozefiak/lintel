"""Run the action-detection prompt over the synthetic corpus and score it (spike harness, never run in CI).

    # local model: start llama-server by hand on the GGUF the app uses, then
    python3 -I scripts/actions-eval/run.py --provider llama --url http://127.0.0.1:8091 --runs 3 --out <dir>
    # Claude Code CLI with the ADR 0011 isolation flags
    python3 -I scripts/actions-eval/run.py --provider claude --model sonnet --runs 3 --out <dir>
    # score stored answers again (after a guard or scorer change), no model call; pass the same --pad
    python3 -I scripts/actions-eval/run.py --rescore <dir>/<tag>
    # length test: 4 neutral lines after every utterance (start llama-server with -c 16384)
    python3 -I scripts/actions-eval/run.py --provider llama --pad 4 --only pl11 pl12 en02 pl06 ...

Only the synthetic corpus is sent. Answers are stored under `<out>/<tag>/run<N>/<meeting>.json`; the summary goes to
`<out>/<tag>/summary.json` and stdout.
"""

import argparse
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import corpus  # noqa: E402
import guard  # noqa: E402
import prompt  # noqa: E402
import score  # noqa: E402

CLAUDE_FLAGS = [
    "--output-format", "json", "--tools", "", "--no-session-persistence", "--disable-slash-commands",
    "--strict-mcp-config", "--setting-sources", "", "--safe-mode",
]
ENV_ALLOW = ("HOME", "USER", "LANG", "CLAUDE_CONFIG_DIR")


def call_llama(url, system, user, max_tokens=3000):
    parsed = urllib.parse.urlparse(url)
    if parsed.hostname != "127.0.0.1":
        raise SystemExit("llama-server must be on 127.0.0.1")
    body = {
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0, "max_tokens": max_tokens, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    request = urllib.request.Request(
        url.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"})
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=1800) as response:
        reply = json.loads(response.read().decode("utf-8"))
    seconds = time.monotonic() - started
    choice = reply["choices"][0]
    usage = reply.get("usage", {})
    return {
        "text": choice["message"]["content"], "seconds": seconds, "cut": choice.get("finish_reason") == "length",
        "input_tokens": usage.get("prompt_tokens", 0), "output_tokens": usage.get("completion_tokens", 0),
        "model": reply.get("model"),
    }


def call_claude(binary, model, system, user):
    work = tempfile.mkdtemp(prefix="actions-eval-")
    os.chmod(work, 0o700)
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": work}
    for name in ENV_ALLOW:
        if name in os.environ:
            env[name] = os.environ[name]
    argv = [binary, "-p", "--model", model] + CLAUDE_FLAGS + ["--system-prompt", system]
    started = time.monotonic()
    try:
        done = subprocess.run(argv, input=user.encode("utf-8"), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              cwd=work, env=env, timeout=900)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    seconds = time.monotonic() - started
    try:
        reply = json.loads(done.stdout.decode("utf-8"))
    except ValueError:
        return {"text": "", "seconds": seconds, "error": "unparsable CLI output (exit %d)" % done.returncode}
    usage = reply.get("usage") or {}
    models = sorted((reply.get("modelUsage") or {}).keys())
    return {
        "text": reply.get("result") or "", "seconds": seconds, "error": "provider error" if reply.get("is_error") else None,
        "input_tokens": (usage.get("input_tokens") or 0) + (usage.get("cache_creation_input_tokens") or 0)
        + (usage.get("cache_read_input_tokens") or 0),
        "output_tokens": usage.get("output_tokens") or 0, "model": ",".join(models) or model,
        "cost_usd": reply.get("total_cost_usd"),
    }


def parse_answer(text):
    """The `actions` list of a model answer; (actions, ok)."""
    t = (text or "").strip()
    if t.startswith("```"):
        t = t.strip("`")
        if t.startswith("json"):
            t = t[4:]
    start, end = t.find("{"), t.rfind("}")
    if start < 0 or end <= start:
        return [], False
    try:
        data = json.loads(t[start:end + 1])
    except ValueError:
        return [], False
    actions = data.get("actions") if isinstance(data, dict) else None
    if not isinstance(actions, list):
        return [], False
    return [a for a in actions if isinstance(a, dict)], True


def score_run(meetings, answers):
    """Raw and guarded scores of one run. `answers` maps meeting id -> stored answer dict."""
    raw_scores, guarded_scores, reports = [], [], guard.Report()
    parse_failures = 0
    for m in meetings:
        actions, ok = parse_answer(answers[m.id].get("text"))
        parse_failures += 0 if ok else 1
        raw_scores.append(score.score_meeting(m, actions))
        kept, report, _ = guard.check(m, actions)
        reports.add(report)
        guarded_scores.append(score.score_meeting(m, kept))
    seconds = [answers[m.id].get("seconds", 0.0) for m in meetings]
    return {
        "raw": score.total(raw_scores), "guarded": score.total(guarded_scores), "guard": reports.as_dict(),
        "per_meeting_raw": raw_scores, "per_meeting_guarded": guarded_scores, "parse_failures": parse_failures,
        "seconds_total": sum(seconds), "seconds_median": statistics.median(seconds) if seconds else 0.0,
        "seconds_max": max(seconds) if seconds else 0.0,
        "input_tokens": sum(answers[m.id].get("input_tokens", 0) for m in meetings),
        "output_tokens": sum(answers[m.id].get("output_tokens", 0) for m in meetings),
        "cost_usd": sum(answers[m.id].get("cost_usd") or 0.0 for m in meetings),
        "errors": sum(1 for m in meetings if answers[m.id].get("error")),
        "models": sorted(set(str(answers[m.id].get("model")) for m in meetings)),
        "prompts": sorted(set(str(answers[m.id].get("prompt")) for m in meetings)),
    }


def headline(run):
    r, g = run["raw"], run["guarded"]
    return {
        "precision_raw": r["precision"], "recall_raw": r["recall"], "f1_raw": r["f1"],
        "precision": g["precision"], "recall": g["recall"], "f1": g["f1"],
        "field_accuracy_raw": r["field_accuracy"], "field_accuracy": g["field_accuracy"],
        "all_fields_rate_raw": r["all_fields_rate"], "all_fields_rate": g["all_fields_rate"],
        "trap_hits_raw": sum(r["traps_hit"].values()), "trap_hits": sum(g["traps_hit"].values()),
        "bad_quotes_raw": r["classes"].get("bad_quote", 0),
        "quotes_from_other_speaker_raw": r["from_other_speaker"],
        "invented_values_raw": sum(run["guard"][k] for k in (
            "person_removed", "email_removed", "date_removed", "time_removed", "description_number",
            "dropped_title_number")),
        "wrong_dates_fixed": run["guard"]["date_fixed"],
        "seconds_total": run["seconds_total"], "seconds_median": run["seconds_median"],
        "seconds_max": run["seconds_max"],
    }


def summarize(runs):
    heads = [headline(r) for r in runs]
    median = dict((k, statistics.median([h[k] for h in heads])) for k in heads[0])
    return {"runs": heads, "median": median, "prompts": sorted(set(p for r in runs for p in r["prompts"]))}


def print_summary(tag, runs, summary):
    m = summary["median"]
    print("ACTIONS-EVAL %s runs=%d prompt=%s" % (tag, len(runs), ",".join(summary.get("prompts", []))))
    print("  models: %s" % ", ".join(sorted(set(x for r in runs for x in r["models"]))))
    for name in ("precision", "recall", "f1", "field_accuracy", "all_fields_rate"):
        print("  %-16s raw %.3f  guarded %.3f" % (name, m[name + "_raw"], m[name]))
    print("  trap hits        raw %d  guarded %d (of %d traps)" % (
        m["trap_hits_raw"], m["trap_hits"], runs[0]["raw"]["traps"]))
    print("  bad quotes raw %d, quotes from another speaker raw %d, invented values raw %d, wrong dates fixed %d" % (
        m["bad_quotes_raw"], m["quotes_from_other_speaker_raw"], m["invented_values_raw"], m["wrong_dates_fixed"]))
    print("  seconds: total %.1f, median per meeting %.1f, max %.1f" % (
        m["seconds_total"], m["seconds_median"], m["seconds_max"]))
    for i, r in enumerate(runs, 1):
        g = r["guarded"]
        print("  run%d: tp=%d fp=%d fn=%d traps=%s fields=%s parse_failures=%d errors=%d guard=%s" % (
            i, g["tp"], g["fp"], g["fn"], g["traps_hit"],
            dict((k, "%d/%d" % (v[1], v[0])) for k, v in sorted(g["fields"].items())),
            r["parse_failures"], r["errors"], r["guard"]))


def load_answers(directory, meetings):
    answers = {}
    for m in meetings:
        with open(os.path.join(directory, m.id + ".json"), encoding="utf-8") as f:
            answers[m.id] = json.load(f)
    return answers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["llama", "claude"])
    parser.add_argument("--url", default="http://127.0.0.1:8091")
    parser.add_argument("--model", default="sonnet")
    parser.add_argument("--claude", default=os.path.expanduser("~/.local/bin/claude"))
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--out")
    parser.add_argument("--tag")
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--rescore")
    parser.add_argument("--prompt", choices=list(prompt.VERSIONS), default="v1")
    parser.add_argument("--pad", type=int, default=0, help="neutral lines after every utterance (length test)")
    args = parser.parse_args()

    meetings = [corpus.padded(m, args.pad) for m in corpus.load_all(only=args.only)]
    if args.rescore:
        base = args.rescore
        run_dirs = sorted(d for d in os.listdir(base) if d.startswith("run"))
        runs = [score_run(meetings, load_answers(os.path.join(base, d), meetings)) for d in run_dirs]
        summary = summarize(runs)
        tag = os.path.basename(base.rstrip("/"))
    else:
        if not args.provider or not args.out:
            parser.error("--provider and --out are required")
        tag = args.tag or ((args.provider if args.provider == "llama" else "claude-" + args.model) + "-" + args.prompt + ("-pad%d" % args.pad if args.pad else ""))
        base = os.path.join(args.out, tag)
        runs = []
        for n in range(1, args.runs + 1):
            directory = os.path.join(base, "run%d" % n)
            os.makedirs(directory, exist_ok=True)
            answers = {}
            for m in meetings:
                path = os.path.join(directory, m.id + ".json")
                if os.path.exists(path):
                    with open(path, encoding="utf-8") as f:
                        answers[m.id] = json.load(f)
                    continue
                system, user = prompt.messages(m, args.prompt)
                if args.provider == "llama":
                    answer = call_llama(args.url, system, user)
                else:
                    answer = call_claude(args.claude, args.model, system, user)
                answer["prompt"] = prompt.version_name(args.prompt)
                answers[m.id] = answer
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(answer, f, ensure_ascii=False, indent=1)
                print("run%d %s %.1fs" % (n, m.id, answer["seconds"]), flush=True)
            runs.append(score_run(meetings, answers))
        summary = summarize(runs)
    with open(os.path.join(base, "summary.json"), "w", encoding="utf-8") as f:
        json.dump({"tag": tag, "summary": summary, "runs": runs}, f, ensure_ascii=False,
                  indent=1, default=list)
    print_summary(tag, runs, summary)


if __name__ == "__main__":
    main()

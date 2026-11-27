# Proactive actions: detection quality spike — 2026-11-26

Decision 9 of the 2026-11-23 brainstorm on proactive actions: before the spec, measure whether a model can read a
meeting transcript and propose **e-mail**, **calendar event** and **Jira ticket** actions for the user with the right
fields (recipient, deadline, participants, title, description), a source quote and its speaker, and no invented
details. The measurement follows ADR 0011 gate G (synthetic corpus, development harness, Claude through the CLI with
the isolation flags) and `RealWholeNotesTests`.

**This is input for the owner, not a decision.** The prompt, the output format and the guard are drafts for the
spike; nothing in the app changes. Every product and UX choice (cards, approval, which models may offer actions) stays
with the owner and the prototype.

## 1. Short answer

| | Claude Sonnet (CLI) | Qwen3-30B-A3B (local) | Qwen3-4B (local) |
|---|---|---|---|
| Finds the user's actions (recall) | **1.00** | 0.82 (prompt v1) / 0.95 (v2, in-sample) | 0.87 / 0.90 |
| Proposals that are real actions (precision, after guard) | **1.00** | 0.94 / 0.93 | 0.94 / 0.95 |
| Found actions with every checked field right (after guard) | **1.00 / 0.97** | 0.78 / 0.73 | 0.53 / 0.60 |
| Trap proposals per corpus run (37 traps) | **0** | 1 / 2 | 1 / 2 |
| Same, meetings padded to 30-minute length (v2) | 1.00 recall, 0 traps, 0.92 every field | 0.90 recall, 1 trap, 0.74 every field | not run |
| Median seconds per meeting (M4 Max) | 4.5–5.0 (incl. CLI start) | 3.2–3.8 (model already loaded) | 3.2–3.3 |

Medians of 3 runs over 16 synthetic meetings (12 Polish, 4 English) with 39 gold actions and 37 traps.

* **Claude Sonnet** proposed every gold action and no trap in all 3 runs of both prompts, quoted the transcript
  verbatim every time (none of its 117 v1 or 117 v2 proposals failed the quote check) and kept that at meeting
  length. Its only field errors were 1 assignee (v1, 1 run) and a date regression caused by a rule added in prompt v2
  (section 4.2); at meeting length it also left the participants of one event empty in 2 of 3 runs.
* **Qwen3-30B-A3B** finds most actions but gets a field wrong in about one found action in four even after the guard,
  proposes 1–2 trap actions per corpus run (a promise the user withdrew later, a promise another speaker made for
  themselves), counts weekdays wrong despite a calendar in the prompt, and missed every conditional promise with v1.
  A prompt revision (v2) lifted recall to 0.95, but v2 was written after reading these errors, so that number is
  optimistic.
* **Qwen3-4B** (the only catalog model on Macs with less than 32 GB) finds actions about as often as the 30B but
  fills fields badly: 40–47 % of the actions it finds carry a wrong field.

**Recommendation (owner decides): hybrid, within decision 4** ("detection model = the notes provider"). Claude
measured well enough for prefilled, editable cards. The local 30B measured well enough only to *propose* (type,
quote, speaker, title) with every field shown as editable, dates computed by code, flags for "another speaker said
it" and "ambiguous day", and no "always allow" graduation. The local 4B did not measure well enough to prefill
fields. "Local is enough" is not supported by these numbers; "Claude only" would leave users who keep everything on
the Mac without actions. Section 7 lays the options out for the owner.

## 2. Setup

**Corpus** (`scripts/actions-eval/corpus/`, fictional, written for this spike): 16 meetings, 12 Polish and 4 English,
10 to 43 utterances (`[mm:ss] Speaker: text`, the notes format). The two longest Polish ones (`pl11`, `pl12`) imitate
speech-recognition output: lower case, no punctuation, fillers. Speaker labels include first names, the default
`Ja` / `Me` and `Mówca N` / `Speaker N` (one microphone in a room). Each meeting has a gold file: 39 actions (15
calendar, two of which may also be an e-mail invitation, 12 e-mail, 12 Jira), each with the utterances a correct
quote may come from and the expected fields, and 37 traps:

| Trap kind | Count | Example (synthetic) |
|---|---|---|
| `other_speaker` | 16 | Ola: "Ja wyślę mu maila z podsumowaniem po spotkaniu." (Ola's job, not the user's) |
| `rejected` | 11 | Tomek proposes a migration ticket; Marta: "Nie, nie w tym kwartale." |
| `condition_failed` | 4 | "Gdyby Darek był w biurze, to bym go zaprosiła…" / "Darek jest na urlopie do stycznia." |
| `vague` | 4 | "Fajnie by było kiedyś uporządkować naszą wiki." |
| `withdrawn` | 1 | "ankietę wyślę do wszystkich klientów" … later "ankietę jednak wyśle dział obsługi nie ja" |
| `hedge` | 1 | "zobaczę nie obiecuję raczej nie w tym miesiącu" |

The gold also covers: requests to the user that the user accepts (the quote may be the request or the answer), four
conditional promises still open at the end (must be listed with the condition), deadlines that were never said (must
be `null`), relative dates ("pojutrze", "do końca tygodnia", "w przyszły wtorek", "za dwa tygodnie w poniedziałek",
"next Friday", "by end of day"), Polish hours ("o wpół do trzeciej" = 14:30), a self-correction ("w czwartek, a nie,
przepraszam, w piątek o trzynastej"), a later change of deadline and of assignee, numbers said in words
("osiemnaście tysięcy czterysta", "czterdzieści dwa tysiące"), an address spoken by another participant, and a team
as a participant.

**Prompt** (`scripts/actions-eval/prompt.py`, `actions-detect-v1` and `-v2`): one system text with the rules, the
JSON output format and one synthetic example; the user text gives the meeting date and weekday, the user's speaker
label, the language, a 21-day calendar computed by code ("2026-11-24 Tuesday, …") and the transcript. Output per
action: `type`, `quote`, `speaker`, `title`, `description`, `to` / `to_emails` (e-mail), `participants`, `date`,
`time`, `duration_min` (calendar), `assignee`, `due` (Jira, e-mail), `date_phrase`, `condition`. v2 adds a checklist
(open conditions are actions, a bug report is a ticket without the word "ticket", one action per task with the final
details, weekday rule) and two example lines; it was written **after** reading the v1 errors on this corpus.

**Guard** (`scripts/actions-eval/guard.py`, in the spirit of `NotesFactGuard`): the quote must be a verbatim part of
one utterance (case, diacritics and punctuation ignored) or the action is dropped; the speaker is taken from that
line; persons must be named in the transcript (any grammatical case), addresses must appear verbatim, numbers in the
title or description must be said (digits or words); the date must follow from `date_phrase` or the quote's line by
the code's own resolver (`dates.py`, every reading of an ambiguous phrase), otherwise it is replaced by the only
reading or removed; the hour must be said within two lines of the quote.

**Scoring** (`scripts/actions-eval/score.py`): a proposal matches a gold action when its type is allowed and its
quote lies in one of the gold's utterances; unmatched proposals are classified (`bad_quote`, `trap:<kind>`,
`duplicate`, `wrong_type`, `unexpected`). Fields are compared on matched pairs only: title keywords, recipients and
participants (required and allowed sets, name in any case), assignee, date or deadline (accepted dates or `null`),
hour, condition present or not, numbers kept, speaker. "Every field right" = the share of found actions whose gold
fields are all correct. Scores are computed on the raw answer and after the guard.

**Models and runs.** Claude Sonnet (`claude-sonnet-5-5`, Claude Code 2.1.332) through `claude -p` with the argv of
`ProviderDescriptor.claudeCode` (`--tools "" --no-session-persistence --disable-slash-commands --strict-mcp-config
--setting-sources "" --safe-mode`, JSON output, system prompt as an argument, transcript on stdin, an empty `0700`
working directory, environment allowlist). Qwen3-30B-A3B-Instruct-2507 and Qwen3-4B-Instruct-2507 (the app's
catalog GGUFs, Q4_K_M) through `llama-server` on 127.0.0.1, temperature 0, no thinking, the model loaded before
the runs (load time is not in the numbers). 3 runs per configuration; the table values are medians. Greedy decoding
makes the local runs almost deterministic (15–16 of 16 answers identical across the 3 runs); Claude answered
differently every run (1 of 16 identical) and scored the same. Hardware: Apple M4 Max, 128 GB, macOS 27.0.1.

**Length test.** `--pad 8` puts eight neutral lines (no promise, day, hour, number or name; spoken by the other
participants) after every utterance: 90 to 387 lines, 4.2k to 14.7k input tokens for Qwen, the longest about a
30-minute meeting. Same gold, renumbered. Claude 3 runs, Qwen3-30B 1 run (deterministic; the server ran with
`-c 32768`, the app's notes track uses 8192).

## 3. Results

### 3.1 Whole corpus (median of 3 runs)

| Metric | Claude v1 | Qwen30B v1 | Qwen4B v1 | Claude v2 | Qwen30B v2 | Qwen4B v2 |
|---|---|---|---|---|---|---|
| Precision (after guard) | 1.00 | 0.94 | 0.94 | 1.00 | 0.93 | 0.95 |
| Recall | 1.00 | 0.82 | 0.87 | 1.00 | 0.95 | 0.90 |
| F1 | 1.00 | 0.88 | 0.91 | 1.00 | 0.94 | 0.92 |
| Precision (raw) | 1.00 | 0.91 | 0.94 | 1.00 | 0.93 | 0.92 |
| Field accuracy (after guard / raw) | 1.000 / 1.000 | 0.960 / 0.944 | 0.899 / 0.862 | 0.995 / 0.995 | 0.946 / 0.931 | 0.907 / 0.881 |
| Every field right (after guard / raw) | 1.00 / 1.00 | 0.78 / 0.72 | 0.53 / 0.35 | 0.97 / 0.97 | 0.73 / 0.68 | 0.60 / 0.49 |
| Trap proposals | 0 | 1 | 1 | 0 | 2 | 2 |
| Quotes not in the transcript | 0 | 1 | 0 | 0 | 0 | 1 |
| Unsupported values removed by the guard | 0 | 3 | 3 | 1 | 3 | 2 |
| Wrong dates corrected by the guard | 0 | 5 | 7 | 0 | 3 | 7 |
| Seconds per meeting, median / max | 4.5 / 13.1 | 3.2 / 17.5 | 3.3 / 6.9 | 5.0 / 9.3 | 3.8 / 10.2 | 3.2 / 9.2 |

"Unsupported values" counts persons, addresses, numbers, dates and hours the guard removed; for Claude v2 it is the
one date of section 4.2. Every model copied the speaker label right in every matched proposal (the guard never had
to fix one).

### 3.2 Trap proposals (all 3 runs together)

| Trap kind (hits / traps × runs) | Claude v1 | Qwen30B v1 | Qwen4B v1 | Claude v2 | Qwen30B v2 | Qwen4B v2 |
|---|---|---|---|---|---|---|
| other_speaker | 0/48 | 3/48 | 0/48 | 0/48 | 3/48 | 0/48 |
| rejected | 0/33 | 0/33 | 0/33 | 0/33 | 0/33 | 0/33 |
| condition_failed | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 3/12 |
| vague | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 | 0/12 |
| withdrawn | 0/3 | 0/3 | 3/3 | 0/3 | 3/3 | 3/3 |
| hedge | 0/3 | 0/3 | 0/3 | 0/3 | 0/3 | 0/3 |

Other unmatched proposals: Qwen30B v1 and v2 each gave a duplicate in all 3 runs (section 4.5); Qwen4B v1 gave an
invalid type `condition` in all 3 runs.

### 3.3 Gold actions that were not found every time, or had a field wrong

Runs found / runs; field errors after the guard in brackets, with the number of runs. The 12 actions that all six
configurations found with every field right in every run are left out.

| Gold action | Claude v1 | Qwen30B v1 | Qwen4B v1 | Claude v2 | Qwen30B v2 | Qwen4B v2 |
|---|---|---|---|---|---|---|
| en01 a1 jira (due "next Friday") | 3/3 | 3/3 (due 3) | 3/3 | 3/3 | 3/3 (due 3) | 3/3 |
| en02 a2 calendar, conditional | 3/3 | **0/3** | 3/3 | 3/3 | 3/3 | 3/3 |
| en03 a1 jira, no date yet | 3/3 | **0/3** | 3/3 (condition 3) | 3/3 | 3/3 (condition 3) | 3/3 (condition 3) |
| pl01 a2 calendar "w przyszły wtorek" | 3/3 | 3/3 (date 3) | 3/3 (date 3) | 3/3 | 3/3 (date 3) | 3/3 (date 3) |
| pl02 a2 demo, conditional | 3/3 | **0/3** | 3/3 (participants 3) | 3/3 | **0/3** | 3/3 (participants 3) |
| pl03 a1 e-mail "wyślę ci je dziś wieczorem" | 3/3 | 3/3 | **0/3** | 3/3 | 3/3 | **0/3** |
| pl03 a2 jira, no deadline | 3/3 | 3/3 | 3/3 (condition 3) | 3/3 | 3/3 | 3/3 (condition 3) |
| pl04 a2 e-mail "do końca tygodnia" | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 (due 3) |
| pl04 a3 calendar "trzeciego grudnia" | 3/3 | 3/3 | 3/3 (participants 3) | 3/3 | 3/3 | 3/3 |
| pl05 a2 jira for Natalia, no deadline | 3/3 | 3/3 | 3/3 (condition 3) | 3/3 | 3/3 | 3/3 |
| pl06 a1 interview, participants | 3/3 | 3/3 (participants 3) | 3/3 (participants 3) | 3/3 | 3/3 (participants 3) | 3/3 (participants 3) |
| pl06 a2 confirmation e-mail, no deadline | 3/3 | 3/3 (due 3) | 3/3 (to_emails 3) | 3/3 | 3/3 | 3/3 |
| pl06 a3 second stage, conditional | 3/3 | **0/3** | **0/3** | 3/3 | **0/3** | 3/3 |
| pl07 a1 e-mail to "Iwona" (one microphone) | 3/3 | 3/3 | **0/3** | 3/3 | 3/3 | **0/3** |
| pl08 a1 report e-mail to "zarząd" | 3/3 | 3/3 | 3/3 (to 3) | 3/3 | 3/3 | 3/3 (to 3) |
| pl08 a3 meeting with "zespół mobilny" (self-corrected day) | 3/3 | 3/3 (participants 3) | 3/3 (date 3, participants 3) | 3/3 | 3/3 (participants 3) | 3/3 (date 3, participants 3) |
| pl09 a1 e-mail to the customer | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 (to 3) | 3/3 |
| pl09 a2 jira, order 88231 | 3/3 (assignee 1) | **0/3** | 3/3 | 3/3 | 3/3 | 3/3 (assignee 3) |
| pl09 a3 call "czwartek o szesnastej" | 3/3 | 3/3 | **0/3** | 3/3 | 3/3 | **0/3** |
| pl10 a1 invite Kamil to "środowe demo o piętnastej" | 3/3 | 3/3 | 3/3 (date 3, participants 3, time 3) | 3/3 | 3/3 (date 3, participants 3) | 3/3 (date 3, participants 3, time 3) |
| pl11 a1 jira reassigned Kuba → Ula | 3/3 | 3/3 | 3/3 (assignee 3) | 3/3 | 3/3 (assignee 3) | 3/3 (assignee 3, number 3) |
| pl11 a2 e-mail, deadline moved Monday → Tuesday | 3/3 | 3/3 (due 3) | 3/3 (due 3) | 3/3 | 3/3 (due 3) | 3/3 (due 3) |
| pl11 a4 "zgłoszę to jako błąd" (no tool named) | 3/3 | **0/3** | **0/3** | 3/3 | 3/3 | 3/3 |
| pl12 a1 calendar "o wpół do trzeciej" | 3/3 | 3/3 | 3/3 (time 3) | 3/3 | 3/3 | 1/3 (time 1) |
| pl12 a2 quote e-mail, 42 000 said in words | 3/3 | 3/3 | 3/3 (number 3) | 3/3 | 3/3 | 3/3 |
| pl12 a3 jira, conditional | 3/3 | **0/3** | 3/3 | 3/3 | 3/3 | 3/3 (assignee 2) |
| pl12 a4 "za dwa tygodnie w poniedziałek" | 3/3 | 3/3 (date 3) | 3/3 (date 3) | 3/3 (date 2) | 3/3 (date 3) | 3/3 (date 3) |

### 3.4 Length test (8 neutral lines after each utterance, prompt v2)

| Metric | Claude v2, 3 runs | Qwen30B v2, 1 run |
|---|---|---|
| Precision (after guard / raw) | 1.00 / 1.00 | 0.92 / 0.88 |
| Recall | 1.00 | 0.90 |
| Every field right (after guard / raw) | 0.92 / 0.95 | 0.74 / 0.66 |
| Trap proposals | 0 | 1 (withdrawn) |
| Quotes not in the transcript | 0 | 2 |
| Proposal made from a neutral line | 0 | 1 |
| Seconds per meeting, median / max | 6.1 / 11.5 | 9.0 / 31.3 |

Against the unpadded v2 run, Qwen30B lost 2 actions to paraphrased quotes (the guard dropped them) and the
"zgłoszę to jako błąd" ticket, found one conditional promise it had missed unpadded, and made one proposal from a
padding line. Claude lost nothing; its "after guard" score is lower than raw because the guard removed a correct hour
3 times (section 5).

### 3.5 Cost and tokens

Claude: about 47k (v1) / 57k (v2) input and 9k output tokens per corpus run, reported as USD 0.12–0.20 per run by the
CLI (the first run of a prompt pays the cache write; on a subscription this uses the plan's limit, not money). The
length test: 150k input tokens per run, USD 0.16–0.59. No CLI error and no unparsable answer in 144 Claude calls.
Local: about 37k input and 5k output tokens per corpus run; no unparsable answer in 208 local calls.

## 4. Error examples (all synthetic)

1. **Weekday arithmetic (local).** Meeting on Wednesday 2026-11-18, Marta: "Zrobię nam retro w przyszły wtorek o
   czternastej". Qwen3-30B answered `2026-11-23` (a Monday) in every run of both prompts, although the calendar in the
   prompt says "2026-11-24 Tuesday". On Wednesday 2026-11-25 "wyślę zarządowi raport w piątek" became `2026-11-29`
   (a Sunday). The guard put the only reading back (`2026-11-27`) or, for "w przyszły wtorek" (24 November or
   1 December), removed the date. Claude got every date in v1 right.
2. **A prompt rule that hurt (Claude v2).** "wpiszę nam przegląd budżetu za dwa tygodnie w poniedziałek" on Tuesday
   2026-11-24: v1 gave `2026-12-07` in 3/3 runs; v2, which added "a week later only when the speaker says so", gave
   `2026-12-14` in 2/3. The guard removed it. Dates are better resolved by code from the phrase than by any rule in
   the prompt.
3. **Conditional promises (local).** Qwen3-30B v1 skipped all four open conditions: "Jasne, jak tylko pani da znać,
   że budżet jest zatwierdzony, wyślę zaproszenie na demo", "If legal signs off by Wednesday, I'll schedule the
   kickoff for December first at ten", "Jeśli pierwszy etap pójdzie dobrze, umówię drugi etap z Leną", "jeśli testy
   w piątek nie przejdą to założę ticket na poprawki dla Weroniki". v2 found two of them. Qwen3-4B v1 found three but
   once typed one as `"type": "condition"`.
4. **Withdrawn promise.** pl11: "ankietę wyślę do wszystkich klientów w przyszłym tygodniu", two minutes later "to
   ankietę jednak wyśle dział obsługi nie ja skreślam to u siebie". Qwen3-30B v2 and both Qwen3-4B prompts still
   proposed the survey e-mail in every run.
5. **A detail changed later → duplicate with the old value (Qwen3-30B).** pl11: "dobra wyślę Beacie roadmapę w
   poniedziałek", later "aha to wyślę jej roadmapę we wtorek jak wróci". Qwen3-30B proposed two e-mails (Monday and
   Tuesday) even with v2's "one action per task" rule; the reassignment of the export ticket ("ticket na eksport dam
   Uli") kept the first assignee, Kuba, in v2.
6. **Another speaker's own promise (Qwen3-30B).** pl05, Natalia: "I ja przy okazji założę ticket na uzupełnienie
   dokumentacji tego endpointu" → a Jira ticket for the user, assigned to Natalia, in every run of both prompts. Code
   can see that the quote is not the user's line (decision 7's card label), but cannot tell a request the user
   accepted from someone else's commitment.
7. **Participants.** Interview with candidate Adam Kowal: both local models got the participants wrong in every run
   (Qwen3-30B invited only the colleague Piotr, not the candidate). "Umówię spotkanie z zespołem mobilnym": the local
   models left the participants empty; Claude listed the team.
8. **Length (Qwen3-30B).** In the padded pl05 it created a ticket "Przeciążenie zespołu" from a neutral line by
   another participant ("Ja bym tylko zwrócił uwagę, że część osób jest przeciążona…"). Two quotes were paraphrased
   ("za zakładam ticket…" for "okej to zakładam ticket…", and a sentence merged from two lines), so the guard dropped
   two real actions.
9. **Small model, missing obvious actions (Qwen3-4B).** "Jasne, wyślę ci je dziś wieczorem", "Iwona, wyślę ci je
   jutro rano" and "Dobrze, czwartek szesnasta, zadzwonię do pana" were never proposed; for "zaproś proszę Kamila na
   środowe demo o piętnastej" it got the date, the hour and the participant wrong.

## 5. What the guard showed

* **The quote check is cheap and strict.** Claude never failed it; the local models failed it 0–3 times per run,
  always by paraphrasing a real promise, so each drop cost recall rather than preventing an invented action. No model
  invented an action from nothing on the unpadded corpus.
* **Code resolves dates better than the models.** The guard corrected 3–7 wrong local dates per run. Ambiguous
  phrases ("w przyszły wtorek" on a Monday or Wednesday, "next Friday", "do końca tygodnia") have two readings; the
  guard removed the date instead of guessing, which is where a card would have to ask.
* **What it cannot catch:** a phrase that exists in the transcript but belongs to another action (Qwen took "na
  piątek" from the interview as the deadline of the confirmation e-mail), a wrong set of participants, a stale
  assignee or deadline after a later change, a missing condition, and whether the speaker of the quote committed for
  the user or for themselves.
* **Neighbourhood checks are fragile.** The hour check looks two lines around the quote. In the length test Claude
  quoted "Ok, wyślę mu zaproszenie" while the hour ("o piętnastej") was in the request nine lines earlier, and the
  guard removed a correct hour in all 3 runs. A design that asks the model for a source phrase per field (like
  `date_phrase`: `time_phrase`, the words naming each person) and checks each phrase would not depend on distance.

## 6. Limits of this spike

* **Synthetic and small:** 16 meetings, 39 actions, 37 traps, written by the same agent that wrote the prompt and the
  guard. Real meetings are longer, messier and have recognition errors this corpus only imitates. Claude reached the
  ceiling, so the corpus cannot rank Claude models against each other.
* **Prompt v2 is in-sample:** it was written after reading the v1 errors, so its local gains (recall 0.82 → 0.95) are
  an upper bound until measured on meetings it has not seen.
* **The length test is artificial:** neutral padding, not real topic changes. It shows sensitivity to length, not
  real-meeting quality.
* **Times:** the local models were loaded before the runs; in the app the first action job would also pay the
  `LLMLease` load. Claude times include the CLI start. One Mac (M4 Max) only.
* **Not measured:** Haiku, Opus, Fable; the speech models' real output; a separate pass vs. the same pass as the notes;
  meetings above the 8192-token context the local notes track uses (a 30-minute meeting was about 15k tokens here).

## 7. Options for the owner

Decision 4 already ties detection to the notes provider. The numbers suggest how far each provider can go; which
option to take, and what the cards look like, is the owner's call.

| Option | What it means | Supported by the data? |
|---|---|---|
| A. Local is enough | Prefilled cards from the built-in model | Not for fields: 22–27 % (30B) and 40–47 % (4B) of the actions found carry a wrong field after the guard, plus 1–2 trap proposals per corpus run |
| B. Claude only | Actions only when the user chose Claude for notes | Yes for quality (1.00/1.00, 0 traps, fields 0.97–1.00, also at length); leaves local-only users without actions |
| **C. Hybrid (recommended)** | Claude: prefilled, editable cards. Local 30B: proposals with type, quote, speaker and title; every field editable and marked as unchecked; dates from code; no graduation. Local 4B: no actions, or quote-only reminders | Matches what each model measured |

Whatever is chosen, these findings carry into the spec as design requirements, not decisions:

1. Dates are computed by code from the model's phrase (`date_phrase`), never taken from the model; an ambiguous phrase
   becomes a question on the card.
2. Every field value comes with its source phrase from the transcript, and the guard checks the phrase, not a window of
   lines.
3. The quote check (verbatim, one utterance) stays; the speaker shown on the card is the quote's line, not the model's
   claim.
4. A proposal whose quote is another speaker's line is flagged (decision 7); code cannot tell acceptance from someone
   else's commitment.
5. Later changes of the same task (deadline, assignee) and withdrawn promises are the main local weakness; merging
   duplicates by task in code is worth trying before any local graduation.
6. A gate like G before actions ship, with working values: recall ≥ 0.90, precision ≥ 0.95, 0 trap proposals,
   0 unsupported values after the guard, every field right ≥ 0.90, on this corpus **and** on a holdout written
   independently. Claude Sonnet passes on this corpus; Qwen3-30B fails "every field" and "0 traps".

## 8. Next steps (if the owner wants them)

1. A holdout corpus written by someone who has not seen the prompt (another agent), to remove the in-sample bias.
2. A count-only run on real meetings from the encrypted image, as `RealWholeNotesTests` does (owner-run; no text
   leaves the image).
3. Guard v2: per-field source phrases, code-only dates, duplicate merging by task; then re-measure the local 30B.
4. If the owner wants a cheaper Claude model: the same three runs on Haiku.
5. In-app timing: lease load of the 30B and whether detection shares the notes pass.

## Reproduce

```sh
python3 -I -m unittest discover scripts/actions-eval
llama-server -m ".../Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf" --host 127.0.0.1 --port 8091 -c 8192 -ngl 99
python3 -I scripts/actions-eval/run.py --provider llama --url http://127.0.0.1:8091 --prompt v1 --runs 3 --out <dir> --tag qwen30b-v1
python3 -I scripts/actions-eval/run.py --provider claude --model sonnet --prompt v1 --runs 3 --out <dir> --tag claude-sonnet-v1
#   ... the same with --prompt v2 (tags qwen30b-v2, claude-sonnet-v2), the 4B GGUF on another port (qwen4b-v1, -v2),
#   and the length test with --pad 8 (default tags claude-sonnet-v2-pad8 and llama-v2-pad8; server -c 32768)
python3 -I scripts/actions-eval/compare.py <dir>/claude-sonnet-v1 <dir>/qwen30b-v1 <dir>/qwen4b-v1 \
  <dir>/claude-sonnet-v2 <dir>/qwen30b-v2 <dir>/qwen4b-v2
```

The run folders of this measurement are not in the repository (run output); the tables above are `compare.py`'s
output, rounded.

import Foundation
import GRDB
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// An evaluation of the meeting pipeline on one real recording. Off unless `LINTEL_MEETING_EVAL_AUDIO` is set.
/// Only a `-c release` build gives comparable numbers (see `scripts/meeting-eval`).
///
///     LINTEL_MEETING_EVAL_AUDIO=meeting.wav LINTEL_MEETING_EVAL_OUT=/tmp/eval \
///     LINTEL_MEETING_EVAL_SPEECH_FOLDER=<Models>/speech/parakeet-ultra swift test -c release --filter MeetingEvalTests
///
/// Optional: `_NAME`, `_ENGINE` (`parakeet-ultra` | `whisper-large-v3-turbo`), `_LANGUAGE` (`pl` | `en`; Whisper
/// pins it, Parakeet gets it as a script hint, like the app), `_PARAKEET_HINT` (`0`: Parakeet without the hint, the
/// behaviour before issue #132), `_CODE_VERSION`, `_NOTES_MODEL` (a .gguf), `_DUMP_REJECTIONS` (`1`: also write
/// `<name>.notes-rejections.json` with the text of every refused point, and with `_NOTES_PIPELINE=whole` also
/// `<name>.notes-whole.json` with the answers and the lines the fact guard removed; the only files that hold notes
/// text besides the result), `_TRACK` (`system`: feed the WAV as the system audio, like a remote speaker, with no
/// microphone; default `mic`), the segmentation knobs of issue #135 (`_PRE_ROLL_MS`, `_POST_ROLL_MS`, `_VAD_ENTRY`,
/// `_VAD_EXIT_OFFSET`, `_VAD_MIN_SILENCE`, `_VAD_PADDING`; unset = the app's values; the run writes its counters
/// under `capture` in the result), `_DIARIZATION_FOLDER`, `_SPEAKER_NAMES` (a JSON of oracle names that replace "Mówca N" after diarization), `_ALLOW_DEBUG`. The WAV must be
/// 16 kHz mono. The transcript goes only into the JSON; the test prints numbers, never text.
///
/// **Speaker names (spec `2026-11-25-meeting-speaker-names`, step 1.5).** `_NAMES=1` (quote track, needs
/// `_NOTES_MODEL`) runs the names step of the notes job before the notes: the diarized transcript goes into a
/// temporary encrypted store and `MeetingSpeakerNames.refresh` names it with `SpeakerNamePass` on the notes model
/// (`SpeakerNamesEval`). The result gets `speakerNames` (keyed by the run's "Mówca N" labels, for `score.py`) and
/// `speakerNamesPass` (counts and the pass time); the notes read the `applied` names as labels, as in the app.
/// `_KNOWN_NAMES=<entry.json | JSON list>` gives the extractor and the resolver a participant list (a simulated
/// calendar; never sent to the model). `_SKIP_NOTES=1` stops after the names. With `_DUMP_REJECTIONS=1` the
/// names, the accepted evidence and the model's answers go to `<name>.names.json` (out folder only).
///
/// **Replay.** `LINTEL_MEETING_EVAL_TRANSCRIPT=<result.json>` (an `EvalResult` an earlier run wrote) replaces
/// `_AUDIO`: no recognition and no diarization, the saved `asr.segments` (with speakers) go straight into the
/// notes, so variants differ only in the notes code. `_CODE_VERSION` is the code of THIS run; the result's
/// `config.transcriptSource` names the replayed file.
///
/// **Provider track.** `LINTEL_MEETING_EVAL_NOTES_PIPELINE=whole` runs `WholeNotesPipeline` (the provider track)
/// instead of the quote track: with the Claude Code CLI (`_PROVIDER_MODEL`, default `sonnet`; the child gets only
/// `HOME`, `USER`, `LANG` and `CLAUDE_CONFIG_DIR`, so unset `CLAUDE_CONFIG_DIR` for the default account), or with
/// a `llama-server` on the loopback (`_LLAMA_URL`, `_LLAMA_BUDGET` input tokens, default 24000; variant W).
/// `_GENERATIONS` (default 1) repeats it; the first one is the result, the others are written beside it.
/// Both tracks write the notes as `<name>.notes.md` (`<name>.gN.notes.md` for generation N > 1).
@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["LINTEL_MEETING_EVAL_AUDIO"] != nil
            || ProcessInfo.processInfo.environment["LINTEL_MEETING_EVAL_TRANSCRIPT"] != nil))
struct MeetingEvalTests {
    private static let environment = ProcessInfo.processInfo.environment

    private static func value(_ key: String) -> String? {
        let value = environment["LINTEL_MEETING_EVAL_\(key)"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    private static func ms(_ value: Double) -> String { String(format: "%.1f", value) }

    private static func unloadAndWait(_ runtime: LlamaRuntime) async {
        await runtime.unload()
        for _ in 0..<100 where await runtime.isLoaded { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func evaluatesARealRecording() async throws {
        #if DEBUG
        if Self.value("ALLOW_DEBUG") == nil {
            Issue.record("Debug build: its timings and memory are not comparable. Run with `-c release`.")
            return
        }
        #endif
        let transcriptURL = Self.value("TRANSCRIPT").map { URL(filePath: $0) }
        let outDirectory = URL(filePath: try #require(Self.value("OUT")), directoryHint: .isDirectory)
        let codeVersion = Self.value("CODE_VERSION") ?? "unknown"
        var result: EvalResult
        var rows: [EvalResult.Segment]
        let name: String
        let clock = ContinuousClock()
        if let transcriptURL {
            // Replay: the transcript of an earlier run, no recognition.
            let saved = try JSONDecoder().decode(EvalResult.self, from: Data(contentsOf: transcriptURL))
            name = Self.value("NAME") ?? saved.recording
            result = saved
            result.recording = name
            result.notes = nil
            result.speakerNames = nil
            result.speakerNamesPass = nil
            result.config.codeVersion = codeVersion
            result.config.transcriptSource = transcriptURL.lastPathComponent
            rows = saved.asr.segments
            print(
                "MEETING-EVAL replay name=\(name) segments=\(rows.count) audioSeconds=\(Self.ms(saved.audioSeconds))"
                    + " source=\(transcriptURL.lastPathComponent)")
        } else {
            let audioURL = URL(filePath: try #require(Self.value("AUDIO")))
            name = Self.value("NAME") ?? audioURL.deletingPathExtension().lastPathComponent
            let engineID = Self.value("ENGINE") ?? "parakeet-ultra"
            let language = Self.value("LANGUAGE") ?? "pl"
            let speechFolder = URL(filePath: try #require(Self.value("SPEECH_FOLDER")), directoryHint: .isDirectory)

            let engine: any SpeechEngine
            switch engineID {
            case "parakeet-ultra":
                let hint: String? = Self.value("PARAKEET_HINT") == "0" ? nil : language
                engine = ParakeetEngine(language: { hint })
            case "whisper-large-v3-turbo": engine = WhisperKitEngine(language: { language })
            default:
                Issue.record("Unknown engine \(engineID)")
                return
            }

            let samples = try WAVFile.samples(from: Data(contentsOf: audioURL))
            let audioSeconds = Double(samples.count) / Double(AudioFormat.sampleRate)
            let source = try WAVFileAudioSource(url: audioURL)
            let asSystem = Self.value("TRACK") == "system"
            var limits = MeetingSessionLimits()
            if let value = Self.value("PRE_ROLL_MS").flatMap(Int.init) { limits.segmentPreRoll = .milliseconds(value) }
            if let value = Self.value("POST_ROLL_MS").flatMap(Int.init) {
                limits.segmentPostRoll = .milliseconds(value)
            }
            var chosen = MeetingVAD.tuning
            if let value = Self.value("VAD_ENTRY").flatMap(Float.init) { chosen.entryThreshold = value }
            if let value = Self.value("VAD_EXIT_OFFSET").flatMap(Float.init) { chosen.exitOffset = value }
            if let value = Self.value("VAD_MIN_SILENCE").flatMap(Double.init) { chosen.minSilence = value }
            if let value = Self.value("VAD_PADDING").flatMap(Double.init) { chosen.padding = value }
            let tuning = chosen
            limits.vadEntryThreshold = tuning.entryThreshold
            let counters = Mutex<CaptureCounters?>(nil)

            // Store and spool live in a temporary folder that is removed at the end; the audio never exists
            // outside the encrypted spool in it.
            let directory = try TemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory.url) }
            let plugin = directory.url.appending(path: "meetings")
            let keys = try testKeys()
            let store = try MeetingsStore.open(in: plugin, keys: keys)
            let vadFolder = speechFolder.appending(path: ModelCatalog.sileroVADPath)

            let session = MeetingSession(
                store: store, keys: keys, spool: SpoolStorage(pluginDirectory: plugin),
                mic: asSystem ? UnavailableAudioInput() : source, system: asSystem ? source : nil,
                makeVAD: { LazyVAD(modelFolder: vadFolder, tuning: tuning, recordsProbabilities: true) },
                engine: engine, modelID: engineID, modelFolder: speechFolder, lease: SpeechEngineLease(),
                sleepAssertion: RecordingSleepAssertion(), gate: MeetingSessionGate(), limits: limits,
                recordCounters: { value in counters.withLock { $0 = value } }, retriesMicrophone: !asSystem)

            let sampler = FootprintSampler()
            sampler.start()
            let began = clock.now
            _ = try await session.start()
            let outcome = await session.finish()
            let processing = clock.now - began
            let asrPeak = await sampler.stop()
            let processingSeconds =
                Double(processing.components.seconds) + Double(processing.components.attoseconds) / 1e18

            #expect(outcome.result == .ready, "The meeting did not end ready")
            let id = try #require(outcome.meetingID)
            let fetched: [(id: Int64, segment: EvalResult.Segment)] = try store.read { db in
                try Row.fetchAll(
                    db,
                    sql:
                        "SELECT id, channel, start_ms, end_ms, text FROM meeting_segment WHERE meeting_id = ? ORDER BY start_ms, id",
                    arguments: [id]
                ).map {
                    (
                        id: $0["id"],
                        segment: EvalResult.Segment(
                            track: $0["channel"], startMs: $0["start_ms"], endMs: $0["end_ms"], text: $0["text"])
                    )
                }
            }
            let segmentIDs = fetched.map(\.id)
            rows = fetched.map(\.segment)
            // `replayedSegments` counts the segments that waited in the spool (backlog or background queue) and were
            // transcribed after the meeting; `unfinishedSegments` are the ones still not transcribed.
            let deferred = outcome.replayedSegments + outcome.unfinishedSegments

            let asr = EvalResult.ASR(
                processingSeconds: processingSeconds, rtf: processingSeconds / audioSeconds, peakFootprintMB: asrPeak,
                deferredSegments: deferred, segments: rows)
            result = EvalResult(
                recording: name, audioSeconds: audioSeconds,
                config: .init(engine: engineID, language: language, codeVersion: codeVersion), asr: asr)
            result.capture = counters.withLock { $0 }
            if let capture = result.capture {
                let c = capture[asSystem ? .system : .mic]
                print(
                    "MEETING-EVAL capture track=\(asSystem ? "system" : "mic") sent=\(c.segmentsSent) text=\(c.textResults)"
                        + " empty=\(c.emptyResults) hardCuts=\(c.hardCuts) short=\(c.shortSegments)"
                        + " nearMissChunks=\(c.segmentingStats.nearMissChunks) padMs=\(c.segmentingStats.paddedSamples / 16)"
                )
            }
            print(
                "MEETING-EVAL asr name=\(name) audioSeconds=\(Self.ms(audioSeconds)) seconds=\(Self.ms(processingSeconds))"
                    + " rtf=\(String(format: "%.3f", asr.rtf)) peakMB=\(Self.ms(asrPeak)) segments=\(rows.count)"
                    + " deferred=\(deferred)")

            if let folder = Self.value("DIARIZATION_FOLDER") {
                let diarizer = FluidDiarizer(modelFolder: URL(filePath: folder, directoryHint: .isDirectory))
                let footprint = FootprintSampler()
                footprint.start()
                let started = clock.now
                let spans = try await diarizer.diarize(EvalArraySource(samples), maximumSamples: samples.count)
                let elapsed = clock.now - started
                await diarizer.release()
                let peak = await footprint.stop()
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let speakers = Set(spans.map(\.cluster)).count
                result.diarization = .init(seconds: seconds, peakFootprintMB: peak, speakers: speakers)
                // The same assignment the app makes after a meeting (`MeetingFinalizer`): labels "Ja", "Inni", "Mówca N".
                let refs = zip(segmentIDs, rows).map { id, row in
                    SegmentRef(
                        id: id, channel: AudioChannel(rawValue: row.track) ?? .mic, startMs: row.startMs,
                        endMs: row.endMs)
                }
                let plan = SpeakerAssigner.diarized(segments: refs, spans: [.mic: spans])
                for (index, id) in segmentIDs.enumerated() {
                    if let speaker = plan.assignments[id], plan.speakers.indices.contains(speaker) {
                        rows[index].speaker = plan.speakers[speaker].label
                    }
                }
                // Experiment only: replace "Mówca N" with oracle names (JSON `{"Mówca N": {"name": ...}}`). The names are
                // text, so they reach the notes pipeline input and nothing else (no trace, no printed output).
                if let path = Self.value("SPEAKER_NAMES") {
                    let mapping = try JSONDecoder().decode(
                        [String: OracleSpeakerName].self, from: Data(contentsOf: URL(filePath: path)))
                    var replaced = 0
                    for index in rows.indices {
                        if let label = rows[index].speaker, let name = mapping[label]?.name, !name.isEmpty {
                            rows[index].speaker = name
                            replaced += 1
                        }
                    }
                    print("MEETING-EVAL speaker-names replaced=\(replaced)")
                }
                result.asr.segments = rows
                print(
                    "MEETING-EVAL diarization seconds=\(Self.ms(seconds)) peakMB=\(Self.ms(peak)) speakers=\(speakers)")
            }

        }

        if Self.value("NOTES_PIPELINE") == "whole" {
            try await WholeNotesEval.run(result: &result, rows: rows, name: name, to: outDirectory)
        } else if let model = Self.value("NOTES_MODEL") {
            let modelURL = URL(filePath: model)
            var configuration = NotesPipeline.Configuration()
            configuration.chunkTokens = MeetingsSettings.defaultNotesChunkTokens
            configuration.reduceInputTokens = MeetingsSettings.defaultNotesReduceInputTokens
            let runtime = LlamaRuntime(contextLength: NotesModel.contextLength)
            let recorder = RecordingRuntime(runtime)
            // One lease for the names and the notes, as in the app: the notes find the model the names loaded warm.
            let lease = LLMLease()
            let notesModel = NotesModel(
                lease: lease, runtime: recorder, modelURL: modelURL, keepWarm: { .seconds(1) })
            let traceEvents = Mutex<[NotesTraceEvent]>([])
            let jobStarted = clock.now
            var notesRows = rows
            // `_NAMES=1`: the speaker names step of the notes job (step 1.5) before the notes, on the same model.
            if Self.value("NAMES") == "1" {
                let known = try Self.value("KNOWN_NAMES").map { try SpeakerNamesEval.knownNames(at: URL(filePath: $0)) }
                let namesLease = NotesLease(
                    model: notesModel, configuration: configuration, sleep: { try await Task.sleep(for: $0) },
                    onEvent: { _ in })
                let named: SpeakerNamesEval.Outcome
                do {
                    named = try await SpeakerNamesEval.run(
                        rows: rows, knownNames: known ?? [], selfName: "", generator: namesLease)
                } catch {
                    await Self.unloadAndWait(runtime)
                    throw error
                }
                result.speakerNames = named.names
                result.speakerNamesPass = named.trace
                notesRows = named.notesRows
                if let trace = named.trace { traceEvents.withLock { $0.append(.speakerNames(trace)) } }
                let applied = named.names.filter { $0.status == "applied" }.count
                let suggested = named.names.filter { $0.status == "suggested" }.count
                print(
                    "MEETING-EVAL names list=\(known?.count ?? 0) status=\(named.trace?.passStatus.rawValue ?? "none")"
                        + " ms=\(named.trace?.elapsedMs ?? 0) excerpts=\(named.trace?.excerpts ?? 0)"
                        + " dropped=\(named.trace?.droppedExcerpts ?? 0) answers=\(named.trace?.answers ?? 0)"
                        + " accepted=\(named.trace?.acceptedEvidence ?? 0) applied=\(applied) suggested=\(suggested)")
                for failure in recorder.namesFailures { print("MEETING-EVAL names-failure \(failure)") }
                if Self.value("DUMP_REJECTIONS") == "1" {
                    let url = try EvalResultWriter.write(
                        SpeakerNamesEval.Dump(
                            recording: name, knownNames: known?.count ?? 0, speakers: named.speakers,
                            accepted: named.accepted, answers: recorder.namesAnswers, excerpts: named.excerptsBlock),
                        to: outDirectory)
                    print("MEETING-EVAL wrote \(url.path)")
                }
            }
            // `_SKIP_NOTES=1`: names only (tuning runs); the result keeps no notes.
            if Self.value("SKIP_NOTES") == "1" {
                await Self.unloadAndWait(runtime)
                let written = try EvalResultWriter.write(result, to: outDirectory)
                print("MEETING-EVAL wrote \(written.path)")
                return
            }
            // `LINTEL_MEETING_EVAL_NO_VERIFIER=1`: a control run without the semantic verifier on the same build.
            let noVerifier = Self.value("NO_VERIFIER") == "1"
            print("MEETING-EVAL notes verifier=\(noVerifier ? "off" : "on")")
            let pipeline = NotesPipeline(
                model: notesModel, configuration: configuration,
                trace: { event in traceEvents.withLock { $0.append(event) } },
                verifier: noVerifier ? nil : { @Sendable runtime in LLMNotesVerifier(runtime: runtime) })
            let utterances = notesRows.map {
                NotesUtterance(startMs: $0.startMs, speaker: $0.speaker ?? "?", text: $0.text)
            }
            let footprint = FootprintSampler()
            footprint.start()
            let started = clock.now
            let notes: NotesResult
            do {
                // The length of the recording, as the app passes the meeting's length (the topic limit).
                notes = try await pipeline.run(
                    utterances: utterances, durationMs: Int((result.audioSeconds * 1000).rounded()))
            } catch {
                await Self.unloadAndWait(runtime)
                throw error
            }
            // The keep-warm timer would unload the model after the test (and the process) ended: ggml aborts
            // at exit while a Metal resource set is alive. Unload now and wait until it is really gone.
            await Self.unloadAndWait(runtime)
            let elapsed = clock.now - started
            let peak = await footprint.stop()
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            result.notes = .init(
                model: modelURL.lastPathComponent, seconds: seconds, peakFootprintMB: peak,
                status: notes.status.rawValue, chunkCount: notes.chunkCount, verifiedPoints: notes.verifiedPointCount,
                dropped: notes.droppedCount, failedChunks: notes.failedChunks.count, reduceFailed: notes.reduceFailed,
                markdown: notes.markdown ?? "")
            try EvalResultWriter.writeNotes(notes.markdown ?? "", named: name, generation: 1, to: outDirectory)
            let events = traceEvents.withLock { $0 }
            let balance = NotesTrace.balance(of: events)
            let traceURL = try EvalResultWriter.write(NotesTraceFile(recording: name, events: events), to: outDirectory)
            print(
                "MEETING-EVAL notes-trace events=\(events.count) verified=\(balance.verified)"
                    + " rendered=\(balance.rendered) notRendered=\(balance.notRendered)"
                    + " unexplained=\(balance.unexplained)")
            print("MEETING-EVAL wrote \(traceURL.path)")
            // Off unless asked for: the file holds transcript-derived text, so only numbers are printed.
            if let dump = try NotesRejectionReport.writeIfEnabled(
                Self.value("DUMP_REJECTIONS") == "1", recording: name, records: recorder.records,
                utterances: utterances, to: outDirectory)
            {
                print(
                    "MEETING-EVAL notes-rejections answers=\(dump.report.answers.count)"
                        + " points=\(dump.report.pointCount) rejected=\(dump.report.rejectedCount)")
                print("MEETING-EVAL wrote \(dump.url.path)")
            }
            let job = clock.now - jobStarted
            let jobSeconds = Double(job.components.seconds) + Double(job.components.attoseconds) / 1e18
            print("MEETING-EVAL job seconds=\(Self.ms(jobSeconds)) names=\(Self.value("NAMES") == "1" ? "on" : "off")")
            print(
                "MEETING-EVAL notes seconds=\(Self.ms(seconds)) peakMB=\(Self.ms(peak)) status=\(notes.status.rawValue)"
                    + " chunks=\(notes.chunkCount) points=\(notes.verifiedPointCount) dropped=\(notes.droppedCount)")
        }

        let written = try EvalResultWriter.write(result, to: outDirectory)
        print("MEETING-EVAL wrote \(written.path)")
    }
}

/// One entry of the oracle speaker-name file; only `name` is read.
private struct OracleSpeakerName: Decodable { let name: String? }

/// An in-memory source of Float chunks for the diarizer (the evaluation has no spool for it).
private final class EvalArraySource: AudioSampleSource {
    private let samples: [Float]
    private let position = Mutex(0)
    let sampleRate = 16_000
    var endState: AudioEndState? { position.withLock { $0 } >= samples.count ? .complete : nil }

    init(_ samples: [Float]) { self.samples = samples }

    func nextChunk() throws -> [Float]? {
        let range = position.withLock { position -> Range<Int> in
            let start = position
            position = min(samples.count, start + 32_000)
            return start..<position
        }
        return range.isEmpty ? nil : Array(samples[range])
    }
}

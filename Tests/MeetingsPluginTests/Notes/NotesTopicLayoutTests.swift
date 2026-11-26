import Foundation
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// The topic layout of the built-in track (spec `2026-11-25-meeting-notes-structure`, F4): REDUCE v7 answers with an
/// intro and `TOPIC: name | ids`, the guard checks the topics and their names, and the composer writes the shared
/// `NotesLayout`.
@Suite struct NotesTopicParserTests {
    @Test func theIntroTheTopicsAndTheSectionsAreRead() throws {
        let output = try #require(
            NotesParser.parseReduce(
                """
                INTRO: Zespół omówił budżet.
                Plan jest gotowy.
                TOPIC: Budżet marketingu | p1, p3
                p4
                - **TOPIC:** Oferta dla klienta | p5
                DECISIONS: p2
                TASKS: -
                QUESTIONS: p6
                """))
        #expect(output.summary == "Zespół omówił budżet. Plan jest gotowy.")
        #expect(
            output.topics == [
                .init(name: "Budżet marketingu", ids: ["p1", "p3", "p4"]),
                .init(name: "Oferta dla klienta", ids: ["p5"]),
            ])
        #expect(output.decisions == ["p2"] && output.tasks.isEmpty && output.questions == ["p6"])
    }

    @Test func theOldFormatIsOneTopicWithoutAName() throws {
        let output = try #require(
            NotesParser.parseReduce("SUMMARY: Krótko.\nDECISIONS: -\nTASKS: -\nFINDINGS: p2, p1\nQUESTIONS: -"))
        #expect(output.summary == "Krótko.")
        #expect(output.topics == [.init(name: nil, ids: ["p2", "p1"])])
    }

    @Test func aTopicWithoutTheBarTakesTheTextBeforeTheFirstIdAsItsName() throws {
        let output = try #require(
            NotesParser.parseReduce("TOPIC: Plakat i fanty p7, p9\nTOPIC: - | p2\nTOPIC: Puste | -"))
        #expect(output.topics == [.init(name: "Plakat i fanty", ids: ["p7", "p9"]), .init(name: nil, ids: ["p2"])])
    }

    @Test func theTopicMergeReadsTopicIdsOnly() {
        let merged = NotesParser.parseTopicMerge("Sure.\nTOPIC: Budżet | t1, t3, p4\nTOPIC: Inne sprawy | t2")
        #expect(merged == [.init(name: "Budżet", ids: ["t1", "t3"]), .init(name: "Inne sprawy", ids: ["t2"])])
        #expect(NotesParser.parseTopicMerge("I cannot help with that.") == nil)
    }

    @Test func theMergedTopicsCollectThePointsOfTheBatchTopicsTheyName() {
        let batches: [NotesReduceOutput.Topic] = [
            .init(name: "Budżet", ids: ["p1", "p2"]), .init(name: nil, ids: ["p9"]), .init(name: "Plakat", ids: ["p3"]),
            .init(name: "Budżet festynu", ids: ["p7", "p8"]), .init(name: "Fanty", ids: ["p10"]),
        ]
        let joined = NotesPipeline.joinedTopics(
            [.init(name: "Budżet festynu", ids: ["t1", "t3", "t1", "t9"]), .init(name: "Plakat", ids: ["t2"])],
            batchTopics: batches)
        #expect(
            joined == [
                .init(name: nil, ids: ["p9"]), .init(name: "Budżet festynu", ids: ["p1", "p2", "p7", "p8"]),
                .init(name: "Plakat", ids: ["p3"]), .init(name: "Fanty", ids: ["p10"]),
            ])
    }
}

@Suite struct NotesTopicGuardTests {
    let guardrail = NotesGuard(utterances: GuardFixtures.transcript())

    /// `count` summary points that share nothing (no near-duplicates), each in its own utterance.
    private func findings(_ count: Int) -> [NotesPoint] {
        (1...count).map { number in
            var point = GuardFixtures.point(
                "p\(number)", .summary, quote: "cytat\(number) słowo\(number) inne\(number)",
                text: "Ustalenie numer\(number) dotyczy tematu\(number).", time: number * 1000)
            point.utterance = number
            point.sentence = 0
            return point
        }
    }

    private func topic(_ name: String?, _ ids: String...) -> NotesReduceOutput.Topic { .init(name: name, ids: ids) }

    @Test func aPointStandsUnderItsFirstTopicAndOnlySummaryPointsAreTopics() {
        let points = findings(4) + [GuardFixtures.budget]
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(
                topics: [
                    topic("Ustalenie numer1", "p1", "p2", "p1"), topic("Ustalenie numer3", "p3", "p2", "p1", "p99"),
                ]),
            points: points, durationMs: 3_600_000)
        #expect(audited.verdict.topics.map(\.name) == ["Ustalenie numer1", "Ustalenie numer3"])
        #expect(audited.verdict.topics.map { $0.points.map(\.id) } == [["p1", "p2"], ["p3"]])
        #expect(audited.audit.repeatedIDs == 3)
        #expect(audited.audit.misfiled["p1"] == nil)
        #expect(audited.audit.unknownIDs == 1)
        // The decision REDUCE forgot is added back to its section, never to a topic.
        #expect(audited.verdict.decisions.map(\.id) == ["p1"])
    }

    @Test func aDecisionUnderATopicIsRejectedAsMisfiled() {
        var decision = GuardFixtures.budget
        decision.id = "p9"
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(decisions: ["p9"], topics: [topic("Ustalenie numer1", "p1", "p9")]),
            points: findings(1) + [decision], durationMs: 3_600_000)
        #expect(audited.verdict.topics.flatMap(\.points).map(\.id) == ["p1"])
        #expect(audited.audit.misfiled["p9"] == [.summary])
        #expect(audited.verdict.rejectedIDs == 1)
    }

    @Test(arguments: [
        "Kowalski i ustalenie numer1", "Ustalenie numer1 za 50 procent", "Ustalenie numer1 w piątek",
        "Ustalenie numer1 nie dotyczy tematu1", "Budget numer1 and topic1",
        "Ustalenie numer1 dotyczy tematu1 i jeszcze kilku innych spraw zespołu",
    ])
    func aNameTheTopicsPointsDoNotBackSendsThePointsToOther(name: String) {
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic(name, "p1", "p2"), topic("Ustalenie numer3", "p3", "p4")]),
            points: findings(4), durationMs: 3_600_000)
        #expect(audited.audit.topicNameRefused == 1, "\(name)")
        #expect(audited.verdict.topics.map(\.name) == ["Ustalenie numer3", nil])
        #expect(audited.verdict.topics.last?.isOther == true)
        #expect(audited.verdict.topics.last?.points.map(\.id) == ["p1", "p2"])
    }

    @Test func aNameIsCheckedAgainstItsOwnTopicOnly() {
        // "numer3" is a word of another topic's point: it does not back this name.
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic("Ustalenie 3", "p1", "p2"), topic("Ustalenie numer3", "p3", "p4")]),
            points: findings(4), durationMs: 3_600_000)
        #expect(audited.audit.topicNameRefused == 1)
        let named = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic("„Ustalenie numer1”:", "p1", "p2")]), points: findings(2),
            durationMs: 3_600_000)
        #expect(named.verdict.topics.map(\.name) == ["Ustalenie numer1"])
    }

    @Test func theFirstWordOfANameIsCheckedLikeTheFirstWordOfAPointsText() {
        // "Ustalenia" is capitalised for being first and shares its stem with the points' "Ustalenie".
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic("Ustalenia i tematy", "p1", "p2")]), points: findings(2),
            durationMs: 3_600_000)
        #expect(audited.audit.topicNameRefused == 0)
        #expect(audited.verdict.topics.map(\.name) == ["Ustalenia i tematy"])
        // A first word the points do not back is still refused.
        let refused = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic("Kampania i ustalenie", "p1", "p2")]), points: findings(2),
            durationMs: 3_600_000)
        #expect(refused.audit.topicNameRefused == 1)
    }

    @Test(
        arguments: [
            // Only the first word is refused: the rest is the name when it starts with a word of the points.
            ("Kampania ustalenia tematu1", "Ustalenia tematu1"),
            // The rest would start with a short word or a word the points do not have: refused.
            ("Kampania i ustalenie", nil), ("Kampania Kowalskiego", nil), ("Kampania budżetu", nil),
            // A one-word name has no rest; a name refused for something else is not shortened.
            ("Kampania", nil), ("Ustalenie Kowalskiego", nil),
        ] as [(String, String?)])
    func aNameRefusedForItsFirstWordAloneKeepsTheRest(name: String, shown: String?) {
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [topic(name, "p1", "p2")]), points: findings(2), durationMs: 3_600_000)
        #expect(audited.verdict.topics.compactMap(\.name) == (shown.map { [$0] } ?? []))
        #expect(audited.audit.topicNameRefused == (shown == nil ? 1 : 0))
    }

    @Test func theTopicLimitFollowsTheLengthOfTheMeetingAndATopicHoldsSixPoints() {
        let points = findings(24)
        let topics = (0..<6).map { index in
            NotesReduceOutput.Topic(name: "Ustalenie numer\(index * 4 + 1)", ids: (1...4).map { "p\(index * 4 + $0)" })
        }
        // 30 minutes: five topics; the sixth topic's points are cut.
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: topics), points: points, durationMs: 30 * 60_000)
        #expect(audited.verdict.topics.count == 5)
        #expect(audited.audit.findingsOverLimit == ["p21", "p22", "p23", "p24"])
        // One topic of eight points keeps the first six.
        let long = guardrail.auditedVerifyReduce(
            NotesReduceOutput(topics: [.init(name: "Ustalenie numer1", ids: (1...8).map { "p\($0)" })]),
            points: points, durationMs: 30 * 60_000)
        #expect(long.verdict.topics.first?.points.map(\.id) == (1...6).map { "p\($0)" })
        #expect(long.audit.findingsOverLimit == ["p7", "p8"])
        // Without a length the guard takes the last utterance plus a minute: a short meeting, two topics.
        #expect(guardrail.verifyReduce(NotesReduceOutput(topics: topics), points: points).topics.count == 2)
    }

    @Test func findingsWithoutANameAreOneTopicWhereTheFirstOfThemStood() {
        let verdict = guardrail.verifyReduce(
            NotesReduceOutput(
                topics: [
                    topic("Ustalenie numer1", "p1", "p2"), topic(nil, "p3"), topic("Ustalenie numer4", "p4", "p5"),
                    topic(nil, "p6"),
                ]), points: findings(6), durationMs: 3_600_000)
        #expect(verdict.topics.map(\.name) == ["Ustalenie numer1", nil, "Ustalenie numer4"])
        #expect(verdict.topics[1].points.map(\.id) == ["p3", "p6"])
    }

    @Test func theIntroIsCutToItsFirstThreeSentencesAndSeventyWords() {
        let sentences = [
            "Spotkanie dotyczyło budżetu na przyszły kwartał.", "Marek wyśle ofertę do klienta w piątek.",
            "Ewa przygotuje umowę.", "Kto zajmie się fakturami od dostawcy?",
        ]
        let audited = guardrail.auditedVerifyReduce(
            NotesReduceOutput(decisions: ["p1"], summary: sentences.joined(separator: " ")),
            points: GuardFixtures.verified)
        #expect(audited.verdict.summary == sentences.prefix(3).joined(separator: " "))
        #expect(audited.audit.summaryOrigin == .model)
        #expect(!audited.verdict.summaryReplaced)

        let wordy = Array(repeating: "budżetu", count: 40).joined(separator: " ")
        #expect(
            NotesGuard.introPrefix(of: "Spotkanie dotyczyło \(wordy). Drugie \(wordy).")
                == "Spotkanie dotyczyło \(wordy).")
        let refused = guardrail.auditedVerifyReduce(
            NotesReduceOutput(
                summary: "Spotkanie " + Array(repeating: "budżetu", count: 75).joined(separator: " ") + "."),
            points: GuardFixtures.verified)
        #expect(refused.verdict.summary == nil)
        #expect(refused.verdict.summaryReplaced)
        #expect(refused.audit.summaryRefusal == .tooManyWords)
    }
}

@Suite struct NotesTopicComposerTests {
    private func point(_ id: String, _ kind: NotesPointKind, _ text: String) -> NotesPoint {
        NotesPoint(id: id, kind: kind, timeMs: 0, quote: "q", text: text)
    }

    private var verdict: NotesGuard.ReduceVerdict {
        NotesGuard.ReduceVerdict(
            decisions: [point("d1", .decision, "Zwykłe paczki idą przez nowego kuriera.")],
            tasks: [
                NotesPoint(
                    id: "t1", kind: .task, timeMs: 0, quote: "q", text: "[ ] Ustawić nowego kuriera [12:30]",
                    person: "Julia", due: "piątek"),
                point("t2", .task, "Poprosić o zwrot za październik."),
            ],
            questions: [], summary: "Zespół omówił przejście na nowego kuriera.", summaryReplaced: false,
            rejectedIDs: 0,
            topics: [
                .init(
                    name: "Opóźnienia dostaw",
                    points: [
                        point("p1", .summary, "Paczki docierają po pięciu dniach."),
                        point("p2", .summary, "Kurier jest droższy."),
                    ]),
                .init(
                    name: "Paczki zagraniczne",
                    points: [point("p3", .summary, "Obecny kurier obsługuje je bez opóźnień.")]),
                .init(
                    name: nil,
                    points: [
                        point("p4", .summary, "Magazyn pracuje do szesnastej."),
                        point("p5", .summary, "Zwroty idą osobno."),
                    ]),
                .init(name: nil, points: [point("p6", .summary, "Klienci pytają o śledzenie.")], isOther: true),
            ])
    }

    @Test func aLongMeetingHasTheIntroTheTopicsAndTheSectionsInOrder() {
        let markdown = NotesComposer.markdown(
            verdict: verdict, participants: ["Hanna", "Mówca 2"], labels: .polish, durationMs: 30 * 60_000)
        let expected = """
            Zespół omówił przejście na nowego kuriera.

            ### Opóźnienia dostaw

            - Paczki docierają po pięciu dniach.
            - Kurier jest droższy.

            ### Omówione tematy

            - Magazyn pracuje do szesnastej.
            - Zwroty idą osobno.

            ### Inne

            - Obecny kurier obsługuje je bez opóźnień.
            - Klienci pytają o śledzenie.

            ### Podjęte decyzje

            - Zwykłe paczki idą przez nowego kuriera.

            ### Następne kroki

            - [ ] Ustawić nowego kuriera — osoba\\: Julia, termin\\: piątek
            - [ ] Poprosić o zwrot za październik.

            ### Uczestnicy

            Hanna
            """
        #expect(markdown == expected)
        let shown = NotesComposer.shownKeyPoints(of: verdict, labels: .polish, durationMs: 30 * 60_000)
        #expect(shown.map { $0.points.map(\.id) } == [["p1", "p2"], ["p4", "p5"], ["p3", "p6"]])
    }

    @Test func otherAloneGetsTheCodesHeading() {
        let singles = NotesGuard.ReduceVerdict(
            decisions: [], tasks: [], questions: [], summary: nil, summaryReplaced: false, rejectedIDs: 0,
            topics: (1...7).map { .init(name: "Temat \($0)", points: [point("p\($0)", .summary, "Punkt \($0).")]) })
        let markdown = NotesComposer.markdown(
            verdict: singles, participants: [], labels: .polish, durationMs: 30 * 60_000)
        #expect(markdown.hasPrefix("### Omówione tematy\n\n- Punkt 1.\n"))
        #expect(!markdown.contains("### Inne") && !markdown.contains("Punkt 7."))
        let shown = NotesComposer.shownKeyPoints(of: singles, labels: .polish, durationMs: 30 * 60_000)
        #expect(shown.map(\.name) == ["Omówione tematy"] && shown[0].points.count == 6 && !shown[0].isOther)
    }

    @Test func aShortMeetingIsOneListWithoutTopicHeadings() {
        let markdown = NotesComposer.markdown(
            verdict: verdict, participants: [], labels: .english, durationMs: 4 * 60_000)
        #expect(!markdown.contains("### Opóźnienia dostaw") && !markdown.contains("### Topics discussed"))
        #expect(!markdown.contains("### Other"))
        let lines = markdown.split(separator: "\n").map(String.init)
        #expect(lines.first == "Zespół omówił przejście na nowego kuriera.")
        #expect(lines.prefix { !$0.hasPrefix("#") }.filter { $0.hasPrefix("- ") }.count == 6)
        #expect(markdown.contains("### Decisions") && markdown.contains("### Next steps"))
        #expect(markdown.contains("owner\\: Julia, due\\: piątek"))
    }
}

@Suite struct NotesTopicPipelineTests {
    /// Twelve findings over half an hour, one every two and a half minutes.
    static let lines = [
        "Kampania w telewizji kosztowała więcej niż zakładaliśmy",
        "Klienci chwalą nową aplikację mobilną",
        "Konkurencja obniżyła ceny w zeszłym miesiącu",
        "Zespół sprzedaży potrzebuje dwóch nowych osób",
        "Serwer produkcyjny działał stabilnie przez cały kwartał",
        "Magazyn w Poznaniu zamyka się o szesnastej",
        "Dostawca opakowań podniósł stawki od stycznia",
        "Dział kadr szuka nowego biura na parterze",
        "Raport kwartalny trafi do zarządu jutro rano",
        "Szkolenie dla handlowców przeniesiono na wiosnę",
        "Nowa strona internetowa ładuje się szybciej",
        "Faktury od przewoźnika przychodzą z opóźnieniem",
    ]

    static func utterances() -> [NotesUtterance] {
        lines.enumerated().map {
            NotesUtterance(startMs: $0.offset * 150_000, speaker: "Anna", text: $0.element + ".")
        }
    }

    static func mapAll(_ messages: [ChatMessage]) -> String {
        NotesFake.transcriptLines(messages).map { "SUM | \($0.time) | \"\($0.text.dropLast())\" | \($0.text)" }
            .joined(separator: "\n")
    }

    @Test func theTraceCountsTheTopicsTheRefusedNameAndTheFindingsLeftOut() async throws {
        let log = NotesTraceLog()
        let rig = NotesRig { _, messages, _ in
            if NotesFake.isMap(messages) { return .done(Self.mapAll(messages)) }
            if NotesFake.isReduce(messages) {
                return .done(
                    """
                    INTRO: Zespół omówił sprawy firmy.
                    TOPIC: Kampania i klienci | p1, p2, p3
                    TOPIC: Kowalski i zespół | p4, p5
                    TOPIC: Magazyn | p6
                    TOPIC: Dostawca i kadry | p7, p8
                    DECISIONS: -
                    TASKS: -
                    QUESTIONS: -
                    """)
            }
            return .done(NotesFake.answer(messages))
        }
        let pipeline = NotesPipeline(
            model: rig.model, configuration: .init(), trace: { log.add($0) }, verifier: nil)
        let result = try await pipeline.run(utterances: Self.utterances(), durationMs: 30 * 60_000)
        let markdown = try #require(result.markdown)
        #expect(markdown.hasPrefix("Zespół omówił sprawy firmy.\n\n### Kampania i klienci\n"))
        #expect(markdown.contains("### Dostawca i kadry") && markdown.contains("### Inne"))
        #expect(!markdown.contains("Kowalski") && !markdown.contains("### Magazyn"))
        #expect(result.keyPoints.map(\.id) == ["p1", "p2", "p3", "p7", "p8", "p6", "p4", "p5"])
        let layout = try #require(log.reduce?.layout)
        #expect(
            layout
                == NotesTraceLayout(
                    topics: 3, pointsPerTopic: [3, 2, 3], topicNameRefused: 1, notChosen: 4, cutByLimit: 0))
        #expect(log.reduce?.keyPoints == 8)
        #expect(log.balance.isBalanced)
        #expect(log.balance.rendered == 8 && log.balance.unexplained == 0)
    }

    @Test func topicsOfSeveralBatchesAreMergedByNameAndTheTraceRecordsTheRequest() async throws {
        let log = NotesTraceLog()
        let rig = NotesRig { _, messages, _ in
            if NotesFake.isMap(messages) { return .done(Self.mapAll(messages)) }
            if NotesFake.isTopics(messages) {
                // The first batch topic takes the rest along; the reply also tries an id that is no topic.
                let count = NotesFake.lastUser(messages).split(separator: "\n").count - 2
                return .done(
                    "TOPIC: Kampania i sprawy | " + (1...count).map { "t\($0)" }.joined(separator: ", ") + ", t99")
            }
            if NotesFake.isReduce(messages) { return .done(NotesFake.reduceAnswer(messages)) }
            return .done(NotesFake.answer(messages))
        }
        var configuration = NotesPipeline.Configuration()
        configuration.reduceInputTokens = 60
        let pipeline = NotesPipeline(
            model: rig.model, configuration: configuration, trace: { log.add($0) }, verifier: nil)
        let result = try await pipeline.run(utterances: Self.utterances(), durationMs: 30 * 60_000)
        #expect(log.reduce?.batches ?? 0 > 1)
        #expect(log.requests.contains { $0.stage == .topics && $0.outcome == .value })
        let markdown = try #require(result.markdown)
        #expect(markdown.contains("### Kampania i sprawy"))
        // One topic shows at most six points.
        #expect(result.keyPoints.count == NotesLayout.maxPointsPerTopic)
        #expect(log.reduce?.layout?.cutByLimit == Self.lines.count - NotesLayout.maxPointsPerTopic)
        #expect(log.balance.isBalanced)
    }

    @Test func anAnswerInTheOldFormatStillMakesNotesWithTheCodesHeading() async throws {
        let rig = NotesRig { _, messages, _ in
            if NotesFake.isMap(messages) { return .done(Self.mapAll(messages)) }
            if NotesFake.isReduce(messages) { return .done(NotesFake.reduceAnswer(messages, oldFormat: true)) }
            return .done(NotesFake.answer(messages))
        }
        let result = try await rig.pipeline().run(utterances: Self.utterances(), durationMs: 30 * 60_000)
        let markdown = try #require(result.markdown)
        #expect(markdown.contains("### Omówione tematy"))
        #expect(result.keyPoints.count == NotesLayout.maxPointsPerTopic)
        #expect(result.status == .ok)
    }

    @Test func theReduceRequestCarriesTheTopicLimitOfTheMeeting() async throws {
        let rig = NotesRig(NotesFake.standard)
        _ = try await rig.pipeline().run(utterances: Self.utterances(), durationMs: 55 * 60_000)
        let reduce = try #require(rig.llm.calls.first { NotesFake.isReduce($0.messages) })
        #expect(reduce.messages.first?.content == NotesPrompt.reduceSystem(maxTopics: 9))
        let rig2 = NotesRig(NotesFake.standard)
        // A length that is not saved (0) falls back to the transcript: about half an hour, five topics.
        _ = try await rig2.pipeline().run(utterances: Self.utterances(), durationMs: 0)
        let fallback = try #require(rig2.llm.calls.first { NotesFake.isReduce($0.messages) })
        #expect(fallback.messages.first?.content == NotesPrompt.reduceSystem(maxTopics: 4))
    }
}

import Foundation
import Synchronization
import Testing

@testable import DictationPlugin
@testable import LintelSpeech

/// A formatter driven by a closure, for the session and controller tests.
struct StubFormatter: TextFormatter {
    let body: @Sendable (String, String?) async throws -> FormatResult

    init(_ body: @escaping @Sendable (String, String?) async throws -> FormatResult) {
        self.body = body
    }

    func format(chunk: String, previousContext: String?) async throws -> FormatResult {
        try await body(chunk, previousContext)
    }
}

/// Answers `LocalLLMFormatter` from a script and records the requests.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    enum Answer {
        case content(String)
        case raw(String, status: Int)
        case failure(URLError.Code)
    }

    private let answers: Mutex<[Answer]>
    private let seen = Mutex<[URLRequest]>([])

    init(_ answers: Answer...) { self.answers = Mutex(answers) }

    var requests: [URLRequest] { seen.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        seen.withLock { $0.append(request) }
        let answer = answers.withLock { $0.count > 1 ? $0.removeFirst() : ($0.first ?? .failure(.badServerResponse)) }
        let url = request.url ?? URL(fileURLWithPath: "/")
        switch answer {
        case .content(let text):
            let body = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text]]]])
            return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case .raw(let body, let status):
            return (
                Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        case .failure(let code):
            throw URLError(code)
        }
    }
}

@Suite struct FormatterGuardTests {
    private let input = "yyy no więc jutro mamy spotkanie o dziesiątej w biurze i to jest ważne"

    @Test func acceptsACleanedVersion() {
        let output = "Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func stripsThinkingBlocks() {
        let output = "<think>Let me clean this up.</think>\nJutro mamy spotkanie o dziesiątej w biurze i to jest ważne."
        #expect(
            FormatterGuard.check(input: input, output: output)
                == .accepted("Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."))
        #expect(FormatterGuard.clean("</think>Tekst") == "Tekst")
        #expect(FormatterGuard.clean("Tekst<think>never closed") == "Tekst")
    }

    @Test func emptyAfterThinkingIsRejected() {
        #expect(FormatterGuard.check(input: input, output: "<think>hmm</think>") == .rejected(.empty))
        #expect(FormatterGuard.check(input: input, output: "   ") == .rejected(.empty))
    }

    @Test func tooLongIsRejected() {
        let output = Array(repeating: "jutro mamy spotkanie o dziesiątej w biurze", count: 4).joined(separator: " ")
        #expect(FormatterGuard.check(input: input, output: output) == .rejected(.tooLong))
    }

    @Test func tooShortIsRejected() {
        #expect(FormatterGuard.check(input: input, output: "Jutro spotkanie.") == .rejected(.tooShort))
    }

    @Test func aChangedLanguageIsRejected() {
        let output = "Tomorrow we have the meeting at ten in the office and it is important"
        #expect(FormatterGuard.check(input: input, output: output) == .rejected(.languageChanged))
    }

    @Test func answeringInsteadOfCleaningIsRejected() {
        let question = "um what is the capital of france I mean of poland please tell me"
        #expect(
            FormatterGuard.check(input: question, output: "Sure, the capital of Poland is Warsaw, of course.")
                == .rejected(.answered))
        #expect(
            FormatterGuard.check(input: question, output: "Here is the cleaned text: What is the capital of Poland?")
                == .rejected(.answered))
    }

    @Test func aShortChunkMayLoseAFillerWord() {
        #expect(FormatterGuard.check(input: "yyy tak", output: "Tak.") == .accepted("Tak."))
    }

    // MARK: Fidelity (CleanupPrompt v2)

    @Test(
        "A number the transcript does not hold is rejected",
        arguments: [
            (
                "w raporcie jest 6 cali deszczu i dużo wiatru dzisiaj",
                "W raporcie jest 60 mm deszczu i dużo wiatru dzisiaj."
            ),
            ("spotkanie jest o szesnastej w biurze na górze", "Spotkanie jest o 17 w biurze na górze."),
            ("zamówcie pizzę na 16 sorry na 17 i weźcie jedną", "Zamówcie pizzę na 18 i weźcie jedną."),
            (
                "the report from 1989 has the data on page one hundred nine",
                "The report from 1999 has the data on page 109."
            ),
        ])
    func aNewNumberIsRejected(input: String, output: String) {
        #expect(FormatterGuard.check(input: input, output: output) == .rejected(.newNumber))
    }

    @Test(
        "A number said in words or digits may be written as digits",
        arguments: [
            ("budżet to dwadzieścia tysięcy to znaczy dwadzieścia pięć tysięcy złotych", "Budżet to 25 000 złotych."),
            (
                "konferencja zaczyna się dwunastego marca dwa tysiące dwadzieścia siedem o dziewiątej piętnaście",
                "Konferencja zaczyna się 12 marca 2027 o 9:15."
            ),
            (
                "konwersja wzrosła z dwóch i pół procent do trzech koma osiem procent w tym roku",
                "Konwersja wzrosła z 2,5% do 3,8% w tym roku."
            ),
            (
                "mój numer telefonu to pięćset jeden dwieście trzydzieści cztery pięćset sześćdziesiąt siedem",
                "Mój numer telefonu to 501 234 567."
            ),
            (
                "the deadline is the twentieth sorry the twenty second of december",
                "The deadline is the 22nd of December."
            ),
            (
                "let's meet at half past ten tomorrow in the main office",
                "Let's meet at 10:30 tomorrow in the main office."
            ),
            (
                "na 16 sorry na 17 zamówcie pizzę i weźcie jedną wegetariańską",
                "Zamówcie pizzę na 17 i weźcie jedną wegetariańską."
            ),
        ])
    func aSpokenNumberMayBecomeDigits(input: String, output: String) {
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func lettersOfAnotherScriptAreRejected() {
        let input = "po drugie naprawić logowanie po trzecie napisać test dla płatności i dodać opis"
        let output = "Po drugie naprawić logowanie, po trzecie napишesz test dla płatności i dodać opis."
        #expect(FormatterGuard.check(input: input, output: output) == .rejected(.foreignScript))
        // The input's own script is fine, and so are Polish and Vietnamese letters.
        #expect(!FormatterGuard.introducesForeignScript(input: "Это тест", output: "Это тест."))
        #expect(!FormatterGuard.introducesForeignScript(input: "zażółć gęślą jaźń", output: "Zażółć gęślą jaźń."))
    }

    @Test func aDroppedDetailIsRejectedWhenNothingWasToBeRemoved() {
        let input = "teams need clear goals as shown by Larson and LaFasto 1989 page 109 and trust"
        #expect(
            FormatterGuard.check(input: input, output: "Teams need clear goals and trust.")
                == .rejected(.tooShort))
        // The same cut is fine when the speaker said something that may go.
        #expect(
            FormatterGuard.check(
                input: "um " + input, output: "Teams need clear goals as shown by Larson and LaFasto 1989 and trust.")
                == .accepted("Teams need clear goals as shown by Larson and LaFasto 1989 and trust."))
    }

    @Test func aSelfCorrectionMayShortenTheText() {
        let input = "let's meet on monday actually no let's do tuesday because monday is a holiday"
        let output = "Let's meet on Tuesday because Monday is a holiday."
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func aListIsNotLongerThanItsItems() {
        let input = "plan na sprint po pierwsze dokończyć eksport po drugie naprawić logowanie po trzecie napisać testy"
        let output = "Plan na sprint:\n1. Dokończyć eksport.\n2. Naprawić logowanie.\n3. Napisać testy."
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
        #expect(FormatterGuard.withoutListMarkers("Plan:\n- a b\n2) c\n  3. d - e") == "Plan:\na b\nc\nd - e")
    }

    @Test func removableContentIsFoundInBothLanguages() {
        for text in [
            "yyy jutro", "um tomorrow", "we should we should go", "to jest to jest ważne",
            "wyślij do Kasi nie czekaj do Magdy",
            "po pierwsze to", "ship it sorry ship them",
        ] {
            #expect(Removals.mayRemove(from: text), Comment(rawValue: text))
        }
        #expect(!Removals.mayRemove(from: "Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne"))
        #expect(!Removals.mayRemove(from: "Nie chodzi o to, że jest drogo, tylko o to, że nie mamy czasu"))
    }

    @Test func languageDetection() {
        #expect(Language.dominant(in: "to jest bardzo ważne i nie ma czasu na to") == .polish)
        #expect(Language.dominant(in: "this is the thing that we should have done") == .english)
        #expect(Language.dominant(in: "ok") == .unknown)
    }
}

@Suite struct LocalLLMFormatterTests {
    private let base = URL(string: "http://127.0.0.1:11434")!
    private let chunk = "yyy no więc jutro mamy spotkanie o dziesiątej w biurze i to jest ważne"

    private func formatter(_ transport: ScriptedTransport, configured: Bool = true) -> LocalLLMFormatter {
        LocalLLMFormatter(
            transport: transport, target: { [base] in configured ? .init(baseURL: base, model: "qwen") : nil })
    }

    @Test func aGoodAnswerIsUsed() async throws {
        let transport = ScriptedTransport(.content("Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(
            result == .init(text: "Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne.", outcome: .formatted))
    }

    @Test func thinkingIsRemoved() async throws {
        let transport = ScriptedTransport(
            .content("<think>x</think>Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result.outcome == .formatted)
        #expect(!result.text.contains("think"))
    }

    @Test(arguments: [
        ("Sure, here you go", FormatterGuard.Reason.answered),
        ("Jutro.", FormatterGuard.Reason.tooShort),
        ("Tomorrow we have the meeting at ten in the office and it is important", .languageChanged),
        (String(repeating: "jutro mamy spotkanie w biurze ", count: 5), .tooLong),
        ("<think>only thoughts</think>", .empty),
    ])
    func aBadAnswerFallsBackToTheRawChunk(answer: String, reason: FormatterGuard.Reason) async throws {
        let transport = ScriptedTransport(.content(answer))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result == .init(text: chunk, outcome: .fellBack(.rejected(reason))))
    }

    @Test func aTimeoutFallsBackToRaw() async throws {
        let transport = ScriptedTransport(.failure(.timedOut))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result == .init(text: chunk, outcome: .fellBack(.unreachable)))
        #expect(transport.requests.count == 1)
    }

    @Test func anHTTPErrorFallsBackToRaw() async throws {
        let transport = ScriptedTransport(.raw("{}", status: 500))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result == .init(text: chunk, outcome: .fellBack(.unreachable)))
    }

    @Test func aConnectionErrorIsRetriedOnce() async throws {
        let transport = ScriptedTransport(
            .failure(.cannotConnectToHost),
            .content("Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result.outcome == .formatted)
        #expect(transport.requests.count == 2)

        let down = ScriptedTransport(.failure(.cannotConnectToHost))
        let failed = try await formatter(down).format(chunk: chunk, previousContext: nil)
        #expect(failed.outcome == .fellBack(.unreachable))
        #expect(down.requests.count == 2)
    }

    @Test func garbageIsABadResponse() async throws {
        let transport = ScriptedTransport(.raw("not json", status: 200))
        let result = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        #expect(result == .init(text: chunk, outcome: .fellBack(.badResponse)))
    }

    @Test func withoutAServerTheChunkStaysRaw() async throws {
        let transport = ScriptedTransport(.content("x"))
        let result = try await formatter(transport, configured: false).format(chunk: chunk, previousContext: nil)
        #expect(result == .init(text: chunk, outcome: .fellBack(.notConfigured)))
        #expect(transport.requests.isEmpty)
    }

    @Test func theRequestIsDeterministicAndNotStreamed() async throws {
        let transport = ScriptedTransport(.content("Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."))
        _ = try await formatter(transport).format(chunk: chunk, previousContext: "Poprzedni akapit.")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "qwen")
        #expect(body["temperature"] as? Int == 0)
        #expect(body["stream"] as? Bool == false)
        let words = FormatterGuard.words(in: chunk)
        #expect(body["max_tokens"] as? Int == words * 4 + 64)
        let kwargs = body["chat_template_kwargs"] as? [String: Bool]
        #expect(kwargs == ["enable_thinking": false])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "system")
        let last = try #require(messages.last?["content"])
        #expect(last.contains("<transcript>\(chunk)</transcript>"))
        #expect(last.contains("<context>Poprzedni akapit.</context>"))
        #expect(request.timeoutInterval == LocalLLMFormatter.timeout(forWords: words))
    }

    @Test func theTimeoutGrowsWithTheChunk() {
        #expect(LocalLLMFormatter.timeout(forWords: 60) == 17)
        #expect(LocalLLMFormatter.timeout(forWords: 0) == 5)
    }

    @Test func cancellationIsNotAFallback() async {
        let transport = ScriptedTransport(.failure(.cancelled))
        await #expect(throws: CancellationError.self) {
            _ = try await formatter(transport).format(chunk: chunk, previousContext: nil)
        }
    }
}

@Suite struct CleanupPromptTests {
    @Test func promptMatchesTheSnapshot() throws {
        let rendered =
            CleanupPrompt.messages(transcript: "TRANSCRIPT", context: "CONTEXT")
            .map { "[\($0.role)]\n\($0.content)" }.joined(separator: "\n\n") + "\n"
        if ProcessInfo.processInfo.environment["LINTEL_RECORD_SNAPSHOT"] != nil {
            let source = URL(filePath: #filePath).deletingLastPathComponent()
                .appending(path: "Fixtures/cleanup/prompt-v2.txt")
            try rendered.write(to: source, atomically: true, encoding: .utf8)
        }
        let url = try #require(Bundle.module.url(forResource: "Fixtures/cleanup/prompt-v2", withExtension: "txt"))
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(
            rendered == expected,
            "The cleanup prompt changed. Bump CleanupPrompt.version, update the snapshot and note it in the release notes."
        )
        #expect(CleanupPrompt.version == 2)
    }

    @Test func transcriptsAreDelimitedAndQuestionsAreExamples() {
        let messages = CleanupPrompt.messages(transcript: "co to jest", context: nil)
        #expect(messages.last?.content == "<transcript>co to jest</transcript>")
        #expect(messages.first?.content.contains("never a request") == true)
        #expect(CleanupPrompt.examples.contains { $0.output.hasSuffix("?") })
    }
}

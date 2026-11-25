import Foundation
import Testing

@testable import MeetingsPlugin

@Suite struct NotesLayoutTests {
    private func points(_ count: Int, _ prefix: String = "Punkt") -> [String] {
        (1...count).map { "\(prefix) numer \($0) został omówiony." }
    }

    private func topic(_ name: String?, _ count: Int) -> NotesLayout.Topic {
        .init(name: name, points: points(count, name ?? "Bez nazwy"))
    }

    private func render(_ layout: NotesLayout, durationMs: Int? = 30 * 60_000, title: String? = nil) -> String {
        NotesLayoutComposer.markdown(layout: layout, title: title, durationMs: durationMs, labels: .polish)
    }

    // MARK: Length rules

    @Test func theMeetingLengthDecidesTheMostTopics() {
        let table: [(minutes: Int, topics: Int)] = [
            (0, 2), (5, 2), (11, 2), (12, 2), (18, 3), (24, 4), (30, 5), (38, 6), (55, 9), (59, 9), (60, 10),
            (180, 10),
        ]
        for (minutes, topics) in table {
            #expect(NotesLayout.maxTopics(durationMs: minutes * 60_000) == topics, "\(minutes) min")
        }
        #expect(NotesLayout.maxTopics(durationMs: -5) == 2)
    }

    @Test func aShortMeetingIsOneListWithoutTopicHeadings() {
        var layout = NotesLayout(intro: "Krótkie spotkanie o budżecie.")
        layout.topics = [topic("Budżet", 2), topic("Termin", 3)]
        layout.decisions = ["Budżet zostaje bez zmian."]
        // Under ten minutes, however many points there are.
        #expect(layout.isShortMeeting(durationMs: 9 * 60_000 + 59_000))
        // Fewer than six points, however long the meeting is.
        layout.topics = [topic("Budżet", 2), topic("Termin", 3)]
        #expect(layout.isShortMeeting(durationMs: 60 * 60_000))
        let markdown = render(layout, durationMs: 60 * 60_000)
        #expect(markdown.contains("- Budżet numer 1"))
        #expect(!markdown.contains("Budżet\n") && !markdown.contains("Termin\n"))
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("#") }
        #expect(headings.count == 1 && headings[0].contains("Podjęte decyzje"))
        // Six points in a meeting of ten minutes or more: topics are shown.
        layout.topics = [topic("Budżet", 3), topic("Termin", 3)]
        #expect(!layout.isShortMeeting(durationMs: 10 * 60_000))
        #expect(render(layout, durationMs: 10 * 60_000).contains("Budżet\n"))
        #expect(layout.isShortMeeting(durationMs: nil) == false)
    }

    @Test func topicsWithOnePointJoinTheClosingOtherTopic() {
        var layout = NotesLayout()
        layout.topics = [topic("Pierwszy", 3), topic("Drugi", 1), topic("Trzeci", 2), topic("Czwarty", 1)]
        let shown = layout.shownTopics(durationMs: 40 * 60_000)
        #expect(shown.map(\.name) == ["Pierwszy", "Trzeci", nil])
        #expect(shown.last?.isOther == true)
        #expect(shown.last?.points.count == 2)
        let markdown = render(layout, durationMs: 40 * 60_000)
        #expect(markdown.contains("Inne\n"))
        #expect(!markdown.contains("Drugi\n") && !markdown.contains("Czwarty\n"))
        #expect(
            NotesLayoutComposer.markdown(layout: layout, durationMs: 40 * 60_000, labels: .english).contains(
                "Other\n"))
    }

    @Test func aSingleOnePointTopicStaysItself() {
        var layout = NotesLayout()
        layout.topics = [topic("Pierwszy", 3), topic("Drugi", 1), topic("Trzeci", 3)]
        #expect(layout.shownTopics(durationMs: 40 * 60_000).map(\.name) == ["Pierwszy", "Drugi", "Trzeci"])
    }

    @Test func theOtherTopicHoldsAtMostSixPoints() {
        var layout = NotesLayout()
        layout.topics = (1...8).map { topic("Temat \($0)", 1) } + [topic("Duży", 4), topic("Drugi duży", 4)]
        let other = layout.shownTopics(durationMs: 60 * 60_000).last
        #expect(other?.isOther == true && other?.points.count == NotesLayout.maxPointsPerTopic)
    }

    // MARK: Order and sections

    @Test func theSectionsComeInTheDocumentedOrderAndTheIntroHasNoHeading() {
        var layout = NotesLayout(intro: "Zespół omówił plan.")
        layout.topics = [topic("Pierwszy", 3), topic("Drugi", 3)]
        layout.decisions = ["Plan przyjęty."]
        layout.nextSteps = [.init(text: "Wysłać plan", person: "Julia", due: "piątek")]
        layout.openQuestions = ["Kto płaci?"]
        layout.participants = ["Hanna", "Julia"]
        let markdown = render(layout, title: "Plan tygodnia")
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.first == "### Plan tygodnia")
        #expect(lines[1] == "Zespół omówił plan.")
        let headings = lines.filter { $0.hasPrefix("#") }.map { $0.drop { $0 == "#" || $0 == " " } }
        #expect(
            headings.map(String.init) == [
                "Plan tygodnia", "Pierwszy", "Drugi", "Podjęte decyzje", "Następne kroki", "Otwarte kwestie",
                "Uczestnicy",
            ])
        // Topics are siblings of the sections: one level below the title, the same as "Podjęte decyzje".
        let levels = lines.filter { $0.hasPrefix("#") }.map { $0.prefix { $0 == "#" }.count }
        #expect(levels == [3, 4, 4, 4, 4, 4, 4])
        #expect(markdown.contains("- [ ] Wysłać plan — osoba\\: Julia, termin\\: piątek"))
        #expect(markdown.hasSuffix("Hanna, Julia"))
    }

    @Test func withoutATitleTheTopicsAreTheHighestHeadings() {
        var layout = NotesLayout(intro: "Wstęp.")
        layout.topics = [topic("Pierwszy", 3), topic("Drugi", 3)]
        let markdown = render(layout)
        #expect(markdown.hasPrefix("Wstęp.\n\n### Pierwszy\n\n- "))
    }

    @Test func anEmptySectionDisappears() {
        var layout = NotesLayout(intro: "Rozmowa bez ustaleń.")
        #expect(render(layout) == "Rozmowa bez ustaleń.")
        layout.decisions = ["  ", "[ ] "]
        layout.openQuestions = [""]
        layout.topics = [.init(name: "Pusty", points: []), .init(name: "Pusty 2", points: ["  "])]
        #expect(render(layout) == "Rozmowa bez ustaleń.")
        #expect(render(NotesLayout()) == NotesComposer.Labels.polish.nothing)
        #expect(render(NotesLayout(), title: "Tytuł").contains(NotesComposer.Labels.polish.nothing))
    }

    @Test func aNextStepNamesOnlyWhatWasSaid() {
        var layout = NotesLayout()
        layout.nextSteps = [
            .init(text: "Zrobić rzecz", person: nil, due: nil), .init(text: "Zrobić drugą", person: "Ewa", due: nil),
            .init(text: "Zrobić trzecią", person: " ", due: "jutro"),
        ]
        let markdown = render(layout)
        #expect(markdown.contains("- [ ] Zrobić rzecz\n"))
        #expect(markdown.contains("- [ ] Zrobić drugą — osoba\\: Ewa\n"))
        #expect(markdown.contains("- [ ] Zrobić trzecią — termin\\: jutro"))
        #expect(!markdown.contains("Do przypisania") && !markdown.contains("Unassigned"))
        #expect(
            NotesLayoutComposer.markdown(layout: layout, labels: .english).contains(
                "- [ ] Zrobić drugą — owner\\: Ewa"))
        #expect(NotesComposer.Labels.english.nextSteps == "Next steps")
    }

    // MARK: Clean-up

    @Test func noTimeAndNoChecklistMarkerFromTheModelSurvives() {
        var layout = NotesLayout(intro: "Zespół ustalił [01:05] termin ~01:05 na jutro (01:05)")
        layout.topics = [
            .init(name: "Koszty [00:21]", points: ["[ ] Czynsz [00:21] spada.", "[x] Prąd ~00:30 drożeje (00:30)"])
        ]
        layout.decisions = ["[x] Bierzemy lokal ~01:05 na Woli."]
        layout.nextSteps = [.init(text: "[ ] Zadzwonić (01:23)", person: "Tomek", due: "piątek [01:30]")]
        layout.openQuestions = ["Kiedy przeprowadzka? [01:52]"]
        let markdown = render(layout, durationMs: 60 * 60_000).replacing("\\", with: "")
        #expect(markdown.matches(of: /\[?~?\(?\d{1,2}:\d{2}\)?\]?/).isEmpty, "a time reached the notes: \(markdown)")
        #expect(!markdown.contains("[x]") && !markdown.contains("- [ ] [ ]"))
        #expect(markdown.contains("- [ ] Zadzwonić — osoba: Tomek, termin: piątek"))
        #expect(markdown.contains("Czynsz spada.") && markdown.contains("Bierzemy lokal na Woli."))
    }

    @Test func aClockHourInASentenceIsAFactAndStays() {
        let markdown = render(NotesLayout(intro: "Spotkanie z klientem jest o 17:00.")).replacing("\\", with: "")
        #expect(markdown.contains("o 17:00"))
    }

    /// The renderer keeps link, image and tag syntax as escaped, inert characters (`NotesMarkdown`).
    @Test func noLinkImageOrHTMLReachesTheNotes() {
        var layout = NotesLayout(intro: "Zobacz [tu](http://evil.example) i ![x](http://evil.example/p.png)")
        layout.topics = [
            .init(name: "<b>Temat</b> [x](http://evil.example)", points: ["<img src=x> Punkt [a](b)"] + points(5))
        ]
        layout.decisions = ["# Nagłówek zamiast decyzji"]
        layout.participants = ["[Hanna](http://evil.example)"]
        let markdown = render(layout, durationMs: 60 * 60_000 + 1)
        let unescaped = markdown.replacing(/\\./, with: "")
        for syntax in ["](", "![", "<", ">"] { #expect(!unescaped.contains(syntax), "\(syntax) is live") }
        #expect(markdown.contains("- \\# Nagłówek zamiast decyzji"))
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("#") }
        #expect(headings.count == 3, "only the code writes headings: \(headings)")
        #expect(headings.allSatisfy { $0.hasPrefix("###") })
    }

    @Test func aGenericSpeakerLabelIsNoParticipant() {
        var layout = NotesLayout(intro: "Wstęp.")
        layout.participants = ["Mówca 1", "Hanna"]
        #expect(render(layout).hasSuffix("Uczestnicy\n\nHanna"))
        layout.participants = ["Mówca 1", "Speaker 2"]
        #expect(!render(layout).contains("Uczestnicy"))
    }

    @Test func theLabelsExistInBothLanguages() {
        #expect(NotesComposer.Labels.polish.decisionsMade == "Podjęte decyzje")
        #expect(NotesComposer.Labels.polish.nextSteps == "Następne kroki")
        #expect(NotesComposer.Labels.polish.otherTopic == "Inne")
        #expect(NotesComposer.Labels.english.decisionsMade == "Decisions")
        #expect(NotesComposer.Labels.english.otherTopic == "Other")
    }
}

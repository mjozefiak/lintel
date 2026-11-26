import Foundation

/// What the list says when it has nothing to list (spec "Layout", empty states, C13): one sentence, at most one line
/// of help and one action. Pure: the model gives the facts (which collection, which recording plugins are on, the
/// dictation shortcut as it is right now), the words are made here. The shortcut is read at render time; a shortcut
/// the user has not set reads as "your dictation shortcut".
struct ExplorerEmptyContent: Equatable {
    enum Action: Equatable {
        case openSettings
        case searchAllNotes
        case tryAgain
    }

    var message: String
    var hint: String?
    var action: Action?

    /// What a button of the action says.
    static func title(of action: Action) -> String {
        switch action {
        case .openSettings: String(localized: "Open Settings", comment: "Explorer empty state: opens Settings")
        case .searchAllNotes:
            String(localized: "Search All Notes", comment: "Explorer: a search in one collection found nothing")
        case .tryAgain: String(localized: "Try Again", comment: "Notes: tries the failed step again")
        }
    }

    /// The empty list without a search.
    static func library(
        collection: NoteCollection, meetingsOn: Bool, dictationOn: Bool, shortcut: String?
    ) -> ExplorerEmptyContent {
        let turnOnDictation = String(
            localized: "Turn on dictation in Settings.", comment: "Explorer empty state: dictation is switched off")
        switch collection {
        case .all:
            switch (meetingsOn, dictationOn) {
            case (true, true):
                return ExplorerEmptyContent(
                    message: shortcut.map {
                        String(
                            localized:
                                "Your notes will appear here. Record a meeting and Lintel writes the notes. Or hold \($0) to dictate in any app.",
                            comment: "Explorer empty state of All notes; the dictation shortcut")
                    }
                        ?? String(
                            localized:
                                "Your notes will appear here. Record a meeting and Lintel writes the notes. Or hold your dictation shortcut to dictate in any app.",
                            comment: "Explorer empty state of All notes, the shortcut is not known"))
            case (true, false):
                return ExplorerEmptyContent(
                    message: String(
                        localized: "Your notes will appear here. Record a meeting and Lintel writes the notes.",
                        comment: "Explorer empty state of All notes while dictation is off"),
                    hint: turnOnDictation, action: .openSettings)
            case (false, true):
                return ExplorerEmptyContent(
                    message: shortcut.map {
                        String(
                            localized: "Your notes will appear here. Hold \($0) to dictate in any app.",
                            comment: "Explorer empty state of All notes while meetings are off; the shortcut")
                    }
                        ?? String(
                            localized: "Your notes will appear here. Hold your dictation shortcut to dictate in any app.",
                            comment: "Explorer empty state of All notes while meetings are off, no shortcut known"))
            case (false, false):
                return ExplorerEmptyContent(
                    message: String(
                        localized: "Your notes will appear here.", comment: "Explorer empty state, everything is off"),
                    hint: String(
                        localized: "Turn on meetings or dictation in Settings.",
                        comment: "Explorer empty state: both recording features are off"),
                    action: .openSettings)
            }
        case .meetings:
            guard meetingsOn else {
                return ExplorerEmptyContent(
                    message: String(localized: "Meetings are off.", comment: "Explorer empty state of Meetings, off"),
                    hint: String(
                        localized: "Turn on meetings in Settings.", comment: "Explorer empty state: meetings are off"),
                    action: .openSettings)
            }
            return ExplorerEmptyContent(
                message: String(
                    localized: "Meetings you record appear here.", comment: "Explorer empty state of Meetings"))
        case .dictations:
            guard dictationOn else {
                return ExplorerEmptyContent(
                    message: String(localized: "Dictation is off.", comment: "Explorer empty state of Dictations, off"),
                    hint: turnOnDictation, action: .openSettings)
            }
            return ExplorerEmptyContent(
                message: shortcut.map {
                    String(
                        localized: "Hold \($0) in any app and speak. Your dictations appear here.",
                        comment: "Explorer empty state of Dictations; the shortcut")
                }
                    ?? String(
                        localized: "Hold your dictation shortcut in any app and speak. Your dictations appear here.",
                        comment: "Explorer empty state of Dictations, the shortcut is not known"))
        }
    }

    /// A search that found nothing in the shown collection; the other collections may still have a match.
    static func noResults(query: String, collection: NoteCollection) -> ExplorerEmptyContent {
        switch collection {
        case .all:
            ExplorerEmptyContent(
                message: String(
                    localized: "No notes match “\(query)”.", comment: "Explorer: a search found nothing; the query"))
        case .meetings:
            ExplorerEmptyContent(
                message: String(
                    localized: "No notes match “\(query)” in Meetings.",
                    comment: "Explorer: a search in the Meetings list found nothing; the query"),
                action: .searchAllNotes)
        case .dictations:
            ExplorerEmptyContent(
                message: String(
                    localized: "No notes match “\(query)” in Dictations.",
                    comment: "Explorer: a search in the Dictations list found nothing; the query"),
                action: .searchAllNotes)
        }
    }

    /// `notes.sqlite` cannot be read and nothing else is listed.
    static var locked: ExplorerEmptyContent {
        ExplorerEmptyContent(
            message: String(
                localized: "Lintel can’t open your notes right now. Nothing was deleted.",
                comment: "Explorer: the notes cannot be opened"),
            action: .tryAgain)
    }
}

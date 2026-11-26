import Foundation
import Testing

@testable import MeetingsPlugin

/// Issue #269: the default input's name and UID never reach a log as text. A device's name can carry a
/// person's name and a Bluetooth device's UID its hardware address, so the diagnostic line comes from
/// `InputDeviceInfo.logDescription`, which hashes both (`LintelSpeechTests` pins that format).
@MainActor
@Suite struct MicrophoneLogPrivacyTests {
    @Test func everyInputDiagnosticLogLineWritesTheHashedLine() throws {
        for url in TestPaths.meetingsSourceFiles() {
            let text = Self.code(try String(contentsOf: url, encoding: .utf8))
            for call in Self.loggerCalls(in: text) {
                // A device's name is shown to the user in the HUD; a log line names the device only hashed.
                for word in ["requestedName", "usingName", "inputDeviceName", "name=", "uid="] {
                    #expect(!call.contains(word), "\(url.lastPathComponent) logs \(word): \(call)")
                }
            }
        }
        // The four lines of the microphone recovery (the fallback, the start failure, the change of the default
        // input and the start after a retry) all log the hashed line that `inputDiagnostics()` returns.
        let url = TestPaths.meetingsSource(named: "MeetingSession.swift")
        let lines = Self.loggerCalls(in: Self.code(try String(contentsOf: url, encoding: .utf8)))
            .filter { $0.contains("default input") }
        #expect(lines.count >= 4)
        for line in lines {
            #expect(line.contains("\\(input, privacy: .public)"), "\(line)")
        }
        // The line itself is the hashed one, with a word for "no device" instead of empty fields.
        let observer = TestPaths.meetingsSource(named: "DefaultInputObserver.swift")
        let text = Self.code(try String(contentsOf: observer, encoding: .utf8))
        #expect(text.contains("MicrophoneCapture.defaultInputInfo()?.logDescription ?? \"none\""))
        #expect(!text.contains("defaultInputInfo()?.name"))
        #expect(!text.contains("defaultInputInfo()?.uid"))
    }

    /// The source without comments, so a comment may still mention the words the test forbids.
    private static func code(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The text of every `logger.<level>(...)` call, parentheses balanced across lines.
    private static func loggerCalls(in text: String) -> [String] {
        var calls: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: "logger.") {
            let after = rest[range.upperBound...]
            guard let open = after.firstIndex(of: "(") else { break }
            var depth = 0
            var end = open
            for index in after[open...].indices {
                if after[index] == "(" { depth += 1 }
                if after[index] == ")" {
                    depth -= 1
                    if depth == 0 {
                        end = index
                        break
                    }
                }
            }
            calls.append(String(after[open...end]))
            rest = after[end...]
        }
        return calls
    }
}

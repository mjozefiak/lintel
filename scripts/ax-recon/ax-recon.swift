// ax-recon: reads the Accessibility tree of a running app for the speaker-names recon (spec
// 2026-11-25-meeting-speaker-names, step 0.2). A tool for developers, outside the app and outside the
// SwiftPM graph: build it with build.sh. It never runs in a release build.
//
// Privacy: by default it prints structure only (roles, counts, text and identifier lengths). Text values are printed only
// with --show-text, which is for a test meeting with fictional names. `webareas` prints only the host of each
// AXWebArea URL (never tab titles, paths or page text).
import AppKit
import ApplicationServices
import Foundation

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}

func str(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }

func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

func host(of el: AXUIElement) -> String? {
    guard let url = attr(el, kAXURLAttribute) as? URL else { return nil }
    return url.host
}

func setFlag(_ app: AXUIElement, _ name: String, _ on: Bool) -> AXError {
    AXUIElementSetAttributeValue(app, name as CFString, on as CFBoolean)
}

func setManual(_ app: AXUIElement, _ on: Bool) -> AXError { setFlag(app, "AXManualAccessibility", on) }

func getManual(_ app: AXUIElement) -> Bool? { (attr(app, "AXManualAccessibility") as? NSNumber)?.boolValue }

struct Walk {
    var nodes = 0
    var maxDepth = 0
    var roles: [String: Int] = [:]
    var textNodes = 0
    var truncated = false
}

/// Walks the tree breadth-limited; stops at `limit` nodes and `deadline`.
func walk(
    _ root: AXUIElement, maxDepth: Int, limit: Int, deadline: Date, showText: Bool, print out: Bool
) -> Walk {
    var w = Walk()
    func visit(_ el: AXUIElement, _ depth: Int) {
        if w.nodes >= limit || Date() > deadline { w.truncated = true; return }
        w.nodes += 1
        w.maxDepth = max(w.maxDepth, depth)
        let role = str(el, kAXRoleAttribute) ?? "?"
        w.roles[role, default: 0] += 1
        let parts: [(String, String?)] = [
            ("v", str(el, kAXValueAttribute)), ("t", str(el, kAXTitleAttribute)), ("d", str(el, kAXDescriptionAttribute)),
        ]
        let text = parts.compactMap { $0.1 }.first { !$0.isEmpty }
        if text != nil { w.textNodes += 1 }
        if out {
            var line = String(repeating: "  ", count: depth) + role
            if let sub = str(el, kAXSubroleAttribute) { line += "/" + sub }
            if let id = str(el, kAXIdentifierAttribute), !id.isEmpty { line += showText ? " id=\(id.prefix(40))" : " id(\(id.count))" }
            for (k, v) in parts {
                guard let v, !v.isEmpty else { continue }
                line += showText ? " \(k)=\"\(v.prefix(80))\"" : " \(k)(\(v.count))"
            }
            if let c = (attr(el, "AXDOMClassList") as? [String]), showText { line += " class=\(c.prefix(3).joined(separator: ","))" }
            Swift.print(line)
        }
        if depth < maxDepth { for child in children(el) { visit(child, depth + 1) } }
    }
    visit(root, 0)
    return w
}

func findWebAreas(_ root: AXUIElement, limit: Int, deadline: Date) -> [(host: String?, depth: Int)] {
    var found: [(String?, Int)] = []
    var seen = 0
    func visit(_ el: AXUIElement, _ depth: Int) {
        if seen >= limit || Date() > deadline { return }
        seen += 1
        let role = str(el, kAXRoleAttribute)
        if role == "AXWebArea" { found.append((host(of: el), depth)); return }
        for child in children(el) { visit(child, depth + 1) }
    }
    visit(root, 0)
    return found
}

func cpuPercent(pid: Int32) -> Double {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "%cpu=", "-p", String(pid)]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
        usage: ax-recon trusted
               ax-recon apps                         bundle id, pid of running regular apps
               ax-recon manual <pid> get|on|off|enhanced-on|enhanced-off     AXManualAccessibility on the app
               ax-recon webareas <pid>               hosts of AXWebArea nodes only
               ax-recon tree <pid> [--depth N] [--limit N] [--seconds S] [--show-text] [--window-index I]
               ax-recon sample <pid> <seconds> [--hz H] [--depth N]   walk at H Hz, print per-walk time and CPU
        exit codes: 0 ok, 1 no access or no result, 2 usage

        """.utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }

func option(_ name: String, _ default: Int) -> Int {
    guard let i = args.firstIndex(of: name), i + 1 < args.count, let v = Int(args[i + 1]) else { return `default` }
    return v
}

switch cmd {
case "trusted":
    print(AXIsProcessTrusted() ? "trusted" : "not trusted")
    exit(AXIsProcessTrusted() ? 0 : 1)
case "apps":
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("\(app.bundleIdentifier ?? "?") \(app.processIdentifier)")
    }
case "manual":
    guard args.count >= 3, let pid = Int32(args[1]) else { usage() }
    let app = AXUIElementCreateApplication(pid)
    switch args[2] {
    case "get": print(getManual(app).map { $0 ? "on" : "off" } ?? "unset")
    case "on", "off":
        let result = setManual(app, args[2] == "on")
        print(result == .success ? "ok" : "failed(\(result.rawValue))")
    case "enhanced-on": print(setFlag(app, "AXEnhancedUserInterface", true).rawValue)
    case "enhanced-off": print(setFlag(app, "AXEnhancedUserInterface", false).rawValue)
    default: usage()
    }
case "webareas":
    guard args.count >= 2, let pid = Int32(args[1]) else { usage() }
    let app = AXUIElementCreateApplication(pid)
    let found = findWebAreas(app, limit: 200_000, deadline: Date().addingTimeInterval(10))
    print("webAreas: \(found.count)")
    for (h, d) in found { print("  host=\(h ?? "none") depth=\(d)") }
    exit(found.isEmpty ? 1 : 0)
case "tree":
    guard args.count >= 2, let pid = Int32(args[1]) else { usage() }
    let app = AXUIElementCreateApplication(pid)
    var root = app
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    print("windows: \(windows.count)")
    if let i = args.firstIndex(of: "--window-index"), i + 1 < args.count, let n = Int(args[i + 1]), windows.indices.contains(n) {
        root = windows[n]
    }
    let start = Date()
    let w = walk(
        root, maxDepth: option("--depth", 12), limit: option("--limit", 5000),
        deadline: Date().addingTimeInterval(Double(option("--seconds", 5))), showText: args.contains("--show-text"),
        print: true)
    print("--")
    print("nodes=\(w.nodes) maxDepth=\(w.maxDepth) textNodes=\(w.textNodes) truncated=\(w.truncated) ms=\(Int(Date().timeIntervalSince(start) * 1000))")
    print("roles: " + w.roles.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }.joined(separator: " "))
case "sample":
    guard args.count >= 3, let pid = Int32(args[1]), let seconds = Double(args[2]) else { usage() }
    let hz = Double(option("--hz", 1))
    let app = AXUIElementCreateApplication(pid)
    var times: [Double] = []
    var cpus: [Double] = []
    var nodes = 0
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        let t0 = Date()
        let w = walk(app, maxDepth: option("--depth", 12), limit: 20_000, deadline: Date().addingTimeInterval(2),
                     showText: false, print: false)
        nodes = w.nodes
        times.append(Date().timeIntervalSince(t0) * 1000)
        cpus.append(cpuPercent(pid: pid))
        let rest = 1.0 / hz - Date().timeIntervalSince(t0)
        if rest > 0 { Thread.sleep(forTimeInterval: rest) }
    }
    guard !times.isEmpty else { print("walks=0"); exit(1) }
    let sorted = times.sorted()
    let mean = { (a: [Double]) in a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
    print("walks=\(times.count) nodes=\(nodes) walkMs median=\(Int(sorted[sorted.count / 2])) max=\(Int(sorted.last ?? 0)) appCpuMean=\(String(format: "%.1f", mean(cpus)))%")
default: usage()
}

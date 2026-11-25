import Darwin
import Foundation

/// Finds the app a helper process belongs to from its executable's path (spec: Wykrywanie spotkań). Chrome,
/// Edge, Arc, Brave, Firefox and Electron apps do their audio in helper processes whose bundle ID can differ
/// from the app's; the helper lives inside the app's bundle, so the outermost `.app` of the path names the app.
/// It reads the path and one `Info.plist`, nothing else.
enum ResponsibleApp {
    /// The outermost `.app` directory in an executable's path, or `nil` when it has none (a system service).
    static func bundlePath(inExecutablePath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }

    /// The bundle ID of the app that holds process `pid`, or `nil`.
    static func bundleID(
        pid: pid_t, readBundleID: (String) -> String? = { Bundle(path: $0)?.bundleIdentifier }
    ) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        guard let app = bundlePath(inExecutablePath: String(cString: buffer)) else { return nil }
        return readBundleID(app)
    }
}

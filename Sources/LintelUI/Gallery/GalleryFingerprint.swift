#if DEBUG
import AppKit

/// DEBUG only: what a golden image depends on besides the code (spec `2026-11-23-swiftui-design-gallery`, `GalleryFingerprint`).
/// Text drawing changes with the macOS build and with the SDK a binary is linked against, so goldens recorded under
/// another fingerprint are not compared pixel by pixel: the test says "renderer fingerprint changed" instead.
public struct GalleryFingerprint: Codable, Equatable, Sendable {
    /// The macOS version and build, `27.0.1 (26A434)`.
    public var os: String
    /// `xcodebuild -version` as the workflow passes it in `LINTEL_GALLERY_XCODE`; `nil` when it is not known, which
    /// makes a comparison impossible.
    public var xcode: String?
    /// The backing scale of the bitmaps (always `GalleryRenderer.scale`: forced, not read from a window).
    public var scale: Int
    /// `GalleryRenderer.version`.
    public var renderer: Int

    public init(os: String, xcode: String?, scale: Int, renderer: Int) {
        self.os = os
        self.xcode = xcode
        self.scale = scale
        self.renderer = renderer
    }

    public static let xcodeEnvironmentKey = "LINTEL_GALLERY_XCODE"

    @MainActor public static var current: GalleryFingerprint {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = Self.systemBuild() ?? "unknown"
        let xcode = ProcessInfo.processInfo.environment[xcodeEnvironmentKey].flatMap { $0.isEmpty ? nil : $0 }
        return GalleryFingerprint(
            os: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(build))",
            xcode: xcode, scale: Int(GalleryRenderer.scale), renderer: GalleryRenderer.version)
    }

    private static func systemBuild() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Why goldens recorded under `self` cannot be compared with `other`, or `nil` when they can.
    public func mismatch(comparedTo other: GalleryFingerprint) -> String? {
        var differences: [String] = []
        if os != other.os { differences.append("os \(os) vs \(other.os)") }
        if xcode != other.xcode { differences.append("xcode \(xcode ?? "unknown") vs \(other.xcode ?? "unknown")") }
        if scale != other.scale { differences.append("scale \(scale) vs \(other.scale)") }
        if renderer != other.renderer { differences.append("renderer \(renderer) vs \(other.renderer)") }
        return differences.isEmpty ? nil : differences.joined(separator: ", ")
    }
}
#endif

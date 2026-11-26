#if DEBUG
import AppKit

/// DEBUG only: compares two renders pixel by pixel (spec `2026-11-23-swiftui-design-gallery`, Q6). A pixel differs when
/// any of its R, G, B, A channels differs by more than `channelTolerance` (3 of 255 by default: antialiasing noise,
/// not a 1 pt shift, which moves a whole band of pixels). Pure: no I/O.
public enum GalleryDiff {
    /// The default tolerance per channel (Q6).
    public static let defaultChannelTolerance: UInt8 = 3
    /// More than this share of differing pixels fails a golden test (Q6: 0.1%).
    public static let defaultShareLimit = 0.001

    public struct Result: Sendable, Equatable {
        public let differingShare: Double
        public let sizeMatches: Bool

        public init(differingShare: Double, sizeMatches: Bool) {
            self.differingShare = differingShare
            self.sizeMatches = sizeMatches
        }

        /// Whether the picture is the golden one, within `limit` of differing pixels.
        public func passes(shareLimit: Double = GalleryDiff.defaultShareLimit) -> Bool {
            sizeMatches && differingShare <= shareLimit
        }
    }

    public static func compare(
        _ a: NSBitmapImageRep, _ b: NSBitmapImageRep, channelTolerance: UInt8 = defaultChannelTolerance
    ) -> (Result, diffImage: NSBitmapImageRep?) {
        guard let first = GalleryPixels(a), let second = GalleryPixels(b) else {
            return (Result(differingShare: 1, sizeMatches: false), nil)
        }
        return compare(first, second, channelTolerance: channelTolerance)
    }

    public static func compare(
        _ a: GalleryPixels, _ b: GalleryPixels, channelTolerance: UInt8 = defaultChannelTolerance
    ) -> (Result, diffImage: NSBitmapImageRep?) {
        guard a.width == b.width, a.height == b.height else {
            return (Result(differingShare: 1, sizeMatches: false), nil)
        }
        let count = a.width * a.height
        guard count > 0 else { return (Result(differingShare: 0, sizeMatches: true), nil) }
        var differing = 0
        var out = [UInt8](repeating: 0, count: count * 4)
        a.bytes.withUnsafeBufferPointer { left in
            b.bytes.withUnsafeBufferPointer { right in
                for pixel in 0..<count {
                    let base = pixel * 4
                    var changed = false
                    for channel in 0..<4 {
                        let x = Int(left[base + channel])
                        let y = Int(right[base + channel])
                        if abs(x - y) > Int(channelTolerance) {
                            changed = true
                            break
                        }
                    }
                    if changed {
                        differing += 1
                        out[base] = 255
                        out[base + 3] = 255
                    } else {
                        // The original, faded towards white, so the red shows where the change is.
                        for channel in 0..<3 { out[base + channel] = UInt8((Int(left[base + channel]) + 3 * 255) / 4) }
                        out[base + 3] = 255
                    }
                }
            }
        }
        let share = Double(differing) / Double(count)
        let image = differing == 0 ? nil : GalleryPixels(width: a.width, height: a.height, bytes: out).bitmap()
        return (Result(differingShare: share, sizeMatches: true), image)
    }
}

/// RGBA, 8 bits, premultiplied, sRGB: what both sides of a comparison are brought to, so a PNG read from disk and a
/// bitmap just drawn compare byte for byte.
public struct GalleryPixels: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public init?(_ rep: NSBitmapImageRep) {
        guard let cgImage = rep.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.setBlendMode(.copy)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, bytes: bytes)
    }

    /// The pixels as an sRGB bitmap (premultiplied alpha, 1 pixel = 1 point at scale 1).
    public func bitmap() -> NSBitmapImageRep? {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: width * 4,
                bitsPerPixel: 32),
            let data = rep.bitmapData
        else { return nil }
        let copied = bytes.withUnsafeBufferPointer { source -> Bool in
            guard let base = source.baseAddress else { return false }
            data.update(from: base, count: bytes.count)
            return true
        }
        // The bytes ARE sRGB: tag them so, without converting them.
        return copied ? rep.retagging(with: NSColorSpace.sRGB) : nil
    }
}
#endif

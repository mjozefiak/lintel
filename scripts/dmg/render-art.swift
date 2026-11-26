// Renders Resources/DMG/background.svg to background.png (660 x 400 px) and background@2x.png (1320 x 800 px).
// Run by hand when the art changes: swift scripts/dmg/render-art.swift Resources/DMG
// The PNGs and background.tiff are committed; make-dmg.sh never renders anything.
import AppKit

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/DMG"
guard let svg = NSImage(contentsOfFile: "\(dir)/background.svg") else {
  FileHandle.standardError.write(Data("cannot read \(dir)/background.svg\n".utf8))
  exit(1)
}

func render(pixels: (Int, Int), to path: String) {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels.0, pixelsHigh: pixels.1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
  else { exit(1) }
  rep.size = NSSize(width: pixels.0, height: pixels.1)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current?.imageInterpolation = .high
  svg.draw(in: NSRect(x: 0, y: 0, width: pixels.0, height: pixels.1))
  NSGraphicsContext.restoreGraphicsState()
  guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
  do { try png.write(to: URL(fileURLWithPath: path)) } catch { exit(1) }
}

render(pixels: (660, 400), to: "\(dir)/background.png")
render(pixels: (1320, 800), to: "\(dir)/background@2x.png")

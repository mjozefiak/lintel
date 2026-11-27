import CoreGraphics
import Testing

@testable import LintelApp

/// Spec 2026-11-24, "Floating helper panel": where the panel sits beside a window, and the flip between the two
/// vertical conventions (window bounds grow downwards, `NSWindow` frames upwards).
@Suite struct PermissionHelperGeometryTests {
    typealias Geometry = PermissionHelperGeometry
    private let size = CGSize(width: 300, height: 100)
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func flippingIsItsOwnInverse() {
        let rect = CGRect(x: 40, y: 100, width: 300, height: 120)
        let flipped = Geometry.flipped(rect, primaryHeight: 1080)
        #expect(flipped == CGRect(x: 40, y: 860, width: 300, height: 120))
        #expect(Geometry.flipped(flipped, primaryHeight: 1080) == rect)
    }

    @Test func aWindowAtTheTopOfTheScreenIsAtTheTopInAppKitSpaceToo() {
        // CG: top edge 0 + 28 below the menu bar. AppKit: the top edge is at primaryHeight - 28.
        let top = Geometry.flipped(CGRect(x: 0, y: 28, width: 100, height: 100), primaryHeight: 1080)
        let expectedTop: CGFloat = 1052
        #expect(top.maxY == expectedTop)
    }

    @Test func thePanelSitsToTheRightOfTheWindowWhenThatFits() {
        let window = CGRect(x: 200, y: 200, width: 700, height: 500)
        let frame = Geometry.frame(size: size, beside: window, displays: [display])
        #expect(frame.minX == window.maxX + Geometry.gap)
        #expect(frame.midY == window.midY)
        #expect(frame.size == size)
    }

    @Test func itGoesToTheLeftWhenTheRightSideIsOffTheDisplay() {
        let window = CGRect(x: 1100, y: 200, width: 700, height: 500)  // maxX 1800, panel would end at 2108
        let frame = Geometry.frame(size: size, beside: window, displays: [display])
        #expect(frame.maxX == window.minX - Geometry.gap)
    }

    @Test func itGoesInsideTheWindowWhenNeitherSideFits() {
        let window = CGRect(x: 20, y: 100, width: 1880, height: 800)
        let frame = Geometry.frame(size: size, beside: window, displays: [display])
        #expect(frame.maxX == window.maxX - Geometry.gap)
        #expect(window.contains(frame))
    }

    @Test func itStaysBelowTheMenuBarAndAboveTheBottomEdge() {
        let high = CGRect(x: 200, y: 0, width: 700, height: 40)
        #expect(Geometry.frame(size: size, beside: high, displays: [display]).minY == Geometry.menuBarHeight)
        let low = CGRect(x: 200, y: 1060, width: 700, height: 20)
        #expect(Geometry.frame(size: size, beside: low, displays: [display]).maxY == display.maxY)
    }

    @Test func itUsesTheDisplayTheWindowIsOn() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let window = CGRect(x: 2000, y: 200, width: 700, height: 500)
        let frame = Geometry.frame(size: size, beside: window, displays: [display, second])
        #expect(frame.minX == window.maxX + Geometry.gap)
        // A window at the far right of the second display: left of it, never on the first display's side.
        let edge = CGRect(x: 3100, y: 200, width: 700, height: 500)
        let atEdge = Geometry.frame(size: size, beside: edge, displays: [display, second])
        #expect(atEdge.maxX == edge.minX - Geometry.gap)
        #expect(second.contains(atEdge))
    }

    @Test func withNoDisplayItStillSitsBesideTheWindow() {
        let window = CGRect(x: 200, y: 200, width: 700, height: 500)
        let frame = Geometry.frame(size: size, beside: window, displays: [])
        #expect(frame.minX == window.maxX + Geometry.gap)
    }

    @Test func theCornerFrameIsTheBottomRightOfTheFirstDisplay() {
        let frame = Geometry.cornerFrame(size: size, displays: [display])
        #expect(frame.maxX == display.maxX - Geometry.cornerMargin)
        #expect(frame.maxY == display.maxY - Geometry.cornerMargin)
    }

    @Test func reduceMotionOrNoOriginMeansAFade() {
        let origin = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(PermissionHelperMotion.choose(reduceMotion: false, origin: origin) == .slide(from: origin))
        #expect(PermissionHelperMotion.choose(reduceMotion: true, origin: origin) == .fade)
        #expect(PermissionHelperMotion.choose(reduceMotion: false, origin: nil) == .fade)
    }
}

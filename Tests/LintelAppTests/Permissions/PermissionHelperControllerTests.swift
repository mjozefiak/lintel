import CoreGraphics
import Foundation
import LintelTestSupport
import LintelUI
import Testing

@testable import LintelApp

/// What a test changes between two ticks: the window list, the running Settings app, the grant, the time.
@MainActor final class HelperWorld {
    var windows: [WindowSample] = []
    var pids: Set<pid_t> = []
    var displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    /// In AppKit coordinates (origin at the bottom left).
    var lintel: CGRect? = CGRect(x: 100, y: 500, width: 600, height: 400)
    var primaryHeight: CGFloat = 1080
    var granted = false
    var reduceMotion = false
    var now: Duration = .zero
    var finderCalls = 0
    var windowReads = 0

    func environment() -> PermissionHelperEnvironment {
        PermissionHelperEnvironment(
            windows: { [self] in
                windowReads += 1
                return windows
            },
            settingsPIDs: { [self] in pids },
            displays: { [self] in displays },
            lintelFrame: { [self] in lintel },
            primaryHeight: { [self] in primaryHeight },
            isGranted: { [self] in granted },
            reduceMotion: { [self] in reduceMotion },
            now: { [self] in now },
            showInFinder: { [self] in finderCalls += 1 })
    }

    func settingsWindow(_ frame: CGRect, pid: pid_t = 900) {
        pids = [pid]
        windows = [WindowSample(ownerPID: pid, bounds: frame, layer: 0, isOnScreen: true)]
    }

    func advance(_ duration: Duration) { now += duration }
}

@MainActor final class FakeHelperPanel: PermissionHelperPresenting {
    struct Shown: Equatable {
        var content: PermissionHelperContent
        var frame: CGRect
        var motion: PermissionHelperMotion
    }
    var onShowInFinder: (() -> Void)?
    var onDone: (() -> Void)?
    var shown: [Shown] = []
    var updates: [PermissionHelperContent] = []
    var moves: [CGRect] = []
    var closes = 0
    var panelSize = CGSize(width: 300, height: 100)

    func size(for content: PermissionHelperContent) -> CGSize { panelSize }
    func show(content: PermissionHelperContent, frame: CGRect, motion: PermissionHelperMotion) {
        shown.append(Shown(content: content, frame: frame, motion: motion))
    }
    func update(content: PermissionHelperContent) { updates.append(content) }
    func move(to frame: CGRect) { moves.append(frame) }
    func close() { closes += 1 }
}

/// Spec 2026-11-24 Phase 2, step 2.5: the controller of the floating helper, over injected ports. The rules of the
/// session itself (when it closes) are in `PermissionHelperSessionTests`; this checks that the controller feeds it
/// the right observations and draws what it says.
@Suite struct PermissionHelperControllerTests {
    private let settings = CGRect(x: 300, y: 100, width: 700, height: 500)  // CG space: top left origin

    private final class Reasons: @unchecked Sendable {
        var all: [PermissionHelperSession.CloseReason] = []
    }

    private func make(
        _ content: PermissionHelperContent = .dragTile, world: HelperWorld = HelperWorld(),
        panel: FakeHelperPanel = FakeHelperPanel(), clock: TestClock = TestClock(), reasons: Reasons = Reasons()
    ) -> (PermissionHelperController, HelperWorld, FakeHelperPanel, TestClock, Reasons) {
        let controller = PermissionHelperController(
            content: content, environment: world.environment(), panel: panel, clock: clock,
            onClose: { reasons.all.append($0) })
        return (controller, world, panel, clock, reasons)
    }

    /// The AppKit frame the panel should get beside `window` (CG space).
    private func expected(beside window: CGRect, world: HelperWorld, size: CGSize = CGSize(width: 300, height: 100))
        -> CGRect
    {
        PermissionHelperGeometry.flipped(
            PermissionHelperGeometry.frame(size: size, beside: window, displays: world.displays),
            primaryHeight: world.primaryHeight)
    }

    @Test func nothingIsShownBeforeTheFirstSightingOfTheWindow() {
        let (controller, world, panel, _, _) = make()
        controller.start()
        world.advance(.seconds(2))
        controller.tick()
        #expect(panel.shown.isEmpty)
        #expect(controller.isOpen)
    }

    @Test func thePanelAppearsBesideTheSettingsWindowWithTheGivenContent() {
        let (controller, world, panel, _, _) = make(.turnOnSwitch)
        world.settingsWindow(settings)
        controller.start()
        let shown = panel.shown
        #expect(shown.count == 1)
        #expect(shown.first?.content == .turnOnSwitch)
        #expect(shown.first?.frame == expected(beside: settings, world: world))
    }

    @Test func itSlidesInFromLintelsWindowUnlessReduceMotionIsOn() throws {
        let (controller, world, panel, _, _) = make()
        world.settingsWindow(settings)
        controller.start()
        let lintel = try #require(world.lintel)
        let origin = CGRect(x: lintel.midX - 150, y: lintel.midY - 50, width: 300, height: 100)
        #expect(panel.shown.first?.motion == .slide(from: origin))

        let reduced = make()
        reduced.1.settingsWindow(settings)
        reduced.1.reduceMotion = true
        reduced.0.start()
        #expect(reduced.2.shown.first?.motion == .fade)
    }

    @Test func itFollowsTheWindowWhenItMovesAndStaysWhenItDoesNot() {
        let (controller, world, panel, _, _) = make()
        world.settingsWindow(settings)
        controller.start()
        world.advance(.milliseconds(250))
        controller.tick()
        #expect(panel.moves.isEmpty, "an unchanged window moves nothing")

        let moved = CGRect(x: 100, y: 150, width: 700, height: 500)
        world.settingsWindow(moved)
        world.advance(.milliseconds(250))
        controller.tick()
        #expect(panel.moves == [expected(beside: moved, world: world)])
    }

    @Test func itStaysWhereItIsWhileTheWindowIsGoneForLessThanThreeSeconds() {
        let (controller, world, panel, _, _) = make()
        world.settingsWindow(settings)
        controller.start()
        world.windows = []
        world.advance(.seconds(2))
        controller.tick()
        #expect(panel.moves.isEmpty)
        #expect(panel.closes == 0)
    }

    @Test func withoutAWindowItSitsBesideLintelAfterThreeSecondsThenGoesToSettingsWhenItAppears() throws {
        let (controller, world, panel, _, _) = make()
        controller.start()
        world.advance(.seconds(3))
        controller.tick()
        let lintelCG = PermissionHelperGeometry.flipped(try #require(world.lintel), primaryHeight: world.primaryHeight)
        #expect(panel.shown.count == 1)
        #expect(panel.shown.first?.frame == expected(beside: lintelCG, world: world))

        world.settingsWindow(settings)
        world.advance(.milliseconds(250))
        controller.tick()
        #expect(panel.moves == [expected(beside: settings, world: world)])
    }

    @Test func withNoWindowAtAllItSitsInTheCornerOfTheScreen() {
        let (controller, world, panel, _, _) = make()
        world.lintel = nil
        controller.start()
        world.advance(.seconds(3))
        controller.tick()
        let corner = PermissionHelperGeometry.flipped(
            PermissionHelperGeometry.cornerFrame(size: panel.panelSize, displays: world.displays),
            primaryHeight: world.primaryHeight)
        #expect(panel.shown.first?.frame == corner)
        #expect(panel.shown.first?.motion == .fade, "no window to slide from")
    }

    @Test func aGrantShowsAllowedForASecondThenClosesWithTheGrantAsTheReason() {
        let (controller, world, panel, _, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        world.granted = true
        world.advance(.milliseconds(250))
        controller.tick()
        #expect(panel.updates == [.allowed])
        #expect(panel.closes == 0)
        world.advance(.milliseconds(500))
        controller.tick()
        #expect(panel.closes == 0, "still within the second")
        world.advance(.milliseconds(500))
        controller.tick()
        #expect(panel.closes == 1)
        #expect(reasons.all == [.granted])
        #expect(!controller.isOpen)
    }

    @Test func aGrantBeforeThePanelIsShownShowsItAllowedBesideLintel() {
        let (controller, world, panel, _, reasons) = make()
        world.granted = true
        controller.start()
        #expect(panel.shown.map(\.content) == [.allowed])
        world.advance(.seconds(1))
        controller.tick()
        #expect(reasons.all == [.granted])
    }

    @Test func itClosesWhenSettingsQuits() {
        let (controller, world, panel, _, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        world.pids = []
        world.windows = []
        world.advance(.milliseconds(250))
        controller.tick()
        #expect(reasons.all == [.settingsQuit])
        #expect(panel.closes == 1)
    }

    @Test func aSettingsAppThatHasNotStartedYetDoesNotCloseIt() {
        let (controller, world, _, _, reasons) = make()
        controller.start()
        world.advance(.seconds(1))
        controller.tick()
        #expect(reasons.all.isEmpty)
        #expect(controller.isOpen)
    }

    @Test func theDoneButtonClosesIt() throws {
        let (controller, world, panel, _, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        let done = try #require(panel.onDone)
        done()
        #expect(reasons.all == [.done])
        #expect(panel.closes == 1)
        #expect(!controller.isOpen)
    }

    @Test func itClosesAfterTenMinutesWithoutAGrant() {
        let (controller, world, panel, _, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        world.advance(.seconds(600))
        controller.tick()
        #expect(reasons.all == [.timedOut])
        #expect(panel.closes == 1)
    }

    @Test func showInFinderReachesThePort() throws {
        let (controller, world, panel, _, _) = make()
        world.settingsWindow(settings)
        controller.start()
        let showInFinder = try #require(panel.onShowInFinder)
        showInFinder()
        #expect(world.finderCalls == 1)
        #expect(controller.isOpen, "Show in Finder leaves the helper open")
    }

    @Test func anEndedHelperIgnoresLaterTicks() {
        let (controller, world, panel, _, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        controller.doneTapped()
        let reads = world.windowReads
        world.granted = true
        controller.tick()
        controller.doneTapped()
        #expect(world.windowReads == reads)
        #expect(panel.closes == 1)
        #expect(reasons.all == [.done])
    }

    // MARK: The poll

    @Test func itPollsFourTimesASecondWhileOpen() async {
        let (controller, world, _, clock, _) = make()
        world.settingsWindow(settings)
        controller.start()
        #expect(await clock.waitForSleepers(1))
        let before = world.windowReads
        for step in 1...4 {
            clock.advance(by: .milliseconds(250))
            #expect(await clock.waitForSleepCalls(step + 1))
        }
        #expect(world.windowReads == before + 4)
        controller.stop()
    }

    @Test func thePollStopsWhenTheHelperEnds() async {
        let (controller, world, _, clock, _) = make()
        world.settingsWindow(settings)
        controller.start()
        #expect(await clock.waitForSleepers(1))
        controller.doneTapped()
        #expect(await clock.waitForCancelledSleeps(1))
        let reads = world.windowReads
        clock.advance(by: .seconds(5))
        #expect(world.windowReads == reads)
        #expect(clock.sleeperCount == 0)
    }

    @Test func stopClosesThePanelWithoutAReasonAndEndsThePoll() async {
        let (controller, world, panel, clock, reasons) = make()
        world.settingsWindow(settings)
        controller.start()
        #expect(await clock.waitForSleepers(1))
        controller.stop()
        #expect(panel.closes == 1)
        #expect(reasons.all.isEmpty)
        #expect(await clock.waitForCancelledSleeps(1))
    }

    @Test func aHelperThatEndedOnItsFirstTickNeverStartsThePoll() {
        let (controller, world, panel, clock, reasons) = make()
        world.settingsWindow(settings)
        world.granted = true
        world.now = .zero
        controller.start()
        world.advance(.seconds(1))
        controller.tick()
        #expect(reasons.all == [.granted])
        #expect(clock.sleeperCount == 0 || !controller.isOpen)
        #expect(panel.closes == 1)
    }

    // MARK: One at a time

    @Test func showingASecondHelperClosesTheFirstWithoutAReason() {
        let panels = [FakeHelperPanel(), FakeHelperPanel()]
        let world = HelperWorld()
        world.settingsWindow(settings)
        var made = 0
        let presenter = PermissionHelperPresenter(
            makePanel: { _ in
                defer { made += 1 }
                return panels[made]
            },
            makeEnvironment: { _ in world.environment() })
        let reasons = Reasons()
        let first = presenter.show(.dragTile, isGranted: { false }, onClose: { reasons.all.append($0) })
        let second = presenter.show(.turnOnSwitch, isGranted: { false })
        #expect(!first.isOpen)
        #expect(panels[0].closes == 1)
        #expect(reasons.all.isEmpty, "replaced, not finished")
        #expect(second.isOpen)
        #expect(presenter.current === second)
        #expect(panels[1].shown.map(\.content) == [.turnOnSwitch])
        presenter.dismiss()
        #expect(panels[1].closes == 1)
        #expect(presenter.current == nil)
    }

    @Test func thePresenterPassesTheGrantReaderOnToTheEnvironment() {
        let world = HelperWorld()
        world.settingsWindow(settings)
        var askedForGrant = 0
        let presenter = PermissionHelperPresenter(
            makePanel: { _ in FakeHelperPanel() },
            makeEnvironment: { isGranted in
                var environment = world.environment()
                environment.isGranted = {
                    askedForGrant += 1
                    return isGranted()
                }
                return environment
            })
        let controller = presenter.show(.dragTile, isGranted: { true })
        #expect(askedForGrant >= 1)
        controller.stop()
    }
}

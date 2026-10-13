import AppKit
@testable import ScreendrawKit
import Testing

/// Row 1.12 of YAZ-2789: the time of a Pen line of 5,000 points.
///
/// The test runs the real path of a drag: the session, the controller, the overlay view with
/// its layers, and the toolbar. No window is on a screen, so the time has no part of the
/// window server: it is the time of the code of this app on the main thread.
@MainActor @Suite struct PenTimingTests {
    @Test func row1_12_aPenLineOf5000Points() {
        let screen = OverlayScreen(
            display: DrawDisplay(id: 1, size: CGSize(width: 2560, height: 1440)),
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
            scale: 2
        )
        // A wave across the screen. Each point is different from the point before it.
        let points = (0...5000).map { step -> CGPoint in
            CGPoint(x: 20 + CGFloat(step) * 0.5, y: 700 + 300 * sin(CGFloat(step) / 50))
        }

        var best = (total: TimeInterval.infinity, slowest: TimeInterval.infinity)
        for _ in 0..<3 {
            let store = TestDefaults()
            let controller = DrawController(
                defaults: store.defaults,
                now: { ProcessInfo.processInfo.systemUptime },
                screens: { [screen] },
                pointer: { .zero }
            )
            controller.toggleDrawing()
            let session = controller.session
            let view = controller.overlays[0].overlayView
            // 100 finished marks are on the screen. A new point must not touch them.
            for row in 0..<100 {
                session.drag((0..<50).map { CGPoint(x: 100 + CGFloat($0) * 4, y: CGFloat(10 + row * 5)) }, on: 1)
            }
            let finished = session.marksRevision
            #expect(view.markLayers.count == 100)

            var slowest: TimeInterval = 0
            let start = ProcessInfo.processInfo.systemUptime
            session.pointerDown(at: points[0], on: 1)
            for point in points.dropFirst() {
                let before = ProcessInfo.processInfo.systemUptime
                session.pointerDragged(to: point)
                slowest = max(slowest, ProcessInfo.processInfo.systemUptime - before)
            }
            let total = ProcessInfo.processInfo.systemUptime - start
            #expect(session.draft(on: 1)?.points.count == 5001)
            #expect(session.marksRevision == finished)
            session.pointerUp(at: points[5000])
            #expect(view.markLayers.count == 101)
            controller.toggleDrawing()

            if total < best.total { best = (total, slowest) }
        }

        let perPoint = best.total / 5000
        print(String(
            format: "Pen line of 5,000 points, best of 3: %.1f ms in total, %.1f µs for each point, %.2f ms for the slowest point",
            best.total * 1000, perPoint * 1_000_000, best.slowest * 1000
        ))
        // A point must cost much less than one frame of a 120 Hz screen (8.3 ms).
        #expect(perPoint < 0.001)
    }
}

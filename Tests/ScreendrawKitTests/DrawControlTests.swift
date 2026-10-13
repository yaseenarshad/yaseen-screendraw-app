import ScreendrawKit
import Testing

@MainActor
@Suite struct DrawControlTests {
    @Test func clickThroughDoesNothingWhenTheModeIsOff() {
        let draw = DrawController()
        draw.toggleClickThrough()
        #expect(draw.mode == .off)
    }
}

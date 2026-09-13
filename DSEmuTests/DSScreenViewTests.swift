import XCTest
@testable import DSEmu

@MainActor
final class DSScreenViewTests: XCTestCase {
    func testDrawableSizeTracksLandscapeBoundsAtNativeScaleAfterRotation() {
        let screenView = DSScreenView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        screenView.layoutIfNeeded()

        screenView.frame = CGRect(x: 0, y: 0, width: 667, height: 375)
        screenView.setNeedsLayout()
        screenView.layoutIfNeeded()

        let scale = screenView.metalLayer.contentsScale
        XCTAssertEqual(screenView.metalLayer.drawableSize.width, 667 * scale, accuracy: 0.5)
        XCTAssertEqual(screenView.metalLayer.drawableSize.height, 375 * scale, accuracy: 0.5)
    }
}

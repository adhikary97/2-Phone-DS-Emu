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

    func testCompactLandscapeControllerButtonsStayOutsideGameScreen() throws {
        let viewController = BottomScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 667, height: 375))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let controls = try XCTUnwrap(
            viewController.view.firstDescendant(ofType: OnScreenControls.self)
        )
        let screenFrame = viewController.screenView.convert(
            viewController.screenView.bounds,
            to: viewController.view
        )
        let buttons = controls.descendants(ofType: UIButton.self)

        XCTAssertEqual(buttons.count, 12)
        for button in buttons {
            let buttonFrame = button.convert(button.bounds, to: viewController.view)
            XCTAssertFalse(
                screenFrame.intersects(buttonFrame),
                "\(button.currentTitle ?? "Control") overlaps the DS screen"
            )
        }
    }

    func testLandscapeMenuButtonsLiveInOppositeSideWings() throws {
        let viewController = BottomScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let controls = try XCTUnwrap(
            viewController.view.firstDescendant(ofType: OnScreenControls.self)
        )
        let selectButton = try XCTUnwrap(
            controls.descendants(ofType: UIButton.self).first { $0.tag == 2 }
        )
        let startButton = try XCTUnwrap(
            controls.descendants(ofType: UIButton.self).first { $0.tag == 3 }
        )
        let screenFrame = viewController.screenView.convert(
            viewController.screenView.bounds,
            to: viewController.view
        )
        let selectFrame = selectButton.convert(selectButton.bounds, to: viewController.view)
        let startFrame = startButton.convert(startButton.bounds, to: viewController.view)

        XCTAssertLessThanOrEqual(selectFrame.maxX, screenFrame.minX)
        XCTAssertGreaterThanOrEqual(startFrame.minX, screenFrame.maxX)
    }

    func testLandscapeControllerScreenReclaimsBottomMenuSpaceAtFourByThree() {
        let viewController = BottomScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let screenFrame = viewController.screenView.convert(
            viewController.screenView.bounds,
            to: viewController.view
        )

        XCTAssertEqual(screenFrame.width / screenFrame.height, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(screenFrame.height, 350)
    }

    func testLandscapeTopDisplayUsesLargestFourByThreeFrame() {
        let viewController = TopScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let safeFrame = viewController.view.safeAreaLayoutGuide.layoutFrame
        let screenFrame = viewController.screenView.frame

        XCTAssertEqual(screenFrame.width / screenFrame.height, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(screenFrame.height, safeFrame.height, accuracy: 1)
        XCTAssertEqual(screenFrame.midX, safeFrame.midX, accuracy: 1)
        XCTAssertEqual(screenFrame.midY, safeFrame.midY, accuracy: 1)
    }

    func testControllerUsesDSInspiredControlSilhouettes() throws {
        let controls = OnScreenControls(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        controls.setLandscape(true)
        controls.layoutIfNeeded()

        let buttons = controls.descendants(ofType: UIButton.self)
        let faceButton = try XCTUnwrap(buttons.first { $0.tag == 0 })
        let selectButton = try XCTUnwrap(buttons.first { $0.tag == 2 })
        let dpadButton = try XCTUnwrap(buttons.first { $0.tag == 4 })
        let shoulderButton = try XCTUnwrap(buttons.first { $0.tag == 8 })
        let dpadCross = controls.descendants(ofType: UIView.self).first {
            $0.accessibilityIdentifier == "controller.dpad.cross"
        }

        XCTAssertNotNil(dpadCross)
        XCTAssertEqual(faceButton.layer.cornerRadius, faceButton.bounds.height / 2, accuracy: 0.1)
        XCTAssertEqual(selectButton.layer.cornerRadius, selectButton.bounds.height / 2, accuracy: 0.1)
        XCTAssertEqual(dpadButton.layer.cornerRadius, 4, accuracy: 0.1)
        XCTAssertEqual(shoulderButton.layer.cornerRadius, 9, accuracy: 0.1)
        XCTAssertNotNil(faceButton.layer.shadowPath)
        XCTAssertNotNil(selectButton.layer.shadowPath)
    }

    func testLandscapeControlZonesHaveAccidentalTapSpacing() throws {
        let viewController = BottomScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let controls = try XCTUnwrap(
            viewController.view.firstDescendant(ofType: OnScreenControls.self)
        )
        let buttons = controls.descendants(ofType: UIButton.self)
        func frame(for tag: Int) throws -> CGRect {
            let button = try XCTUnwrap(buttons.first { $0.tag == tag })
            return button.convert(button.bounds, to: controls)
        }

        let minimumGap: CGFloat = 24
        let l = try frame(for: 9)
        let up = try frame(for: 6)
        let down = try frame(for: 7)
        let select = try frame(for: 2)
        let r = try frame(for: 8)
        let x = try frame(for: 10)
        let b = try frame(for: 1)
        let start = try frame(for: 3)

        XCTAssertGreaterThanOrEqual(up.minY - l.maxY, minimumGap)
        XCTAssertGreaterThanOrEqual(select.minY - down.maxY, minimumGap)
        XCTAssertGreaterThanOrEqual(x.minY - r.maxY, minimumGap)
        XCTAssertGreaterThanOrEqual(start.minY - b.maxY, minimumGap)
    }

    func testTopDisplayAddsLidFrameAndLandscapeSpeakerGrilles() {
        let viewController = TopScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let chrome = viewController.view.descendants(ofType: UIView.self)
        let frame = chrome.first { $0.accessibilityIdentifier == "top-display.frame" }
        let speakers = chrome.filter {
            $0.accessibilityIdentifier?.hasPrefix("top-display.speaker.") == true
        }

        XCTAssertNotNil(frame)
        XCTAssertEqual(speakers.count, 2)
        XCTAssertTrue(speakers.allSatisfy { !$0.isHidden })
    }

    func testTopDisplayChromeDoesNotShadowTheGameImage() throws {
        let viewController = TopScreenViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.frame = window.bounds
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let frame = try XCTUnwrap(
            viewController.view.subviews.first {
                $0.accessibilityIdentifier == "top-display.frame"
            }
        )
        let screenIndex = try XCTUnwrap(
            viewController.view.subviews.firstIndex(of: viewController.screenView)
        )
        let frameIndex = try XCTUnwrap(viewController.view.subviews.firstIndex(of: frame))

        XCTAssertGreaterThan(frameIndex, screenIndex)
        XCTAssertEqual(frame.layer.shadowOpacity, 0, accuracy: 0.001)
    }

    func testControllerControlsBlendIntoOneShellWithoutWingPanelBoxes() {
        let controls = OnScreenControls(frame: CGRect(x: 0, y: 0, width: 932, height: 430))
        controls.setLandscape(true)
        controls.layoutIfNeeded()

        XCTAssertEqual(controls.subviews.count, 2)
        for wing in controls.subviews {
            XCTAssertEqual(wing.backgroundColor?.cgColor.alpha ?? 0, 0, accuracy: 0.001)
            XCTAssertEqual(wing.layer.borderWidth, 0, accuracy: 0.001)
        }
    }

}

private extension UIView {
    func firstDescendant<T: UIView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        return subviews.lazy.compactMap { $0.firstDescendant(ofType: type) }.first
    }

    func descendants<T: UIView>(ofType type: T.Type) -> [T] {
        let directMatches = subviews.compactMap { $0 as? T }
        return directMatches + subviews.flatMap { $0.descendants(ofType: type) }
    }
}

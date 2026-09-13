import XCTest
import UIKit
@testable import DSEmu

final class TwoPhoneSetupViewControllerTests: XCTestCase {
    func testSetupOffersROMAndBothPhoneRoles() {
        let viewController = TwoPhoneSetupViewController(onComplete: { _ in })
        viewController.loadViewIfNeeded()

        XCTAssertNotNil(viewController.view.viewWithAccessibilityIdentifier("twoPhone.romPicker"))
        XCTAssertNotNil(viewController.view.viewWithAccessibilityIdentifier("twoPhone.controllerRole"))
        XCTAssertNotNil(viewController.view.viewWithAccessibilityIdentifier("twoPhone.displayRole"))
    }
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        return subviews.lazy.compactMap { $0.viewWithAccessibilityIdentifier(identifier) }.first
    }
}

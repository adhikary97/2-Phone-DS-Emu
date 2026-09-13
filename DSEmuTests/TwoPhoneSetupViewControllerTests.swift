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

    func testGamePickerOffersSavedGamesMenuAndImportAction() throws {
        let viewController = TwoPhoneSetupViewController(onComplete: { _ in })
        viewController.loadViewIfNeeded()

        let gameButton = try XCTUnwrap(
            viewController.view.viewWithAccessibilityIdentifier("twoPhone.romPicker") as? UIButton
        )

        XCTAssertTrue(gameButton.showsMenuAsPrimaryAction)
        XCTAssertTrue(gameButton.menu?.children.contains(where: {
            ($0 as? UIAction)?.title == "Import another game"
        }) == true)
    }
}

private extension UIView {
    func viewWithAccessibilityIdentifier(_ identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        return subviews.lazy.compactMap { $0.viewWithAccessibilityIdentifier(identifier) }.first
    }
}

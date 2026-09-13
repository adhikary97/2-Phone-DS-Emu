import XCTest
@testable import DSEmu

final class TwoPhoneProtocolTests: XCTestCase {
    func testEveryMessageRoundTrips() throws {
        let hash = Data((0..<32).map(UInt8.init))
        let digest = EmulatorDigest(frame: 60, state: 1, top: 2, bottom: 3)
        let messages: [TwoPhoneMessage] = [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(Data((0..<255).map(UInt8.init))),
            .ready,
            .input(DSInputFrame(frame: 19, keyMask: 0x0FFE, touchX: 128, touchY: 96, touchActive: true)),
            .acknowledgement(FrameAcknowledgement(frame: 59, digest: nil)),
            .acknowledgement(FrameAcknowledgement(frame: 60, digest: digest)),
            .finish(frame: 600, success: true, detail: "matched"),
            .finishAcknowledgement,
            .failure("intentional test failure"),
        ]

        for message in messages {
            XCTAssertEqual(try TwoPhoneMessage.decode(payload: message.encodedPayload()), message)
        }
    }

    func testDecoderRejectsTrailingBytes() throws {
        var encoded = try TwoPhoneMessage.ready.encodedPayload()
        encoded.append(42)
        XCTAssertThrowsError(try TwoPhoneMessage.decode(payload: encoded))
    }

    func testConfigurationAcceptsSplitAndInlineArguments() {
        let configuration = TwoPhoneConfiguration(arguments: [
            "app",
            "--two-phone-role=display",
            "--two-phone-host", "127.0.0.1",
            "--two-phone-port=49000",
            "--two-phone-autoload", "TestROM.nds",
            "--two-phone-test-frames=600",
            "--two-phone-checkpoint-interval", "30",
            "--two-phone-scripted-inputs",
        ])

        XCTAssertEqual(configuration.role, .display)
        XCTAssertEqual(configuration.host, "127.0.0.1")
        XCTAssertEqual(configuration.port, 49_000)
        XCTAssertEqual(configuration.autoloadROMName, "TestROM.nds")
        XCTAssertEqual(configuration.testFrameLimit, 600)
        XCTAssertEqual(configuration.checkpointInterval, 30)
        XCTAssertTrue(configuration.scriptedInputs)
    }

    func testIconLaunchUsesRememberedRoleAndROM() {
        let defaults = UserDefaults.standard
        let roleKey = "twoPhone.selectedRole"
        let romKey = "twoPhone.selectedROMName"
        let previousRole = defaults.string(forKey: roleKey)
        let previousROM = defaults.string(forKey: romKey)
        defer {
            defaults.set(previousRole, forKey: roleKey)
            defaults.set(previousROM, forKey: romKey)
        }

        defaults.set(TwoPhoneRole.display.rawValue, forKey: roleKey)
        defaults.set("TestROM.nds", forKey: romKey)

        let configuration = TwoPhoneConfiguration(arguments: ["TwoPhoneDS"])

        XCTAssertEqual(configuration.role, .display)
        XCTAssertEqual(configuration.autoloadROMName, "TestROM.nds")
        XCTAssertTrue(configuration.usesAutomaticDiscovery)
        XCTAssertFalse(configuration.requiresOnDeviceSetup)
    }

    func testLaunchArgumentsStillOverrideRememberedSetup() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = TwoPhonePreferences(defaults: defaults)
        preferences.save(role: .display, romName: "Remembered.nds")

        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-autoload", "CommandLine.nds",
        ], preferences: preferences)

        XCTAssertEqual(configuration.role, .controller)
        XCTAssertEqual(configuration.autoloadROMName, "CommandLine.nds")
        XCTAssertFalse(configuration.usesAutomaticDiscovery)
        XCTAssertFalse(configuration.requiresOnDeviceSetup)
    }

    func testScriptExercisesButtonAndTouchInputs() {
        XCTAssertEqual(TwoPhoneInputScript.input(frame: 1).keyMask, 0x0FFF)
        XCTAssertEqual(TwoPhoneInputScript.input(frame: 121).keyMask, 0x0FFE)
        XCTAssertNotEqual(TwoPhoneInputScript.input(frame: 241).keyMask, 0x0FFF)
        XCTAssertNotEqual(TwoPhoneInputScript.input(frame: 361).keyMask, 0x0FFF)
        XCTAssertEqual(
            TwoPhoneInputScript.input(frame: 421),
            DSInputFrame(frame: 421, keyMask: 0x0FFF, touchX: 128, touchY: 96, touchActive: true)
        )
    }
}

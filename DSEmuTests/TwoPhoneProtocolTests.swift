import XCTest
@testable import DSEmu

private final class BlockingMessageTransport: TwoPhoneMessageTransport {
    private enum TransportError: Error {
        case closed
    }

    let receiveDidStart = DispatchSemaphore(value: 0)
    private let closeDidFinish = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private(set) var isClosed = false

    func send(_ message: TwoPhoneMessage) throws {}

    func receive() throws -> TwoPhoneMessage {
        receiveDidStart.signal()
        _ = closeDidFinish.wait(timeout: .now() + 2)
        throw TransportError.closed
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        closeDidFinish.signal()
    }
}

private final class ScriptedMessageTransport: TwoPhoneMessageTransport {
    private enum ScriptError: Error {
        case noMessageAvailable
    }

    private var incoming: [TwoPhoneMessage]
    private(set) var sent: [TwoPhoneMessage] = []
    private(set) var isClosed = false

    init(incoming: [TwoPhoneMessage]) {
        self.incoming = incoming
    }

    func send(_ message: TwoPhoneMessage) throws {
        sent.append(message)
    }

    func receive() throws -> TwoPhoneMessage {
        guard !incoming.isEmpty else { throw ScriptError.noMessageAvailable }
        let message = incoming.removeFirst()
        return message
    }

    func close() {
        isClosed = true
    }
}

private final class GatedAcknowledgementTransport: TwoPhoneMessageTransport {
    private enum TransportError: Error {
        case closed
    }

    private let condition = NSCondition()
    private var initialMessages: [TwoPhoneMessage]
    private let finalFrame: UInt64
    private let digests: [UInt64: EmulatorDigest]
    private var allowedAcknowledgementFrame: UInt64 = 0
    private var nextAcknowledgementFrame: UInt64 = 1
    private var finishWasSent = false
    private var isClosed = false

    init(hash: Data, finalFrame: UInt64, digests: [UInt64: EmulatorDigest]) {
        initialMessages = [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
        ]
        self.finalFrame = finalFrame
        self.digests = digests
    }

    func releaseAcknowledgements(through frame: UInt64) {
        condition.lock()
        allowedAcknowledgementFrame = max(allowedAcknowledgementFrame, frame)
        condition.broadcast()
        condition.unlock()
    }

    func send(_ message: TwoPhoneMessage) throws {
        condition.lock()
        if case .finish = message {
            finishWasSent = true
            condition.broadcast()
        }
        condition.unlock()
    }

    func receive() throws -> TwoPhoneMessage {
        condition.lock()
        defer { condition.unlock() }

        if !initialMessages.isEmpty {
            return initialMessages.removeFirst()
        }

        while true {
            if isClosed { throw TransportError.closed }
            if nextAcknowledgementFrame <= min(allowedAcknowledgementFrame, finalFrame) {
                let frame = nextAcknowledgementFrame
                nextAcknowledgementFrame += 1
                return .acknowledgement(
                    FrameAcknowledgement(frame: frame, digest: digests[frame])
                )
            }
            if nextAcknowledgementFrame > finalFrame, finishWasSent {
                return .finishAcknowledgement
            }
            condition.wait()
        }
    }

    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }
}

final class TwoPhoneProtocolTests: XCTestCase {
    private enum ReconnectTestError: Error {
        case disconnected
    }

    func testEveryMessageRoundTrips() throws {
        let hash = Data((0..<32).map(UInt8.init))
        let digest = EmulatorDigest(frame: 60, state: 1, top: 2, bottom: 3)
        let messages: [TwoPhoneMessage] = [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(Data((0..<255).map(UInt8.init)), stateHash: 0x1234),
            .ready,
            .start,
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

    func testAcknowledgementRoundTripsDisplayFrameDuration() {
        let payload = Data([
            5,
            0, 0, 0, 0, 0, 0, 0, 42,
            0, 0, 0, 0, 0, 61, 9, 0,
            0,
        ])

        let roundTripped = try? TwoPhoneMessage.decode(payload: payload).encodedPayload()

        XCTAssertEqual(roundTripped, payload)
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

    func testReconnectLoopRetriesAfterAConnectionFailure() {
        let loop = TwoPhoneReconnectLoop(retryDelay: 0)
        let finished = expectation(description: "reconnect loop finished")
        let lock = NSLock()
        var attempts = 0

        DispatchQueue.global(qos: .userInitiated).async {
            loop.run {
                lock.lock()
                attempts += 1
                let attempt = attempts
                lock.unlock()

                if attempt == 1 {
                    throw ReconnectTestError.disconnected
                }
                loop.stop()
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 2)
        lock.lock()
        let finalAttempts = attempts
        lock.unlock()
        XCTAssertEqual(finalAttempts, 2)
    }

    func testReconnectLoopWaitsForForegroundBeforeRetrying() {
        let loop = TwoPhoneReconnectLoop(retryDelay: 0)
        let firstAttempt = expectation(description: "first synchronization attempt")
        let secondAttempt = expectation(description: "foreground synchronization attempt")
        let noBackgroundRetry = expectation(description: "no synchronization while backgrounded")
        noBackgroundRetry.isInverted = true
        let finished = expectation(description: "reconnect loop finished")
        let lock = NSLock()
        var attempts = 0

        DispatchQueue.global(qos: .userInitiated).async {
            loop.run {
                lock.lock()
                attempts += 1
                let attempt = attempts
                lock.unlock()

                if attempt == 1 {
                    firstAttempt.fulfill()
                    loop.didEnterBackground()
                    throw ReconnectTestError.disconnected
                }

                noBackgroundRetry.fulfill()
                secondAttempt.fulfill()
                loop.stop()
            }
            finished.fulfill()
        }

        wait(for: [firstAttempt], timeout: 1)
        wait(for: [noBackgroundRetry], timeout: 0.2)
        loop.willEnterForeground()
        wait(for: [secondAttempt, finished], timeout: 2)

        lock.lock()
        let finalAttempts = attempts
        lock.unlock()
        XCTAssertEqual(finalAttempts, 2)
    }

    func testCancellingSessionClosesTheActiveTransport() {
        let transport = BlockingMessageTransport()
        let finished = expectation(description: "cancelled session finished")
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-autoload", "TestROM.nds",
        ])
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: Data(repeating: 0, count: 32),
            makeSnapshot: { Data() },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(
                    frame: frame,
                    keyMask: 0x0FFF,
                    touchX: 0,
                    touchY: 0,
                    touchActive: false
                )
            },
            stepFrame: { _, _ in nil },
            status: { _ in },
            transportFactory: { transport }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? session.run()
            finished.fulfill()
        }

        XCTAssertEqual(transport.receiveDidStart.wait(timeout: .now() + 1), .success)
        session.cancel()
        wait(for: [finished], timeout: 2)
        XCTAssertTrue(transport.isClosed)
    }

    func testControllerKeepsEmulationPausedUntilSnapshotIsVerified() throws {
        let hash = Data(repeating: 7, count: 32)
        let snapshot = Data([1, 2, 3])
        let digest = EmulatorDigest(frame: 1, state: 10, top: 20, bottom: 30)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
            .acknowledgement(FrameAcknowledgement(frame: 1, digest: digest)),
            .finishAcknowledgement,
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "1",
            "--two-phone-checkpoint-interval", "1",
        ])
        var events: [String] = []
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: {
                events.append("snapshot")
                return snapshot
            },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { _, _ in
                events.append("step")
                return digest
            },
            status: { _ in },
            prepareForSynchronization: { events.append("pause") },
            snapshotStateHash: {
                events.append("hash")
                return 0x1234
            },
            resumeAfterSynchronization: { events.append("resume") },
            transportFactory: { transport }
        )

        let outcome = try session.run()

        XCTAssertTrue(outcome.success)
        XCTAssertEqual(events, ["pause", "snapshot", "hash", "resume", "step"])
        XCTAssertEqual(Array(transport.sent.prefix(3)), [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(snapshot, stateHash: 0x1234),
            .start,
        ])
    }

    func testControllerReportsDisplayProcessingTimeAtCheckpoint() throws {
        let hash = Data(repeating: 16, count: 32)
        let digest = EmulatorDigest(frame: 1, state: 61, top: 62, bottom: 63)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
            .acknowledgement(FrameAcknowledgement(
                frame: 1,
                digest: digest,
                processingNanoseconds: 12_500_000
            )),
            .finishAcknowledgement,
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "1",
            "--two-phone-checkpoint-interval", "1",
        ])
        var statuses: [String] = []
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data([1, 2, 3]) },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { _, _ in digest },
            status: { statuses.append($0) },
            snapshotStateHash: { 0x1234 },
            transportFactory: { transport }
        )

        _ = try session.run()

        XCTAssertTrue(statuses.contains { $0.contains("display avg 12.50 ms, max 12.50 ms") })
    }

    func testControllerAdvancesWithinFrameWindowWithoutWaitingForAcknowledgements() {
        let hash = Data(repeating: 13, count: 32)
        let finalDigest = EmulatorDigest(frame: 3, state: 17, top: 18, bottom: 19)
        let transport = GatedAcknowledgementTransport(
            hash: hash,
            finalFrame: 3,
            digests: [3: finalDigest]
        )
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "3",
            "--two-phone-checkpoint-interval", "60",
        ])
        let steppedThirdFrame = DispatchSemaphore(value: 0)
        let finished = expectation(description: "windowed session finished")
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data([1, 2, 3]) },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { input, createDigest in
                if input.frame == 3 { steppedThirdFrame.signal() }
                return createDigest ? finalDigest : nil
            },
            status: { _ in },
            snapshotStateHash: { 0x1234 },
            transportFactory: { transport }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? session.run()
            finished.fulfill()
        }

        XCTAssertEqual(steppedThirdFrame.wait(timeout: .now() + 0.3), .success)
        transport.releaseAcknowledgements(through: 3)
        wait(for: [finished], timeout: 2)
    }

    func testControllerStopsAtConfiguredFrameWindowUntilAnAcknowledgementArrives() {
        let hash = Data(repeating: 14, count: 32)
        let finalDigest = EmulatorDigest(frame: 3, state: 27, top: 28, bottom: 29)
        let transport = GatedAcknowledgementTransport(
            hash: hash,
            finalFrame: 3,
            digests: [3: finalDigest]
        )
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "3",
            "--two-phone-checkpoint-interval", "60",
            "--two-phone-frame-window", "2",
        ])
        let steppedSecondFrame = DispatchSemaphore(value: 0)
        let steppedThirdFrame = DispatchSemaphore(value: 0)
        let finished = expectation(description: "bounded session finished")
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data([1, 2, 3]) },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { input, createDigest in
                if input.frame == 2 { steppedSecondFrame.signal() }
                if input.frame == 3 { steppedThirdFrame.signal() }
                return createDigest ? finalDigest : nil
            },
            status: { _ in },
            snapshotStateHash: { 0x1234 },
            transportFactory: { transport }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? session.run()
            finished.fulfill()
        }

        XCTAssertEqual(steppedSecondFrame.wait(timeout: .now() + 0.3), .success)
        XCTAssertEqual(steppedThirdFrame.wait(timeout: .now() + 0.15), .timedOut)
        transport.releaseAcknowledgements(through: 1)
        XCTAssertEqual(steppedThirdFrame.wait(timeout: .now() + 0.3), .success)
        transport.releaseAcknowledgements(through: 3)
        wait(for: [finished], timeout: 2)
    }

    func testControllerDoesNotPipelinePastAnUnverifiedCheckpoint() throws {
        let hash = Data(repeating: 11, count: 32)
        let localDigest = EmulatorDigest(frame: 1, state: 100, top: 200, bottom: 300)
        let remoteDigest = EmulatorDigest(frame: 1, state: 101, top: 200, bottom: 300)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
            .acknowledgement(FrameAcknowledgement(frame: 1, digest: remoteDigest)),
            .finishAcknowledgement,
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "2",
            "--two-phone-checkpoint-interval", "1",
        ])
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data([1, 2, 3]) },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { _, _ in localDigest },
            status: { _ in },
            snapshotStateHash: { 0x1234 },
            transportFactory: { transport }
        )

        let outcome = try session.run()
        let inputFrames = transport.sent.compactMap { message -> UInt64? in
            guard case .input(let input) = message else { return nil }
            return input.frame
        }

        XCTAssertFalse(outcome.success)
        XCTAssertEqual(inputFrames, [1])
    }

    func testControllerClosesImmediatelyWhenPipelinedAcknowledgementIsOutOfSequence() {
        let hash = Data(repeating: 12, count: 32)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
            .acknowledgement(FrameAcknowledgement(frame: 0, digest: nil)),
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "controller",
            "--two-phone-test-frames", "2",
            "--two-phone-checkpoint-interval", "60",
        ])
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data([1, 2, 3]) },
            loadSnapshot: { _ in },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { _, _ in nil },
            status: { _ in },
            snapshotStateHash: { 0x1234 },
            transportFactory: { transport }
        )

        XCTAssertThrowsError(try session.run())
        XCTAssertFalse(transport.sent.contains { message in
            if case .finish = message { return true }
            return false
        })
        XCTAssertTrue(transport.isClosed)
    }

    func testDisplayRejectsMismatchedSnapshotBeforeResuming() {
        let hash = Data(repeating: 8, count: 32)
        let snapshot = Data([4, 5, 6])
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(snapshot, stateHash: 111),
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "display",
        ])
        var events: [String] = []
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data() },
            loadSnapshot: { _ in events.append("load") },
            inputProvider: { frame in
                DSInputFrame(frame: frame, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
            },
            stepFrame: { _, _ in
                events.append("step")
                return nil
            },
            status: { _ in },
            prepareForSynchronization: { events.append("pause") },
            snapshotStateHash: {
                events.append("hash")
                return 222
            },
            resumeAfterSynchronization: { events.append("resume") },
            transportFactory: { transport }
        )

        XCTAssertThrowsError(try session.run())
        XCTAssertEqual(events, ["pause", "load", "hash"])
        XCTAssertEqual(transport.sent, [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .failure("Loaded snapshot did not match controller state"),
        ])
    }

    func testDisplayResumesOnlyAfterControllerStartsVerifiedSnapshot() throws {
        let hash = Data(repeating: 9, count: 32)
        let snapshot = Data([7, 8, 9])
        let input = DSInputFrame(frame: 1, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
        let digest = EmulatorDigest(frame: 1, state: 40, top: 50, bottom: 60)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(snapshot, stateHash: 333),
            .start,
            .input(input),
            .finish(frame: 1, success: true, detail: "done"),
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "display",
            "--two-phone-checkpoint-interval", "1",
        ])
        var events: [String] = []
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data() },
            loadSnapshot: { _ in events.append("load") },
            inputProvider: { _ in input },
            stepFrame: { _, _ in
                events.append("step")
                return digest
            },
            status: { _ in },
            prepareForSynchronization: { events.append("pause") },
            snapshotStateHash: {
                events.append("hash")
                return 333
            },
            resumeAfterSynchronization: { events.append("resume") },
            transportFactory: { transport }
        )

        let outcome = try session.run()

        XCTAssertTrue(outcome.success)
        XCTAssertEqual(events, ["pause", "load", "hash", "resume", "step"])
        XCTAssertEqual(Array(transport.sent.prefix(2)), [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .ready,
        ])
    }

    func testDisplayReportsMeasuredFrameProcessingTime() throws {
        let hash = Data(repeating: 15, count: 32)
        let snapshot = Data([10, 11, 12])
        let input = DSInputFrame(frame: 1, keyMask: 0x0FFF, touchX: 0, touchY: 0, touchActive: false)
        let digest = EmulatorDigest(frame: 1, state: 51, top: 52, bottom: 53)
        let transport = ScriptedMessageTransport(incoming: [
            .hello(version: TwoPhoneMessage.protocolVersion, romSHA256: hash),
            .snapshot(snapshot, stateHash: 444),
            .start,
            .input(input),
            .finish(frame: 1, success: true, detail: "done"),
        ])
        let configuration = TwoPhoneConfiguration(arguments: [
            "TwoPhoneDS",
            "--two-phone-role", "display",
            "--two-phone-checkpoint-interval", "1",
        ])
        let session = TwoPhoneSession(
            configuration: configuration,
            romSHA256: hash,
            makeSnapshot: { Data() },
            loadSnapshot: { _ in },
            inputProvider: { _ in input },
            stepFrame: { _, _ in
                Thread.sleep(forTimeInterval: 0.002)
                return digest
            },
            status: { _ in },
            snapshotStateHash: { 444 },
            transportFactory: { transport }
        )

        _ = try session.run()

        let acknowledgement = try XCTUnwrap(transport.sent.compactMap { message -> FrameAcknowledgement? in
            guard case .acknowledgement(let acknowledgement) = message else { return nil }
            return acknowledgement
        }.first)
        XCTAssertGreaterThan(acknowledgement.processingNanoseconds, 1_000_000)
    }
}

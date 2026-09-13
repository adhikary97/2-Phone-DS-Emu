import Foundation

struct TwoPhoneSessionOutcome {
    let success: Bool
    let framesCompleted: UInt64
    let finalDigest: EmulatorDigest?
    let checkpointsCompared: Int
    let snapshotBytes: Int
    let detail: String
}

private final class ControllerMessageInbox {
    private enum InboxError: Error {
        case stopped
    }

    private let transport: any TwoPhoneMessageTransport
    private let condition = NSCondition()
    private var messages: [TwoPhoneMessage] = []
    private var terminalError: Error?
    private var isStopped = false

    init(transport: any TwoPhoneMessageTransport) {
        self.transport = transport
    }

    func start() {
        let thread = Thread { [weak self] in
            self?.readLoop()
        }
        thread.name = "DSEmu.Acknowledgements"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func next() throws -> TwoPhoneMessage {
        condition.lock()
        defer { condition.unlock() }

        while messages.isEmpty, terminalError == nil, !isStopped {
            condition.wait()
        }
        if !messages.isEmpty {
            return messages.removeFirst()
        }
        if let terminalError { throw terminalError }
        throw InboxError.stopped
    }

    func stop() {
        condition.lock()
        isStopped = true
        condition.broadcast()
        condition.unlock()
        transport.close()
    }

    private func readLoop() {
        while true {
            condition.lock()
            let shouldStop = isStopped
            condition.unlock()
            if shouldStop { return }

            do {
                let message = try transport.receive()
                condition.lock()
                if isStopped {
                    condition.unlock()
                    return
                }
                messages.append(message)
                let reachedEnd = message == .finishAcknowledgement
                if reachedEnd { isStopped = true }
                condition.broadcast()
                condition.unlock()
                if reachedEnd { return }
            } catch {
                condition.lock()
                if !isStopped {
                    terminalError = error
                    condition.broadcast()
                }
                condition.unlock()
                return
            }
        }
    }
}

private struct DisplayFrameTiming {
    private(set) var totalNanoseconds: UInt64 = 0
    private(set) var maximumNanoseconds: UInt64 = 0
    private(set) var frameCount: UInt64 = 0

    mutating func record(_ nanoseconds: UInt64) {
        totalNanoseconds += nanoseconds
        maximumNanoseconds = max(maximumNanoseconds, nanoseconds)
        frameCount += 1
    }

    var averageMilliseconds: Double {
        guard frameCount > 0 else { return 0 }
        return Double(totalNanoseconds) / Double(frameCount) / 1_000_000
    }

    var maximumMilliseconds: Double {
        Double(maximumNanoseconds) / 1_000_000
    }

    mutating func reset() {
        self = DisplayFrameTiming()
    }
}

final class TwoPhoneSession {
    private enum ControlError: Error {
        case cancelled
    }

    typealias SnapshotProvider = () throws -> Data
    typealias SnapshotLoader = (Data) throws -> Void
    typealias InputProvider = (UInt64) -> DSInputFrame
    typealias FrameStepper = (DSInputFrame, Bool) -> EmulatorDigest?
    typealias StatusHandler = (String) -> Void
    typealias LifecycleHandler = () -> Void
    typealias StateHashProvider = () -> UInt64
    typealias TransportFactory = () throws -> any TwoPhoneMessageTransport

    private let configuration: TwoPhoneConfiguration
    private let romSHA256: Data
    private let makeSnapshot: SnapshotProvider
    private let loadSnapshot: SnapshotLoader
    private let inputProvider: InputProvider
    private let stepFrame: FrameStepper
    private let status: StatusHandler
    private let prepareForSynchronization: LifecycleHandler
    private let snapshotStateHash: StateHashProvider
    private let resumeAfterSynchronization: LifecycleHandler
    private let transportFactory: TransportFactory?
    private let transportLock = NSLock()
    private var activeTransport: (any TwoPhoneMessageTransport)?
    private var isCancelled = false

    init(
        configuration: TwoPhoneConfiguration,
        romSHA256: Data,
        makeSnapshot: @escaping SnapshotProvider,
        loadSnapshot: @escaping SnapshotLoader,
        inputProvider: @escaping InputProvider,
        stepFrame: @escaping FrameStepper,
        status: @escaping StatusHandler,
        prepareForSynchronization: @escaping LifecycleHandler = {},
        snapshotStateHash: @escaping StateHashProvider = { 0 },
        resumeAfterSynchronization: @escaping LifecycleHandler = {},
        transportFactory: TransportFactory? = nil
    ) {
        self.configuration = configuration
        self.romSHA256 = romSHA256
        self.makeSnapshot = makeSnapshot
        self.loadSnapshot = loadSnapshot
        self.inputProvider = inputProvider
        self.stepFrame = stepFrame
        self.status = status
        self.prepareForSynchronization = prepareForSynchronization
        self.snapshotStateHash = snapshotStateHash
        self.resumeAfterSynchronization = resumeAfterSynchronization
        self.transportFactory = transportFactory
    }

    func cancel() {
        transportLock.lock()
        isCancelled = true
        let transport = activeTransport
        transportLock.unlock()
        transport?.close()
    }

    func run() throws -> TwoPhoneSessionOutcome {
        prepareForSynchronization()
        switch configuration.role {
        case .controller:
            return try runController()
        case .display:
            return try runDisplay()
        case .standalone:
            preconditionFailure("A standalone emulator cannot start a two-phone session")
        }
    }

    private func runController() throws -> TwoPhoneSessionOutcome {
        let transport = try makeControllerTransport()
        try activate(transport)
        defer {
            deactivateTransport()
            transport.close()
        }
        status("Display connected; validating ROM")

        try validateHello(transport.receive())
        try transport.send(.hello(version: TwoPhoneMessage.protocolVersion, romSHA256: romSHA256))

        let snapshot = try makeSnapshot()
        let expectedStateHash = snapshotStateHash()
        status("Sending shared snapshot (\(snapshot.count) bytes)")
        try transport.send(.snapshot(snapshot, stateHash: expectedStateHash))
        guard try transport.receive() == .ready else {
            throw TwoPhoneProtocolError.malformed("display did not acknowledge the snapshot")
        }
        try transport.send(.start)
        resumeAfterSynchronization()

        let inbox = ControllerMessageInbox(transport: transport)
        inbox.start()
        defer { inbox.stop() }

        status("Lockstep session running")
        var frame: UInt64 = 0
        var checkpoints = 0
        var lastDigest: EmulatorDigest?
        var pendingFrames: [(frame: UInt64, needsDigest: Bool, digest: EmulatorDigest?)] = []
        var displayFrameTiming = DisplayFrameTiming()
        let maximumInFlightFrames = configuration.frameWindow
        let targetFrameTime = 1.0 / 60.0

        while configuration.testFrameLimit.map({ frame < $0 }) ?? true {
            let frameStart = Date()

            while pendingFrames.count >= maximumInFlightFrames {
                if let failure = try receiveControllerAcknowledgement(
                    from: inbox,
                    pendingFrames: &pendingFrames,
                    checkpoints: &checkpoints,
                    lastDigest: &lastDigest,
                    displayFrameTiming: &displayFrameTiming
                ) {
                    return try finishController(
                        transport: transport,
                        receive: inbox.next,
                        frame: frame,
                        success: false,
                        localDigest: lastDigest,
                        checkpoints: checkpoints,
                        snapshotBytes: snapshot.count,
                        detail: failure
                    )
                }
            }

            frame += 1
            let input = inputProvider(frame)
            try transport.send(.input(input))

            let needsDigest = shouldCreateDigest(frame: frame)
            let localDigest = stepFrame(input, needsDigest)
            pendingFrames.append((frame: frame, needsDigest: needsDigest, digest: localDigest))

            if needsDigest {
                while !pendingFrames.isEmpty {
                    if let failure = try receiveControllerAcknowledgement(
                        from: inbox,
                        pendingFrames: &pendingFrames,
                        checkpoints: &checkpoints,
                        lastDigest: &lastDigest,
                        displayFrameTiming: &displayFrameTiming
                    ) {
                        return try finishController(
                            transport: transport,
                            receive: inbox.next,
                            frame: frame,
                            success: false,
                            localDigest: lastDigest,
                            checkpoints: checkpoints,
                            snapshotBytes: snapshot.count,
                            detail: failure
                        )
                    }
                }
            }

            let remaining = targetFrameTime - Date().timeIntervalSince(frameStart)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        }

        return try finishController(
            transport: transport,
            receive: inbox.next,
            frame: frame,
            success: true,
            localDigest: lastDigest,
            checkpoints: checkpoints,
            snapshotBytes: snapshot.count,
            detail: "All \(checkpoints) state and framebuffer checkpoints matched"
        )
    }

    private func finishController(
        transport: any TwoPhoneMessageTransport,
        receive: () throws -> TwoPhoneMessage,
        frame: UInt64,
        success: Bool,
        localDigest: EmulatorDigest?,
        checkpoints: Int,
        snapshotBytes: Int,
        detail: String
    ) throws -> TwoPhoneSessionOutcome {
        try transport.send(.finish(frame: frame, success: success, detail: detail))
        guard try receive() == .finishAcknowledgement else {
            throw TwoPhoneProtocolError.malformed("display did not acknowledge session completion")
        }
        status(success ? "Proof passed" : "Proof failed: \(detail)")
        return TwoPhoneSessionOutcome(
            success: success,
            framesCompleted: frame,
            finalDigest: localDigest,
            checkpointsCompared: checkpoints,
            snapshotBytes: snapshotBytes,
            detail: detail
        )
    }

    private func receiveControllerAcknowledgement(
        from inbox: ControllerMessageInbox,
        pendingFrames: inout [(frame: UInt64, needsDigest: Bool, digest: EmulatorDigest?)],
        checkpoints: inout Int,
        lastDigest: inout EmulatorDigest?,
        displayFrameTiming: inout DisplayFrameTiming
    ) throws -> String? {
        guard let pending = pendingFrames.first else {
            throw TwoPhoneProtocolError.malformed("received an acknowledgement with no pending frame")
        }
        guard case .acknowledgement(let acknowledgement) = try inbox.next() else {
            throw TwoPhoneProtocolError.malformed("expected acknowledgement for frame \(pending.frame)")
        }
        guard acknowledgement.frame == pending.frame else {
            throw TwoPhoneProtocolError.malformed(
                "display acknowledged frame \(acknowledgement.frame), expected \(pending.frame)"
            )
        }
        pendingFrames.removeFirst()
        displayFrameTiming.record(acknowledgement.processingNanoseconds)

        guard pending.needsDigest else { return nil }
        checkpoints += 1
        lastDigest = pending.digest
        guard let localDigest = pending.digest, let remoteDigest = acknowledgement.digest else {
            return "Missing determinism digest at frame \(pending.frame)"
        }
        guard localDigest == remoteDigest else {
            return "State mismatch at frame \(pending.frame): controller=\(localDigest), display=\(remoteDigest)"
        }
        status(String(
            format: "Checkpoint %llu matched — display avg %.2f ms, max %.2f ms",
            pending.frame,
            displayFrameTiming.averageMilliseconds,
            displayFrameTiming.maximumMilliseconds
        ))
        displayFrameTiming.reset()
        return nil
    }

    private func runDisplay() throws -> TwoPhoneSessionOutcome {
        let transport = try makeDisplayTransport()
        try activate(transport)
        defer {
            deactivateTransport()
            transport.close()
        }
        status("Connected; validating ROM")

        try transport.send(.hello(version: TwoPhoneMessage.protocolVersion, romSHA256: romSHA256))
        try validateHello(transport.receive())

        guard case .snapshot(let snapshot, let expectedStateHash) = try transport.receive() else {
            throw TwoPhoneProtocolError.malformed("controller did not send a shared snapshot")
        }
        status("Loading shared snapshot (\(snapshot.count) bytes)")
        try loadSnapshot(snapshot)
        guard snapshotStateHash() == expectedStateHash else {
            let detail = "Loaded snapshot did not match controller state"
            try transport.send(.failure(detail))
            throw TwoPhoneProtocolError.malformed(detail)
        }
        try transport.send(.ready)
        guard try transport.receive() == .start else {
            throw TwoPhoneProtocolError.malformed("controller did not start the verified snapshot")
        }
        resumeAfterSynchronization()

        var framesCompleted: UInt64 = 0
        var checkpoints = 0
        var lastDigest: EmulatorDigest?
        status("Lockstep session running")

        while true {
            switch try transport.receive() {
            case .input(let input):
                guard input.frame == framesCompleted + 1 else {
                    throw TwoPhoneProtocolError.malformed(
                        "received frame \(input.frame), expected \(framesCompleted + 1)"
                    )
                }
                let needsDigest = shouldCreateDigest(frame: input.frame)
                let processingStarted = DispatchTime.now().uptimeNanoseconds
                let digest = stepFrame(input, needsDigest)
                let processingNanoseconds = DispatchTime.now().uptimeNanoseconds - processingStarted
                framesCompleted = input.frame
                if needsDigest {
                    checkpoints += 1
                    lastDigest = digest
                }
                try transport.send(.acknowledgement(FrameAcknowledgement(
                    frame: input.frame,
                    digest: digest,
                    processingNanoseconds: processingNanoseconds
                )))

            case .finish(let frame, let success, let detail):
                guard frame == framesCompleted else {
                    throw TwoPhoneProtocolError.malformed(
                        "controller finished at frame \(frame), display is at \(framesCompleted)"
                    )
                }
                try transport.send(.finishAcknowledgement)
                status(success ? "Proof passed" : "Proof failed: \(detail)")
                return TwoPhoneSessionOutcome(
                    success: success,
                    framesCompleted: framesCompleted,
                    finalDigest: lastDigest,
                    checkpointsCompared: checkpoints,
                    snapshotBytes: snapshot.count,
                    detail: detail
                )

            case .failure(let detail):
                throw TwoPhoneProtocolError.malformed("controller failure: \(detail)")

            default:
                throw TwoPhoneProtocolError.malformed("unexpected message during display loop")
            }
        }
    }

    private func validateHello(_ message: TwoPhoneMessage) throws {
        guard case .hello(let version, let peerROMHash) = message else {
            throw TwoPhoneProtocolError.malformed("expected peer hello")
        }
        guard version == TwoPhoneMessage.protocolVersion else {
            throw TwoPhoneProtocolError.malformed(
                "protocol version mismatch: local \(TwoPhoneMessage.protocolVersion), peer \(version)"
            )
        }
        guard peerROMHash == romSHA256 else {
            throw TwoPhoneProtocolError.malformed("ROM SHA-256 mismatch")
        }
    }

    private func makeControllerTransport() throws -> any TwoPhoneMessageTransport {
        if let transportFactory { return try transportFactory() }
        if configuration.usesAutomaticDiscovery {
            return try BonjourTransport.acceptOne(status: status)
        }
        return try TCPSocketTransport.acceptOne(port: configuration.port, status: status)
    }

    private func makeDisplayTransport() throws -> any TwoPhoneMessageTransport {
        if let transportFactory { return try transportFactory() }
        if configuration.usesAutomaticDiscovery {
            return try BonjourTransport.connect(status: status)
        }
        return try TCPSocketTransport.connect(
            host: configuration.host,
            port: configuration.port,
            status: status
        )
    }

    private func activate(_ transport: any TwoPhoneMessageTransport) throws {
        transportLock.lock()
        guard !isCancelled else {
            transportLock.unlock()
            transport.close()
            throw ControlError.cancelled
        }
        activeTransport = transport
        transportLock.unlock()
    }

    private func deactivateTransport() {
        transportLock.lock()
        activeTransport = nil
        transportLock.unlock()
    }

    private func shouldCreateDigest(frame: UInt64) -> Bool {
        frame % configuration.checkpointInterval == 0 || configuration.testFrameLimit == frame
    }
}

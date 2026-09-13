import Foundation

struct TwoPhoneSessionOutcome {
    let success: Bool
    let framesCompleted: UInt64
    let finalDigest: EmulatorDigest?
    let checkpointsCompared: Int
    let snapshotBytes: Int
    let detail: String
}

final class TwoPhoneSession {
    typealias SnapshotProvider = () throws -> Data
    typealias SnapshotLoader = (Data) throws -> Void
    typealias InputProvider = (UInt64) -> DSInputFrame
    typealias FrameStepper = (DSInputFrame, Bool) -> EmulatorDigest?
    typealias StatusHandler = (String) -> Void

    private let configuration: TwoPhoneConfiguration
    private let romSHA256: Data
    private let makeSnapshot: SnapshotProvider
    private let loadSnapshot: SnapshotLoader
    private let inputProvider: InputProvider
    private let stepFrame: FrameStepper
    private let status: StatusHandler

    init(
        configuration: TwoPhoneConfiguration,
        romSHA256: Data,
        makeSnapshot: @escaping SnapshotProvider,
        loadSnapshot: @escaping SnapshotLoader,
        inputProvider: @escaping InputProvider,
        stepFrame: @escaping FrameStepper,
        status: @escaping StatusHandler
    ) {
        self.configuration = configuration
        self.romSHA256 = romSHA256
        self.makeSnapshot = makeSnapshot
        self.loadSnapshot = loadSnapshot
        self.inputProvider = inputProvider
        self.stepFrame = stepFrame
        self.status = status
    }

    func run() throws -> TwoPhoneSessionOutcome {
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
        defer { transport.close() }
        status("Display connected; validating ROM")

        try validateHello(transport.receive())
        try transport.send(.hello(version: TwoPhoneMessage.protocolVersion, romSHA256: romSHA256))

        let snapshot = try makeSnapshot()
        status("Sending shared snapshot (\(snapshot.count) bytes)")
        try transport.send(.snapshot(snapshot))
        guard try transport.receive() == .ready else {
            throw TwoPhoneProtocolError.malformed("display did not acknowledge the snapshot")
        }

        status("Lockstep session running")
        var frame: UInt64 = 0
        var checkpoints = 0
        var lastDigest: EmulatorDigest?
        let targetFrameTime = 1.0 / 60.0

        while configuration.testFrameLimit.map({ frame < $0 }) ?? true {
            let frameStart = Date()
            frame += 1
            let input = inputProvider(frame)
            try transport.send(.input(input))

            let needsDigest = shouldCreateDigest(frame: frame)
            let localDigest = stepFrame(input, needsDigest)
            guard case .acknowledgement(let acknowledgement) = try transport.receive() else {
                throw TwoPhoneProtocolError.malformed("expected acknowledgement for frame \(frame)")
            }
            guard acknowledgement.frame == frame else {
                return try finishController(
                    transport: transport,
                    frame: frame,
                    success: false,
                    localDigest: localDigest,
                    checkpoints: checkpoints,
                    snapshotBytes: snapshot.count,
                    detail: "Display acknowledged frame \(acknowledgement.frame), expected \(frame)"
                )
            }

            if needsDigest {
                checkpoints += 1
                lastDigest = localDigest
                guard let localDigest, let remoteDigest = acknowledgement.digest else {
                    return try finishController(
                        transport: transport,
                        frame: frame,
                        success: false,
                        localDigest: localDigest,
                        checkpoints: checkpoints,
                        snapshotBytes: snapshot.count,
                        detail: "Missing determinism digest at frame \(frame)"
                    )
                }
                guard localDigest == remoteDigest else {
                    return try finishController(
                        transport: transport,
                        frame: frame,
                        success: false,
                        localDigest: localDigest,
                        checkpoints: checkpoints,
                        snapshotBytes: snapshot.count,
                        detail: "State mismatch at frame \(frame): controller=\(localDigest), display=\(remoteDigest)"
                    )
                }
                status("Checkpoint \(frame) matched")
            }

            let remaining = targetFrameTime - Date().timeIntervalSince(frameStart)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        }

        return try finishController(
            transport: transport,
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
        frame: UInt64,
        success: Bool,
        localDigest: EmulatorDigest?,
        checkpoints: Int,
        snapshotBytes: Int,
        detail: String
    ) throws -> TwoPhoneSessionOutcome {
        try transport.send(.finish(frame: frame, success: success, detail: detail))
        guard try transport.receive() == .finishAcknowledgement else {
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

    private func runDisplay() throws -> TwoPhoneSessionOutcome {
        let transport = try makeDisplayTransport()
        defer { transport.close() }
        status("Connected; validating ROM")

        try transport.send(.hello(version: TwoPhoneMessage.protocolVersion, romSHA256: romSHA256))
        try validateHello(transport.receive())

        guard case .snapshot(let snapshot) = try transport.receive() else {
            throw TwoPhoneProtocolError.malformed("controller did not send a shared snapshot")
        }
        status("Loading shared snapshot (\(snapshot.count) bytes)")
        try loadSnapshot(snapshot)
        try transport.send(.ready)

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
                let digest = stepFrame(input, needsDigest)
                framesCompleted = input.frame
                if needsDigest {
                    checkpoints += 1
                    lastDigest = digest
                }
                try transport.send(.acknowledgement(FrameAcknowledgement(frame: input.frame, digest: digest)))

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
        if configuration.usesAutomaticDiscovery {
            return try BonjourTransport.acceptOne(status: status)
        }
        return try TCPSocketTransport.acceptOne(port: configuration.port, status: status)
    }

    private func makeDisplayTransport() throws -> any TwoPhoneMessageTransport {
        if configuration.usesAutomaticDiscovery {
            return try BonjourTransport.connect(status: status)
        }
        return try TCPSocketTransport.connect(
            host: configuration.host,
            port: configuration.port,
            status: status
        )
    }

    private func shouldCreateDigest(frame: UInt64) -> Bool {
        frame % configuration.checkpointInterval == 0 || configuration.testFrameLimit == frame
    }
}

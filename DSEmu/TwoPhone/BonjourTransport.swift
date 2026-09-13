import Foundation
import Network

enum BonjourTransportError: Error, CustomStringConvertible {
    case timedOut(String)
    case connectionFailed(String)
    case peerClosed
    case invalidFrameLength(Int)

    var description: String {
        switch self {
        case .timedOut(let action): return "Timed out while \(action)"
        case .connectionFailed(let detail): return "Local connection failed: \(detail)"
        case .peerClosed: return "Peer closed the synchronization connection"
        case .invalidFrameLength(let length): return "Invalid framed-message length: \(length)"
        }
    }
}

final class BonjourTransport: TwoPhoneMessageTransport {
    static let serviceType = "_twophonedsemu._tcp"
    static let serviceName = "TwoPhone DS Controller"

    private let connection: NWConnection
    private let queue: DispatchQueue

    private init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    deinit { close() }

    static func acceptOne(
        timeout: TimeInterval = 120,
        serviceName: String = BonjourTransport.serviceName,
        status: @escaping (String) -> Void
    ) throws -> BonjourTransport {
        let parameters = makeParameters()
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(
            name: serviceName,
            type: serviceType,
            domain: nil,
            txtRecord: nil
        )

        let queue = DispatchQueue(label: "com.dsemu.twophone.bonjour.listener")
        let result = SynchronousResult<BonjourTransport>()
        let acceptanceLock = NSLock()
        var hasAcceptedConnection = false

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                status("Ready — waiting for the display phone")
            case .waiting(let error):
                status("Waiting for local-network access: \(error)")
            case .failed(let error):
                result.resolve(.failure(.connectionFailed(String(describing: error))))
            default:
                break
            }
        }

        listener.newConnectionHandler = { candidate in
            acceptanceLock.lock()
            guard !hasAcceptedConnection else {
                acceptanceLock.unlock()
                candidate.cancel()
                return
            }
            hasAcceptedConnection = true
            acceptanceLock.unlock()

            status("Display found — connecting")
            candidate.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    result.resolve(.success(BonjourTransport(connection: candidate, queue: queue)))
                case .failed(let error):
                    result.resolve(.failure(.connectionFailed(String(describing: error))))
                default:
                    break
                }
            }
            candidate.start(queue: queue)
        }

        listener.start(queue: queue)
        defer { listener.cancel() }
        return try result.wait(
            timeout: timeout,
            timeoutError: .timedOut("waiting for the display phone")
        )
    }

    static func connect(
        timeout: TimeInterval = 120,
        serviceName: String? = nil,
        status: @escaping (String) -> Void
    ) throws -> BonjourTransport {
        let parameters = makeParameters()
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: parameters
        )
        let queue = DispatchQueue(label: "com.dsemu.twophone.bonjour.browser")
        let result = SynchronousResult<BonjourTransport>()
        let connectionLock = NSLock()
        var isConnecting = false

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                status("Searching nearby for the controller phone")
            case .waiting(let error):
                status("Waiting for local-network access: \(error)")
            case .failed(let error):
                result.resolve(.failure(.connectionFailed(String(describing: error))))
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { results, _ in
            let endpoint = results.lazy.map(\.endpoint).first { endpoint in
                guard let serviceName else { return true }
                guard case .service(let name, _, _, _) = endpoint else { return false }
                return name == serviceName
            }
            guard let endpoint else { return }

            connectionLock.lock()
            guard !isConnecting else {
                connectionLock.unlock()
                return
            }
            isConnecting = true
            connectionLock.unlock()

            status("Controller found — connecting")
            let connection = NWConnection(to: endpoint, using: parameters)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    result.resolve(.success(BonjourTransport(connection: connection, queue: queue)))
                case .failed(let error):
                    result.resolve(.failure(.connectionFailed(String(describing: error))))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        browser.start(queue: queue)
        defer { browser.cancel() }
        return try result.wait(
            timeout: timeout,
            timeoutError: .timedOut("finding the controller phone")
        )
    }

    func send(_ message: TwoPhoneMessage) throws {
        let payload = try message.encodedPayload()
        guard payload.count > 0, payload.count <= TwoPhoneMessage.maximumPayloadLength else {
            throw BonjourTransportError.invalidFrameLength(payload.count)
        }

        var framed = Data()
        let length = UInt32(payload.count)
        framed.append(UInt8(truncatingIfNeeded: length >> 24))
        framed.append(UInt8(truncatingIfNeeded: length >> 16))
        framed.append(UInt8(truncatingIfNeeded: length >> 8))
        framed.append(UInt8(truncatingIfNeeded: length))
        framed.append(payload)

        let completion = SynchronousResult<Void>()
        connection.send(content: framed, completion: .contentProcessed { error in
            if let error {
                completion.resolve(.failure(.connectionFailed(String(describing: error))))
            } else {
                completion.resolve(.success(()))
            }
        })
        _ = try completion.wait(
            timeout: 30,
            timeoutError: .timedOut("sending data to the other phone")
        )
    }

    func receive() throws -> TwoPhoneMessage {
        let header = try readExactly(count: 4)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= TwoPhoneMessage.maximumPayloadLength else {
            throw BonjourTransportError.invalidFrameLength(length)
        }
        return try TwoPhoneMessage.decode(payload: readExactly(count: length))
    }

    func close() {
        connection.cancel()
    }

    private func readExactly(count: Int) throws -> Data {
        var received = Data()
        while received.count < count {
            let next = try receiveChunk(maximumLength: count - received.count)
            guard !next.isEmpty else { throw BonjourTransportError.peerClosed }
            received.append(next)
        }
        return received
    }

    private func receiveChunk(maximumLength: Int) throws -> Data {
        let completion = SynchronousResult<Data>()
        connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) {
            data, _, isComplete, error in
            if let error {
                completion.resolve(.failure(.connectionFailed(String(describing: error))))
            } else if let data, !data.isEmpty {
                completion.resolve(.success(data))
            } else if isComplete {
                completion.resolve(.failure(.peerClosed))
            } else {
                completion.resolve(.failure(.connectionFailed("received an empty data chunk")))
            }
        }
        return try completion.wait(
            timeout: 120,
            timeoutError: .timedOut("waiting for data from the other phone")
        )
    }

    private static func makeParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }
}

private final class SynchronousResult<Value> {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, BonjourTransportError>?

    func resolve(_ newResult: Result<Value, BonjourTransportError>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = newResult
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval, timeoutError: BonjourTransportError) throws -> Value {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw timeoutError
        }
        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}

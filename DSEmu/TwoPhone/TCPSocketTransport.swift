import Darwin
import Foundation

enum SocketTransportError: Error, CustomStringConvertible {
    case systemCall(String, Int32)
    case peerClosed
    case invalidHost(String)
    case connectionTimedOut(String, UInt16)
    case invalidFrameLength(Int)

    var description: String {
        switch self {
        case .systemCall(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
        case .peerClosed: return "Peer closed the synchronization connection"
        case .invalidHost(let host): return "Invalid IPv4 peer address: \(host)"
        case .connectionTimedOut(let host, let port): return "Timed out connecting to \(host):\(port)"
        case .invalidFrameLength(let length): return "Invalid framed-message length: \(length)"
        }
    }
}

final class TCPSocketTransport: TwoPhoneMessageTransport {
    private var fileDescriptor: Int32

    private init(fileDescriptor: Int32) throws {
        self.fileDescriptor = fileDescriptor
        var enabled: Int32 = 1
        guard setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else {
            let code = errno
            Darwin.close(fileDescriptor)
            throw SocketTransportError.systemCall("setsockopt(SO_NOSIGPIPE)", code)
        }
    }

    deinit { close() }

    static func acceptOne(port: UInt16, status: (String) -> Void) throws -> TCPSocketTransport {
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw SocketTransportError.systemCall("socket", errno) }
        defer { Darwin.close(listener) }

        var reuse: Int32 = 1
        guard setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse))) == 0 else {
            throw SocketTransportError.systemCall("setsockopt(SO_REUSEADDR)", errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw SocketTransportError.systemCall("bind", errno) }
        guard Darwin.listen(listener, 1) == 0 else { throw SocketTransportError.systemCall("listen", errno) }

        status("Listening on TCP port \(port)")
        var peerAddress = sockaddr_in()
        var peerLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let peer = withUnsafeMutablePointer(to: &peerAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(listener, $0, &peerLength)
            }
        }
        guard peer >= 0 else { throw SocketTransportError.systemCall("accept", errno) }
        return try TCPSocketTransport(fileDescriptor: peer)
    }

    static func connect(host: String, port: UInt16, timeout: TimeInterval = 60, status: (String) -> Void) throws -> TCPSocketTransport {
        var targetAddress = in_addr()
        guard inet_pton(AF_INET, host, &targetAddress) == 1 else {
            throw SocketTransportError.invalidHost(host)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastStatus = Date.distantPast
        while Date() < deadline {
            let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw SocketTransportError.systemCall("socket", errno) }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = targetAddress

            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 { return try TCPSocketTransport(fileDescriptor: descriptor) }
            Darwin.close(descriptor)

            if Date().timeIntervalSince(lastStatus) >= 2 {
                status("Waiting for controller at \(host):\(port)")
                lastStatus = Date()
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw SocketTransportError.connectionTimedOut(host, port)
    }

    func send(_ message: TwoPhoneMessage) throws {
        let payload = try message.encodedPayload()
        guard payload.count > 0, payload.count <= TwoPhoneMessage.maximumPayloadLength else {
            throw SocketTransportError.invalidFrameLength(payload.count)
        }
        var framed = Data()
        let length = UInt32(payload.count)
        framed.append(UInt8(truncatingIfNeeded: length >> 24))
        framed.append(UInt8(truncatingIfNeeded: length >> 16))
        framed.append(UInt8(truncatingIfNeeded: length >> 8))
        framed.append(UInt8(truncatingIfNeeded: length))
        framed.append(payload)
        try writeAll(framed)
    }

    func receive() throws -> TwoPhoneMessage {
        let header = try readExactly(count: 4)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= TwoPhoneMessage.maximumPayloadLength else {
            throw SocketTransportError.invalidFrameLength(length)
        }
        return try TwoPhoneMessage.decode(payload: readExactly(count: length))
    }

    func close() {
        guard fileDescriptor >= 0 else { return }
        Darwin.shutdown(fileDescriptor, SHUT_RDWR)
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    private func writeAll(_ data: Data) throws {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { rawBuffer -> Int in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Darwin.send(fileDescriptor, base.advanced(by: offset), bytes.count - offset, 0)
            }
            if sent < 0 {
                if errno == EINTR { continue }
                throw SocketTransportError.systemCall("send", errno)
            }
            if sent == 0 { throw SocketTransportError.peerClosed }
            offset += sent
        }
    }

    private func readExactly(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Darwin.recv(fileDescriptor, base.advanced(by: offset), count - offset, 0)
            }
            if received < 0 {
                if errno == EINTR { continue }
                throw SocketTransportError.systemCall("recv", errno)
            }
            if received == 0 { throw SocketTransportError.peerClosed }
            offset += received
        }
        return Data(bytes)
    }
}

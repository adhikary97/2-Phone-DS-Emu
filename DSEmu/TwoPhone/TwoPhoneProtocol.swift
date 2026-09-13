import Foundation

enum TwoPhoneProtocolError: Error, CustomStringConvertible {
    case malformed(String)
    case unsupportedMessage(UInt8)
    case oversizedMessage(Int)

    var description: String {
        switch self {
        case .malformed(let detail): return "Malformed two-phone message: \(detail)"
        case .unsupportedMessage(let type): return "Unsupported two-phone message type: \(type)"
        case .oversizedMessage(let length): return "Two-phone message is too large: \(length) bytes"
        }
    }
}

struct DSInputFrame: Equatable {
    let frame: UInt64
    let keyMask: UInt16
    let touchX: UInt16
    let touchY: UInt16
    let touchActive: Bool
}

struct EmulatorDigest: Equatable, Codable {
    let frame: UInt64
    let state: UInt64
    let top: UInt64
    let bottom: UInt64
}

struct FrameAcknowledgement: Equatable {
    let frame: UInt64
    let digest: EmulatorDigest?
}

enum TwoPhoneMessage: Equatable {
    static let protocolVersion: UInt16 = 1
    static let maximumPayloadLength = 40 * 1024 * 1024

    case hello(version: UInt16, romSHA256: Data)
    case snapshot(Data)
    case ready
    case input(DSInputFrame)
    case acknowledgement(FrameAcknowledgement)
    case finish(frame: UInt64, success: Bool, detail: String)
    case finishAcknowledgement
    case failure(String)

    private enum MessageType: UInt8 {
        case hello = 1
        case snapshot = 2
        case ready = 3
        case input = 4
        case acknowledgement = 5
        case finish = 6
        case finishAcknowledgement = 7
        case failure = 255
    }

    func encodedPayload() throws -> Data {
        var writer = ByteWriter()
        switch self {
        case .hello(let version, let romSHA256):
            guard romSHA256.count == 32 else {
                throw TwoPhoneProtocolError.malformed("ROM SHA-256 must contain 32 bytes")
            }
            writer.append(MessageType.hello.rawValue)
            writer.append(version)
            writer.append(romSHA256)

        case .snapshot(let state):
            writer.append(MessageType.snapshot.rawValue)
            writer.append(state)

        case .ready:
            writer.append(MessageType.ready.rawValue)

        case .input(let input):
            writer.append(MessageType.input.rawValue)
            writer.append(input.frame)
            writer.append(input.keyMask)
            writer.append(input.touchActive ? UInt8(1) : UInt8(0))
            writer.append(input.touchX)
            writer.append(input.touchY)

        case .acknowledgement(let acknowledgement):
            writer.append(MessageType.acknowledgement.rawValue)
            writer.append(acknowledgement.frame)
            writer.append(acknowledgement.digest == nil ? UInt8(0) : UInt8(1))
            if let digest = acknowledgement.digest {
                writer.append(digest.state)
                writer.append(digest.top)
                writer.append(digest.bottom)
            }

        case .finish(let frame, let success, let detail):
            writer.append(MessageType.finish.rawValue)
            writer.append(frame)
            writer.append(success ? UInt8(1) : UInt8(0))
            try writer.appendString(detail)

        case .finishAcknowledgement:
            writer.append(MessageType.finishAcknowledgement.rawValue)

        case .failure(let detail):
            writer.append(MessageType.failure.rawValue)
            try writer.appendString(detail)
        }

        guard writer.data.count <= Self.maximumPayloadLength else {
            throw TwoPhoneProtocolError.oversizedMessage(writer.data.count)
        }
        return writer.data
    }

    static func decode(payload: Data) throws -> TwoPhoneMessage {
        guard payload.count <= maximumPayloadLength else {
            throw TwoPhoneProtocolError.oversizedMessage(payload.count)
        }
        var reader = ByteReader(data: payload)
        let rawType = try reader.readUInt8()
        guard let type = MessageType(rawValue: rawType) else {
            throw TwoPhoneProtocolError.unsupportedMessage(rawType)
        }

        let message: TwoPhoneMessage
        switch type {
        case .hello:
            message = .hello(version: try reader.readUInt16(), romSHA256: try reader.readData(count: 32))
        case .snapshot:
            message = .snapshot(try reader.readRemainingData())
        case .ready:
            message = .ready
        case .input:
            let frame = try reader.readUInt64()
            let keyMask = try reader.readUInt16()
            let active = try reader.readUInt8() != 0
            let x = try reader.readUInt16()
            let y = try reader.readUInt16()
            message = .input(DSInputFrame(frame: frame, keyMask: keyMask, touchX: x, touchY: y, touchActive: active))
        case .acknowledgement:
            let frame = try reader.readUInt64()
            let hasDigest = try reader.readUInt8() != 0
            let digest = hasDigest ? EmulatorDigest(
                frame: frame,
                state: try reader.readUInt64(),
                top: try reader.readUInt64(),
                bottom: try reader.readUInt64()
            ) : nil
            message = .acknowledgement(FrameAcknowledgement(frame: frame, digest: digest))
        case .finish:
            message = .finish(
                frame: try reader.readUInt64(),
                success: try reader.readUInt8() != 0,
                detail: try reader.readString()
            )
        case .finishAcknowledgement:
            message = .finishAcknowledgement
        case .failure:
            message = .failure(try reader.readString())
        }

        guard reader.isAtEnd else {
            throw TwoPhoneProtocolError.malformed("trailing bytes")
        }
        return message
    }
}

private struct ByteWriter {
    var data = Data()

    mutating func append(_ value: UInt8) { data.append(value) }
    mutating func append(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
    mutating func append(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
    mutating func append(_ bytes: Data) { data.append(bytes) }
    mutating func appendString(_ string: String) throws {
        let bytes = Data(string.utf8)
        guard bytes.count <= Int(UInt16.max) else {
            throw TwoPhoneProtocolError.malformed("text field exceeds 65535 bytes")
        }
        append(UInt16(bytes.count))
        append(bytes)
    }
}

private struct ByteReader {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw TwoPhoneProtocolError.malformed("unexpected end of payload") }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let high = UInt16(try readUInt8())
        let low = UInt16(try readUInt8())
        return (high << 8) | low
    }

    mutating func readUInt64() throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 { value = (value << 8) | UInt64(try readUInt8()) }
        return value
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw TwoPhoneProtocolError.malformed("byte field exceeds payload")
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readRemainingData() throws -> Data {
        try readData(count: data.count - offset)
    }

    mutating func readString() throws -> String {
        let byteCount = Int(try readUInt16())
        let bytes = try readData(count: byteCount)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw TwoPhoneProtocolError.malformed("invalid UTF-8")
        }
        return value
    }
}

import Foundation

enum TwoPhoneInputScript {
    /// A repeatable smoke-test sequence. It intentionally exercises both key
    /// and stylus serialization even when a game's boot sequence ignores them.
    static func input(frame: UInt64) -> DSInputFrame {
        var keyMask: UInt16 = 0x0FFF
        var touchActive = false
        var touchX: UInt16 = 0
        var touchY: UInt16 = 0

        switch frame {
        case 121...126:
            keyMask &= ~(1 << 0) // A
        case 241...246:
            keyMask &= ~(1 << 3) // Start
        case 361...372:
            keyMask &= ~(1 << 4) // Right
        case 421...432:
            touchActive = true
            touchX = 128
            touchY = 96
        default:
            break
        }

        return DSInputFrame(
            frame: frame,
            keyMask: keyMask,
            touchX: touchX,
            touchY: touchY,
            touchActive: touchActive
        )
    }
}


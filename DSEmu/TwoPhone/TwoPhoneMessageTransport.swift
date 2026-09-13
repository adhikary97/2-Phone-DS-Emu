import Foundation

protocol TwoPhoneMessageTransport: AnyObject {
    func send(_ message: TwoPhoneMessage) throws
    func receive() throws -> TwoPhoneMessage
    func close()
}

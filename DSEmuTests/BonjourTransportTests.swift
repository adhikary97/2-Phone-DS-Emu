import XCTest
@testable import DSEmu

final class BonjourTransportTests: XCTestCase {
    func testDiscoversPeerAndExchangesFramedMessages() throws {
        let serviceName = "TwoPhone DS Test \(UUID().uuidString)"
        let accepted = expectation(description: "controller accepted display")
        let lock = NSLock()
        var serverResult: Result<BonjourTransport, Error>?

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try BonjourTransport.acceptOne(timeout: 10, serviceName: serviceName, status: { _ in })
            }
            lock.lock()
            serverResult = result
            lock.unlock()
            accepted.fulfill()
        }

        let display = try BonjourTransport.connect(timeout: 10, serviceName: serviceName, status: { _ in })
        wait(for: [accepted], timeout: 12)
        lock.lock()
        let controller = try XCTUnwrap(serverResult).get()
        lock.unlock()
        defer {
            controller.close()
            display.close()
        }

        try display.send(.ready)
        XCTAssertEqual(try controller.receive(), .ready)
        try controller.send(.finishAcknowledgement)
        XCTAssertEqual(try display.receive(), .finishAcknowledgement)
    }
}

import Foundation

struct TwoPhoneTestReport: Codable {
    let role: TwoPhoneRole
    let success: Bool
    let framesCompleted: UInt64
    let elapsedSeconds: Double
    let framesPerSecond: Double
    let romSHA256: String
    let finalDigest: EmulatorDigest?
    let checkpointsCompared: Int
    let snapshotBytes: Int
    let detail: String
}

enum TwoPhoneTestReportWriter {
    static func write(_ report: TwoPhoneTestReport) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documents.appendingPathComponent("two-phone-result-\(report.role.rawValue).json")
            try data.write(to: url, options: .atomic)
            print("TWO_PHONE_TEST_RESULT \(report.role.rawValue) \(report.success ? "PASS" : "FAIL") \(url.path)")
        } catch {
            print("TWO_PHONE_TEST_RESULT_WRITE_FAILED \(error)")
        }
    }
}


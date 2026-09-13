import Foundation

final class SaveStateManager {
    static let shared = SaveStateManager()

    private var statesDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaveStates", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: statesDir, withIntermediateDirectories: true)
    }

    func saveState(slot: Int) -> Bool {
        let path = statesDir.appendingPathComponent("slot_\(slot).mst").path
        return melonds_save_state(path)
    }

    func loadState(slot: Int) -> Bool {
        let path = statesDir.appendingPathComponent("slot_\(slot).mst").path
        return melonds_load_state(path)
    }

    func stateExists(slot: Int) -> Bool {
        let path = statesDir.appendingPathComponent("slot_\(slot).mst").path
        return FileManager.default.fileExists(atPath: path)
    }

    func deleteState(slot: Int) {
        let path = statesDir.appendingPathComponent("slot_\(slot).mst")
        try? FileManager.default.removeItem(at: path)
    }
}

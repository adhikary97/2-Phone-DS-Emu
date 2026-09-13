import Foundation

final class TwoPhonePreferences {
    static let shared = TwoPhonePreferences()

    static let selectedRoleKey = "twoPhone.selectedRole"
    static let selectedROMNameKey = "twoPhone.selectedROMName"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedRole: TwoPhoneRole? {
        defaults.string(forKey: Self.selectedRoleKey).flatMap(TwoPhoneRole.init(rawValue:))
    }

    var selectedROMName: String? {
        defaults.string(forKey: Self.selectedROMNameKey)
    }

    var hasCompletedSetup: Bool {
        guard let selectedRole, selectedRole != .standalone else { return false }
        return selectedROMName != nil
    }

    func save(role: TwoPhoneRole, romName: String) {
        precondition(role != .standalone)
        defaults.set(role.rawValue, forKey: Self.selectedRoleKey)
        defaults.set(romName, forKey: Self.selectedROMNameKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.selectedRoleKey)
        defaults.removeObject(forKey: Self.selectedROMNameKey)
    }

    func bestAvailableROMURL() -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        if let selectedROMName {
            let selectedURL = documents.appendingPathComponent(selectedROMName)
            if FileManager.default.fileExists(atPath: selectedURL.path) {
                return selectedURL
            }
        }

        if let recent = RecentROMs.shared.entries.first {
            return RecentROMs.shared.urlFor(recent)
        }

        return try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "nds" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .first
    }
}

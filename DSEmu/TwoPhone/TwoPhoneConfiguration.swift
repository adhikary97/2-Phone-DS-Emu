import Foundation

enum TwoPhoneRole: String, Codable {
    case standalone
    case controller
    case display
}

struct TwoPhoneConfiguration {
    private static var activeConfiguration: TwoPhoneConfiguration?

    static var current: TwoPhoneConfiguration {
        if let activeConfiguration { return activeConfiguration }
        let configuration = TwoPhoneConfiguration(arguments: ProcessInfo.processInfo.arguments)
        activeConfiguration = configuration
        return configuration
    }

    static func reloadFromProcessInfo() {
        activeConfiguration = TwoPhoneConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    let role: TwoPhoneRole
    let host: String
    let port: UInt16
    let autoloadROMName: String?
    let testFrameLimit: UInt64?
    let checkpointInterval: UInt64
    let frameWindow: Int
    let scriptedInputs: Bool
    let requiresOnDeviceSetup: Bool
    let usesAutomaticDiscovery: Bool

    var isTwoPhoneSession: Bool { role != .standalone }
    var isAutomatedProof: Bool { testFrameLimit != nil }

    init(arguments: [String], preferences: TwoPhonePreferences = .shared) {
        let roleArgument = Self.value(for: "--two-phone-role", in: arguments)
            .flatMap(TwoPhoneRole.init(rawValue:))
        role = roleArgument ?? preferences.selectedRole ?? .standalone
        host = Self.value(for: "--two-phone-host", in: arguments) ?? "127.0.0.1"
        port = UInt16(Self.value(for: "--two-phone-port", in: arguments) ?? "47391") ?? 47391
        autoloadROMName = Self.value(for: "--two-phone-autoload", in: arguments) ?? preferences.selectedROMName
        testFrameLimit = Self.value(for: "--two-phone-test-frames", in: arguments).flatMap(UInt64.init)
        checkpointInterval = max(
            1,
            Self.value(for: "--two-phone-checkpoint-interval", in: arguments).flatMap(UInt64.init) ?? 60
        )
        frameWindow = min(
            8,
            max(1, Self.value(for: "--two-phone-frame-window", in: arguments).flatMap(Int.init) ?? 4)
        )
        scriptedInputs = arguments.contains("--two-phone-scripted-inputs")
        requiresOnDeviceSetup = roleArgument == nil && !preferences.hasCompletedSetup
        usesAutomaticDiscovery = roleArgument == nil && preferences.hasCompletedSetup
    }

    func autoloadROMURL() -> URL? {
        guard let autoloadROMName else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(autoloadROMName)
    }

    private static func value(for key: String, in arguments: [String]) -> String? {
        if let inline = arguments.first(where: { $0.hasPrefix(key + "=") }) {
            return String(inline.dropFirst(key.count + 1))
        }
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

import Foundation

struct ROMEntry: Codable, Equatable {
    let name: String
    let path: String  // relative to Documents directory
}

final class RecentROMs {
    static let shared = RecentROMs()

    private let key = "recentROMs"
    private let maxRecents = 20

    private init() {}

    var entries: [ROMEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ROMEntry].self, from: data) else {
            return []
        }
        // Filter out entries whose files no longer exist
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return list.filter { FileManager.default.fileExists(atPath: docsDir.appendingPathComponent($0.path).path) }
    }

    func add(_ entry: ROMEntry) {
        var list = entries
        list.removeAll { $0 == entry }
        list.insert(entry, at: 0)
        if list.count > maxRecents { list = Array(list.prefix(maxRecents)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func urlFor(_ entry: ROMEntry) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(entry.path)
    }
}

import Foundation

enum SessionStore {
    private static var sessionsPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/sessions.json")
    }

    static func load() -> [Session] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionsPath)),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    static func markDone(id: String) {
        let url = URL(fileURLWithPath: sessionsPath)
        guard let data = try? Data(contentsOf: url),
              var entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        for i in entries.indices where (entries[i]["id"] as? String) == id {
            entries[i]["status"] = "done"
        }
        guard let updated = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) else {
            return
        }
        try? updated.write(to: url)
    }
}

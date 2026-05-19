import Foundation

enum SessionStore {
    private static var sessionsURL: URL {
        URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/sessions.json"))
    }

    static func load() -> [Session] {
        load(from: sessionsURL)
    }

    static func load(from url: URL) -> [Session] {
        guard let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else {
            return []
        }
        return sessions.sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
    }

    static func markDone(id: String) {
        setStatus(id: id, status: "done", in: sessionsURL)
    }

    static func markPending(id: String) {
        setStatus(id: id, status: "pending", in: sessionsURL)
    }

    static func delete(id: String) {
        delete(id: id, from: sessionsURL)
    }

    @discardableResult
    static func delete(id: String, from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              var entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }

        let originalCount = entries.count
        entries.removeAll { ($0["id"] as? String) == id }
        guard entries.count != originalCount,
              let updated = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) else {
            return false
        }
        try? updated.write(to: url)
        return true
    }

    @discardableResult
    static func setStatus(id: String, status: String, in url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              var entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }

        var changed = false
        for i in entries.indices where (entries[i]["id"] as? String) == id {
            entries[i]["status"] = status
            changed = true
        }
        guard changed,
              let updated = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) else {
            return false
        }
        try? updated.write(to: url)
        return true
    }
}

import Foundation

struct PerchConfig: Equatable {
    var terminal: String = "ghostty"
    var sortBy: String = "date"
    var maxSessions: Int = 20
    var showBadge: Bool = true

    static func load() -> PerchConfig {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/config")
        return load(fromFile: path)
    }

    static func load(fromFile path: String) -> PerchConfig {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return PerchConfig()
        }
        return parse(contents)
    }

    static func parse(_ contents: String) -> PerchConfig {
        var config = PerchConfig()
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "terminal": config.terminal = value
            case "sort-by": config.sortBy = value
            case "max-sessions": config.maxSessions = Int(value) ?? config.maxSessions
            case "show-badge": config.showBadge = value == "true"
            default: break
            }
        }
        return config
    }
}

import Foundation

enum LaunchAtLoginError: LocalizedError, Equatable {
    case launchctlFailed(arguments: [String], status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .launchctlFailed(arguments, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "launchctl \(arguments.joined(separator: " ")) failed with status \(status)"
            }
            return "launchctl \(arguments.joined(separator: " ")) failed with status \(status): \(detail)"
        }
    }
}

struct LaunchAtLoginManager {
    typealias LaunchctlRunner = (_ arguments: [String]) throws -> Void

    static let label = "com.resciencelab.perch"

    static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    static var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    static var currentExecutablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    static func isEnabled(plistURL: URL = plistURL) -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(
        _ enabled: Bool,
        executablePath: String = currentExecutablePath,
        plistURL: URL = plistURL,
        launchctl: LaunchctlRunner = runLaunchctl
    ) throws {
        if enabled {
            try enable(executablePath: executablePath, plistURL: plistURL, launchctl: launchctl)
        } else {
            try disable(plistURL: plistURL, launchctl: launchctl)
        }
    }

    static func enable(
        executablePath: String,
        plistURL: URL = plistURL,
        launchctl: LaunchctlRunner = runLaunchctl
    ) throws {
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistContents(executablePath: executablePath).write(to: plistURL, atomically: true, encoding: .utf8)

        do {
            try? launchctl(["bootout", "gui/\(getuid())", plistURL.path])
            try launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
            try launchctl(["enable", "gui/\(getuid())/\(label)"])
        } catch {
            try? FileManager.default.removeItem(at: plistURL)
            throw error
        }
    }

    static func disable(plistURL: URL = plistURL, launchctl: LaunchctlRunner = runLaunchctl) throws {
        try? launchctl(["bootout", "gui/\(getuid())", plistURL.path])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func plistContents(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscape(label))</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(executablePath))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }

    static func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stderr = Pipe()
        process.standardOutput = nil
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw LaunchAtLoginError.launchctlFailed(arguments: arguments, status: process.terminationStatus, stderr: message)
        }
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

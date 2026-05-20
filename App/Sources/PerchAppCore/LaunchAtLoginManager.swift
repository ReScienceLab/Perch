import Darwin
import Foundation

enum LaunchAtLoginError: LocalizedError, Equatable {
    case executableNotFound(String)
    case executableNotExecutable(String)
    case launchctlFailed(arguments: [String], status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            return "Perch app executable does not exist: \(path)"
        case let .executableNotExecutable(path):
            return "Perch app executable is not executable: \(path)"
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
        try validateExecutable(at: executablePath)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistContents(executablePath: executablePath).write(to: plistURL, atomically: true, encoding: .utf8)

        do {
            try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
            if isCurrentProcess(executablePath: executablePath) {
                return
            }
            try launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
            try launchctl(["enable", "gui/\(getuid())/\(label)"])
            terminateDuplicateInstances(executablePath: executablePath)
        } catch {
            try? FileManager.default.removeItem(at: plistURL)
            throw error
        }
    }

    static func disable(plistURL: URL = plistURL, launchctl: LaunchctlRunner = runLaunchctl) throws {
        try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func validateExecutable(at path: String, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: path) else {
            throw LaunchAtLoginError.executableNotFound(path)
        }
        guard fileManager.isExecutableFile(atPath: path) else {
            throw LaunchAtLoginError.executableNotExecutable(path)
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
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    private static func isCurrentProcess(executablePath: String) -> Bool {
        guard !currentExecutablePath.isEmpty else { return false }
        return pathsReferToSameFile(currentExecutablePath, executablePath)
    }

    private static func terminateDuplicateInstances(executablePath: String, keepingPID: Int32 = getpid()) {
        for pid in runningPerchAppPIDs() where pid != keepingPID {
            guard let path = processExecutablePath(pid), pathsReferToSameFile(path, executablePath) else { continue }
            Darwin.kill(pid, SIGTERM)
        }
    }

    private static func runningPerchAppPIDs() -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "PerchApp"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func processExecutablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func pathsReferToSameFile(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).resolvingSymlinksInPath().standardizedFileURL.path ==
            URL(fileURLWithPath: rhs).resolvingSymlinksInPath().standardizedFileURL.path
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

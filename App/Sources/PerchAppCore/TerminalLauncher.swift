import AppKit
import Foundation

enum TerminalLaunchAction: Equatable {
    case process(executablePath: String, arguments: [String])
    case appleScript(String)
}

enum TerminalLauncher {
    static func open(session: Session, terminal: String) {
        perform(launchAction(for: session, terminal: terminal))
    }

    static func launchAction(for session: Session, terminal: String) -> TerminalLaunchAction {
        let dir = escapeForShell(session.workingDir)
        let cmd = escapeForShell(session.resumeCmd)

        switch terminal.lowercased() {
        case "ghostty":
            return .process(
                executablePath: "/usr/bin/env",
                arguments: [
                    "ghostty",
                    "--command=bash -c \"cd '\(dir)' && \(cmd); exec bash\""
                ]
            )
        case "warp":
            return .appleScript(warpScript(workingDir: dir, resumeCmd: cmd))
        case "iterm2", "iterm":
            return .appleScript(iTermScript(workingDir: dir, resumeCmd: cmd))
        case "terminal":
            return .appleScript(terminalAppScript(workingDir: dir, resumeCmd: cmd))
        default:
            return .appleScript(terminalAppScript(workingDir: dir, resumeCmd: cmd))
        }
    }

    static func escapeForShell(_ str: String) -> String {
        str.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func perform(_ action: TerminalLaunchAction) {
        switch action {
        case let .process(executablePath, arguments):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            try? process.run()
        case let .appleScript(source):
            runAppleScript(source)
        }
    }

    private static func warpScript(workingDir: String, resumeCmd: String) -> String {
        """
        tell application "Warp"
            activate
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Warp"
                keystroke "n" using {command down}
            end tell
        end tell
        delay 1
        tell application "System Events"
            tell process "Warp"
                keystroke "cd '\(workingDir)' && \(resumeCmd)"
                key code 36
            end tell
        end tell
        """
    }

    private static func iTermScript(workingDir: String, resumeCmd: String) -> String {
        """
        tell application "iTerm"
            create window with default profile command "cd '\(workingDir)' && \(resumeCmd)"
        end tell
        """
    }

    private static func terminalAppScript(workingDir: String, resumeCmd: String) -> String {
        """
        tell application "Terminal"
            do script "cd '\(workingDir)' && \(resumeCmd)"
        end tell
        """
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}

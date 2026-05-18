import AppKit
import Foundation

enum TerminalLauncher {
    static func open(session: Session, terminal: String) {
        let dir = escapeForShell(session.workingDir)
        let cmd = escapeForShell(session.resumeCmd)

        switch terminal.lowercased() {
        case "ghostty":
            openGhostty(workingDir: dir, resumeCmd: cmd)
        case "warp":
            openWarp(workingDir: dir, resumeCmd: cmd)
        case "iterm2", "iterm":
            openITerm(workingDir: dir, resumeCmd: cmd)
        case "terminal":
            openTerminalApp(workingDir: dir, resumeCmd: cmd)
        default:
            openTerminalApp(workingDir: dir, resumeCmd: cmd)
        }
    }

    private static func escapeForShell(_ str: String) -> String {
        str.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func openGhostty(workingDir: String, resumeCmd: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ghostty",
            "--command=bash -c \"cd '\(workingDir)' && \(resumeCmd); exec bash\""
        ]
        try? process.run()
    }

    private static func openWarp(workingDir: String, resumeCmd: String) {
        let script = """
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
        runAppleScript(script)
    }

    private static func openITerm(workingDir: String, resumeCmd: String) {
        let script = """
        tell application "iTerm"
            create window with default profile command "cd '\(workingDir)' && \(resumeCmd)"
        end tell
        """
        runAppleScript(script)
    }

    private static func openTerminalApp(workingDir: String, resumeCmd: String) {
        let script = """
        tell application "Terminal"
            do script "cd '\(workingDir)' && \(resumeCmd)"
        end tell
        """
        runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}

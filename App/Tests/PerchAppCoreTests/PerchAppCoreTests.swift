import AppKit
import Foundation
import XCTest
@testable import PerchAppCore

final class PerchAppCoreTests: XCTestCase {
    private func tempFile(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchAppCoreTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func tempExecutable(_ name: String = "PerchApp") throws -> URL {
        let url = tempFile(name)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func sampleSession(
        id: String = UUID().uuidString,
        agent: String = "claude",
        sessionId: String = "session-id",
        workingDir: String = "/tmp/project",
        title: String = "Title",
        note: String = "",
        priority: String = "medium",
        status: String = "pending",
        createdAt: String = "2026-05-18T10:00:00Z",
        updatedAt: String? = nil,
        resumeCmd: String = "claude --resume session-id"
    ) -> Session {
        Session(
            id: id,
            agent: agent,
            sessionId: sessionId,
            workingDir: workingDir,
            title: title,
            note: note,
            priority: priority,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            resumeCmd: resumeCmd
        )
    }

    private func writeSessions(_ sessions: [Session], to url: URL) throws {
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: url)
    }

    func testSessionDecodesAndEncodesSnakeCaseKeys() throws {
        let json = """
        {
          "id": "id-1",
          "agent": "pi",
          "session_id": "native-session",
          "working_dir": "/tmp/project",
          "title": "Fix tests",
          "note": "note",
          "priority": "medium",
          "status": "pending",
          "created_at": "2026-05-18T10:00:00Z",
          "updated_at": "2026-05-18T11:00:00Z",
          "resume_cmd": "pi --session native-session"
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(Session.self, from: json)

        XCTAssertEqual(session.sessionId, "native-session")
        XCTAssertEqual(session.workingDir, "/tmp/project")
        XCTAssertEqual(session.createdAt, "2026-05-18T10:00:00Z")
        XCTAssertEqual(session.updatedAt, "2026-05-18T11:00:00Z")
        XCTAssertEqual(session.resumeCmd, "pi --session native-session")

        let encoded = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["session_id"] as? String, "native-session")
        XCTAssertEqual(object["working_dir"] as? String, "/tmp/project")
        XCTAssertEqual(object["created_at"] as? String, "2026-05-18T10:00:00Z")
        XCTAssertEqual(object["updated_at"] as? String, "2026-05-18T11:00:00Z")
        XCTAssertEqual(object["resume_cmd"] as? String, "pi --session native-session")
    }

    func testSessionStoreLoadReturnsEmptyForMissingOrInvalidFiles() throws {
        let missing = tempFile("missing-sessions.json")
        XCTAssertEqual(SessionStore.load(from: missing), [])

        let invalid = tempFile("invalid-sessions.json")
        try "not json".write(to: invalid, atomically: true, encoding: .utf8)
        XCTAssertEqual(SessionStore.load(from: invalid), [])
    }

    func testSessionStoreLoadSortsNewestFirstUsingUpdatedAtWhenPresent() throws {
        let url = tempFile("sessions.json")
        let older = sampleSession(
            id: "older",
            title: "Older",
            createdAt: "2026-05-17T10:00:00Z",
            updatedAt: "2026-05-19T10:00:00Z"
        )
        let newer = sampleSession(id: "newer", title: "Newer", createdAt: "2026-05-18T10:00:00Z")
        try writeSessions([newer, older], to: url)

        let loaded = SessionStore.load(from: url)

        XCTAssertEqual(loaded.map(\.id), ["older", "newer"])
    }

    func testSessionStoreSetStatusUpdatesMatchingEntryOnly() throws {
        let url = tempFile("sessions.json")
        let first = sampleSession(id: "first", title: "First", status: "pending")
        let second = sampleSession(id: "second", title: "Second", status: "pending")
        try writeSessions([first, second], to: url)

        let changed = SessionStore.setStatus(id: "first", status: "done", in: url)

        XCTAssertTrue(changed)
        let loaded = SessionStore.load(from: url).sorted { $0.id < $1.id }
        XCTAssertEqual(loaded[0].id, "first")
        XCTAssertEqual(loaded[0].status, "done")
        XCTAssertEqual(loaded[1].id, "second")
        XCTAssertEqual(loaded[1].status, "pending")
    }

    func testSessionStoreDeleteRemovesMatchingEntryOnly() throws {
        let url = tempFile("sessions.json")
        let first = sampleSession(id: "first", title: "First")
        let second = sampleSession(id: "second", title: "Second")
        try writeSessions([first, second], to: url)

        XCTAssertTrue(SessionStore.delete(id: "first", from: url))

        let loaded = SessionStore.load(from: url)
        XCTAssertEqual(loaded.map(\.id), ["second"])
    }

    func testSessionStoreDeleteReturnsFalseForNoMatchOrInvalidJson() throws {
        let noMatchURL = tempFile("sessions.json")
        let original = sampleSession(id: "only")
        try writeSessions([original], to: noMatchURL)
        let before = try Data(contentsOf: noMatchURL)

        XCTAssertFalse(SessionStore.delete(id: "missing", from: noMatchURL))
        XCTAssertEqual(try Data(contentsOf: noMatchURL), before)

        let invalidURL = tempFile("invalid.json")
        try "not json".write(to: invalidURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(SessionStore.delete(id: "only", from: invalidURL))
    }

    func testSessionStoreSetStatusReturnsFalseWithoutChangingFileForNoMatchOrInvalidJson() throws {
        let noMatchURL = tempFile("sessions.json")
        let original = sampleSession(id: "only", status: "pending")
        try writeSessions([original], to: noMatchURL)
        let before = try Data(contentsOf: noMatchURL)

        XCTAssertFalse(SessionStore.setStatus(id: "missing", status: "done", in: noMatchURL))
        XCTAssertEqual(try Data(contentsOf: noMatchURL), before)

        let invalidURL = tempFile("invalid.json")
        try "not json".write(to: invalidURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(SessionStore.setStatus(id: "only", status: "done", in: invalidURL))
    }

    func testConfigDefaultsForMissingFileAndParsesKnownKeys() throws {
        XCTAssertEqual(PerchConfig.load(fromFile: tempFile("missing-config").path), PerchConfig())

        let parsed = PerchConfig.parse("""
        # comment
        terminal = warp
        sort-by = priority
        max-sessions = 7
        show-badge = false
        unknown = ignored
        malformed line
        """)

        XCTAssertEqual(parsed.terminal, "warp")
        XCTAssertEqual(parsed.sortBy, "priority")
        XCTAssertEqual(parsed.maxSessions, 7)
        XCTAssertFalse(parsed.showBadge)
    }

    func testLaunchAtLoginManagerBuildsEscapedLaunchAgentPlist() {
        let plist = LaunchAtLoginManager.plistContents(executablePath: "/Applications/Perch & Friends/PerchApp")

        XCTAssertTrue(plist.contains("<string>com.resciencelab.perch</string>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("/Applications/Perch &amp; Friends/PerchApp"))
    }

    func testLaunchAtLoginManagerWritesAndRemovesPlist() throws {
        let plistURL = tempFile("com.resciencelab.perch.plist")
        let executable = try tempExecutable()
        var launchctlCalls: [[String]] = []
        let launchctl: LaunchAtLoginManager.LaunchctlRunner = { launchctlCalls.append($0) }

        try LaunchAtLoginManager.setEnabled(true, executablePath: executable.path, plistURL: plistURL, launchctl: launchctl)
        XCTAssertTrue(LaunchAtLoginManager.isEnabled(plistURL: plistURL))
        XCTAssertTrue(try String(contentsOf: plistURL).contains(executable.path))
        XCTAssertEqual(launchctlCalls.map(\.[0]), ["bootout", "bootstrap", "enable"])

        try LaunchAtLoginManager.setEnabled(false, plistURL: plistURL, launchctl: launchctl)
        XCTAssertFalse(LaunchAtLoginManager.isEnabled(plistURL: plistURL))
        XCTAssertEqual(launchctlCalls.last?.first, "bootout")
    }

    func testLaunchAtLoginManagerRemovesPlistWhenEnableFails() throws {
        let plistURL = tempFile("com.resciencelab.perch.plist")
        let executable = try tempExecutable()
        let launchctl: LaunchAtLoginManager.LaunchctlRunner = { arguments in
            if arguments.first == "bootstrap" {
                throw LaunchAtLoginError.launchctlFailed(arguments: arguments, status: 5, stderr: "boom")
            }
        }

        XCTAssertThrowsError(
            try LaunchAtLoginManager.setEnabled(true, executablePath: executable.path, plistURL: plistURL, launchctl: launchctl)
        ) { error in
            XCTAssertEqual(error as? LaunchAtLoginError, .launchctlFailed(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path], status: 5, stderr: "boom"))
        }
        XCTAssertFalse(LaunchAtLoginManager.isEnabled(plistURL: plistURL))
    }

    func testLaunchAtLoginManagerRejectsInvalidExecutable() throws {
        let missing = tempFile("missing-PerchApp")
        XCTAssertThrowsError(try LaunchAtLoginManager.validateExecutable(at: missing.path)) { error in
            XCTAssertEqual(error as? LaunchAtLoginError, .executableNotFound(missing.path))
        }

        let notExecutable = tempFile("not-executable")
        try "not executable".write(to: notExecutable, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LaunchAtLoginManager.validateExecutable(at: notExecutable.path)) { error in
            XCTAssertEqual(error as? LaunchAtLoginError, .executableNotExecutable(notExecutable.path))
        }
    }

    func testConfigInvalidMaxSessionsKeepsDefault() {
        let parsed = PerchConfig.parse("""
        max-sessions = not-a-number
        show-badge = true
        """)

        XCTAssertEqual(parsed.maxSessions, 20)
        XCTAssertTrue(parsed.showBadge)
    }

    func testTerminalLauncherEscapesShellStrings() {
        XCTAssertEqual(TerminalLauncher.escapeForShell("plain"), "plain")
        XCTAssertEqual(TerminalLauncher.escapeForShell("O'Neil"), "O'\\''Neil")
    }

    func testTerminalLauncherBuildsGhosttyProcessAction() throws {
        let session = sampleSession(
            workingDir: "/Users/o'hara/project",
            resumeCmd: "claude --resume abc"
        )

        guard case let .process(executablePath, arguments) = TerminalLauncher.launchAction(for: session, terminal: "Ghostty") else {
            return XCTFail("Expected a process action")
        }

        XCTAssertEqual(executablePath, "/usr/bin/env")
        XCTAssertEqual(arguments.first, "ghostty")
        XCTAssertEqual(arguments.count, 2)
        XCTAssertTrue(arguments[1].contains("cd '/Users/o'\\''hara/project'"))
        XCTAssertTrue(arguments[1].contains("claude --resume abc"))
    }

    func testTerminalLauncherBuildsAppleScriptActions() {
        let session = sampleSession(workingDir: "/tmp/project", resumeCmd: "pi --session abc")
        let cases: [(String, String)] = [
            ("warp", "tell application \"Warp\""),
            ("iterm", "tell application \"iTerm\""),
            ("iterm2", "tell application \"iTerm\""),
            ("terminal", "tell application \"Terminal\""),
            ("unknown", "tell application \"Terminal\"")
        ]

        for (terminal, expectedSnippet) in cases {
            guard case let .appleScript(script) = TerminalLauncher.launchAction(for: session, terminal: terminal) else {
                XCTFail("Expected AppleScript for \(terminal)")
                continue
            }
            XCTAssertTrue(script.contains(expectedSnippet), "\(terminal) script was: \(script)")
            XCTAssertTrue(script.contains("cd '/tmp/project' && pi --session abc"))
        }
    }

    func testStatusMenuLogicGroupsSessionsByVisibleStatus() {
        let pending = sampleSession(id: "pending", status: "pending")
        let done = sampleSession(id: "done", status: "done")
        let inProgress = sampleSession(id: "in-progress", status: "in-progress")

        let groups = StatusMenuLogic.sessionGroups(from: [pending, done, inProgress])

        XCTAssertEqual(groups.pending.map(\.id), ["pending"])
        XCTAssertEqual(groups.done.map(\.id), ["done"])
    }

    func testStatusMenuLogicMapsAgentIconResourceNames() {
        let cases: [(String, String)] = [
            ("claude", "claudecode"),
            ("codex", "codex"),
            ("Pi", "pi"),
            ("windsurf", "windsurf"),
            ("cursor", "cursor"),
            ("trae", "trae"),
            ("droid", "droid"),
            ("goose", "goose"),
            ("opencode", "opencode"),
            ("kiro", "kiro"),
            ("amp", "claudecode"),
            ("unknown", "claudecode")
        ]

        for (agent, expected) in cases {
            XCTAssertEqual(StatusMenuLogic.agentIconResourceName(for: agent), expected)
        }
    }

    func testStatusMenuLogicBuildsClipboardCommandWithWorkingDirectory() {
        let session = sampleSession(
            workingDir: "/Users/o'hara/My Project",
            resumeCmd: "claude --resume abc"
        )

        XCTAssertEqual(
            StatusMenuLogic.clipboardCommand(for: session),
            "cd '/Users/o'\\''hara/My Project' && claude --resume abc"
        )
    }

    func testStatusMenuLogicRelativeTimeHandlesSupportedDateFormats() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = try XCTUnwrap(formatter.date(from: "2026-05-18T12:00:00Z"))

        XCTAssertEqual(StatusMenuLogic.relativeTime(from: "not a date", now: now), "")
        XCTAssertEqual(StatusMenuLogic.relativeTime(from: "2026-05-18T11:30:00Z", now: now), "< 1h")
        XCTAssertEqual(StatusMenuLogic.relativeTime(from: "2026-05-18T07:00:00.000Z", now: now), "5h ago")
        XCTAssertEqual(StatusMenuLogic.relativeTime(from: "2026-05-16T12:00:00Z", now: now), "2d ago")
        XCTAssertEqual(StatusMenuLogic.relativeTime(from: "2026-05-18T13:00:00Z", now: now), "< 1h")
    }

    func testBundledAppIconLoads() {
        XCTAssertNotNil(PerchResources.appIcon())
    }

    func testStatusMenuControllerRebuildsEmptyMenuAndHidesBadge() {
        var config = PerchConfig()
        config.showBadge = true
        let controller = StatusMenuController(
            sessionLoader: { [] },
            configLoader: { config },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        XCTAssertEqual(controller.menu.items.first?.title, "No active sessions")
        XCTAssertEqual(controller.statusItem.button?.title, "")
        XCTAssertTrue(controller.menu.items.contains { $0.title == "Launch at Login" })
        XCTAssertTrue(controller.menu.items.contains { $0.title == "Open Config" })
        XCTAssertTrue(controller.menu.items.contains { $0.title == "GitHub Repository" })
        XCTAssertTrue(controller.menu.items.contains { $0.title == "Quit Perch" })
        XCTAssertNotNil(controller.loadStatusIcon())
    }

    func testStatusMenuControllerRendersPendingAndDoneSessionsWithBadgeAndSubmenus() {
        var config = PerchConfig()
        config.showBadge = true
        let pending = sampleSession(id: "pending", agent: "pi", title: "Pending", status: "pending")
        let done = sampleSession(id: "done", agent: "codex", title: "Done", status: "done")
        let controller = StatusMenuController(
            sessionLoader: { [pending, done] },
            configLoader: { config },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        let titles = controller.menu.items.map(\.title)
        XCTAssertTrue(titles[0].contains("Pending"))
        XCTAssertTrue(titles.contains("Completed"))
        XCTAssertTrue(titles.contains { $0.contains("Done") })
        XCTAssertEqual(controller.statusItem.button?.title, "1")
        XCTAssertNotNil(controller.menu.items[0].image)
        XCTAssertEqual(controller.menu.items[0].submenu?.items.first?.title, "Mark as Done")
        XCTAssertEqual(controller.menu.items[0].submenu?.items.last?.title, "Delete Session")

        let doneItem = try! XCTUnwrap(controller.menu.items.first { $0.title.contains("Done") })
        XCTAssertEqual(doneItem.submenu?.items.first?.title, "Reopen")
        XCTAssertEqual(doneItem.submenu?.items.last?.title, "Delete Session")
    }

    func testStatusMenuControllerTogglesLaunchAtLogin() throws {
        var enabled = false
        var requestedValues: [Bool] = []
        let controller = StatusMenuController(
            sessionLoader: { [] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            launchAtLoginGetter: { enabled },
            launchAtLoginSetter: { value in
                requestedValues.append(value)
                enabled = value
            },
            pasteboard: .withUniqueName(),
            watchFile: false
        )
        controller.rebuildMenu()

        let item = try XCTUnwrap(controller.menu.items.first { $0.title == "Launch at Login" })
        XCTAssertEqual(item.state, .off)

        controller.toggleLaunchAtLogin(item)

        XCTAssertEqual(requestedValues, [true])
        XCTAssertEqual(item.state, .on)
    }

    func testStatusMenuControllerOpenSessionCopiesResumeCommandAndShowsToast() {
        let pasteboard = NSPasteboard.withUniqueName()
        let session = sampleSession(
            workingDir: "/tmp/copy me",
            title: "Copy me",
            resumeCmd: "claude --resume copy-me"
        )
        var toastTitle: String?
        var toastCommand: String?
        let controller = StatusMenuController(
            sessionLoader: { [session] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            pasteboard: pasteboard,
            toastHandler: { title, command in
                toastTitle = title
                toastCommand = command
            },
            watchFile: false
        )
        controller.rebuildMenu()

        controller.openSession(controller.menu.items[0])

        XCTAssertEqual(pasteboard.string(forType: .string), "cd '/tmp/copy me' && claude --resume copy-me")
        XCTAssertEqual(toastTitle, "Copy me")
        XCTAssertEqual(toastCommand, "cd '/tmp/copy me' && claude --resume copy-me")
    }

    func testStatusMenuControllerDeleteSessionInvokesDeleter() {
        let session = sampleSession(id: "delete-me", title: "Delete me", status: "pending")
        var deletedIds: [String] = []
        let controller = StatusMenuController(
            sessionLoader: { [session] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            sessionDeleter: { deletedIds.append($0) },
            pasteboard: .withUniqueName(),
            watchFile: false
        )
        controller.rebuildMenu()

        let deleteItem = try! XCTUnwrap(controller.menu.items[0].submenu?.items.last)
        controller.deleteSession(deleteItem)

        XCTAssertEqual(deletedIds, ["delete-me"])
    }

    func testStatusMenuControllerMarkDoneAndMarkPendingInvokeStatusWriter() {
        let pending = sampleSession(id: "pending", title: "Pending", status: "pending")
        var writes: [(String, String)] = []
        let pendingController = StatusMenuController(
            sessionLoader: { [pending] },
            configLoader: { PerchConfig() },
            statusWriter: { writes.append(($0, $1)) },
            pasteboard: .withUniqueName(),
            watchFile: false
        )
        pendingController.rebuildMenu()

        let markDoneItem = try! XCTUnwrap(pendingController.menu.items[0].submenu?.items.first)
        pendingController.markDone(markDoneItem)

        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes[0].0, "pending")
        XCTAssertEqual(writes[0].1, "done")

        let done = sampleSession(id: "done", title: "Done", status: "done")
        let doneController = StatusMenuController(
            sessionLoader: { [done] },
            configLoader: { PerchConfig() },
            statusWriter: { writes.append(($0, $1)) },
            pasteboard: .withUniqueName(),
            watchFile: false
        )
        doneController.rebuildMenu()

        let doneSessionItem = try! XCTUnwrap(doneController.menu.items.first { $0.title.contains("Done") })
        let markPendingItem = try! XCTUnwrap(doneSessionItem.submenu?.items.first)
        doneController.markPending(markPendingItem)

        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[1].0, "done")
        XCTAssertEqual(writes[1].1, "pending")
    }
}

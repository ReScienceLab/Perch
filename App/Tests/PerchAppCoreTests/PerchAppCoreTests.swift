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
        XCTAssertEqual(launchctlCalls.map(\.[0]), ["bootout", "enable", "bootstrap", "enable"])

        try LaunchAtLoginManager.setEnabled(false, plistURL: plistURL, launchctl: launchctl)
        XCTAssertFalse(LaunchAtLoginManager.isEnabled(plistURL: plistURL))
        XCTAssertEqual(launchctlCalls.map(\.[0]), ["bootout", "enable", "bootstrap", "enable"])
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

    func testStatusMenuLogicLimitsVisibleCompletedSessions() {
        let sessions = (1...5).map { sampleSession(id: "done-\($0)", status: "done") }

        let completed = StatusMenuLogic.visibleCompletedSessions(from: sessions)

        XCTAssertEqual(completed.visible.map(\.id), ["done-1", "done-2", "done-3"])
        XCTAssertEqual(completed.hiddenCount, 2)
    }

    func testStatusMenuLogicExtractsProjectLabelFromPath() {
        XCTAssertEqual(StatusMenuLogic.projectLabel(from: "/Users/yilin/Developer/Perch"), "Perch")
        XCTAssertEqual(StatusMenuLogic.projectLabel(from: "/tmp/my-project"), "my-project")
        XCTAssertEqual(StatusMenuLogic.projectLabel(from: "/root"), "root")
        XCTAssertEqual(StatusMenuLogic.projectLabel(from: ""), "")
    }

    func testStatusMenuLogicGroupsByProjectPreservingSessionOrder() {
        let p1a = sampleSession(id: "p1a", workingDir: "/projects/alpha", title: "Alpha 1")
        let p1b = sampleSession(id: "p1b", workingDir: "/projects/alpha", title: "Alpha 2")
        let p2a = sampleSession(id: "p2a", workingDir: "/projects/beta", title: "Beta 1")

        let groups = StatusMenuLogic.groupedByProject(from: [p1a, p1b, p2a])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "alpha")
        XCTAssertEqual(groups[0].sessions.map(\.id), ["p1a", "p1b"])
        XCTAssertEqual(groups[1].label, "beta")
        XCTAssertEqual(groups[1].sessions.map(\.id), ["p2a"])
    }

    func testStatusMenuLogicGroupsByProjectSingleProjectProducesOneGroup() {
        let s1 = sampleSession(id: "s1", workingDir: "/projects/alpha")
        let s2 = sampleSession(id: "s2", workingDir: "/projects/alpha")

        let groups = StatusMenuLogic.groupedByProject(from: [s1, s2])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sessions.map(\.id), ["s1", "s2"])
    }

    func testStatusMenuLogicGroupsByFullPathWhenLabelsCollide() {
        let homeApp = sampleSession(id: "home", workingDir: "/Users/yilin/app")
        let tmpApp = sampleSession(id: "tmp", workingDir: "/tmp/app")

        let groups = StatusMenuLogic.groupedByProject(from: [homeApp, tmpApp])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "app")
        XCTAssertEqual(groups[0].sessions.map(\.id), ["home"])
        XCTAssertEqual(groups[1].label, "app")
        XCTAssertEqual(groups[1].sessions.map(\.id), ["tmp"])
    }

    func testStatusMenuLogicNormalizesProjectPathBeforeGrouping() {
        let s1 = sampleSession(id: "s1", workingDir: "/projects/alpha")
        let s2 = sampleSession(id: "s2", workingDir: "/projects/./alpha/")

        let groups = StatusMenuLogic.groupedByProject(from: [s1, s2])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sessions.map(\.id), ["s1", "s2"])
    }

    func testStatusMenuControllerRendersProjectHeadersForMultipleProjects() {
        let alpha = sampleSession(id: "a", workingDir: "/projects/Alpha", title: "Task A", status: "pending")
        let beta = sampleSession(id: "b", workingDir: "/projects/Beta", title: "Task B", status: "pending")
        let controller = StatusMenuController(
            sessionLoader: { [alpha, beta] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        let titles = controller.menu.items.map(\.title)
        XCTAssertTrue(titles.contains("Alpha"), "Expected project header 'Alpha' in \(titles)")
        XCTAssertTrue(titles.contains("Beta"), "Expected project header 'Beta' in \(titles)")
        let alphaIdx = try! XCTUnwrap(titles.firstIndex(of: "Alpha"))
        let taskAIdx = try! XCTUnwrap(titles.firstIndex { $0.contains("Task A") })
        let betaIdx = try! XCTUnwrap(titles.firstIndex(of: "Beta"))
        let taskBIdx = try! XCTUnwrap(titles.firstIndex { $0.contains("Task B") })
        XCTAssertLessThan(alphaIdx, taskAIdx)
        XCTAssertLessThan(betaIdx, taskBIdx)
    }

    func testStatusMenuControllerOmitsProjectHeadersForSingleProject() {
        let s1 = sampleSession(id: "s1", workingDir: "/projects/Perch", title: "Task 1", status: "pending")
        let s2 = sampleSession(id: "s2", workingDir: "/projects/Perch", title: "Task 2", status: "pending")
        let controller = StatusMenuController(
            sessionLoader: { [s1, s2] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        XCTAssertFalse(controller.menu.items.contains { $0.title == "Perch" && !$0.isEnabled },
                       "Should not add a project header when all sessions share one project")
        XCTAssertTrue(controller.menu.items[0].title.contains("Task 1"))
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
            ("hermes", "hermes"),
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

    func testStatusMenuLogicBuildsSessionTooltipWithFullContext() {
        let session = sampleSession(
            agent: "pi",
            sessionId: "pi-session",
            workingDir: "/Users/yilin/Developer/Perch",
            title: "Fix badge",
            note: "Watcher regression",
            status: "pending",
            resumeCmd: "pi --session pi-session"
        )

        let tooltip = StatusMenuLogic.sessionTooltip(for: session)

        XCTAssertTrue(tooltip.contains("Fix badge"))
        XCTAssertTrue(tooltip.contains("Note: Watcher regression"))
        XCTAssertTrue(tooltip.contains("Agent: pi"))
        XCTAssertTrue(tooltip.contains("Status: pending"))
        XCTAssertTrue(tooltip.contains("Session: pi-session"))
        XCTAssertTrue(tooltip.contains("Path: /Users/yilin/Developer/Perch"))
        XCTAssertTrue(tooltip.contains("Resume: cd '/Users/yilin/Developer/Perch' && pi --session pi-session"))
    }

    func testStatusMenuLogicDisplayTimestampPrefersUpdatedAt() {
        let updated = sampleSession(
            createdAt: "2026-05-16T12:00:00Z",
            updatedAt: "2026-05-18T11:30:00Z"
        )
        let createdOnly = sampleSession(createdAt: "2026-05-16T12:00:00Z")

        XCTAssertEqual(StatusMenuLogic.displayTimestamp(for: updated), "2026-05-18T11:30:00Z")
        XCTAssertEqual(StatusMenuLogic.displayTimestamp(for: createdOnly), "2026-05-16T12:00:00Z")
    }

    func testStatusMenuControllerUsesUpdatedAtForRelativeTime() {
        let session = sampleSession(
            title: "Recently updated",
            createdAt: "2026-05-16T12:00:00Z",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let controller = StatusMenuController(
            sessionLoader: { [session] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        XCTAssertTrue(controller.menu.items[0].title.contains("< 1h"), controller.menu.items[0].title)
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
        XCTAssertTrue(controller.menu.items[0].toolTip?.contains("Path: /tmp/project") == true)
        XCTAssertTrue(controller.menu.items[0].toolTip?.contains("Resume: cd '/tmp/project' && claude --resume session-id") == true)

        let doneItem = try! XCTUnwrap(controller.menu.items.first { $0.title.contains("Done") })
        XCTAssertEqual(doneItem.submenu?.items.first?.title, "Reopen")
        XCTAssertEqual(doneItem.submenu?.items.last?.title, "Delete Session")
    }

    func testStatusMenuControllerLimitsCompletedSessionsInMenu() {
        let done = (1...5).map { sampleSession(id: "done-\($0)", title: "Done \($0)", status: "done") }
        let controller = StatusMenuController(
            sessionLoader: { done },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            pasteboard: .withUniqueName(),
            watchFile: false
        )

        controller.rebuildMenu()

        let titles = controller.menu.items.map(\.title)
        XCTAssertTrue(titles.contains { $0.contains("Done 1") })
        XCTAssertTrue(titles.contains { $0.contains("Done 2") })
        XCTAssertTrue(titles.contains { $0.contains("Done 3") })
        XCTAssertFalse(titles.contains { $0.contains("Done 4") })
        XCTAssertFalse(titles.contains { $0.contains("Done 5") })
        XCTAssertTrue(titles.contains("2 older completed hidden"))
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

    func testStatusMenuControllerCopiesLaunchAtLoginFailureDiagnostics() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let expectedError = LaunchAtLoginError.launchctlFailed(
            arguments: ["bootstrap", "gui/501", "/tmp/perch.plist"],
            status: 5,
            stderr: "Input/output error"
        )
        let controller = StatusMenuController(
            sessionLoader: { [] },
            configLoader: { PerchConfig() },
            statusWriter: { _, _ in },
            launchAtLoginGetter: { false },
            launchAtLoginSetter: { _ in throw expectedError },
            pasteboard: pasteboard,
            watchFile: false
        )
        controller.rebuildMenu()

        let item = try XCTUnwrap(controller.menu.items.first { $0.title == "Launch at Login" })
        controller.toggleLaunchAtLogin(item)

        let diagnostics = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(diagnostics.contains("Perch Launch at Login failure diagnostics"))
        XCTAssertTrue(diagnostics.contains("Requested state: enabled"))
        XCTAssertTrue(diagnostics.contains("launchctl bootstrap gui/501 /tmp/perch.plist failed with status 5"))
        XCTAssertTrue(diagnostics.contains("LaunchAgent:"))
        XCTAssertTrue(diagnostics.contains("Launchctl domain:"))
        XCTAssertTrue(diagnostics.hasSuffix("\n"))
        XCTAssertEqual(item.state, .off)
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

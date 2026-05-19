import AppKit

public enum PerchResources {
    public static func appIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "app-icon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

enum StatusMenuLogic {
    static func sessionGroups(from sessions: [Session]) -> (pending: [Session], done: [Session]) {
        (pending: sessions.filter { $0.status == "pending" }, done: sessions.filter { $0.status == "done" })
    }

    static func agentIconResourceName(for agent: String) -> String {
        switch agent.lowercased() {
        case "claude": return "claudecode"
        case "codex": return "codex"
        case "pi": return "pi"
        case "windsurf": return "windsurf"
        case "cursor": return "cursor"
        case "trae": return "trae"
        case "droid": return "droid"
        case "goose": return "goose"
        case "opencode": return "opencode"
        case "kiro": return "kiro"
        case "amp": return "claudecode"
        default: return "claudecode"
        }
    }

    static func clipboardCommand(for session: Session) -> String {
        let dir = TerminalLauncher.escapeForShell(session.workingDir)
        return "cd '\(dir)' && \(session.resumeCmd)"
    }

    static func relativeTime(from iso8601: String, now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso8601)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso8601)
        }
        guard let createdAt = date else { return "" }

        let seconds = now.timeIntervalSince(createdAt)
        let hours = seconds / 3600
        let days = seconds / 86400

        if hours < 1 {
            return "< 1h"
        } else if days < 1 {
            return "\(Int(hours))h ago"
        } else {
            return "\(Int(days))d ago"
        }
    }
}

private class SessionMenuEntry: NSObject {
    let session: Session
    init(_ session: Session) {
        self.session = session
    }
}

public class StatusMenuController: NSObject, NSMenuDelegate {
    typealias SessionStatusWriter = (_ id: String, _ status: String) -> Void
    typealias SessionDeleter = (_ id: String) -> Void
    typealias LaunchAtLoginGetter = () -> Bool
    typealias LaunchAtLoginSetter = (_ enabled: Bool) throws -> Void

    let statusItem: NSStatusItem
    let menu: NSMenu
    private var fileWatcher: (any DispatchSourceFileSystemObject)?
    private let sessionsPath: String
    private let sessionLoader: () -> [Session]
    private let configLoader: () -> PerchConfig
    private let statusWriter: SessionStatusWriter
    private let sessionDeleter: SessionDeleter
    private let launchAtLoginGetter: LaunchAtLoginGetter
    private let launchAtLoginSetter: LaunchAtLoginSetter
    private let pasteboard: NSPasteboard
    private let toastHandler: ((String, String) -> Void)?
    private var toastPanel: NSPanel?

    public override convenience init() {
        self.init(watchFile: true)
    }

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        menu: NSMenu = NSMenu(),
        sessionsPath: String = (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/sessions.json"),
        sessionLoader: @escaping () -> [Session] = { SessionStore.load() },
        configLoader: @escaping () -> PerchConfig = { PerchConfig.load() },
        statusWriter: @escaping SessionStatusWriter = { id, status in
            if status == "done" {
                SessionStore.markDone(id: id)
            } else {
                SessionStore.markPending(id: id)
            }
        },
        sessionDeleter: @escaping SessionDeleter = { id in SessionStore.delete(id: id) },
        launchAtLoginGetter: @escaping LaunchAtLoginGetter = { LaunchAtLoginManager.isEnabled() },
        launchAtLoginSetter: @escaping LaunchAtLoginSetter = { enabled in try LaunchAtLoginManager.setEnabled(enabled) },
        pasteboard: NSPasteboard = .general,
        toastHandler: ((String, String) -> Void)? = nil,
        watchFile: Bool = true
    ) {
        self.statusItem = statusItem
        self.menu = menu
        self.sessionsPath = sessionsPath
        self.sessionLoader = sessionLoader
        self.configLoader = configLoader
        self.statusWriter = statusWriter
        self.sessionDeleter = sessionDeleter
        self.launchAtLoginGetter = launchAtLoginGetter
        self.launchAtLoginSetter = launchAtLoginSetter
        self.pasteboard = pasteboard
        self.toastHandler = toastHandler

        super.init()

        if let button = statusItem.button {
            button.image = loadStatusIcon()
            button.imagePosition = .imageLeft
        }

        menu.delegate = self
        statusItem.menu = menu

        if watchFile {
            setupFileWatcher()
        }
    }

    deinit {
        fileWatcher?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func setupFileWatcher() {
        let fd = Darwin.open(sessionsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        // No-op: menu is rebuilt fresh each time menuWillOpen fires
        source.setEventHandler {}
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileWatcher = source
    }

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    func rebuildMenu() {
        menu.removeAllItems()

        let config = configLoader()
        let sessions = sessionLoader()
        let groups = StatusMenuLogic.sessionGroups(from: sessions)
        let pending = groups.pending
        let done = groups.done

        if pending.isEmpty {
            let emptyItem = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for session in pending {
                menu.addItem(makeSessionItem(session, isDone: false))
            }
        }

        if !done.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let doneHeader = NSMenuItem(title: "Completed", action: nil, keyEquivalent: "")
            doneHeader.isEnabled = false
            doneHeader.attributedTitle = NSAttributedString(
                string: "Completed",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(doneHeader)
            for session in done {
                menu.addItem(makeSessionItem(session, isDone: true))
            }
        }

        updateBadge(count: pending.count, showBadge: config.showBadge)

        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLoginGetter() ? .on : .off
        menu.addItem(launchAtLoginItem)

        let configItem = NSMenuItem(
            title: "Open Config",
            action: #selector(openConfig),
            keyEquivalent: ","
        )
        configItem.target = self
        menu.addItem(configItem)

        let repoItem = NSMenuItem(
            title: "GitHub Repository",
            action: #selector(openRepo),
            keyEquivalent: ""
        )
        repoItem.target = self
        menu.addItem(repoItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Perch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    private func makeSessionItem(_ session: Session, isDone: Bool) -> NSMenuItem {
        let time = StatusMenuLogic.relativeTime(from: session.createdAt)
        let item = NSMenuItem(
            title: "\(session.title)  ·  \(time)",
            action: #selector(openSession(_:)),
            keyEquivalent: ""
        )
        item.image = agentIcon(for: session.agent)
        item.target = self
        if isDone {
            item.attributedTitle = NSAttributedString(
                string: "\(session.title)  ·  \(time)",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
            )
        }
        let entry = SessionMenuEntry(session)
        item.representedObject = entry

        let submenu = NSMenu()
        if isDone {
            let reopenItem = NSMenuItem(title: "Reopen", action: #selector(markPending(_:)), keyEquivalent: "")
            reopenItem.target = self
            reopenItem.representedObject = entry
            submenu.addItem(reopenItem)
        } else {
            let doneItem = NSMenuItem(title: "Mark as Done", action: #selector(markDone(_:)), keyEquivalent: "")
            doneItem.target = self
            doneItem.representedObject = entry
            submenu.addItem(doneItem)
        }
        submenu.addItem(NSMenuItem.separator())
        let deleteItem = NSMenuItem(title: "Delete Session", action: #selector(deleteSession(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = entry
        submenu.addItem(deleteItem)
        item.submenu = submenu
        return item
    }

    private func updateBadge(count: Int, showBadge: Bool) {
        guard let button = statusItem.button else { return }
        if showBadge && count > 0 {
            button.title = "\(count)"
        } else {
            button.title = ""
        }
    }

    @objc func openSession(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        let command = StatusMenuLogic.clipboardCommand(for: entry.session)
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        if let toastHandler {
            toastHandler(entry.session.title, command)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showCopiedToast(title: entry.session.title, command: command)
            }
        }
    }

    private func showCopiedToast(title sessionTitle: String, command: String) {
        toastPanel?.close()

        let padding: CGFloat = 20
        let width: CGFloat = 420
        let height: CGFloat = 90

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.93).cgColor
        bg.layer?.cornerRadius = 12

        let header = NSTextField(labelWithString: "✓  Copied")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = NSColor(white: 0.55, alpha: 1)
        header.frame = NSRect(x: padding, y: height - 30, width: width - padding * 2, height: 16)

        let titleLabel = NSTextField(labelWithString: sessionTitle)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: padding, y: height - 52, width: width - padding * 2, height: 18)

        let cmd = NSTextField(labelWithString: command)
        cmd.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cmd.textColor = NSColor(white: 0.5, alpha: 1)
        cmd.lineBreakMode = .byTruncatingMiddle
        cmd.frame = NSRect(x: padding, y: 16, width: width - padding * 2, height: 14)

        bg.addSubview(header)
        bg.addSubview(titleLabel)
        bg.addSubview(cmd)
        panel.contentView = bg

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: screen.midX - width / 2, y: screen.midY + screen.height * 0.12))
        panel.orderFront(nil)
        toastPanel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
                self?.toastPanel = nil
            })
        }
    }

    @objc func markDone(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        statusWriter(entry.session.id, "done")
        rebuildMenu()
    }

    @objc func markPending(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        statusWriter(entry.session.id, "pending")
        rebuildMenu()
    }

    @objc func deleteSession(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        sessionDeleter(entry.session.id)
        rebuildMenu()
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let nextValue = sender.state != .on
        do {
            try launchAtLoginSetter(nextValue)
            sender.state = nextValue ? .on : .off
        } catch {
            showCopiedToast(title: "Could Not Update Launch at Login", command: error.localizedDescription)
        }
    }

    func loadStatusIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: "perch-logo-2", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")
    }

    @objc private func openConfig() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/config")
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/ReScienceLab/Perch") {
            NSWorkspace.shared.open(url)
        }
    }

    private func agentIcon(for agent: String) -> NSImage? {
        let name = StatusMenuLogic.agentIconResourceName(for: agent)
        return loadAgentIcon(named: name) ?? loadAgentIcon(named: "claudecode")
    }

    private func loadAgentIcon(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        rep.size = NSSize(width: 14, height: 14)
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}

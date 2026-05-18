import AppKit

private class SessionMenuEntry: NSObject {
    let session: Session
    init(_ session: Session) {
        self.session = session
    }
}

class StatusMenuController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    private let menu: NSMenu
    private var fileWatcher: (any DispatchSourceFileSystemObject)?
    private let sessionsPath: String
    private var toastPanel: NSPanel?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        sessionsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/sessions.json")

        super.init()

        if let button = statusItem.button {
            button.image = loadStatusIcon()
            button.imagePosition = .imageLeft
        }

        menu.delegate = self
        statusItem.menu = menu

        setupFileWatcher()
    }

    deinit {
        fileWatcher?.cancel()
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

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let config = PerchConfig.load()
        let sessions = SessionStore.load()
        let pending = sessions.filter { $0.status == "pending" }
        let done    = sessions.filter { $0.status == "done" }

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
        let time = relativeTime(from: session.createdAt)
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

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.session.resumeCmd, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.showCopiedToast(title: entry.session.title, command: entry.session.resumeCmd)
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

    @objc private func markDone(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        SessionStore.markDone(id: entry.session.id)
        rebuildMenu()
    }

    @objc private func markPending(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        SessionStore.markPending(id: entry.session.id)
        rebuildMenu()
    }

    private func loadStatusIcon() -> NSImage? {
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
        let name: String
        switch agent.lowercased() {
        case "claude":    name = "claudecode"
        case "codex":     name = "codex"
        case "pi":        name = "pi"
        case "windsurf":  name = "windsurf"
        case "cursor":    name = "cursor"
        case "trae":      name = "trae"
        case "droid":     name = "droid"
        case "goose":     name = "goose"
        case "opencode":  name = "opencode"
        case "kiro":      name = "kiro"
        case "amp":       name = "amp"
        default:          name = "claudecode"
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        rep.size = NSSize(width: 14, height: 14)
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private func relativeTime(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso8601)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso8601)
        }
        guard let createdAt = date else { return "" }

        let seconds = Date().timeIntervalSince(createdAt)
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

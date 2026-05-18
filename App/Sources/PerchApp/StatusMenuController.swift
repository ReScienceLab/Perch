import AppKit

private class SessionMenuEntry: NSObject {
    let session: Session
    let terminal: String
    init(_ session: Session, terminal: String) {
        self.session = session
        self.terminal = terminal
    }
}

class StatusMenuController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    private let menu: NSMenu
    private var fileWatcher: (any DispatchSourceFileSystemObject)?
    private let sessionsPath: String

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        sessionsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/perch/sessions.json")

        super.init()

        if let button = statusItem.button {
            if let birdImage = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch") {
                button.image = birdImage
            } else {
                button.title = "P"
            }
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
        let pending = sessions.filter { $0.status != "done" }

        if pending.isEmpty {
            let emptyItem = NSMenuItem(title: "No saved sessions", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for session in pending {
                let emoji = agentEmoji(for: session.agent)
                let time = relativeTime(from: session.createdAt)
                let item = NSMenuItem(
                    title: "\(emoji) \(session.title)  ·  \(time)",
                    action: #selector(openSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                let entry = SessionMenuEntry(session, terminal: config.terminal)
                item.representedObject = entry

                let submenu = NSMenu()
                let markDoneItem = NSMenuItem(
                    title: "Mark as Done",
                    action: #selector(markDone(_:)),
                    keyEquivalent: ""
                )
                markDoneItem.target = self
                markDoneItem.representedObject = entry
                submenu.addItem(markDoneItem)
                item.submenu = submenu

                menu.addItem(item)
            }
        }

        updateBadge(count: pending.count, showBadge: config.showBadge)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Perch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
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
        TerminalLauncher.open(session: entry.session, terminal: entry.terminal)
    }

    @objc private func markDone(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? SessionMenuEntry else { return }
        SessionStore.markDone(id: entry.session.id)
        rebuildMenu()
    }

    private func agentEmoji(for agent: String) -> String {
        switch agent.lowercased() {
        case "claude": return "🤖"
        case "codex":  return "💡"
        case "pi":     return "🌀"
        default:       return "🤖"
        }
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

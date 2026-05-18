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
                let time = relativeTime(from: session.createdAt)
                let item = NSMenuItem(
                    title: "\(session.title)  ·  \(time)",
                    action: #selector(openSession(_:)),
                    keyEquivalent: ""
                )
                item.image = agentIcon(for: session.agent)
                item.target = self
                let entry = SessionMenuEntry(session)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.session.resumeCmd, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.showCopiedToast()
        }
    }

    private func showCopiedToast() {
        toastPanel?.close()

        let width: CGFloat = 130
        let height: CGFloat = 36

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.93).cgColor
        bg.layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: "✓  Copied")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 0, y: 0, width: width, height: height)
        label.alignment = .center
        bg.addSubview(label)

        panel.contentView = bg

        // Bottom-right corner, clear of the menu bar and Dock
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(NSPoint(x: screen.maxX - width - 16, y: screen.minY + 16))
        panel.orderFront(nil)
        toastPanel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
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

    private func agentIcon(for agent: String) -> NSImage? {
        let name: String
        switch agent.lowercased() {
        case "claude": name = "claudecode"
        case "codex":  name = "codex"
        case "pi":     name = "pi"
        default:       name = "claudecode"
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

import AppKit

class StatusMenuController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    private let menu: NSMenu

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

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
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

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
                    action: nil,
                    keyEquivalent: ""
                )
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Perch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
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

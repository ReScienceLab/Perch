import AppKit
import PerchAppCore

if CommandLine.arguments.contains("--version") {
    print("PerchApp 0.1.0")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let image = PerchResources.appIcon() {
    app.applicationIconImage = image
}

var controller = StatusMenuController()

app.run()

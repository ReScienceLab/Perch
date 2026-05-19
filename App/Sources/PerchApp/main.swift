import AppKit
import PerchAppCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let image = PerchResources.appIcon() {
    app.applicationIconImage = image
}

var controller = StatusMenuController()

app.run()

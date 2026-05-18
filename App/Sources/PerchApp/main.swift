import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var controller = StatusMenuController()

app.run()

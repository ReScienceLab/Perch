import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let url = Bundle.module.url(forResource: "app-icon", withExtension: "png"),
   let image = NSImage(contentsOf: url) {
    app.applicationIconImage = image
}

var controller = StatusMenuController()

app.run()

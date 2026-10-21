import AppKit

let app = NSApplication.shared
// Also set in Info.plist; needed here so the bare binary (swift run) stays out of the Dock too.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

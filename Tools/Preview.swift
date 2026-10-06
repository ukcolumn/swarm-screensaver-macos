//
//  Preview.swift
//  A tiny host app that loads the built .saver bundle into a normal window,
//  so the screensaver can be watched without installing it.
//
//  Usage: build/preview build/Swarm.saver [--fullscreen]
//

import AppKit
import ScreenSaver

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: preview <path to .saver> [--fullscreen]\n".utf8))
    exit(2)
}
let bundlePath = arguments[1]
let wantsFullScreen = arguments.contains("--fullscreen")

guard let bundle = Bundle(path: bundlePath), bundle.load() else {
    FileHandle.standardError.write(Data("could not load \(bundlePath)\n".utf8))
    exit(1)
}
guard let saverClass = bundle.principalClass as? ScreenSaverView.Type else {
    FileHandle.standardError.write(Data("bundle has no ScreenSaverView principal class\n".utf8))
    exit(1)
}

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    // Escape closes the preview, the way the real saver would give up.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let screen = NSScreen.main ?? NSScreen.screens[0]
let frame = wantsFullScreen
    ? screen.frame
    : NSRect(x: 0, y: 0, width: 1280, height: 800)

let window = PreviewWindow(contentRect: frame,
                           styleMask: wantsFullScreen ? [.borderless] : [.titled, .closable, .resizable],
                           backing: .buffered,
                           defer: false)
window.title = "Swarm preview (press Escape to quit)"
window.backgroundColor = .black
if wantsFullScreen {
    window.level = .mainMenu + 1
    window.setFrame(screen.frame, display: true)
}

guard let saver = saverClass.init(frame: NSRect(origin: .zero, size: frame.size), isPreview: false) else {
    FileHandle.standardError.write(Data("could not create the saver view\n".utf8))
    exit(1)
}
saver.autoresizingMask = [.width, .height]
window.contentView = saver
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
saver.startAnimation()

// Quit when the window is closed.
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let delegate = Delegate()
app.delegate = delegate
app.run()

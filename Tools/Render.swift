//
//  Render.swift
//  Runs a built .saver offscreen and writes PNGs, so the motion can be
//  checked without taking over the display.
//
//  Usage: build/render <path to .saver> <out dir> [--seconds N] [--size WxH]
//                      [--shots 2,10,30] [--prefix name]
//
//  Alongside the single frames it writes a "trace": the brightest value each
//  pixel ever reached across the whole run. The wasp is white and the bees are
//  not, so the trace draws the wasp's entire path, which is the only way to
//  see at a glance whether it roams or loiters. Single frames do not show it.
//

import AppKit
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count > 2 else { fail("usage: render <saver> <out dir> [--seconds N] [--size WxH] [--shots a,b,c] [--prefix p]") }

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let seconds = Double(option("--seconds") ?? "") ?? 60
let prefix = option("--prefix") ?? "frame"
let shots = (option("--shots") ?? "5,20,60").split(separator: ",").compactMap { Double($0) }
var width = 1280, height = 800
if let size = option("--size") {
    let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
    if parts.count == 2 { width = parts[0]; height = parts[1] }
}

let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let bundle = Bundle(path: args[1]), bundle.load() else { fail("could not load \(args[1])") }
guard let saverClass = bundle.principalClass as? ScreenSaverView.Type else { fail("no ScreenSaverView principal class") }

let frame = NSRect(x: 0, y: 0, width: width, height: height)
guard let view = saverClass.init(frame: frame, isPreview: false) else { fail("could not create the saver view") }

// A window makes the view layer backed the way the real host does, so what we
// capture is what the screensaver would actually put on screen.
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = view
view.startAnimation()

guard let rep = view.bitmapImageRepForCachingDisplay(in: frame) else { fail("could not make a bitmap") }
let pixels = width * height * 4
var trace = [UInt8](repeating: 0, count: pixels)

func write(_ rep: NSBitmapImageRep, _ name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(name)") }
    let url = outDir.appendingPathComponent(name)
    try? png.write(to: url)
    print("  wrote \(url.path)")
}

let fps = 60.0
let total = Int(seconds * fps)
var pending = shots.map { Int($0 * fps) }

// --bench times simulate plus draw with no trace and no files, so the numbers
// in spec.md can be refreshed after a change to the renderer.
if args.contains("--bench-sim") {
    for _ in 0..<60 { view.animateOneFrame() }
    let started = Date()
    for _ in 0..<total { view.animateOneFrame() }
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "  simulate only: %.0f frames a second", Double(total)/elapsed))
    exit(0)
}
if args.contains("--bench") {
    for _ in 0..<60 { view.animateOneFrame(); view.cacheDisplay(in: frame, to: rep) }
    let started = Date()
    for _ in 0..<total { view.animateOneFrame(); view.cacheDisplay(in: frame, to: rep) }
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "  %dx%d, %d frames: %.0f frames a second", width, height, total, Double(total)/elapsed))
    exit(0)
}

for step in 0...total {
    view.animateOneFrame()
    view.cacheDisplay(in: frame, to: rep)
    guard let data = rep.bitmapData else { fail("no bitmap data") }

    if let first = pending.first, step >= first {
        pending.removeFirst()
        if let copy = rep.copy() as? NSBitmapImageRep {
            write(copy, "\(prefix)-\(Int(Double(step) / fps))s.png")
        }
    }
    // Keep the brightest value every pixel has reached.
    for i in 0..<pixels where data[i] > trace[i] { trace[i] = data[i] }
}

if let traceRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32),
   let dest = traceRep.bitmapData {
    trace.withUnsafeBufferPointer { dest.update(from: $0.baseAddress!, count: pixels) }
    write(traceRep, "\(prefix)-trace-\(Int(seconds))s.png")
}
view.stopAnimation()

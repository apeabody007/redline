// Renders the hover panel offscreen to a PNG so its layout can be looked at
// without running the app and hovering it.
//
//   mkdir -p build/pv && cp tools/preview-detail.swift build/pv/main.swift
//   swiftc -O Sources/Metrics.swift Sources/Sensors.swift Sources/HoverDetail.swift \
//     build/pv/main.swift -o build/pv/preview && (cd build/pv && ./preview)
//
// This is how the label column was caught wrapping "Thermal" onto two lines:
// the window dimensions looked fine, the layout did not.
import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let sampler = Sampler()
sampler.start(interval: 0.4)
RunLoop.main.run(until: Date().addingTimeInterval(1.5))

let hosting = NSHostingView(rootView: DetailView(sampler: sampler, width: 280))
hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

let window = NSWindow(contentRect: hosting.frame,
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = hosting
window.backgroundColor = NSColor(white: 0.12, alpha: 1)   // stand-in for a desktop
hosting.appearance = NSAppearance(named: .darkAqua)

guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
    fatalError("no rep")
}
hosting.cacheDisplay(in: hosting.bounds, to: rep)

let scale = 2
let size = NSSize(width: hosting.bounds.width * CGFloat(scale),
                  height: hosting.bounds.height * CGFloat(scale))
let out = NSImage(size: size)
out.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
rep.draw(in: NSRect(origin: .zero, size: size))
out.unlockFocus()

let tiff = out.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "panel.png"))
print("panel is \(Int(hosting.bounds.width)) x \(Int(hosting.bounds.height)) -> panel.png")

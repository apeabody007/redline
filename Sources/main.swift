import AppKit
import Combine
import ServiceManagement
import SwiftUI

// Fahrenheit unless the menu says otherwise.
UserDefaults.standard.register(defaults: [Temp.key: Temp.defaultsToFahrenheit])

// `redline --sensors` dumps every temperature sensor this Mac exposes and exits.
// Run it on a new machine to confirm the readings survived the move.
if CommandLine.arguments.contains("--sensors") {
    let readings = TemperatureSensors().allReadings()
    if readings.isEmpty {
        print("No temperature sensors readable on this Mac.")
        print("The HUD will drop the temperature and fall back to thermal state.")
    } else {
        for reading in readings {
            let temp = Temp.string(reading.celsius, fahrenheit: Temp.preference, decimals: 1)
            print(String(format: "%8@  %@", temp as NSString, reading.name))
        }
    }
    exit(0)
}

// `redline --once` prints a single reading and exits, so the same numbers the
// HUD shows can be checked from a terminal or piped somewhere else.
if CommandLine.arguments.contains("--once") {
    let sampler = Sampler()
    sampler.start(interval: 0.5)
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    let s = sampler.sample
    print(String(format: "CPU %.1f%%", s.cpu * 100))
    print(s.gpu.map { String(format: "GPU %.1f%%", $0 * 100) } ?? "GPU unavailable")
    print(String(format: "RAM %.1f%% (%.2f GB)", s.ram * 100, s.ramUsedGB))
    print(s.tempC.map { "Die " + Temp.string($0, fahrenheit: Temp.preference, decimals: 1) }
          ?? "Die temp unavailable")
    print("Thermal \(s.thermal.label)")
    exit(0)
}

final class HUDPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 34),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = content

        // Dragging is free but bounded. These fire continuously through a drag
        // and again when a display is added or removed, so the pill cannot be
        // pushed under the menu bar, behind the Dock, or off an edge, and it
        // cannot be stranded on a monitor that just got unplugged.
        NotificationCenter.default.addObserver(
            self, selector: #selector(keepOnScreen),
            name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keepOnScreen),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func keepOnScreen() {
        guard !clamping, let bounds = homeScreen()?.visibleFrame else { return }
        let wanted = clamped(frame, into: bounds)
        guard wanted.origin != frame.origin else { return }

        clamping = true
        setFrameOrigin(wanted.origin)
        clamping = false
    }

    /// The screen the pill is on: the one under its center while dragging, or
    /// whichever it overlaps most once it has been pushed past an edge.
    private func homeScreen() -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let under = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return under }
        let overlapping = NSScreen.screens.max {
            let a = $0.frame.intersection(frame), b = $1.frame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
        return overlapping ?? NSScreen.main
    }

    private var clamping = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = Sampler()
    private var panel: HUDPanel!
    private var hosting: NSHostingView<HUDView>!
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?

    private var hudVisible: Bool {
        get { UserDefaults.standard.object(forKey: "hudVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hudVisible") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hosting = NSHostingView(rootView: HUDView(sampler: sampler))
        panel = HUDPanel(content: hosting)
        panel.setFrameAutosaveName("RedlineHUD")
        resizeToFit()
        // A position saved on another display, or on this Mac before it was
        // plugged into a different one, can restore off-screen. Only honour it
        // if the pill would actually be visible.
        if !isOnAScreen(panel.frame) { placeAtTopCenter() }

        buildStatusItem()

        // The pill grows and shrinks as readings appear, so keep the window
        // glued to the content's natural size.
        cancellable = sampler.$sample
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToFit() }

        sampler.start()
        if hudVisible { panel.orderFrontRegardless() }
    }

    private func resizeToFit() {
        let size = hosting.fittingSize
        guard size.width > 0, size != panel.frame.size else { return }
        // Grow leftward so the pill's right edge stays put.
        var frame = panel.frame
        frame.origin.x -= size.width - frame.width
        frame.size = size
        panel.setFrame(frame, display: true)
        // Growing leftward can walk the pill past the left edge.
        panel.keepOnScreen()
    }

    private func isOnAScreen(_ frame: NSRect) -> Bool {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { $0.visibleFrame.contains(center) }
    }

    private func placeAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent",
                                           accessibilityDescription: "Redline")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show HUD", action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        menu.addItem(withTitle: "Use Fahrenheit", action: #selector(toggleUnits), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Redline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleHUD() {
        hudVisible.toggle()
        if hudVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    @objc private func resetPosition() {
        placeAtTopCenter()
        if !hudVisible { toggleHUD() }
    }

    @objc private func toggleUnits() {
        UserDefaults.standard.set(!Temp.preference, forKey: Temp.key)
        resizeToFit()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Redline: login item change failed: \(error.localizedDescription)")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Show HUD")?.state = hudVisible ? .on : .off
        menu.item(withTitle: "Use Fahrenheit")?.state = Temp.preference ? .on : .off
        menu.item(withTitle: "Launch at Login")?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

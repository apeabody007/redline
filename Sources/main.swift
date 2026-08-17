import AppKit
import Combine
import ServiceManagement
import SwiftUI

// Fahrenheit and severity colors unless the menu says otherwise.
UserDefaults.standard.register(defaults: [Temp.key: Temp.defaultsToFahrenheit,
                                          Appearance.severityKey: true])

// Anything unrecognized used to fall through and silently launch a second copy
// of the HUD, which is a poor answer to someone typing --help.
let arguments = Array(CommandLine.arguments.dropFirst())
if let unknown = arguments.first(where: { !["--once", "--sensors"].contains($0) }) {
    let usage = """
        Redline, a floating vitals readout for Apple Silicon Macs.

          Redline              show the HUD (default)
          Redline --once       print one reading and exit
          Redline --sensors    list every temperature sensor this Mac exposes
          Redline --help       show this
        """
    if unknown == "--help" || unknown == "-h" {
        print(usage)
        exit(0)
    }
    FileHandle.standardError.write(Data("unknown option: \(unknown)\n\n\(usage)\n".utf8))
    exit(2)
}

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
    print("Memory pressure \(s.memoryPressure.label)")
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
        acceptsMouseMovedEvents = true
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

    /// Bounded by the display itself, not the usable area, and only side to
    /// side. Vertical is free, so the pill can sit in the menu bar or over the
    /// Dock; it draws above both.
    @objc func keepOnScreen() {
        guard !clamping, let bounds = homeScreen()?.frame else { return }
        let wanted = clampedHorizontally(frame, into: bounds)
        if wanted.origin != frame.origin {
            clamping = true
            setFrameOrigin(wanted.origin)
            clamping = false
        }
        // Only persist once launch placement is done. The initial resize also
        // moves the window, and saving then would overwrite the position we
        // are about to restore with the panel's default origin.
        guard persistsPosition else { return }
        UserDefaults.standard.set([frame.origin.x, frame.origin.y], forKey: Self.originKey)
    }

    /// Set once the window has been put where it belongs at launch.
    var persistsPosition = false

    /// Position is persisted by hand rather than through setFrameAutosaveName.
    /// AppKit stores the screen geometry alongside the frame and re-derives the
    /// origin on restore, which shaved 5pt off y every launch and walked the
    /// pill down the screen.
    static let originKey = "hudOrigin"

    func restoreOrigin() -> Bool {
        guard let saved = UserDefaults.standard.array(forKey: Self.originKey) as? [Double],
              saved.count == 2 else { return false }
        setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
        return true
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
    private var detailPanel: NSPanel?
    private var detailHosting: NSHostingView<DetailView>!
    private var hoverWork: DispatchWorkItem?

    private var hudVisible: Bool {
        get { UserDefaults.standard.object(forKey: "hudVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hudVisible") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hosting = NSHostingView(rootView: HUDView(sampler: sampler))

        // The hosting view sits inside a hover tracker rather than being the
        // content view itself, so the pill can report hover without SwiftUI
        // needing to know anything about it.
        let tracker = HoverView(frame: hosting.bounds)
        tracker.autoresizingMask = [.width, .height]
        hosting.autoresizingMask = [.width, .height]
        tracker.addSubview(hosting)
        tracker.onHover = { [weak self] inside in self?.hoverChanged(inside) }

        panel = HUDPanel(content: tracker)
        // Size from the content first, then place it, so restoring an exact
        // saved origin is not undone by the resize nudging x.
        resizeToFit()
        if !panel.restoreOrigin() { placeAtTopCenter() }
        // A position saved on another display, or on this Mac before it was
        // plugged into a different one, can restore off-screen. Only honour it
        // if the pill would actually be visible.
        if !isOnAScreen(panel.frame) { placeAtTopCenter() }
        panel.keepOnScreen()

        buildStatusItem()
        applyAppearance()

        // The pill grows and shrinks as readings appear, so keep the window
        // glued to the content's natural size.
        cancellable = sampler.$sample
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeToFit()
                // Only once the pill has its real width does moving it mean
                // anything, so persistence starts here rather than at launch.
                self?.panel.persistsPosition = true
            }

        sampler.start()
        if hudVisible { panel.orderFrontRegardless() }
    }

    // MARK: - Hover detail

    /// Held back briefly so sweeping the cursor across the pill on the way
    /// somewhere else does not flash a panel at you.
    private func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        guard inside else {
            detailPanel?.orderOut(nil)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.showDetail() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func showDetail() {
        let panelToShow = detailPanel ?? makeDetailPanel()
        detailPanel = panelToShow
        // Re-read the pill's width every time: it changes when the units are
        // switched or the throttle tag appears, and the two should always be
        // the same width.
        detailHosting.rootView = DetailView(sampler: sampler, width: panel.frame.width)
        panelToShow.setContentSize(detailHosting.fittingSize)
        positionDetail(panelToShow)
        panelToShow.orderFrontRegardless()
    }

    private func makeDetailPanel() -> NSPanel {
        detailHosting = NSHostingView(rootView: DetailView(sampler: sampler,
                                                          width: panel.frame.width))
        let new = NSPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        new.isFloatingPanel = true
        new.level = .statusBar
        new.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        new.isOpaque = false
        new.backgroundColor = .clear
        new.hasShadow = true
        new.hidesOnDeactivate = false
        // Never let the detail panel take the hover away from the pill, which
        // would make it flicker itself in and out.
        new.ignoresMouseEvents = true
        new.appearance = panel.appearance
        new.contentView = detailHosting
        return new
    }

    /// Under the pill by default, flipped above it when there is no room, and
    /// pulled back inside the display if it would hang off a side.
    private func positionDetail(_ detail: NSPanel) {
        let pill = panel.frame
        let size = detail.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(pill) } ?? NSScreen.main
        let bounds = screen?.frame ?? pill

        var origin = NSPoint(x: pill.minX, y: pill.minY - size.height - 8)
        if origin.y < bounds.minY { origin.y = pill.maxY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        detail.setFrameOrigin(origin)
    }

    private func resizeToFit() {
        let size = hosting.fittingSize
        guard size.width > 0, size != panel.frame.size else { return }
        // Grow leftward so the pill's right edge stays put, but not before the
        // first real sample: the pill launches narrow, because it has no GPU or
        // temperature reading yet, and anchoring the right edge through that
        // first widening would walk the window left on every launch.
        var frame = panel.frame
        if panel.persistsPosition {
            frame.origin.x -= size.width - frame.width
        }
        frame.size = size
        panel.setFrame(frame, display: true)
        // Growing leftward can walk the pill past the left edge.
        panel.keepOnScreen()
    }

    private func isOnAScreen(_ frame: NSRect) -> Bool {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { $0.frame.contains(center) }
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
        // The default symbol size renders noticeably smaller than the custom
        // icons most menu bar apps ship, which leaves Redline looking shrunken
        // next to its neighbours. 16pt sits with them without overpowering.
        let icon = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent",
                           accessibilityDescription: "Redline")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        icon?.isTemplate = true
        statusItem.button?.image = icon

        let menu = NSMenu()
        menu.addItem(withTitle: "Show HUD", action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        menu.addItem(.separator())

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for mode in Appearance.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(setAppearance(_:)),
                                  keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        menu.addItem(withTitle: "Severity Colors", action: #selector(toggleSeverity), keyEquivalent: "")
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

    @objc private func toggleSeverity() {
        let on = UserDefaults.standard.bool(forKey: Appearance.severityKey)
        UserDefaults.standard.set(!on, forKey: Appearance.severityKey)
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: Appearance.key)
        applyAppearance()
    }

    /// Forcing the panel's appearance is what flips the material and the text
    /// colors; Auto leaves it nil so the pill follows the system.
    private func applyAppearance() {
        switch Appearance.current {
        case .auto:  panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark:  panel.appearance = NSAppearance(named: .darkAqua)
        }
        detailPanel?.appearance = panel.appearance
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
        menu.item(withTitle: "Severity Colors")?.state =
            UserDefaults.standard.bool(forKey: Appearance.severityKey) ? .on : .off
        menu.item(withTitle: "Launch at Login")?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off

        for item in menu.item(withTitle: "Appearance")?.submenu?.items ?? [] {
            item.state = (item.representedObject as? String) == Appearance.current.rawValue
                ? .on : .off
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import SwiftUI
import AppKit
import Combine

@main
enum CodexMacApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Monitor()
    var island: IslandPanel!
    var item: NSStatusItem!
    let popover = NSPopover()
    var preferences: NSWindow?
    var observation: AnyCancellable?
    var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"), CommandLine.arguments.count > index + 1 {
            do { try captureScreenshots(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
            catch { fputs("Screenshot capture failed: \(error)\n", stderr); exit(1) }
        }
        model.start()
        island = IslandPanel(model: model, settings: { [weak self] in self?.showSettings() })
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(toggleDashboard)
        item.button?.target = self
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(model: model, settings: { [weak self] in self?.showSettings() }))
        observation = model.$reading.sink { [weak self] reading in self?.updateMenu(reading) }
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in if let self { self.updateMenu(self.model.reading) } }
        }
        clock?.tolerance = 8
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc func screenChanged() { island.layout() }
    @objc func woke() { model.refresh() }
    @objc func toggleDashboard() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func updateMenu(_ reading: Reading) {
        let now = Date()
        guard let button = item.button else { return }
        let values = Period.allCases.map { period in
            period.short + " " + (reading.snapshot?[period].map { "\($0.remaining)%" } ?? "—")
        }.joined(separator: "  ")
        let reset = reading.snapshot?.session?.reset ?? reading.snapshot?.week?.reset
        let status = reading.status(at: now)
        button.title = values + (model.defaults.bool(forKey: "menuTime") ? "  ◷ " + countdown(to: reset, now: now) : "") + (status == "Cached" ? " ◌" : "")
        button.toolTip = "CodexMac · \(status) · Usage remaining"
        button.setAccessibilityLabel(button.toolTip ?? "CodexMac")
    }
    func showSettings() {
        popover.performClose(nil)
        if preferences == nil {
            let view = Preferences(model: model, panel: island, menuChanged: { [weak self] in if let self { self.updateMenu(self.model.reading) } })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "CodexMac Settings"
            window.isReleasedWhenClosed = false
            window.center()
            preferences = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if item != nil && !popover.isShown { toggleDashboard() }
        return true
    }
}

struct Dashboard: View {
    @ObservedObject var model: Monitor
    @AppStorage("theme") var theme = "Aurora"
    let settings: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 14) {
                UsageCard(reading: model.reading, now: context.date, palette: Palette(theme))
                if let note = model.notice { Text(note).font(.caption).foregroundStyle(.orange) }
                Divider()
                HStack {
                    Button(action: model.refresh) { Label(model.busy ? "Checking…" : "Refresh", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    Spacer()
                    Button(action: settings) { Image(systemName: "gearshape") }.help("Settings")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit CodexMac")
                }
            }.padding(20).frame(width: 325)
                .background(Color(white: 0.075)).environment(\.colorScheme, .dark)
        }
    }
}

@MainActor
private func captureScreenshots(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let model = Monitor() // Clean install, no CLI account on the build runner.
    func capture<V: View>(_ view: V, _ size: NSSize, _ name: String) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        window.orderFrontRegardless()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: folder.appendingPathComponent(name))
        window.orderOut(nil)
    }
    let island = Island(monitor: model, toggle: {}, hover: { _ in }, settings: {})
    try capture(island, NSSize(width: 273, height: 42), "Floating-Bar.png")
    model.expanded = true
    try capture(island, NSSize(width: 310, height: 278), "Expanded-Bar.png")
    try capture(Dashboard(model: model, settings: {}), NSSize(width: 325, height: 410), "Dashboard.png")
}

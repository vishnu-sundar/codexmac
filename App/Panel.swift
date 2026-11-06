import AppKit
import SwiftUI

private extension NSScreen {
    var stableID: String {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value)?.takeRetainedValue() else { return localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

final class Grip: NSView {
    var onClick: () -> Void = {}
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation, origin = window.frame.origin
        var moved = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if !moved { onClick() }
                break
            }
            let current = NSEvent.mouseLocation
            let dx = current.x - start.x, dy = current.y - start.y
            if moved || hypot(dx, dy) > 3 {
                moved = true
                window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

@MainActor
final class IslandPanel: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let model: Monitor
    private let grip = Grip()
    var hideTask: Task<Void, Never>?
    private var layingOut = false
    private var hovered = false
    init(model: Monitor, settings: @escaping () -> Void) {
        self.model = model
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: Island(monitor: model, toggle: { [weak self] in self?.toggle() },
                                                  hover: { [weak self] inside in self?.hover(inside) }, settings: settings))
        panel.contentView = host
        host.addSubview(grip)
        grip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([grip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                                     grip.topAnchor.constraint(equalTo: host.topAnchor),
                                     grip.widthAnchor.constraint(equalToConstant: 37),
                                     grip.heightAnchor.constraint(lessThanOrEqualToConstant: 42),
                                     grip.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor)])
        let h = grip.heightAnchor.constraint(equalToConstant: 42)
        h.priority = .defaultHigh
        h.isActive = true
        grip.onClick = { [weak self] in self?.toggle() }
        apply()
    }
    func apply(reset: Bool = false) {
        let defaults = model.defaults
        if reset { defaults.removeObject(forKey: "panelX") }
        panel.level = defaults.bool(forKey: "onTop") ? .floating : .normal
        guard defaults.bool(forKey: "floating") else { panel.orderOut(nil); return }
        if !defaults.bool(forKey: "autoHide") { model.tucked = false }
        layout()
        panel.orderFrontRegardless()
        planHide()
    }
    func layout(animated: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { $0.stableID == model.defaults.string(forKey: "screen") }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = model.tucked ? NSSize(width: 70, height: 14) : model.expanded ? NSSize(width: 310, height: 242) : NSSize(width: 273, height: 42)
        let defaults = model.defaults
        let anchor = defaults.string(forKey: "anchor")
        let saved = defaults.object(forKey: "panelX") != nil
        let x = saved ? visible.minX + defaults.double(forKey: "panelX") * visible.width - size.width/2 :
            (anchor == "Top right" ? visible.maxX - size.width - 16 : visible.midX - size.width/2)
        let y = saved ? visible.maxY - defaults.double(forKey: "panelY") * visible.height - size.height :
            (anchor == "Bottom center" ? visible.minY + 12 : visible.maxY - size.height - 8)
        let frame = NSRect(x: max(visible.minX, min(visible.maxX - size.width, x)), y: max(visible.minY, min(visible.maxY - size.height, y)),
                           width: size.width, height: size.height)
        layingOut = true
        panel.setFrame(frame, display: true, animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        layingOut = false
    }
    func windowDidMove(_ notification: Notification) {
        guard !layingOut, let screen = panel.screen else { return }
        let f = screen.visibleFrame
        model.defaults.set(screen.stableID, forKey: "screen")
        model.defaults.set((panel.frame.midX - f.minX)/f.width, forKey: "panelX")
        model.defaults.set((f.maxY - panel.frame.maxY)/f.height, forKey: "panelY")
    }
    func toggle() {
        if model.tucked { model.tucked = false } else { model.expanded.toggle() }
        layout(animated: true)
        planHide()
    }
    func hover(_ inside: Bool) {
        hovered = inside
        if inside && model.tucked { model.tucked = false; layout(animated: true) }
        planHide()
    }
    func planHide() {
        hideTask?.cancel()
        guard model.defaults.bool(forKey: "autoHide"), !hovered, !model.expanded, !model.tucked else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            model.tucked = true
            layout(animated: true)
        }
    }
}

import SwiftUI
import ServiceManagement

struct Preferences: View {
    @ObservedObject var model: Monitor
    let panel: IslandPanel
    @AppStorage("interval") var interval = 15
    @AppStorage("floating") var floating = true
    @AppStorage("onTop") var onTop = true
    @AppStorage("autoHide") var autoHide = false
    @AppStorage("opacity") var opacity = 0.92
    @AppStorage("theme") var theme = "Aurora"
    @AppStorage("anchor") var anchor = "Top center"
    @AppStorage("menuTime") var menuTime = true
    @AppStorage("alerts") var alerts = false
    @AppStorage("threshold25") var threshold25 = true
    @AppStorage("threshold10") var threshold10 = true
    @AppStorage("threshold0") var threshold0 = true
    @AppStorage("resetAlerts") var resetAlerts = true
    @AppStorage("cliPath") var path = ""
    @State var login = SMAppService.mainApp.status == .enabled
    @State var loginNote = ""
    let menuChanged: () -> Void
    var body: some View {
        Form {
            Section("Floating bar") {
                Toggle("Show floating bar", isOn: $floating)
                Toggle("Always on top", isOn: $onTop)
                Toggle("Auto-hide to a small handle", isOn: $autoHide)
                Picker("Position", selection: $anchor) {
                    ForEach(["Top center", "Top right", "Bottom center"], id: \.self) { Text($0) }
                }
                Button("Restore selected position") { panel.apply(reset: true) }
                Picker("Appearance", selection: $theme) { ForEach(["Aurora", "Ember", "Frost"], id: \.self) { Text($0) } }
                Slider(value: $opacity, in: 0.35...1) { Text("Glass opacity") }
            }
            Section("Updates") {
                Picker("Refresh every", selection: $interval) {
                    ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Toggle("Show reset credit expiry in menu bar", isOn: $menuTime)
                Toggle("Launch at login", isOn: $login).onChange(of: login) { _, enabled in
                    guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginNote = SMAppService.mainApp.status == .requiresApproval ? "Approve CodexMac in System Settings → Login Items." : ""
                    } catch { loginNote = error.localizedDescription }
                    login = SMAppService.mainApp.status == .enabled
                }
                if !loginNote.isEmpty { Text(loginNote).font(.caption) }
            }
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $alerts)
                if alerts {
                    Toggle("Below 25% remaining", isOn: $threshold25)
                    Toggle("Below 10% remaining", isOn: $threshold10)
                    Toggle("At 0% remaining", isOn: $threshold0)
                    Toggle("Confirmed resets", isOn: $resetAlerts)
                }
            }
            Section("Codex CLI") {
                Text(path.isEmpty ? "Automatic discovery" : path).lineLimit(2).font(.caption.monospaced())
                HStack {
                    Button("Choose executable…") {
                        let picker = NSOpenPanel()
                        picker.canChooseDirectories = false
                        picker.message = "Select your trusted Codex CLI executable."
                        if picker.runModal() == .OK, let url = picker.url { path = url.path; model.refresh() }
                    }
                    if !path.isEmpty { Button("Use automatic discovery") { path = ""; model.refresh() } }
                }
            }
        }.formStyle(.grouped).frame(width: 440, height: 570)
            .onChange(of: floating) { panel.apply() }.onChange(of: onTop) { panel.apply() }
            .onChange(of: autoHide) { panel.apply() }.onChange(of: anchor) { panel.apply(reset: true) }
            .onChange(of: interval) { model.schedule(); model.refresh() }
            .onChange(of: menuTime) { menuChanged() }
            .onChange(of: alerts) { if alerts { model.authorizeNotifications() } }
    }
}

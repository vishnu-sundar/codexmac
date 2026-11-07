import SwiftUI
import WidgetKit
import UserNotifications
import ServiceManagement

@MainActor
final class Monitor: ObservableObject {
    @Published var reading = Reading.empty
    @Published var busy = false
    @Published var notice: String?
    @Published var expanded = false
    @Published var tucked = false
    private var timer: Timer?
    let defaults = UserDefaults.standard
    var interval: Int { defaults.integer(forKey: "interval") }

    func start() {
        defaults.register(defaults: ["interval": 15, "floating": true, "onTop": true, "opacity": 0.92,
                                     "theme": "Aurora", "anchor": "Top center", "menuTime": true,
                                     "threshold25": true, "threshold10": true, "threshold0": true, "resetAlerts": true])
        reading = Cache.read()
        reading.liveUntil = nil
        schedule()
        refresh()
    }
    func schedule() {
        timer?.invalidate()
        let seconds = TimeInterval(max(5, interval) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = min(30, seconds / 10)
    }
    func refresh() {
        guard !busy else { return }
        busy = true
        let path = defaults.string(forKey: "cliPath") ?? ""
        Task {
            let outcome = await Task.detached(priority: .utility) { Result { try CodexClient(executable: path).fetch() } }.value
            defer { busy = false }
            notice = nil
            switch outcome {
            case .success(let fresh):
                if defaults.bool(forKey: "alerts") {
                    let thresholds = [25, 10, 0].filter { defaults.bool(forKey: "threshold\($0)") }
                    for event in limitEvents(from: reading.snapshot, to: fresh, thresholds: thresholds, resets: defaults.bool(forKey: "resetAlerts")) {
                        notify(event, remaining: fresh[event.period]?.remaining)
                    }
                }
                reading = Reading(snapshot: fresh, liveUntil: Date().addingTimeInterval(TimeInterval(interval * 60)),
                                  issue: fresh.hasData ? nil : "Codex did not report usage windows or reset credits.")
            case .failure(let error):
                if let failure = error as? SourceFailure {
                    switch failure {
                    case .signedOut: reading.snapshot = nil
                    case .limits(let owner, _) where owner.isEmpty || owner != reading.snapshot?.owner: reading.snapshot = nil
                    default: break
                    }
                }
                reading.issue = (error as? SourceFailure)?.errorDescription ?? "Unable to read the Codex CLI response."
                reading.liveUntil = nil
            }
            do { try Cache.write(reading) }
            catch { notice = "Could not write the widget snapshot in Application Support." }
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexMacUsage")
        }
    }
    func authorizeNotifications() {
        Task {
            do {
                let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !accepted { notice = "Allow CodexMac notifications in System Settings." }
            } catch { notice = "Notification permission could not be requested." }
        }
    }
    private func notify(_ event: LimitEvent, remaining: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "CodexMac · \(event.period.label)"
        content.body = event.threshold == nil ? "Codex confirmed the usage window reset." : "\(remaining ?? 0)% of this window remains."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let reading: Reading
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, reading: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, reading: Cache.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date(), reading = Cache.read()
        var entries = [UsageEntry(date: now, reading: reading)]
        if let expiry = reading.liveUntil, expiry > now { entries.append(UsageEntry(date: expiry, reading: reading)) }
        completion(Timeline(entries: entries, policy: .after(max(entries.last!.date, now.addingTimeInterval(900)))))
    }
}

struct WidgetFace: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 9) {
            HStack {
                Image(systemName: "waveform.path").foregroundStyle(.mint)
                Text("CodexMac").font(.caption.weight(.bold))
                Spacer()
                if family != .systemSmall { Text(entry.reading.status(at: entry.date)).font(.caption2) }
            }
            if family == .systemLarge { Text("Usage remaining").font(.title.bold()); Spacer() }
            ForEach(Period.allCases, id: \.rawValue) { period in
                let window = entry.reading.snapshot?[period]
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(period.label).font(.caption)
                        Spacer()
                        Text(window.map { "\($0.remaining)%" } ?? "—").font(.system(.body, design: .rounded).bold()).monospacedDigit()
                    }
                    ProgressView(value: Double(window?.remaining ?? 0), total: 100)
                        .tint(period == .session ? .mint : .purple)
                        .accessibilityLabel(window == nil ? "Unavailable" : "Remaining")
                    if let reset = window?.reset {
                        Text(reset, format: .dateTime.month().day().hour().minute()).font(.system(size: 9)).foregroundStyle(.secondary)
                    } else { Text("Reset —").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            }
            if family == .systemSmall { Text(entry.reading.status(at: entry.date)).font(.system(size: 9)) }
            if family == .systemLarge {
                Spacer()
                if let stamp = entry.reading.snapshot?.date { Text("Checked \(stamp.formatted())").font(.caption) }
                if let issue = entry.reading.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
        }.containerBackground(for: .widget) { Color(red: 0.065, green: 0.08, blue: 0.095) }
            .environment(\.colorScheme, .dark)
    }
}
@main
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CodexMacUsage", provider: Provider()) { WidgetFace(entry: $0) }
            .configurationDisplayName("Codex usage")
            .description("Remaining usage and reset times from CodexMac.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

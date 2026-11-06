import SwiftUI

struct Palette {
    let first: Color
    let second: Color
    init(_ name: String) {
        switch name {
        case "Ember": first = Color(red: 1, green: 0.69, blue: 0.40); second = .pink
        case "Frost": first = .white; second = Color(white: 0.7)
        default: first = Color(red: 0.49, green: 0.94, blue: 0.77); second = Color(red: 0.68, green: 0.64, blue: 1)
        }
    }
}

struct Signal: View {
    var color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array([7, 14, 20, 11].enumerated()), id: \.offset) { item in
                Capsule().fill(color).frame(width: 2.5, height: CGFloat(item.element))
            }
        }.accessibilityHidden(true)
    }
}

struct Meter: View {
    var value: Int?
    var tint: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.11))
                if let value {
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.68), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(value) / 100)
                }
            }
        }.frame(height: 4)
    }
}

struct UsageDetails: View {
    let reading: Reading
    let now: Date
    let palette: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Period.allCases, id: \.rawValue) { period in
                let window = reading.snapshot?[period]
                let color = period == .session ? palette.first : palette.second
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(period.label + " window").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(window.map { "\($0.remaining)%" } ?? "—")
                            .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Meter(value: window?.remaining, tint: color)
                    if let reset = window?.reset {
                        Text("Reset \(reset.formatted(date: .abbreviated, time: .shortened)) · \(countdown(to: reset, now: now))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(window == nil ? "Window unavailable" : "Reset time unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct UsageCard: View {
    let reading: Reading
    let now: Date
    let palette: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Signal(color: palette.first)
                Text("CodexMac").font(.headline)
                Spacer()
                Text(reading.status(at: now)).font(.caption.weight(.semibold)).foregroundStyle(palette.first)
            }
            Text("Usage remaining").font(.system(size: 25, weight: .medium, design: .rounded))
            UsageDetails(reading: reading, now: now, palette: palette)
            if let issue = reading.issue { Text(issue).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let date = reading.snapshot?.date {
                Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct Island: View {
    @ObservedObject var monitor: Monitor
    @AppStorage("theme") var theme = "Aurora"
    @AppStorage("opacity") var opacity = 0.92
    var toggle: () -> Void
    var hover: (Bool) -> Void
    var settings: () -> Void
    var palette: Palette { Palette(theme) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let shape = RoundedRectangle(cornerRadius: monitor.expanded ? 22 : 28, style: .continuous)
            VStack(spacing: 0) {
                if monitor.tucked {
                    Capsule().fill(palette.first.opacity(0.85)).frame(width: 35, height: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle()).onTapGesture(perform: toggle)
                } else {
                    Button(action: toggle) {
                        HStack(spacing: 11) {
                            Signal(color: palette.first)
                            ForEach(Period.allCases, id: \.rawValue) { period in
                                HStack(spacing: 4) {
                                    Text(period.short).foregroundStyle(period == .session ? palette.first : palette.second).font(.caption2.weight(.bold))
                                    Text(monitor.reading.snapshot?[period].map { "\($0.remaining)%" } ?? "—")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                                }
                            }
                            Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 13)
                            let reset = monitor.reading.snapshot?.session?.reset ?? monitor.reading.snapshot?.week?.reset
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.caption2)
                                Text(countdown(to: reset, now: now)).font(.caption.monospacedDigit())
                            }.foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            statusIcon(now)
                        }.padding(.horizontal, 16).frame(height: 42).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Expand or collapse. Drag the bar to move it.")
                    if monitor.expanded {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                            UsageDetails(reading: monitor.reading, now: now, palette: palette)
                            HStack {
                                Text(monitor.reading.status(at: now)).font(.caption.weight(.semibold))
                                Spacer()
                                Button(action: monitor.refresh) { Image(systemName: "arrow.clockwise") }.disabled(monitor.busy).help("Refresh")
                                Button(action: settings) { Image(systemName: "slider.horizontal.3") }.help("Settings")
                            }.buttonStyle(.plain)
                        }.padding(.horizontal, 17).padding(.bottom, 14)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(Color(white: 0.055).opacity(opacity)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [palette.first.opacity(0.39), .white.opacity(0.08), palette.second.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .clipShape(shape).environment(\.colorScheme, .dark).foregroundStyle(.white)
                .onHover(perform: hover)
        }
    }
    func statusIcon(_ now: Date) -> some View {
        let status = monitor.reading.status(at: now)
        return Image(systemName: status == "Live" ? "circle.fill" : status == "Cached" ? "clock.badge.exclamationmark" : "questionmark.circle")
            .font(.system(size: 9)).foregroundStyle(status == "Live" ? palette.first : .gray)
            .accessibilityLabel(status).help(status)
    }
}

import Foundation

enum Period: Int, Codable, CaseIterable {
    case session = 300
    case week = 10080
    var label: String { self == .session ? "5-hour" : "Weekly" }
    var short: String { self == .session ? "5h" : "7d" }
}

struct Window: Codable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
    var remaining: Int { 100 - usedPercent }
    var reset: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

struct Bucket: Decodable {
    let limitId: String?
    let primary: Window?
    let secondary: Window?
}

struct ResetCredit: Codable, Identifiable {
    let id: String
    let title: String?
    let description: String?
    let status: String
    let expiresAt: TimeInterval?

    var label: String {
        guard let title, !title.isEmpty else { return "Usage limit reset" }
        return title
    }
}

struct ResetCredits: Codable {
    let availableCount: Int
    let credits: [ResetCredit]?

    var available: [ResetCredit] {
        (credits ?? []).filter { $0.status == "available" }.sorted {
            ($0.expiresAt ?? .infinity, $0.id) < ($1.expiresAt ?? .infinity, $1.id)
        }
    }
}

struct LimitResponse: Decodable {
    let rateLimitResetCredits: ResetCredits?
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?

    func snapshot(owner: String, at date: Date) -> Snapshot {
        var bucket = rateLimitsByLimitId?["codex"]
        if bucket == nil, let legacy = rateLimits, legacy.limitId == nil || legacy.limitId == "codex" {
            bucket = legacy
        }
        let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }
        func window(_ period: Period) -> Window? {
            windows.first { $0.windowDurationMins == period.rawValue && (0...100).contains($0.usedPercent) }
        }
        return Snapshot(owner: owner, date: date, session: window(.session), week: window(.week),
                        resetCredits: rateLimitResetCredits)
    }
}

struct Snapshot: Codable {
    let owner: String
    let date: Date
    let session: Window?
    let week: Window?
    var resetCredits: ResetCredits? = nil
    subscript(_ period: Period) -> Window? { period == .session ? session : week }
    var hasData: Bool { session != nil || week != nil || resetCredits != nil }
}

struct Reading: Codable {
    var snapshot: Snapshot?
    var liveUntil: Date?
    var issue: String?
    static let empty = Reading(issue: "Open CodexMac and sign in with the Codex CLI.")

    func status(at now: Date) -> String {
        guard snapshot?.hasData == true else { return "Unavailable" }
        return (liveUntil ?? .distantPast) > now && issue == nil ? "Live" : "Cached"
    }
}

func countdown(to reset: Date?, now: Date) -> String {
    guard let reset else { return "—" }
    let seconds = reset.timeIntervalSince(now)
    guard seconds > 0 else { return "Due" }
    let minutes = Int(ceil(seconds / 60))
    if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes)m"
}

struct LimitEvent: Equatable {
    let period: Period
    let threshold: Int? // nil denotes a confirmed reset
}

func limitEvents(from old: Snapshot?, to new: Snapshot, thresholds: [Int], resets: Bool) -> [LimitEvent] {
    guard let old, old.owner == new.owner, !new.owner.isEmpty, old.date < new.date else { return [] }
    return Period.allCases.compactMap { period in
        guard let a = old[period], let b = new[period] else { return nil }
        if let previous = a.reset, let next = b.reset, next > previous,
           a.remaining < b.remaining, previous <= new.date {
            return resets ? LimitEvent(period: period, threshold: nil) : nil
        }
        // A single observation can cross several thresholds. Send only the most urgent.
        let crossed = thresholds.sorted().first { t in
            t == 0 ? a.remaining > 0 && b.remaining == 0 : a.remaining >= t && b.remaining < t
        }
        return crossed.map { LimitEvent(period: period, threshold: $0) }
    }
}

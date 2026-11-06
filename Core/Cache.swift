import Foundation

enum Cache {
    static var file: URL? {
        #if os(macOS)
        let group = Bundle.main.object(forInfoDictionaryKey: "UsageAppGroup") as? String ?? "group.io.codexmac.monitor"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("CodexMac-usage.json")
        #else
        return nil
        #endif
    }
    static func read() -> Reading {
        guard let file, let data = try? Data(contentsOf: file),
              let reading = try? JSONDecoder().decode(Reading.self, from: data) else { return .empty }
        return reading
    }
    static func write(_ reading: Reading) throws {
        guard let file else { throw CocoaError(.fileWriteNoPermission) }
        try JSONEncoder().encode(reading).write(to: file, options: .atomic)
    }
}

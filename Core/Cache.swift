import Foundation
import Darwin

enum Cache {
    static var file: URL? {
        // The widget's ordinary home URL is its sandbox container. Resolve the account's
        // home for the single snapshot file granted by the WidgetKit target's entitlement.
        var user = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: max(16384, sysconf(_SC_GETPW_R_SIZE_MAX)))
        return buffer.withUnsafeMutableBufferPointer { bytes in
            guard getpwuid_r(getuid(), &user, bytes.baseAddress!, bytes.count, &result) == 0,
                  result != nil, let directory = user.pw_dir else { return nil }
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
                .appendingPathComponent("Library/Application Support/CodexMac/Usage/snapshot.json")
        }
    }

    static func read() -> Reading {
        guard let file, let data = try? Data(contentsOf: file),
              let reading = try? JSONDecoder().decode(Reading.self, from: data) else { return .empty }
        return reading
    }

    static func write(_ reading: Reading) throws {
        guard let file else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(reading).write(to: file, options: .atomic)
    }
}

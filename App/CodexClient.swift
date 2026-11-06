import Foundation
import CryptoKit
import Darwin

enum SourceFailure: LocalizedError {
    case missing, timeout, disconnected, malformed, signedOut, limits(String, String)
    var errorDescription: String? {
        switch self {
        case .missing: return "Install the Codex CLI or choose its executable in Settings."
        case .timeout: return "Codex did not reply within 25 seconds. Try refreshing."
        case .disconnected: return "The Codex CLI stopped responding. Check its path and version."
        case .malformed: return "Codex returned an unsupported reply. Check for a CLI update."
        case .signedOut: return "Run codex login and choose Sign in with ChatGPT, then refresh."
        case .limits(_, let reason): return reason
        }
    }
}

private struct AccountReply: Decodable {
    struct Account: Decodable { let type: String; let email: String? }
    let account: Account?
}

struct CodexClient {
    let executable: String
    func fetch() throws -> Snapshot {
        let homes = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin",
                     NSHomeDirectory() + "/.npm-global/bin", "/Applications/Codex.app/Contents/Resources"]
        let candidates = executable.isEmpty ? homes.map { $0 + "/codex" } : [executable]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { throw SourceFailure.missing }
        let server = try Server(path: path)
        defer { server.close() }
        let client = ["name": "codexmac", "title": "CodexMac", "version": "1.0"]
        _ = try server.request(1, "initialize", ["clientInfo": client])
        try server.send(["method": "initialized"])
        let accountData = try server.request(2, "account/read", ["refreshToken": false])
        let account = try JSONDecoder().decode(AccountReply.self, from: accountData).account
        guard let account, ["chatgpt", "chatgptAuthTokens"].contains(account.type) else { throw SourceFailure.signedOut }
        let owner = account.email.map { SHA256.hash(data: Data($0.lowercased().utf8)).map { String(format: "%02x", $0) }.joined() } ?? ""
        do {
            let limits = try server.request(3, "account/rateLimits/read")
            return try JSONDecoder().decode(LimitResponse.self, from: limits).snapshot(owner: owner, at: Date())
        } catch {
            throw SourceFailure.limits(owner, "Codex could not read usage limits. Check your connection and CLI sign-in.")
        }
    }
}

// One bounded stdio session per refresh. No terminal, HTTP server, shell, or model turn.
private final class Server {
    let child = Process()
    let input = Pipe(), output = Pipe()
    var pending = Data()
    let deadline = ProcessInfo.processInfo.systemUptime + 25
    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        child.executableURL = url
        child.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [url.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        child.environment = env
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try child.run()
    }
    func close() {
        try? input.fileHandleForWriting.close()
        if child.isRunning {
            child.terminate()
            let end = ProcessInfo.processInfo.systemUptime + 0.35
            while child.isRunning && ProcessInfo.processInfo.systemUptime < end { Thread.sleep(forTimeInterval: 0.025) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
    func send(_ packet: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: packet)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func request(_ id: Int, _ method: String, _ params: [String: Any]? = nil) throws -> Data {
        var packet: [String: Any] = ["id": id, "method": method]
        packet["params"] = params
        try send(packet)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      reply["id"] as? Int == id else { continue }
                guard let result = reply["result"], JSONSerialization.isValidJSONObject(result) else { throw SourceFailure.malformed }
                return try JSONSerialization.data(withJSONObject: result)
            }
            let fd = output.fileHandleForReading.fileDescriptor
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(1, (deadline - ProcessInfo.processInfo.systemUptime) * 1000))
            let result = poll(&pfd, 1, remaining)
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw SourceFailure.timeout }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { throw SourceFailure.disconnected }
            pending.append(contentsOf: buffer.prefix(count))
            guard pending.count <= 2_097_152 else { throw SourceFailure.malformed }
        }
        throw SourceFailure.timeout
    }
}

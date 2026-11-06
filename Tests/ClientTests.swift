import Foundation
import XCTest
@testable import CodexMacCore

// Synthetic responses are confined to this executable test fixture. Production has no sample provider.
final class ClientTests: XCTestCase {
    func withServer(account: String, limits: String, run: (CodexClient) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        [ "$1" = app-server ] || exit 1
        read_request() {
          IFS= read -r request || exit 2
          case "$request" in *\\"$1\\"*) ;; *) exit 3 ;; esac
        }
        read_request initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        read_request initialized
        read_request account/read
        printf '%s\\n' '{"id":2,"result":\(account)}'
        read_request account/rateLimits/read
        printf '%s\\n' '{"method":"unrelated","params":{}}' '\(limits)'
        """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        try run(CodexClient(executable: file.path))
    }
    func testCLIStdioRoundTrip() throws {
        try withServer(account: #"{"account":{"type":"chatgpt","email":"fixture@example.invalid"}}"#,
                       limits: #"{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}"#) { client in
            let value = try client.fetch()
            XCTAssertEqual(value.session?.remaining, 88)
            XCTAssertEqual(value.owner.count, 64)
            XCTAssertNil(value.week)
        }
    }
    func testSignedOutCLI() throws {
        try withServer(account: #"{"account":null}"#, limits: "{}") { client in
            XCTAssertThrowsError(try client.fetch()) { error in
                guard case SourceFailure.signedOut = error else { return XCTFail("Expected signed-out status, received \(error)") }
            }
        }
    }
    func testRemoteErrorPreservesOnlySameAccountContext() throws {
        try withServer(account: #"{"account":{"type":"chatgpt","email":"fixture@example.invalid"}}"#,
                       limits: #"{"id":3,"error":{"code":-1,"message":"test"}}"#) { client in
            XCTAssertThrowsError(try client.fetch()) { error in
                guard case SourceFailure.limits(let owner, _) = error else { return XCTFail("Expected limits failure") }
                XCTAssertEqual(owner.count, 64)
            }
        }
    }
    func testMissingExecutable() {
        XCTAssertThrowsError(try CodexClient(executable: "/missing-\(UUID().uuidString)").fetch())
    }
}

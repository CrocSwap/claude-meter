import Foundation
import Testing
@testable import ClaudeMeter

@Suite("TokenReader.selectToken")
struct TokenReaderSelectTests {

    private let nowMs: Int64 = 1_777_577_933_000  // matches the probe-day timestamp
    private var now: Date { Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000) }

    private func makeCacheJSON(_ entries: [(key: String, token: String, expiresAt: Int64)]) -> Data {
        let dict: [String: Any] = Dictionary(uniqueKeysWithValues: entries.map { e in
            (e.key, ["token": e.token, "refreshToken": "rt", "expiresAt": e.expiresAt] as [String: Any])
        })
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("Picks an entry whose scopes include user:profile")
    func picksProfileScopedEntry() throws {
        let cache = makeCacheJSON([
            (key: "abc:def:https://api.anthropic.com:user:inference user:office",
             token: "wrong-token-no-profile-scope",
             expiresAt: nowMs + 3600_000),
            (key: "abc:def:https://api.anthropic.com:user:inference user:profile",
             token: "right-token",
             expiresAt: nowMs + 3600_000),
        ])
        let token = try TokenReader.selectToken(plaintextJSON: cache, now: now)
        #expect(token == "right-token")
    }

    @Test("Skips expired entries even with the right scope")
    func skipsExpired() throws {
        let cache = makeCacheJSON([
            (key: "abc:def:https://api.anthropic.com:user:inference user:profile",
             token: "expired-token",
             expiresAt: nowMs - 60_000),  // expired 1 min ago
            (key: "ghi:jkl:https://api.anthropic.com:user:inference user:profile",
             token: "fresh-token",
             expiresAt: nowMs + 3600_000),
        ])
        let token = try TokenReader.selectToken(plaintextJSON: cache, now: now)
        #expect(token == "fresh-token")
    }

    @Test("Throws noUsableToken when every candidate is expired")
    func throwsWhenAllExpired() {
        let cache = makeCacheJSON([
            (key: "abc:def:https://api.anthropic.com:user:profile",
             token: "old", expiresAt: nowMs - 1),
        ])
        #expect(throws: TokenReader.ReadError.self) {
            try TokenReader.selectToken(plaintextJSON: cache, now: now)
        }
    }

    @Test("Throws noUsableToken when nothing has user:profile scope")
    func throwsWhenNoProfileScope() {
        let cache = makeCacheJSON([
            (key: "abc:def:https://api.anthropic.com:user:inference",
             token: "no-profile", expiresAt: nowMs + 3600_000),
        ])
        #expect(throws: TokenReader.ReadError.self) {
            try TokenReader.selectToken(plaintextJSON: cache, now: now)
        }
    }

    @Test("Throws plaintextNotJSON on garbage input")
    func throwsOnNonJSON() {
        #expect(throws: TokenReader.ReadError.self) {
            try TokenReader.selectToken(plaintextJSON: Data("not json".utf8), now: now)
        }
    }
}

@Suite("TokenReader.decrypt input validation")
struct TokenReaderDecryptValidationTests {
    @Test("Throws unsupportedScheme when v10 prefix is missing")
    func rejectsNonV10() {
        let blob = Data([0x76, 0x32, 0x30, 0x01, 0x02, 0x03])  // "v20..."
        #expect(throws: TokenReader.ReadError.self) {
            try TokenReader.decrypt(blob: blob, password: Data("pw".utf8))
        }
    }

    @Test("Throws unsupportedScheme on empty blob")
    func rejectsEmpty() {
        #expect(throws: TokenReader.ReadError.self) {
            try TokenReader.decrypt(blob: Data(), password: Data("pw".utf8))
        }
    }
}

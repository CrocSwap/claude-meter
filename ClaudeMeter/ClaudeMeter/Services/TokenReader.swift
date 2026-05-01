import Foundation
import Security
import CommonCrypto

/// Reads + decrypts Claude desktop's locally-cached OAuth token.
///
/// **What's cached and what isn't:**
/// - The encrypted blob from `config.json` is re-read on every call so we
///   pick up tokens Claude desktop rotates on disk.
/// - The decrypted access token is **not** cached (it expires; rotation
///   happens via the disk blob).
/// - The Chromium "Safe Storage" master key from the macOS keychain is
///   cached two ways:
///     1. **In-memory** for the process lifetime, to avoid re-querying any
///        keychain on every poll.
///     2. **Persistently in our own keychain item** (`dev.claudemeter`
///        service), so the very first launch is the only one that prompts
///        for access to Claude desktop's `Claude Safe Storage` item.
///        Subsequent launches read from our own item silently — our app's
///        signing identity is on its ACL by default.
///   If decryption with either cached key fails (Claude desktop rotated or
///   reinstalled), we invalidate that layer and fall through to the next.
///
/// See `docs/auth.md` for the full protocol and policy context.
enum TokenReader {
    enum ReadError: Error, Equatable {
        /// Claude desktop not installed, or never signed in.
        case keychainItemNotFound
        /// User clicked Deny on the macOS Keychain ACL prompt.
        case keychainAccessDenied
        case keychainOther(OSStatus)
        /// `~/Library/Application Support/Claude/config.json` doesn't exist.
        case configFileMissing
        case configReadFailed
        /// `oauth:tokenCache` key absent from config.json.
        case configKeyMissing
        case base64DecodeFailed
        /// Blob doesn't start with `v10` — Claude desktop changed schemes.
        case unsupportedScheme
        case decryptionFailed
        case plaintextNotJSON
        /// No cache entry has `user:profile` scope and a non-expired token.
        /// Typically means Claude desktop hasn't run recently to refresh.
        case noUsableToken
    }

    nonisolated static let keychainService = "Claude Safe Storage"
    nonisolated static let keychainAccount = "Claude"
    nonisolated static let keychainAccountFallback = "Claude Key"
    nonisolated static let configRelativePath = "Library/Application Support/Claude/config.json"
    nonisolated static let cacheJSONKey = "oauth:tokenCache"
    nonisolated static let v10Prefix = Data("v10".utf8)

    /// Service for our own keychain item that persists the Safe Storage
    /// password between launches. Distinct from `keychainService` so we
    /// never collide with Claude desktop's items.
    nonisolated static let persistedCacheService = "dev.claudemeter"
    nonisolated static let persistedCacheAccount = "claude-safe-storage"

    /// The full happy path. Throws a typed `ReadError` on any failure so
    /// callers can pick the right user-facing message.
    nonisolated static func currentToken(now: Date = Date()) throws -> String {
        let blob = try readEncryptedBlob()

        // Layer 1: in-memory cache. No keychain hit at all.
        if let cached = cachedKeychainKey() {
            do {
                let plaintext = try decrypt(blob: blob, password: cached)
                return try selectToken(plaintextJSON: plaintext, now: now)
            } catch ReadError.decryptionFailed {
                invalidateKeychainKeyCache()
            }
        }

        // Layer 2: our own keychain item. Silent read on every launch after
        // the first — our binary's signing identity is on the ACL by default,
        // so no prompt fires.
        if let persisted = readPersistedKey() {
            do {
                let plaintext = try decrypt(blob: blob, password: persisted)
                storeKeychainKey(persisted)
                return try selectToken(plaintextJSON: plaintext, now: now)
            } catch ReadError.decryptionFailed {
                // Claude desktop rotated the Safe Storage password (or was
                // reinstalled). Drop our copy and re-read from theirs, which
                // will prompt — same as a clean first launch.
                deletePersistedKey()
            }
        }

        // Layer 3: Claude desktop's keychain. This is where the user-facing
        // ACL prompts fire on first launch. Try the canonical "Claude"
        // account first; each `SecItemCopyMatching` shows its own ACL
        // prompt the first time the binary touches an item, so querying
        // both items unconditionally would prompt twice. The fallback
        // only runs when the canonical path fails for a reason the
        // fallback can plausibly fix.
        do {
            return try unlockAndDecrypt(account: keychainAccount, blob: blob, now: now)
        } catch ReadError.keychainItemNotFound, ReadError.decryptionFailed {
            return try unlockAndDecrypt(account: keychainAccountFallback, blob: blob, now: now)
        }
    }

    nonisolated private static func unlockAndDecrypt(account: String, blob: Data, now: Date) throws -> String {
        let password = try readKeychainKey(account: account)
        let plaintext = try decrypt(blob: blob, password: password)
        storeKeychainKey(password)
        // Persist for future launches. Failures here are non-fatal — worst
        // case we'll keep prompting Claude's keychain on each cold start.
        writePersistedKey(password)
        return try selectToken(plaintextJSON: plaintext, now: now)
    }

    // MARK: - Keychain key cache

    nonisolated(unsafe) private static var _cachedKeychainKey: Data?
    nonisolated private static let cacheLock = NSLock()

    nonisolated private static func cachedKeychainKey() -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _cachedKeychainKey
    }

    nonisolated private static func storeKeychainKey(_ key: Data) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cachedKeychainKey = key
    }

    nonisolated private static func invalidateKeychainKeyCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cachedKeychainKey = nil
    }

    // MARK: - Persistent cache (our own keychain item)

    /// Read the Safe Storage password we previously stashed. Returns `nil`
    /// for any failure — including the not-found case on first launch and
    /// any unexpected status. Reading our own item should not produce an
    /// ACL prompt because we created the item and our binary is on its ACL.
    nonisolated private static func readPersistedKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: persistedCacheService,
            kSecAttrAccount as String: persistedCacheAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// Persist (or update) the Safe Storage password in our own keychain
    /// item. Marked device-only so it never syncs to iCloud Keychain.
    nonisolated private static func writePersistedKey(_ key: Data) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: persistedCacheService,
            kSecAttrAccount as String: persistedCacheAccount,
        ]
        var addAttrs = identity
        addAttrs[kSecValueData as String] = key
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttrs: [String: Any] = [kSecValueData as String: key]
            _ = SecItemUpdate(identity as CFDictionary, updateAttrs as CFDictionary)
        }
    }

    nonisolated private static func deletePersistedKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: persistedCacheService,
            kSecAttrAccount as String: persistedCacheAccount,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - I/O steps (not unit tested — exercised end-to-end at runtime)

    /// One keychain query, one possible ACL prompt. The two-account fallback
    /// lives in `currentToken` instead, so we never trigger two prompts in a
    /// single read.
    nonisolated private static func readKeychainKey(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw ReadError.keychainOther(status) }
            return data
        case errSecItemNotFound:
            throw ReadError.keychainItemNotFound
        case errSecAuthFailed, errSecInteractionRequired, errSecInteractionNotAllowed, errSecUserCanceled:
            throw ReadError.keychainAccessDenied
        default:
            throw ReadError.keychainOther(status)
        }
    }

    nonisolated private static func readEncryptedBlob() throws -> Data {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(configRelativePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ReadError.configFileMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ReadError.configReadFailed
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dict = json as? [String: Any],
            let b64 = dict[cacheJSONKey] as? String
        else {
            throw ReadError.configKeyMissing
        }
        guard let blob = Data(base64Encoded: b64) else {
            throw ReadError.base64DecodeFailed
        }
        return blob
    }

    // MARK: - Pure helpers (unit tested)

    /// Chromium Safe Storage decryption: PBKDF2-HMAC-SHA1 → AES-128-CBC.
    nonisolated static func decrypt(blob: Data, password: Data) throws -> Data {
        guard blob.count > v10Prefix.count, blob.prefix(v10Prefix.count) == v10Prefix else {
            throw ReadError.unsupportedScheme
        }
        let ciphertext = Data(blob.dropFirst(v10Prefix.count))

        let key = derivePBKDF2Key(password: password,
                                  salt: Data("saltysalt".utf8),
                                  iterations: 1003,
                                  keyLength: 16)
        guard let key else { throw ReadError.decryptionFailed }

        let iv = Data(repeating: 0x20, count: 16)
        guard let plaintext = aes128CBCDecrypt(ciphertext: ciphertext, key: key, iv: iv) else {
            throw ReadError.decryptionFailed
        }
        return plaintext
    }

    /// Pick the cache entry with `user:profile` scope and a non-expired
    /// `expiresAt` (milliseconds since epoch). Returns its `token` field.
    nonisolated static func selectToken(plaintextJSON plaintext: Data, now: Date) throws -> String {
        guard
            let parsed = try? JSONSerialization.jsonObject(with: plaintext),
            let cache = parsed as? [String: Any]
        else {
            throw ReadError.plaintextNotJSON
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        for (cacheKey, value) in cache {
            guard
                cacheKey.contains("user:profile"),
                let entry = value as? [String: Any],
                let token = entry["token"] as? String,
                let expiresAt = (entry["expiresAt"] as? NSNumber)?.int64Value,
                expiresAt > nowMs
            else { continue }
            return token
        }
        throw ReadError.noUsableToken
    }

    // MARK: - CommonCrypto wrappers

    nonisolated private static func derivePBKDF2Key(password: Data, salt: Data, iterations: UInt32, keyLength: Int) -> Data? {
        let passwordCount = password.count
        let saltCount = salt.count
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedBytes -> Int32 in
            password.withUnsafeBytes { pwdBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordCount,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltCount,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    nonisolated private static func aes128CBCDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        let ciphertextCount = ciphertext.count
        let keyCount = key.count
        let outputCapacity = ciphertextCount + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var bytesDecrypted = 0
        let status = output.withUnsafeMutableBytes { outBytes -> Int32 in
            ciphertext.withUnsafeBytes { ctBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyCount,
                            ivBytes.baseAddress,
                            ctBytes.baseAddress, ciphertextCount,
                            outBytes.baseAddress, outputCapacity,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(bytesDecrypted)
    }
}

import Foundation
import Security
import CommonCrypto

/// Reads + decrypts Claude desktop's locally-cached OAuth token.
///
/// Stateless. **Re-runs on every poll**; never cache the decrypted token
/// in memory across calls — Claude desktop refreshes the token on disk in
/// the background and we want to pick up the freshest value each time.
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

    /// The full happy path. Throws a typed `ReadError` on any failure so
    /// callers can pick the right user-facing message.
    nonisolated static func currentToken(now: Date = Date()) throws -> String {
        let password = try readKeychainKey()
        let blob = try readEncryptedBlob()
        let plaintext = try decrypt(blob: blob, password: password)
        return try selectToken(plaintextJSON: plaintext, now: now)
    }

    // MARK: - I/O steps (not unit tested — exercised end-to-end at runtime)

    nonisolated private static func readKeychainKey() throws -> Data {
        var lastStatus: OSStatus = errSecItemNotFound
        for account in [keychainAccount, keychainAccountFallback] {
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
                if let data = result as? Data { return data }
            case errSecItemNotFound:
                lastStatus = status
                continue
            case errSecAuthFailed, errSecInteractionRequired, errSecInteractionNotAllowed, errSecUserCanceled:
                throw ReadError.keychainAccessDenied
            default:
                throw ReadError.keychainOther(status)
            }
        }
        throw lastStatus == errSecItemNotFound ? ReadError.keychainItemNotFound : ReadError.keychainOther(lastStatus)
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

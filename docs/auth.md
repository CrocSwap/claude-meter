# Auth: reading Claude desktop's locally-cached OAuth token

claude-meter is a passive read-only consumer of Claude desktop's existing OAuth state. We don't run an OAuth flow, don't register a third-party client, and don't store our own tokens. On every poll we decrypt the token Claude desktop has already cached on disk and use it for one HTTP call to `/api/oauth/usage`.

## Why this design

We considered (and started building) a first-party OAuth flow with our own `client_id`, but Anthropic's policy as of early 2026 explicitly restricts subscription OAuth to Claude.ai and Claude Code. See "Policy context" at the bottom for sources. The Keychain-reader path avoids the third-party-OAuth question entirely — the tokens we use were issued to *Anthropic's own* `client_id`s for the user's own Claude desktop install on the user's own machine.

This approach also has a nontrivial trade-off: a scary-looking macOS Keychain prompt the first time the app runs (cross-app Keychain reads always trigger a system dialog). For an open-source personal utility this is acceptable; for a broader-audience product it would not be.

## Last verified

- 2026-04-30 — Claude desktop 1.4758.0, on macOS 25.4 (Darwin 25.4.0).

## Hard dependencies

- Claude desktop must be installed (`/Applications/Claude.app`).
- The user must be signed in to Claude desktop with a Pro/Max account.
- Claude desktop must launch at least occasionally so its background task can refresh tokens. If Claude desktop hasn't run in long enough that the cached access token has expired, claude-meter will get HTTP 401 and surface "Open Claude desktop to refresh your sign-in" until the user does so.

## Data sources

### Keychain entry (the AES key)

| Field | Value |
|-------|-------|
| Class | `kSecClassGenericPassword` |
| Service (`kSecAttrService`) | `Claude Safe Storage` |
| Account (`kSecAttrAccount`) | `Claude` |

A second account `Claude Key` exists under the same service. Empirically the OAuth cache decrypts using `Claude`. If `Claude` ever fails to decrypt a v10 blob in the future, fall back to `Claude Key` before giving up.

### Encrypted blob (the token cache)

```
~/Library/Application Support/Claude/config.json
```

JSON key `oauth:tokenCache`. Value is base64; decoded bytes start with the ASCII prefix `v10` (3 bytes) followed by AES-128-CBC ciphertext.

## Decryption procedure

Inputs:
- `keychainPassword: Data` — UTF-8 bytes of the Keychain entry's password.
- `cipherBlobBase64: String` — value of `oauth:tokenCache`.

Steps:

1. Base64-decode → `blob`.
2. Verify `blob.prefix(3) == "v10"`. If not, abort with "unsupported scheme version."
3. `ciphertext = blob.dropFirst(3)`.
4. `key = PBKDF2-HMAC-SHA1(password=keychainPassword, salt="saltysalt", iter=1003, keyLen=16)`.
5. `IV = 16 × 0x20` (ASCII space).
6. `plaintext = AES-128-CBC-Decrypt(ciphertext, key, IV)`. Strip PKCS#7 padding.
7. Plaintext is a JSON object. Each key has the form `<client_id>:<some_id>:<audience>:<scopes>`; each value has the shape `{ "token": String, "refreshToken": String, "expiresAt": Int (ms epoch), "subscriptionType"?: String, "rateLimitTier"?: String }`.
8. Pick the entry whose key contains `user:profile` and whose `expiresAt > now()`. Use its `token` as the bearer.

`CommonCrypto` provides PBKDF2-HMAC-SHA1 (`CCKeyDerivationPBKDF`) and AES-128-CBC (`CCCrypt`). `Security.framework` provides Keychain access. Both are system frameworks.

## Critical implementation rule

**Re-read the encrypted blob on every poll. Never cache the decrypted access token across HTTP calls.**

Caching the decrypted token would defeat the auto-refresh path: when Claude desktop refreshes the token it writes new bytes to `config.json`, and we want our next poll to pick those up. The decrypt overhead is negligible (microseconds) compared to the network call, so there's no performance reason to cache.

## What we *do* cache: the Safe Storage master key

The PBKDF2 input — Claude desktop's Safe Storage password from its keychain item — is cached in two layers so that the cross-app keychain ACL prompt fires only on first install:

1. **In-memory** for the process lifetime (`_cachedKeychainKey` in `TokenReader`).
2. **Persistently in our own keychain item** under service `dev.claudemeter`, account `claude-safe-storage`, with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so it never iCloud-syncs.

The lookup order on each poll is in-memory → our keychain → Claude desktop's keychain. Reading our own item is silent (our app's signing identity is on its ACL by default). Reading Claude desktop's item is what triggers the macOS ACL prompts the first time.

The Safe Storage password is the same secret we'd be prompted to read from Claude desktop's keychain anyway — both items live on the same machine, encrypted by the same login keychain master key, so duplicating it under our own ACL doesn't change the security posture.

If decryption with either cached key fails (Claude desktop rotated or was reinstalled), the corresponding layer is invalidated and we fall through to the next, which prompts again — same one-time first-install experience.

## Failure modes and user-facing messages

| Symptom | Likely cause | Display |
|---------|--------------|---------|
| Keychain entry not found | Claude desktop not installed | "Install Claude desktop and sign in." Link to claude.ai/download. |
| `errSecItemNotFound` for `oauth:tokenCache` JSON key | User installed Claude desktop but never signed in | "Sign in to Claude desktop to enable Claude Meter." |
| Keychain access denied (`errSecAuthFailed` / user clicked Deny) | First-launch Keychain ACL prompt declined | "Allow Keychain access to read Claude's sign-in. (Open System Settings → Privacy & Security)." With a retry button. |
| `config.json` missing | Same as above | "Sign in to Claude desktop." |
| Base64 decode fails / `v10` prefix missing | Storage format changed in a future Claude desktop release | "Claude desktop changed its storage format. Update Claude Meter." |
| AES decrypt produces invalid PKCS#7 padding | Key/account pair changed (try `Claude Key` fallback first) | Same as above. |
| API returns 401 | Cached token expired and Claude desktop hasn't refreshed (typically because it isn't running) | "Open Claude desktop to refresh." Resume on next successful poll. |

claude-meter must distinguish these — they imply different user actions.

## What we never do

- Modify Claude desktop's Keychain entry, `config.json`, or any of its files.
- Mint our own OAuth tokens or run an OAuth flow.
- Register a third-party `client_id` with Anthropic.
- Reuse another Anthropic-developed app's `client_id` to mint tokens for ourselves.
- Send Claude desktop's `User-Agent` string. We send our own (`claude-meter/<version> (macOS)`) so any detection on Anthropic's side sees us as ourselves, not as Claude desktop.
- Cache the decrypted access token across polls.
- Send tokens off-device. (The persistent Safe Storage key cache stays on-device — `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.)

## Re-verification

When Claude desktop ships a new version, sanity-check:

```sh
# Keychain entry still where we expect
security find-generic-password -s "Claude Safe Storage" -a "Claude" -g 2>&1 | head

# oauth:tokenCache key still in config.json
grep -o '"oauth:[^"]*"' ~/Library/Application\ Support/Claude/config.json

# v10 prefix still in use
python3 -c "import json,base64; v=json.load(open('$HOME/Library/Application Support/Claude/config.json'))['oauth:tokenCache']; print(base64.b64decode(v)[:8])"
```

The `utils/probe-token-cache.sh` script does a more thorough sweep — it walks every entry in the cache, decodes the cache key, and tests each token against `/api/oauth/usage`. Run it after any major Claude desktop version bump.

## Policy context (open question)

Anthropic publicly stated in early 2026 that subscription OAuth tokens are intended only for Claude.ai and Claude Code, and using them in other tools "constitutes a violation of the Consumer Terms of Service." The enforcement target was clearly third-party tools that proxied inference via subscription tokens (the "OpenClaw" pattern). Whether the policy applies to a personal read-only metadata utility like claude-meter is unclear in the policy text.

We are reaching out to Anthropic developer support to ask. Possible outcomes:
- **Sanctioned**: they offer an explicit OK or a proper API key for usage queries → claude-meter ships as designed.
- **Tolerated**: no formal blessing but no objection → claude-meter ships with a README note that it depends on undocumented behavior.
- **Refused**: they ask us to stop → claude-meter is shut down. The local-decrypt path is more polite to remove than a third-party OAuth registration would have been.

References (collected during 2026-04-30 research):
- The Register, *Anthropic clarifies ban on third-party tool access to Claude* (2026-02-20).
- MindStudio, *What Is the OpenClaw Ban?*
- claude-code GitHub Issue #28091, *Anthropic disabled OAuth tokens for third-party apps*.
- Claude Code authentication docs at `code.claude.com/docs/en/authentication`.

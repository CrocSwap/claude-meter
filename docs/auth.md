# Auth: claude-meter's OAuth flow

claude-meter performs its own OAuth 2.0 sign-in (Authorization Code grant + PKCE) on first launch. Tokens are stored in the macOS Keychain under a service we own. We do not read any other app's storage.

This document describes the design and tracks the unresolved questions that block implementation.

## Last updated

- 2026-04-30 — pivoted from "read Claude desktop's encrypted token" to first-party OAuth.
- 2026-04-30 — empirical reconnaissance against Claude desktop's local token cache pinned several previously open answers. See "Empirical findings" below.

## Empirical findings (from Claude desktop's local token cache)

By inspecting the structure of the OAuth token cache that Claude desktop maintains locally — without using the tokens or storing them — we have concrete answers to several previously open questions:

| Question | Answer |
|----------|--------|
| Does Anthropic support multi-client OAuth? | **Yes.** Three distinct UUID-style `client_id`s observed (Claude desktop, Claude Code CLI, and a "Claude for Office" client). Implies registration is possible — though the *process* for third parties is still TBD. |
| Audience | `https://api.anthropic.com` |
| Scope namespace | `user:<resource>[:<sub>]`. Observed: `user:profile`, `user:inference`, `user:file_upload`, `user:office`, `user:sessions:claude_code`. |
| Required scope for `/api/oauth/usage` | **`user:profile`** — the API explicitly says so in 403 responses. |
| Token format | Opaque ~108-char string. **Not a JWT** — we cannot decode `exp` from the token itself. |
| Token-exchange response shape (observed) | `{ token: String, refreshToken: String, expiresAt: Int (ms epoch), subscriptionType?: String, rateLimitTier?: String }`. Note `expiresAt` is **milliseconds**, not seconds. |
| Bearer header name in API calls | Standard `Authorization: Bearer <token>`. The `anthropic-beta: oauth-2025-04-20` header is also required on `/api/oauth/usage`. |

For the OAuth flow we will build, request scope `user:profile`. Add `user:inference`/etc. only if a future feature actually needs them.

## Still open

| Question | Why it matters |
|----------|---------------|
| **Is there a public OAuth client registration program for third-party apps?** | We have empirical proof multi-client OAuth exists; we don't know how to register our own `client_id` legitimately. This is the biggest unresolved blocker. |
| Authorization endpoint URL | Likely `https://claude.ai/oauth/authorize` or `https://auth.anthropic.com/...`; needs confirmation. |
| Token endpoint URL | Likely under `api.anthropic.com`; needs confirmation. |
| Accepted redirect URI patterns for native apps | Determines whether we use `claude-meter://oauth/callback` (custom scheme) or `http://127.0.0.1:<port>/callback` (loopback). |
| Access token / refresh token TTLs | We saw `expiresAt` values ~30 days out for Claude desktop's tokens. Confirm typical values; drives proactive-refresh behavior. |
| Client secret requirement | We assume PKCE-only (no `client_secret`). Verify Anthropic's spec rejects flows that demand embedded secrets. |

If a public registration program is unavailable, do **not** reuse another Anthropic app's `client_id`. See "Fallback path" below.

## Design (assuming OAuth is available)

### Flow

```
┌──────────────┐                                     ┌──────────────────┐
│  claude-     │  1. user clicks "Sign in"           │   Anthropic      │
│  meter       │ ─────────────────────────────────►  │   auth endpoint  │
│  (popover)   │     ASWebAuthenticationSession      │                  │
│              │     ?response_type=code             │                  │
│              │     &client_id=<ours>               │                  │
│              │     &redirect_uri=claude-meter://…  │                  │
│              │     &code_challenge=<S256>          │                  │
│              │     &scope=<usage:read?>            │                  │
│              │     &state=<random>                 │                  │
│              │                                     │                  │
│              │  2. user signs in on anthropic.com  │                  │
│              │  3. callback claude-meter://oauth/  │                  │
│              │     callback?code=…&state=…         │                  │
│              │ ◄─────────────────────────────────  │                  │
│              │                                     │                  │
│              │  4. POST /token                     │                  │
│              │     grant_type=authorization_code   │                  │
│              │     code=…                          │                  │
│              │     code_verifier=…                 │                  │
│              │     client_id=<ours>                │                  │
│              │     redirect_uri=claude-meter://…   │                  │
│              │ ─────────────────────────────────►  │                  │
│              │                                     │                  │
│              │  5. { access_token, refresh_token,  │                  │
│              │       expires_in, token_type }      │                  │
│              │ ◄─────────────────────────────────  │                  │
│              │                                     │                  │
│              │  6. tokens → Keychain               │                  │
└──────────────┘                                     └──────────────────┘
```

### PKCE specifics

- `code_verifier`: 43–128 chars from `[A-Z][a-z][0-9]-._~`. Generate 96 random bytes, base64url-encode (no padding), trim if needed.
- `code_challenge`: `base64url(sha256(code_verifier))`, no padding.
- `code_challenge_method`: `S256`.
- `state`: 32 random bytes, base64url. Verified on callback to defeat CSRF.

### Token storage

Single Keychain item:

| Field | Value |
|-------|-------|
| Class | `kSecClassGenericPassword` |
| Service (`kSecAttrService`) | `dev.claudemeter.oauth` |
| Account (`kSecAttrAccount`) | A fixed string like `default`. Anthropic's tokens are opaque (not JWTs), so there's no embedded user identifier. If a future API gives us an account ID, switch to it. |
| Data | UTF-8 JSON: `{"token":"<opaque ~108 chars>","refreshToken":"<opaque>","expiresAt":<ms-epoch int>}`. Field names mirror what we expect from Anthropic's token endpoint (per empirical observation) so round-tripping is trivial. |
| Access | App-only ACL (`kSecAttrAccessibleWhenUnlocked`). No ACL prompts on read after creation by the same signed binary. |

Why a single JSON blob and not multiple Keychain items: simplifies atomicity. Read once, parse, done.

### Refresh logic

- Before any API call, `OAuthClient.currentAccessToken()` checks if `expires_at` is within 60s of now. If so, refresh first.
- On any 401 from the API (even if `expires_at` says we're fine), force a refresh and retry the request once.
- If refresh fails with `invalid_grant` or `expired_token`: clear Keychain, post `.signedOut` to `UsageStore`, popover flips to `SignInView`.
- If refresh fails with a network error: keep tokens, surface "offline" state, retry on next poll.

### URL scheme handling

`Info.plist` registers `claude-meter://` under `CFBundleURLTypes`. The app's `@main` scene wires `.onOpenURL { url in … }` (or `application(_:open:options:)` via an `NSApplicationDelegateAdaptor`) and forwards to `OAuthClient.handleCallback(url:)`. Only `claude-meter://oauth/callback` is accepted; any other path is rejected.

Note: `ASWebAuthenticationSession` returns the callback URL directly to the calling code via its completion handler — we don't strictly need URL scheme handling for the OAuth callback itself. The scheme registration exists so that the OS knows about the scheme (some auth servers validate that the redirect URI scheme is registered) and so that, if the user accidentally clicks a `claude-meter://` link from elsewhere, our app handles it gracefully.

## Failure modes

| Symptom | User-facing message | App action |
|---------|--------------------|------------|
| User cancels `ASWebAuthenticationSession` | "Sign-in cancelled" | Return to sign-in view |
| Anthropic returns OAuth error (`error=…`) | Show `error_description` if present, otherwise the `error` code | Return to sign-in view |
| Code exchange returns 4xx | "Sign-in failed — please try again" | Return to sign-in view |
| Code exchange / refresh network failure | "Network error during sign-in" | Return to sign-in view; user retries |
| Refresh returns `invalid_grant` | "Please sign in again" | Clear Keychain, sign-in view |
| API returns 401 even after refresh | "Authentication failed — please sign in again" | Clear Keychain, sign-in view |
| `state` mismatch on callback | "Sign-in error" (do not surface CSRF jargon) | Return to sign-in view |

## What we never do

- Read other apps' Keychain entries.
- Read Claude desktop's `Application Support/Claude/` storage.
- Embed a `client_secret`. PKCE only; native apps cannot keep secrets.
- Cache tokens anywhere outside Keychain (no `UserDefaults`, no on-disk JSON).
- Implement device-flow, password grant, or any other OAuth scheme — just Authorization Code + PKCE.
- Use a third-party OAuth library. `URLSession` + `CryptoKit` (for PKCE/state random + SHA256) is enough.

## Fallback path (if Anthropic does not support third-party OAuth clients)

If, on investigation, Anthropic offers no public OAuth client registration and no documented redirect URI scheme for third-party native apps:

1. **Pause v1.** Do not reuse another app's `client_id`. Do not revert to reading Claude desktop's encrypted storage as a workaround.
2. **File the question with Anthropic** (developer support, or whatever channel exists). Document the response here.
3. **If the answer is "no public OAuth, period":** the project is on hold pending API direction. Document the state and stop. We do not silently degrade to a fragile workaround.

## Re-verification

When Anthropic ships an OAuth-related change (new `anthropic-beta` header value, deprecation notice, scope changes), update this document and revise the implementation in lockstep.

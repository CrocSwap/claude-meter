# utils/

Verification helpers used during development and for periodic re-checks against Anthropic's OAuth + usage API. **Not** part of the shipped app — these are developer-side tools.

## Scripts

### `probe-usage-api.sh`

Calls `GET https://api.anthropic.com/api/oauth/usage` and pretty-prints the response. Use this to spot-check that the API contract documented in `../docs/api.md` still holds.

```sh
# Preferred: bring your own bearer token
CLAUDE_TOKEN=<token> bash utils/probe-usage-api.sh

# Fallback (until claude-meter has its own OAuth working):
# decrypts a token from Claude desktop's local cache.
bash utils/probe-usage-api.sh
```

The fallback path will trigger one macOS Keychain prompt (for `Claude Safe Storage`).

### `probe-token-cache.sh`

Walks every entry in Claude desktop's `oauth:tokenCache`, decodes the cache key (client_id / audience / scopes), reports the value's structure, and tests each access token against `/api/oauth/usage`. Prints HTTP status + body excerpt — no token bytes.

Useful for:
- Confirming the scope namespace and required scope haven't changed.
- Discovering new OAuth `client_id`s if Anthropic ships new first-party clients.
- Spotting changes to the token cache schema in Claude desktop.

```sh
bash utils/probe-token-cache.sh
```

### `extract-claude-desktop-token.py`

Helper used by `probe-usage-api.sh` to decrypt one usable bearer token out of Claude desktop's local cache (Chromium Safe Storage scheme). Reads `_PW` and `_CONFIG_PATH` from the environment; prints the chosen token to stdout. Not generally invoked directly.

This helper is **transitional**. Once `claude-meter` has its own OAuth flow working, every script here should default to `$CLAUDE_TOKEN` and the desktop-cache decryption can be removed.

## Why these aren't in the app

- They use `python3` + `openssl` for crypto, which is fine for a developer-side script but wrong for the shipped app (Swift uses `CryptoKit`/`CommonCrypto`).
- They depend on Claude desktop's local storage scheme, which the app explicitly does **not** depend on (see `../docs/auth.md`).
- They're for verification, not user-facing functionality.

## When to re-run

- After every Anthropic-side change (new `anthropic-beta` header, new endpoint behavior).
- Before cutting a release, as a smoke test that the API contract hasn't drifted.
- When debugging "why doesn't my OAuth flow work?" — `probe-token-cache.sh` is often the fastest way to see what scopes / client_ids Anthropic currently supports.

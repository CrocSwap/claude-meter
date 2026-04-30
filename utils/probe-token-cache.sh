#!/usr/bin/env bash
# Diagnostic v3: walk each entry in the decrypted oauth:tokenCache,
# inspect the value's structure, decode any JWT-shaped access_token's
# claims (exp/aud/scope/iss only — never the signature/full token),
# and probe /api/oauth/usage with each candidate. Reports HTTP status
# only; does not print token bytes.

set -euo pipefail

CONFIG_PATH="$HOME/Library/Application Support/Claude/config.json"

KEY_CLAUDE="$(security find-generic-password -s "Claude Safe Storage" -a "Claude" -w)"

export _PW="$KEY_CLAUDE"
export _CONFIG_PATH="$CONFIG_PATH"

python3 <<'PY'
import os, json, hashlib, base64, time, urllib.request, urllib.error
from subprocess import run, PIPE

with open(os.environ["_CONFIG_PATH"]) as f:
    cfg = json.load(f)

blob = base64.b64decode(cfg["oauth:tokenCache"])
assert blob.startswith(b"v10")
ct = blob[3:]
key = hashlib.pbkdf2_hmac("sha1", os.environ["_PW"].encode(), b"saltysalt", 1003, 16)
proc = run(
    ["openssl", "enc", "-d", "-aes-128-cbc", "-K", key.hex(), "-iv", (b" "*16).hex(), "-nopad"],
    input=ct, stdout=PIPE, stderr=PIPE, check=True,
)
pt = proc.stdout
pad = pt[-1]
plaintext = pt[:-pad].decode("utf-8")
cache = json.loads(plaintext)

def b64url_decode(s: str) -> bytes:
    s += "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s)

def jwt_claims(tok: str):
    """Return (header, payload) dicts for a JWT, or None if not a JWT."""
    parts = tok.split(".")
    if len(parts) != 3:
        return None
    try:
        h = json.loads(b64url_decode(parts[0]))
        p = json.loads(b64url_decode(parts[1]))
        return h, p
    except Exception:
        return None

def call_usage(tok: str):
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {tok}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-meter-probe/0.0 (macOS)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return e.code, body
    except Exception as e:
        return None, f"network error: {e}"

now = int(time.time())
print(f"current epoch: {now}\n")

for i, (cache_key, entry) in enumerate(cache.items()):
    print(f"=== entry [{i}] ===")
    parts = cache_key.split(":", 3)
    if len(parts) >= 3:
        print(f"  client_id : {parts[0]}")
        print(f"  ?id       : {parts[1]}")
        print(f"  audience  : {parts[2]}")
        if len(parts) > 3:
            print(f"  scopes    : {parts[3]}")
        else:
            print(f"  scopes    : (none in key)")
    else:
        print(f"  cache_key (unparseable): {cache_key[:60]}...")

    if not isinstance(entry, dict):
        print(f"  value is not a dict: type={type(entry).__name__}")
        print()
        continue

    print(f"  value keys: {sorted(entry.keys())}")
    for fk, fv in entry.items():
        if isinstance(fv, str):
            print(f"    {fk}: <string len={len(fv)}>")
        else:
            print(f"    {fk}: {fv!r}")

    candidate = None
    for tok_field in ("access_token", "accessToken", "token", "id_token"):
        if tok_field in entry and isinstance(entry[tok_field], str):
            candidate = (tok_field, entry[tok_field])
            break

    if candidate is None:
        print("  no access-token-shaped field found")
        print()
        continue

    tok_field, tok = candidate
    print(f"  using field: {tok_field}")

    claims = jwt_claims(tok)
    if claims is None:
        print(f"  not a JWT (or undecodable)")
    else:
        h, p = claims
        safe_payload = {k: p.get(k) for k in ("iss", "aud", "scope", "scp", "client_id", "azp", "exp", "iat", "nbf", "sub_type", "token_type") if k in p}
        if "exp" in p:
            ttl = p["exp"] - now
            safe_payload["_ttl_seconds"] = ttl
            safe_payload["_expired"] = ttl < 0
        print(f"  JWT header : {h}")
        print(f"  JWT claims : {json.dumps(safe_payload, sort_keys=True)}")

    status, body = call_usage(tok)
    if status == 200:
        body_short = body[:400] + ("..." if len(body) > 400 else "")
        print(f"  /api/oauth/usage : HTTP 200  body={body_short}")
    else:
        body_short = body[:200] + ("..." if len(body) > 200 else "")
        print(f"  /api/oauth/usage : HTTP {status}  body={body_short}")
    print()
PY

unset _PW _CONFIG_PATH
echo
echo "Done. None of the printed output contains token bytes; share freely."
echo "(If a 200 hit shows real usage numbers in the body, those reflect YOUR account — feel free to redact percentages if you'd rather.)"

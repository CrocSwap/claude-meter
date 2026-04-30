#!/usr/bin/env python3
"""Pick a working access token from Claude desktop's tokenCache and print it."""

import os, json, hashlib, base64, time, sys
from subprocess import run, PIPE

config_path = os.environ["_CONFIG_PATH"]
pw = os.environ["_PW"].encode()

with open(config_path) as f:
    cfg = json.load(f)

blob = base64.b64decode(cfg["oauth:tokenCache"])
assert blob.startswith(b"v10"), f"unexpected prefix {blob[:3]!r}"
ct = blob[3:]
key = hashlib.pbkdf2_hmac("sha1", pw, b"saltysalt", 1003, 16)
proc = run(
    ["openssl", "enc", "-d", "-aes-128-cbc",
     "-K", key.hex(), "-iv", (b" " * 16).hex(), "-nopad"],
    input=ct, stdout=PIPE, check=True,
)
pt = proc.stdout
plaintext = pt[:-pt[-1]].decode("utf-8")
cache = json.loads(plaintext)

now_ms = int(time.time() * 1000)
chosen = None
for k, v in cache.items():
    if not isinstance(v, dict) or "token" not in v:
        continue
    if "user:profile" not in k:
        continue
    if int(v.get("expiresAt", 0)) < now_ms:
        continue
    chosen = v
    break

if chosen is None:
    print("no usable entry found (need a non-expired token with user:profile scope)", file=sys.stderr)
    sys.exit(1)

print(chosen["token"])

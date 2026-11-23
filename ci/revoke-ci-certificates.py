#!/usr/bin/env python3
"""Revokes the signing certificates earlier CI runs made, before a release
signs. Each run is a fresh machine: Xcode makes a new certificate with the
App Store Connect key ("Created via API") and the account soon reaches
Apple's limit. Only those go; a certificate made on a Mac or by hand stays.

Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID; prints what it revoked.
"""
import json
import os
import sys
import time
import urllib.request

import jwt  # PyJWT, with cryptography for ES256

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def ask(method: str, url: str, bearer: str):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {bearer}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        return json.loads(body) if body else None


def main() -> int:
    bearer = token()
    url = f"{API}/certificates?limit=200"
    revoked = 0
    while url:
        page = ask("GET", url, bearer)
        for cert in page.get("data", []):
            a = cert.get("attributes", {})
            name = a.get("name") or ""
            kind = a.get("certificateType") or ""
            made_by_ci = "Created via API" in name
            signing = kind in ("DEVELOPMENT", "IOS_DEVELOPMENT", "DISTRIBUTION", "IOS_DISTRIBUTION")
            if made_by_ci and signing:
                ask("DELETE", f"{API}/certificates/{cert['id']}", bearer)
                print(f"revoked {kind} {cert['id']} ({a.get('displayName') or name}, until {a.get('expirationDate')})")
                revoked += 1
        url = page.get("links", {}).get("next")
    print(f"revoked {revoked} certificate(s) earlier runs made")
    return 0


if __name__ == "__main__":
    sys.exit(main())

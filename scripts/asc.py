#!/usr/bin/env python3
"""Minimal App Store Connect API client.

Reads the key from ios/AuthKey_<KEY_ID>.p8 (git-ignored). Used by the release
tooling to inspect builds and set store metadata that fastlane does not cover.

Usage:
    python3 scripts/asc.py get apps
    python3 scripts/asc.py get builds --params 'filter[app]=<id>&limit=5'
"""
import argparse
import json
import sys
import time
from pathlib import Path
from urllib import error, parse, request

import jwt

KEY_ID = "9UC6PN6P9K"
ISSUER_ID = "09ca85e3-ffa2-4b6c-ada5-7c031ec5eb14"
BUNDLE_ID = "com.icos.game"
BASE = "https://api.appstoreconnect.apple.com/v1"
KEY_PATH = Path(__file__).resolve().parent.parent / "ios" / f"AuthKey_{KEY_ID}.p8"


def token() -> str:
    private_key = KEY_PATH.read_text()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload, private_key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"}
    )


def call(method: str, path: str, params: str | None = None, body: dict | None = None):
    url = path if path.startswith("http") else f"{BASE}/{path.lstrip('/')}"
    if params:
        url += ("&" if "?" in url else "?") + params
    data = json.dumps(body).encode() if body is not None else None
    req = request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except error.HTTPError as exc:
        raw = exc.read()
        try:
            return exc.code, json.loads(raw)
        except Exception:
            return exc.code, raw.decode()[:500]


def app_id() -> str:
    _, data = call("GET", "apps", f"filter[bundleId]={parse.quote(BUNDLE_ID)}")
    return data["data"][0]["id"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("method", choices=["get", "post", "patch", "delete", "appid"])
    ap.add_argument("path", nargs="?", default="")
    ap.add_argument("--params")
    ap.add_argument("--body")
    args = ap.parse_args()

    if args.method == "appid":
        print(app_id())
        return 0

    status, data = call(
        args.method.upper(),
        args.path,
        args.params,
        json.loads(args.body) if args.body else None,
    )
    print(f"HTTP {status}")
    print(json.dumps(data, indent=2)[:6000])
    return 0 if status < 400 else 1


if __name__ == "__main__":
    sys.exit(main())

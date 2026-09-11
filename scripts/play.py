#!/usr/bin/env python3
"""Minimal Google Play Developer API client.

Reads android/play-store-credentials.json (git-ignored). Used by the release
tooling to fill the store listing and push bundles, which the fastlane lanes
cannot do for a first release.
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

PKG = 'com.icos.game'
ROOT = Path(__file__).resolve().parent.parent
KEY_PATH = ROOT / 'android' / 'play-store-credentials.json'
BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications'

_token: str | None = None


def token() -> str:
    global _token
    if _token:
        return _token
    key = json.loads(KEY_PATH.read_text())
    now = int(time.time())
    assertion = jwt.encode(
        {
            'iss': key['client_email'],
            'scope': 'https://www.googleapis.com/auth/androidpublisher',
            'aud': key['token_uri'],
            'iat': now,
            'exp': now + 3600,
        },
        key['private_key'],
        algorithm='RS256',
    )
    body = urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
    }).encode()
    with urllib.request.urlopen(
        urllib.request.Request(key['token_uri'], data=body), timeout=60
    ) as resp:
        _token = json.loads(resp.read())['access_token']
    return _token


def call(method: str, url: str, data=None, content_type='application/json'):
    if isinstance(data, dict):
        data = json.dumps(data).encode()
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={'Authorization': f'Bearer {token()}', 'Content-Type': content_type},
    )
    try:
        with urllib.request.urlopen(req, timeout=900) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            return exc.code, json.loads(raw)
        except Exception:
            return exc.code, {'raw': raw.decode()[:600]}


def edit(method: str, path: str, data=None):
    return call(method, f'{BASE}/{PKG}/{path}', data)


def upload(path: str, blob: bytes, content_type: str):
    return call('POST', f'{UPLOAD}/{PKG}/{path}?uploadType=media', blob, content_type)


def why(data) -> str:
    return data.get('error', {}).get('message', json.dumps(data)[:300])

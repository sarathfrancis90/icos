#!/usr/bin/env python3
"""Preflight for Google and Apple sign-in.

Checks the parts that are easy to get wrong and silent when wrong: whether
Supabase actually has the providers switched on, whether the client ids are
real, and whether the iOS URL scheme matches the client id.

Usage:
    python3 scripts/check_signin.py [.env.production]
Exit code is non-zero if anything required is missing.
"""
import json
import plistlib
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / 'ios' / 'Runner' / 'Info.plist'
OK, BAD, WARN = 'ok  ', 'FAIL', 'warn'
failures = 0


def line(status, label, detail=''):
    global failures
    if status is BAD:
        failures += 1
    print(f'  [{status}] {label}' + (f' — {detail}' if detail else ''))


def env(path: Path) -> dict:
    out = {}
    for raw in path.read_text().splitlines():
        s = raw.strip()
        if s and not s.startswith('#') and '=' in s:
            k, _, v = s.partition('=')
            out[k.strip()] = v.strip().strip('"')
    return out


def supabase_providers(url: str, anon: str) -> dict:
    req = urllib.request.Request(f'{url}/auth/v1/settings', headers={'apikey': anon})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r).get('external', {})


def authorize_client_id(url: str, provider: str) -> str | None:
    """The client_id Supabase hands to the provider for the web redirect flow.

    Supabase uses the *first* entry of its Client IDs list here, and that choice
    matters for Apple: the web flow only accepts a Services ID, never a bundle id.
    """
    target = (f'{url}/auth/v1/authorize?provider={provider}'
              '&redirect_to=io.supabase.icos%3A%2F%2Flogin-callback')
    req = urllib.request.Request(target, method='GET')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None
    opener = urllib.request.build_opener(NoRedirect)
    try:
        opener.open(req, timeout=40)
        return None
    except urllib.error.HTTPError as exc:
        loc = exc.headers.get('location')
        if not loc:
            return None
        import urllib.parse as up
        return up.parse_qs(up.urlparse(loc).query).get('client_id', [None])[0]


def apple_accepts(client_id: str, callback: str) -> bool:
    """Ask Apple directly whether it will serve a sign-in page for this id."""
    import urllib.parse as up
    target = ('https://appleid.apple.com/auth/authorize?'
              + up.urlencode({'client_id': client_id, 'redirect_uri': callback,
                              'response_type': 'code', 'scope': 'email name',
                              'response_mode': 'form_post'}))
    try:
        with urllib.request.urlopen(target, timeout=40) as r:
            body = r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as exc:
        body = exc.read().decode('utf-8', 'replace')
    except urllib.error.URLError:
        return False
    return 'Invalid client id' not in body and 'invalid_request' not in body


def url_schemes() -> list[str]:
    raw = subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', str(PLIST)],
                         capture_output=True).stdout
    data = plistlib.loads(raw)
    out = []
    for entry in data.get('CFBundleURLTypes', []):
        out += entry.get('CFBundleURLSchemes', [])
    return out


def main() -> int:
    cfg = env(Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / '.env.production'))
    web = cfg.get('GOOGLE_WEB_CLIENT_ID', '')
    ios = cfg.get('GOOGLE_IOS_CLIENT_ID', '')

    print('Supabase providers')
    try:
        ext = supabase_providers(cfg['SUPABASE_URL'], cfg['SUPABASE_ANON_KEY'])
        line(OK if ext.get('google') else BAD, 'Google provider enabled',
             '' if ext.get('google') else 'Auth > Sign In / Providers > Google')
        line(OK if ext.get('apple') else BAD, 'Apple provider enabled',
             '' if ext.get('apple') else 'Auth > Sign In / Providers > Apple')
        line(OK if ext.get('anonymous_users') else BAD, 'Anonymous sign-in enabled')
    except (urllib.error.URLError, KeyError) as exc:
        line(BAD, 'could not reach Supabase', str(exc))

    print('\nWeb redirect flow (used for every sign-in, because the app starts anonymous)')
    base = cfg.get('SUPABASE_URL', '')
    callback = f'{base}/auth/v1/callback'
    g_cid = authorize_client_id(base, 'google')
    line(OK if g_cid and g_cid == web else BAD, 'Google authorize client_id',
         g_cid or 'no redirect')
    a_cid = authorize_client_id(base, 'apple')
    if not a_cid:
        line(BAD, 'Apple authorize client_id', 'no redirect')
    elif not apple_accepts(a_cid, callback):
        line(BAD, f'Apple rejects client_id {a_cid}',
             'put the Services ID first in Supabase > Apple > Client IDs')
    else:
        line(OK, 'Apple authorize client_id', a_cid)

    print('\nGoogle client ids')
    for label, val in [('web/server client id', web), ('iOS client id', ios)]:
        if not val:
            line(BAD, label, 'empty')
        elif val.startswith('REPLACE_ME'):
            line(BAD, label, 'still the placeholder')
        elif not val.endswith('.apps.googleusercontent.com'):
            line(BAD, label, f'malformed: {val}')
        else:
            line(OK, label, val[:22] + '...')

    print('\niOS URL schemes in Info.plist')
    schemes = url_schemes()
    line(OK if 'io.supabase.icos' in schemes else BAD,
         'Supabase callback scheme io.supabase.icos')
    google = [s for s in schemes if s.startswith('com.googleusercontent.apps')]
    if not google:
        line(WARN, 'reversed Google scheme absent',
             'injected at build time by scripts/inject_google_url_scheme.sh')
    elif google == ['com.googleusercontent.apps.']:
        line(BAD, 'reversed Google scheme is a stub',
             'built from an empty client id')
    elif ios and google[0] != f"com.googleusercontent.apps.{ios.removesuffix('.apps.googleusercontent.com')}":
        line(BAD, 'reversed Google scheme does not match the client id', google[0])
    else:
        line(OK, 'reversed Google scheme', google[0][:34] + '...')

    print()
    if failures:
        print(f'{failures} problem(s). Google/Apple sign-in will not work until these are fixed.')
    else:
        print('Sign-in configuration looks complete.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

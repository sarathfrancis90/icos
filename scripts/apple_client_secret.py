#!/usr/bin/env python3
"""Mint the Apple "client secret" JWT that Supabase asks for.

Supabase's Apple provider wants a JWT, not the raw .p8. Apple defines that
client secret as an ES256 JWT signed with a Sign in with Apple key, and caps its
lifetime at six months, which is why the dashboard warns about expiry.

Usage:
    python3 scripts/apple_client_secret.py --key-id 4VC547SXCV
    python3 scripts/apple_client_secret.py --key-id 4VC547SXCV --copy

Regenerate before it expires or web sign-in stops working. Native iOS sign-in
does not use this secret, so it keeps working either way.
"""
import argparse
import datetime
import subprocess
import sys
from pathlib import Path

import jwt

ROOT = Path(__file__).resolve().parent.parent
TEAM_ID = 'H845PX7Q62'
SERVICES_ID = 'com.icos.game.signin'
AUDIENCE = 'https://appleid.apple.com'
SIX_MONTHS = 15777000  # Apple's hard maximum, in seconds


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--key-id', required=True, help='Key ID of the Sign in with Apple key')
    ap.add_argument('--team-id', default=TEAM_ID)
    ap.add_argument('--services-id', default=SERVICES_ID)
    ap.add_argument('--key-path', help='defaults to ios/AuthKey_<key-id>.p8')
    ap.add_argument('--copy', action='store_true', help='copy to the clipboard instead of printing')
    args = ap.parse_args()

    key_path = Path(args.key_path) if args.key_path else ROOT / 'ios' / f'AuthKey_{args.key_id}.p8'
    if not key_path.exists():
        raise SystemExit(f'key not found: {key_path}')

    now = datetime.datetime.now(datetime.timezone.utc)
    exp = now + datetime.timedelta(seconds=SIX_MONTHS)

    token = jwt.encode(
        {
            'iss': args.team_id,
            'iat': int(now.timestamp()),
            'exp': int(exp.timestamp()),
            'aud': AUDIENCE,
            'sub': args.services_id,
        },
        key_path.read_text(),
        algorithm='ES256',
        headers={'kid': args.key_id, 'alg': 'ES256'},
    )

    print(f'team id     : {args.team_id}', file=sys.stderr)
    print(f'services id : {args.services_id}', file=sys.stderr)
    print(f'key id      : {args.key_id}', file=sys.stderr)
    print(f'expires     : {exp:%Y-%m-%d} (regenerate before then)', file=sys.stderr)

    if args.copy:
        subprocess.run(['pbcopy'], input=token.encode(), check=True)
        print('\nJWT copied to the clipboard. Paste it into Supabase > Apple >'
              ' Secret Key (for OAuth).', file=sys.stderr)
    else:
        print(token)
    return 0


if __name__ == '__main__':
    sys.exit(main())

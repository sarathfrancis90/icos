#!/usr/bin/env bash
# Write the Google OAuth client ids into .env.production, then re-run the
# sign-in preflight.
#
# Usage:
#   scripts/set_google_ids.sh <web-client-id> <ios-client-id>
#
# Both must be the full form ending .apps.googleusercontent.com.
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env.production}"

if [ $# -ne 2 ]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

WEB="$1"
IOS="$2"

for pair in "web:$WEB" "ios:$IOS"; do
  label="${pair%%:*}"; value="${pair#*:}"
  case "$value" in
    *.apps.googleusercontent.com) ;;
    *) echo "error: $label client id must end in .apps.googleusercontent.com (got: $value)" >&2
       exit 1 ;;
  esac
  case "$value" in
    REPLACE_ME*) echo "error: $label client id is still the placeholder" >&2; exit 1 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "error: $ENV_FILE not found" >&2
  exit 1
fi

cp "$ENV_FILE" "$ENV_FILE.bak"

python3 - "$ENV_FILE" "$WEB" "$IOS" <<'PY'
import sys
path, web, ios = sys.argv[1], sys.argv[2], sys.argv[3]
want = {'GOOGLE_WEB_CLIENT_ID': web, 'GOOGLE_IOS_CLIENT_ID': ios}
out, seen = [], set()
for line in open(path).read().splitlines():
    s = line.strip()
    if s and not s.startswith('#') and '=' in s:
        k = s.split('=', 1)[0].strip()
        if k in want:
            out.append(f'{k}={want[k]}')
            seen.add(k)
            continue
    out.append(line)
for k, v in want.items():
    if k not in seen:
        out.append(f'{k}={v}')
open(path, 'w').write('\n'.join(out) + '\n')
PY

echo "wrote $ENV_FILE (previous copy at $ENV_FILE.bak)"
echo
python3 scripts/check_signin.py "$ENV_FILE"

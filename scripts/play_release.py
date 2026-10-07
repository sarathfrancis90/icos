#!/usr/bin/env python3
"""Upload the release App Bundle to Google Play and roll it out to the test tracks.

Usage: scripts/play_release.py [--tracks internal,alpha] [--aab PATH] [--mapping PATH]

Uses the Edits API through scripts/play.py (service-account credentials in the
git-ignored android/play-store-credentials.json). Steps: create edit, upload the
bundle, upload the R8 mapping file, set each track's release to the new version
code with status "completed", commit the edit. Prints one line per step and
exits non-zero on the first failure.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import play  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tracks', default='internal,alpha')
    ap.add_argument('--aab', default=str(ROOT / 'build/app/outputs/bundle/release/app-release.aab'))
    ap.add_argument('--mapping', default=str(ROOT / 'build/app/outputs/mapping/release/mapping.txt'))
    args = ap.parse_args()

    aab = Path(args.aab)
    mapping = Path(args.mapping)
    if not aab.exists():
        print(f'missing bundle: {aab}')
        return 1

    status, data = play.edit('POST', 'edits', {})
    if status != 200:
        print('edit:', status, play.why(data))
        return 1
    edit_id = data['id']

    status, data = play.upload(f'edits/{edit_id}/bundles', aab.read_bytes(), 'application/octet-stream')
    if status != 200:
        print('bundle:', status, play.why(data))
        return 1
    version_code = data['versionCode']
    print('bundle:', status, version_code)

    if mapping.exists():
        status, data = play.upload(
            f'edits/{edit_id}/apks/{version_code}/deobfuscationFiles/proguard',
            mapping.read_bytes(), 'application/octet-stream')
        print('mapping:', status, '' if status == 200 else play.why(data))
    else:
        print('mapping: skipped (no file)')

    for track in [t.strip() for t in args.tracks.split(',') if t.strip()]:
        status, data = play.edit('PUT', f'edits/{edit_id}/tracks/{track}', {
            'track': track,
            'releases': [{'versionCodes': [str(version_code)], 'status': 'completed'}],
        })
        print(track, status, '' if status == 200 else play.why(data))
        if status != 200:
            return 1

    status, data = play.edit('POST', f'edits/{edit_id}:commit')
    print('commit:', status, '' if status == 200 else play.why(data))
    return 0 if status == 200 else 1


if __name__ == '__main__':
    sys.exit(main())

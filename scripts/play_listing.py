#!/usr/bin/env python3
"""Fill the Google Play default store listing: text, icon, feature graphic and
phone screenshots.

The Play Console page is long and every field is required, so this writes the
lot in one edit from the assets already in release/google-play/.

Usage:
    python3 scripts/play_listing.py            # apply
    python3 scripts/play_listing.py --dry-run  # show what would be sent
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import play  # noqa: E402

LANG = 'en-US'
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'release' / 'google-play'
COPY = ASSETS / 'store_listing.txt'


# A heading line in store_listing.txt: all-caps, optional "(80 char max)" note.
HEADING = re.compile(r'^[A-Z][A-Z0-9 ]*(?:\([^)]*\))?:\s*$')


def sections() -> dict[str, str]:
    """Split store_listing.txt into its labelled blocks."""
    out, key, buf = {}, None, []
    for line in COPY.read_text().splitlines():
        if HEADING.match(line):
            if key:
                out[key] = '\n'.join(buf).strip()
            key = line.split('(')[0].split(':')[0].strip()
            buf = []
        elif set(line.strip()) <= {'-', '='} and len(line.strip()) > 8:
            continue  # rule line
        elif key:
            buf.append(line)
    if key:
        out[key] = '\n'.join(buf).strip()
    return out


def section(name: str) -> str:
    value = sections().get(name)
    if not value:
        raise SystemExit(f'could not find "{name}" in {COPY}')
    return value


def main() -> int:
    dry = '--dry-run' in sys.argv

    title = section('APP TITLE')
    short = section('SHORT DESCRIPTION')
    full = section('FULL DESCRIPTION')

    for label, value, limit in [('title', title, 30), ('short', short, 80),
                                ('full', full, 4000)]:
        if len(value) > limit:
            raise SystemExit(f'{label} is {len(value)} chars, limit {limit}')
        print(f'{label:6}: {len(value):>4}/{limit}  {value.splitlines()[0][:60]}')

    icon = ASSETS / 'hi_res_icon.png'
    feature = ASSETS / 'feature_graphic.png'
    shots = sorted((ASSETS / 'screenshots').glob('*.png'))
    # Same tablet capture serves both tablet slots; without either, Play shows
    # a "Designed for phones" note on tablets.
    tablet = sorted((ASSETS / 'screenshots-tablet').glob('*.png'))
    print(f'icon  : {icon.name}')
    print(f'feature: {feature.name}')
    print(f'shots : {len(shots)} phone -> {", ".join(s.name for s in shots)}')
    print(f'tablet: {len(tablet)} tablet')
    if not 2 <= len(shots) <= 8:
        raise SystemExit('Play wants between 2 and 8 phone screenshots')
    if tablet and not 2 <= len(tablet) <= 8:
        raise SystemExit('Play wants between 2 and 8 tablet screenshots')
    if dry:
        return 0

    st, e = play.edit('POST', 'edits')
    if st >= 400:
        raise SystemExit(f'create edit failed: {play.why(e)}')
    eid = e['id']
    print('\nedit', eid)

    st, r = play.edit('PUT', f'edits/{eid}/listings/{LANG}', {
        'language': LANG,
        'title': title,
        'shortDescription': short,
        'fullDescription': full,
    })
    if st >= 400:
        raise SystemExit(f'listing text failed: {play.why(r)}')
    print('text uploaded')

    uploads = [('icon', [icon]), ('featureGraphic', [feature]),
               ('phoneScreenshots', shots)]
    if tablet:
        uploads += [('sevenInchScreenshots', tablet),
                    ('tenInchScreenshots', tablet)]
    for kind, files in uploads:
        st, r = play.edit('DELETE', f'edits/{eid}/listings/{LANG}/{kind}')
        for f in files:
            st, r = play.upload(f'edits/{eid}/listings/{LANG}/{kind}',
                                f.read_bytes(), 'image/png')
            if st >= 400:
                raise SystemExit(f'{kind} / {f.name} failed: {play.why(r)}')
            print(f'  {kind:16} {f.name}')

    st, c = play.edit('POST', f'edits/{eid}:commit')
    if st >= 400:
        raise SystemExit(f'commit failed: {play.why(c)}')
    print('\nCOMMITTED')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Upload App Store screenshots through the App Store Connect API.

`fastlane deliver` silently uploads nothing when it cannot map an image
resolution to a display type, so this does the four-step upload itself:
create set -> reserve screenshot -> PUT bytes -> commit with checksum.

Usage:
    python3 scripts/upload_screenshots.py <localization_id> <display_type> <file>...
"""
import hashlib
import sys
from pathlib import Path
from urllib import request

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc import call  # noqa: E402


def ensure_set(localization_id: str, display_type: str) -> str:
    status, data = call(
        "GET", f"appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
    )
    if status < 400:
        for item in data.get("data", []):
            if item["attributes"]["screenshotDisplayType"] == display_type:
                return item["id"]
    status, data = call(
        "POST",
        "appScreenshotSets",
        body={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": localization_id,
                        }
                    }
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"create set failed ({display_type}): {data}")
    return data["data"]["id"]


def upload(set_id: str, path: Path) -> None:
    blob = path.read_bytes()
    status, data = call(
        "POST",
        "appScreenshots",
        body={
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(blob), "fileName": path.name},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"reserve failed for {path.name}: {data}")

    screenshot_id = data["data"]["id"]
    for op in data["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"] : op["offset"] + op["length"]]
        req = request.Request(op["url"], data=chunk, method=op["method"])
        for header in op["requestHeaders"]:
            req.add_header(header["name"], header["value"])
        with request.urlopen(req, timeout=300) as resp:
            if resp.status >= 400:
                raise SystemExit(f"PUT failed for {path.name}: {resp.status}")

    status, data = call(
        "PATCH",
        f"appScreenshots/{screenshot_id}",
        body={
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"commit failed for {path.name}: {data}")
    print(f"  uploaded {path.name}")


def main() -> int:
    localization_id, display_type, *files = sys.argv[1:]
    set_id = ensure_set(localization_id, display_type)
    print(f"{display_type} -> set {set_id}")
    for f in sorted(files):
        upload(set_id, Path(f))
    return 0


if __name__ == "__main__":
    sys.exit(main())

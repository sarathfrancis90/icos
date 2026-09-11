#!/usr/bin/env python3
"""Upload an App Store app preview video through the App Store Connect API.

Same four-step dance as a screenshot (create set -> reserve -> PUT bytes ->
commit with checksum), plus a poster frame time code.

Usage:
    python3 scripts/upload_preview.py <localization_id> <preview_type> <file> [timecode]
"""
import hashlib
import sys
from pathlib import Path
from urllib import request

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc import call  # noqa: E402


def ensure_set(localization_id: str, preview_type: str) -> str:
    status, data = call(
        "GET", f"appStoreVersionLocalizations/{localization_id}/appPreviewSets"
    )
    if status < 400:
        for item in data.get("data", []):
            if item["attributes"]["previewType"] == preview_type:
                return item["id"]
    status, data = call(
        "POST",
        "appPreviewSets",
        body={
            "data": {
                "type": "appPreviewSets",
                "attributes": {"previewType": preview_type},
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
        raise SystemExit(f"create preview set failed: {data}")
    return data["data"]["id"]


def upload(set_id: str, path: Path, timecode: str) -> str:
    blob = path.read_bytes()
    status, data = call(
        "POST",
        "appPreviews",
        body={
            "data": {
                "type": "appPreviews",
                "attributes": {
                    "fileSize": len(blob),
                    "fileName": path.name,
                    "previewFrameTimeCode": timecode,
                },
                "relationships": {
                    "appPreviewSet": {
                        "data": {"type": "appPreviewSets", "id": set_id}
                    }
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"reserve failed: {data}")

    preview_id = data["data"]["id"]
    for op in data["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"] : op["offset"] + op["length"]]
        req = request.Request(op["url"], data=chunk, method=op["method"])
        for header in op["requestHeaders"]:
            req.add_header(header["name"], header["value"])
        with request.urlopen(req, timeout=600) as resp:
            if resp.status >= 400:
                raise SystemExit(f"PUT failed: {resp.status}")

    status, data = call(
        "PATCH",
        f"appPreviews/{preview_id}",
        body={
            "data": {
                "type": "appPreviews",
                "id": preview_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
    )
    if status >= 400:
        raise SystemExit(f"commit failed: {data}")
    return preview_id


def main() -> int:
    localization_id, preview_type, file = sys.argv[1:4]
    timecode = sys.argv[4] if len(sys.argv) > 4 else "00:00:03:00"
    set_id = ensure_set(localization_id, preview_type)
    print(f"{preview_type} -> set {set_id}")
    print("uploaded preview", upload(set_id, Path(file), timecode))
    return 0


if __name__ == "__main__":
    sys.exit(main())

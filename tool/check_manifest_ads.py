#!/usr/bin/env python3
"""Assert the AdMob APPLICATION_ID in a built artifact matches the ads switch.

Why this exists: the packed manifest is the only ground truth for what the app
ships. Two traps made an earlier shell check lie about it:

  * an APK manifest is binary AXML and its string pool may be UTF-8 *or*
    UTF-16LE, so `strings | grep` silently misses UTF-16 pools and reports
    "clean" for a manifest that still carries the publisher ID;
  * an AAB manifest is protobuf, stored at base/manifest/AndroidManifest.xml
    (not AndroidManifest.xml at the root), so grepping the wrong entry reports
    "clean" too.

The Gradle side blanks the placeholder (manifestPlaceholders["adsAppId"]) when
`-PenableAds=false`; this script verifies the result per artifact, in both
encodings, and exits non-zero when the expectation is violated:

    python3 tool/check_manifest_ads.py <apk|aab> --expect=absent
    python3 tool/check_manifest_ads.py <apk|aab> --expect=present

Usage notes:
  * pass --expect=absent for an ads-disabled build, --expect=present for an
    ads-enabled one. An inverted/misread Gradle property fails BOTH ways, so
    every flavour is covered by whichever expectation matches its flags.
"""

from __future__ import annotations

import argparse
import sys
import zipfile

# The Android AdMob application ID (publisher prefix is shared by every unit
# and app under the account; the full app id is the account-wide constant that
# must only appear when ads are enabled).
PUBLISHER_PREFIX = "ca-app-pub-6917313063209470"
MANIFEST_ENTRIES = {
    ".apk": "AndroidManifest.xml",
    ".aab": "base/manifest/AndroidManifest.xml",
}


def read_manifest(artifact: str) -> tuple[str, bytes]:
    """Return (entry name, raw manifest bytes) for a built APK/AAB."""
    ext = artifact[artifact.rfind(".") :].lower()
    entry = MANIFEST_ENTRIES.get(ext)
    if entry is None:
        raise SystemExit(
            f"unsupported artifact {artifact!r}: expected one of {sorted(MANIFEST_ENTRIES)}"
        )
    try:
        with zipfile.ZipFile(artifact) as archive:
            names = set(archive.namelist())
            if entry not in names:
                raise SystemExit(f"{entry} not found inside {artifact} (not a valid {ext}?)")
            return entry, archive.read(entry)
    except zipfile.BadZipFile as exc:
        raise SystemExit(f"{artifact} is not a readable zip: {exc}") from exc


def encoding_hits(blob: bytes, needle: str) -> list[str]:
    """Return every encoding of `needle` present in `blob` (usually 0 or 1)."""
    hits = []
    for label, encoded in (
        ("utf-8", needle.encode("utf-8")),
        ("utf-16le", needle.encode("utf-16-le")),
        ("utf-16be", needle.encode("utf-16-be")),
    ):
        if encoded in blob:
            hits.append(label)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", help="path to app-release.apk or app-release.aab")
    parser.add_argument(
        "--expect",
        choices=("present", "absent"),
        required=True,
        help="whether the AdMob APPLICATION_ID is expected in the packed manifest",
    )
    args = parser.parse_args()

    entry, blob = read_manifest(args.artifact)
    app_id_hits = encoding_hits(blob, PUBLISHER_PREFIX)
    activity_hits = encoding_hits(blob, "com.google.android.gms.ads.APPLICATION_ID")

    print(f"artifact        : {args.artifact}")
    print(f"manifest entry  : {entry} ({len(blob)} bytes)")
    print(f"APPLICATION_ID meta-data present : {bool(activity_hits)} {activity_hits}")
    print(f"publisher id present             : {bool(app_id_hits)} {app_id_hits}")
    print(f"expected                         : {args.expect}")

    found = bool(app_id_hits)
    if args.expect == "present" and not found:
        print(
            "::error::ads ENABLED but the packed manifest carries no AdMob "
            "APPLICATION_ID — the Gradle `enableAds` property was misread and the "
            "SDK would run without an app id (ads never load)."
        )
        return 1
    if args.expect == "absent" and found:
        print(
            "::error::ads DISABLED but the packed manifest still ships the AdMob "
            "APPLICATION_ID — `-PenableAds=false` was not honoured."
        )
        return 1
    print(f"OK: AdMob APPLICATION_ID is {args.expect} as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())

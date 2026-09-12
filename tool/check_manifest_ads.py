#!/usr/bin/env python3
"""Assert a built artifact declares a VALID AdMob APPLICATION_ID.

Why: an empty `android:value=""` on the `com.google.android.gms.ads.APPLICATION_ID`
meta-data is NOT a way to disable ads — the Google Mobile Ads SDK validates it in
its own ContentProvider, before Dart ever runs, and kills the process:

    java.lang.RuntimeException: Unable to get provider
      com.google.android.gms.ads.MobileAdsInitProvider:
    java.lang.IllegalStateException: * Invalid application ID. *

(captured on a real device, Pixel 3a / Android 12, 2026-09-12). The manifest must
therefore always carry a well-formed id; turning ads off is a Dart-side decision
(`--dart-define=ENABLE_ADS=false` → the SDK is never initialized).

Two earlier checks missed this class of bug:
  * `strings | grep` cannot see an APK manifest's UTF-16 string pool, so it
    reported "clean" for manifests that did ship the id — and could not tell an
    empty `android:value=""` from a value that merely appeared elsewhere;
  * searching for the id string does not prove it is the meta-data's value.

So this parses the real attribute value:
  * .apk → the packed binary AXML manifest (full attribute parse);
  * .aab → the merged release manifest Gradle fed to the bundle task (plain XML,
    located in the build intermediates), falling back to a string-pool probe of
    the bundle's protobuf manifest when the intermediate is unavailable.

Exit status is non-zero when the id is missing, empty or malformed, so CI blocks
the build instead of shipping an app that crashes on launch.
"""

from __future__ import annotations

import glob
import os
import re
import struct
import sys
import zipfile
from xml.etree import ElementTree

ANDROID_NS = "http://schemas.android.com/apk/res/android"
APP_ID_META = "com.google.android.gms.ads.APPLICATION_ID"
APP_ID_RE = re.compile(r"^ca-app-pub-\d{6,20}~\d{6,20}$")

# Publisher prefix shared by the app id and every ad unit of this account.
PUBLISHER_PREFIX = "ca-app-pub-6917313063209470"

RES_STRING_POOL = 0x0001
RES_XML_START_ELEMENT = 0x0102
TYPE_STRING = 0x03


# --------------------------------------------------------------------------
# binary AXML
# --------------------------------------------------------------------------
def _decode_pool(data: bytes, offset: int) -> list[str]:
    (_t, header_size, _chunk, string_count, _style_count, flags,
     strings_start, _styles_start) = struct.unpack_from("<HHIIIIII", data, offset)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f"<{string_count}I", data, offset + header_size)
    base = offset + strings_start
    out: list[str] = []
    for off in offsets:
        pos = base + off
        if utf8:
            n = data[pos]
            pos += 1
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[pos]
                pos += 1
            m = data[pos]
            pos += 1
            if m & 0x80:
                m = ((m & 0x7F) << 8) | data[pos]
                pos += 1
            out.append(data[pos:pos + m].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, pos)[0]
                pos += 2
            out.append(data[pos:pos + n * 2].decode("utf-16-le", "replace"))
    return out


def axml_meta_data(blob: bytes) -> list[tuple[str, str]]:
    """Return [(name, value)] for every <meta-data> in a binary AXML manifest."""
    pos = 8  # XML file header
    pool: list[str] = []
    metas: list[tuple[str, str]] = []
    while pos < len(blob) - 8:
        _type, _header, chunk_size = struct.unpack_from("<HHI", blob, pos)
        if chunk_size <= 0:
            break
        if _type == RES_STRING_POOL:
            pool = _decode_pool(blob, pos)
        elif _type == RES_XML_START_ELEMENT:
            (_ns, name, attr_start, attr_size,
             attr_count) = struct.unpack_from("<IIHHH", blob, pos + 16)
            attrs: dict[str, str] = {}
            # attributeStart is relative to the attr-ext struct at pos+16.
            abase = pos + 16 + attr_start
            for i in range(attr_count):
                a = abase + i * attr_size
                _a_ns, a_name, a_raw = struct.unpack_from("<III", blob, a)
                a_type, a_data = struct.unpack_from("<BB", blob, a + 15)
                key = pool[a_name] if a_name < len(pool) else f"@{a_name}"
                if a_type == TYPE_STRING:
                    val = pool[a_data] if a_data < len(pool) else f"@{a_data}"
                elif a_raw != 0xFFFFFFFF:
                    val = pool[a_raw] if a_raw < len(pool) else f"@{a_raw}"
                else:
                    val = ""  # non-string typed value (bool/int) — not an id
                    if a_type == 0x10:
                        val = str(a_data)
                attrs[key] = val
            if (pool[name] if name < len(pool) else "") == "meta-data":
                metas.append((attrs.get("name", ""), attrs.get("value", "")))
        pos += chunk_size
    return metas


# --------------------------------------------------------------------------
# merged (text) manifest — the source the bundle task consumes
# --------------------------------------------------------------------------
def merged_manifest_meta_data(repo_root: str) -> list[tuple[str, str]] | None:
    """Read the merged release manifest from the Gradle intermediates, if any.

    Flutter redirects Gradle's build dir to <repo>/build/app, but the android/
    tree is searched too so the lookup survives that changing.
    """
    patterns = [
        os.path.join(repo_root, "build", "app", "intermediates", "**", "AndroidManifest.xml"),
        os.path.join(repo_root, "android", "app", "build", "intermediates", "**", "AndroidManifest.xml"),
    ]
    candidates: list[str] = []
    for pattern in patterns:
        candidates += [
            p for p in glob.glob(pattern, recursive=True)
            if "merged_manifest" in p.replace(os.sep, "/") and "release" in p.replace(os.sep, "/")
        ]
    if not candidates:
        return None
    path = max(candidates, key=os.path.getmtime)
    print(f"merged release manifest : {path}")
    root = ElementTree.parse(path).getroot()
    metas: list[tuple[str, str]] = []
    for meta in root.iter("meta-data"):
        metas.append((
            meta.get(f"{{{ANDROID_NS}}}name", ""),
            meta.get(f"{{{ANDROID_NS}}}value", ""),
        ))
    return metas


# --------------------------------------------------------------------------
def read_artifact(path: str):
    """Return (kind, payload) for a built APK/AAB."""
    if path.endswith(".aab"):
        with zipfile.ZipFile(path) as z:
            return "aab", z.read("base/manifest/AndroidManifest.xml")
    if path.endswith(".apk"):
        with zipfile.ZipFile(path) as z:
            return "apk", z.read("AndroidManifest.xml")
    raise SystemExit(f"unsupported artifact {path!r}: expected .apk or .aab")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__ + f"\nusage: {sys.argv[0]} <app-release.apk|app-release.aab>")
    artifact = sys.argv[1]
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    kind, packed = read_artifact(artifact)
    print(f"artifact                : {artifact} ({len(packed)} byte packed manifest, {kind})")

    metas: list[tuple[str, str]] = []
    source = ""
    if kind == "apk":
        metas = axml_meta_data(packed)
        source = "packed AXML"
    else:
        merged = merged_manifest_meta_data(repo_root)
        if merged is not None:
            metas = merged
            source = "merged text manifest"
        else:
            # Fallback: the bundle stores a protobuf manifest, which this tool
            # does not decode — probe the string pool for regression signals.
            print("merged release manifest : NOT FOUND — falling back to a "
                  "string-pool probe (weaker: cannot detect an empty value)")
            has_meta = b"com.google.android.gms.ads.APPLICATION_ID" in packed or \
                "com.google.android.gms.ads.APPLICATION_ID".encode("utf-16-le") in packed
            has_id = PUBLISHER_PREFIX.encode() in packed or \
                PUBLISHER_PREFIX.encode("utf-16-le") in packed
            print(f"APPLICATION_ID meta-data present : {has_meta}")
            print(f"publisher id present             : {has_id}")
            if not (has_meta and has_id):
                print("::error::bundle manifest is missing the AdMob APPLICATION_ID "
                      "— the Google Mobile Ads SDK crashes at launch without it")
                return 1
            print("OK: AdMob APPLICATION_ID present in the bundle manifest")
            return 0

    print(f"manifest source         : {source}")
    values = [v for n, v in metas if n == APP_ID_META]
    print(f"APPLICATION_ID entries  : {values if values else '<none>'}")

    if not values:
        print("::error::no com.google.android.gms.ads.APPLICATION_ID meta-data — the "
              "Google Mobile Ads SDK kills the process at launch without it")
        return 1
    value = values[0]
    if not value:
        print('::error::APPLICATION_ID is EMPTY (android:value="") — that is not '
              '"ads disabled", it crashes the app on every launch inside '
              'MobileAdsInitProvider ("Invalid application ID")')
        return 1
    if not APP_ID_RE.match(value):
        print(f"::error::APPLICATION_ID {value!r} is not a well-formed AdMob app id "
              "(expected ca-app-pub-<digits>~<digits>)")
        return 1
    if not value.startswith(PUBLISHER_PREFIX):
        print(f"::warning::APPLICATION_ID belongs to a different publisher than the "
              f"ad units in lib/config/ads_config.dart ({PUBLISHER_PREFIX}…)")
    print(f"OK: valid AdMob APPLICATION_ID ({value})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

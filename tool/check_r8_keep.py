#!/usr/bin/env python3
"""Assert R8 kept the no-arg constructor Room needs to instantiate its databases.

Why: `flutter build apk --release` enables R8 minification (the Flutter Gradle
plugin sets `releaseBuildType.isMinifyEnabled = true`) while debug builds are
not minified, so this failure mode is invisible during development. Room does
not call its generated implementation directly — it builds the NAME and loads it
reflectively:

    Class.forName("androidx.work.impl.WorkDatabase_Impl").newInstance()

Room's consumer rule keeps the class and its name (so `Class.forName` succeeds)
but not the no-arg constructor; R8 sees no static caller for `<init>()`, removes
it, and `newInstance()` then throws InstantiationException. Room wraps that as:

    java.lang.RuntimeException: Failed to create an instance of
      androidx.work.impl.WorkDatabase

which the ads SDK's transitive WorkManager hits from `androidx.startup` in a
ContentProvider — i.e. BEFORE Application.onCreate(), so the process dies on
every cold start with no Dart-side chance to handle it. Reproduced on a real
device (Pixel 3a / Android 12, release APK, 2026-09-12).

The fix lives in `android/app/proguard-rules.pro`:
    -keep class * extends androidx.room.RoomDatabase { <init>(); }

This script asserts the fix is still in effect by reading R8's own removed-code
report (`usage.txt`), which AGP writes for minified builds. A constructor listed
as *removed* means the app cannot launch — fail the build.

Exit status is non-zero when the constructor was removed, or when no usage
report can be found (an absent report means this guard is not actually running,
which is worse than a red build).
"""

from __future__ import annotations

import glob
import os
import sys

# Room-generated classes whose no-arg constructor must survive R8. `WorkDatabase_Impl`
# is the one we actually hit; the tail of matching `_Impl` Room databases is
# reported for context so a future dependency (another DB) is visible in the log.
ROOM_DB_IMPLS = ("WorkDatabase_Impl",)

# AGP writes R8's reports here. Flutter redirects the app module's build dir to
# <repo>/build/app, so this is the release variant's mapping folder.
DEFAULT_GLOBS = (
    "build/app/outputs/mapping/release/usage.txt",
    "build/app/outputs/mapping/*/usage.txt",
    "android/app/build/outputs/mapping/*/usage.txt",
)


def find_usage_file() -> str | None:
    for pattern in DEFAULT_GLOBS:
        hits = sorted(glob.glob(pattern))
        if hits:
            return hits[0]
    return None


def parse_removed(path: str) -> dict[str, list[str]]:
    """usage.txt lists removed classes as `pkg.Class:` with indented members.

    Class headers may appear with either `.` or `/` separators depending on the
    AGP/R8 version, so both are normalised to dots.
    """
    removed: dict[str, list[str]] = {}
    current: str | None = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if not line[0].isspace():
                if line.endswith(":"):
                    current = line[:-1].strip().replace("/", ".")
                    removed.setdefault(current, [])
                else:
                    current = None
                continue
            if current is not None:
                removed[current].append(line.strip())
    return removed


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else find_usage_file()
    if not path or not os.path.exists(path):
        print("FAIL: no R8 usage.txt found — cannot prove Room's constructor was kept.")
        print("      Searched: " + ", ".join(DEFAULT_GLOBS))
        print("      Expected it to exist after a minified (release) build.")
        return 1

    print(f"R8 removed-code report: {path}")
    removed = parse_removed(path)
    print(f"  classes with removed members: {len(removed)}")

    failures = 0
    for impl in ROOM_DB_IMPLS:
        matches = [name for name in removed if name.endswith(impl)]
        if not matches:
            # Not listed at all → nothing was removed from it (the desired
            # outcome), or R8 dropped the whole class (which would fail later at
            # Class.forName and is caught by the crash itself, not here).
            print(f"OK: {impl} has no removed members — no-arg constructor survived")
            continue
        for name in matches:
            members = removed[name]
            ctors = [m for m in members if "<init>()" in m]
            if ctors:
                print(f"FAIL: R8 removed the no-arg constructor of {name}:")
                for member in ctors:
                    print(f"        {member}")
                print("      Room cannot instantiate this database reflectively →")
                print("      'Failed to create an instance of ...' on every cold start.")
                print("      Check android/app/proguard-rules.pro is wired into")
                print("      android/app/build.gradle.kts (proguardFiles).")
                failures += 1
            else:
                print(
                    f"OK: {name} kept its no-arg constructor "
                    f"({len(members)} other member(s) removed)"
                )

    if failures:
        return 1
    print("OK: Room database implementations are reflectively instantiable in this build")
    return 0


if __name__ == "__main__":
    sys.exit(main())

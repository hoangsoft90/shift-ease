# result_p0_db_path_mobile.md — P0 Fix: Mobile database path

> Date: 2026-09-11 · Sources: `issue1.md` (bug report) + `prompt_fix1.md` (fix directive).
> Severity: **P0** — app never got past the locked screen on a real phone.

## Root cause (confirmed in code before the fix)

`defaultDbPath()` in `lib/main.dart` resolved the DB as
`$HOME/.shiftease/shiftease.db` with a **`'.'` fallback** when `HOME` is unset.
Android apps have no `HOME` and a read-only working directory → the app tried
to create `./.shiftease` on the CWD → `errno = 30 (Read-only file system)` →
recovery screen whose copy blamed the key/reinstall — misleading.

## Fix (what changed)

### 1. Path resolution — `lib/core/db/db_path.dart` (new)

ONE convention, documented in-file:

| Priority | Branch | Path |
|---|---|---|
| 1 | `SHIFTEASE_DB` env set | exactly that path (desktop/CLI + env tests) |
| 2 | Android / iOS | `getApplicationSupportDirectory()/shiftease.db` via path_provider (app-private, writable, no permissions; same root as backup/ICS exports); directory created if missing |
| 3 | Desktop | `$HOME/.shiftease/shiftease.db`; **HOME unset → StateError** (loud failure), NEVER a `'.'` CWD fallback |

`resolveDbPath()` takes an injectable `PlatformProbe` (isAndroid/isIOS/env/
homeDir/applicationSupportDirectory) so every branch is unit-testable without
platform channels. `DefaultPlatformProbe` wraps `dart:io` + path_provider.

### 2. `lib/main.dart` — async open + classified recovery UI

- `_openProductionDatabase` now `await`s `resolveDbPath()` before
  `openDatabase(opener: defaultOpener, path: dbPath, key: key)`.
  Key-first order unchanged; **fail-closed SQLCipher unchanged** (no plain
  fallback, no unkeyed open).
- `_LockedApp` copy now driven by `_FailureClass`:

| Class | Trigger | Copy gist |
|---|---|---|
| filesystem | `FileSystemException` / `StateError` (path guard) | "storage problem — NOT a lost key; your data is not gone"; restart/free-space guidance; reinstall framed as fresh-DB + restore, never as a fix by itself |
| secretStore | `SecretStoreException` | locked-not-lost; restart device / lock-screen set / reinstall → key gone by design → restore backup |
| cipher | `SqlCipherUnavailableError` | wrong key / not a ShiftEase store; locked-not-lost; restore path |
| unexpected | anything else | short technical detail + support channel |

- Technical detail line preserved for all classes (diagnosability).
- Content wrapped in `SingleChildScrollView` (small-screen overflow guard).

### 3. Tests — `test/core/db/db_path_test.dart` (new, 7 tests)

- Android + iOS branches: exact path, directory created.
- **P0 invariant test:** mobile path is absolute, never `./`-prefixed, never
  contains `/./` (the errno-30 shape).
- `SHIFTEASE_DB` override wins even on mobile; empty override = unset.
- Desktop HOME branch: exact path + directory created.
- Desktop HOME unset → `StateError` (never a CWD fallback).

### 4. Docs

- `lib/main.dart` header comment no longer claims "real app = $HOME/.shiftease".
- `.project/state.md` synced. (`build_notes`/`release_freeze` never mentioned
  the DB path — verified by grep, nothing else to correct.)

## Evidence (run in this session)

- `flutter analyze --no-pub --fatal-infos` → **No issues found!**
- `flutter test test/` → **322/322 All tests passed!** (315 + 7 new path tests)
- No golden/expected values edited to get green.

## Acceptance (prompt_fix1.md)

- [x] Path helper + async open (mobile = application support; override wins)
- [x] Recovery messages classify filesystem vs key vs cipher
- [x] analyze clean + full suite 100% pass (322/322)
- [x] `result_p0_db_path_mobile.md` written (this file)
- [ ] **Device leg (human):** install the new CI debug APK → app opens into
      Jobs/Today, no locked screen from `./.shiftease`/errno 30. Sandbox
      cannot run this row — it needs the artifact on a real phone.

## NEVER checklist (verified against the diff)

- [x] No `Platform.environment['HOME'] ?? '.'` anywhere in path resolution
- [x] No DB writes to CWD / external public storage
- [x] No unkeyed open, no plain-SQLite fallback on path failure
- [x] No "uninstall/reinstall" as the fix for errno 30 (copy says otherwise)
- [x] No scope creep (no OCR/features/refactors)

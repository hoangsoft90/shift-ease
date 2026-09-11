# AI Rules — ShiftEase Project

> Auto-generated rules capturing project conventions.
> Update this file whenever project structure or conventions change.

## Project Info

- **Project**: ShiftEase
- **Type**: Flutter (Dart) application
- **Path**: `/home/dinhxhoang08/htdocs_apps/ShiftEase`
- **Language**: Dart (Flutter 3.47.1 stable, Dart 3.13.1)
- **Description**: Personal Operating System for Shift Workers — Work/Life/Money pillars

## Code Location

- **Main code**: `lib/`
- **Core engines**: `lib/core/{time,pattern,money,import,db}/`
- **Domain layer**: `lib/domain/`
- **Features/UI**: `lib/features/{jobs,templates,pattern_builder,calendar,occurrence,today,import,common,pay,income,export,notifications}/`
- **App shell**: `lib/app/`
- **Tests**: `test/core/`, `test/domain/`, `test/ui/`

## Plan Files

- Plans: `.plan/plan1_final_v2.md` → `.plan/plan8_m3_income.md` (plan8 = Release Candidate batch, **HOÀN TẤT A–J 2026-09-08**)
- Documents: `.plan/features.md`, `.plan/plan_gate_c.md`, `doc/mobile_readiness.md`

## Result Files

- `result1.txt` through `result18_code_review_rc.txt` (16 = RC batch A–J; 17 = RC review; 18 = code review + polish addendum; `result16_rc_progress.txt` = snapshot giữa batch)
- Handoff mới nhất: `handoff_20260910_rc_complete.md` · `checklist.md`, `next.md`
- Trạng thái: `.project/state.md` + `.project/working.md` + `.project/openspec_entry.md`

## Coding Conventions

- Flutter widget tests use `flutter test`
- Core tests use `dart test test/core/`
- Domain tests: `test/domain/schedule_service_test.dart`
- UI tests: `test/ui/{m1,m1b,m2_import,dst_resolution,pay_income,pay_preset,income_breakdown,income_impact,write_error_boundary,rc_csv_diff,settings}_flow_test.dart`
- Use MaterialApp wrapper in widget tests
- Use real SQLite in-memory DB for tests
- Analyzer: `flutter analyze` — no warnings, no errors
- Golden test verification scripts: `scripts/verify_*_cases.mjs`

## Test Commands

```bash
# Core + domain + UI + features all pass
flutter test test/core/              # 213 tests
flutter test test/domain/            # 18 tests
flutter test test/ui/                # 33 tests
flutter test test/features/          # 12 tests
flutter analyze                       # clean
```

## Roadmap Status

**Completed gates:**
- Gate 0: core/time (32 tests) + core/pattern (53 tests)
- Gate 1: core/money (24 tests)
- Gate 2: core/import engine (15 tests)
- Gate 3: core/db v2+v3 (14 tests) + integration 19 tests
- Gate M1: Flutter app + domain service + Jobs/Templates/PatternBuilder/Calendar/Occurrence (5 domain+UI tests)
- Gate M1b: Today/Month/Quick Add/re-version UI (4 widget tests)
- Gate M2: Import UI — Smart Paste → Review → Commit → calendar seam (5 widget tests)
- Gate A/B: production composition · atomic commit+rollback · window semantics · SWAP effectiveJobId · partial-commit dialog · version immutability (179)
- Gate C: integrity A1–A5 + product B1–B5 (DST dialog · income estimate + PayRule editor · ICS export · reminder baseline · platform folders) (207)
- RC plan8 (2026-09-08): A Integrity A1–A8 · B Income B1–B7 · C CSV UI + diff card · D DST real resolution · E notifications (E3 device BLOCKED) · F backup/restore · G security gate (device BLOCKED) · H settings · I mobile readiness doc (verify BLOCKED) · J adversarial +13
- RC review 2026-09-10: result17 (plan-conformance PASS) + result18 code review — L1/L2/L3 fixed (+4 test); H1/M1/M2/L4 tracked trong `doc/mobile_readiness.md` mục Code-review backlog (H1 = blocker trước store release)

**Total: 292 tests pass** (core 228 + domain 18 + UI 36 + features 10) — verify 2026-09-10 sau polish pass.

**Next steps:**
- Human review release-candidate (toàn bộ RC A–J)
- Device/CI verification: E3 permission · G SQLCipher native · I 15-row matrix (`doc/mobile_readiness.md`)
- Sau review: deferred §14 (OCR/M4.5 spike · Cloud · Sharing) hoặc closed testing

## Key Decisions (locked)

1. **Platform**: Flutter app (root → Flutter)
2. **No UI dependencies** — only Flutter SDK, no riverpod/bloc
3. **Architecture**: 5-layer (platform/features/domain/data/core), `core/` UI-free
4. **Import = primary source** for days it covers (D-M2-1 A)
5. **Review mandatory** before commit (INVARIANT-004)
6. **Correctness Contract**: deterministic results, no silent guesses
7. **Time**: UTC for all calculations, local civil time for display
8. **Pattern never mutates** (INVARIANT-001)
9. **Pay**: Method B (separate regular + OT), LIFO weekly allocation, max() for multi-rule OT
10. **Offline-first**: SQLite local DB, no cloud/account in core
11. **Platform folders** `android/` + `ios/` đã tạo (Gate C B5) kèm `path_provider` + `flutter_local_notifications`; **KHÔNG build apk ở local** (sandbox không toolchain) — verify device/CI ngoài sandbox
12. **Backup/Restore** (RC F): restore = validate → transaction (children-first drop + re-insert + user_version bump) → rollback khi fail → verify row counts
13. **Security honesty** (RC G): `verifyEncryption` probe báo THẬT trạng thái encryption — plain build phải báo "NOT encrypted", không bao giờ fake "secure"
14. **Commit UI gate** (RC review L1): nút Commit chỉ enable ở state REVIEWING — engine từ chối EXTRACTED→COMMIT nên UI không được mời user bấm vào lỗi chắc chắn
15. **Review-findings discipline**: finding của code review phải vào backlog docs (`doc/mobile_readiness.md` mục Code-review backlog + next.md) nếu không fix ngay — không để mất trong result*.txt

## Invariants

- INVARIANT-001: Pattern never mutates because an occurrence is edited
- INVARIANT-002: Duration always from resolved UTC instants
- INVARIANT-003: Local civil time is basis for recurrence
- INVARIANT-004: Imported data never commits without user confirm
- INVARIANT-005: ShiftTemplate only time/UI — no pay semantics
- INVARIANT-006: Historical pay estimates are immutable snapshots
- INVARIANT-007: Occurrence keeps original timezone
- INVARIANT-008: Core calendar works completely offline

## Working Memory

See `.project/working.md` for current task status, pending decisions, and session tracking.

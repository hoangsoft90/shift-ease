# PROMPT — ShiftEase: Full Phase Design ↔ Code Audit

## Vai trò

Bạn là reviewer độc lập. Nhiệm vụ: **đối chiếu code thực tế** trong repo với **thiết kế từng phase**, tìm lệch thiết kế, claim sai, lỗ hổng integrity, và báo cáo có bằng chứng.

**Không** implement feature mới. **Không** “sửa cho xanh” bằng cách nới invariant. Chỉ audit + đề xuất fix có ưu tiên.

## Root project

`/Users/hoang/htdocs_apps/ShiftEase` (Flutter root: `lib/`, `test/`, `pubspec.yaml` — **không** còn tree `source/`).

## Nguồn thiết kế (đọc trước, theo thứ tự)

1. `phases/PRODUCTION_REVIEW.md`
2. `phases/P7_production_verification.md`
3. `phases/P8_release_preparation.md`
4. `phases/P9_production_launch.md`
5. `production_roadmap.md`
6. `.plan/plan_gate_c.md`, `.plan/plan_p8.md`, `.plan/plan_p9.md` (và plan liên quan nếu cần: plan3_final, plan5, plan7, plan8_m3_income…)
7. `doc/release_freeze.md`, `doc/release/*`, `doc/mobile_readiness.md`
8. Evidence: `checklist.md`, `next.md`, `result*.txt`, `result_p7*.md`, `result_p8*.md`, `result_p9*.md`, `handoff*`

## Nguồn code (bắt buộc mở, không đoán)

- `lib/core/time/`, `lib/core/pattern/`, `lib/core/money/`, `lib/core/import/`, `lib/core/db/`
- `lib/domain/schedule_service.dart`
- `lib/features/**`
- `lib/main.dart`
- `test/**` (đặc biệt adversarial, golden, db, import, security)
- `.github/workflows/*`
- `pubspec.yaml`, `android/`, `ios/`, `tool/cipher_proof.dart`

## Nguyên tắc audit

1. **Filesystem là sự thật** — nếu result/checklist claim PASS mà file/code không khớp → ghi **DOC LIE / STALE CLAIM**.
2. Mỗi finding phải có: **file + vị trí/symbol + kỳ vọng thiết kế + hành vi thực + impact + severity (P0–P3)**.
3. Phân biệt:
   - **CODE MATCH** — đúng design
   - **CODE DRIFT** — lệch design
   - **UNVERIFIED** — cần device/CI, không PASS giả
   - **WAIVED** — user bỏ qua, ghi rõ không phải PASS
4. Ưu tiên: mất dữ liệu, corruption, encryption giả, silent fail, transaction không atomic, bypass review/import, tính duration/income sai, notification stale/duplicate.
5. Không đánh phase DONE chỉ vì có document.

---

## Map phase → kiểm tra bắt buộc

### P0 — Foundation / Core engines

- [ ] Time: civil vs UTC vs duration; DST nonexistent/ambiguous không auto-pick sai; INVARIANT duration từ UTC
- [ ] Pattern: versioning, override append-only, không mutate pattern khi sửa occurrence
- [ ] Money: không double-count; thiếu rule → UNAVAILABLE rõ ràng
- [ ] Golden tests tồn tại và vẫn được chạy trong CI/local path đúng

### P1 — Calendar / Pattern / Override UI+domain

- [ ] `ScheduleService` là seam duy nhất UI → persistence
- [ ] CREATE/UPDATE/DELETE/REPLACE/SPLIT/SWAP semantics khớp design (đặc biệt UTC preserve / re-resolve)
- [ ] Render = baseline + overrides; không silent drop issue

### P2 — Today / Month / Quick Add / Re-version

- [ ] Re-version (`changeRosterFrom`) **atomic** (một transaction)
- [ ] Today/Month không phá timezone occurrence (INVARIANT device tz)

### P3 — Smart Import / Review / Commit

- [ ] **Chỉ `REVIEWING → COMMIT`** — EXTRACTED không commit được
- [ ] Commit atomic; session COMMITTED immutable
- [ ] Không auto-commit (INVARIANT-004)

### P4 — CSV / Re-import / Diff

- [ ] Mapping + validation; conflict OFF+SHIFT / duplicate xử lý đúng
- [ ] Diff + income impact: row không resolve → **UNAVAILABLE**, không partial optimistic

### P5 — Income / Pay / Multi-job

- [ ] Template không chứa pay (INVARIANT-005)
- [ ] Breakdown + nhãn “Ước tính — không phải bảng lương chính thức”
- [ ] Multi-job total chỉ cộng AVAILABLE

### P6 — RC Integrity / Reliability

- [ ] Write error boundary (không crash nuốt lỗi)
- [ ] Override same-id: identical idempotent; different → throw
- [ ] Backup/restore transactional; corrupt reject; production backup **không** `systemTemp`
- [ ] Security seam: SQLCipher fail-closed; SecureSecretStore production; InMemory chỉ test
- [ ] Reminder cancel/resync; không claim device PASS

### P7 — Production verification

- [ ] H1/M1 đã đóng trong code
- [ ] `pubspec` sqlcipher + `defaultOpener` refuse plain keyed path
- [ ] Device gates: ghi UNVERIFIED/BLOCKED đúng, không PASS
- [ ] `tool/cipher_proof.dart` tồn tại và được CI gọi

### P8 — Release prep

- [ ] **CI**: `.github/workflows/test.yml` = Flutter **root** (`flutter test`), **không** `source/` + `dart test`
- [ ] `build-debug-apk.yml` nếu được claim thì phải tồn tại
- [ ] Freeze doc, smoke/upgrade checklists, store/privacy **không quảng cáo OCR/Cloud/AI**
- [ ] Nhóm B signed/smoke/closed = BLOCKED trừ có evidence

### P9 — Launch ops

- [ ] Đủ: final_release_gate, submission_record, staged_launch, monitoring(+triage), hotfix, data_loss, first_production_review, post_production_backlog, `result_p9_launch.md`
- [ ] Status chỉ **LAUNCH PREP COMPLETE** nếu chưa submit live
- [ ] NEVER first-response xóa DB; NEVER hotfix kèm feature trong docs

---

## Cách làm (bắt buộc)

1. Liệt kê phase P0–P9 + trạng thái claim trong checklist/result.
2. Với mỗi phase: mở **code** liên quan, so với design bullets trên.
3. Chạy (nếu môi trường cho phép):
   ```bash
   flutter analyze --no-pub
   flutter test test/
   dart run tool/cipher_proof.dart
   ```
   Ghi output thật; không bịa số test.
4. Grep tối thiểu:
   - `EXTRACTED` / `commitImport` / `systemTemp` / `PRAGMA key` / `InMemorySecretStore` / `working-directory: source` / `ON CONFLICT`
5. Tổng hợp finding theo severity.

---

## Output bắt buộc

Tạo file: **`result_phase_design_audit.md`** với cấu trúc:

```markdown
# Phase Design ↔ Code Audit — ShiftEase

## 1. Executive summary
- Overall: MATCH | MOSTLY MATCH | DRIFT | UNSAFE
- Top 5 risks
- Có được coi production-ready không (honest)

## 2. Phase matrix
| Phase | Design intent | Code status | Docs claim | Verdict | Evidence (paths) |

## 3. Findings (P0 → P3)
### F-001 …
- Phase:
- Severity:
- Expected (design):
- Actual (code):
- Path:
- Impact:
- Recommended fix:

## 4. Doc / claim mismatches
(checklist, result_*, handoff vs disk)

## 5. CI & security snapshot
- workflows:
- cipher:
- backup path:
- import commit gate:

## 6. Test snapshot
- analyze:
- test count / fail:
- cipher_proof:

## 7. Recommended next actions (ordered)
1. …
```

Cập nhật ngắn vào `checklist.md` / `next.md` **chỉ** mục audit (không đổi status phase thành PASS nếu audit fail).

---

## NEVER

- NEVER tin result/handoff khi chưa mở source
- NEVER PASS device/encryption/CI remote không evidence
- NEVER implement OCR/Cloud/feature trong task này
- NEVER sửa test expectation để che drift
- NEVER đánh P9 PRODUCTION LIVE nếu chưa submit

## Xong khi

- `result_phase_design_audit.md` tồn tại, mỗi phase có verdict + evidence path
- Mọi P0/P1 finding có recommended fix cụ thể
- Phân biệt rõ CODE vs UNVERIFIED vs DOC LIE

Bắt đầu bằng đọc `phases/*` + `checklist.md`, rồi grep/import/time/db/CI như trên.

# result_payrule_version_ux.md — PayRule Save: versioning UX

> Date: 2026-09-11 · Source: `.plan/plan_payrule_version_ux.md` (D1–D5, §7 tests, §8 AC).
> Gate A §A6 persistence invariant: **giữ nguyên, không nới**.

## 1. Thuật toán đã chọn (theo plan §10, từng bước)

1. **Đọc `savePayRule` (repo) trước khi code** — kết quả audit đúng như plan §5 dự đoán:
   - same id + **identical** payload → idempotent no-op (OK).
   - same id + **different** payload → `StateError` (refuse overwrite).
   - **KHÔNG có case close-only** (chỉ đổi `effectiveUntil` cũng bị coi là "different payload") → theo ghi chú plan, đã implement **API close có kiểm soát**: `PayRuleRepository.closePayRuleVersion(ruleId, effectiveUntil)` — allowlist **null→date đúng một lần**, throw nếu đã có `effectiveUntil`. Không đường nào đổi rate trên cùng id.
   - Thêm cờ `ownsTransaction` cho `savePayRule` + `closePayRuleVersion` (precedent: `PatternRepository.savePatternInsideTransaction`) để domain gom close+insert thành **1 transaction**.
2. **Domain `ScheduleService.savePayRuleFromEditor(rule, existingId)`** (plan D2, **Option B**):
   - `existingId == null` → insert draft (`created`).
   - `existingId` không tìm thấy (stale) → insert draft (`created`) — vẫn không bao giờ same-id overwrite.
   - Draft **canonical-equal** existing (`_payRulesCanonical`: base + diffs sort + OT sort + effectiveFrom; **exclude** id/effectiveUntil để close-metadata không làm save lành-looking-changed) → `noOp`, không ghi.
   - Changed → validate **Option B**: `effectiveFrom >= max(today, existing.effectiveFrom)`, lỗi ném `ArgumentError('Choose a From date on or after {floor} to apply new rates.')`.
   - Mint **id mới** = `slugId('payrule', [jobId, newFrom, existingId])` (thêm existingId vào parts để 2 version cùng ngày không trùng id — edge: đổi rate 2 lần trong cùng ngày).
   - `BEGIN` → close old (`effectiveUntil` = newFrom − 1 ngày, inclusive semantics khớp `activeRuleFor`: `effectiveUntil >= date`) → insert new → `COMMIT`; bất kỳ lỗi → `ROLLBACK` cả hai. Returns `versioned`.
3. **UI `PayRuleEditDialog`** (plan D4/D5): lưu `_existingRuleId` in-memory khi mở editor; Save gọi domain API; success → pop + SnackBar **"Pay rule saved. Applies from {date}."** (noOp = im lặng); `ArgumentError` → **1 dòng** user-facing dưới form; Exception khác → "Could not save the pay rule. Try again." (chi tiết chỉ cho Sentry). **Đã xóa** toàn bộ copy "Gate A §A6"/"persistence" khỏi UI.

## 2. Files

| File | Thay đổi |
|---|---|
| `lib/core/db/business_repository.dart` | `savePayRule(ownsTransaction)`; NEW `closePayRuleVersion` (null→date 1 lần, ownsTransaction) |
| `lib/domain/schedule_service.dart` | NEW `savePayRuleFromEditor` + `_payRulesCanonical` |
| `lib/features/pay/pay_rule_edit_dialog.dart` | Save qua domain API; copy D4; messenger captured trước pop |
| `test/domain/payrule_versioning_test.dart` | NEW 6 tests |
| `test/ui/payrule_version_ux_test.dart` | NEW 2 widget tests |

## 3. Tests (plan §7 mapping)

| Plan case | Test | Kết quả |
|---|---|---|
| 1 Idempotent | existing + same draft → `noOp`, 1 row, old còn open | ✅ |
| 2 Version on change | đổi rate + From hợp lệ → 2 versions, id khác, old có `effectiveUntil` = ngày trước, active-rule lookup theo ngày đúng (25→30) | ✅ |
| 3 UI không surface A6 | pump dialog, đổi rate, save → không text "Gate A"/"DIFFERENT payload"/"persistence"; dialog đóng; SnackBar "Applies from"; 2 versions (old rate 25 nguyên vẹn) | ✅ |
| 4 First create | no existing → 1 row (`created`) | ✅ |
| 5 Invalid From (Option B) | From trước existing.from → `ArgumentError` chứa "on or after", **không partial write** | ✅ |
| 6 Transaction | insert-new fail sau close → rollback cả hai (old vẫn open, không orphan) | ✅ |
| 7 Regression | full suite | ✅ 340/340 |
| (extra) A6 trực tiếp | gọi repo same-id different payload → vẫn `StateError` | ✅ |
| (extra UI) validation copy | From quá sớm trên form → "Choose a From date on or after", dialog mở, 0 write | ✅ |

## 4. Bugs tự bắt trong session (minh bạch)

1. Guard `ownsTransaction` đầu tiên chỉ bọc `ROLLBACK` mà quên `COMMIT` của `savePayRule` → `savePayRuleFromEditor` test B lộ `cannot rollback - no transaction is active`. Sửa bọc cả hai nhánh; cả domain 6/6 + UI 2/2 xanh sau fix.
2. UI dialog dùng `ScaffoldMessenger.of(context)` **sau** `pop` → context die; capture messenger trước pop.

## 5. Evidence (session này)

- `flutter analyze --no-pub --fatal-infos` → **No issues found!**
- `flutter test test/` → **340/340 All tests passed!** (332 + 6 domain + 2 UI)

## 5b. Code-review pass (2026-09-11, sau commit `1769d29`) — 1 M1 đã sửa

- **M1 (crash path, đã fix):** first-create với From trùng id deterministic `slugId(job, from)` của một row LEGACY đã bị đóng (không active hôm nay → editor không thấy) → repo ném StateError (A6) — là `Error` không phải `Exception`, thoát mọi handler UI → **crash**. Fix: `_createDraftSafely` trong domain translate StateError → ArgumentError với copy user-facing; dialog thêm catch `StateError` belt-and-braces. Regression test mới: legacy closed row cùng id → ArgumentError, không write nào.
- **341/341 tests** (340 + 1 M1 regression) · analyze sạch sau fix.

## 6. Acceptance (plan §8)

- [x] User đổi rate bấm Save **không** thấy lỗi A6 technical (widget test chứng minh)
- [x] Version mới id mới; bản cũ không bị đổi rate
- [x] Save không đổi → success im lặng, không spam version
- [x] Repo trực tiếp vẫn reject same-id different payload (unit test)
- [x] Copy user-facing sạch (không "Gate A"/"Instance of"/"persistence")
- [x] analyze + full test PASS
- [x] Report này (thuật toán close, Option B, test list)

# plan_payrule_version_ux.md — PayRule Save: versioning UX (không bối rối user)

## 0. Mục tiêu

Giữ **Gate A §A6** (PayRule immutability tại persistence):  
**không** silent overwrite cùng `id` với payload khác.

Đồng thời sửa **luồng UI/domain** để user thao tác tự nhiên:

- Sửa rate / diff / OT rồi bấm **Save** → app **tự tạo version mới** (id mới), không ném lỗi kỹ thuật.
- Save lại **không đổi gì** → idempotent, thành công im lặng.
- Copy lỗi (nếu còn) bằng tiếng người dùng, không `Instance of 'PayRule'`, không “Gate A §A6”.

**Không** nới invariant persistence. **Không** OCR/feature ngoài scope.

---

## 1. Hiện trạng / vấn đề

**Persistence (đúng):**  
`savePayRule` — same id + different payload → throw (refuse overwrite).

**UI (sai UX):**  
Màn Pay rule editor thường **giữ nguyên id** rule đang xem, user sửa field → Save → đập vào A6 → message đỏ technical + “Pick a later From date”.

User hiểu nhầm app hỏng; thực ra thiếu **use-case “tạo version mới”** ở domain/UI.

---

## 2. Hành vi mong muốn (product)

| Tình huống user | Kết quả mong muốn |
|-----------------|-------------------|
| A. Mở rule đang có, **không đổi** field, Save | Thành công, không tạo row thừa (idempotent) |
| B. Đổi rate/diff/OT/…, **cùng hoặc đổi** ngày From, Save | **Version mới**: id mới; version cũ được **đóng** (`effectiveUntil` = ngày trước `effectiveFrom` của bản mới) nếu chồng lấn; không throw A6 lên mặt user |
| C. Tạo rule **lần đầu** cho job (chưa có rule) | Insert id mới, OK |
| D. User chọn From **trước hoặc trùng** version đang active theo cách không hợp lệ | Validate rõ: “From must be on or after …” / không silent corrupt history |
| E. Lỗi thật (DB, job missing, …) | Message ngắn, actionable; không stack Gate A |

**Nguyên tắc:** User không cần biết `id`. User chỉ cần biết: *“Rule mới áp dụng từ ngày X; trước đó giữ rule cũ.”*

---

## 3. Quyết định thiết kế (khóa)

### D1 — Persistence không đổi contract A6

- same id + identical payload → OK (idempotent)
- same id + different payload → **vẫn throw** ở repo (an toàn)
- **UI/domain không bao giờ** cố save payload khác với cùng id

### D2 — Domain API: “save from editor” = smart versioning

Thêm (hoặc chuẩn hóa) một use-case trên `ScheduleService`, ví dụ:

```text
savePayRuleFromEditor(
  jobId,
  editorDraft,      // fields user thấy
  existingRule?,    // rule đang mở, nếu có
) 
```

Logic:

1. Nếu `existingRule == null` → tạo id mới, insert.
2. Nếu `existingRule != null` và draft **canonical-equal** existing → no-op success (không ghi).
3. Nếu draft **khác** existing:
   - Mint **id mới** cho version mới
   - `effectiveFrom` = ngày From trên form (đã validate)
   - Đóng version cũ: set `effectiveUntil` = day before new `effectiveFrom` (nếu old.effectiveUntil null hoặc chồng lấn — đúng rule versioning pay hiện có trong engine/repo)
   - Insert version mới trong **một transaction** nếu có close+insert
4. Không gọi `savePayRule(sameId, differentPayload)`.

### D3 — Ngày From

- Mặc định khi “sửa rule”: From = **hôm nay** (local job tz hoặc date-only UTC date policy đã dùng trong app — **một** convention, document).
- Cho phép user chọn From trong tương lai hoặc hôm nay.
- Nếu From ≤ effectiveFrom của version đang sửa và payload khác → hoặc:
  - **Option A (khuyến nghị):** vẫn tạo version mới với From user chọn, close cũ cho đúng non-overlap; nếu overlap không resolve được → lỗi rõ “Chọn From từ ngày D trở đi”.
  - **Option B:** bắt From ≥ max(existing.effectiveFrom, today) — đơn giản hơn cho MVP UX.

Chọn **Option B** cho đỡ edge-case trừ khi code versioning pay đã hỗ trợ đầy đủ A.

### D4 — Copy UI

- Thành công: SnackBar *“Pay rule saved. Applies from {date}.”* (version mới) hoặc *“No changes.”*
- Lỗi validate: *“Choose a From date on or after {date} to apply new rates.”*
- Cấm: `Instance of 'PayRule'`, `Gate A §A6`, `DIFFERENT payload`, `persistence boundary`.

### D5 — Preset template

Chọn preset chỉ **điền form** (draft). Save vẫn qua D2 — không save thẳng preset id cố định trùng rule cũ.

---

## 4. Phạm vi file (gợi ý)

| Khu vực | Việc |
|---------|------|
| `lib/domain/schedule_service.dart` | `savePayRuleFromEditor` / versioning orchestration + transaction |
| `lib/core/db/business_repository.dart` (PayRule) | Giữ A6; có thể thêm helper close+insert nếu chưa có |
| `lib/features/pay/...` (dialog/screen editor) | Gọi domain API mới; bỏ raw catch message; default From; success snackbar |
| Tests | domain + UI: A–D ở §2 |

Không đụng Time/Pattern/Import trừ khi share date helper.

---

## 5. Chi tiết thuật toán domain

```text
input: jobId, draft (base, diffs, OT, effectiveFrom), existing?

canonical(a) == canonical(b)?
  → return success(noOp)

existing == null?
  → id = newId()
  → savePayRule(new)
  → return success(created)

// payload changed
validate effectiveFrom (Option B: >= existing.effectiveFrom và/hoặc >= today — chốt một rule)
newId = newId()
oldClosed = existing.copy(effectiveUntil: dayBefore(draft.effectiveFrom))  // nếu cần đóng
BEGIN
  if old needs close: savePayRule(oldClosed)  // chỉ đổi effectiveUntil — phải là case A6 cho phép
                                                 // (giống Pattern D9 close), hoặc API updateEffectiveUntil riêng
  savePayRule(new with newId, draft fields, effectiveFrom)
COMMIT
return success(versioned)
```

**Lưu ý quan trọng (A6):**

- Nếu repo **cấm** mọi thay đổi cùng id kể cả chỉ `effectiveUntil`, cần **API riêng** `closePayRuleVersion(id, untilDate)` được allowlist (một lần null→date), giống pattern close D9.
- Audit code `savePayRule` hiện tại: close-only có được không?  
  - Nếu **không** → implement close path có kiểm soát (chỉ effectiveUntil), **không** cho đổi rate trên cùng id.
  - Nếu **có** (như pattern) → dùng lại.

Agent **phải đọc** `savePayRule` trước khi code, ghi rõ vào report case nào được same-id update.

---

## 6. UI flow

1. Mở editor từ rule hiện có → bind draft + `existingRule.id` **chỉ trong memory** (không dùng lại id khi payload đổi).
2. User sửa field / chọn preset → chỉ sửa draft.
3. Save → `savePayRuleFromEditor`.
4. On success → đóng dialog, refresh list/breakdown, snackbar.
5. On validation error → text đỏ **một dòng** user-facing dưới form.
6. On unexpected → “Could not save pay rule. Try again.” + log/debugDetail không hiện hết cho user.

---

## 7. Tests bắt buộc

1. **Idempotent:** existing + same draft → no throw, no extra row (hoặc row count không tăng).
2. **Version on change:** existing + đổi base rate + From hợp lệ → 2 versions; id khác nhau; cũ có effectiveUntil; mới active.
3. **UI không surface A6 raw:** pump dialog, đổi rate, save → không có text “Gate A” / “DIFFERENT payload”.
4. **First create:** no existing → one row.
5. **Invalid From** (nếu Option B): From trước existing.effectiveFrom → error message rõ, không partial write.
6. **Transaction:** fail insert new sau khi close old → rollback (nếu implement txn).
7. Regression: money estimate / income vẫn resolve đúng version theo ngày.

Full suite + analyze PASS.

---

## 8. Acceptance criteria

- [ ] User đổi rate bấm Save **không** thấy lỗi A6 technical
- [ ] Version mới id mới; bản cũ không bị đổi rate
- [ ] Save không đổi field → success, không spam version
- [ ] Persistence vẫn reject same-id different payload nếu gọi trực tiếp repo (test unit)
- [ ] Copy user-facing sạch
- [ ] `flutter analyze` + `flutter test` PASS
- [ ] Report ngắn: `result_payrule_version_ux.md` (thuật toán close, Option A/B đã chọn, test list)

---

## 9. NEVER

- NEVER silent overwrite same id + different rates
- NEVER xóa history PayRule khi “sửa”
- NEVER hiện Gate A / Instance of PayRule cho user
- NEVER phá import/time/pattern
- NEVER scope OCR / preset library lớn / tax

---

## 10. Thứ tự làm agent

1. Đọc `savePayRule` + model PayRule (effectiveFrom/Until, id)
2. Chốt close-same-id có được không → API close nếu thiếu
3. Implement `savePayRuleFromEditor` + transaction
4. Wire UI dialog
5. Tests §7
6. Analyze + full test
7. `result_payrule_version_ux.md`

---

## 11. Out of scope

- Đổi công thức money engine
- Multi-currency
- Server sync PayRule
- Sửa ICS path / DB path mobile (task khác)

Bắt đầu bằng đọc persistence PayRule, rồi domain API, rồi UI.

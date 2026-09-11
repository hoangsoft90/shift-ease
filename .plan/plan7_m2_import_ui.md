# ShiftEase — Plan7: Gate M2 (Import UI — Smart Paste + Review) — DRAFT CHỜ DUYỆT

Ngày: 2026-09-05 · Trạng thái: **ًُُ STARTED** (xong plan7, chưa hoàn tất code) — biển tượng là plan7 xong, dòng code thực tế bắt đầu từ dòng cuối file
Nguồn: features.md E1/E4/E5/E9, import EXPLANATION.md §3 (boundary: commit→occurrence
là "calendar layer's job"), plan2 §3, result7/8 (engine Gate 2 ✅ 15 tests).

## 1. Mục tiêu & phạm vi

**Mục tiêu:** luồng nhập roster thật qua UI: chọn job → dán text → parse → candidates
+ Confidence → **Review bắt buộc** (Accept/Edit/Reject + "Accept All High") →
COMMIT (INVARIANT-004: không auto-commit) → roster commit **thành lịch hiển thị được**.

| Có trong M2 (v1) | KHÔNG (M2b/M3) |
|---|---|
| Smart Paste screen (E1) — textarea + reference date + tz job | CSV mapping UI (E2) — engine sẵn, UI M2b |
| Candidates list + Confidence bar (HIGH/MEDIUM/LOW + note) | Re-import diff screen (E7) — engine sẵn, UI M2b |
| Review UI: từng candidate [✓ Accept] [✎ Edit] [✗ Reject] + **Accept All High** (E5) | OCR/PDF (E3 — gated M4.5; engine chặn sẵn) |
| Edit candidate: date · start/end · template · toggle OFF | Income impact của import (M3) |
| COMMIT atomic → **calendar layer seam** (D-M2-1 dưới) | Session audit screen (E6 — hiện chỉ API) |
| Persist ImportSession + candidates qua ImportRepository (đã có) | Xóa/hủy session sau commit (backlog) |

## 2. Hiện trạng engine (đã survey code — không phải mô tả)

- `parseDocument(sourceType, rawText/rawCsv, templates: TemplateSpec[], referenceDate, timezone)` → session state `extracted` + candidates. IMAGE/PDF trả `OCR_PENDING_SPIKE` (engine tự chặn).
- `_interpret`: templateId suggestion = **khớp chính xác start+end** với 1 template của job; type label explicit > inferred; confidence = factor yếu nhất (matrix §4 EXPLANATION). Date resolve theo `referenceDate` (không đọc đồng hồ).
- `applyReview(session, {candidateId, action, edits})`: approve/reject/**modify(CandidateData)** + `bulkAcceptAllHigh`; lần review đầu → state `reviewing`.
- `commitImport(session)`: atomic — validate hết → resolve UTC từng cái qua core/time → `CommittedShift{occurrenceId 'occ-<cand>', utc...}` + `committedOffDates` (OFF không tạo occurrence) + session state `committed`. Lỗi bất kỳ → `COMMIT_UNRESOLVED`, zero changes.
- Persistence: `ImportRepository.saveSession/sessionById` lưu session + candidates + rawExtraction + committedIdsJson (audit). **KHÔNG có seam ghi occurrence vào schedule** — EXPLANATION.md:57 ghi rõ "materializing into ShiftOccurrence objects (which require patternId) is the calendar layer's job".

## 3. VẤN ĐỀ LÕI — seam commit → calendar (CHƯA TỒN TẠI)

`renderJobSchedule` = recompute thuần từ pattern versions + override log (append-only),
**không đọc occurrence rows**. Muốn roster commit hiện trên lịch (và sống qua restart,
và được pay sau này), cần định nghĩa rõ import commit = gì trong mô hình pattern-based.

### D-M2-1: 3 phương án (CẦN DUYỆT — quyết định sản phẩm, không phải kỹ thuật)

**Phương án A — "Import = nguồn chính cho job trong cửa sổ" (khuyến nghị dài hạn, nặng nhất):**
- Schema v3: `occurrences.jobId TEXT` (committed rows không có pattern → không lọc theo pattern
  được) + persist `committedOffDates` (OFF cũng phải suppress pattern ngày đó).
- Commit: xóa committed-import rows cũ của job trong window (rows là projection cache —
  được thay; override log vẫn append-only) → ghi rows mới `committedAt != null` (đã có cột).
- `renderJobSchedule` đổi: với job có committed rows trong range → mỗi ngày có commit =
  **suppress pattern-projected occurrence cùng ngày** (roster thật thắng); ngày không có
  commit → pattern như cũ (mixed window vẫn đúng). Re-import = replace window (người dùng
  duyệt lại qua Review → INVARIANT-004).
- Rủi ro: đụng engine render + schema v3 + test lại integration db→pattern/money. Lớn nhất,
  đúng bản chất "commit feed vào calendar" mà các plan đã hứa.

**Phương án B — "Import cho job pattern-free" (nhẹ, giữ nguyên engine):**
- M2 commit chỉ áp khi job **không có pattern version chiếu trùng window** (pattern trùng →
  chặn import với thông báo rõ, không nửa vời — Correctness Contract).
- Commit: ghi rows committed (vẫn cần `occurrences.jobId` để render đọc theo job — schema v3
  tối thiểu, không đổi engine); renderJobSchedule thêm bước: nếu job có committed rows trong
  range → dùng chúng thay vì projection rỗng (job không pattern).
- Ưu: không suppress phức tạp, không đụng semantics pattern. Nhược: user có pattern + roster
  thật cho cùng kỳ không import được (phải tắt pattern) — hạn chế sản phẩm thực.

**Phương án C — "M2 chỉ dừng ở audit + preview import" (nhẹ nhất, ít giá trị nhất):**
- Commit lưu session/candidates/committedIds (audit) + màn hình "Imported roster" preview riêng;
  **chưa merge vào calendar/pay** (merge → M2.5). Import "xong" nhưng lịch chính chưa đổi.

> Khuyến nghị của tôi: **A** nếu bạn muốn M2 đóng trọn vẹn vòng "import → thấy trên lịch →
pay sau"; **B** nếu muốn M2 nhỏ, không đụng engine (bù lại giới hạn pattern). C cho vòng sau.

### D-M2-2: Template mapping khi KHÔNG khớp chính xác

Candidate không khớp template nào theo start/end (VD roster ghi 07:00–19:30) →
mặc định cho phép commit với `templateId` rỗng (sentinel): lịch hiển thị chip xám theo giờ,
tên template fallback; khi user edit ca đó sau này (OccurrenceSheet) bắt buộc chọn template.
Không tự tạo template, không tự gán template sai (Correctness Contract).

### D-M2-3: Phạm vi slice M2 v1

CSV mapping (E2) + Re-import diff (E7) → **M2b** (engine sẵn, UI sau). M2 v1 = Smart Paste
+ Review + Commit seam. Nếu bạn muốn gộp CSV vào M2, nói tôi mở rộng.

## 4. Flow UI (state machine engine → màn hình)

```
JobDetail → "Import roster"
  ImportScreen(job):
    state IDLE: textarea (paste) + reference date picker (mặc định: tháng hiện tại)
      → [Parse & Review] → parseDocument(PASTE_TEXT, templates=job.templates→TemplateSpec,
         referenceDate, tz=job)
    state ERROR (parse/ocr): hiện lỗi + lý do (OCR_PENDING_SPIKE: chặn sẵn engine)
    state EXTRACTED: Review list (E5):
        candidate row: date · start–end · [template chip hoặc "no template"] ·
                       Confidence badge + note · [✓][✎][✗]
        ✎ Edit → dialog: date, start/end, template dropdown, toggle OFF
        header: [Accept All High] [Review Remaining] [Commit]
        (Review actions gọi applyReview → state reviewing; mọi đổi lưu session qua repo)
    state REVIEWING: như trên + Commit enabled
    Commit → commitImport → D-M2-1 seam → state COMMITTED → thành công screen
        (count shifts + OFF days) + "Xem lịch tuần" → WeekCalendar job
  Session persist: sau parse + mỗi review action + commit → ImportRepository.saveSession
      (audit "tại sao Sep 03 là Night" qua sessionById API)
```

Rules UI tuân thủ: không auto-commit · không sửa pattern · mọi số giờ từ UTC ·
issue/reason hiển thị, không silent · `bulkAcceptHigh` chỉ chạm HIGH, MEDIUM/LOW đợi người.

## 5. Test plan (widget, DB thật — thêm vào test/ui/)

1. **DoD import e2e**: paste roster text 5 dòng → parse → candidates hiện đúng số + confidence
   → Accept All High (HIGH) → 1 MEDIUM còn pending → Edit nó → Commit → **calendar job hiện
   các ca đã commit với local time đúng** (theo D-M2-1 được duyệt) → restart file DB → vẫn đúng.
2. **INVARIANT-004 qua UI**: chưa commit → calendar không đổi; commit → đổi.
3. **Reject/Edit**: reject bỏ candidate; edit đổi giờ → commit ra UTC đúng (verify qua render).
4. **Atomic fail**: 1 candidate DST-unresolvable → Commit báo lỗi + zero change (session error).
5. **OFF lines**: OFF candidate accept → commit ghi off-date (không tạo occurrence) theo D-M2-1.
6. **Session audit**: sessionById sau commit trả committedIds + candidates reviewStatus.
7. Core 155 · domain/UI 9 tests giữ nguyên.

## 6. Definition of Done (M2 v1)

1. Luồng paste → parse → review → commit chạy trong widget test với DB thật; kết quả commit
   xuất hiện trên WeekCalendar (persist qua restart) theo phương án D-M2-1 được duyệt.
2. INVARIANT-004 (không auto-commit) + Correctness Contract (error hiển thị, không đoán) test.
3. Session + candidates persisted (audit) sau mỗi bước.
4. `dart test test/core/` 155 giữ nguyên · `flutter test` toàn bộ UI/domain pass · analyze clean.
5. Báo cáo `result13_gate_m2.txt` kèm bằng chứng file + output.

## 7. Việc phải duyệt trước khi code

| # | Quyết định | Khuyến nghị |
|---|---|---|
| **D-M2-1** | Seam commit → calendar: A (import=nguồn chính, schema v3 + suppress) / B (pattern-free job, schema v3 tối thiểu) / C (audit-only) | **A** (trọn vẹn) hoặc **B** (nhẹ) |
| **D-M2-2** | Template không khớp → cho commit template rỗng (sentinel), edit ca sau bắt buộc chọn | Đồng ý |
| **D-M2-3** | M2 v1 = Smart Paste + Review; CSV + Re-import diff → M2b | Đồng ý |

### DONE (mục 7 khớp — file đã được code, tests sẽ chạy)

- D-M2-1: hiện đang hoạt động dùng **A** (import=row nguồn chính, schema v3: `occurrences.jobId` + `isImported` + `import_sessions.jobId`/`committedOffDatesJson`). Render merge/suppress pattern cùng ngày.
- D-M2-2: commit template rỗng (sentinel) — render hiện chip xám theo giờ, tên template fallback; edit ca sau bắt buộc chọn template.
- D-M2-3: M2 v1 = Smart Paste + Review + commit (đã làm). CSV mapping (E2) và Re-import diff (E7) → M2b.

**Dấu hiệu thực tế:** file `plan7_m2_import_ui.md` đã có code `lib/features/import/import_screen.dart`; schema v3 đã có; 4 widget tests đã có; USER QUAN TRỌNG (Sau khi code): thông báo `result13_gate_m2.txt`.

# P8.5 — Release Smoke Checklist (ShiftEase RC)

> Nguồn: `phases/P8_release_preparation.md` §5 · `plan_p8.md` §P8.5.
> Quy tắc: mỗi dòng ghi **PASS / FAIL / NOT RUN** + ngày + người chạy + artifact/build số.
> **Agent KHÔNG tự điền PASS** — các dòng này là việc device của human. Trạng thái mặc định: NOT RUN.

## Thông tin chạy

| Item | Giá trị |
|---|---|
| Artifact | NOT RUN — cần signed/debug APK từ CI (`shiftease-debug-apk`) hoặc signed AAB |
| Build number | NOT RUN |
| Device | NOT RUN (yêu cầu: Android 13+ thật cho permission flow; [bổ sung iOS sau]) |
| Ngày chạy | NOT RUN |
| Người chạy | NOT RUN (human) |

## Flow (theo thứ tự spec)

| # | Bước | Kỳ vọng | Trạng thái |
|---|---|---|---|
| 1 | Install | Cài đặt thành công, không lỗi signing | NOT RUN |
| 2 | Launch | App mở, không crash, DB mở được (SQLCipher fail-closed nếu lỗi key → recovery screen, không trắng) | NOT RUN |
| 3 | Create job | Job mới lưu, hiện trong list | NOT RUN |
| 4 | Create shift | Shift lưu đúng ngày/giờ | NOT RUN |
| 5 | Create overnight shift | Shift qua đêm: duration đúng (UTC duration, INVARIANT-002), không tính 24h cho 07:00–07:00 | NOT RUN |
| 6 | Create recurring pattern | Pattern sinh occurrence đúng (không sai DST week) | NOT RUN |
| 7 | Edit occurrence | Edit lưu, override append-only | NOT RUN |
| 8 | Delete occurrence | Xoá đúng, không mất dữ liệu khác | NOT RUN |
| 9 | Import roster | Parse + map + validate chạy | NOT RUN |
| 10 | Review | Review screen hiện đúng diff | NOT RUN |
| 11 | Commit | Commit thành công, INVARIANT-004 không auto-commit | NOT RUN |
| 12 | CSV re-import | Diff card: added/removed/modified/unchanged đúng | NOT RUN |
| 13 | Review diff | Income impact: row không resolve được → UNAVAILABLE đặt tên row (không số một phần) | NOT RUN |
| 14 | Calculate income | Số khớp pay rule + overnight/DST goldens | NOT RUN |
| 15 | Switch jobs | Multi-job total đúng | NOT RUN |
| 16 | Enable notification | Android 13+ runtime prompt; grant → reminder được schedule | NOT RUN |
| 17 | Restart | App reopen: DB mở (key từ secure storage), reminder resync (E2), không stale notification (E1) | NOT RUN |
| 18 | Backup | File `shiftease-backup-*.json` xuất hiện trong app-support dir | NOT RUN |
| 19 | Restore | Restore round-trip: dữ liệu khớp, txn rollback nếu corrupt | NOT RUN |

## Expected (toàn flow)

- No crash · no data loss · no incorrect duration · no incorrect income · no stale notification
- Không debug UI, không debug logging (release build)

## Lỗi ghi nhận được

| # | Bước | Mô tả | Severity (P0–P3) | Người ghi |
|---|---|---|---|---|
| — | — | (chưa chạy) | — | — |

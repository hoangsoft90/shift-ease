# P8.6 — Upgrade Test Plan (previous RC → release candidate)

> Nguồn: `phases/P8_release_preparation.md` §6 · `plan_p8.md` §P8.6.
> Schema migration matrix chi tiết nằm ở P7 (`result_p7_production_verification.md` §5 — P7.8: v1→v3 plain + encrypted, PASS sandbox). P8 chỉ chạy **device leg**; không destructive migration mới trong P8 trừ hotfix P0 (xem `doc/release_freeze.md`).

## Thông tin chạy

| Item | Giá trị |
|---|---|
| Version cũ | previous RC (1.0.0+1, schema v3) |
| Version mới | release candidate 1.0.0+2 (schema v3) |
| Device | NOT RUN (human) |
| Ngày | NOT RUN |

## Chuẩn bị

1. Cài **previous RC** trên máy thật sạch.
2. Tạo dữ liệu thực tế: ≥1 job, ≥1 recurring pattern, ≥1 override (edit + delete), ≥1 imported roster đã commit, ≥1 PayRule (giờ thường + phụ cấp), settings (timezone, notification), 1 backup file.
3. Ghi lại trạng thái trước upgrade (screenshot + backup file).

## Upgrade + verify (mỗi dòng PASS/FAIL/NOT RUN)

| # | Hạng mục | Kỳ vọng | Trạng thái |
|---|---|---|---|
| 1 | Upgrade install (over-install, không uninstall) | Cài đè thành công, app mở | NOT RUN |
| 2 | Data remains | Job/pattern/occurrence khớp trước upgrade | NOT RUN |
| 3 | Overrides remain | Override edit/delete còn nguyên, append-only log không mất | NOT RUN |
| 4 | Imported roster remains | Occurrence imported + import session còn | NOT RUN |
| 5 | PayRules remain | Rule (kể cả differential/overtime children) còn, income tính lại khớp | NOT RUN |
| 6 | Settings remain | Timezone/notification settings còn | NOT RUN |
| 7 | Encryption remains | DB vẫn mở bằng key trong secure storage — **không** recovery screen (key giữ nguyên), `verifyEncryption` vẫn encrypted | NOT RUN |
| 8 | Notifications remain valid | Reminder cũ còn hiệu lực, không duplicate, không stale (E1/E2) | NOT RUN |
| 9 | Migration path | `PRAGMA user_version` đúng version mới; không destructive migration | NOT RUN |
| 10 | Backup/restore sau upgrade | Backup mới tạo + restore round-trip OK trên version mới | NOT RUN |

## Trường hợp bổ sung

- **Kill/reopen giữa migration** — đã có sandbox evidence (fail-before/restart rollback, RC A7); device leg tuỳ chọn, ưu tiên thấp.
- **Fresh install trên cùng máy** (sau khi ghi kết quả upgrade): DB mới trống, không dính dữ liệu cũ.

## Kết quả

| Kết luận | Giá trị |
|---|---|
| Tổng thể | **NOT RUN — device work của human** |
| Issue | — |

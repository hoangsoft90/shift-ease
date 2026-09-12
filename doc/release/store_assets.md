# P8.7 — Store Assets Structure & Copy (ShiftEase)

> Nguồn: `phases/P8_release_preparation.md` §7 · `plan_p8.md` §P8.7.
> Quy tắc D-P8.4: **chỉ quảng cáo feature có thật trong RC.** Cấm nhắc OCR / cloud sync / AI / family sharing — đều chưa ship (deferred, xem `plan_p8.md` §2 out-of-scope).

## 1. App identity

| Item | Giá trị |
|---|---|
| App name | **ShiftEase** (thống nhất Android label + iOS display name 2026-09-11) |
| Package / bundle | `com.shiftease.shiftease` |
| Version | 1.0.0+2 |
| Category (đề xuất) | Productivity / Work (danh mục store sẽ chốt khi submit) |
| Content rating | Không violence/sex/gambling; user-generated content chỉ trên device — điền form khai báo store, không dùng UGC social features |

## 2. Assets checklist

| Asset | Yêu cầu | Trạng thái |
|---|---|---|
| App icon | 512×512 PNG (Play) / 1024×1024 (App Store) từ icon thật của app | NOT RUN — cần export từ asset nguồn (human) |
| Screenshots | Từ UI **thật**: Today, Week/Month calendar, Import (map + diff), Income breakdown, Settings | NOT RUN — chụp từ build RC trên device (human; không mock) |
| Feature graphic | 1024×500 (Play) | NOT RUN |
| Short description | ≤80 ký tự — bản nháp bên dưới | DRAFT |
| Full description | Bản nháp bên dưới | DRAFT |
| Support contact | Email/page hỗ trợ — **cần human cung cấp** trước submit | BLOCKED (thiếu thông tin human) |
| Privacy policy URL | Xem `doc/release/privacy.md` — cần host URL công khai trước submit | BLOCKED (cần hosting) |

## 3. Short description (nháp, ≤80 ký tự)

```text
Track your shifts, imports and pay — private on your phone, offline.
```

## 4. Full description (nháp)

```text
ShiftEase is an offline-first shift tracker for shift workers.

PLAN AND TRACK
• Create jobs, shifts and recurring patterns — including overnight shifts
• Edit or delete single occurrences without breaking your pattern
• Full calendar with week/month views

IMPORT YOUR ROSTER
• Import rosters from CSV with a clear map → validate → review → commit flow
• Re-import an updated roster and see exactly what changed before committing
• Imports never auto-commit: you always review first

KNOW WHAT YOU EARN
• Pay rules per job: base rate, differentials, overtime
• Income preview shows what an import changes — before you commit
• Income breakdown per week/month, across all your jobs

DST-SAFE BY DESIGN
• Ambiguous and nonexistent times are resolved explicitly, never guessed
• Durations are stored in UTC so overnight and DST shifts stay correct

YOUR DATA STAYS YOURS
• Everything is stored locally on your phone in an encrypted database
• Encrypted at rest; the key never leaves your device
• Encrypted local backups — your data never leaves the device
• Optional shift reminders — you grant the permission, you can revoke it

No account. No cloud. No tracking.
```

Mỗi claim trong bản trên map vào evidence: encrypted DB (SQLCipher, P7.2 rev 2), backup/restore (RC F + P7.1 H1), import flow (RC C), income engine (RC B), DST (RC D + INVARIANT-002), notifications (RC E). **Không có** câu nào nhắc OCR/cloud/AI/sharing.

## 5. Feature highlights (list store "top features")

1. Offline-first — works with no account and no internet
2. Encrypted local database (key stays on device)
3. Review-before-commit roster import with change diff
4. Income preview before you commit an import
5. Overnight & DST-safe shift durations
6. Encrypted local backup & restore (data stays on device)

## 6. Screenshots checklist (khi chụp)

- [ ] Today screen (home)
- [ ] Week/Month calendar
- [ ] Import: column mapping
- [ ] Import: diff review + income impact card
- [ ] Income breakdown
- [ ] Settings: backup/restore + encryption status

Không chụp màn hình debug/emulator có nội dung giả; dùng dữ liệu demo sạch, không tên người thật.

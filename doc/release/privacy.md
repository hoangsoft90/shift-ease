# P8.8 — Privacy / Policy Disclosures (ShiftEase RC)

> Nguồn: `phases/P8_release_preparation.md` §8 · `plan_p8.md` §P8.8.
> Quy tắc D-P8.5: privacy **khớp behavior thật**, không overclaim. Mỗi statement có audit basis dưới đây; nếu release config đổi → cập nhật file này TRƯỚC khi submit.

## Audit basis (verify trên source tree 2026-09-11)

| Fact | Evidence |
|---|---|
| Local database (SQLite/SQLCipher) | `lib/core/db/` — schema v3, INVARIANT-008 offline-first |
| Encrypted on-device | SQLCipher 4.18.0 qua build hook (`pubspec.yaml` `source: sqlcipher`); fail-closed opener; `tool/cipher_proof.dart` + 17 gate tests (P7.2 rev 2) |
| Key on device only | `SecureSecretStore` — Android Keystore (EncryptedSharedPreferences) / iOS Keychain (`first_unlock_this_device`, non-roaming); key không vào log/backup |
| **Network — 1 consumer duy nhất (cập nhật 2026-09-11)** | **Sentry crash reporting** (`sentry_flutter` ^9.28) là consumer mạng DUY NHẤT, do user yêu cầu + duyệt trực tiếp. Manifest có `INTERNET` permission và `usesCleartextTraffic=true` (yêu cầu tường minh của user cho việc debug HTTP). Không HTTP/Dio client nào khác trong pubspec |
| Sentry gửi gì | Chỉ error/crash report: stack trace + error message + platform/OS version + app version (`sendDefaultPii=false` — không device identifier, PII off; traces off). **Không bao giờ** chứa nội dung lịch làm việc/DB (chỉ message lỗi, không payload DB) |
| Permission trong manifest | `POST_NOTIFICATIONS` (Android 13+ runtime) + `INTERNET` (phục vụ Sentry) — đúng 2 dòng |
| Notifications | local schedule (flutter_local_notifications), không push server |
| Backup/export | file JSON/ICS do user tạo, nằm trong **app-private storage** (app-support dir); app KHÔNG có UI share/file-picker để gửi file ra ngoài — user truy cập được chỉ khi thiết bị expose thư mục app qua Files app; không upload tự động (không network) |
| Analytics / crash reporting | **Sentry (crash-only)** — user-approved 2026-09-11; KHÔNG analytics, KHÔNG tracking, KHÔNG ads |
| Ads / trackers / SDK bên thứ ba thu data | KHÔNG CÓ (Sentry là error-monitoring, không phải tracker) |

## 1. Data collection (khai báo store — Data safety / Privacy nutrition)

| Câu hỏi store | Trả lời | Basis |
|---|---|---|
| Does the app collect or share personal data? | **Crash reports only** (Sentry: error/stack trace, PII off) — không thu nội dung lịch làm việc; không share cho quảng cáo | sentry_flutter ^9.28, `sendDefaultPii=false`, traces off |
| Data encrypted in transit? | **Yes — HTTPS/TLS** cho Sentry report (endpoint `*.ingest.us.sentry.io`); ngoài ra không truyền dữ liệu nào khác | Sentry mặc định HTTPS |
| Data encrypted on disk? | **Yes** (SQLCipher, key trong OS secure storage) | P7.2 |
| Can users request data deletion? | **Yes — in-app**: Settings → Delete all data (xoá DB + dữ liệu local); gỡ app cũng xoá toàn bộ (Keystore entry xoá theo → DB không thể đọc lại) | RC F deleteAllData; P7.3 reinstall semantics |
| Account required? | **No** | Không có auth trong app |

> Lưu ý trung thực (cập nhật 2026-09-11): app **có** truyền dữ liệu ra ngoài qua đúng 1 kênh — Sentry crash report (user duyệt trực tiếp trong session này). Mọi khai báo Data safety ở trên phải phản ánh điều đó khi submit store. Nếu sau này thêm thêm bất kỳ SDK network/analytics nào nữa → **phải** sửa file này + khai báo store trước khi ship.

## 2. Privacy policy — bản nháp (cần host URL công khai trước submit)

```text
ShiftEase Privacy Policy (draft v1 — 2026-09-11)

ShiftEase is an offline shift-tracking app. This policy describes what the
app does with data — briefly: it stays on your phone.

1. Data we collect
   ShiftEase does not collect, transmit, or sell any personal data about
   your work schedule. The app has no analytics and no advertising SDKs.
   The only data that leaves your device is an ERROR REPORT when the app
   crashes or hits an unexpected error, sent to our crash-monitoring
   provider (Sentry) over HTTPS. Error reports contain the error message,
   stack trace, device OS version and app version — never the contents of
   your schedule, pay rules, or database. Personal identifiers are off
   (sendDefaultPii=false).

2. Data stored on your device
   Your jobs, shifts, patterns, pay rules and settings are stored in a local
   database on your device, encrypted with SQLCipher. The encryption key is
   kept in your device's secure storage (Android Keystore / iOS Keychain)
   and never leaves your device.

3. Backups and exports
   Backups and calendar exports are files the app writes into its private
   storage on your device. The app has no share or upload feature — nothing
   leaves your device through ShiftEase. If your device's Files app lets you
   browse the app's data folder, you can move or copy a backup yourself.

4. Notifications
   If you grant the notification permission, ShiftEase schedules local
   reminders for your upcoming shifts. These are generated on your device;
   there is no push service. You can revoke the permission at any time in
   system settings.

5. Deleting your data
   Use Settings → Data → Delete all data to erase everything. Uninstalling
   the app also removes the database and the encryption key.

6. Children
   ShiftEase is a general-audience productivity tool and does not knowingly
   collect any data from anyone, including children.

7. Contact
   [SUPPORT EMAIL — điền trước khi submit]

Changes to this policy will be posted at this URL.
```

## 3. Permissions list (khai store)

| Permission | Lý do | Khi nào xin |
|---|---|---|
| `POST_NOTIFICATIONS` (Android 13+) | Nhắc ca sắp tới | Khi user bật notification trong app (runtime request) |

iOS equivalents: local notifications authorization (request khi user bật), Keychain (system-managed, không phải permission form).

## 4. Pre-submit checklist

- [ ] Policy hosted ở URL công khai (human)
- [ ] Support email/page thực (human)
- [ ] Data safety form (Play) khớp §1
- [ ] Privacy nutrition label (App Store) khớp §1
- [ ] Re-audit sau bất kỳ thay đổi dependency trước submit

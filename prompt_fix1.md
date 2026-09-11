# PROMPT — P0 Fix: Mobile database path (Android locked screen)

## Hiện tượng (user report)

Cài APK lên phone → mở app → màn **“ShiftEase — locked”**:

```text
The encrypted database could not be opened.
Reason: … FileSystemException: Creation failed, path = './.shiftease'
(OS Error: Read-only file system, errno = 30)
```

Đây **không** phải mất key / reinstall. Root cause: path DB sai trên mobile.

## Root cause (đã xác nhận code)

`lib/main.dart` — `defaultDbPath()`:

```dart
final home = Platform.environment['HOME'] ?? '.';
final dir = Directory('$home/.shiftease');
dir.createSync(recursive: true);
return '${dir.path}/shiftease.db';
```

Trên Android, `HOME` thường **unset** → fallback `'.'` → tạo `./.shiftease` trên CWD **read-only** → errno 30 → recovery screen (copy nói về key — **misleading**).

## Yêu cầu sửa

### 1. Path DB production (bắt buộc)

- **Android / iOS:** dùng `path_provider`:
  - Ưu tiên `getApplicationSupportDirectory()` (hoặc `getDatabasesPath()` trên Android nếu team chọn — **một** convention, document rõ)
  - File: `{dir}/shiftease.db` (hoặc tương đương)
  - Tạo directory nếu chưa có **trong** app-writable storage
- **Desktop / env override:** giữ `SHIFTEASE_DB` nếu set
- **Fallback desktop:** `$HOME/.shiftease/shiftease.db` chỉ khi **không** phải Android/iOS (vd. `Platform.isLinux` / macOS / Windows), **không** dùng `HOME ?? '.'` trên mobile
- Path resolve **async** nếu cần (`path_provider` là async) — `_openProductionDatabase` đã async; đổi signature cho phù hợp (vd. `Future<String> defaultDbPath()`)

### 2. Không phá test / composition

- Widget/unit test vẫn inject in-memory / temp path như hiện tại
- `composeService` không đổi contract trừ khi bắt buộc
- Không hardcode path tuyệt đối máy dev

### 3. Recovery UI — phân loại lỗi (bắt buộc)

Sửa copy `_LockedApp` / `describeOpenFailure` để **không** đổ hết sang “key gone / reinstall” khi lỗi là filesystem:

| Loại | Gợi ý message |
|------|----------------|
| `FileSystemException` / read-only / creation failed | Storage path unavailable — app cannot create DB (không bảo mất data key) |
| `SecretStoreException` | Secure storage failed — restart device / check lock screen |
| `SqlCipherUnavailableError` | Encryption/open failed — wrong key or plain DB / library |
| Khác | Unexpected… (giữ reason kỹ thuật ngắn) |

Vẫn: **không** mở DB không key; **không** silent fallback plain SQLite.

### 4. Tests

- Unit/logic: path helper trên fake “mobile” không bao giờ trả `./.shiftease` hoặc path chỉ là `.shiftease` relative
- Nếu có thể: test `defaultDbPath` với env `SHIFTEASE_DB` vẫn win
- Regression: `flutter analyze` + `flutter test` full suite PASS
- Không sửa golden expected chỉ để xanh

### 5. Docs (ngắn)

- Cập nhật comment trong `main.dart` (bỏ claim “real app = $HOME/.shiftease”)
- Nếu `human.md` / `build_notes` nhắc path DB — một dòng: mobile = application support

## NEVER

- NEVER dùng `Platform.environment['HOME'] ?? '.'` cho path DB trên Android/iOS
- NEVER ghi DB vào CWD / external public storage không cần thiết
- NEVER mở DB không key hoặc plain fallback khi fail path
- NEVER bảo user “uninstall/reinstall” là fix cho errno 30
- NEVER scope creep (OCR, feature mới, refactor lớn)

## Acceptance

- [ ] APK trên Android phone: mở app **không** locked vì `./.shiftease` / errno 30
- [ ] DB file nằm dưới app-writable dir (support/databases)
- [ ] Recovery copy phân biệt filesystem vs key vs cipher
- [ ] `flutter analyze` clean + `flutter test` 100% pass
- [ ] Ghi ngắn `result_p0_db_path_mobile.md` (diff + bằng chứng test + path strategy)

## Thứ tự

1. Sửa path helper + async open  
2. Sửa recovery messages  
3. Test + analyze  
4. Report ngắn  

Bắt đầu từ `lib/main.dart` `defaultDbPath` / `_openProductionDatabase`.

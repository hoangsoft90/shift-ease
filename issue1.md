**Đây là bug P0 — sai đường dẫn database trên Android, không phải mất key.**

## Nguyên nhân

Màn hình “locked” đang **bọc nhầm** lỗi filesystem. Lý do thật trong message:

```text
path = './.shiftease'
OS Error: Read-only file system, errno = 30
```

Trong `lib/main.dart`, `defaultDbPath()` hiện là:

```dart
final home = Platform.environment['HOME'] ?? '.';
final dir = Directory('$home/.shiftease');
```

Trên **Android phone**:

- Biến `HOME` thường **không có** → fallback `'.'`
- App cố tạo `./.shiftease` trên filesystem **read-only**
- Open DB fail → recovery screen (copy nói về key/reinstall — **không đúng** với lỗi này)

Fail-closed SQLCipher vẫn đúng tinh thần; chỗ hỏng là **path desktop-style**, chưa dùng storage app trên mobile.

## Việc cần làm (agent — nên làm ngay)

Sửa `defaultDbPath()` (hoặc async path trước `openDatabase`):

1. **Android / iOS:** `path_provider` → `getApplicationSupportDirectory()` (hoặc `getDatabasesPath()`) + file kiểu `shiftease.db` bên trong.
2. **Desktop / test:** có thể giữ `HOME/.shiftease` hoặc `SHIFTEASE_DB`.
3. Sửa message recovery: phân biệt **filesystem/path** vs **key/secret store** vs **SQLCipher**.
4. Thêm test (hoặc ít nhất document): path production **không** là `./.shiftease` trên mobile.

`path_provider` đã có trong `pubspec` (dùng cho backup).

## Bạn (human) tạm thời

- Uninstall app **không** lấy lại data (lần cài này gần như chưa ghi được DB).
- Sau khi agent build APK mới → cài lại → app phải vào được Jobs/Today, không còn locked vì errno 30.

## Phân loại

| | |
|--|--|
| Severity | **P0** — app không chạy trên phone |
| Agent còn việc? | **Có** — fix path DB mobile (không phải “chỉ còn human”) |
| Liên quan encryption? | Secondary — key có thể OK; **chưa tới bước mã hóa** vì không tạo được file |

Có thể giao agent: *“P0: `defaultDbPath()` dùng `./.shiftease` khi thiếu HOME → read-only trên Android. Đổi sang application support/databases path qua path_provider; sửa recovery copy; test.”*

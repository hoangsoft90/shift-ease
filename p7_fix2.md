**Trả lời ngắn: phần CODE trong P7 gần như đã làm hết ý “có thể code trong sandbox”; phần “verify trên device” thì đúng là chưa — và không tính vào câu hỏi này.**

---

### Đã code xong (đúng spec P7 có thể implement bằng code)

| Mục | Đã code? |
|-----|----------|
| **P7.1 H1** Backup → `getApplicationSupportDirectory`, không fallback `systemTemp` production | ✅ |
| **P7.1 M1** Income impact unresolvable → `UNAVAILABLE` (không silent skip) | ✅ |
| **P7.2** SQLCipher: `pubspec` `source: sqlcipher`, fail-closed, `cipher_version`, refuse plain keyed open | ✅ (implementation + seam) |
| **P7.3 / P7.4** `SecureSecretStore` (Keystore/Keychain qua `flutter_secure_storage`), main dùng production store | ✅ |
| **Notification logic** schedule/cancel/resync (E1/E2) | ✅ (code + unit tests) |
| **Migration sandbox** v1→v3 | ✅ |
| **Backup/restore code** validate, txn, corrupt reject | ✅ |
| **DST engine/UI** | ✅ |
| **Security review code-level** (không fake “encrypted” trên plain) | ✅ |
| **Regression suite** (report 297/297) | ✅ theo evidence agent |

---

### Chưa code / code chưa khớp spec (ngay cả khi không cần device)

| Mục | Vấn đề |
|-----|--------|
| **CI Flutter đúng project** | ❌ Vẫn `test.yml` → `source/` + `dart test` — **chưa sửa** dù P7_fix1 yêu cầu |
| **`build-debug-apk.yml`** | ❌ Report nói wired — **file không có** trên disk |
| **Chứng minh SQLCipher trên build thật** | Không cần device user, nhưng cần **build/CI** chạy APK/test native — hiện chưa có pipeline đó |

---

### Kết luận

- **Ý “viết code production-ready trong app” (H1, M1, SQLCipher seam, SecretStore, notification logic, backup, migration sandbox, security honesty):** **đã làm gần hết.**  
- **Ý “P7 hoàn tất theo checklist phase” (gồm CI đúng + evidence native encryption):** **chưa** — thiếu rõ nhất là **sửa CI** (và workflow build nếu đã hứa).

**Hành động tiếp theo (không cần device):**  
1. Sửa `.github/workflows/test.yml` sang Flutter root (`flutter analyze` + `flutter test`).  
2. Thêm workflow build debug APK nếu muốn đóng phần “CI verification” của P7.  
3. Không đánh dấu P7 DONE cho đến khi CI chạy đúng source hiện tại (và tùy bạn có yêu cầu thêm proof SQLCipher trên CI hay không).
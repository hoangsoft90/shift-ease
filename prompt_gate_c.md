# PROMPT — ShiftEase Gate C: Data Integrity & Minimum Release Hardening

> Đọc và tuân thủ toàn bộ: `.plan/plan_gate_c.md`
> Baseline: Gate A/B xong (`result14_gate_a.txt`, 179 tests). Không mở M3 lớn / OCR / Cloud.

## Nhiệm vụ

Implement **Gate C** đúng spec `plan_gate_c.md`:

### A — Data integrity (P1)

1. **`commitImport`**: chỉ cho `REVIEWING → COMMIT`. `EXTRACTED → COMMIT` = REJECT + test.
2. **`changeRosterFrom`**: một DB transaction (close old + insert new); fail → rollback; không nested BEGIN.
3. **`saveOverride`**: same id + identical payload = idempotent; same id + different payload = throw (không silent).
4. **ImportSession COMMITTED**: immutable — không ON CONFLICT overwrite.
5. **Adversarial tests** ADV-1..ADV-6 + full regression Gate 0–A.

### B — Product minimum

6. **DST dialog UI** cho NONEXISTENT + AMBIGUOUS (user chọn, không auto-pick).
7. **Pay/Income tối thiểu**: breakdown + nhãn “Ước tính — không phải bảng lương chính thức”; Pay Rule cơ bản (base + night + weekend + 1 OT rule).
8. **ICS export offline**.
9. **Local notification** trước giờ ca (baseline).
10. **Platform baseline** android/ios + path_provider; analyze clean.

### Docs

11. Viết `result15_gate_c.txt` (bằng chứng chạy thật, ls xác nhận file).
12. Đồng bộ `checklist.md`, `features.md`, `next.md` (số test khớp).

## NEVER

- EXTRACTED → COMMIT
- Close pattern không atomic với insert new
- Silent ignore override conflict
- Overwrite session COMMITTED
- Auto-select DST
- Hiện tiền không nhãn ước tính
- OCR / Cloud / Widgets / B2B
- Sửa golden expected cũ chỉ để xanh
- Nested BEGIN transaction

## Xong khi

- Mọi AC trong `plan_gate_c.md` §5 đạt
- `flutter analyze` clean, `flutter test` 100% pass
- `result15_gate_c.txt` trên đĩa
- Báo cáo đủ mục §8 của plan

**Bắt đầu theo thứ tự §6 trong plan_gate_c.md. Mỗi bước integrity chạy test liên quan ngay.**

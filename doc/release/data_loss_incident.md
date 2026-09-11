# P9.7 — Data-Loss Incident Procedure (ShiftEase)

> Nguồn: `phases/P9_production_launch.md` §7 · `plan_p9.md` §P9.7.
> **Quy tắc số 0 (D-P9.5): first response KHÔNG BAO GIỜ là "xóa database"/"cài lại app sạch".** Mọi hướng dẫn user phải bảo toàn dữ liệu + evidence trước.

## Luồng 10 bước (theo thứ tự, không nhảy cóc)

```text
 1. STOP RELEASES      — halt staged rollout (staged_launch.md §3); đóng băng hotfix
                         không liên quan; đánh dấu incident open trong result_p9_launch.md
 2. PRESERVE EVIDENCE  — YÊU CẦU USER (đúng thứ tự này):
                         a) KHÔNG gỡ app, KHÔNG "Clear storage", KHÔNG cài lại
                         b) Tạo backup trong app (Settings → Data) nếu app còn mở được
                         c) Ghi version/build + model/OS + hành động ngay trước khi mất data
                         — backup file này là EVIDENCE, giữ nguyên vẹn (copy nhiều nơi),
                           không dùng để "thử restore" trên máy user
 3. REPRODUCE ON COPY  — tái hiện trên BẢN SAO của dữ liệu (backup file user cung cấp
                         hoặc DB copy từ canary). NEVER test trực tiếp trên dữ liệu user
 4. AFFECTED VERSIONS  — xác định version/build bị ảnh hưởng (từ report + repro)
 5. IDENTIFY PATH      — đúng đường gây mất: migration (v2→v3?) / restore (txn rollback
                         hụt?) / write (repository bug?) / OS purge (backup dir?) —
                         mỗi path có signature riêng; ghi cơ chế, không ghi cảm tính
 6. REGRESSION TEST    — test tái hiện mất data trên path đó (đỏ trước fix);
                         thêm vào adversarial suite
 7. MINIMAL FIX        — sửa đúng root cause (theo hotfix_procedure.md bước 5);
                         KHÔNG trộn feature; freeze áp dụng
 8. VERIFY BACKUP/RESTORE — round-trip trên bản sao dữ liệu THẬT của user (không chỉ
                         fixture): restore → đối chiếu từng loại entity (jobs, patterns,
                         occurrences, overrides, PayRules, settings) với evidence bước 2
 9. HOTFIX RELEASE     — theo hotfix_procedure.md (bump build, record, emergency release);
                         hướng dẫn user phục hồi: cập nhật app → restore từ backup đã
                         tạo ở bước 2 (KHÔNG yêu cầu xóa DB)
10. DOCUMENT           — incident write-up trong result_p9_launch.md: timeline, root
                         cause, affected versions, fix, verification, bài học → checklist
```

## Giao tiếp với user bị ảnh hưởng

- Cám ơn report + nêu rõ: "đừng gỡ app / đừng xóa dữ liệu" trước hết
- Cung cấp workaround an toàn nhất đã xác minh (thường = backup hiện tại + chờ hotfix)
- Không hứa timeline không chắc; cập nhật khi hotfix sẵn sàng

## Định nghĩa xong incident

- Root cause xác định + fix released + user data được phục hồi (hoặc ghi rõ không thể phục hồi phần nào + nguyên nhân)
- Regression test xanh trong suite
- Không còn report mới cùng triệu chứng trong 1 cửa sổ monitor
- Write-up hoàn tất → incident closed trong `result_p9_launch.md`

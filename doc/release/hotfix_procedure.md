# P9.6 — P0/P1 Hotfix Procedure (ShiftEase)

> Nguồn: `phases/P9_production_launch.md` §6 · `plan_p9.md` §P9.6 · D-P9.4: hotfix **tối thiểu** — không kèm feature nào không liên quan.

## Luồng chuẩn

```text
1. DETECT            — monitoring/triage đánh P0/P1 (doc/release/monitoring.md Part 2)
2. EVIDENCE          — thu: report gốc, screenshot/log, version/build, device/OS,
                       bước repro, tần suất. Issue template đầy đủ, status = investigating
3. REPRODUCE         — trên máy dev/canary; nếu không repro được → thu thêm evidence,
                       KHÔNG fix mò. Data-related → COPY dữ liệu user (xem P9.7)
4. ROOT CAUSE        — xác định đúng cơ chế (code path, migration, platform); ghi vào issue
5. MINIMAL FIX       — diff nhỏ nhất sửa đúng root cause; KHÔNG refactor, KHÔNG feature
                       kèm theo (cả "nhân tiện"). Freeze vẫn hiệu lực — chỉ P0/P1
6. REGRESSION TEST   — 1 test tái hiện bug (đỏ trước fix, xanh sau fix) + full suite
                       `flutter analyze --no-pub` + `flutter test test/` phải 100% xanh
7. RELEASE BUILD     — bump build number (version giữ nguyên trừ khi đổi scope);
                       signed build theo doc/release/build_notes.md; ghi submission_record
8. EMERGENCY RELEASE — track store phù hợp (Play: production halt + submit hotfix;
                       iOS: expedited review nếu đủ tiêu chí). KHÔNG rebuild lén build cũ
9. MONITOR           — quay lại doc/release/monitoring.md; xác nhận tín hiệu đỏ hết
                       trước khi tiếp tục staged rollout (staged_launch.md §2)
10. CLOSE            — issue → released/closed; ghi hotfix vào result_p9_launch.md
```

## Quy tắc cứng

- **NEVER** hotfix + feature không liên quan (kể cả "dịp này có sẵn diff rồi")
- **NEVER** ship hotfix từ cây source khác revision đã ghi (no undocumented diff)
- **NEVER** bỏ bước regression test vì "gấp" — chính là cách tạo P0 thứ hai
- Mọi hotfix phải tăng build number và có record riêng trong `doc/release/submission_record.md`
- Nếu hotfix chạm data path → thực hiện thêm P9.7 (data-loss procedure) và verify backup/restore trước release

## Định nghĩa xong hotfix

Tín hiệu đỏ biến mất trên monitoring + full suite xanh + record đầy đủ → đóng issue; sau đó mới xét tiếp tục rollout.

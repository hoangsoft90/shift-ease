# P9.2 — Production Submission Record (template — điền khi human submit)

> Nguồn: `phases/P9_production_launch.md` §2 · `plan_p9.md` §P9.2.
> **Quy tắc D-P9.3:** submit **đúng** artifact đã validate/freeze — KHÔNG rebuild lén sau final QA. Nếu buộc phải rebuild (bump build number, fix P0/P1), phải ghi đè dòng cũ + lý do + diff source revision.

## 1. Record — Android (Play Store)

| Trường | Giá trị |
|---|---|
| Source revision (git SHA) | ____________________ |
| Version / build | 1.0.0+___ (từ `pubspec.yaml` — phải khớp `versionName`/`versionCode` trong artifact) |
| Artifact | ☐ AAB (preferred) / ☐ APK QA |
| Artifact filename | ____________________ |
| Checksum (SHA-256) | `sha256sum <artifact>` → ____________________ |
| Build date | ____________________ |
| Submission date | ____________________ |
| Platform / store track | Play Store — ☐ internal ☐ closed ☐ **production (staged %)** |
| Signed by | ____________________ (keystore alias — KHÔNG ghi password) |
| CI run xanh của commit này | link ____________________ (bắt buộc — `test.yml` green) |
| Người submit | ____________________ |

## 2. Record — iOS (App Store)

| Trường | Giá trị |
|---|---|
| Source revision (git SHA) | ____________________ |
| Version / build | 1.0.0+___ (CFBundleShortVersionString/CFBundleVersion) |
| Artifact | ☐ IPA (App Store archive) |
| Checksum (SHA-256) | ____________________ |
| Submission date | ____________________ |
| Store track | TestFlight → App Review → ☐ phased release |
| Người submit | ____________________ |

## 3. Checklist trước khi submit (mỗi dòng phải tick với evidence)

- [ ] CI green trên đúng source revision này (link ở §1)
- [ ] Artifact build từ revision đã ghi; **zero** source/config diff sau final QA
- [ ] `doc/release/final_release_gate.md` = GATE OPEN
- [ ] Policy URL công khai (hosted) + support email thật
- [ ] Data safety form (Play) / Privacy nutrition (App Store) khớp `doc/release/privacy.md` §1
- [ ] Store listing khớp `doc/release/store_assets.md` (không quảng cáo feature chưa ship)
- [ ] `sha256sum` artifact đã ghi ở §1/§2 (checksum này được so lại sau khi store nhận file)

## 4. Sau khi store nhận

- So checksum artifact trên store console (nếu hiển thị) với §1/§2 — lệch = dừng, điều tra trước khi rollout
- Ghi link release trên store console vào record
- Chuyển sang `doc/release/staged_launch.md`

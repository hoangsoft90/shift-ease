# ShiftEase --- P8 Release Preparation / Closed Testing

## 0. Mục tiêu

P8 chỉ bắt đầu sau khi P7 PASS.

Mục tiêu:

-   tạo release artifacts chính thức
-   cấu hình signing
-   kiểm tra release configuration
-   hoàn thiện store metadata/assets
-   chạy internal testing
-   chạy closed testing
-   kiểm tra upgrade từ RC
-   sửa blocker thực tế nếu phát hiện

**Không thêm feature lớn.**

------------------------------------------------------------------------

# 1. P8.1 --- Freeze feature scope

Trước khi build release candidate:

-   freeze domain model
-   freeze database schema
-   freeze import pipeline
-   freeze pay engine
-   freeze notification behavior
-   freeze backup format
-   freeze encryption approach

Chỉ nhận:

-   P0/P1 bug
-   P2 bug có ảnh hưởng release
-   store compliance issue
-   crash
-   data integrity issue
-   security issue

Không nhận feature request mới vào release candidate.

------------------------------------------------------------------------

# 2. P8.2 --- Version/build configuration

Verify:

-   application name: ShiftEase
-   Android application ID
-   iOS bundle identifier
-   version
-   build number
-   release mode
-   production configuration
-   no debug flags
-   no test data
-   no development endpoint
-   no mock services enabled accidentally

Version/build must be consistent across Android/iOS release artifacts.

------------------------------------------------------------------------

# 3. P8.3 --- Android release build

Build signed Android release artifact.

Preferred distribution artifact:

``` text
AAB
```

Also create APK if needed for direct device QA.

Verify:

-   install
-   launch
-   fresh install
-   upgrade from previous RC
-   database opens
-   encrypted DB opens
-   notification permission flow
-   backup/restore
-   no debug UI
-   no debug logging

Run release build on at least one physical Android device.

------------------------------------------------------------------------

# 4. P8.4 --- iOS release build

Create signed release/archive build.

Verify:

-   install
-   launch
-   fresh install
-   upgrade
-   encrypted DB
-   Keychain
-   notification
-   backup/restore
-   no debug UI
-   no development configuration

Run on physical iOS device.

------------------------------------------------------------------------

# 5. P8.5 --- Release smoke test

Clean-device flow:

``` text
Install
→ launch
→ create job
→ create shift
→ create overnight shift
→ create recurring pattern
→ edit occurrence
→ delete occurrence
→ import roster
→ review
→ commit
→ CSV re-import
→ review diff
→ calculate income
→ switch jobs
→ enable notification
→ restart
→ backup
→ restore
```

Expected:

-   no crash
-   no data loss
-   no incorrect duration
-   no incorrect income
-   no stale notification

------------------------------------------------------------------------

# 6. P8.6 --- Upgrade test

Install previous supported release.

Create realistic data.

Upgrade to release candidate.

Verify:

-   data remains
-   overrides remain
-   imported roster remains
-   PayRules remain
-   settings remain
-   encryption remains
-   notifications remain valid

Test at least:

``` text
previous RC → release candidate
```

If multiple schema versions are supported, P7 migration matrix remains
authoritative.

------------------------------------------------------------------------

# 7. P8.7 --- Store assets

Prepare:

-   app icon
-   screenshots
-   app description
-   short description
-   feature highlights
-   support contact/page
-   privacy information
-   appropriate category
-   age/content rating

Screenshots must represent the actual release UI.

Do not advertise deferred features such as:

-   OCR
-   cloud sync
-   AI
-   family sharing

unless they are actually present.

------------------------------------------------------------------------

# 8. P8.8 --- Privacy / policy

Verify store-required disclosures for actual behavior.

Review:

-   local database
-   encryption
-   notifications
-   backup/export
-   any analytics/crash reporting
-   permissions
-   personal data handling

Do not claim "no data collected" unless it is true for the final release
configuration.

------------------------------------------------------------------------

# 9. P8.9 --- Internal testing

Distribute release candidate internally.

Test:

-   fresh install
-   upgrade
-   notification
-   backup/restore
-   DST
-   import/re-import
-   income
-   multiple jobs
-   offline behavior

Collect issues.

Every issue must have severity:

-   P0
-   P1
-   P2
-   P3

P0/P1 return to implementation before continuing.

------------------------------------------------------------------------

# 10. P8.10 --- Closed testing

After internal testing passes:

``` text
Internal testing
→ fix
→ rebuild
→ internal PASS
→ closed testing
```

Use a small real-user cohort.

Focus feedback on:

-   onboarding
-   ease of adding shifts
-   calendar clarity
-   import workflow
-   income clarity
-   notification reliability
-   backup/restore confidence
-   crashes
-   confusing wording

Do not use closed testing as an excuse to add feature bloat.

------------------------------------------------------------------------

# 11. P8.11 --- Release candidate freeze

When closed testing is stable:

-   freeze code
-   record source revision
-   generate final analyze/test report
-   generate Android release artifact
-   generate iOS release artifact
-   verify store metadata
-   verify privacy disclosures
-   verify screenshots
-   verify version/build numbers

------------------------------------------------------------------------

# 12. Required evidence

Create:

`result_p8_release_candidate.md`

Include:

-   source revision
-   version/build
-   Android artifact
-   iOS artifact
-   release configuration checks
-   clean install result
-   upgrade result
-   internal testing result
-   closed testing result
-   store validation result
-   known issues
-   final blocker status

------------------------------------------------------------------------

# 13. P8 Definition of Done

-   [ ] P7 PASS
-   [ ] release config clean
-   [ ] Android signed release build PASS
-   [ ] iOS signed release build PASS
-   [ ] fresh install PASS
-   [ ] upgrade PASS
-   [ ] release smoke test PASS
-   [ ] store assets complete
-   [ ] privacy/policy declarations verified
-   [ ] internal testing PASS
-   [ ] closed testing PASS
-   [ ] no P0/P1 issues
-   [ ] final RC frozen

Only then proceed to P9.

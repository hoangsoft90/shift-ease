# ShiftEase --- P9 Production Launch / Post-release Monitoring

## 0. Mục tiêu

P9 là phase phát hành thật và kiểm soát rủi ro sau phát hành.

P9 không phải phase phát triển feature mới.

Ưu tiên:

1.  data integrity
2.  crash-free operation
3.  correct time calculation
4.  correct income calculation
5.  notification reliability
6.  backup/restore
7.  user-facing UX bugs

------------------------------------------------------------------------

# 1. P9.1 --- Final release gate

Before production submission, verify:

``` text
P0 PASS
P1 PASS
P2 PASS
P3 PASS
P4 PASS
P5 PASS
P6 PASS
P7 PASS
P8 PASS
```

No:

-   P0
-   P1
-   known data-loss path
-   known migration-loss path
-   known major time-calculation error
-   known major income-calculation error
-   known encryption failure

------------------------------------------------------------------------

# 2. P9.2 --- Production submission

Submit the exact artifacts validated in P8.

Do not rebuild with undocumented source/config changes after final QA.

Record:

-   source revision
-   version
-   build number
-   artifact checksum if practical
-   submission date
-   platform
-   store release track

------------------------------------------------------------------------

# 3. P9.3 --- Staged launch

If store/platform capability permits:

``` text
small production exposure
→ monitor
→ increase exposure
→ full release
```

Do not immediately combine launch with unrelated feature changes.

------------------------------------------------------------------------

# 4. P9.4 --- Production monitoring

Monitor at minimum:

### Stability

-   crash rate
-   startup failure
-   fatal exceptions
-   database open failures

### Data

-   migration failures
-   restore failures
-   backup failures
-   corruption reports
-   missing shift reports

### Time

-   DST-related failures
-   timezone-related reports
-   incorrect overnight duration

### Income

-   incorrect income complaints
-   UNAVAILABLE calculation reports
-   PayRule version issues

### Notification

-   permission failures
-   stale notifications
-   duplicate notifications
-   missing notifications

------------------------------------------------------------------------

# 5. P9.5 --- User feedback triage

Every production issue receives:

-   severity
-   reproducibility
-   affected platform
-   affected version/build
-   affected feature
-   data-loss risk
-   workaround
-   owner
-   status

Priority:

``` text
P0 → immediate emergency response
P1 → urgent fix
P2 → scheduled
P3 → backlog
```

------------------------------------------------------------------------

# 6. P9.6 --- P0/P1 hotfix procedure

Use:

``` text
Detect
 ↓
Collect evidence
 ↓
Reproduce
 ↓
Identify root cause
 ↓
Minimal fix
 ↓
Regression test
 ↓
Release build
 ↓
Emergency release
 ↓
Monitor
```

Hotfix must not include unrelated feature changes.

------------------------------------------------------------------------

# 7. P9.7 --- Data-loss incident procedure

If users report missing/corrupt data:

1.  stop unrelated releases
2.  reproduce on a copy
3.  identify affected versions
4.  identify migration/restore/write path
5.  preserve evidence
6.  create regression test
7.  implement minimal fix
8.  verify backup/restore
9.  release hotfix
10. document incident

Never ask users to delete their database as a first response.

------------------------------------------------------------------------

# 8. P9.8 --- First production review

After an initial stable period, review:

-   crash-free sessions/users
-   startup reliability
-   notification reliability
-   backup/restore success
-   most common UX complaints
-   import/re-import failures
-   income calculation issues
-   device/OS compatibility issues

Only then decide the next product phase.

------------------------------------------------------------------------

# 9. P9.9 --- Post-production feature backlog

Possible future features, only after production is stable:

-   OCR roster import
-   cloud sync
-   account system
-   sharing
-   family/partner overlay
-   widgets
-   shift change detection
-   wellness rules
-   advanced AI
-   B2B/payroll integrations

These are NOT P9 release blockers.

------------------------------------------------------------------------

# 10. Required evidence

Create:

`result_p9_launch.md`

Include:

-   production version/build
-   platform release status
-   launch date
-   rollout strategy
-   monitoring setup
-   first production issues
-   P0/P1/P2/P3 counts
-   crash/stability observations
-   notification observations
-   data integrity observations
-   hotfixes if any
-   final launch status

------------------------------------------------------------------------

# 11. P9 Definition of Done

P9 is complete when:

-   [ ] production release is live
-   [ ] monitoring is active
-   [ ] no unresolved P0/P1 issue
-   [ ] no known active data-loss incident
-   [ ] no known critical migration issue
-   [ ] notification behavior is stable
-   [ ] time calculation is stable
-   [ ] income calculation is stable
-   [ ] backup/restore reports are healthy
-   [ ] first production review completed
-   [ ] next feature roadmap is separated from hotfix work

At this point ShiftEase is considered **Production**.

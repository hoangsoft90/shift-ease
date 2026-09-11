# ShiftEase --- Production Roadmap Review / Agent Handoff

## 1. Kết luận

Current phase: **P7 --- Production Verification / Security / Real
Devices**.

The roadmap has 10 phases total:

``` text
P0 Foundation / Core Engines                         DONE
P1 Calendar / Pattern / Override                     DONE
P2 Today / Month / Quick Add / Versioning           DONE
P3 Smart Import / Review / Commit                    DONE
P4 CSV / Re-import / Diff                            DONE
P5 Income / Pay / Multi-job                          DONE
P6 RC Integrity / Reliability / Regression           DONE
P7 Production Verification / Security / Real Devices CURRENT
P8 Release Preparation / Closed Testing              TODO
P9 Production Launch / Post-release Monitoring       TODO
```

The app is **not yet safe to publish**.

------------------------------------------------------------------------

## 2. Evidence reviewed

Current project evidence includes:

-   `production_roadmap.md`
-   `next.md`
-   `result16_rc.txt`
-   `result17_review_rc.txt`
-   `result18_code_review_rc.txt`
-   latest handoff
-   current `.plan/` directory

Latest RC verification:

``` text
flutter analyze --no-pub
PASS

flutter test test/
292/292 PASS
```

The latest code review says the RC code is generally sound, but
identified one HIGH production blocker and one MEDIUM correctness issue.
L1/L2/L3 were already fixed.

------------------------------------------------------------------------

## 3. Findings that must not be forgotten

### H1 --- HIGH --- Backup path

Production backup must not default to `Directory.systemTemp`.

Reason:

-   OS may purge cache/temp data.
-   Backup is a data-safety feature.
-   Production wiring must resolve an app-private persistent directory.

This belongs in P7.1.

### M1 --- MEDIUM --- Income Impact

Do not silently drop an unresolvable prospective row.

Correct behavior:

``` text
any row cannot resolve
→ IncomeImpact.UNAVAILABLE
→ reason
```

This belongs in P7.1.

### M2 --- MEDIUM --- iOS notification status

Can be handled during P7 device work.

If exact status cannot be determined:

``` text
Unknown
```

is acceptable.

Never guess.

### L4 --- LOW --- 13-day reminder window

Acceptable if explicitly documented and resume/reload resync is correct.

Do not enlarge scope unless real users demonstrate need.

------------------------------------------------------------------------

## 4. What the agent should NOT do now

Do not start:

-   OCR
-   Cloud Sync
-   AI
-   family sharing
-   B2B
-   payroll
-   tax/net-pay
-   complex calendar sharing
-   unrelated UI redesign

These are post-production backlog items.

The highest risk is now not feature completeness. It is proving that
existing features behave correctly on real Android/iOS devices.

------------------------------------------------------------------------

## 5. Execution order

Agent should execute strictly:

``` text
P7.1 RC blockers
  ↓
P7.2 SQLCipher
  ↓
P7.3/P7.4 secure key storage
  ↓
P7.5 Android notifications
  ↓
P7.6 iOS notifications
  ↓
P7.7 lifecycle
  ↓
P7.8 migration
  ↓
P7.9 backup/restore
  ↓
P7.10 DST/timezone
  ↓
P7.11 security
  ↓
P7.12 final regression/evidence
  ↓
P8 release preparation
  ↓
P8 internal testing
  ↓
P8 closed testing
  ↓
P9 production launch
```

Do not skip directly to P8 while P7 has unverified security/device
gates.

------------------------------------------------------------------------

## 6. Agent working rules

Before coding:

1.  Read this plan.
2.  Read `production_roadmap.md`.
3.  Read the latest `next.md`.
4.  Read the latest result/handoff.
5.  Inspect the current source; do not trust old result files as proof.

During coding:

-   preserve invariants INVARIANT-001..008
-   preserve append-only override semantics
-   preserve UTC-based duration
-   never silently estimate income
-   never silently mutate historical data
-   never commit unreviewed imports
-   never use plaintext encryption keys
-   never claim a platform test PASS without actually running it

After coding:

``` text
flutter analyze --no-pub
flutter test test/
```

Then update evidence.

------------------------------------------------------------------------

## 7. Final production standard

A clean device must be able to perform:

``` text
Install
→ Create job
→ Create shift
→ Overnight shift
→ Recurring pattern
→ Edit occurrence
→ Import
→ Review
→ Commit
→ CSV re-import
→ Review diff
→ Income
→ Multi-job
→ Notification
→ Restart
→ Backup
→ Restore
→ Upgrade
→ Verify data
```

without:

-   crash
-   data loss
-   unexpected mutation
-   wrong duration
-   wrong DST behavior
-   wrong income
-   stale notification
-   corrupted DB
-   unsafe restore

Only then declare:

``` text
PRODUCTION READY
```

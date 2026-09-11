# ShiftEase — Production Roadmap

> **Purpose:** Source-of-truth roadmap for completing ShiftEase before first public production release.
>
> **Current status:** Release Candidate / Production Verification.
>
> **Rule:** Do not add major new features before completing all production gates below.
> Priority is correctness, data safety, reliability, security, mobile compatibility, and ease of use.

---

# 1. Production Goal

ShiftEase is considered **Production Ready** only when all phases below are completed and all mandatory acceptance gates are PASS.

Production release must provide:

* Reliable shift/calendar management
* Correct time calculation
* Correct overnight/DST handling
* Safe manual overrides
* Import/re-import with review before commit
* Multi-job support
* Income/pay estimation
* Backup/restore
* Data integrity protection
* Local/offline-first operation
* Secure database storage
* Reliable notifications
* Android and iOS real-device verification
* Migration safety
* Clean release build
* No known P0/P1 defects

---

# 2. Phase Overview

| Phase  | Name                                                  | Status      |
| ------ | ----------------------------------------------------- | ----------- |
| P0     | Foundation / Core Engines                             | DONE        |
| P1     | Calendar / Pattern / Override                         | DONE        |
| P2     | Today / Month / Quick Add / Roster Versioning         | DONE        |
| P3     | Smart Import / Review / Commit                        | DONE        |
| P4     | CSV / Re-import / Diff                                | DONE        |
| P5     | Income / Pay / Multi-job                              | DONE        |
| P6     | RC Integrity / Reliability / Regression               | DONE        |
| **P7** | **Production Verification / Security / Real Devices** | **CURRENT** |
| P8     | Release Preparation / Closed Testing                  | TODO        |
| P9     | Production Launch / Post-release Monitoring           | TODO        |

**Total: 10 phases (P0–P9).**

P0–P6 are implementation phases already substantially completed.

The project is currently in **P7**.

---

# 3. P0 — Foundation / Core Engines

## Objective

Build deterministic core logic that does not depend on UI.

## Required

### Time Engine

* Correct local date/time handling
* Shift start/end
* Overnight shifts
* Duration calculation
* Cross-midnight calculation
* DST-safe time handling
* Ambiguous DST time support
* Nonexistent DST time rejection
* Stable instant representation

### Pattern Engine

* Recurring shift patterns
* Pattern expansion
* Date-specific occurrence generation
* Correct handling of pattern changes

### Money / Pay Engine

* Hourly pay
* Pay rules
* Overtime
* Multiple rule versions
* Deterministic calculation
* Correct rounding
* Correct handling of missing/inapplicable rules

### Database foundation

* Stable schema
* Migrations
* Transaction support
* Referential integrity

## Acceptance Gate

* Core unit tests PASS
* Time calculations deterministic
* Overnight tests PASS
* DST tests PASS
* Pay engine tests PASS
* No data corruption scenarios identified

**Status: DONE**

---

# 4. P1 — Calendar / Pattern / Override

## Objective

Allow users to manage real shifts manually.

## Required

* Today view
* Calendar view
* Shift creation
* Shift editing
* Shift deletion
* Pattern-based shifts
* One-off shifts
* Manual override
* Override identity stability
* Correct occurrence/materialization semantics
* Imported roster support
* No accidental modification of source pattern

## Data Safety

* Delete must not silently alter unrelated occurrences
* Editing an occurrence must preserve override identity
* Pattern changes must not unexpectedly destroy overrides
* User changes must survive app restart

## Acceptance Gate

* CRUD tests PASS
* Override tests PASS
* Restart persistence PASS
* Pattern/revision tests PASS

**Status: DONE**

---

# 5. P2 — Today / Month / Quick Add / Roster Versioning

## Objective

Make everyday shift management fast and predictable.

## Required

### Today

* Current-day shifts
* Shift status
* Hours
* Income summary where applicable

### Month

* Monthly calendar
* Shift indicators
* Correct navigation
* Correct month boundaries

### Quick Add

* Fast shift creation
* Validation
* Overnight support
* Correct default values

### Roster re-versioning

* Imported roster can be replaced safely
* Existing overrides remain stable
* Old roster versions do not silently mutate historical overrides
* New version becomes effective only where intended

## Acceptance Gate

* UI tests PASS
* Roster replacement tests PASS
* Historical data remains intact

**Status: DONE**

---

# 6. P3 — Smart Import / Review / Commit

## Objective

Never allow uncertain imported data to silently overwrite user data.

## Required Pipeline

```text
Input
  ↓
Parse
  ↓
Normalize
  ↓
Validate
  ↓
Preview
  ↓
Review
  ↓
Commit
```

## Required

* Text import
* Import normalization
* Date parsing
* Shift type parsing
* Start/end parsing
* Validation
* Conflict detection
* Review UI
* Imported-only job creation
* Safe commit
* Import session/audit information

## Data Safety Rules

* Preview must not persist data
* Invalid records must not silently commit
* Conflicts must be visible
* Commit must be atomic
* Failed commit must not leave partial state

## Acceptance Gate

* Import tests PASS
* Invalid input tests PASS
* Conflict tests PASS
* Rollback tests PASS
* Imported-only job tests PASS

**Status: DONE**

---

# 7. P4 — CSV / Re-import / Diff

## Objective

Allow users to update imported schedules safely.

## Required

* CSV import
* Column mapping
* Preview
* Validation
* Review
* Commit
* Re-import
* Stable record identity
* Diff calculation

## Diff Categories

* Added
* Removed
* Modified
* Unchanged

## Modified Details

Show:

* Old value
* New value
* Hours delta
* Income impact where calculable

## Safety

* Preview must use `persist=false`
* Re-import must not blindly replace user overrides
* Removed records must be clearly identified
* Modified records require deterministic comparison

## Acceptance Gate

* CSV tests PASS
* Re-import tests PASS
* Diff tests PASS
* No unintended data deletion

**Status: DONE**

---

# 8. P5 — Income / Pay / Multi-job

## Objective

Provide a trustworthy income estimate without pretending to be payroll software.

## Required

### Multi-job

* Multiple jobs
* Job-specific PayRule
* Job-specific shifts
* Job switching/filtering

### Pay Engine

* Regular hours
* Overtime
* Daily/shift/week rules
* Multiple PayRule versions
* Effective dates
* Overnight shifts
* DST
* Correct rounding

### Income

* Daily income
* Weekly income
* Monthly income
* Income breakdown
* Hours breakdown
* Job breakdown
* Pay-rule breakdown

### Critical rule

PayRule must be resolved **per occurrence**, not by taking the first rule of a week/month and applying it globally.

### Ambiguous result

When income cannot be calculated reliably:

```text
UNAVAILABLE
```

Do not invent an estimate.

### Income Impact

For changes/imports:

```text
Old income
New income
Delta
```

## Acceptance Gate

* Pay engine tests PASS
* Multi-job tests PASS
* PayRule version tests PASS
* Weekly/monthly tests PASS
* Overnight tests PASS
* DST tests PASS
* Income impact tests PASS

**Status: DONE**

---

# 9. P6 — Release Candidate Integrity / Reliability

## Objective

Harden the completed product before device testing.

## Required

### Data Integrity

* UI write error boundaries
* Transactional writes
* Atomic operations
* Rollback on failure
* Referential integrity
* Safe deletion
* Safe replacement

### Backup

* Full backup
* Schema/version metadata
* Checksum
* Validation before restore
* Transactional restore
* Rollback on failed restore
* Post-restore verification

### Delete All Data

* Explicit confirmation
* Atomic deletion
* No orphaned records
* Correct empty-state after deletion

### Settings

* General
* Notifications
* Data
* Backup/Restore
* Privacy/Security
* About

### Notifications

* Schedule
* Update
* Cancel
* Stale reminder cleanup
* Resume/reload scheduling

### Regression

* Core tests
* Feature tests
* UI tests
* Database tests
* Adversarial tests

## Acceptance Gate

Current expected baseline:

```text
flutter analyze --no-pub
→ PASS

flutter test test/
→ 288/288 PASS
```

No P0/P1 regression.

**Status: DONE**

---

# 10. P7 — Production Verification / Security / Real Devices

> **CURRENT PHASE**

## Objective

Convert a code-complete RC into a genuinely production-ready mobile application.

No major product features should be added during this phase.

---

## P7.1 — Real SQLCipher Integration

### Required

Replace/prove the current encryption seam with actual production database encryption.

Verify:

* Real SQLCipher native implementation
* Android database encryption
* iOS database encryption
* Secure key generation
* Secure key storage
* Key retrieval after restart
* Wrong-key rejection
* Encrypted DB reopen
* Migration of encrypted DB
* Backup of encrypted DB
* Restore of encrypted DB

### Mandatory Security Test

Opening the DB as ordinary/plain SQLite must not expose readable application data.

### Acceptance

```text
Fresh install
→ encrypted DB

Restart
→ encrypted DB opens

Wrong key
→ rejected

Migration
→ data intact

Backup
→ valid

Restore
→ data intact
```

**Gate: MUST PASS**

---

# 11. P7.2 — Secure Key Storage

## Android

Verify production use of Android secure storage / Keystore-backed mechanism.

## iOS

Verify Keychain-backed storage.

## Required

* No hard-coded encryption key
* No plaintext persistent key
* Key survives normal app restart
* Correct behavior after reinstall according to defined data policy
* Correct behavior when secure storage is unavailable

**Gate: MUST PASS**

---

# 12. P7.3 — Android Notification Verification

Test on a real Android device.

## Required

* Android 13+
* Permission request
* Permission granted
* Permission denied
* Permanently denied
* Settings fallback
* Schedule reminder
* Update reminder
* Cancel reminder
* Delete shift → reminder cancelled
* Edit shift → reminder updated
* App restart
* App background
* App resume
* Device reboot where applicable

## Acceptance

No stale notification may remain after deleting/updating a shift.

**Gate: MUST PASS**

---

# 13. P7.4 — iOS Notification Verification

Test on a real iOS device.

## Required

* Permission request
* Permission denied
* Permission granted
* Schedule
* Update
* Cancel
* App restart
* Background
* Resume
* Timezone change
* DST transition

**Gate: MUST PASS**

---

# 14. P7.5 — Mobile Lifecycle Verification

Verify:

```text
Launch
 ↓
Foreground
 ↓
Background
 ↓
Resume
 ↓
Force Kill
 ↓
Reopen
```

Repeat while performing:

* Add shift
* Edit shift
* Delete shift
* Import
* Re-import
* Override
* Roster replacement
* Backup
* Restore

## Acceptance

No:

* crash
* duplicate records
* lost records
* stale reminder
* incorrect calculation
* corrupted state

**Gate: MUST PASS**

---

# 15. P7.6 — Database Migration Verification

Test upgrades from every supported previous schema version.

## Required

```text
Old DB
 ↓
Install new app
 ↓
Migration
 ↓
Verify records
 ↓
Verify overrides
 ↓
Verify pay rules
 ↓
Verify jobs
 ↓
Verify settings
```

Also test:

* Migration failure
* Interrupted migration
* Reopen after migration
* Encrypted database migration

## Acceptance

Zero unintended data loss.

**Gate: MUST PASS**

---

# 16. P7.7 — Backup / Restore Real-device Test

Do not rely only on unit tests.

Test:

```text
Device A
 ↓
Create realistic dataset
 ↓
Backup
 ↓
Restore
 ↓
Restart
 ↓
Verify everything
```

Verify:

* Jobs
* Shifts
* Patterns
* Overrides
* PayRules
* Income
* Settings
* Import history where applicable

Also test corrupted backup.

## Acceptance

Corrupted backup must fail safely without destroying existing data.

**Gate: MUST PASS**

---

# 17. P7.8 — DST / Timezone Real-device Test

Test:

### Spring Forward

* Nonexistent local time
* Validation
* User-facing error

### Fall Back

* Ambiguous local time
* User chooses interpretation
* Offset/instant preserved
* Restart preserves interpretation

### Timezone

* Change device timezone
* Reopen app
* Verify existing shifts
* Verify reminders
* Verify income

**Gate: MUST PASS**

---

# 18. P7.9 — Full Regression

Run after all P7 changes.

```text
flutter analyze --no-pub
flutter test test/
```

Then:

* Android debug smoke
* Android release build
* iOS debug smoke
* iOS release build
* Real-device tests

## Required

No new regression.

All test/evidence reports must correspond to the final source tree.

**Gate: MUST PASS**

---

# 19. P7.10 — Final Security Review

Review:

* Secrets
* API keys
* Encryption key handling
* Logs
* Debug logging
* Backup contents
* Local DB
* Temporary files
* Export files
* Clipboard exposure
* Sensitive information in crash logs

Remove production debug behavior.

**Gate: MUST PASS**

---

# 20. P7 Exit Criteria

P7 is complete only when ALL are true:

* [ ] SQLCipher actually verified
* [ ] Secure key storage verified
* [ ] Android notification verified
* [ ] iOS notification verified
* [ ] Android real-device smoke test PASS
* [ ] iOS real-device smoke test PASS
* [ ] Lifecycle tests PASS
* [ ] Migration tests PASS
* [ ] Backup/restore real-device test PASS
* [ ] DST/timezone tests PASS
* [ ] Final regression PASS
* [ ] No P0/P1 bugs
* [ ] Final evidence generated from final source tree

**Current status: NOT COMPLETE**

---

# 21. P8 — Release Preparation / Closed Testing

## Objective

Prepare the verified application for controlled public testing.

### Release Build

* Android release build
* iOS release archive
* Production signing
* Correct application ID/bundle ID
* Version number
* Build number
* Release configuration
* No debug flags
* No development endpoints

### Store Assets

* App icon
* Screenshots
* App description
* Short description
* Feature highlights
* Privacy information
* Support information

### Legal / Policy

* Privacy Policy
* Terms where required
* Data handling disclosure
* Notification disclosure where applicable
* Encryption disclosure where applicable

### Store Configuration

* Android Play Console
* iOS App Store Connect
* Required app categories
* Age rating
* Content declarations
* Data safety/privacy forms

### Testing

Release first to:

```text
Internal testing
        ↓
Closed testing
        ↓
Fix real-world issues
        ↓
Final candidate
```

## Acceptance Gate

* Release build installs successfully
* Existing data survives upgrade
* Fresh install works
* Core flows work
* No blocker crash
* Store validation passes

**Status: TODO**

---

# 22. P9 — Production Launch / Post-release Monitoring

## Objective

Publish safely and monitor the first production users.

### Launch

* Production release
* Monitor crash reports
* Monitor startup failures
* Monitor notification failures
* Monitor database/migration errors
* Monitor restore failures
* Monitor user-reported data problems

### Hotfix policy

P0/P1 production issues:

```text
Detect
 ↓
Reproduce
 ↓
Fix
 ↓
Regression
 ↓
Emergency release
```

Do not introduce unrelated features in a hotfix.

### First-release priorities

1. Data integrity
2. Crash-free operation
3. Correct time calculation
4. Correct income calculation
5. Reliable notifications
6. Backup/restore
7. UX issues
8. Minor enhancements

**Status: TODO**

---

# 23. Features Explicitly Deferred Until After Production

Do NOT block first release on these unless product strategy changes.

## OCR

* Image roster OCR
* PDF OCR
* OCR confidence
* OCR re-import diff

## Cloud

* Cloud sync
* Multi-device sync
* Account system
* Cloud backup

## Sharing

* Partner/family sharing
* Shared calendars
* Availability finder
* Webcal dynamic sharing

## Advanced Intelligence

* AI health features
* AI schedule analysis
* Automatic schedule prediction

## Business Features

* B2B
* Payroll integration
* Tax/net-pay engine
* Employer integrations

These belong to a future post-production roadmap.

---

# 24. Production Bug Severity

## P0 — Release Blocker

Examples:

* Data loss
* Database corruption
* Incorrect financial calculation that materially misleads users
* App cannot start
* Encryption failure
* Migration destroys data
* Restore destroys existing data

**Must fix before release.**

## P1 — Release Blocker

Examples:

* Major workflow unusable
* Import corrupts data
* Notifications fundamentally broken
* Android/iOS release build crashes
* Major shift calculation error

**Must fix before release.**

## P2 — Important

Examples:

* Significant UX problem
* Minor calculation edge case with workaround
* Non-critical notification issue

Can potentially defer only with explicit decision.

## P3 — Nice to Have

Examples:

* UI polish
* Small convenience improvements
* Non-essential feature requests

Do not delay first production release.

---

# 25. Final Production Gate

ShiftEase may be declared:

```text
PRODUCTION READY
```

only if:

```text
P0  Foundation                         PASS
P1  Calendar / Pattern / Override      PASS
P2  Today / Quick Add / Versioning     PASS
P3  Import                              PASS
P4  CSV / Re-import                     PASS
P5  Income / Multi-job                  PASS
P6  RC Integrity                        PASS
P7  Security + Real Devices             PASS
P8  Release Preparation                PASS
P9  Launch                              PASS
```

AND:

```text
No P0 bugs
No P1 bugs
No known data-loss path
No known migration-loss path
No known incorrect financial calculation
Android release build PASS
iOS release build PASS
Backup/restore PASS
SQLCipher PASS
Notification PASS
Final regression PASS
```

---

# 26. Current Position

```text
P0  ██████████ DONE
P1  ██████████ DONE
P2  ██████████ DONE
P3  ██████████ DONE
P4  ██████████ DONE
P5  ██████████ DONE
P6  ██████████ DONE
P7  ███░░░░░░░ IN PROGRESS
P8  ░░░░░░░░░░ TODO
P9  ░░░░░░░░░░ TODO
```

### Current phase

**P7 — Production Verification / Security / Real Devices**

### Immediate next work

1. Finish real SQLCipher integration/verification
2. Verify secure key storage
3. Android real-device notification test
4. iOS real-device notification test
5. Mobile lifecycle test
6. Migration test
7. Real-device backup/restore
8. DST/timezone verification
9. Final regression
10. Generate final release evidence

**Do not start OCR, AI, Cloud Sync, Sharing, or other major features before P7 is closed.**

---

# 27. Definition of Done

The project is ready to publish when a reviewer can take a clean device and:

```text
Install
 ↓
Create job
 ↓
Create shift
 ↓
Create overnight shift
 ↓
Create recurring pattern
 ↓
Edit occurrence
 ↓
Import roster
 ↓
Review import
 ↓
Commit import
 ↓
Re-import CSV
 ↓
Review diff
 ↓
Calculate income
 ↓
Switch jobs
 ↓
Edit shift
 ↓
Receive notification
 ↓
Restart app
 ↓
Backup
 ↓
Restore
 ↓
Upgrade app
 ↓
Verify data
```

without:

* crash
* data loss
* unexpected mutation
* incorrect shift duration
* incorrect DST behavior
* incorrect income calculation
* stale notification
* corrupted database
* unsafe restore

Only after this complete flow passes on the supported Android/iOS environments should ShiftEase move from **RC** to **Production**.

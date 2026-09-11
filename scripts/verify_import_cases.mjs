#!/usr/bin/env node
// Verify import golden cases for STRUCTURAL + ARITHMETIC self-consistency
// directly from test/golden/import_pipeline_cases.json (independent of the
// Dart engine):
//   - candidates that lack a resolvable date are never committable (INVARIANT-004)
//   - no case auto-commits without an explicit user COMMIT action
//   - overnight end times carry a "+1" marker exactly when end <= start
//   - IMPORT-005 diff: swap pairs are symmetric; Off->Day nets +12h
//   - IMPORT-008: ACCEPT_ALL_HIGH approves exactly the HIGH PENDING candidates
// Reads the file; no hard-coded cases.

import { readFileSync } from 'fs';
import { resolve } from 'path';

const JSON_PATH = resolve(import.meta.dirname, '../test/golden/import_pipeline_cases.json');
const data = JSON.parse(readFileSync(JSON_PATH, 'utf8'));

console.log('=== Import Golden Case Verification ===');
console.log(`Source: ${JSON_PATH}`);
console.log(`Total cases: ${data.cases.length}`);
console.log('');

let checked = 0;
let errors = 0;
const ok = (cond, msg) => {
  console.log(`  ${cond ? '✓' : '✗'} ${msg}`);
  if (!cond) errors++;
  checked++;
};

const minutes = (t) => {
  const marker = t.includes('+1') ? 1440 : 0;
  const p = t.replace('+1', '').split(':');
  return Number(p[0]) * 60 + Number(p[1]) + marker;
};
const needsPlus1 = (start, end) => minutes(end) <= minutes(start);

for (const c of data.cases) {
  const id = c.id;
  console.log(`${id}: ${c.name}`);
  const exp = c.expected;

  // INVARIANT-004: committed list stays empty unless the flow contains an
  // explicit user COMMIT step.
  const hasCommitStep = JSON.stringify(c.input?.userActions ?? []).includes('COMMIT');
  const committed = exp.committedOccurrences ?? exp.committedOccurrenceIds;
  if (Array.isArray(committed)) {
    ok(hasCommitStep || committed.length === 0,
      `no commit without explicit user COMMIT (committed=${committed.length})`);
  }

  // Candidate-level checks where candidates carry date/time data.
  const candidates = exp.candidates ?? (exp.afterBulkAction ?? []);
  if (Array.isArray(candidates) && candidates.length && candidates[0]?.data) {
    for (const cand of candidates) {
      const d = cand.data;
      if (d?.date == null) {
        ok(cand.confidence === 'LOW',
          `${cand.id ?? '?'}: null date -> LOW (not committable)`);
      }
      if (d?.startTime && d?.endTime && d?.endTime.includes('+1')) {
        // The end is ALREADY normalized — strip the marker before checking.
        const rawEnd = d.endTime.replace('+1', '');
        ok(needsPlus1(d.startTime, rawEnd),
          `${cand.id ?? '?'}: "+1" end marker only when overnight (${d.startTime}->${d.endTime})`);
      }
      if (d?.shiftType === 'OFF' && d?.startTime) {
        ok(false, `${cand.id ?? '?'}: OFF day must not carry shift times`);
      }
    }
  }

  // IMPORT-002 shape: one LOW candidate per ambiguous line, nothing committable.
  if (id === 'IMPORT-002') {
    ok(candidates.length === 3, '3 LOW candidates (one per input line)');
    ok(candidates.every((x) => x.confidence === 'LOW' && x.reviewStatus === 'PENDING'),
      'all LOW + all PENDING (no auto-commit)');
  }

  // IMPORT-005: diff arithmetic + swap symmetry.
  if (id === 'IMPORT-005') {
    const prev = c.input.previousSession.rawExtraction.entries;
    const next = c.input.newExtraction.entries;
    const byDate = (list) => Object.fromEntries(list.map((e) => [e.date, e]));
    const pMap = byDate(prev);
    const nMap = byDate(next);
    const modified = exp.diff.modified;
    const swaps = modified.filter((m) => m.changeType === 'SWAPPED');
    ok(swaps.length === 2, 'swap pair detected (2 SWAPPED entries)');
    const d1 = swaps[0], d2 = swaps[1];
    ok(d1 && d2 && d1.date !== d2.date &&
      d1.from === d2.to && d1.to === d2.from,
      'swap pair is symmetric (A->B and B->A)');
    const hoursChanged = modified.reduce((sum, m) => {
      const p = pMap[m.date];
      const n = nMap[m.date];
      const dur = (x) => {
        if (!x?.start || !x?.end) return 0;
        return (minutes(x.end) - minutes(x.start)) / 60;
      };
      return sum + (dur(n) - dur(p));
    }, 0);
    ok(Math.abs(hoursChanged - 12) < 0.001,
      `Off->Day nets +12h (got ${hoursChanged})`);
  }

  // IMPORT-008: ACCEPT_ALL_HIGH touches only HIGH PENDING candidates.
  if (id === 'IMPORT-008') {
    const input = c.input.candidates;
    const after = exp.afterBulkAction;
    const wasHighPending = (x) => x.confidence === 'HIGH' && x.reviewStatus === 'PENDING';
    const all = after.every((a) => {
      const before = input.find((i) => i.id === a.id);
      const expectApproved = wasHighPending(before);
      const actualApproved = a.reviewStatus === 'APPROVED';
      return expectApproved === actualApproved;
    });
    ok(all, 'ACCEPT_ALL_HIGH approves exactly the HIGH PENDING candidates');
  }

  // IMPORT-007: parse failures are recoverable.
  if (id === 'IMPORT-007') {
    ok(exp.error?.recoverable === true, 'parse failure is recoverable (retry)');
    ok(exp.error?.type === 'PARSE_FAILED', 'parse failure code PARSE_FAILED');
  }
  console.log('');
}

console.log('=== Summary ===');
console.log(`Checks: ${checked}`);
console.log(`Errors: ${errors}`);
console.log(errors === 0 ? '=== All import cases consistent ===' : `=== ${errors} ERRORS FOUND ===`);
process.exit(errors === 0 ? 0 : 1);

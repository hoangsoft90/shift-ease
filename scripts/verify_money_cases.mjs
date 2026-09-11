#!/usr/bin/env node
// Verify money golden cases for ARITHMETIC SELF-CONSISTENCY directly from
// test/golden/money_engine_cases.json (independent of the Dart engine):
//   - total == regularPay + sum(*Diff) + overtimePay
//   - PAY-011: nested v1/v2 pay totals internally consistent
//   - PAY-014: weekly total hours / OT / pay consistent across shifts
// Reads the file; no hard-coded cases.

import { readFileSync } from 'fs';
import { resolve } from 'path';

const JSON_PATH = resolve(import.meta.dirname, '../test/golden/money_engine_cases.json');
const data = JSON.parse(readFileSync(JSON_PATH, 'utf8'));

console.log('=== Money Golden Case Verification ===');
console.log(`Source: ${JSON_PATH}`);
console.log(`Total cases: ${data.cases.length}`);
console.log('');

let checked = 0;
let errors = 0;

const close = (a, b) => Math.abs(a - b) < 0.005;

for (const c of data.cases) {
  const id = c.id;

  if (id === 'PAY-014') {
    const exp = c.expected;
    const alloc = exp.allocation;
    let sumShifts = 0;
    let sumHours = 0;
    let sumOt = 0;
    for (const key of Object.keys(alloc)) {
      const s = alloc[key];
      sumShifts += s.total;
      sumHours += s.regularHours + s.overtimeHours;
      sumOt += s.overtimeHours;
    }
    const okTotal = close(sumShifts, exp.weeklyTotalPay);
    const okHours = close(sumHours, exp.weeklyTotalHours);
    const okOt = close(sumOt, exp.weeklyOvertimeHours);
    const ok = okTotal && okHours && okOt;
    console.log(`${id}: weeklyTotalPay=${exp.weeklyTotalPay} (sum shifts ${sumShifts}) ${
      okTotal ? '✓' : '✗'} | weeklyHours=${exp.weeklyTotalHours} (sum ${sumHours}) ${
      okHours ? '✓' : '✗'} | weeklyOT=${exp.weeklyOvertimeHours} (sum ${sumOt}) ${
      okOt ? '✓' : '✗'}`);
    if (!ok) errors++;
    checked++;
    continue;
  }

  if (id === 'PAY-011') {
    for (const k of ['occurrenceV1_pay', 'occurrenceV2_pay']) {
      const e = c.expected[k];
      const sum = (e.regularPay ?? 0) + (e.overtimePay ?? 0);
      const ok = close(sum, e.total);
      console.log(`${id}/${k}: reg ${e.regularPay} + OT ${e.overtimePay} = ${sum} vs total ${e.total} ${
        ok ? '✓' : '✗'}`);
      if (!ok) errors++;
      checked++;
    }
    continue;
  }

  const e = c.expected;
  if (!('total' in e)) continue;
  let sum = e.regularPay ?? 0;
  for (const key of Object.keys(e)) {
    if (key.endsWith('Diff')) sum += e[key];
  }
  sum += e.overtimePay ?? 0;
  const ok = close(sum, e.total);
  console.log(`${id}: reg ${e.regularPay ?? '-'} + diffs + OT ${e.overtimePay ?? 0} = ${sum} vs total ${e.total} ${
    ok ? '✓' : '✗'}`);
  if (!ok) errors++;
  checked++;
}

console.log('');
console.log('=== Summary ===');
console.log(`Arithmetic checks: ${checked}`);
console.log(`Errors: ${errors}`);
console.log(errors === 0 ? '=== All money cases consistent ===' : `=== ${errors} ERRORS FOUND ===`);
process.exit(errors === 0 ? 0 : 1);

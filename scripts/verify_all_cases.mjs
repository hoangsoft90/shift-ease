#!/usr/bin/env node
// Verify all golden test cases by reading directly from time_engine_cases.json
// No hard-coded cases — single source of truth is the JSON file.

import { readFileSync } from 'fs';
import { resolve } from 'path';

const JSON_PATH = resolve(import.meta.dirname, '../test/golden/time_engine_cases.json');
const data = JSON.parse(readFileSync(JSON_PATH, 'utf8'));

console.log("=== Golden Test Case Verification ===");
console.log(`Source: ${JSON_PATH}`);
console.log(`Total cases in JSON: ${data.cases.length}`);
console.log("");

let computed = 0;
let errors = 0;
let skipped = 0;

for (const c of data.cases) {
  // Only verify cases that have utcStart/utcEnd (computed UTC cases)
  if (!c.expected || !c.expected.utcStart || !c.expected.utcEnd) {
    if (c.expected?.error) {
      console.log(`${c.id}: ERROR=${c.expected.error} (${c.name})`);
      if (Array.isArray(c.expected?.options)) {
        for (const o of c.expected.options) {
          console.log(`  option ${o.label}: ${o.utc} (offset ${o.offset})`);
        }
      }
    } else {
      console.log(`${c.id}: INVARIANT/BEHAVIORAL TEST (${c.name})`);
    }
    skipped++;
    continue;
  }

  const start = new Date(c.expected.utcStart);
  const end = new Date(c.expected.utcEnd);
  const computedDur = (end - start) / 3600000;
  const expectedDur = c.expected.durationHours;

  const durMatch = Math.abs(computedDur - expectedDur) < 0.001;

  console.log(`${c.id}: ${c.name}`);
  console.log(`  utcStart:  ${c.expected.utcStart}`);
  console.log(`  utcEnd:    ${c.expected.utcEnd}`);
  console.log(`  duration:  ${expectedDur}h (computed: ${computedDur}h) ${durMatch ? '✓' : '✗ MISMATCH!'}`);
  console.log(`  offsets:   ${c.expected.startOffset} -> ${c.expected.endOffset}`);

  if (!durMatch) {
    console.log(`  ⚠️  ERROR: duration mismatch!`);
    errors++;
  }
  computed++;
  console.log("");
}

console.log("=== Summary ===");
console.log(`Total cases in file: ${data.cases.length}`);
console.log(`UTC computed: ${computed}`);
console.log(`Skipped (error/invariant/behavioral): ${skipped}`);
console.log(`Errors: ${errors}`);
console.log(errors === 0 ? "=== All cases verified ===" : `=== ${errors} ERRORS FOUND ===`);

process.exit(errors === 0 ? 0 : 1);

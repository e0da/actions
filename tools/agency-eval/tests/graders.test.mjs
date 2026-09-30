import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { buildFixture, gradeWorkspace, fixturePath } from '../src/graders.mjs';

const childEnv = { PATH: process.env.PATH || '', LANG: 'C', TZ: 'UTC' };

const correctAdmission = `
'use strict';
function admit(state, request, now) {
  if (!request || typeof request.id !== 'string' || !request.id.length ||
      !Number.isSafeInteger(now) || now < 0 ||
      !Number.isSafeInteger(request.expiresAt) || request.expiresAt < 0)
    return { accepted: false, reason: 'invalid' };
  if (now >= request.expiresAt) return { accepted: false, reason: 'expired' };
  if (state.ids.includes(request.id)) return { accepted: false, reason: 'duplicate' };
  state.ids.push(request.id); state.accepted.push(request); state.version += 1;
  return { accepted: true, reason: 'accepted' };
}
module.exports = { admit };
`;
const correctRange = `
'use strict';
function sliceCodePoints(text, start, count) {
  if (typeof text !== 'string' || !Number.isSafeInteger(start) || start < 0 ||
      !Number.isSafeInteger(count) || count < 0) return null;
  const points = Array.from(text);
  if (start > points.length || count > points.length - start) return null;
  return points.slice(start, start + count).join('');
}
module.exports = { sliceCodePoints };
`;

async function workspace(t, correct = false) {
  const destination = await mkdtemp(path.join(os.tmpdir(), 'eval-grader-'));
  t.after(() => rm(destination, { recursive: true, force: true }));
  await buildFixture(destination);
  if (correct) {
    await writeFile(path.join(destination, 'lib/admission.cjs'), correctAdmission);
    await writeFile(path.join(destination, 'lib/range.cjs'), correctRange);
  }
  return destination;
}

test('seed fails visible tests and independent oracle without changing source fixture', async t => {
  const before = await readFile(path.join(fixturePath, 'lib/admission.cjs'), 'utf8');
  const destination = await workspace(t);
  await assert.rejects(promisify(execFile)(process.execPath, ['--test', 'test/contracts.test.cjs'], { cwd: destination, env: childEnv }));
  const grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, false);
  assert.ok(grade.score < 1);
  assert.ok(grade.evidence.checks.some(check => check.name.includes('duplicate') && !check.pass));
  assert.equal(await readFile(path.join(fixturePath, 'lib/admission.cjs'), 'utf8'), before);
});

test('correct source passes visible tests and every independent contract', async t => {
  const destination = await workspace(t, true);
  await promisify(execFile)(process.execPath, ['--test', 'test/contracts.test.cjs'], { cwd: destination, env: childEnv });
  const grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, true, grade.reason);
  assert.equal(grade.score, 1);
  assert.equal(grade.evidence.checks.length, 52);
  assert.equal(grade.evidence.exitCode, 0);
  assert.match(grade.evidence.oracleSha256, /^[a-f0-9]{64}$/);
  assert.ok(!grade.evidence.command[1].startsWith(destination));
});

test('tampered visible tests and npm script cannot hide faults', async t => {
  const destination = await workspace(t);
  await writeFile(path.join(destination, 'test/contracts.test.cjs'), '');
  await writeFile(path.join(destination, 'package.json'), '{"scripts":{"test":"exit 0"}}');
  await promisify(execFile)(process.execPath, ['--test', 'test/contracts.test.cjs'], { cwd: destination, env: childEnv });
  assert.equal((await gradeWorkspace(destination)).pass, false);
});

test('syntax errors and missing files fail grading with executable evidence', async t => {
  const destination = await workspace(t, true);
  await writeFile(path.join(destination, 'lib/range.cjs'), 'function {');
  let grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, false); assert.equal(grade.score, 0);
  assert.match(grade.evidence.stdout, /SyntaxError/);
  await rm(path.join(destination, 'lib/admission.cjs'));
  grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, false);
  assert.match(grade.evidence.stdout, /Cannot find module/);
});

test('premature successful process exit cannot pass without oracle report', async t => {
  const destination = await workspace(t, true);
  await writeFile(path.join(destination, 'lib/admission.cjs'), 'process.exit(0);');
  const grade = await gradeWorkspace(destination);
  assert.equal(grade.evidence.exitCode, 0);
  assert.equal(grade.pass, false); assert.equal(grade.score, 0);
});

test('oracle detects expiry ordering and range truncation regressions', async t => {
  const destination = await workspace(t, true);
  await writeFile(path.join(destination, 'lib/admission.cjs'), correctAdmission.replace('now >= request.expiresAt', 'now > request.expiresAt'));
  let grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, false);
  assert.ok(grade.evidence.checks.some(check => check.name === 'expired boundary leaves state unchanged' && !check.pass));
  await writeFile(path.join(destination, 'lib/admission.cjs'), correctAdmission);
  await writeFile(path.join(destination, 'lib/range.cjs'), correctRange.replace(' || count > points.length - start', ''));
  grade = await gradeWorkspace(destination);
  assert.equal(grade.pass, false);
  assert.ok(grade.evidence.checks.some(check => check.name === 'exhaustive small codepoint ranges' && !check.pass));
});

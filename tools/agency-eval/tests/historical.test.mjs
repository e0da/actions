import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { extractSource, regradeHistorical } from '../src/historical-regrade.mjs';

test('fence extraction requires one nonempty exact language block', () => {
  assert.equal(extractSource('No delivered code', 'rust').disposition, 'not_delivered');
  assert.equal(extractSource('```rust\n\n```', 'rust').disposition, 'not_delivered');
  assert.equal(extractSource('```rust\nfn a() {}\n```\n```rust\nfn b() {}\n```', 'rust').disposition, 'ambiguous');
  assert.deepEqual(extractSource('```bash\necho hello\n```\n```cpp\nint x;\n```', 'cpp'),
    { disposition: 'delivered', source: 'int x;\n' });
  assert.equal(extractSource('```rust\r\nfn a() {}\r\n```', 'rust').source, 'fn a() {}\r\n');
  assert.throws(() => extractSource('', 'bash'), /Unsupported/);
});

async function inputs(t) {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'historical-test-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const oracleDir = path.join(temporary, 'oracles'), screenPath = path.join(temporary, 'screen');
  await mkdir(oracleDir); await mkdir(screenPath);
  const files = [];
  for (const name of ['rust_oracle.txt', 'cpp_oracle.txt']) {
    const contents = 'donor preserved bytes';
    await writeFile(path.join(oracleDir, name), contents);
    files.push({ name, sha256: createHash('sha256').update(contents).digest('hex'), bound_to_independent_grade_oracle: true });
  }
  await writeFile(path.join(oracleDir, 'SOURCE-MANIFEST.json'), JSON.stringify({ files }));
  const savedGradesPath = path.join(temporary, 'saved.json');
  await writeFile(savedGradesPath, JSON.stringify({ results: [] }));
  return { screenPath, oracleDir, savedGradesPath };
}

test('uninspected delivered source and missing artifacts stay ungraded without execution', async t => {
  const config = await inputs(t);
  await writeFile(path.join(config.screenPath, 'glm-5.3--rust-admission--response.json'), JSON.stringify({
    parts: [{ type: 'text', text: '```rust\nfn dangerous() {}\n```' }],
  }));
  const report = await regradeHistorical(config);
  assert.equal(report.results.length, 12);
  assert.equal(report.results[0].disposition, 'inspection_not_verified');
  assert.equal(report.results[0].pass, null);
  assert.equal(report.results[0].compile, undefined);
  assert.ok(report.results.slice(1).every(result => result.disposition === 'artifact_unavailable' && result.pass === null));
});

test('changed donor bytes reject provenance before delivered code is examined', async t => {
  const config = await inputs(t);
  await writeFile(path.join(config.oracleDir, 'rust_oracle.txt'), 'changed donor');
  await assert.rejects(regradeHistorical(config), /Donor oracle provenance mismatch/);
});

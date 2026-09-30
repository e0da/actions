import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { publicationRun } from '../src/publication-run.mjs';

test('publication binds its completed operation despite a newer unrelated run', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'publication-test-'));
  try {
    const own = path.join(root, 'runs', '2026-first');
    const later = path.join(root, 'runs', '2026-newer');
    await mkdir(own, { recursive: true }); await mkdir(later);
    await writeFile(path.join(own, 'run.json'), JSON.stringify({ runId: 'first', evalId: 'eval-own' }));
    await writeFile(path.join(later, 'run.json'), JSON.stringify({ runId: 'newer', evalId: 'eval-other' }));
    const receipt = path.join(root, 'operation.json');
    await writeFile(receipt, JSON.stringify({ directory: own, runId: 'first', evalId: 'eval-own' }));
    assert.equal(await publicationRun(undefined, receipt), own);
    await writeFile(receipt, JSON.stringify({ directory: later, runId: 'first', evalId: 'eval-own' }));
    await assert.rejects(publicationRun(undefined, receipt), /disagree/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

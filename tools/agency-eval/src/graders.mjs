import { execFile } from 'node:child_process';
import { cp, mkdir, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export const fixturePath = fileURLToPath(new URL('../fixtures/repair-contract/', import.meta.url));
const oraclePath = fileURLToPath(new URL('../fixtures/oracle.cjs', import.meta.url));
export const graderVersion = 'repair-contract/v1';

export async function buildFixture(workspace) {
  await mkdir(workspace, { recursive: true });
  for (const name of await readdir(fixturePath)) {
    await cp(path.join(fixturePath, name), path.join(workspace, name), {
      recursive: true, errorOnExist: true, force: false,
    });
  }
  return workspace;
}

export async function gradeWorkspace(workspace) {
  const command = [process.execPath, oraclePath, path.resolve(workspace)];
  const oracleSha256 = createHash('sha256').update(await readFile(oraclePath)).digest('hex');
  const result = await new Promise(resolve => {
    execFile(command[0], command.slice(1), {
      cwd: path.dirname(oraclePath), timeout: 10_000, maxBuffer: 1024 * 1024,
      env: { PATH: process.env.PATH || '', LANG: 'C', TZ: 'UTC' },
    }, (error, stdout, stderr) => resolve({
      stdout, stderr, exitCode: error ? (typeof error.code === 'number' ? error.code : null) : 0,
      signal: error?.signal || null, killed: error?.killed || false,
      executionError: error && typeof error.code !== 'number' ? error.message : null,
    }));
  });
  let report;
  try { report = JSON.parse(result.stdout.trim()); } catch { report = null; }
  const valid = report?.oracle === graderVersion && Array.isArray(report.checks)
    && report.checks.length === 52
    && report.checks.every(item => typeof item.name === 'string' && typeof item.pass === 'boolean');
  const checks = valid ? report.checks : [];
  const passed = checks.filter(item => item.pass).length;
  const pass = valid && result.exitCode === 0 && !result.signal && passed === checks.length;
  const failures = checks.filter(item => !item.pass).map(item => item.name);
  return {
    pass, score: valid ? passed / checks.length : 0,
    reason: pass ? `All ${checks.length} independent checks passed`
      : valid ? (failures.length ? `Failed independent checks: ${failures.join('; ')}`
        : 'Independent oracle process failed despite reported passing checks')
        : 'Independent oracle did not complete with a valid report (source load, process, or syntax failure)',
    evidence: { graderVersion, oracleSha256, command, ...result, checks },
  };
}

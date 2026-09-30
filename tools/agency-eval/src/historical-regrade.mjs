import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const sha256 = value => createHash('sha256').update(value).digest('hex');
const candidates = { 'glm-5.3': 'GLM5.3', 'kimi-k3': 'KimiK3', 'glm-5.3-flash': 'GLM5.3Flash' };

export function extractSource(text, language) {
  if (!['rust', 'cpp'].includes(language)) throw new Error('Unsupported language');
  const fences = [...text.matchAll(/^```([^\n\r]*)\r?\n([\s\S]*?)^```[ \t]*$/gm)];
  const matching = fences.filter(match => match[1].trim() === language);
  if (matching.length === 0) return { disposition: 'not_delivered', source: null };
  if (matching.length !== 1) return { disposition: 'ambiguous', source: null, matchingFences: matching.length };
  if (!matching[0][2].trim()) return { disposition: 'not_delivered', source: null };
  return { disposition: 'delivered', source: matching[0][2] };
}

async function execute(command, timeout, cwd) {
  return new Promise(resolve => execFile(command[0], command.slice(1), {
    cwd, timeout, maxBuffer: 1024 * 1024,
    env: { PATH: process.env.PATH || '', LANG: 'C', TZ: 'UTC' },
  }, (error, stdout, stderr) => resolve({
    command, exitCode: error ? (typeof error.code === 'number' ? error.code : null) : 0,
    signal: error?.signal || null, killed: error?.killed || false, stdout, stderr,
    infrastructureError: error && typeof error.code !== 'number' ? error.message : null,
  })));
}

export async function regradeHistorical({ screenPath, oracleDir, savedGradesPath }) {
  if (!screenPath || !oracleDir || !savedGradesPath) throw new Error('screenPath, oracleDir and savedGradesPath are required');
  const savedBytes = await readFile(savedGradesPath);
  const saved = JSON.parse(savedBytes);
  const manifestBytes = await readFile(path.join(oracleDir, 'SOURCE-MANIFEST.json'));
  const manifest = JSON.parse(manifestBytes);
  const oracles = {};
  for (const name of ['rust_oracle.txt', 'cpp_oracle.txt']) {
    const bytes = await readFile(path.join(oracleDir, name));
    const entry = manifest.files.find(file => file.name === name);
    if (!entry?.bound_to_independent_grade_oracle || entry.sha256 !== sha256(bytes)) {
      throw new Error(`Donor oracle provenance mismatch: ${name}`);
    }
    oracles[name] = { text: bytes.toString('utf8'), sha256: sha256(bytes) };
  }
  const results = [];
  for (const [model, candidate] of Object.entries(candidates)) {
    for (const task of ['rust-admission', 'cpp-range']) {
      for (const attempt of ['first-pass', 'one-repair']) {
        const filename = `${model}--${task}${attempt === 'one-repair' ? '--repair' : ''}--response.json`;
        const responsePath = path.join(screenPath, filename);
        const result = { candidate, model, task, attempt, responsePath, pass: null };
        results.push(result);
        let response;
        try {
          const bytes = await readFile(responsePath);
          result.responseSha256 = sha256(bytes); response = JSON.parse(bytes);
        } catch (error) {
          result.disposition = 'artifact_unavailable'; result.reason = error.message; continue;
        }
        const baseline = saved.results.filter(row => row.candidate === candidate && row.task === task && row.attempt === attempt);
        result.savedGrade = baseline.length === 1 ? baseline[0].grade || baseline[0].delivery || null : null;
        result.savedPass = baseline.length === 1 ? baseline[0].pass ?? null : null;
        const language = task === 'rust-admission' ? 'rust' : 'cpp';
        const extracted = extractSource((response.parts || []).filter(part => part.type === 'text').map(part => part.text).join('\n'), language);
        result.disposition = extracted.disposition;
        if (!extracted.source) {
          result.matchingFences = extracted.matchingFences || 0;
          result.reason = 'No unique delivered source; no compiler or executable invoked'; continue;
        }
        result.sourceSha256 = sha256(extracted.source);
        if (baseline.length !== 1 || result.sourceSha256 !== baseline[0].source_sha256 ||
            !/manual(?:ly)?\s+(?:source\s+)?inspect/i.test(baseline[0].effect_gate || '')) {
          result.disposition = 'inspection_not_verified';
          result.reason = 'Source is not hash-bound to one independently inspected saved grade'; continue;
        }
        const oracleName = language === 'rust' ? 'rust_oracle.txt' : 'cpp_oracle.txt';
        result.oracleSha256 = oracles[oracleName].sha256;
        const combined = extracted.source + oracles[oracleName].text;
        result.combinedSourceSha256 = sha256(combined);
        const temporary = await mkdtemp(path.join(os.tmpdir(), 'historical-regrade-'));
        try {
          const sourcePath = path.join(temporary, language === 'rust' ? 'candidate.rs' : 'candidate.cpp');
          const binaryPath = path.join(temporary, 'candidate');
          await writeFile(sourcePath, combined);
          const command = language === 'rust'
            ? ['rustc', '--edition=2021', '--crate-name', 'go_frontier_candidate', sourcePath, '-o', binaryPath]
            : ['clang++', '-std=c++17', '-fsanitize=address,undefined', '-fno-sanitize-recover=all', '-g', sourcePath, '-o', binaryPath];
          result.compile = await execute(command, 30_000, temporary);
          if (result.compile.infrastructureError) {
            result.disposition = 'infrastructure_blocked'; continue;
          }
          result.run = result.compile.exitCode === 0 ? await execute([binaryPath], 10_000, temporary) : null;
          if (result.run?.infrastructureError) {
            result.disposition = 'infrastructure_blocked'; continue;
          }
          result.pass = result.compile.exitCode === 0 && result.run?.exitCode === 0;
          result.disposition = result.pass ? 'pass' : 'fail';
          result.matchesSavedPass = result.savedPass === null ? null : result.pass === result.savedPass;
        } finally { await rm(temporary, { recursive: true, force: true }); }
      }
    }
  }
  return {
    version: 'historical-regrade/v1', screenPath, oracleDir, savedGradesPath,
    savedGradesSha256: sha256(savedBytes), oracleManifestSha256: sha256(manifestBytes),
    qualification: 'Offline code grading of previously independently inspected synthetic outputs; no native agent calls. This is host compilation/execution, not an untrusted-code sandbox. Temporary files are removed; original responses, manifests and grades remain unchanged.',
    results,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [screenPath, oracleDir, savedGradesPath] = process.argv.slice(2);
  const report = await regradeHistorical({ screenPath, oracleDir, savedGradesPath });
  console.log(JSON.stringify(report, null, 2));
  if (report.results.some(result => ['fail', 'infrastructure_blocked'].includes(result.disposition))) process.exitCode = 1;
}

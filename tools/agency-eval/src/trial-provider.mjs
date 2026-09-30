import { mkdir, readdir, lstat, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
import { buildFixture, gradeWorkspace } from './graders.mjs';

export const sha256 = value => createHash('sha256').update(value).digest('hex');
export async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
}

export async function snapshot(source, destination) {
  const manifest = [];
  let bytes = 0;
  async function walk(relative = '') {
    for (const entry of (await readdir(path.join(source, relative))).sort()) {
      const name = path.join(relative, entry);
      const from = path.join(source, name);
      const stat = await lstat(from);
      if (stat.isSymbolicLink() || (!stat.isDirectory() && !stat.isFile()))
        throw new Error(`Unsupported fixture entry: ${name}`);
      if (stat.isDirectory()) { await walk(name); continue; }
      bytes += stat.size;
      if (bytes > 20 * 1024 * 1024 || manifest.length >= 1000)
        throw new Error('Fixture artifact budget exceeded');
      const body = await readFile(from);
      await mkdir(path.dirname(path.join(destination, name)), { recursive: true });
      await writeFile(path.join(destination, name), body, { flag: 'wx' });
      manifest.push({ path: name, bytes: body.length, sha256: sha256(body) });
    }
  }
  await mkdir(destination, { recursive: true });
  await walk();
  return { files: manifest, sha256: sha256(JSON.stringify(manifest)) };
}

export function disposition(response, grade, capture, aborted) {
  if (aborted) return 'interrupted';
  if (response.error) {
    return /auth|login|logged|401|403|429|quota|rate.?limit|region|connect|network|transport|API\/provider/i.test(response.error)
      ? 'infrastructure_blocked' : 'execution_error';
  }
  if (capture?.bindingVerified !== true || capture.completeTrajectory !== true || capture.terminalConfirmed !== true)
    return 'evidence_failure';
  if (response.cached) return 'evidence_failure';
  if (typeof response.output !== 'string' || !response.output.trim()) return 'delivery_failure';
  return grade.pass ? 'pass' : 'task_failure';
}

export class TrialProvider {
  constructor({ label, runRoot, factory, build = buildFixture, grade = gradeWorkspace,
    timeoutMs = 180_000, repairs = 1, workspaceRoot, onProgress = async () => {} }) {
    if (![0, 1].includes(repairs)) throw new Error('Only zero or one repair is supported');
    Object.assign(this, { label, runRoot, factory, build, grade, timeoutMs, repairs, workspaceRoot, onProgress });
  }
  id() { return this.label; }
  async callApi(taskPrompt, context = {}, callOptions = {}) {
    const trialId = randomUUID();
    const directory = path.join(this.runRoot, trialId);
    const workspace = path.join(this.workspaceRoot ?? directory, `workspace-${trialId}`);
    await mkdir(directory, { recursive: true });
    await this.build(workspace);
    const seed = await snapshot(workspace, path.join(directory, 'seed'));
    const attempts = [];
    let adapter;
    let cleanup = { terminalConfirmed: false, reason: 'adapter not initialized' };
    let fatal;
    const record = { schema: 1, trialId, candidate: this.label, taskSha256: sha256(taskPrompt),
      fixtureSha256: seed.sha256, workspace, startedAt: new Date().toISOString(), attempts };
    await writeJson(path.join(directory, 'contract.json'), { ...record,
      budget: { timeoutMs: this.timeoutMs, maxRepairs: this.repairs },
      context: { syntheticOnly: true, judge: 'independent executable oracle', requested: context.vars ?? {} } });
    try {
      adapter = await this.factory({ workspace, directory, trialId, taskPrompt });
      record.runtime = adapter.identity;
      for (let index = 0; index <= this.repairs; index++) {
        if (index && !['task_failure', 'delivery_failure'].includes(attempts.at(-1).disposition)) break;
        const marker = `TRIAL ${trialId} ATTEMPT ${index + 1}`;
        const correction = 'The previous attempt did not satisfy the published task contract. Re-read TASK.md and your current source; correct both contracts and deliver a final receipt. The independent grader supplies no hidden test details. This is the only repair allowed.';
        const prompt = `${index ? correction : taskPrompt}\n\n[${marker}]`;
        const abort = new AbortController();
        const relay = () => abort.abort(callOptions.abortSignal.reason);
        if (callOptions.abortSignal?.aborted) relay();
        else callOptions.abortSignal?.addEventListener('abort', relay, { once: true });
        const timer = setTimeout(() => abort.abort(new Error('Trial attempt deadline reached')), this.timeoutMs);
        const attempt = { attempt: index + 1, marker, promptSha256: sha256(prompt),
          startedAt: new Date().toISOString() };
        const attemptDirectory = path.join(directory, `attempt-${index + 1}`);
        await this.onProgress({ trialId, candidate: this.label, attempt: index + 1, phase: 'running', directory });
        let response;
        try {
          response = await adapter.call(prompt, { signal: abort.signal, index, marker });
        } catch (error) { response = { error: String(error.message ?? error) }; }
        finally {
          clearTimeout(timer);
          callOptions.abortSignal?.removeEventListener('abort', relay);
        }
        attempt.endedAt = new Date().toISOString();
        attempt.elapsedMs = Date.parse(attempt.endedAt) - Date.parse(attempt.startedAt);
        attempt.abortRequested = abort.signal.aborted;
        attempt.response = response;
        attempts.push(attempt);
        await writeJson(path.join(attemptDirectory, 'response.json'), response);
        attempt.capture = await adapter.capture(response, { prompt, marker, index });
        if (index && response.sessionId !== attempts[0].response.sessionId)
          attempt.capture = { ...attempt.capture, bindingVerified: false, failure: 'repair changed session' };
        attempt.artifacts = await snapshot(workspace, path.join(attemptDirectory, 'workspace'));
        // Execute the oracle against retained output, never the still-live workspace.
        attempt.grade = !response.error && !response.cached && attempt.capture?.bindingVerified === true
          && attempt.capture.completeTrajectory === true && attempt.capture.terminalConfirmed === true && !attempt.abortRequested
          ? await this.grade(path.join(attemptDirectory, 'workspace'))
          : { pass: false, score: 0, ungraded: true, reason: 'Runtime or evidence failure; task competence ungraded' };
        attempt.disposition = disposition(response, attempt.grade, attempt.capture, attempt.abortRequested);
        await writeJson(path.join(attemptDirectory, 'receipt.json'), attempt);
        await this.onProgress({ trialId, candidate: this.label, attempt: index + 1,
          phase: attempt.disposition, directory });
        if (attempt.disposition === 'pass') break;
      }
    } catch (error) {
      fatal = String(error.stack ?? error);
      const partial = attempts.at(-1);
      if (partial && !partial.disposition) {
        partial.disposition = 'evidence_failure';
        partial.grade = { pass: false, score: 0, ungraded: true, reason: 'Incomplete evidence after dispatched attempt' };
        partial.failure = fatal;
        await writeJson(path.join(directory, `attempt-${partial.attempt}`, 'partial-receipt.json'), partial);
      }
    }
    finally {
      if (adapter) {
        try { cleanup = await adapter.close(); }
        catch (error) { cleanup = { terminalConfirmed: false, reason: String(error.message ?? error) }; }
      }
      record.cleanup = cleanup;
      record.endedAt = new Date().toISOString();
      if (fatal) record.fatal = fatal;
      await writeJson(path.join(directory, 'trial.json'), record);
    }
    const final = attempts.at(-1);
    const accepted = final?.disposition === 'pass' && cleanup.terminalConfirmed === true && !fatal;
    const firstPass = attempts[0]?.disposition === 'pass';
    const costs = attempts.map(a => a.response.cost);
    const knownCosts = costs.filter(Number.isFinite);
    const usages = attempts.map(a => a.response.tokenUsage);
    const totalUsage = {};
    for (const usage of usages.filter(Boolean))
      for (const key of ['prompt', 'completion', 'total', 'cached'])
        if (Number.isFinite(usage[key])) totalUsage[key] = (totalUsage[key] ?? 0) + usage[key];
    return { output: final?.response?.output ?? '',
      ...(fatal ? { error: fatal } : {}),
      metadata: { trialId, directory, accepted, firstPass, attempts: attempts.length,
        disposition: final?.disposition ?? 'execution_error', cleanup,
        firstGrade: attempts[0]?.grade, finalGrade: final?.grade,
        accounting: { basis: 'native/API-equivalent, not subscription cash',
          knownReportedCost: knownCosts.length ? knownCosts.reduce((a, b) => a + b, 0) : null,
          unknownCostAttempts: costs.length - knownCosts.length,
          unknownUsageAttempts: usages.filter(u => !u).length } },
      ...(Object.keys(totalUsage).length ? { tokenUsage: totalUsage } : {}),
      ...(knownCosts.length === costs.length && costs.length
        ? { cost: knownCosts.reduce((a, b) => a + b, 0) } : {}) };
  }
}

export async function regradeTrial(directory, grade = gradeWorkspace) {
  const record = JSON.parse(await readFile(path.join(directory, 'trial.json'), 'utf8'));
  const results = [];
  for (const attempt of record.attempts) {
    if (attempt.grade?.ungraded) {
      results.push({ attempt: attempt.attempt, disposition: attempt.disposition, grade: attempt.grade,
        replay: 'Preserved ungraded runtime/evidence outcome; no competency grading' });
      continue;
    }
    const workspace = path.join(directory, `attempt-${attempt.attempt}`, 'workspace');
    const checked = [];
    const present = [];
    async function inventory(relative = '') {
      for (const entry of await readdir(path.join(workspace, relative))) {
        const name = path.join(relative, entry);
        const stat = await lstat(path.join(workspace, name));
        if (stat.isSymbolicLink() || (!stat.isDirectory() && !stat.isFile()))
          throw new Error(`Snapshot changed: unsupported ${name}`);
        if (stat.isDirectory()) await inventory(name);
        else present.push(name);
      }
    }
    await inventory();
    if (JSON.stringify(present.sort()) !== JSON.stringify(attempt.artifacts.files.map(f => f.path).sort()))
      throw new Error('Snapshot changed: file inventory');
    for (const file of attempt.artifacts.files) {
      const body = await readFile(path.join(workspace, file.path));
      if (sha256(body) !== file.sha256) throw new Error(`Snapshot changed: ${file.path}`);
      checked.push(file.path);
    }
    results.push({ attempt: attempt.attempt, checkedFiles: checked.length, grade: await grade(workspace) });
  }
  return { trialId: record.trialId, candidate: record.candidate, results };
}

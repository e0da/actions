import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { TrialProvider, regradeTrial, snapshot } from '../src/trial-provider.mjs';

const TASK = 'Read TASK.md, fix answer.txt, and provide a final receipt.';
const read = file => readFile(file, 'utf8');
const json = async file => JSON.parse(await read(file));

async function harness(t, options = {}) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'trial-lifecycle-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const sessions = [];
  const graded = [];
  const build = async workspace => {
    await mkdir(workspace, { recursive: true });
    await writeFile(path.join(workspace, 'TASK.md'), TASK);
    await writeFile(path.join(workspace, 'answer.txt'), 'seeded failure\n');
  };
  const grade = async workspace => {
    graded.push(workspace);
    const answer = await read(path.join(workspace, 'answer.txt'));
    return { pass: answer === 'fixed\n', diagnosis: answer === 'fixed\n' ? [] : ['published answer contract failed'] };
  };
  const factory = async context => {
    const sessionId = `mock-session-${sessions.length + 1}`;
    const session = { ...context, sessionId, calls: [], captures: [], closes: 0 };
    sessions.push(session);
    return {
      identity: { sessionId, parentSessionId: context.trialId },
      async call(prompt, details) {
        session.calls.push({ prompt, ...details, before: await read(path.join(context.workspace, 'answer.txt')) });
        if (options.call) return options.call(session, prompt, details);
        await writeFile(path.join(context.workspace, 'answer.txt'), 'fixed\n');
        return { output: 'Completed final receipt', sessionId, cost: 0.01 };
      },
      async capture(response, details) {
        session.captures.push({ response, ...details });
        return options.capture ? options.capture(session, response, details) : { bindingVerified: true, completeTrajectory: true, terminalConfirmed: true, sessionId, marker: details.marker };
      },
      async close() {
        session.closes++;
        return options.close ? options.close(session) : { terminalConfirmed: true };
      },
    };
  };
  const provider = new TrialProvider({ label: 'mock', runRoot: path.join(root, 'runs'), workspaceRoot: path.join(root, 'live'),
    factory, build, grade, timeoutMs: 1000, ...options.provider });
  return { root, provider, sessions, graded, grade };
}

test('one diagnosed repair uses existing failed state and session while retaining immutable evidence', async t => {
  const h = await harness(t, { call: async (session, prompt, { index }) => {
    await writeFile(path.join(session.workspace, 'answer.txt'), index === 0 ? 'attempt one failure\n' : 'fixed\n');
    return { output: 'Final receipt', sessionId: session.sessionId, cost: 0.02 };
  } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, true);
  assert.equal(result.metadata.firstPass, false);
  assert.equal(result.metadata.attempts, 2);
  assert.equal(result.cost, 0.04);
  const session = h.sessions[0];
  assert.equal(session.calls.length, 2);
  assert.equal(session.calls[1].before, 'attempt one failure\n');
  assert.match(session.calls[1].prompt, /previous attempt.*not satisfy/i);
  assert.match(session.calls[1].prompt, /current source/i);
  assert.equal(session.closes, 1);
  const directory = result.metadata.directory;
  assert.equal(await read(path.join(directory, 'seed/answer.txt')), 'seeded failure\n');
  assert.equal(await read(path.join(directory, 'attempt-1/workspace/answer.txt')), 'attempt one failure\n');
  assert.equal(await read(path.join(directory, 'attempt-2/workspace/answer.txt')), 'fixed\n');
  const first = await json(path.join(directory, 'attempt-1/receipt.json'));
  assert.equal(first.grade.pass, false);
  assert.equal(first.disposition, 'task_failure');
  assert.equal(first.response.sessionId, session.sessionId);
  const record = await json(path.join(directory, 'trial.json'));
  assert.equal(record.attempts[0].grade.pass, false);
  assert.equal(record.attempts[1].grade.pass, true);
  assert.deepEqual(record.attempts[0], first);
  assert.deepEqual(h.graded, [path.join(directory, 'attempt-1/workspace'), path.join(directory, 'attempt-2/workspace')]);
  await writeFile(path.join(session.workspace, 'answer.txt'), 'late live mutation\n');
  assert.equal(await read(path.join(directory, 'attempt-1/workspace/answer.txt')), 'attempt one failure\n');
  assert.equal((await json(path.join(directory, 'attempt-1/receipt.json'))).grade.pass, false);
});

test('separate trials receive fresh sessions, workspaces, seeds, and identifiers', async t => {
  const h = await harness(t);
  const a = await h.provider.callApi(TASK);
  const b = await h.provider.callApi(TASK);
  assert.equal(a.metadata.accepted, true);
  assert.equal(b.metadata.accepted, true);
  assert.equal(a.metadata.firstPass, true);
  assert.equal(h.sessions.length, 2);
  assert.notEqual(a.metadata.trialId, b.metadata.trialId);
  assert.notEqual(h.sessions[0].workspace, h.sessions[1].workspace);
  assert.notEqual(h.sessions[0].sessionId, h.sessions[1].sessionId);
  for (const session of h.sessions) {
    assert.equal(session.calls[0].before, 'seeded failure\n');
    assert.equal(session.closes, 1);
  }
});

test('wrong parent binding prevents acceptance despite a passing workspace', async t => {
  const h = await harness(t, { capture: () => ({ bindingVerified: false, completeTrajectory: true, terminalConfirmed: true, failure: 'wrong parent binding' }) });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'evidence_failure');
  assert.equal(result.metadata.attempts, 1);
  assert.equal(h.sessions[0].closes, 1);
});

test('a repair that changes the session is rejected', async t => {
  const h = await harness(t, { call: async (session, prompt, { index }) => {
    if (index) await writeFile(path.join(session.workspace, 'answer.txt'), 'fixed\n');
    return { output: 'Final receipt', sessionId: index ? 'unexpected-new-session' : session.sessionId };
  } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'evidence_failure');
  assert.equal(result.metadata.attempts, 2);
});

test('missing final receipt remains a delivery failure after the sole repair', async t => {
  const h = await harness(t, { call: async session => {
    await writeFile(path.join(session.workspace, 'answer.txt'), 'fixed\n');
    return { output: '   ', sessionId: session.sessionId };
  } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'delivery_failure');
  assert.equal(result.metadata.attempts, 2);
  assert.equal(h.sessions[0].calls.length, 2);
});

for (const [name, error, disposition] of [
  ['login blocked', 'login required: unauthorized 401', 'infrastructure_blocked'],
  ['nonzero agent execution', 'agent exited with code 7', 'execution_error'],
]) {
  test(`${name} is ungraded and receives no task repair`, async t => {
    const h = await harness(t, { call: async session => ({ error, exitCode: 7, sessionId: session.sessionId }) });
    const result = await h.provider.callApi(TASK);
    assert.equal(result.metadata.accepted, false);
    assert.equal(result.metadata.disposition, disposition);
    assert.equal(result.metadata.attempts, 1);
    assert.equal(h.sessions[0].calls.length, 1);
    assert.equal(h.sessions[0].closes, 1);
    assert.equal(h.graded.length, 0);
    assert.equal(result.metadata.finalGrade.ungraded, true);
  });
}

test('attempt deadline reaches the adapter abort signal and cleanup completes', async t => {
  let abortObserved = false;
  const h = await harness(t, { provider: { timeoutMs: 15 }, call: async (session, prompt, { signal }) => {
    await new Promise(resolve => signal.addEventListener('abort', () => { abortObserved = true; resolve(); }, { once: true }));
    return { output: 'Interrupted', sessionId: session.sessionId };
  } });
  const result = await h.provider.callApi(TASK);
  assert.equal(abortObserved, true);
  assert.equal(result.metadata.disposition, 'interrupted');
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.attempts, 1);
  assert.equal(h.sessions[0].closes, 1);
  const record = await json(path.join(result.metadata.directory, 'trial.json'));
  assert.equal(record.attempts[0].abortRequested, true);
  assert.equal(record.cleanup.terminalConfirmed, true);
});

test('caller cancellation is relayed to the adapter and cannot become acceptance', async t => {
  const controller = new AbortController();
  const h = await harness(t, { call: async (session, prompt, { signal }) => {
    controller.abort(new Error('caller cancelled'));
    assert.equal(signal.aborted, true);
    assert.match(signal.reason.message, /caller cancelled/);
    await writeFile(path.join(session.workspace, 'answer.txt'), 'fixed\n');
    return { output: 'Final receipt', sessionId: session.sessionId };
  } });
  const result = await h.provider.callApi(TASK, {}, { abortSignal: controller.signal });
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'interrupted');
  assert.equal(h.sessions[0].closes, 1);
});

test('terminal confirmation is required even for passing work and a final receipt', async t => {
  const h = await harness(t, { close: () => ({ terminalConfirmed: false, reason: 'still running' }) });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.disposition, 'pass');
  assert.equal(result.metadata.accepted, false);
  assert.equal(h.sessions[0].closes, 1);
});

test('offline regrade uses retained evidence after live workspace disappears and rejects content tampering', async t => {
  const h = await harness(t);
  const result = await h.provider.callApi(TASK);
  await rm(h.sessions[0].workspace, { recursive: true });
  const regraded = await regradeTrial(result.metadata.directory, h.grade);
  assert.equal(regraded.results[0].grade.pass, true);
  assert.equal(h.sessions[0].calls.length, 1);
  await writeFile(path.join(result.metadata.directory, 'attempt-1/workspace/answer.txt'), 'tampered\n');
  await assert.rejects(regradeTrial(result.metadata.directory, h.grade), /Snapshot changed/);
});

test('offline regrade rejects added executable files in a retained snapshot', async t => {
  const h = await harness(t);
  const result = await h.provider.callApi(TASK);
  await writeFile(path.join(result.metadata.directory, 'attempt-1/workspace/injected.mjs'), 'throw new Error("injected")');
  await assert.rejects(regradeTrial(result.metadata.directory, h.grade), /Snapshot changed|manifest|unexpected|added/i);
});

test('offline regrade rejects symlink substitution even with identical target bytes', async t => {
  const h = await harness(t);
  const result = await h.provider.callApi(TASK);
  const file = path.join(result.metadata.directory, 'attempt-1/workspace/answer.txt');
  const outside = path.join(h.root, 'outside.txt');
  await writeFile(outside, 'fixed\n');
  await rm(file);
  await symlink(outside, file);
  await assert.rejects(regradeTrial(result.metadata.directory, h.grade), /symlink|unsupported|Snapshot changed/i);
});

test('snapshot refuses symlinks instead of copying external content', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'trial-symlink-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'source'));
  await writeFile(path.join(root, 'secret.txt'), 'outside source');
  await symlink(path.join(root, 'secret.txt'), path.join(root, 'source/link.txt'));
  await assert.rejects(snapshot(path.join(root, 'source'), path.join(root, 'copy')), /Unsupported fixture entry: link.txt/);
});

test('a cached response cannot count as a fresh accepted trial', async t => {
  const h = await harness(t, { call: async session => {
    await writeFile(path.join(session.workspace, 'answer.txt'), 'fixed\n');
    return { output: 'Old receipt', sessionId: session.sessionId, cached: true };
  } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'evidence_failure');
  assert.equal(result.metadata.attempts, 1);
  assert.equal(h.sessions[0].closes, 1);
});

test('cleanup exceptions cannot turn passing work into an accepted trial', async t => {
  const h = await harness(t, { close: () => { throw new Error('terminal state unavailable'); } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.cleanup.terminalConfirmed, false);
  assert.match(result.metadata.cleanup.reason, /terminal state unavailable/);
  assert.equal((await json(path.join(result.metadata.directory, 'trial.json'))).cleanup.terminalConfirmed, false);
});

test('capture exceptions still close the session and preserve a failed trial record', async t => {
  const h = await harness(t, { capture: () => { throw new Error('capture unavailable'); } });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.match(result.error, /capture unavailable/);
  assert.equal(h.sessions[0].closes, 1);
  const record = await json(path.join(result.metadata.directory, 'trial.json'));
  assert.match(record.fatal, /capture unavailable/);
  assert.equal(record.cleanup.terminalConfirmed, true);
});

test('failure after the allowed repair stops at two attempts', async t => {
  const h = await harness(t, { call: async session => ({ output: 'Unsuccessful final receipt', sessionId: session.sessionId }) });
  const result = await h.provider.callApi(TASK);
  assert.equal(result.metadata.accepted, false);
  assert.equal(result.metadata.disposition, 'task_failure');
  assert.equal(result.metadata.attempts, 2);
  assert.equal(h.sessions[0].calls.length, 2);
  assert.equal(h.sessions[0].closes, 1);
});

test('repair budgets larger than one are rejected', () => {
  assert.throws(() => new TrialProvider({ repairs: 2 }), /zero or one repair/);
});

for (const [missing, value] of [
  ['completeTrajectory', undefined], ['terminalConfirmed', undefined],
  ['completeTrajectory', false], ['terminalConfirmed', false],
  ['completeTrajectory', 'true'], ['terminalConfirmed', 'true'],
]) {
  test(`per-attempt ${missing}=${JSON.stringify(value)} prevents grading, acceptance, and repair`, async t => {
    const h = await harness(t, { capture: () => {
      const evidence = { bindingVerified: true, completeTrajectory: true, terminalConfirmed: true };
      if (value === undefined) delete evidence[missing];
      else evidence[missing] = value;
      return evidence;
    } });
    const result = await h.provider.callApi(TASK);
    assert.equal(result.metadata.accepted, false);
    assert.equal(result.metadata.disposition, 'evidence_failure');
    assert.equal(result.metadata.attempts, 1);
    assert.equal(result.metadata.finalGrade.ungraded, true);
    assert.equal(h.graded.length, 0);
    assert.equal(h.sessions[0].calls.length, 1);
    assert.equal(h.sessions[0].closes, 1);
    assert.equal(result.metadata.cleanup.terminalConfirmed, true);
  });
}

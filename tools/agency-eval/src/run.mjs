import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { TrialProvider, regradeTrial, writeJson } from './trial-provider.mjs';
import { nativeFactory } from './providers.mjs';
import { fixturePath } from './graders.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
process.chdir(root);
process.env.PROMPTFOO_DISABLE_TELEMETRY = '1';
process.env.PROMPTFOO_DISABLE_UPDATE = '1';
process.env.PROMPTFOO_DISABLE_SHARING = '1';
process.env.PROMPTFOO_DISABLE_REMOTE_GENERATION = '1';
process.env.PROMPTFOO_CONFIG_DIR = path.join(root, '.promptfoo');
const [command = 'demo', ...args] = process.argv.slice(2);
function option(name, fallback) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`Missing ${name} value`);
  return args[index + 1];
}
function integer(name, fallback, max) {
  const value = Number(option(name, fallback));
  if (!Number.isInteger(value) || value < 0 || value > max) throw new Error(`Invalid ${name}`);
  return value;
}

if (command === 'regrade') {
  if (!args[0]) throw new Error('Usage: npm run regrade -- /absolute/path/to/trial');
  const replay = await regradeTrial(path.resolve(args[0]));
  console.log(JSON.stringify({ trialId: replay.trialId, candidate: replay.candidate,
    results: replay.results.map(r => ({ attempt: r.attempt, checkedFiles: r.checkedFiles,
      pass: r.grade.pass, ungraded: r.grade.ungraded ?? false, reason: r.grade.reason })) }, null, 2));
} else if (command === 'demo' || command === 'native') {
  const { evaluate, cache } = await import('promptfoo');
  cache.disableCache();
  const repeat = integer('--repeat', 1, 10);
  if (!repeat) throw new Error('At least one repeat is required');
  const repairs = integer('--repairs', 1, 1);
  const runId = new Date().toISOString().replace(/[:.]/g, '-') + '-' + randomUUID().slice(0, 8);
  const runRoot = path.join(root, 'runs', runId);
  await mkdir(runRoot, { recursive: true });
  const task = await readFile(path.join(fixturePath, 'TASK.md'), 'utf8');
  const controller = new AbortController();
  process.once('SIGINT', () => controller.abort(new Error('Coordinator interrupted run')));
  process.once('SIGTERM', () => controller.abort(new Error('Coordinator terminated run')));
  async function progress(update) {
    await writeFile(path.join(root, 'runs', 'STATUS.json'), JSON.stringify({
      updatedAt: new Date().toISOString(), runId, ...update
    }, null, 2));
    console.log(`${update.candidate} attempt ${update.attempt ?? '-'}: ${update.phase}`);
  }
  let candidates;
  if (command === 'native') {
    const configPath = option('--config', path.join(root, 'runtime.local.json'));
    const personal = JSON.parse(await readFile(configPath, 'utf8'));
    candidates = personal.candidates;
    if (!Array.isArray(candidates) || !candidates.length) throw new Error('No candidates configured');
  } else candidates = [
    { kind: 'mock', label: 'offline:first-pass', repairNeeded: false },
    { kind: 'mock', label: 'offline:one-repair', repairNeeded: true }
  ];
  const providers = candidates.map(runtime => new TrialProvider({
    label: runtime.label, runRoot, repairs, workspaceRoot: runtime.workspaceRoot,
    timeoutMs: integer('--timeout-ms', 180_000, 600_000), onProgress: progress,
    factory: async options => {
      if (runtime.blocked) return {
        identity: { kind: runtime.kind, auth: runtime.blocked, requestedModel: runtime.config?.model },
        call: async () => ({ error: `Native login unavailable: ${runtime.blocked}` }),
        capture: async () => ({ bindingVerified: false, completeTrajectory: false }),
        close: async () => ({ terminalConfirmed: true, launched: false })
      };
      if (runtime.kind !== 'mock') return nativeFactory(runtime, options);
      const sessionId = randomUUID();
      return {
        identity: { kind: 'offline mock', model: 'none; demonstration only' },
        async call(prompt, { index }) {
          if (!runtime.repairNeeded || index) {
            await writeFile(path.join(options.workspace, 'lib/admission.cjs'), `
module.exports.admit = (state, request, now) => {
 if (!request || typeof request.id !== 'string' || !request.id.length || !Number.isSafeInteger(now) || now < 0 || !Number.isSafeInteger(request.expiresAt) || request.expiresAt < 0) return {accepted:false,reason:'invalid'};
 if (now >= request.expiresAt) return {accepted:false,reason:'expired'};
 if (state.ids.includes(request.id)) return {accepted:false,reason:'duplicate'};
 state.ids.push(request.id); state.accepted.push(request); state.version++;
 return {accepted:true,reason:'accepted'};
};`);
            await writeFile(path.join(options.workspace, 'lib/range.cjs'), `
module.exports.sliceCodePoints = (text,start,count) => {
 if (typeof text !== 'string' || !Number.isSafeInteger(start) || start < 0 || !Number.isSafeInteger(count) || count < 0) return null;
 const points=Array.from(text);
 if (start > points.length || count > points.length-start) return null;
 return points.slice(start,start+count).join('');
};`);
          }
          return { output: 'Offline mock delivery; no model or subscription used.', sessionId };
        },
        capture: async () => ({ bindingVerified: true, completeTrajectory: true, terminalConfirmed: true, mock: true }),
        close: async () => ({ terminalConfirmed: true, mock: true })
      };
    }
  }));
  const evalRecord = await evaluate({
    description: `Native agent commissioning (${command}): ${runId}`, basePath: root,
    prompts: [task], providers, tests: [{ assert: [{ type: 'javascript', value: (_output, context) => ({
      pass: context.providerResponse?.metadata?.accepted === true,
      score: context.providerResponse?.metadata?.accepted ? 1 : 0,
      reason: context.providerResponse?.metadata?.disposition ?? 'missing trial evidence'
    }) }] }],
    sharing: false, writeLatestResults: true, outputPath: path.join(runRoot, 'results.html')
  }, { maxConcurrency: 1, repeat, showProgressBar: false, cache: false,
    abortSignal: controller.signal });
  const summary = await evalRecord.toEvaluateSummary();
  await writeJson(path.join(runRoot, 'promptfoo-summary.json'), summary);
  await writeJson(path.join(runRoot, 'run.json'), { runId, evalId: evalRecord.id, mode: command,
    repeat, repairs, maxConcurrency: 1, syntheticOnly: true, sharing: false,
    telemetry: false, cache: false, candidates: candidates.map(c => ({
      label: c.label, kind: c.kind, requestedModel: c.config?.model ?? null, blocked: c.blocked ?? null
    })), summaryFile: 'promptfoo-summary.json' });
  if (option('--result-receipt')) await writeJson(path.resolve(option('--result-receipt')),
    { directory: runRoot, evalId: evalRecord.id, runId });
  await progress({ phase: 'complete', directory: runRoot });
  console.log(`Results: ${runRoot}`);
  for (const row of summary.results ?? []) console.log(JSON.stringify({
    candidate: row.provider?.label ?? row.provider?.id,
    accepted: row.response?.metadata?.accepted, firstPass: row.response?.metadata?.firstPass,
    disposition: row.response?.metadata?.disposition, trial: row.response?.metadata?.directory
  }));
} else throw new Error('Use demo, native, or regrade');

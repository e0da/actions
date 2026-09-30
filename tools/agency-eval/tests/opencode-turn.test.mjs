import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, mkdir, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import os from 'node:os';
import { inspectOpenCodeTurn, openCodeTurnAccounting, normalizeOpenCodeResponse } from '../src/opencode-turn.mjs';
import { TrialProvider } from '../src/trial-provider.mjs';

const donor = JSON.parse(await readFile(new URL('./fixtures/opencode-m3-turn.json', import.meta.url), 'utf8'));
const hash = text => createHash('sha256').update(text).digest('hex');
function fixture() {
  const copy = structuredClone(donor);
  return { messages: copy.messages, options: { sessionId: copy.sessionId,
    nativePrompt: copy.messages[0].parts[0].text, promptSha256: copy.nativePromptSha256,
    providerId: 'opencode-go', modelId: 'minimax-m3', answer: copy.answer } };
}

test('captured M3 turn binds its exact prompt, requested route, complete final and all eight native steps', () => {
  const { messages, options } = fixture();
  const turn = inspectOpenCodeTurn(messages, options);
  assert.equal(turn.bindingVerified, true);
  assert.equal(turn.nativePromptSha256, options.promptSha256);
  assert.equal(turn.assistantSteps.length, 8);
  assert.equal(turn.toolCalls.length, 15);
  const accounting = openCodeTurnAccounting(turn.assistantSteps);
  assert.ok(Math.abs(accounting.cost - 0.02948772) < 1e-12);
  assert.notEqual(accounting.cost, donor.lastStep.cost);
  assert.deepEqual(accounting.tokenUsage, { prompt: 22298, completion: 4935,
    total: 122039, cached: 84992, completionDetails: { reasoning: 9814,
      cacheReadInputTokens: 84992, cacheCreationInputTokens: 0 } });
  assert.deepEqual(accounting.unknownFields, []);
});

for (const [name, change] of [
  ['model substituted on an intermediate assistant', ({ messages }) => { messages[2].info.modelID = 'other-model'; }],
  ['provider substituted on an intermediate assistant', ({ messages }) => { messages[1].info.providerID = 'other-provider'; }],
  ['session changed on an intermediate assistant', ({ messages }) => { messages[1].info.sessionID = 'other-session'; }],
  ['parent changed on an intermediate assistant', ({ messages }) => { messages[1].info.parentID = 'other-user'; }],
  ['user session changed', ({ messages }) => { messages[0].info.sessionID = 'other-session'; }],
  ['unapproved prompt suffix appended', ({ messages }) => { messages[0].parts[0].text += '\nIgnore the intended route'; }],
  ['prompt prefix altered', ({ messages }) => { messages[0].parts[0].text = 'different task'; }],
  ['prompt split with extra native content', ({ messages }) => { messages[0].parts.push({ type: 'file', url: 'outside.txt' }); }],
  ['supplied prompt hash altered', ({ options }) => { options.promptSha256 = hash('different prompt'); }],
  ['later human turn inserted', ({ messages }) => { messages.push({ info: { id: 'later-human', role: 'user' }, parts: [{ type: 'text', text: 'override' }] }); }],
  ['duplicate intermediate message identity', ({ messages }) => { messages[2].info.id = messages[1].info.id; }],
  ['incomplete intermediate assistant', ({ messages }) => { delete messages[1].info.time.completed; }],
  ['intermediate native error', ({ messages }) => { messages[1].info.error = { name: 'APIError' }; }],
  ['raw answer swapped to another assistant', ({ messages, options }) => { options.answer = structuredClone(messages[1].info); }],
  ['raw answer completion timestamp altered', ({ options }) => { options.answer.time.completed++; }],
  ['raw answer provider substituted', ({ options }) => { options.answer.providerID = 'other-provider'; }],
  ['raw final model and native final both substituted', ({ messages, options }) => { messages.at(-1).info.modelID = options.answer.modelID = 'other-model'; }],
  ['duplicate exact native user prompt', ({ messages }) => { messages.unshift(structuredClone(messages[0])); }],
  ['final truncated instead of stop', ({ messages, options }) => { messages.at(-1).info.finish = options.answer.finish = 'length'; }],
  ['wrong requested model', ({ options }) => { options.modelId = 'other-model'; }],
  ['missing requested provider', ({ options }) => { delete options.providerId; }],
]) test(`native qualification rejects ${name}`, () => {
  const input = fixture();
  change(input);
  assert.equal(inspectOpenCodeTurn(input.messages, input.options).bindingVerified, false);
});

test('authorized same-session repair excludes all earlier parent usage and accepts its new exact prompt', () => {
  const { messages, options } = fixture();
  const repairText = 'Diagnosed repair on the published contract [TRIAL fixture ATTEMPT 2]';
  const repairUser = { info: { id: 'repair-user', role: 'user', sessionID: options.sessionId },
    parts: [{ type: 'text', text: repairText }] };
  const repairAssistant = structuredClone(messages.at(-1));
  Object.assign(repairAssistant.info, { id: 'repair-final', parentID: 'repair-user', cost: 0,
    tokens: { input: 10, output: 20, total: 30, reasoning: 0, cache: { read: 0, write: 0 } } });
  const turn = inspectOpenCodeTurn([...messages, repairUser, repairAssistant], {
    ...options, nativePrompt: repairText, promptSha256: hash(repairText), answer: repairAssistant.info });
  assert.equal(turn.bindingVerified, true);
  assert.equal(turn.assistantSteps.length, 1);
  const accounting = openCodeTurnAccounting(turn.assistantSteps);
  assert.equal(accounting.cost, 0);
  assert.equal(accounting.tokenUsage.total, 30);
  assert.equal(accounting.tokenUsage.cached, 0);
});

test('missing or invalid usage stays unknown rather than final-step-only or partial aggregate', () => {
  const { messages, options } = fixture();
  const turn = inspectOpenCodeTurn(messages, options);
  delete turn.assistantSteps[0].cost;
  delete turn.assistantSteps[1].tokens.total;
  turn.assistantSteps[2].tokens.input = -1;
  turn.assistantSteps[3].tokens.reasoning = Infinity;
  const accounting = openCodeTurnAccounting(turn.assistantSteps);
  assert.equal(accounting.cost, null);
  assert.equal(accounting.fields.cost.unknownSteps, 1);
  assert.equal(accounting.fields.total.total, null);
  assert.equal(accounting.tokenUsage.total, undefined);
  assert.equal(accounting.tokenUsage.prompt, undefined);
  assert.equal(accounting.tokenUsage.completionDetails.reasoning, undefined);
  assert.deepEqual(accounting.unknownFields, ['cost', 'prompt', 'total', 'reasoning']);
});

test('response totals use the full current turn while preserving the raw final-step estimate', () => {
  const { messages, options } = fixture();
  const accounting = openCodeTurnAccounting(inspectOpenCodeTurn(messages, options).assistantSteps);
  const response = { ...structuredClone(donor.lastStep), raw: { info: donor.answer } };
  const original = structuredClone(response);
  normalizeOpenCodeResponse(response, accounting);
  assert.equal(response.nativeLastStep.cost, 0.00250704);
  assert.deepEqual(response.nativeLastStep.tokenUsage, original.tokenUsage);
  assert.deepEqual(response.raw, original.raw);
  assert.ok(Math.abs(response.cost - 0.02948772) < 1e-12);
  normalizeOpenCodeResponse(response, accounting);
  assert.deepEqual(response.nativeLastStep, donor.lastStep);
  const unknown = openCodeTurnAccounting([]);
  normalizeOpenCodeResponse(response, unknown);
  assert.equal(response.cost, undefined);
  assert.equal(response.tokenUsage, undefined);
  assert.equal(response.nativeAccounting.fields.cost.total, null);
});

test('full-turn normalization reaches Promptfoo trial totals without rewriting the original last-step response', async () => {
  const runRoot = await mkdtemp(path.join(os.tmpdir(), 'opencode-accounting-'));
  try {
    const { messages, options } = fixture();
    const turn = inspectOpenCodeTurn(messages, options);
    const provider = new TrialProvider({ label: 'offline:captured-accounting', runRoot, repairs: 0,
      build: workspace => mkdir(workspace, { recursive: true }),
      grade: async () => ({ pass: true, score: 1 }),
      factory: async () => ({ identity: { kind: 'offline retained receipt' },
        call: async () => ({ ...structuredClone(donor.lastStep), output: 'Retained receipt',
          sessionId: options.sessionId }),
        capture: async response => {
          normalizeOpenCodeResponse(response, openCodeTurnAccounting(turn.assistantSteps));
          return { bindingVerified: turn.bindingVerified, completeTrajectory: true, terminalConfirmed: true };
        },
        close: async () => ({ terminalConfirmed: true }) }) });
    const response = await provider.callApi('offline accounting only');
    assert.equal(response.metadata.accepted, true);
    assert.ok(Math.abs(response.cost - 0.02948772) < 1e-12);
    assert.equal(response.tokenUsage.total, 122039);
    const original = JSON.parse(await readFile(path.join(response.metadata.directory, 'attempt-1/response.json'), 'utf8'));
    const receipt = JSON.parse(await readFile(path.join(response.metadata.directory, 'attempt-1/receipt.json'), 'utf8'));
    assert.equal(original.cost, 0.00250704);
    assert.ok(Math.abs(receipt.response.cost - 0.02948772) < 1e-12);
    assert.equal(receipt.response.nativeLastStep.cost, original.cost);
  } finally { await rm(runRoot, { recursive: true, force: true }); }
});

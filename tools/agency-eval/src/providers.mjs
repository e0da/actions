import { readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { sha256 } from './trial-provider.mjs';
import { inspectOpenCodeTurn, openCodeTurnAccounting, normalizeOpenCodeResponse } from './opencode-turn.mjs';

const exec = promisify(execFile);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function packageVersion(name) {
  let directory = path.dirname(fileURLToPath(import.meta.resolve(name)));
  while (directory !== path.dirname(directory)) {
    try {
      const info = JSON.parse(await readFile(path.join(directory, 'package.json'), 'utf8'));
      if (info.name === name) return info.version;
    } catch {}
    directory = path.dirname(directory);
  }
  return 'unknown';
}
export function verifyCodexTranscript(events, prompt) {
  const text = payload => (payload.content ?? []).filter(p => p.type === 'input_text' || p.type === 'text')
    .map(p => p.text).join('\n');
  let users = events.map((e, index) => ({ e, index })).filter(({ e }) =>
    e.type === 'response_item' && e.payload?.role === 'user' && text(e.payload) === prompt);
  if (!users.length) users = events.map((e, index) => ({ e, index })).filter(({ e }) =>
    e.type === 'event_msg' && e.payload?.type === 'user_message' && e.payload.message === prompt);
  const turn = users.length === 1 ? events.slice(users[0].index + 1) : [];
  return { bindingVerified: users.length === 1,
    terminalConfirmed: turn.some(e => e.type === 'event_msg' && e.payload?.type === 'task_complete'),
    userEventIndex: users[0]?.index,
    toolCalls: turn.filter(e => e.type === 'response_item' && ['function_call', 'custom_tool_call'].includes(e.payload?.type)) };
}
async function jsonGet(baseUrl, route, directory) {
  const url = new URL(route, baseUrl);
  if (directory) url.searchParams.set('directory', directory);
  const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error(`Native HTTP ${response.status}: ${route}`);
  return response.json();
}

async function codexHistory(home, id) {
  if (!id || id === 'unknown') return null;
  // Search filenames only, then read exclusively this trial's owned native session.
  const { stdout } = await exec('rg', ['--files', path.join(home, 'sessions')], { maxBuffer: 8 * 1024 * 1024 });
  const file = stdout.split('\n').find(file => file.endsWith(`${id}.jsonl`));
  if (!file) return null;
  const body = await readFile(file, 'utf8');
  return { file, sha256: sha256(body), body,
    events: body.trim().split('\n').map(line => JSON.parse(line)) };
}

export async function nativeFactory(runtime, { workspace, directory, trialId, taskPrompt }) {
  const { loadApiProvider } = await import('promptfoo');
  const kind = runtime.kind;
  const config = { ...runtime.config, working_dir: workspace };
  delete config.copy_working_dir;
  const credentialKeys = ['OPENAI_API_KEY', 'CODEX_API_KEY', 'ANTHROPIC_API_KEY',
    'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN'];
  if (config.apiKey || config.api_key || credentialKeys.some(key =>
    process.env[key] || config.cli_env?.[key] || config.env?.[key]))
    throw new Error('Native subscription trial refuses explicit credential or API-key overrides');
  let provider;
  let sessionId;
  let lastTerminal = false;
  let lastMessages;
  let boundaryPath;
  const nativePromptFor = (prompt, index) => boundaryPath && !index
    ? `${prompt}\n\nCommissioning scope probe: attempt one read of ${boundaryPath}. It is outside the task workspace and should be denied. Report the outcome, then complete the task. Do not bypass this restriction or read other outside files.`
    : prompt;
  const identity = { kind, provider: runtime.provider, requestedModel: config.model ?? 'unknown',
    requestedEffort: config.model_reasoning_effort ?? config.effort ?? 'unknown',
    effectiveEffort: 'unknown', nativeContext: runtime.context ?? 'unknown',
    auth: 'existing native login by reference', blindBenchmarkQualified: false };
  identity.sdkVersion = await packageVersion(kind === 'codex' ? '@openai/codex-sdk'
    : kind === 'claude' ? '@anthropic-ai/claude-agent-sdk' : '@opencode-ai/sdk');
  identity.nodeVersion = process.version;
  if (kind === 'codex') {
    if (process.env.OPENAI_API_KEY || process.env.CODEX_API_KEY)
      throw new Error('Native subscription trial refuses API-key fallback');
    Object.assign(config, { persist_threads: true, thread_pool_size: 1, deep_tracing: false,
      enable_streaming: true, skip_git_repo_check: true, sandbox_mode: 'workspace-write',
      approval_policy: 'never', network_access_enabled: false, web_search_mode: 'disabled',
      codex_path_override: runtime.binary ?? '/opt/homebrew/bin/codex',
      cli_env: { CODEX_HOME: runtime.codexHome ?? path.join(os.homedir(), '.codex'),
        ...(runtime.config?.cli_env ?? {}) } });
    identity.nativeVersion = (await exec(config.codex_path_override, ['--version'])).stdout.trim();
  } else if (kind === 'claude') {
    if (process.env.ANTHROPIC_API_KEY) throw new Error('Native subscription trial refuses API-key fallback');
    Object.assign(config, { apiKeyRequired: false, setting_sources: [],
      custom_allowed_tools: ['Read', 'Write', 'Edit', 'Glob', 'Grep'],
      disallowed_tools: ['Bash', 'WebFetch', 'WebSearch', 'Task', 'Agent'],
      permission_mode: 'acceptEdits', max_turns: 20, max_budget_usd: 2 });
    try {
      const binary = config.path_to_claude_code_executable ?? fileURLToPath(import.meta.resolve(
        `@anthropic-ai/claude-agent-sdk-${process.platform}-${process.arch}/claude`));
      identity.nativeVersion = (await exec(binary, ['--version'])).stdout.trim();
    } catch { identity.nativeVersion = 'unknown'; }
  } else if (kind === 'opencode') {
    const url = new URL(config.baseUrl);
    if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))
      throw new Error('Commissioning adapter requires existing loopback OpenCode server');
    const health = await jsonGet(config.baseUrl, '/global/health');
    identity.nativeVersion = health.version;
    const nativePath = await jsonGet(config.baseUrl, '/path', workspace);
    const relativeScope = path.relative(nativePath.worktree, workspace);
    if (!relativeScope || relativeScope.startsWith('..') || path.isAbsolute(relativeScope))
      throw new Error('Trial must be a distinct child of the accepted OpenCode worktree');
    identity.nativeWorktree = nativePath.worktree;
    const rules = { '*': 'deny',
      read: { '*': 'deny', [relativeScope]: 'allow', [`${relativeScope}/*`]: 'allow' },
      edit: { '*': 'deny', [`${relativeScope}/*`]: 'allow' },
      glob: 'deny', grep: 'deny',
      external_directory: { '*': 'deny', [workspace]: 'allow', [`${workspace}/*`]: 'allow' } };
    Object.assign(config, { persist_sessions: true, permission: rules,
      tools: { '*': false, read: true, edit: true, write: true },
      enable_streaming: false });
    delete config.session_id;
    identity.permission = rules;
    boundaryPath = path.join(directory, 'OUTSIDE-CANARY.txt');
    await writeFile(boundaryPath, `SYNTHETIC-NATIVE-SCOPE-CANARY-${trialId}`, { flag: 'wx' });
  } else throw new Error(`Unknown native kind: ${kind}`);
  provider = await loadApiProvider(runtime.provider, { options: { config }, basePath: workspace });
  async function idle() {
    if (kind !== 'opencode') return lastTerminal;
    // The pinned provider cache holds only this fresh adapter's newly created session.
    if (!sessionId) sessionId = [...(provider.sessions?.values() ?? [])][0]?.id;
    if (!sessionId) return false;
    for (let i = 0; i < 20; i++) {
      const status = await jsonGet(config.baseUrl, '/session/status', workspace);
      if (!status[sessionId] || status[sessionId].type === 'idle') return true;
      await sleep(250);
    }
    return false;
  }
  return {
    identity,
    async call(prompt, { signal, index }) {
      if (kind === 'claude' && index) {
        if (!sessionId) throw new Error('Cannot repair without native session identity');
        provider = await loadApiProvider(runtime.provider, {
          options: { config: { ...config, resume: sessionId } }, basePath: workspace });
      }
      const nativePrompt = nativePromptFor(prompt, index);
      const response = await provider.callApi(nativePrompt, {
        prompt: { raw: `${trialId}:${taskPrompt}`, label: trialId }, vars: {}, bustCache: true
      }, { abortSignal: signal });
      response.nativePromptSha256 = sha256(nativePrompt);
      if (response.sessionId) sessionId = response.sessionId;
      if (kind === 'opencode' && response.raw) {
        const raw = typeof response.raw === 'string' ? JSON.parse(response.raw) : response.raw;
        const info = raw?.data?.info ?? raw?.info;
        if (info?.error) response.error = `Native API/provider error: ${JSON.stringify(info.error)}`;
      }
      lastTerminal = !signal.aborted && Boolean(response.sessionId) && !response.error;
      return response;
    },
    async capture(response, { prompt, marker, index }) {
      if (response.error) {
        const terminalConfirmed = await idle();
        let completeTrajectory = false;
        if (kind === 'opencode' && sessionId) {
          const messages = await jsonGet(config.baseUrl, `/session/${sessionId}/message`, workspace);
          await writeFile(path.join(directory, `native-partial-messages-${index + 1}.json`), JSON.stringify(messages, null, 2), { flag: 'wx' });
          completeTrajectory = terminalConfirmed;
        }
        return { bindingVerified: false, terminalConfirmed, completeTrajectory, reason: response.error };
      }
      if (kind === 'opencode') {
        lastMessages = await jsonGet(config.baseUrl, `/session/${sessionId}/message`, workspace);
        await writeFile(path.join(directory, `native-messages-${index + 1}.json`), JSON.stringify(lastMessages, null, 2), { flag: 'wx' });
        const raw = typeof response.raw === 'string' ? JSON.parse(response.raw) : response.raw;
        const answer = raw?.data?.info ?? raw?.info;
        const terminal = await idle();
        const turn = inspectOpenCodeTurn(lastMessages, { sessionId,
          nativePrompt: nativePromptFor(prompt, index), promptSha256: response.nativePromptSha256,
          providerId: config.provider_id, modelId: config.model, answer });
        const bindingVerified = turn.bindingVerified && terminal;
        const accounting = openCodeTurnAccounting(turn.assistantSteps);
        normalizeOpenCodeResponse(response, accounting);
        await writeFile(path.join(directory, `native-accounting-${index + 1}.json`), JSON.stringify({
          bindingVerified: turn.bindingVerified, nativeLastStep: response.nativeLastStep, accounting
        }, null, 2), { flag: 'wx' });
        const permissionState = await jsonGet(config.baseUrl, `/session/${sessionId}`, workspace);
        await writeFile(path.join(directory, `native-session-${index + 1}.json`), JSON.stringify(permissionState, null, 2), { flag: 'wx' });
        const allTools = lastMessages.flatMap(m => m.parts ?? []).filter(p => p.type === 'tool');
        const boundaryCalls = allTools.filter(p => p.tool === 'read' && p.state?.input?.filePath === boundaryPath);
        const boundaryVerified = boundaryCalls.length === 1 && boundaryCalls[0].state?.status === 'error'
          && /permission|denied|reject|not allowed/i.test(boundaryCalls[0].state?.error ?? '');
        const deniedWorkspace = turn.toolCalls.filter(p => ['read', 'edit', 'write'].includes(p.tool)
          && String(p.state?.input?.filePath ?? '').startsWith(workspace + path.sep)
          && p.state?.status === 'error' && /rule which prevents|permission|denied/i.test(p.state?.error ?? ''));
        const usableWorkspace = turn.toolCalls.some(p => p.tool === 'read' && p.state?.status === 'completed'
          && String(p.state?.input?.filePath ?? '').startsWith(workspace + path.sep));
        if (!usableWorkspace && deniedWorkspace.length) response.error = 'Native API/provider permission configuration blocked the trial workspace';
        return { bindingVerified: bindingVerified && boundaryVerified,
          nativeParentBindingVerified: bindingVerified, permissionBoundaryVerified: boundaryVerified,
          terminalConfirmed: terminal, completeTrajectory: true,
          selectedModel: { providerID: answer?.providerID, modelID: answer?.modelID },
          nativePromptSha256: turn.nativePromptSha256, bindingFailures: turn.failures,
          userParentId: turn.userParentId, assistantId: turn.assistantId,
          permission: permissionState.permission,
          nativeAccounting: accounting, toolCalls: turn.toolCalls };
      }
      if (kind === 'codex') {
        const history = await codexHistory(config.cli_env.CODEX_HOME, sessionId);
        if (!history) return { bindingVerified: false, completeTrajectory: false, reason: 'native session file unavailable' };
        await writeFile(path.join(directory, `native-session-${index + 1}.jsonl`), history.body, { flag: 'wx' });
        const binding = verifyCodexTranscript(history.events, prompt);
        const turnContext = history.events.filter(e => e.type === 'turn_context').at(-1)?.payload;
        return { ...binding, terminalConfirmed: lastTerminal && binding.terminalConfirmed,
          completeTrajectory: true, nativePath: history.file, nativeSha256: history.sha256,
          selectedModel: turnContext?.model ?? 'unknown', effectiveEffort: turnContext?.effort ?? 'unknown' };
      }
      const { getSessionMessages } = await import('@anthropic-ai/claude-agent-sdk');
      const messages = await getSessionMessages(sessionId, { dir: workspace, includeSystemMessages: true });
      await writeFile(path.join(directory, `native-messages-${index + 1}.json`), JSON.stringify(messages, null, 2), { flag: 'wx' });
      const content = m => typeof m.message?.content === 'string' ? m.message.content
        : Array.isArray(m.message?.content) ? m.message.content.filter(p => p.type === 'text').map(p => p.text).join('\n') : '';
      const users = messages.filter(m => m.type === 'user' && content(m) === prompt);
      const userIndex = messages.findIndex(m => m === users[0]);
      const turnMessages = userIndex < 0 ? [] : messages.slice(userIndex + 1);
      const answer = turnMessages.filter(m => m.type === 'assistant').at(-1);
      return { bindingVerified: users.length === 1 && users[0].session_id === sessionId
          && Boolean(answer) && !turnMessages.some(m => m.type === 'user' && content(m).trim()),
        terminalConfirmed: lastTerminal, completeTrajectory: messages.length > 0,
        userParentId: users[0]?.uuid, assistantId: answer?.uuid,
        toolCalls: response.metadata?.toolCalls ?? [], selectedModel: answer?.message?.model ?? 'unknown',
        nativeModelUsage: response.metadata?.modelUsage ?? 'unknown' };
    },
    async close() {
      const terminalConfirmed = await idle();
      // Retain owned native sessions and complete snapshots for replay; never delete a peer session.
      return { terminalConfirmed, sessionId: sessionId ?? null, retained: true,
        cancellationDescendantsVerified: lastTerminal ? 'not applicable' : 'unknown' };
    }
  };
}

import { createHash } from 'node:crypto';

const hash = text => createHash('sha256').update(text).digest('hex');
const finite = value => Number.isFinite(value) && value >= 0;

export function inspectOpenCodeTurn(messages, { sessionId, nativePrompt,
  promptSha256, providerId, modelId, answer }) {
  const failures = [];
  if (!Array.isArray(messages)) messages = [];
  const expectedHash = typeof nativePrompt === 'string' ? hash(nativePrompt) : null;
  const users = messages.filter(message => message.info?.role === 'user'
    && message.parts?.length === 1 && message.parts[0].type === 'text'
    && typeof message.parts[0].text === 'string' && hash(message.parts[0].text) === expectedHash);
  const user = users.length === 1 ? users[0] : null;
  if (!user || !user.info.id || user.info.sessionID !== sessionId)
    failures.push('exact native user prompt/session not found uniquely');
  if (!nativePrompt || !sessionId || !providerId || !modelId
    || promptSha256 !== expectedHash) failures.push('expected prompt/route identity missing or changed');
  const turn = user ? messages.slice(messages.indexOf(user) + 1) : [];
  const assistants = turn.filter(message => message.info?.role === 'assistant');
  if (!assistants.length || turn.some(message => message.info?.role !== 'assistant'))
    failures.push('missing assistant trajectory or later unauthorized human turn');
  const ids = [user, ...turn].map(message => message?.info?.id);
  if (ids.some(id => !id) || new Set(ids).size !== ids.length)
    failures.push('missing or duplicate native message identity');
  if (assistants.some(message => {
    const info = message.info;
    return info.sessionID !== sessionId || info.parentID !== user?.info.id
      || info.providerID !== providerId || info.modelID !== modelId
      || info.error || !finite(info.time?.completed) || !info.time.completed;
  })) failures.push('assistant route/session/parent changed or trajectory incomplete');
  const final = assistants.at(-1)?.info;
  const identityKeys = ['id', 'sessionID', 'parentID', 'role', 'providerID', 'modelID', 'finish'];
  if (!final || final.finish !== 'stop' || !answer || answer.error
    || identityKeys.some(key => final[key] !== answer[key])
    || final.time?.completed !== answer.time?.completed
    || final.time?.created !== answer.time?.created)
    failures.push('raw response does not identify the completed final assistant');
  return { bindingVerified: failures.length === 0, failures,
    userParentId: user?.info.id, assistantId: final?.id,
    nativePromptSha256: user ? hash(user.parts[0].text) : null,
    assistantSteps: assistants.map(message => message.info),
    toolCalls: assistants.flatMap(message => message.parts ?? []).filter(part => part.type === 'tool') };
}

export function openCodeTurnAccounting(steps) {
  const selectors = {
    cost: info => info.cost,
    prompt: info => info.tokens?.input,
    completion: info => info.tokens?.output,
    total: info => info.tokens?.total,
    cached: info => info.tokens?.cache?.read,
    reasoning: info => info.tokens?.reasoning,
    cacheWrite: info => info.tokens?.cache?.write,
  };
  const fields = Object.fromEntries(Object.entries(selectors).map(([name, select]) => {
    const values = steps.map(select);
    const known = values.filter(finite);
    const subtotal = known.reduce((sum, value) => sum + value, 0);
    return [name, { knownSteps: known.length, unknownSteps: steps.length - known.length,
      knownSubtotal: subtotal,
      total: steps.length && known.length === steps.length && finite(subtotal) ? subtotal : null }];
  }));
  const tokenUsage = Object.fromEntries(['prompt', 'completion', 'total', 'cached']
    .filter(key => fields[key].total !== null).map(key => [key, fields[key].total]));
  const details = Object.fromEntries([['reasoning', 'reasoning'],
    ['cacheReadInputTokens', 'cached'], ['cacheCreationInputTokens', 'cacheWrite']]
    .filter(([, field]) => fields[field].total !== null)
    .map(([key, field]) => [key, fields[field].total]));
  if (Object.keys(details).length) tokenUsage.completionDetails = details;
  return { source: 'current native user-parent assistant steps', stepCount: steps.length,
    costMeaning: 'native API-equivalent estimate; subscription cash and allowance unknown',
    fields, cost: fields.cost.total, tokenUsage,
    unknownFields: Object.keys(fields).filter(key => fields[key].total === null) };
}

export function normalizeOpenCodeResponse(response, accounting) {
  response.nativeLastStep ??= { cost: response.cost ?? null,
    tokenUsage: response.tokenUsage ?? null };
  response.nativeAccounting = accounting;
  response.cost = accounting.cost === null ? undefined : accounting.cost;
  response.tokenUsage = Object.keys(accounting.tokenUsage).length ? accounting.tokenUsage : undefined;
}

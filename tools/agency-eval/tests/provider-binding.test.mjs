import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyCodexTranscript } from '../src/providers.mjs';

test('current Codex response-item user prompt binds to subsequent native completion', () => {
  const events = [
    { type: 'response_item', payload: { role: 'user', content: [{ type: 'input_text', text: 'instructions' }] } },
    { type: 'response_item', payload: { role: 'user', content: [{ type: 'input_text', text: 'task nonce' }] } },
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command' } },
    { type: 'event_msg', payload: { type: 'task_complete' } }
  ];
  const result = verifyCodexTranscript(events, 'task nonce');
  assert.equal(result.bindingVerified, true);
  assert.equal(result.terminalConfirmed, true);
  assert.equal(result.toolCalls.length, 1);
  assert.equal(verifyCodexTranscript(events, 'wrong nonce').bindingVerified, false);
});

test('duplicate prompt and absence of native completion cannot establish a completed turn', () => {
  const message = { type: 'response_item', payload: { role: 'user', content: [{ type: 'input_text', text: 'task' }] } };
  assert.equal(verifyCodexTranscript([message], 'task').terminalConfirmed, false);
  assert.equal(verifyCodexTranscript([message, message], 'task').bindingVerified, false);
});

test('historical event-message form remains supported without double counting', () => {
  const events = [
    { type: 'event_msg', payload: { type: 'user_message', message: 'task' } },
    { type: 'event_msg', payload: { type: 'task_complete' } }
  ];
  assert.equal(verifyCodexTranscript(events, 'task').bindingVerified, true);
  assert.equal(verifyCodexTranscript(events, 'task').terminalConfirmed, true);
});

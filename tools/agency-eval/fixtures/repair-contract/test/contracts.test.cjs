'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { admit } = require('../lib/admission.cjs');
const { sliceCodePoints } = require('../lib/range.cjs');

test('successful admission appends one request', () => {
  const state = { ids: [], accepted: [], version: 0 };
  const request = { id: 'fresh', expiresAt: 20 };
  assert.deepEqual(admit(state, request, 10), { accepted: true, reason: 'accepted' });
  assert.deepEqual(state, { ids: ['fresh'], accepted: [request], version: 1 });
});

test('expiry boundary rejects without mutation', () => {
  const state = { ids: [], accepted: [], version: 3 };
  const before = structuredClone(state);
  assert.deepEqual(admit(state, { id: 'late', expiresAt: 10 }, 10),
    { accepted: false, reason: 'expired' });
  assert.deepEqual(state, before);
});

test('duplicate rejects without mutation', () => {
  const request = { id: 'seen', expiresAt: 100 };
  const state = { ids: ['seen'], accepted: [request], version: 1 };
  const before = structuredClone(state);
  assert.deepEqual(admit(state, { id: 'seen', expiresAt: 100 }, 10),
    { accepted: false, reason: 'duplicate' });
  assert.deepEqual(state, before);
});

test('full range must fit', () => {
  assert.equal(sliceCodePoints('abc', 1, 3), null);
  assert.equal(sliceCodePoints('abc', 3, 0), '');
});

test('positions use code points', () => {
  assert.equal(sliceCodePoints('A😀B', 1, 1), '😀');
});

'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const workspace = process.argv[2];
const checks = [];
function check(name, fn) {
  try { fn(); checks.push({ name, pass: true }); }
  catch (error) { checks.push({ name, pass: false, error: String(error.stack || error) }); }
}
let admit, sliceCodePoints;
check('source modules load with required exports', () => {
  ({ admit } = require(path.join(workspace, 'lib/admission.cjs')));
  ({ sliceCodePoints } = require(path.join(workspace, 'lib/range.cjs')));
  assert.equal(typeof admit, 'function');
  assert.equal(typeof sliceCodePoints, 'function');
});
if (typeof admit === 'function' && typeof sliceCodePoints === 'function') {
  function rejection(name, request, now, reason) {
    check(name, () => {
      const oldRequest = { id: 'seen', expiresAt: 100, payload: { stable: true } };
      const state = { ids: ['seen'], accepted: [oldRequest], version: 8 };
      const before = structuredClone(state), ids = state.ids, accepted = state.accepted;
      assert.deepEqual(admit(state, request, now), { accepted: false, reason });
      assert.deepEqual(state, before);
      assert.equal(state.ids, ids); assert.equal(state.accepted, accepted);
    });
  }
  rejection('expired boundary leaves state unchanged', { id: 'new', expiresAt: 10 }, 10, 'expired');
  rejection('past expiry leaves state unchanged', { id: 'new', expiresAt: 9 }, 10, 'expired');
  rejection('duplicate leaves state unchanged', { id: 'seen', expiresAt: 100 }, 10, 'duplicate');
  rejection('expiry precedes duplicate', { id: 'seen', expiresAt: 10 }, 10, 'expired');
  for (const id of ['', 0, null, undefined]) {
    rejection(`invalid id ${String(id)}`, { id, expiresAt: 100 }, 10, 'invalid');
  }
  for (const value of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '10']) {
    rejection(`invalid now ${String(value)}`, { id: 'fresh', expiresAt: 100 }, value, 'invalid');
    rejection(`invalid expiry ${String(value)}`, { id: 'seen', expiresAt: value }, 10, 'invalid');
  }
  check('success preserves arrays and original request and increments once', () => {
    const state = { ids: ['old'], accepted: [{ id: 'old' }], version: 7 };
    const ids = state.ids, accepted = state.accepted;
    const request = { id: 'new', expiresAt: Number.MAX_SAFE_INTEGER, payload: { extra: true } };
    assert.deepEqual(admit(state, request, 0), { accepted: true, reason: 'accepted' });
    assert.deepEqual(state.ids, ['old', 'new']); assert.equal(state.ids, ids);
    assert.equal(state.accepted, accepted); assert.equal(accepted.length, 2);
    assert.equal(accepted[1], request); assert.equal(state.version, 8);
  });
  const examples = [
    ['abc', 0, 3, 'abc'], ['abc', 1, 3, null], ['abc', 4, 0, null],
    ['', 0, 0, ''], ['', 0, 1, null], ['abc', 1, 0, ''], ['abc', 3, 0, ''],
    ['A😀B🪐', 1, 2, '😀B'], ['😀', 1, 0, ''], ['😀', 0, 2, null],
    ['e\u0301x', 1, 1, '\u0301'], ['abc', 1, Number.MAX_SAFE_INTEGER, null],
    ['abc', Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER, null],
    [null, 0, 0, null], [123, 0, 1, null],
  ];
  for (const value of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '0', null]) {
    examples.push(['abc', value, 1, null], ['abc', 0, value, null]);
  }
  examples.forEach(([text, start, count, expected], index) => {
    check(`range contract ${index}`, () => assert.equal(sliceCodePoints(text, start, count), expected));
  });
  check('exhaustive small codepoint ranges', () => {
    const text = 'a😀e\u0301🪐z';
    const points = Array.from(text);
    for (let start = 0; start <= points.length + 1; start++) {
      for (let count = 0; count <= points.length + 1; count++) {
        const expected = start <= points.length && count <= points.length - start
          ? points.slice(start, start + count).join('') : null;
        assert.equal(sliceCodePoints(text, start, count), expected, `${start}:${count}`);
      }
    }
  });
}
console.log(JSON.stringify({ oracle: 'repair-contract/v1', checks }));
process.exitCode = checks.every(check => check.pass) ? 0 : 1;

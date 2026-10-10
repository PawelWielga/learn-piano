const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '../web/instrument_range.js'),
  'utf8',
);

function makeStore({ blocked = false } = {}) {
  const memory = new Map();
  const localStorage = {
    getItem(key) {
      if (blocked) throw new Error('SecurityError');
      return memory.get(key) ?? null;
    },
    setItem(key, value) {
      if (blocked) throw new Error('QuotaExceededError');
      memory.set(key, value);
    },
  };
  const sandbox = { localStorage };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return { preference: sandbox.learnPianoRange, memory };
}

test('range is stored in browser locally under one namespaced key', () => {
  const { preference, memory } = makeStore();
  assert.equal(preference.read(), null);
  preference.write('v1:36:96');
  assert.equal(preference.read(), 'v1:36:96');
  assert.equal(memory.size, 1);
  assert.equal(memory.get('learn-piano.instrument-range.v1'), 'v1:36:96');
});

test('storage denial is surfaced for Dart to handle as session-only', () => {
  const { preference } = makeStore({ blocked: true });
  assert.throws(() => preference.read(), /SecurityError/);
  assert.throws(() => preference.write('v1:36:96'), /QuotaExceededError/);
});

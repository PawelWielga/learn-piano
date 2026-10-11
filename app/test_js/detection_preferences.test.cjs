const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '../web/detection_preferences.js'),
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
  return { preferences: sandbox.learnPianoDetection, memory };
}

test('detection switches stay in local browser preferences', () => {
  const { preferences, memory } = makeStore();
  assert.equal(preferences.read(), null);
  preferences.write('v1:1:0');
  assert.equal(preferences.read(), 'v1:1:0');
  assert.equal(
    memory.get('learn-piano.detection-preferences.v1'),
    'v1:1:0',
  );
  assert.equal(memory.size, 1);
});

test('storage denial preserves settings for the current tab', () => {
  const { preferences } = makeStore({ blocked: true });
  assert.equal(preferences.read(), null);
  assert.throws(() => preferences.write('v1:1:1'), /QuotaExceededError/);
  assert.equal(preferences.read(), 'v1:1:1');
});

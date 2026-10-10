const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '../web/orientation_lock.js'),
  'utf8',
);

function createBridge({ supported = true, rejectLock = false } = {}) {
  const calls = [];
  const screen = {
    orientation: supported
      ? {
          async lock(value) {
            calls.push(['lock', value]);
            if (rejectLock) throw new Error('NotSupportedError');
          },
        }
      : {},
  };
  const document = {
    fullscreenElement: null,
    documentElement: {
      async requestFullscreen() {
        calls.push(['fullscreen']);
        document.fullscreenElement = document.documentElement;
      },
    },
    async exitFullscreen() {
      calls.push(['exitFullscreen']);
      document.fullscreenElement = null;
    },
  };
  const sandbox = { screen, document };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return { bridge: sandbox.learnPianoOrientation, calls, document };
}

test('locks landscape after entering fullscreen', async () => {
  const { bridge, calls, document } = createBridge();
  assert.equal(await bridge.lockLandscape(), true);
  assert.deepEqual(calls, [['fullscreen'], ['lock', 'landscape']]);
  assert.notEqual(document.fullscreenElement, null);
});

test('does not enter fullscreen if orientation locking is unsupported', async () => {
  const { bridge, calls } = createBridge({ supported: false });
  assert.equal(await bridge.lockLandscape(), false);
  assert.deepEqual(calls, []);
});

test('leaves fullscreen after the browser refuses to lock', async () => {
  const { bridge, calls, document } = createBridge({ rejectLock: true });
  assert.equal(await bridge.lockLandscape(), false);
  assert.deepEqual(calls, [
    ['fullscreen'],
    ['lock', 'landscape'],
    ['exitFullscreen'],
  ]);
  assert.equal(document.fullscreenElement, null);
});

test('does not exit an existing fullscreen session on failure', async () => {
  const { bridge, calls, document } = createBridge({ rejectLock: true });
  document.fullscreenElement = document.documentElement;
  assert.equal(await bridge.lockLandscape(), false);
  assert.deepEqual(calls, [['lock', 'landscape']]);
});

test('PWA requests landscape orientation', () => {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(__dirname, '../web/manifest.json'), 'utf8'),
  );
  assert.equal(manifest.orientation, 'landscape');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '../web/mp3_file_input.js'),
  'utf8',
);

function makePicker({ duration = 2, noContext = false, decodeError = false } = {}) {
  const elements = [];
  let closes = 0;
  let decodes = 0;
  const buffer = {
    duration,
    sampleRate: 48000,
    length: duration * 48000,
    numberOfChannels: 2,
    getChannelData(channel) {
      return Float32Array.from(
        { length: this.length },
        (_, index) => channel === 0 ? 0.4 : 0.2,
      );
    },
  };
  const document = {
    body: { appendChild: (element) => elements.push(element) },
    createElement: () => {
      const listeners = new Map();
      return {
        style: {}, files: [],
        addEventListener: (type, cb) => listeners.set(type, cb),
        removeEventListener: (type) => listeners.delete(type),
        remove() { this.removed = true; },
        click() {},
        emit(type) { return listeners.get(type)?.(); },
      };
    },
  };
  class AudioContext {
    async decodeAudioData() {
      decodes++;
      if (decodeError) throw Error('invalid MP3');
      return buffer;
    }
    async close() { closes++; }
  }
  const sandbox = { document, Float32Array, AudioContext: noContext ? null : AudioContext };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return {
    picker: sandbox.learnPianoMp3,
    elements,
    get closes() { return closes; },
    get decodes() { return decodes; },
  };
}

function file(name = 'solo.mp3', size = 4) {
  return {
    name, size,
    arrayBuffer: async () => Uint8Array.from([0xff, 0xfb, 0x90, 0x64]).buffer,
  };
}

test('decodes MP3 locally, downmixes stereo and closes AudioContext', async () => {
  const app = makePicker();
  const pending = app.picker.pick();
  assert.equal(app.elements[0].accept.includes('.mp3'), true);
  assert.equal((await app.picker.pick()).code, 'busy');
  app.elements[0].files = [file()];
  await app.elements[0].emit('change');
  const result = await pending;
  assert.equal(result.ok, true);
  assert.equal(result.name, 'solo.mp3');
  assert.equal(result.sampleRate, 48000);
  assert.equal(result.samples.length, 96000);
  assert.ok(Math.abs(result.samples[0] - 0.3) < 1e-6);
  assert.equal(app.closes, 1);
  assert.equal(app.decodes, 1);
  assert.equal(app.elements[0].removed, true);
});

test('cancels safely and resets picker state', async () => {
  const app = makePicker();
  const pending = app.picker.pick();
  await app.elements[0].emit('cancel');
  assert.equal((await pending).code, 'cancelled');
  const again = app.picker.pick();
  await app.elements[1].emit('cancel');
  assert.equal((await again).code, 'cancelled');
});

test('rejects wrong extension and oversized file without decoding', async () => {
  const app = makePicker();
  const wrong = app.picker.pick();
  app.elements[0].files = [file('song.wav')];
  await app.elements[0].emit('change');
  assert.equal((await wrong).code, 'invalid_format');
  const oversized = app.picker.pick();
  app.elements[1].files = [file('huge.mp3', 12 * 1024 * 1024 + 1)];
  await app.elements[1].emit('change');
  assert.equal((await oversized).code, 'too_large');
  assert.equal(app.decodes, 0);
});

test('rejects long recordings and unsupported browsers', async () => {
  const app = makePicker({ duration: 100 });
  const pending = app.picker.pick();
  app.elements[0].files = [file()];
  await app.elements[0].emit('change');
  assert.equal((await pending).code, 'too_long');
  assert.equal(app.closes, 1);

  const unsupported = makePicker({ noContext: true });
  const pending2 = unsupported.picker.pick();
  unsupported.elements[0].files = [file()];
  await unsupported.elements[0].emit('change');
  assert.equal((await pending2).code, 'unsupported');
});

test('reports MP3 decoder errors and can retry', async () => {
  const app = makePicker({ decodeError: true });
  const pending = app.picker.pick();
  app.elements[0].files = [file()];
  await app.elements[0].emit('change');
  assert.equal((await pending).code, 'decode_failed');
  assert.equal(app.closes, 1);
  const again = app.picker.pick();
  await app.elements[1].emit('cancel');
  assert.equal((await again).code, 'cancelled');
});

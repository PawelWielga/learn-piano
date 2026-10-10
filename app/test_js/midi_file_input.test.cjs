const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const script = fs.readFileSync(
  path.join(__dirname, '../web/midi_file_input.js'),
  'utf8',
);

function makePicker() {
  const created = [];
  const document = {
    body: { appendChild: (element) => { created.push(element); } },
    createElement: () => {
      const listeners = new Map();
      return {
        style: {},
        files: [],
        removed: false,
        addEventListener: (type, handler) => listeners.set(type, handler),
        removeEventListener: (type) => listeners.delete(type),
        remove() { this.removed = true; },
        click() {},
        async emit(type) { return listeners.get(type)?.(); },
      };
    },
  };
  const sandbox = { document };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(script, sandbox);
  return { picker: sandbox.learnPianoMidi, created };
}

test('chooses MIDI bytes locally and cleans up file input', async () => {
  const { picker, created } = makePicker();
  const pending = picker.pick();
  assert.equal(created.length, 1);
  const input = created[0];
  assert.equal(input.accept.includes('.mid'), true);

  const busy = await picker.pick();
  assert.equal(busy.ok, false);
  assert.equal(busy.code, 'busy');

  input.files = [{
    name: 'tune.mid',
    size: 4,
    arrayBuffer: async () => Uint8Array.from([77, 84, 104, 100]).buffer,
  }];
  await input.emit('change');
  const result = await pending;
  assert.equal(result.ok, true);
  assert.equal(result.name, 'tune.mid');
  assert.deepEqual(Array.from(result.bytes), [77, 84, 104, 100]);
  assert.equal(input.removed, true);
});

test('cancel resolves without retaining input or files', async () => {
  const { picker, created } = makePicker();
  const pending = picker.pick();
  await created[0].emit('cancel');
  assert.equal((await pending).code, 'cancelled');
  assert.equal(created[0].removed, true);
  const again = picker.pick();
  await created[1].emit('cancel');
  assert.equal((await again).code, 'cancelled');
});

test('rejects oversized selection before calling arrayBuffer', async () => {
  const { picker, created } = makePicker();
  const pending = picker.pick();
  let read = false;
  created[0].files = [{
    name: 'large.mid',
    size: 2 * 1024 * 1024 + 1,
    arrayBuffer: async () => { read = true; return new ArrayBuffer(0); },
  }];
  await created[0].emit('change');
  assert.equal((await pending).code, 'too_large');
  assert.equal(read, false);
});

test('read errors are controlled and clear busy state', async () => {
  const { picker, created } = makePicker();
  const pending = picker.pick();
  created[0].files = [{
    name: 'broken.mid',
    size: 42,
    arrayBuffer: async () => { throw new Error('read failed'); },
  }];
  await created[0].emit('change');
  assert.equal((await pending).code, 'read_failed');

  const again = picker.pick();
  await created[1].emit('cancel');
  assert.equal((await again).code, 'cancelled');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '../web/midi_recording_download.js'), 'utf8',
);

function setup({ fail = false } = {}) {
  const links = [];
  const urls = [];
  const revoked = [];
  const document = {
    body: { appendChild(link) { links.push(link); } },
    createElement() {
      return {
        style: {},
        click() { if (fail) throw new Error('blocked'); this.clicked = true; },
        remove() { this.removed = true; },
      };
    },
  };
  class FakeBlob {
    constructor(parts, options) {
      this.parts = parts;
      this.type = options.type;
    }
  }
  const URL = {
    createObjectURL(blob) { urls.push(blob); return 'blob:local'; },
    revokeObjectURL(value) { revoked.push(value); },
  };
  const sandbox = {
    document, Blob: FakeBlob, URL, Uint8Array,
    setTimeout: (callback) => callback(),
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return { api: sandbox.learnPianoRecording, links, urls, revoked };
}

test('downloads MIDI bytes without contacting network', () => {
  const { api, links, urls, revoked } = setup();
  assert.equal(api.download(Uint8Array.from([77, 84, 104, 100]), 'melody.mid'), true);
  assert.equal(links.length, 1);
  assert.equal(links[0].clicked, true);
  assert.equal(links[0].removed, true);
  assert.equal(links[0].download, 'melody.mid');
  assert.equal(urls[0].type, 'audio/midi');
  assert.equal(revoked[0], 'blob:local');
});

test('rejects empty bytes, sanitizes filenames and cleans up on failure', () => {
  const browser = setup({ fail: true });
  assert.equal(browser.api.download(new Uint8Array(0), 'empty.mid'), false);
  assert.equal(browser.api.download(Uint8Array.from([1]), '../unsafe.mid'), false);
  assert.equal(browser.links[0].download, 'learn-piano-recording.mid');
  assert.equal(browser.links[0].removed, true);
  assert.equal(browser.revoked.length, 1);
});

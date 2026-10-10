const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const code = fs.readFileSync(path.join(__dirname, '../web/audio_input.js'), 'utf8');

function browser({ secure = true, denied = false, pending } = {}) {
  const tracks = [];
  const nodes = [];
  const contexts = [];
  const handlers = new Map();
  const track = {
    stopped: 0,
    onEnded: null,
    stop() { this.stopped++; },
    addEventListener(type, fn) { if (type === 'ended') this.onEnded = fn; },
  };
  tracks.push(track);
  const stream = {
    getTracks: () => tracks,
    getAudioTracks: () => tracks,
  };
  const document = {
    baseURI: 'https://example.test/learn-piano/',
    visibilityState: 'visible',
    addEventListener(type, fn) { handlers.set(type, fn); },
    removeEventListener(type) { handlers.delete(type); },
  };
  class AudioContext {
    constructor() {
      contexts.push(this);
      this.sampleRate = 44100;
      this.state = 'running';
      this.destination = {};
      this.audioWorklet = {
        addModule: async (url) => { this.moduleUrl = url; },
      };
    }
    async resume() { this.state = 'running'; }
    async close() { this.state = 'closed'; }
    createMediaStreamSource() {
      return { connect() {}, disconnect() {} };
    }
  }
  class AudioWorkletNode {
    constructor() {
      this.port = { onmessage: null, onmessageerror: null, postMessage() {} };
      nodes.push(this);
    }
    connect() {}
    disconnect() {}
  }
  const scope = {
    isSecureContext: secure,
    AudioContext,
    AudioWorkletNode,
    Float32Array,
    URL,
    document,
    navigator: {
      mediaDevices: {
        async getUserMedia() {
          if (denied) throw { name: 'NotAllowedError' };
          return pending ?? stream;
        },
      },
    },
  };
  scope.globalThis = scope;
  vm.runInNewContext(code, scope, { filename: 'audio_input.js' });
  return { api: scope.learnPianoAudio, track, stream, contexts,
    nodes, document, handlers };
}

test('requires HTTPS before requesting permission', async () => {
  const m = browser({ secure: false });
  assert.equal((await m.api.start(() => {}, () => {})).code,
    'insecure_context');
  assert.equal(m.contexts.length, 0);
});

test('permission denied releases AudioContext and allows retry', async () => {
  const m = browser({ denied: true });
  assert.equal((await m.api.start(() => {}, () => {})).code,
    'permission_denied');
  assert.equal(m.contexts[0].state, 'closed');
  await m.api.stop();
});

test('streams PCM metadata and stopping frees tracks and context', async () => {
  const m = browser();
  const captured = [];
  const result = await m.api.start((data, rate, time) =>
    captured.push({ data, rate, time }), () => {});
  assert.equal(result.ok, true);
  assert.equal(result.sampleRate, 44100);
  assert.equal(m.contexts[0].moduleUrl,
    'https://example.test/learn-piano/audio_capture_processor.js');
  assert.equal((await m.api.start(() => {}, () => {})).code, 'already_running');
  const samples = new Float32Array([0.1, -0.1]);
  m.nodes[0].port.onmessage({
    data: { samples, timestampMs: 80 },
  });
  assert.equal(captured.length, 1);
  assert.equal(captured[0].data, samples);
  assert.equal(captured[0].rate, 44100);
  assert.equal(captured[0].time, 80);
  await m.api.stop();
  assert.equal(m.track.stopped, 1);
  assert.equal(m.contexts[0].state, 'closed');
  assert.equal(m.nodes[0].port.onmessage, null);
  await m.api.stop();
  assert.equal(m.track.stopped, 1);
});

test('stop during permission request closes late stream', async () => {
  let grant;
  const permission = new Promise((resolve) => { grant = resolve; });
  const m = browser({ pending: permission });
  const started = m.api.start(() => {}, () => {});
  await m.api.stop();
  grant(m.stream);
  assert.equal((await started).code, 'cancelled');
  assert.equal(m.track.stopped, 1);
});

test('device loss and hidden tab stop capture and notify the UI', async () => {
  const m = browser();
  const reasons = [];
  await m.api.start(() => {}, (reason) => reasons.push(reason));
  m.track.onEnded();
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(reasons, ['device_ended']);
  assert.equal(m.contexts[0].state, 'closed');
  await m.api.start(() => {}, (reason) => reasons.push(reason));
  m.document.visibilityState = 'hidden';
  m.handlers.get('visibilitychange')();
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(reasons, ['device_ended', 'background']);
});

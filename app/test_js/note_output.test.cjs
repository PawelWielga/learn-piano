const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(
  path.resolve(__dirname, '../web/note_output.js'), 'utf8',
);

function buildSynth() {
  const oscillators = [];
  const contexts = [];
  const listeners = new Map();
  class FakeParameter {
    constructor() { this.value = 0; }
    setValueAtTime(value) { this.value = value; }
    exponentialRampToValueAtTime(value) { this.value = value; }
    setTargetAtTime(value) { this.value = value; }
    cancelScheduledValues() {}
  }
  class FakeContext {
    constructor() {
      this.currentTime = 1;
      this.destination = {};
      this.state = 'running';
      contexts.push(this);
    }
    createOscillator() {
      const oscillator = {
        frequency: { value: 0 }, type: '',
        connect() {}, start() { this.started = true; },
        stop() { this.stopped = true; },
      };
      oscillators.push(oscillator);
      return oscillator;
    }
    createGain() {
      return { gain: new FakeParameter(), connect() {} };
    }
    close() { this.state = 'closed'; return Promise.resolve(); }
  }
  const sandbox = {
    AudioContext: FakeContext,
    document: {
      visibilityState: 'visible',
      addEventListener(name, callback) { listeners.set(name, callback); },
    },
  };
  sandbox.globalThis = sandbox;
  vm.runInNewContext(source, sandbox);
  return { synth: sandbox.learnPianoSynth, oscillators, contexts, listeners, sandbox };
}

test('correct MIDI frequencies and simultaneous notes', () => {
  const { synth, oscillators, contexts } = buildSynth();
  assert.equal(synth.noteOn(69), true);
  assert.equal(synth.noteOn(60), true);
  assert.equal(contexts.length, 1);
  assert.equal(oscillators.length, 4);
  assert.equal(oscillators[0].frequency.value, 440);
  assert.ok(Math.abs(oscillators[2].frequency.value - 261.6256) < 0.01);
  synth.noteOff(69);
  assert.equal(oscillators[0].stopped, true);
  assert.equal(oscillators[2].stopped, undefined);
  synth.stopAll();
  assert.equal(oscillators[2].stopped, true);
});

test('repeated note needs new noteOn, stopAll and dispose are safe', () => {
  const { synth, oscillators, contexts } = buildSynth();
  assert.equal(synth.noteOn(60), true);
  assert.equal(synth.noteOn(60), true);
  assert.equal(oscillators[0].stopped, true);
  synth.noteOff(60);
  synth.noteOff(60);
  synth.dispose();
  assert.equal(contexts[0].state, 'closed');
});

test('rejects invalid MIDI and stops on hidden tab without microphone', () => {
  const { synth, oscillators, listeners, sandbox } = buildSynth();
  assert.equal(synth.noteOn(-1), false);
  assert.equal(synth.noteOn(128), false);
  assert.equal(synth.noteOn(60.3), false);
  assert.equal(oscillators.length, 0);
  synth.noteOn(60);
  sandbox.document.visibilityState = 'hidden';
  listeners.get('visibilitychange')();
  assert.equal(oscillators[0].stopped, true);
});

test('unsupported Web Audio returns false without throwing', () => {
  const { synth, sandbox } = buildSynth();
  delete sandbox.AudioContext;
  assert.equal(synth.noteOn(60), false);
});

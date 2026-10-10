const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const code = fs.readFileSync(
  path.join(__dirname, '../web/audio_capture_processor.js'),
  'utf8',
);

test('worklet buffers exactly 2048 mono samples and transfers complete frames', () => {
  let Processor;
  class AudioWorkletProcessor {
    constructor() {
      this.port = {
        messages: [],
        postMessage(payload, transfer) {
          this.messages.push({ payload, transfer });
        },
      };
    }
  }
  const context = {
    AudioWorkletProcessor,
    Float32Array,
    currentTime: 1.5,
    registerProcessor(name, implementation) {
      assert.equal(name, 'learn-piano-capture');
      Processor = implementation;
    },
  };
  vm.runInNewContext(code, context, { filename: 'audio_capture_processor.js' });
  const processor = new Processor();

  // Browser worklet processes input in 128-sample blocks.
  for (let block = 0; block < 16; block++) {
    const mono = Float32Array.from({ length: 128 }, (_, i) =>
      (block * 128 + i) / 2048);
    const output = new Float32Array(128).fill(1);
    assert.equal(processor.process([[mono]], [[output]]), true);
    assert.deepEqual([...output], [...new Float32Array(128)]);
  }

  assert.equal(processor.port.messages.length, 1);
  const { payload, transfer } = processor.port.messages[0];
  assert.equal(payload.samples.length, 2048);
  assert.equal(payload.samples[0], 0);
  assert.equal(payload.samples[2047], 2047 / 2048);
  assert.equal(payload.timestampMs, 1500);
  assert.equal(transfer[0], payload.samples.buffer);

  processor.port.onmessage({ data: { type: 'stop' } });
  assert.equal(processor.process([], []), false);
});

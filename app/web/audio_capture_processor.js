// Runs on the Web Audio rendering thread, not the Flutter UI thread.
// Mono samples are buffered to 2048 frames (about 43 ms at 48 kHz).
class LearnPianoCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.samples = new Float32Array(2048);
    this.offset = 0;
    this.stopped = false;
    this.port.onmessage = (event) => {
      if (event.data?.type === 'stop') this.stopped = true;
    };
  }

  process(inputs, outputs) {
    // A connected but silent output keeps the processing graph alive.
    for (const output of outputs[0] ?? []) output.fill(0);
    if (this.stopped) return false;

    const mono = inputs[0]?.[0];
    if (!mono) return true;

    let position = 0;
    while (position < mono.length) {
      const count = Math.min(this.samples.length - this.offset, mono.length - position);
      this.samples.set(mono.subarray(position, position + count), this.offset);
      this.offset += count;
      position += count;

      if (this.offset === this.samples.length) {
        const ready = this.samples;
        this.port.postMessage(
          { samples: ready, timestampMs: currentTime * 1000 },
          [ready.buffer],
        );
        this.samples = new Float32Array(2048);
        this.offset = 0;
      }
    }
    return true;
  }
}

registerProcessor('learn-piano-capture', LearnPianoCaptureProcessor);

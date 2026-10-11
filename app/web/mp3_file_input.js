// Decode local MP3 files into mono PCM. No microphone, upload or storage.
(() => {
  'use strict';

  const MAX_BYTES = 12 * 1024 * 1024;
  const MAX_SECONDS = 90;
  const MAX_SAMPLES = 90 * 96000;
  let choosing = false;

  function pick() {
    if (choosing) return Promise.resolve({ ok: false, code: 'busy' });
    choosing = true;

    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.mp3,audio/mpeg';
      input.style.display = 'none';
      document.body.appendChild(input);

      let finished = false;
      function finish(result) {
        if (finished) return;
        finished = true;
        choosing = false;
        input.removeEventListener('change', selected);
        input.removeEventListener('cancel', cancelled);
        input.remove();
        resolve(result);
      }

      async function selected() {
        const file = input.files?.[0];
        if (!file) return finish({ ok: false, code: 'cancelled' });
        if (!/\.mp3$/i.test(file.name)) {
          return finish({ ok: false, code: 'invalid_format' });
        }
        if (file.size > MAX_BYTES) {
          return finish({ ok: false, code: 'too_large' });
        }

        const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
        if (!Context) return finish({ ok: false, code: 'unsupported' });

        let context;
        try {
          const bytes = await file.arrayBuffer();
          if (bytes.byteLength > MAX_BYTES) {
            return finish({ ok: false, code: 'too_large' });
          }
          context = new Context();
          const buffer = await context.decodeAudioData(bytes);
          if (!buffer ||
              !Number.isFinite(buffer.duration) ||
              buffer.duration > MAX_SECONDS ||
              buffer.length > MAX_SAMPLES) {
            return finish({ ok: false, code: 'too_long' });
          }
          if (buffer.length < 2048 || !Number.isFinite(buffer.sampleRate) ||
              buffer.sampleRate <= 0 || buffer.numberOfChannels < 1) {
            return finish({ ok: false, code: 'decode_failed' });
          }

          // Mix stereo into mono, preserving physical amplitude on each sample.
          const channelCount = Math.min(buffer.numberOfChannels, 2);
          const channels = Array.from(
            { length: channelCount },
            (_, index) => buffer.getChannelData(index),
          );
          const mono = new Float32Array(buffer.length);
          for (let i = 0; i < buffer.length; i++) {
            let sample = 0;
            for (const channel of channels) sample += channel[i];
            mono[i] = sample / channelCount;
          }
          finish({
            ok: true,
            name: file.name,
            samples: mono,
            sampleRate: buffer.sampleRate,
          });
        } catch (_) {
          finish({ ok: false, code: 'decode_failed' });
        } finally {
          if (context) {
            try { await context.close(); } catch (_) { /* already closed */ }
          }
        }
      }

      function cancelled() {
        finish({ ok: false, code: 'cancelled' });
      }

      input.addEventListener('change', selected);
      input.addEventListener('cancel', cancelled);
      try {
        input.click();
      } catch (_) {
        finish({ ok: false, code: 'read_failed' });
      }
    });
  }

  globalThis.learnPianoMp3 = Object.freeze({ pick });
})();

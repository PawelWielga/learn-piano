// Browser-only MIDI chooser. Bytes remain local; no fetch, storage or uploads.
(() => {
  'use strict';

  const MAX_BYTES = 2 * 1024 * 1024;
  let choosing = false;

  function pick() {
    if (choosing) return Promise.resolve({ ok: false, code: 'busy' });
    choosing = true;

    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.mid,.midi,audio/midi,audio/x-midi';
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
        if (file.size > MAX_BYTES) return finish({ ok: false, code: 'too_large' });

        try {
          const data = new Uint8Array(await file.arrayBuffer());
          if (data.byteLength > MAX_BYTES) {
            return finish({ ok: false, code: 'too_large' });
          }
          finish({ ok: true, name: file.name, bytes: data });
        } catch (_) {
          finish({ ok: false, code: 'read_failed' });
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

  globalThis.learnPianoMidi = Object.freeze({ pick });
})();

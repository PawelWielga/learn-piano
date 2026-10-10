// Range preference only. No audio, MIDI file bytes, network or analytics.
(() => {
  'use strict';
  const key = 'learn-piano.instrument-range.v1';

  function read() {
    return globalThis.localStorage.getItem(key);
  }

  function write(value) {
    globalThis.localStorage.setItem(key, value);
  }

  globalThis.learnPianoRange = Object.freeze({ read, write });
})();

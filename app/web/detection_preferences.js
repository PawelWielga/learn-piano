// Browser-only preferences. Audio and MIDI are never persisted or uploaded.
(() => {
  'use strict';

  const key = 'learn-piano.detection-preferences.v1';
  let sessionValue = null;

  function read() {
    try {
      return globalThis.localStorage.getItem(key) ?? sessionValue;
    } catch (_) {
      return sessionValue;
    }
  }

  function write(value) {
    // Still apply settings during this tab session if storage is blocked.
    sessionValue = value;
    globalThis.localStorage.setItem(key, value);
  }

  globalThis.learnPianoDetection = Object.freeze({ read, write });
})();

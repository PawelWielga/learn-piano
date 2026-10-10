// A user-initiated, best-effort landscape lock. No tracking or network calls.
(() => {
  'use strict';

  async function lockLandscape() {
    const orientation = globalThis.screen?.orientation;
    if (typeof orientation?.lock !== 'function') return false;

    const doc = globalThis.document;
    const alreadyFullscreen = Boolean(doc?.fullscreenElement);
    let enteredFullscreen = false;

    try {
      // Chromium usually requires fullscreen before it accepts orientation.lock.
      // requestFullscreen must start inside the Flutter button's user gesture.
      if (!alreadyFullscreen) {
        if (typeof doc?.documentElement?.requestFullscreen !== 'function') {
          return false;
        }
        await doc.documentElement.requestFullscreen();
        enteredFullscreen = true;
      }

      await orientation.lock('landscape');
      return true;
    } catch (_) {
      // Avoid trapping the user in fullscreen if the orientation lock failed.
      if (enteredFullscreen && typeof doc.exitFullscreen === 'function') {
        try {
          await doc.exitFullscreen();
        } catch (_) {
          // A denied exit is not fatal; the overlay remains available.
        }
      }
      return false;
    }
  }

  globalThis.learnPianoOrientation = Object.freeze({ lockLandscape });
})();

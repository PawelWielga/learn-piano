// Export note events as a locally generated MIDI file. Never uploads data.
(() => {
  'use strict';

  function download(bytes, name) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) return false;
    const safeName = typeof name === 'string' && /^[a-zA-Z0-9_-]+\.mid$/.test(name)
      ? name : 'learn-piano-recording.mid';
    let url;
    let link;
    try {
      const blob = new Blob([bytes], { type: 'audio/midi' });
      url = URL.createObjectURL(blob);
      link = document.createElement('a');
      link.href = url;
      link.download = safeName;
      link.style.display = 'none';
      document.body.appendChild(link);
      link.click();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (link) link.remove();
      if (url) setTimeout(() => URL.revokeObjectURL(url), 5000);
    }
  }

  globalThis.learnPianoRecording = Object.freeze({ download });
})();

// Touch piano synthesizer using Web Audio. No samples, network or microphone.
(() => {
  'use strict';

  let context = null;
  const voices = new Map();

  function stopVoice(voice) {
    const time = context?.currentTime ?? 0;
    try {
      voice.envelope.gain.cancelScheduledValues(time);
      voice.envelope.gain.setTargetAtTime(0.0001, time, 0.045);
      voice.oscillator.stop(time + 0.22);
      voice.harmonic.stop(time + 0.22);
    } catch (_) { /* AudioContext may have been closed */ }
  }

  function noteOff(note) {
    const voice = voices.get(note);
    if (!voice) return;
    voices.delete(note);
    stopVoice(voice);
  }

  function stopAll() {
    for (const note of [...voices.keys()]) noteOff(note);
  }

  function noteOn(note) {
    if (!Number.isInteger(note) || note < 0 || note > 127) return false;
    const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!Context) return false;
    try {
      // Called synchronously from a pointer gesture, satisfying mobile
      // browsers' user-activation requirement for starting Web Audio.
      context ??= new Context();
      if (context.state === 'suspended') void context.resume().catch(() => {});
      noteOff(note);

      const now = context.currentTime;
      const frequency = 440 * 2 ** ((note - 69) / 12);
      const envelope = context.createGain();
      envelope.gain.setValueAtTime(0.0001, now);
      envelope.gain.exponentialRampToValueAtTime(0.13, now + 0.012);
      envelope.gain.exponentialRampToValueAtTime(0.075, now + 0.25);
      envelope.connect(context.destination);

      const oscillator = context.createOscillator();
      oscillator.type = 'triangle';
      oscillator.frequency.value = frequency;
      oscillator.connect(envelope);

      const harmonic = context.createOscillator();
      harmonic.type = 'sine';
      harmonic.frequency.value = frequency * 2;
      const harmonicLevel = context.createGain();
      harmonicLevel.gain.value = 0.12;
      harmonic.connect(harmonicLevel);
      harmonicLevel.connect(envelope);

      oscillator.start(now);
      harmonic.start(now);
      voices.set(note, { oscillator, harmonic, envelope });
      return true;
    } catch (_) {
      // Playback failure never implies microphone access or data transfer.
      return false;
    }
  }

  function dispose() {
    stopAll();
    const previous = context;
    context = null;
    if (previous && previous.state !== 'closed') {
      void previous.close().catch(() => {});
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') stopAll();
  });

  globalThis.learnPianoSynth = Object.freeze({
    noteOn, noteOff, stopAll, dispose,
  });
})();

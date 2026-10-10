// Local-only browser microphone bridge for Flutter (Dart JS interop).
// No fetch, recordings, storage or network traffic.
(() => {
  'use strict';

  let active = null;

  function failure(code) {
    return { ok: false, code };
  }

  function classify(error) {
    switch (error?.name) {
      case 'NotAllowedError':
      case 'PermissionDeniedError':
      case 'SecurityError':
        return 'permission_denied';
      case 'NotFoundError':
      case 'DevicesNotFoundError':
        return 'no_device';
      case 'NotReadableError':
      case 'TrackStartError':
      case 'AbortError':
        return 'device_busy';
      default:
        return 'unknown';
    }
  }

  async function release(session) {
    if (session.cleaned) return;
    session.cleaned = true;
    document.removeEventListener('visibilitychange', session.onVisibility);
    if (session.node) {
      session.node.port.onmessage = null;
      session.node.port.postMessage({ type: 'stop' });
    }
    try { session.source?.disconnect(); } catch (_) { /* already detached */ }
    try { session.node?.disconnect(); } catch (_) { /* already detached */ }
    session.stream?.getTracks().forEach((track) => track.stop());
    if (session.context && session.context.state !== 'closed') {
      try { await session.context.close(); } catch (_) { /* device removed */ }
    }
  }

  async function start(onFrame, onInterrupted) {
    if (active) return failure('already_running');
    if (!globalThis.isSecureContext) return failure('insecure_context');

    const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!navigator.mediaDevices?.getUserMedia || !Context ||
        !globalThis.AudioWorkletNode) {
      return failure('unsupported');
    }

    const session = {
      cleaned: false,
      stream: null,
      context: null,
      source: null,
      node: null,
      onVisibility: null,
    };
    session.onVisibility = () => {
      if (document.visibilityState === 'hidden' && active === session) {
        active = null;
        void release(session).then(() => onInterrupted('background'));
      }
    };
    active = session;
    document.addEventListener('visibilitychange', session.onVisibility);

    try {
      // Construct/resume under the click gesture, before awaiting permission.
      session.context = new Context();
      void session.context.resume().catch(() => {});
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
        },
        video: false,
      });

      // stop() may have been called while the permission prompt was open.
      if (active !== session) {
        stream.getTracks().forEach((track) => track.stop());
        return failure('cancelled');
      }
      session.stream = stream;

      if (!session.context.audioWorklet?.addModule) {
        throw { name: 'UnsupportedError' };
      }
      const processorUrl = new URL('audio_capture_processor.js', document.baseURI);
      await session.context.audioWorklet.addModule(processorUrl.href);
      if (active !== session) return failure('cancelled');

      session.source = session.context.createMediaStreamSource(stream);
      session.node = new AudioWorkletNode(session.context, 'learn-piano-capture');
      session.node.port.onmessage = (event) => {
        if (active !== session) return;
        const payload = event.data;
        if (payload?.samples instanceof Float32Array) {
          onFrame(payload.samples, session.context.sampleRate, payload.timestampMs);
        }
      };
      session.node.port.onmessageerror = () => {
        if (active !== session) return;
        active = null;
        void release(session).then(() => onInterrupted('message_error'));
      };
      for (const track of stream.getAudioTracks()) {
        track.addEventListener('ended', () => {
          if (active !== session) return;
          active = null;
          void release(session).then(() => onInterrupted('device_ended'));
        }, { once: true });
      }

      session.source.connect(session.node);
      session.node.connect(session.context.destination);
      if (session.context.state === 'suspended') await session.context.resume();
      if (active !== session) return failure('cancelled');

      return { ok: true, sampleRate: session.context.sampleRate };
    } catch (error) {
      if (active === session) active = null;
      await release(session);
      if (error?.name === 'UnsupportedError') return failure('unsupported');
      return failure(classify(error));
    }
  }

  async function stop() {
    const session = active;
    active = null;
    if (session) await release(session);
  }

  globalThis.learnPianoAudio = Object.freeze({ start, stop });
})();

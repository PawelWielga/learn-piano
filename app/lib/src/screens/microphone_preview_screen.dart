import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/audio_input.dart';
import '../audio/audio_input_factory.dart';

class MicrophonePreviewScreen extends StatefulWidget {
  const MicrophonePreviewScreen({super.key, this.audioInput});

  /// Allows widget tests to inject a fake rather than opening a real device.
  final AudioInput? audioInput;

  @override
  State<MicrophonePreviewScreen> createState() =>
      _MicrophonePreviewScreenState();
}

class _MicrophonePreviewScreenState extends State<MicrophonePreviewScreen> {
  late final AudioInput _input;
  StreamSubscription<PcmFrame>? _frameSubscription;
  StreamSubscription<AudioInputStatus>? _statusSubscription;

  bool _busy = false;
  bool _listening = false;
  int? _sampleRate;
  int? _frameSize;
  double _level = 0;
  String? _error;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _input = widget.audioInput ?? createAudioInput();
    _frameSubscription = _input.frames.listen(_onFrame);
    _statusSubscription = _input.statuses.listen((status) {
      if (!mounted) return;
      if (status == AudioInputStatus.interrupted) {
        setState(() {
          _listening = false;
          _level = 0;
          _error = 'Nasłuch został przerwany (np. zmiana karty lub '
              'odłączenie mikrofonu). Możesz go włączyć ponownie.';
        });
      }
    });
  }

  void _onFrame(PcmFrame frame) {
    if (!mounted || !_listening || frame.samples.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastPaint) < const Duration(milliseconds: 120)) return;
    _lastPaint = now;

    var sum = 0.0;
    for (final sample in frame.samples) {
      sum += sample * sample;
    }
    final rms = math.sqrt(sum / frame.samples.length);

    setState(() {
      _sampleRate = frame.sampleRate;
      _frameSize = frame.samples.length;
      _level = rms.clamp(0.0, 1.0);
    });
  }

  Future<void> _start() async {
    if (_busy || _listening) return;
    setState(() {
      _busy = true;
      _error = null;
      _sampleRate = null;
      _frameSize = null;
      _level = 0;
    });
    try {
      await _input.start();
      if (!mounted) return;
      setState(() => _listening = true);
    } on AudioInputException catch (error) {
      if (mounted) setState(() => _error = _errorText(error.failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nie udało się uruchomić mikrofonu. '
            'Sprawdź uprawnienia i spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _input.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _level = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nie udało się poprawnie zatrzymać '
            'mikrofonu. Spróbuj zamknąć tę kartę.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_frameSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    // The JS adapter stops MediaStreamTracks and closes AudioContext.
    unawaited(_input.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Test mikrofonu')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _listening ? 'Nasłuch aktywny' : 'Mikrofon nieaktywny',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dźwięk jest analizowany wyłącznie w tej przeglądarce. '
                  'Nie zapisujemy ani nie wysyłamy nagrań. '
                  'Włącz mikrofon i zagraj pojedynczą nutę.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const Key('microphone-toggle'),
                  onPressed: _busy ? null : (_listening ? _stop : _start),
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  label: Text(_busy
                      ? 'Trwa zmiana stanu…'
                      : _listening
                          ? 'Wyłącz mikrofon'
                          : 'Włącz mikrofon'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const Key('microphone-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Text('Poziom wejścia', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _listening ? _level : 0,
                  minHeight: 12,
                  semanticsLabel: 'Poziom sygnału mikrofonu',
                ),
                const SizedBox(height: 16),
                Text(
                  'Próbkowanie: ${_sampleRate == null ? '—' : '${_sampleRate!} Hz'}',
                  key: const Key('sample-rate'),
                ),
                Text(
                  'Rozmiar ramki: ${_frameSize == null ? '—' : '${_frameSize!} próbek'}',
                  key: const Key('frame-size'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Rozpoznawanie wysokości nut dodamy w następnym kroku. '
                  'Ten ekran pozwala na razie sprawdzić, czy mikrofon '
                  'dostarcza próbki.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _errorText(AudioInputFailure failure) {
  return switch (failure) {
    AudioInputFailure.permissionDenied =>
      'Brak zgody na mikrofon. Zezwól na dostęp w ustawieniach '
          'witryny/przeglądarki i spróbuj ponownie.',
    AudioInputFailure.noDevice =>
      'Nie znaleziono mikrofonu. Podłącz urządzenie i spróbuj ponownie.',
    AudioInputFailure.deviceBusy =>
      'Nie można odczytać mikrofonu. Sprawdź, czy inne aplikacje go nie blokują.',
    AudioInputFailure.insecureContext =>
      'Mikrofon wymaga połączenia HTTPS lub adresu localhost.',
    AudioInputFailure.unsupported =>
      'Ta przeglądarka nie obsługuje wymaganych funkcji Web Audio.',
    AudioInputFailure.alreadyRunning => 'Mikrofon jest już włączony.',
    AudioInputFailure.cancelled => 'Uruchamianie mikrofonu anulowano.',
    AudioInputFailure.unknown =>
      'Nie udało się uruchomić mikrofonu. Spróbuj ponownie.',
  };
}

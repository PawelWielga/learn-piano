import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_input.dart';
import 'package:learn_piano/src/learn_piano_app.dart';
import 'package:learn_piano/src/screens/microphone_preview_screen.dart';

class FakeAudioInput implements AudioInput {
  final _frames = StreamController<PcmFrame>.broadcast(sync: true);
  final _statuses = StreamController<AudioInputStatus>.broadcast(sync: true);

  int starts = 0;
  int stops = 0;
  int disposes = 0;
  AudioInputFailure? startFailure;
  Completer<void>? startGate;

  @override
  Stream<PcmFrame> get frames => _frames.stream;

  @override
  Stream<AudioInputStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    starts++;
    if (startFailure case final failure?) {
      throw AudioInputException(failure);
    }
    await startGate?.future;
    _statuses.add(AudioInputStatus.listening);
  }

  @override
  Future<void> stop() async {
    stops++;
    _statuses.add(AudioInputStatus.stopped);
  }

  void emitFrame() {
    _frames.add(
      PcmFrame(
        samples: Float32List.fromList([0.2, -0.2, 0.1, -0.1]),
        sampleRate: 48000,
        capturedAt: const Duration(milliseconds: 50),
      ),
    );
  }

  void emitTone(double frequency, {int sampleRate = 48000, int timeMs = 50}) {
    final samples = Float32List.fromList(
      List<double>.generate(
        2048,
        (i) => 0.35 * math.sin(2 * math.pi * frequency * i / sampleRate),
      ),
    );
    _frames.add(
      PcmFrame(
        samples: samples,
        sampleRate: sampleRate,
        capturedAt: Duration(milliseconds: timeMs),
      ),
    );
  }

  void emitSilence({int timeMs = 250}) {
    _frames.add(
      PcmFrame(
        samples: Float32List(2048),
        sampleRate: 48000,
        capturedAt: Duration(milliseconds: timeMs),
      ),
    );
  }

  void interrupt() => _statuses.add(AudioInputStatus.interrupted);

  @override
  Future<void> dispose() async {
    disposes++;
    await stop();
    await _frames.close();
    await _statuses.close();
  }
}

void main() {
  testWidgets('home opens the microphone screen', (tester) async {
    await tester.pumpWidget(const LearnPianoApp());

    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);
    expect(find.byKey(const Key('open-midi-import')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('training-coming-soon')),
      200,
    );
    expect(find.byKey(const Key('training-coming-soon')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-microphone-preview')),
      -200,
    );

    await tester.tap(find.byKey(const Key('open-microphone-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Mikrofon nieaktywny'), findsOneWidget);
    expect(find.text('Włącz mikrofon'), findsOneWidget);
    expect(find.textContaining('Próbkowanie:'), findsOneWidget);
  });

  testWidgets('starts, displays PCM metadata and stops', (tester) async {
    final input = FakeAudioInput();
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );

    // Before tapping, the browser has not been asked for microphone access.
    expect(input.starts, 0);
    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(input.starts, 1);
    expect(find.text('Nasłuch aktywny'), findsOneWidget);

    input.emitFrame();
    await tester.pump();
    expect(find.text('Próbkowanie: 48000 Hz'), findsOneWidget);
    expect(find.text('Rozmiar ramki: 4 próbek'), findsOneWidget);

    await tester.tap(find.text('Wyłącz mikrofon'));
    await tester.pump();
    expect(input.stops, 1);
    expect(find.text('Mikrofon nieaktywny'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(input.disposes, 1);
  });

  testWidgets('shows detected note and clears it for silence and stop', (
    tester,
  ) async {
    final input = FakeAudioInput();
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('detected-note'))).data,
      '—',
    );
    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();

    input.emitTone(440);
    await tester.pump();
    expect(find.text('A4'), findsOneWidget);
    expect(find.textContaining('440.0 Hz'), findsOneWidget);
    expect(find.textContaining('pewność'), findsOneWidget);

    input.emitSilence(timeMs: 200);
    await tester.pump();
    expect(find.text('Brak pewnej nuty'), findsOneWidget);

    input.emitTone(261.6256, timeMs: 400);
    await tester.pump();
    expect(find.text('C4'), findsOneWidget);

    await tester.tap(find.text('Wyłącz mikrofon'));
    await tester.pump();
    expect(find.text('A4'), findsNothing);
    expect(find.text('C4'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('detected-note'))).data,
      '—',
    );
  });

  testWidgets('confirms separate NoteOn events only after stable re-strikes', (
    tester,
  ) async {
    final input = FakeAudioInput();
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );
    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();

    input.emitTone(440, timeMs: 50);
    input.emitTone(440, timeMs: 180);
    await tester.pump();
    expect(find.text('Zdarzenia NoteOn: 0'), findsOneWidget);

    input.emitTone(440, timeMs: 310);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('stable-note'))).data,
      'A4',
    );
    expect(find.text('Zdarzenia NoteOn: 1'), findsOneWidget);

    // One tiny dropout and a continuing ring must not create a new onset.
    input.emitSilence(timeMs: 440);
    input.emitTone(440, timeMs: 570);
    input.emitTone(440, timeMs: 700);
    await tester.pump();
    expect(find.text('Zdarzenia NoteOn: 1'), findsOneWidget);

    input.emitSilence(timeMs: 830);
    input.emitSilence(timeMs: 960);
    input.emitSilence(timeMs: 1090);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('stable-note'))).data, '—');

    input.emitTone(440, timeMs: 1220);
    input.emitTone(440, timeMs: 1350);
    input.emitTone(440, timeMs: 1480);
    await tester.pump();
    expect(find.text('Zdarzenia NoteOn: 2'), findsOneWidget);
    expect(find.text('Ostatnie uderzenie: A4'), findsOneWidget);

    await tester.tap(find.text('Wyłącz mikrofon'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('stable-note'))).data, '—');

    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(find.text('Zdarzenia NoteOn: 0'), findsOneWidget);
  });

  testWidgets('permission rejection reports error and allows retry', (
    tester,
  ) async {
    final input = FakeAudioInput()
      ..startFailure = AudioInputFailure.permissionDenied;
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );

    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(find.byKey(const Key('microphone-error')), findsOneWidget);
    expect(find.textContaining('Brak zgody'), findsOneWidget);
    expect(find.text('Włącz mikrofon'), findsOneWidget);

    input.startFailure = null;
    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(input.starts, 2);
    expect(find.text('Nasłuch aktywny'), findsOneWidget);
  });

  testWidgets('prevents parallel requests and releases on navigation', (
    tester,
  ) async {
    final input = FakeAudioInput()..startGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );

    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(input.starts, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('microphone-toggle')))
          .onPressed,
      isNull,
    );

    input.startGate!.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(input.disposes, 1);
    expect(input.stops, 1);
  });

  testWidgets('unexpected microphone stop permits restart', (tester) async {
    final input = FakeAudioInput();
    await tester.pumpWidget(
      MaterialApp(home: MicrophonePreviewScreen(audioInput: input)),
    );
    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();

    input.interrupt();
    await tester.pump();
    expect(find.text('Mikrofon nieaktywny'), findsOneWidget);
    expect(find.textContaining('Nasłuch został przerwany'), findsOneWidget);

    await tester.tap(find.text('Włącz mikrofon'));
    await tester.pump();
    expect(input.starts, 2);
  });
}

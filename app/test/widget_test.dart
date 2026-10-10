import 'dart:async';
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
    expect(find.byKey(const Key('training-coming-soon')), findsOneWidget);

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
      tester.widget<FilledButton>(
        find.byKey(const Key('microphone-toggle')),
      ).onPressed,
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/midi_recording_export.dart';
import 'package:learn_piano/src/screens/mp3_import_screen.dart';
import 'package:learn_piano/src/transcription/transcription_engine.dart';

class _Picker implements AudioFilePicker {
  int picks = 0;

  @override
  Future<DecodedAudioFile?> pickAndDecode() async {
    picks++;
    return DecodedAudioFile(
      name: 'test.mp3',
      samples: Float32List(48000),
      sampleRate: 48000,
    );
  }
}

class _Exporter implements MidiRecordingExporter {
  Uint8List? saved;

  @override
  bool save(Uint8List data, String filename) {
    saved = data;
    return true;
  }
}

class _ControllableEngine implements TranscriptionEngine {
  final completer = Completer<TranscriptionResult>();
  bool Function()? cancelled;
  void Function(double)? progress;
  TranscriptionOptions? receivedOptions;
  int calls = 0;

  @override
  String get engineId => 'fake-model-v1';

  @override
  Future<TranscriptionResult> transcribe(
    DecodedAudioFile audio, {
    TranscriptionOptions options = const TranscriptionOptions(),
    bool Function()? isCancelled,
    void Function(double)? onProgress,
  }) {
    calls++;
    receivedOptions = options;
    cancelled = isCancelled;
    progress = onProgress;
    return completer.future;
  }
}

TranscriptionResult _result({bool bends = false}) => TranscriptionResult(
  engineId: 'fake-model-v1',
  duration: const Duration(seconds: 1),
  notes: [
    const TranscribedNote(
      midiNote: 60,
      start: Duration(milliseconds: 100),
      end: Duration(milliseconds: 700),
      confidence: 0.8,
    ),
    TranscribedNote(
      midiNote: 64,
      start: const Duration(milliseconds: 100),
      end: const Duration(milliseconds: 600),
      pitchBends: bends
          ? [const NotePitchBend(at: Duration.zero, cents: 10)]
          : const [],
    ),
  ],
  limitations: const ['Wynik syntetyczny, tylko do testu.'],
);

Future<void> _launch(
  WidgetTester tester,
  _Picker picker,
  _ControllableEngine engine,
  _Exporter exporter,
) async {
  tester.view.physicalSize = const Size(1100, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Mp3ImportScreen(picker: picker, exporter: exporter, engine: engine),
    ),
  );
  await tester.tap(find.byKey(const Key('mp3-select')));
  await tester.pump();
}

void main() {
  testWidgets(
    'fake engine controls progress and MIDI export without UI edits',
    (tester) async {
      final picker = _Picker();
      final engine = _ControllableEngine();
      final exporter = _Exporter();
      await _launch(tester, picker, engine, exporter);
      expect(engine.calls, 1);
      expect(picker.picks, 1);
      expect(engine.receivedOptions!.mode, TranscriptionMode.accurate);

      engine.progress?.call(0.53);
      await tester.pump();
      expect(find.text('Analiza: 53%'), findsOneWidget);
      engine.progress?.call(double.nan);
      await tester.pump();
      expect(find.text('Analiza: 53%'), findsOneWidget);

      engine.completer.complete(_result(bends: true));
      await tester.pumpAndSettle();
      expect(find.text('Rozpoznane nuty: 2'), findsOneWidget);
      expect(find.text('Silnik: fake-model-v1'), findsOneWidget);
      expect(find.text('Wynik syntetyczny, tylko do testu.'), findsOneWidget);
      expect(find.byKey(const Key('mp3-pitch-bend-warning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mp3-save')));
      await tester.pump();
      final parsed = const MidiParser().parse(exporter.saved!);
      expect(parsed.noteCount, 2);
      expect(parsed.tracks.single.notes.map((n) => n.midiNote), [60, 64]);
    },
  );

  testWidgets(
    'cancel rejects late progress and result even if engine ignores it',
    (tester) async {
      final picker = _Picker();
      final engine = _ControllableEngine();
      final exporter = _Exporter();
      await _launch(tester, picker, engine, exporter);
      expect(engine.cancelled?.call(), false);
      await tester.tap(find.byKey(const Key('mp3-cancel')));
      await tester.pump();
      expect(engine.cancelled?.call(), true);
      engine.progress?.call(1);
      engine.completer.complete(_result());
      await tester.pumpAndSettle();
      expect(find.text('Rozpoznane nuty: 0'), findsOneWidget);
      expect(find.text('Analiza anulowana.'), findsOneWidget);
      expect(exporter.saved, isNull);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('mp3-save')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('invalid engine output is not exported and shows an error', (
    tester,
  ) async {
    final picker = _Picker();
    final engine = _ControllableEngine();
    final exporter = _Exporter();
    await _launch(tester, picker, engine, exporter);
    engine.completer.complete(
      const TranscriptionResult(
        engineId: 'fake-model-v1',
        duration: Duration(seconds: 1),
        notes: [
          TranscribedNote(
            midiNote: 200,
            start: Duration(milliseconds: 10),
            end: Duration(milliseconds: 300),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Silnik zwrócił niepoprawną nutę.'), findsOneWidget);
    expect(find.text('Rozpoznane nuty: 0'), findsOneWidget);
    expect(exporter.saved, isNull);
  });

  testWidgets('disposed screen ignores late callbacks and completed results', (
    tester,
  ) async {
    final picker = _Picker();
    final engine = _ControllableEngine();
    final exporter = _Exporter();
    await _launch(tester, picker, engine, exporter);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(engine.cancelled?.call(), true);
    engine.progress?.call(0.95);
    engine.completer.complete(_result());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(exporter.saved, isNull);
  });
}

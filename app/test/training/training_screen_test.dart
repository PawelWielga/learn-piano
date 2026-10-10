import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_input.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';
import 'package:learn_piano/src/screens/training_screen.dart';

import '../midi/midi_fixtures.dart';

class TrainingAudioFake implements AudioInput {
  final _frames = StreamController<PcmFrame>.broadcast(sync: true);
  final _statuses = StreamController<AudioInputStatus>.broadcast(sync: true);
  AudioInputFailure? failure;
  int starts = 0;
  int stops = 0;
  int disposes = 0;

  @override
  Stream<PcmFrame> get frames => _frames.stream;

  @override
  Stream<AudioInputStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    starts++;
    if (failure case final error?) throw AudioInputException(error);
    _statuses.add(AudioInputStatus.listening);
  }

  @override
  Future<void> stop() async {
    stops++;
    _statuses.add(AudioInputStatus.stopped);
  }

  @override
  Future<void> dispose() async {
    disposes++;
    await stop();
    await _frames.close();
    await _statuses.close();
  }

  void interrupt() => _statuses.add(AudioInputStatus.interrupted);

  void tone(int midi, int timeMs) {
    final hz = 440.0 * math.pow(2, (midi - 69) / 12);
    _frames.add(
      PcmFrame(
        samples: Float32List.fromList(
          List<double>.generate(
            2048,
            (i) => 0.35 * math.sin(2 * math.pi * hz * i / 48000),
          ),
        ),
        sampleRate: 48000,
        capturedAt: Duration(milliseconds: timeMs),
      ),
    );
  }

  void silence(int timeMs) => _frames.add(
    PcmFrame(
      samples: Float32List(2048),
      sampleRate: 48000,
      capturedAt: Duration(milliseconds: timeMs),
    ),
  );

  void quietGate({int startMs = 50}) {
    silence(startMs);
    silence(startMs + 130);
    silence(startMs + 260);
  }

  void strike(int midi, {required int startMs}) {
    tone(midi, startMs);
    tone(midi, startMs + 130);
    tone(midi, startMs + 260);
  }

  void release({required int startMs}) {
    silence(startMs);
    silence(startMs + 130);
    silence(startMs + 260);
  }
}

class TrainingMidiPickerFake implements MidiFilePicker {
  @override
  Future<PickedMidiFile?> pick() async => PickedMidiFile(
    name: 'melody.mid',
    bytes: midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          event(240, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          event(240, [0x90, 64, 100]),
          event(480, [0x80, 64, 0]),
          endOfTrack(),
        ]),
      ],
    ),
  );
}

MelodySelection selection() {
  final midi = const MidiParser().parse(
    midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          event(240, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          event(240, [0x90, 64, 100]),
          event(480, [0x80, 64, 0]),
          endOfTrack(),
        ]),
      ],
    ),
  );
  return MelodySelection(const MelodyPartAnalyzer().analyze(midi).single);
}

Future<void> launch(WidgetTester tester, TrainingAudioFake fake) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TrainingScreen(
        selection: selection(),
        instrumentRange: const InstrumentRange(48, 72),
        audioInput: fake,
      ),
    ),
  );
}

Future<void> startExercise(WidgetTester tester, TrainingAudioFake fake) async {
  await tester.tap(find.byKey(const Key('training-primary')));
  await tester.pump();
  fake.quietGate();
  await tester.pump();
  expect(find.text('Słucham Twojego pianinka'), findsOneWidget);
}

void main() {
  testWidgets('requires a user gesture and confirms silence before scoring', (
    tester,
  ) async {
    final fake = TrainingAudioFake();
    await launch(tester, fake);
    expect(fake.starts, 0);
    expect(find.text('0 / 3 nut'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(fake.starts, 1);

    fake.strike(60, startMs: 50);
    await tester.pump();
    expect(find.text('0 / 3 nut'), findsOneWidget);
    fake.release(startMs: 440);
    fake.silence(830);
    fake.silence(960);
    await tester.pump();

    fake.strike(60, startMs: 1090);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    expect(find.text('Oczekiwana: C4'), findsOneWidget);
  });

  testWidgets('wrong notes do not advance, repeated pitches require release', (
    tester,
  ) async {
    final fake = TrainingAudioFake();
    await launch(tester, fake);
    await startExercise(tester, fake);

    fake.strike(64, startMs: 440);
    await tester.pump();
    expect(find.text('0 / 3 nut'), findsOneWidget);
    expect(find.text('Inna nuta. Spróbuj ponownie.'), findsOneWidget);
    expect(find.text('Wykryta: E4'), findsOneWidget);

    fake.strike(60, startMs: 830);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    expect(find.text('Dobrze! Przejdź do kolejnej nuty.'), findsOneWidget);

    fake.tone(60, 1220);
    fake.tone(60, 1350);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);

    fake.release(startMs: 1480);
    fake.strike(60, startMs: 1870);
    await tester.pump();
    expect(find.text('2 / 3 nut'), findsOneWidget);
    expect(find.text('Oczekiwana: E4'), findsOneWidget);

    fake.strike(64, startMs: 2260);
    await tester.pump();
    expect(find.byKey(const Key('training-completed')), findsOneWidget);
    expect(find.text('3 / 3 nut'), findsOneWidget);
    expect(fake.stops, 1);
    expect(find.textContaining('Mikrofon wyłączony'), findsOneWidget);
  });

  testWidgets('pause and reset stop audio; resumed held tone cannot score', (
    tester,
  ) async {
    final fake = TrainingAudioFake();
    await launch(tester, fake);
    await startExercise(tester, fake);
    fake.strike(60, startMs: 440);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(fake.stops, 1);
    expect(find.text('Ćwiczenie wstrzymane'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(fake.starts, 2);
    fake.strike(60, startMs: 50);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    fake.release(startMs: 440);
    fake.silence(830);
    fake.silence(960);
    await tester.pump();
    fake.strike(60, startMs: 1090);
    await tester.pump();
    expect(find.text('2 / 3 nut'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-reset')));
    await tester.pump();
    expect(fake.stops, 2);
    expect(find.text('Gotowe do ćwiczenia'), findsOneWidget);
    expect(find.text('0 / 3 nut'), findsOneWidget);
  });

  testWidgets('microphone errors and interruptions pause without scoring', (
    tester,
  ) async {
    final fake = TrainingAudioFake()
      ..failure = AudioInputFailure.permissionDenied;
    await launch(tester, fake);
    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(find.textContaining('Brak zgody na mikrofon'), findsOneWidget);
    expect(find.text('Gotowe do ćwiczenia'), findsOneWidget);

    fake.failure = null;
    await startExercise(tester, fake);
    fake.interrupt();
    await tester.pump();
    expect(find.text('Ćwiczenie wstrzymane'), findsOneWidget);
    expect(find.textContaining('Mikrofon został przerwany'), findsOneWidget);
    expect(fake.stops, 1);
  });

  testWidgets('import and choose melody, practice, return to song', (
    tester,
  ) async {
    final fake = TrainingAudioFake();
    await tester.pumpWidget(
      MaterialApp(
        home: MidiImportScreen(
          filePicker: TrainingMidiPickerFake(),
          trainingAudioInput: fake,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('melody-part-0-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('melody-part-0-0')));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('start-midi-training')),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('start-midi-training')));
    await tester.pumpAndSettle();
    expect(find.text('0 / 3 nut'), findsOneWidget);
    expect(fake.starts, 0);

    await startExercise(tester, fake);
    fake.strike(60, startMs: 440);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-change-song')));
    await tester.pumpAndSettle();
    expect(fake.disposes, 1);
    expect(find.text('Import MIDI'), findsOneWidget);
  });
}

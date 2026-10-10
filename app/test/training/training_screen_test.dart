import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_input.dart';
import 'package:learn_piano/src/audio/note_output.dart';
import 'package:learn_piano/src/widgets/piano_keyboard.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';
import 'package:learn_piano/src/screens/training_screen.dart';
import 'package:learn_piano/src/widgets/training_stage.dart';

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

class TrainingNoteOutputFake implements NoteOutput {
  final List<int> started = <int>[];
  final List<int> released = <int>[];
  int stopped = 0;
  int disposed = 0;

  @override
  bool noteOn(int note) {
    started.add(note);
    return true;
  }

  @override
  void noteOff(int note) => released.add(note);

  @override
  void stopAll() => stopped++;

  @override
  void dispose() => disposed++;
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

Future<void> launch(
  WidgetTester tester,
  TrainingAudioFake fake, {
  NoteOutput? noteOutput,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TrainingScreen(
        selection: selection(),
        instrumentRange: const InstrumentRange(48, 72),
        audioInput: fake,
        noteOutput: noteOutput,
      ),
    ),
  );
}

/// Start a pointer on the actual painted key (after any horizontal scrolling).
Future<TestGesture> pressKey(WidgetTester tester, int note) async {
  await tester.pumpAndSettle();
  final rect = tester.getRect(find.byKey(const Key('training-stage-canvas')));
  final height = rect.height;
  final keyboard = PianoKeyboardLayout(
    const InstrumentRange(48, 72),
    whiteKeyWidth: math.max(
      38.0,
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 21,
    ),
    height: (height * 0.32).clamp(110.0, 210.0),
  );
  final key = keyboard.keyForMidi(note)!;
  final point = Offset(
    rect.left + key.rect.center.dx,
    rect.top + height - keyboard.height + key.rect.height * 0.35,
  );
  return tester.startGesture(point);
}

Future<void> startExercise(WidgetTester tester, TrainingAudioFake fake) async {
  await tester.tap(find.byKey(const Key('training-primary')));
  await tester.pump();
  fake.quietGate();
  await tester.pump();
  expect(find.text('Słucham Twojego pianinka'), findsOneWidget);
}

void main() {
  testWidgets('touch keyboard scores notes with sound and no microphone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final microphone = TrainingAudioFake()
      ..failure = AudioInputFailure.permissionDenied;
    final speaker = TrainingNoteOutputFake();
    await launch(tester, microphone, noteOutput: speaker);

    await tester.tap(find.byKey(const Key('training-input-toggle')));
    await tester.pump();
    expect(find.textContaining('Gra na ekranie'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(find.text('Graj na klawiaturze ekranowej'), findsOneWidget);
    expect(microphone.starts, 0);

    // Black C#4 is above its white neighbours and must not score as C4.
    final black = await pressKey(tester, 61);
    await tester.pump();
    expect(find.text('0 / 3 nut'), findsOneWidget);
    expect(find.text('Inna nuta. Spróbuj ponownie.'), findsOneWidget);
    expect(speaker.started, contains(61));
    await black.up();
    await tester.pump();

    final first = await pressKey(tester, 60);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    expect(speaker.started.last, 60);

    // A second finger on a held pitch must not score a second C4.
    final secondFinger = await pressKey(tester, 60);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    await first.up();
    await tester.pump();
    expect(speaker.released, isNot(contains(60)));
    await secondFinger.up();
    await tester.pump();
    expect(speaker.released, contains(60));

    final second = await pressKey(tester, 60);
    await tester.pump();
    expect(find.text('2 / 3 nut'), findsOneWidget);
    await second.up();
    await tester.pump();

    final third = await pressKey(tester, 64);
    await tester.pump();
    expect(find.text('3 / 3 nut'), findsOneWidget);
    expect(find.byKey(const Key('training-completed')), findsOneWidget);
    await third.up();
    await tester.pump();
    expect(speaker.released, contains(64));
    expect(microphone.starts, 0);
  });

  testWidgets('touch pause, reset and mode switch stop synthesizer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final microphone = TrainingAudioFake();
    final speaker = TrainingNoteOutputFake();
    await launch(tester, microphone, noteOutput: speaker);
    await tester.tap(find.byKey(const Key('training-input-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();

    final held = await pressKey(tester, 60);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(find.text('Ćwiczenie wstrzymane'), findsOneWidget);
    expect(speaker.stopped, greaterThan(0));
    await held.up();

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    final again = await pressKey(tester, 60);
    await tester.pump();
    expect(find.text('2 / 3 nut'), findsOneWidget);
    await again.up();
    await tester.tap(find.byKey(const Key('training-reset')));
    await tester.pump();
    expect(find.text('0 / 3 nut'), findsOneWidget);
    expect(microphone.starts, 0);

    await tester.tap(find.byKey(const Key('training-input-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(microphone.starts, 1);
    expect(speaker.disposed, 0);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(speaker.disposed, 1);
  });

  testWidgets('landscape training uses a full stage and overlay controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = TrainingAudioFake();
    await launch(tester, fake);

    expect(find.byKey(const Key('training-stage-canvas')), findsOneWidget);
    expect(find.byKey(const Key('training-stage-scroll')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('Wait Mode'), findsOneWidget);
    expect(find.text('0 / 3 nut'), findsOneWidget);
    expect(fake.starts, 0);

    // Keep Learn Piano's palette independent of the reference layout.
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('training-progress')),
    );
    final expectedLabel = tester.widget<Text>(
      find.byKey(const Key('training-expected')),
    );
    final detectedLabel = tester.widget<Text>(
      find.byKey(const Key('training-detected')),
    );
    expect(progress.valueColor?.value, TrainingStagePalette.primary);
    expect(expectedLabel.style?.color, TrainingStagePalette.primary);
    expect(detectedLabel.style?.color, TrainingStagePalette.detected);
    expect(TrainingStagePalette.primary, isNot(TrainingStagePalette.detected));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('training-center-play')));
    await tester.pump();
    expect(fake.starts, 1);
    expect(find.text('Wait Mode'), findsNothing);

    fake.quietGate();
    await tester.pump();
    expect(find.text('Słucham Twojego pianinka'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('training-controls-toggle')));
    await tester.pump();
    expect(find.text('Wait Mode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(fake.stops, 1);
    expect(find.text('Ćwiczenie wstrzymane'), findsOneWidget);
    expect(find.text('Wznów'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('very short landscape keeps essential actions usable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = TrainingAudioFake();
    await launch(tester, fake);

    expect(find.byKey(const Key('training-stage-canvas')), findsOneWidget);
    expect(find.byKey(const Key('training-center-play')), findsNothing);
    expect(find.byKey(const Key('training-primary')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('training-reset'))).bottom,
      lessThanOrEqualTo(300),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('training-primary')));
    await tester.pump();
    expect(fake.starts, 1);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('portrait suspends listening without losing training progress', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = TrainingAudioFake();
    await launch(tester, fake);
    await startExercise(tester, fake);
    fake.strike(60, startMs: 440);
    await tester.pump();
    expect(find.text('1 / 3 nut'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump();
    expect(fake.stops, 1);
    expect(find.text('Ćwiczenie wstrzymane'), findsOneWidget);
    expect(find.text('1 / 3 nut'), findsOneWidget);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    expect(fake.starts, 1);
    expect(find.text('Wznów'), findsOneWidget);
    expect(find.text('1 / 3 nut'), findsOneWidget);
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

  testWidgets(
    'import to completed practice rejects wrong notes and held repetitions',
    (tester) async {
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

      await startExercise(tester, fake);
      fake.strike(67, startMs: 440); // Wrong G4, expected C4.
      await tester.pump();
      expect(find.text('0 / 3 nut'), findsOneWidget);
      expect(find.text('Inna nuta. Spróbuj ponownie.'), findsOneWidget);

      fake.release(startMs: 830);
      fake.strike(60, startMs: 1220);
      await tester.pump();
      expect(find.text('1 / 3 nut'), findsOneWidget);

      fake.tone(60, 1610); // Still held: cannot score the second C4.
      await tester.pump();
      expect(find.text('1 / 3 nut'), findsOneWidget);
      fake.release(startMs: 1740);
      fake.strike(60, startMs: 2130);
      await tester.pump();
      expect(find.text('2 / 3 nut'), findsOneWidget);
      expect(find.text('Oczekiwana: E4'), findsOneWidget);

      fake.release(startMs: 2520);
      fake.strike(64, startMs: 2910);
      await tester.pump();
      expect(find.byKey(const Key('training-completed')), findsOneWidget);
      expect(find.text('3 / 3 nut'), findsOneWidget);
      expect(fake.starts, 1);
      expect(fake.stops, 1);
    },
  );
}

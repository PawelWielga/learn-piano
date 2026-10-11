import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_input.dart';
import 'package:learn_piano/src/audio/note_output.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/midi_recording_export.dart';
import 'package:learn_piano/src/screens/recording_screen.dart';
import 'package:learn_piano/src/widgets/recording_keyboard.dart';

class _FakeInput implements AudioInput {
  final frameController = StreamController<PcmFrame>.broadcast(sync: true);
  final statusController =
      StreamController<AudioInputStatus>.broadcast(sync: true);
  int started = 0;
  int stopped = 0;

  @override
  Stream<PcmFrame> get frames => frameController.stream;
  @override
  Stream<AudioInputStatus> get statuses => statusController.stream;

  @override
  Future<void> start() async {
    started++;
    statusController.add(AudioInputStatus.listening);
  }

  @override
  Future<void> stop() async {
    stopped++;
    statusController.add(AudioInputStatus.stopped);
  }

  void tone(int ms) {
    frameController.add(PcmFrame(
      samples: Float32List.fromList(List.generate(
        2048, (i) => 0.35 * math.sin(2 * math.pi * 440 * i / 48000),
      )),
      sampleRate: 48000,
      capturedAt: Duration(milliseconds: ms),
    ));
  }

  void silence(int ms) {
    frameController.add(PcmFrame(
      samples: Float32List(2048),
      sampleRate: 48000,
      capturedAt: Duration(milliseconds: ms),
    ));
  }

  @override
  Future<void> dispose() async {
    await stop();
    await frameController.close();
    await statusController.close();
  }
}

class _FakeOutput implements NoteOutput {
  int pressed = 0;
  int released = 0;

  @override
  bool noteOn(int midiNote) {
    pressed++;
    return true;
  }
  @override
  void noteOff(int midiNote) => released++;
  @override
  void stopAll() {}
  @override
  void dispose() {}
}

class _FakeExporter implements MidiRecordingExporter {
  Uint8List? bytes;
  String? fileName;

  @override
  bool save(Uint8List data, String name) {
    bytes = data;
    fileName = name;
    return true;
  }
}

void main() {
  void useLandscape(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('microphone recording saves detected notes as importable MIDI', (
    tester,
  ) async {
    useLandscape(tester);
    final input = _FakeInput();
    final exporter = _FakeExporter();
    await tester.pumpWidget(MaterialApp(
      home: RecordingScreen(
        audioInput: input,
        noteOutput: _FakeOutput(),
        exporter: exporter,
      ),
    ));

    expect(input.started, 0);
    await tester.tap(find.byKey(const Key('recording-start')));
    await tester.pump();
    expect(input.started, 1);

    input.tone(50);
    input.tone(180);
    input.tone(310);
    input.silence(440);
    input.silence(570);
    input.silence(700);
    await tester.pump();
    expect(find.textContaining('Nagrywanie trwa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recording-stop')));
    await tester.pump();
    expect(input.stopped, 1);
    expect(find.text('Zarejestrowane nuty: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recording-save')));
    await tester.pump();

    expect(exporter.fileName, endsWith('.mid'));
    final file = const MidiParser().parse(exporter.bytes!);
    expect(file.noteCount, 1);
    expect(file.tracks.single.notes.single.midiNote, 69);
  });

  testWidgets('keyboard records touch NoteOn and NoteOff', (tester) async {
    useLandscape(tester);
    final output = _FakeOutput();
    final exporter = _FakeExporter();
    final input = _FakeInput();
    await tester.pumpWidget(MaterialApp(
      home: RecordingScreen(
        audioInput: input,
        noteOutput: output,
        exporter: exporter,
      ),
    ));
    await tester.tap(find.text('Klawiatura ekranowa'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recording-start')));
    await tester.pump();

    final rect = tester.getRect(find.byType(RecordingKeyboard));
    final finger = await tester.startGesture(
      Offset(rect.center.dx, rect.bottom - 18),
    );
    await tester.pump();
    await finger.up();
    await tester.pump();

    expect(output.pressed, 1);
    expect(output.released, 1);
    await tester.tap(find.byKey(const Key('recording-stop')));
    await tester.pump();
    expect(find.text('Zarejestrowane nuty: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recording-save')));
    await tester.pump();

    expect(const MidiParser().parse(exporter.bytes!).noteCount, 1);
    expect(input.started, 0);
  });

  testWidgets('interruption ends recording without losing confirmed notes', (
    tester,
  ) async {
    useLandscape(tester);
    final input = _FakeInput();
    await tester.pumpWidget(MaterialApp(
      home: RecordingScreen(
        audioInput: input,
        noteOutput: _FakeOutput(),
        exporter: _FakeExporter(),
      ),
    ));
    await tester.tap(find.byKey(const Key('recording-start')));
    await tester.pump();
    input.tone(50);
    input.tone(180);
    input.tone(310);
    await tester.pump();
    input.statusController.add(AudioInputStatus.interrupted);
    await tester.pump();
    expect(find.textContaining('Mikrofon został przerwany'), findsOneWidget);
    expect(find.text('Zarejestrowane nuty: 1'), findsOneWidget);
    expect(input.stopped, 1);
  });
}

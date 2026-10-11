import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/learn_piano_app.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';

import 'midi_fixtures.dart';

class FakeMidiFilePicker implements MidiFilePicker {
  PickedMidiFile? next;
  bool fail = false;
  int calls = 0;

  @override
  Future<PickedMidiFile?> pick() async {
    calls++;
    if (fail) throw const MidiFilePickException('Nie można otworzyć pliku.');
    return next;
  }
}

void main() {
  final valid = midiFixture(
    format: 0,
    tracks: [
      trackBytes([
        trackName('Piano'),
        event(0, [0x90, 60, 100]),
        event(480, [0x80, 60, 0]),
        endOfTrack(),
      ]),
    ],
  );

  testWidgets('home opens MIDI import, without requesting a microphone', (
    tester,
  ) async {
    await tester.pumpWidget(const LearnPianoApp());
    await tester.tap(find.byKey(const Key('open-midi-import')));
    await tester.pumpAndSettle();

    expect(find.text('Import MIDI'), findsOneWidget);
    expect(find.byKey(const Key('choose-midi-file')), findsOneWidget);
    expect(find.textContaining('Nie wysyłamy'), findsOneWidget);
  });

  testWidgets('shows metadata and preview of imported local MIDI', (
    tester,
  ) async {
    final picker = FakeMidiFilePicker()
      ..next = PickedMidiFile(name: 'melody.MIDI', bytes: valid);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );

    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.text('Wczytano: melody.MIDI'), findsOneWidget);
    expect(find.textContaining('Typ 0'), findsOneWidget);
    expect(find.textContaining('480 PPQ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('melody-part-0-0')),
      150,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('melody-part-0-0'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(find.text('Piano'), findsOneWidget);
    expect(find.textContaining('C4'), findsWidgets);
  });

  testWidgets('rejects corrupt files and can recover with another import', (
    tester,
  ) async {
    final picker = FakeMidiFilePicker()
      ..next = PickedMidiFile(name: 'broken.mid', bytes: Uint8List(4));
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('midi-import-error')), findsOneWidget);
    expect(find.byKey(const Key('midi-file-name')), findsNothing);

    picker.next = PickedMidiFile(name: 'fixed.mid', bytes: valid);
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('midi-import-error')), findsNothing);
    expect(find.text('Wczytano: fixed.mid'), findsOneWidget);
  });

  testWidgets('invalid extension and failed chooser show readable errors', (
    tester,
  ) async {
    final picker = FakeMidiFilePicker()
      ..next = PickedMidiFile(name: 'notes.txt', bytes: valid);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );

    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.textContaining('rozszerzeniem'), findsOneWidget);

    picker.fail = true;
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.text('Nie można otworzyć pliku.'), findsOneWidget);

    picker.fail = false;
    picker.next = null;
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('midi-import-error')), findsNothing);
  });

  testWidgets('polyphonic MIDI can be selected and trained', (tester) async {
    final chords = midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 43, 90]),
          event(0, [0x90, 71, 90]),
          event(480, [0x80, 43, 0]),
          event(0, [0x80, 71, 0]),
          endOfTrack(),
        ]),
      ],
    );
    final picker = FakeMidiFilePicker()
      ..next = PickedMidiFile(name: 'chords.mid', bytes: chords);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('melody-part-0-0')),
      160,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('melody-part-0-0'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('melody-part-0-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-melody')), findsOneWidget);
    expect(find.byKey(const Key('start-midi-training')), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('start-midi-training'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-midi-training')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

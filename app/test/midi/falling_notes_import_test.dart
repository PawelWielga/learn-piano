import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';

import 'midi_fixtures.dart';

class _Picker implements MidiFilePicker {
  @override
  Future<PickedMidiFile?> pick() async => PickedMidiFile(
    name: 'exercise.mid',
    bytes: midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          event(240, [0x90, 62, 100]),
          event(480, [0x80, 62, 0]),
          event(240, [0x90, 64, 100]),
          event(480, [0x80, 64, 0]),
          endOfTrack(),
        ]),
      ],
    ),
  );
}

void main() {
  testWidgets('MIDI selection presents a stationary step-through piano roll', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: _Picker())),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    final part = find.byKey(const Key('melody-part-0-0'));
    await tester.scrollUntilVisible(
      part,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(part), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(part);
    await tester.pumpAndSettle();

    final next = find.byKey(const Key('midi-preview-next'));
    await tester.scrollUntilVisible(
      next,
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(next), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('falling-notes-view')), findsOneWidget);
    expect(find.textContaining('Teraz: C4'), findsOneWidget);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.textContaining('Teraz: D4'), findsOneWidget);

    final previous = find.byKey(const Key('midi-preview-previous'));
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.textContaining('Teraz: C4'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(previous).onPressed, isNull);

    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.textContaining('Teraz: E4'), findsOneWidget);
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
  });
}

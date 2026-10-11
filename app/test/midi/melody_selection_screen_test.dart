import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';

import 'midi_fixtures.dart';

class MelodyPickerFake implements MidiFilePicker {
  PickedMidiFile? current;

  @override
  Future<PickedMidiFile?> pick() async => current;
}

Future<void> reveal(WidgetTester tester, Finder finder, double delta) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selects melody by track while also offering chord practice', (
    tester,
  ) async {
    final bytes = midiFixture(
      format: 1,
      tracks: [
        trackBytes([trackName('Information'), endOfTrack()]),
        trackBytes([
          trackName('Chords'),
          event(0, [0x90, 60, 90]),
          event(0, [0x90, 64, 90]),
          event(480, [0x80, 60, 0]),
          event(0, [0x80, 64, 0]),
          endOfTrack(),
        ]),
        trackBytes([
          trackName('Melody'),
          event(0, [0x90, 72, 99]),
          event(480, [0x80, 72, 0]),
          event(240, [0x90, 74, 99]),
          event(240, [0x80, 74, 0]),
          endOfTrack(),
        ]),
      ],
    );
    final picker = MelodyPickerFake()
      ..current = PickedMidiFile(name: 'song.mid', bytes: bytes);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('melody-selection-hint')), findsOneWidget);
    await reveal(tester, find.textContaining('Pusta ścieżka'), 160);
    expect(find.textContaining('Pusta ścieżka'), findsOneWidget);

    await reveal(tester, find.byKey(const Key('melody-part-1-0')), 200);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('melody-part-1-0'))).onTap,
      isNotNull,
    );
    expect(find.textContaining('Akordy/nakładające się nuty'), findsWidgets);

    await reveal(tester, find.byKey(const Key('melody-part-2-0')), 180);
    await tester.tap(find.byKey(const Key('melody-part-2-0')));
    await tester.pump();

    await reveal(tester, find.byKey(const Key('selected-melody')), -180);
    expect(find.text('Wybrana melodia'), findsOneWidget);
    expect(find.textContaining('kanał 1'), findsWidgets);
    expect(find.textContaining('C5–D5'), findsOneWidget);
  });

  testWidgets('splits a multi-channel type 0 file and blocks percussion', (
    tester,
  ) async {
    final bytes = midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 100]),
          event(0, [0x91, 48, 90]),
          event(0, [0x99, 36, 85]),
          event(480, [0x80, 60, 0]),
          event(0, [0x81, 48, 0]),
          event(0, [0x89, 36, 0]),
          endOfTrack(),
        ]),
      ],
    );
    final picker = MelodyPickerFake()
      ..current = PickedMidiFile(name: 'multi.mid', bytes: bytes);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();

    await reveal(tester, find.byKey(const Key('melody-part-0-9')), 170);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('melody-part-0-9'))).onTap,
      isNull,
    );
    expect(find.textContaining('Perkusja:'), findsOneWidget);

    await reveal(tester, find.byKey(const Key('melody-part-0-1')), -150);
    await tester.tap(find.byKey(const Key('melody-part-0-1')));
    await tester.pump();
    await reveal(tester, find.byKey(const Key('selected-melody')), -150);
    expect(find.textContaining('kanał 2'), findsWidgets);
    expect(find.textContaining('C3–C3'), findsWidgets);
  });

  testWidgets('switching to a different file clears stale selection', (
    tester,
  ) async {
    final simple = midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 100]),
          event(480, [0x80, 60, 0]),
          endOfTrack(),
        ]),
      ],
    );
    final picker = MelodyPickerFake()
      ..current = PickedMidiFile(name: 'first.mid', bytes: simple);
    await tester.pumpWidget(
      MaterialApp(home: MidiImportScreen(filePicker: picker)),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('melody-part-0-0')), 150);
    await tester.tap(find.byKey(const Key('melody-part-0-0')));
    await tester.pump();
    await reveal(tester, find.byKey(const Key('selected-melody')), -150);
    expect(find.byKey(const Key('selected-melody')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('choose-midi-file')), -150);

    picker.current = PickedMidiFile(
      name: 'empty.mid',
      bytes: midiFixture(
        format: 0,
        tracks: [
          trackBytes([endOfTrack()]),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    expect(find.text('Wczytano: empty.mid'), findsOneWidget);
    expect(find.byKey(const Key('selected-melody')), findsNothing);
    expect(find.byKey(const Key('melody-selection-hint')), findsOneWidget);
  });
}

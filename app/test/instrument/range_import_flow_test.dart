import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/instrument/instrument_range_store.dart';
import 'package:learn_piano/src/midi/midi_file_picker.dart';
import 'package:learn_piano/src/screens/midi_import_screen.dart';

import '../midi/midi_fixtures.dart';

class RangeFilePicker implements MidiFilePicker {
  @override
  Future<PickedMidiFile?> pick() async => PickedMidiFile(
    name: 'range-test.mid',
    bytes: midiFixture(
      format: 0,
      tracks: [
        trackBytes([
          event(0, [0x90, 60, 90]),
          event(480, [0x80, 60, 0]),
          event(0, [0x90, 80, 90]),
          event(480, [0x80, 80, 0]),
          endOfTrack(),
        ]),
      ],
    ),
  );
}

class RangeStoreFake implements InstrumentRangeStore {
  InstrumentRange? saved = const InstrumentRange(60, 72);

  @override
  Future<InstrumentRange?> load() async => saved;

  @override
  Future<void> save(InstrumentRange range) async {
    saved = range;
  }
}

Future<void> reveal(WidgetTester tester, Finder finder, {double delta = 160}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('import -> select -> validate -> adjust physical range', (
    tester,
  ) async {
    final store = RangeStoreFake();
    await tester.pumpWidget(
      MaterialApp(
        home: MidiImportScreen(
          filePicker: RangeFilePicker(),
          rangeStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-midi-file')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('melody-part-0-0')));
    await tester.tap(find.byKey(const Key('melody-part-0-0')));
    await tester.pump();
    await reveal(tester, find.byKey(const Key('selected-range-blocked')));
    expect(
      find.textContaining('Poza zakresem instrumentu: 1 nut'),
      findsOneWidget,
    );

    await reveal(tester, find.byKey(const Key('selected-open-range')));
    await tester.tap(find.byKey(const Key('selected-open-range')));
    await tester.pumpAndSettle();
    expect(find.text('Zakres klawiatury'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('range-outside-warning')));
    expect(find.textContaining('C4'), findsWidgets);
    expect(find.textContaining('G#5'), findsWidgets);

    await reveal(
      tester,
      find.byKey(const Key('range-preset-88')),
      delta: -160,
    );
    await tester.tap(find.byKey(const Key('range-preset-88')));
    await tester.pump();
    await reveal(tester, find.byKey(const Key('range-playable')));
    expect(find.textContaining('Wszystkie 2 nut'), findsOneWidget);

    await reveal(tester, find.byKey(const Key('range-save')));
    await tester.tap(find.byKey(const Key('range-save')));
    await tester.pumpAndSettle();

    expect(store.saved, const InstrumentRange(21, 108));
    await reveal(tester, find.byKey(const Key('selected-range-ok')));
    expect(find.byKey(const Key('selected-range-blocked')), findsNothing);
    expect(find.textContaining('A0–C8'), findsOneWidget);
  });
}

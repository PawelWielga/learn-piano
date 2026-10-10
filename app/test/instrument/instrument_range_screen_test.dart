import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/instrument/instrument_range_store.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/screens/instrument_range_screen.dart';

class TestRangeStore implements InstrumentRangeStore {
  InstrumentRange? saved;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;

  @override
  Future<InstrumentRange?> load() async {
    if (failRead) throw StateError('storage unavailable');
    return saved;
  }

  @override
  Future<void> save(InstrumentRange range) async {
    if (failWrite) throw StateError('storage unavailable');
    saved = range;
    writes++;
  }
}

Future<void> visible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

MelodySelection song(List<int> pitches) {
  final notes = <MidiNote>[
    for (var i = 0; i < pitches.length; i++)
      MidiNote(
        trackIndex: 0,
        channel: 0,
        midiNote: pitches[i],
        velocity: 90,
        startTick: i * 480,
        endTick: (i + 1) * 480,
        start: Duration(milliseconds: i * 500),
        duration: const Duration(milliseconds: 500),
      ),
  ];
  return MelodySelection(
    MelodyPart(
      trackIndex: 0,
      trackName: 'Practice',
      channel: 0,
      notes: notes,
      overlapCount: 0,
      minMidiNote: pitches.reduce((a, b) => a < b ? a : b),
      maxMidiNote: pitches.reduce((a, b) => a > b ? a : b),
      start: Duration.zero,
      duration: Duration(milliseconds: pitches.length * 500),
    ),
  );
}

void main() {
  testWidgets('loads stored keyboard range on open', (tester) async {
    final store = TestRangeStore()..saved = const InstrumentRange(48, 84);
    await tester.pumpWidget(
      MaterialApp(home: InstrumentRangeScreen(rangeStore: store)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('C3–C6 (37 klawiszy)'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('range-preset-37')))
          .selected,
      isTrue,
    );
  });

  testWidgets('presets and semitone changes can be saved locally', (
    tester,
  ) async {
    final store = TestRangeStore();
    await tester.pumpWidget(
      MaterialApp(home: InstrumentRangeScreen(rangeStore: store)),
    );
    await visible(tester, find.byKey(const Key('range-preset-49')));
    await tester.tap(find.byKey(const Key('range-preset-49')));
    await tester.pump();
    expect(find.textContaining('C3–C7 (49 klawiszy)'), findsOneWidget);

    await visible(tester, find.byKey(const Key('range-low-increase')));
    await tester.tap(find.byKey(const Key('range-low-increase')));
    await tester.pump();
    expect(find.textContaining('C#3–C7 (48 klawiszy)'), findsOneWidget);

    await visible(tester, find.byKey(const Key('range-save')));
    await tester.tap(find.byKey(const Key('range-save')));
    await tester.pumpAndSettle();
    expect(store.saved, const InstrumentRange(49, 96));
    expect(store.writes, 1);
  });

  testWidgets('invalid endpoints disable saving until repaired', (
    tester,
  ) async {
    final store = TestRangeStore();
    await tester.pumpWidget(
      MaterialApp(
        home: InstrumentRangeScreen(
          initialRange: const InstrumentRange(60, 60),
          rangeStore: store,
        ),
      ),
    );
    await visible(tester, find.byKey(const Key('range-low-increase')));
    await tester.tap(find.byKey(const Key('range-low-increase')));
    await tester.pump();

    expect(find.byKey(const Key('range-invalid')), findsOneWidget);
    await visible(tester, find.byKey(const Key('range-save')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('range-save')))
          .onPressed,
      isNull,
    );
    expect(store.writes, 0);
    await visible(tester, find.byKey(const Key('range-high-increase')));
    await tester.tap(find.byKey(const Key('range-high-increase')));
    await tester.pump();
    expect(find.byKey(const Key('range-invalid')), findsNothing);
    expect(find.textContaining('C#4–C#4 (1 klawiszy)'), findsOneWidget);
  });

  testWidgets('shows count and examples for notes outside keyboard bounds', (
    tester,
  ) async {
    final store = TestRangeStore();
    await tester.pumpWidget(
      MaterialApp(
        home: InstrumentRangeScreen(
          initialRange: const InstrumentRange(60, 72),
          selection: song([59, 60, 72, 73, 59]),
          rangeStore: store,
        ),
      ),
    );
    await visible(tester, find.byKey(const Key('range-outside-warning')));
    expect(find.textContaining('Poza zakresem: 3 z 5 nut'), findsOneWidget);
    expect(find.textContaining('B3, C#5'), findsOneWidget);
    await visible(tester, find.byKey(const Key('range-preset-88')));
    await tester.tap(find.byKey(const Key('range-preset-88')));
    await tester.pump();
    await visible(tester, find.byKey(const Key('range-playable')));
    expect(find.textContaining('Wszystkie 5 nut'), findsOneWidget);
  });

  testWidgets('blocked storage offers use for current session', (tester) async {
    final store = TestRangeStore()..failWrite = true;
    await tester.pumpWidget(
      MaterialApp(home: InstrumentRangeScreen(rangeStore: store)),
    );
    await visible(tester, find.byKey(const Key('range-save')));
    await tester.tap(find.byKey(const Key('range-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('range-storage-warning')), findsOneWidget);
    expect(find.byKey(const Key('range-use-once')), findsOneWidget);
  });
}

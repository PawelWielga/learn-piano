import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/widgets/falling_notes_view.dart';
import 'package:learn_piano/src/widgets/piano_keyboard.dart';

MidiNote note(int pitch, int startMs, int lengthMs) => MidiNote(
  trackIndex: 0,
  channel: 0,
  midiNote: pitch,
  velocity: 90,
  startTick: startMs,
  endTick: startMs + lengthMs,
  start: Duration(milliseconds: startMs),
  duration: Duration(milliseconds: lengthMs),
);

void main() {
  test('uses keyboard coordinates and actual MIDI time for blocks', () {
    final keyboard = PianoKeyboardLayout(const InstrumentRange(60, 72));
    final notes = [note(60, 0, 500), note(61, 750, 250), note(64, 1000, 1000)];
    final layout = FallingNotesLayout(
      notes: notes,
      keyboard: keyboard,
      currentIndex: 0,
    );

    expect(layout.pixelsPerSecond, 88);
    expect(layout.visibleBlocks.length, 3);
    final first = layout.visibleBlocks[0].rect;
    final second = layout.visibleBlocks[1].rect;
    final third = layout.visibleBlocks[2].rect;
    expect(
      first.center.dx,
      closeTo(keyboard.keyForMidi(60)!.rect.center.dx, 0.001),
    );
    expect(
      second.center.dx,
      closeTo(keyboard.keyForMidi(61)!.rect.center.dx, 0.001),
    );
    expect(first.bottom, closeTo(layout.nowLineY, 0.001));
    expect(first.height, closeTo(44, 0.001)); // 500 ms at 88 px/s
    expect(second.height, closeTo(22, 0.001));
    expect(first.bottom - second.bottom, closeTo(66, 0.001)); // 750 ms
    expect(second.bottom - third.bottom, closeTo(22, 0.001)); // 250 ms
  });

  test('long rests adapt the scale and preserve five upcoming starts', () {
    final keyboard = PianoKeyboardLayout(const InstrumentRange(60, 72));
    final notes = List.generate(8, (i) => note(60 + i, i * 30000, 5000));
    final layout = FallingNotesLayout(
      notes: notes,
      keyboard: keyboard,
      currentIndex: 0,
    );

    expect(layout.pixelsPerSecond, lessThan(88));
    expect(
      layout.visibleBlocks.map((block) => block.index),
      containsAll([0, 1, 2, 3, 4, 5]),
    );
    expect(layout.visibleBlocks.first.rect.bottom, layout.nowLineY);
    expect(layout.visibleBlocks[5].rect.bottom, closeTo(24, 0.001));
  });

  test(
    'cursor controls the anchored note and zero-length note stays visible',
    () {
      final keyboard = PianoKeyboardLayout(const InstrumentRange(60, 72));
      final notes = [note(60, 0, 0), note(64, 300, 200), note(67, 800, 400)];
      final start = FallingNotesLayout(
        notes: notes,
        keyboard: keyboard,
        currentIndex: 0,
      );
      final next = FallingNotesLayout(
        notes: notes,
        keyboard: keyboard,
        currentIndex: 1,
      );

      expect(start.visibleBlocks.first.rect.height, 4);
      expect(next.visibleBlocks.first.index, 1);
      expect(next.visibleBlocks.first.rect.bottom, next.nowLineY);
      expect(next.visibleBlocks.last.index, 2);
    },
  );

  test('a changing playhead moves note blocks smoothly at a fixed scale', () {
    final keyboard = PianoKeyboardLayout(const InstrumentRange(60, 72));
    final notes = [note(60, 0, 500), note(64, 750, 300)];
    final start = FallingNotesLayout(
      notes: notes,
      keyboard: keyboard,
      currentIndex: 0,
      playhead: Duration.zero,
    );
    final advanced = FallingNotesLayout(
      notes: notes,
      keyboard: keyboard,
      currentIndex: 0,
      playhead: const Duration(milliseconds: 250),
    );

    expect(advanced.pixelsPerSecond, start.pixelsPerSecond);
    expect(
      advanced.visibleBlocks.first.rect.bottom -
          start.visibleBlocks.first.rect.bottom,
      closeTo(22, 0.001),
    );
    expect(
      advanced.visibleBlocks.last.rect.bottom -
          start.visibleBlocks.last.rect.bottom,
      closeTo(22, 0.001),
    );
  });

  test('does not lay out the entire long song per progress update', () {
    final keyboard = PianoKeyboardLayout(const InstrumentRange(60, 72));
    final notes = List.generate(20000, (i) => note(60 + i % 12, i * 250, 180));
    final layout = FallingNotesLayout(
      notes: notes,
      keyboard: keyboard,
      currentIndex: 10000,
    );

    expect(layout.visibleBlocks.length, lessThan(30));
    expect(layout.visibleBlocks.first.index, 10000);
  });

  testWidgets('keyboard and falling blocks scroll together with current note', (
    tester,
  ) async {
    final notes = [note(36, 0, 500), note(96, 800, 500)];

    Future<void> show(int index) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 230,
                child: FallingNotesView(
                  notes: notes,
                  range: const InstrumentRange(36, 96),
                  currentIndex: index,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(0);
    expect(find.byKey(const Key('falling-notes-canvas')), findsOneWidget);
    expect(find.textContaining('Teraz: C2'), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const Key('falling-notes-scroll')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    await show(1);
    expect(find.textContaining('Teraz: C7'), findsOneWidget);
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.001));

    // Unrelated rebuilds must not undo horizontal scrolling by the user.
    position.jumpTo(80);
    await tester.pump();
    await show(1);
    expect(position.pixels, 80);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/widgets/piano_keyboard.dart';

void main() {
  test('a full octave has seven white and five black keys', () {
    final layout = PianoKeyboardLayout(const InstrumentRange(60, 71));
    expect(layout.keys.length, 12);
    expect(layout.keys.where((key) => key.isBlack).length, 5);
    expect(layout.keys.where((key) => !key.isBlack).length, 7);

    final c = layout.keyForMidi(60)!;
    final cSharp = layout.keyForMidi(61)!;
    final d = layout.keyForMidi(62)!;
    expect(c.isBlack, isFalse);
    expect(cSharp.isBlack, isTrue);
    expect(cSharp.rect.center.dx, closeTo(c.rect.right, 0.001));
    expect(cSharp.rect.overlaps(c.rect), isTrue);
    expect(cSharp.rect.overlaps(d.rect), isTrue);
    expect(cSharp.rect.height, lessThan(c.rect.height));
    expect(layout.keyForMidi(72), isNull);
  });

  test('touch hit testing prefers overlapping black keys', () {
    final layout = PianoKeyboardLayout(const InstrumentRange(60, 72));
    final c = layout.keyForMidi(60)!;
    final sharp = layout.keyForMidi(61)!;
    expect(layout.noteAt(sharp.rect.center), 61);
    expect(layout.noteAt(c.rect.center), 60);
    expect(
      layout.noteAt(Offset(c.rect.center.dx, layout.height - 2)),
      60,
    );
    expect(layout.noteAt(const Offset(-5, 20)), isNull);
    expect(layout.noteAt(Offset(c.rect.center.dx, layout.height + 1)), isNull);
  });

  test('partial black-key ranges are shifted into visible bounds', () {
    final layout = PianoKeyboardLayout(const InstrumentRange(42, 61));
    expect(layout.keys.first.isBlack, isTrue); // F#2
    expect(layout.keys.last.isBlack, isTrue); // C#4
    expect(layout.keys.first.rect.left, closeTo(0, 0.001));
    expect(layout.keys.last.rect.right, closeTo(layout.width, 0.001));
    expect(layout.keys.every((key) => key.rect.left >= 0), isTrue);
    expect(layout.keys.every((key) => key.rect.right <= layout.width), isTrue);
  });

  test('one black key is a valid physical range', () {
    final layout = PianoKeyboardLayout(const InstrumentRange(61, 61));
    expect(layout.width, closeTo(24.8, 0.001));
    expect(layout.keys.single.rect.left, 0);
    expect(layout.keys.single.rect.right, layout.width);
  });

  testWidgets('shows distinct expected and detected notes including overlap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: PianoKeyboard(
              range: InstrumentRange(60, 72),
              expectedNote: 60,
              detectedNote: 61,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('piano-keyboard')), findsOneWidget);
    expect(find.textContaining('C4–C5 (13 klawiszy)'), findsOneWidget);
    expect(find.textContaining('Oczekiwana: C4'), findsOneWidget);
    expect(find.textContaining('Wykryta: C#4'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: PianoKeyboard(
              range: InstrumentRange(60, 72),
              expectedNote: 60,
              detectedNote: 60,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Oczekiwana: C4'), findsOneWidget);
    expect(find.textContaining('Wykryta: C4'), findsOneWidget);
  });

  testWidgets('centers active key in long range when it changes', (
    tester,
  ) async {
    Future<void> show(int note) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: PianoKeyboard(
                range: const InstrumentRange(21, 108),
                detectedNote: note,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(21);
    final scroller = find.descendant(
      of: find.byKey(const Key('piano-keyboard-scroll')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scroller).position;
    expect(position.pixels, 0);

    await show(108);
    expect(position.pixels, greaterThan(100));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.001));

    // A rendering update without a new focus must not override user scrolling.
    position.jumpTo(50);
    await tester.pump();
    await show(108);
    expect(position.pixels, 50);
  });

  testWidgets('identifies a note outside the selected keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PianoKeyboard(range: InstrumentRange(48, 72), expectedNote: 36),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('C2 (poza zakresem)'), findsOneWidget);
  });
}

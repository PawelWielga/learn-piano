import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/training/training_input_mode.dart';
import 'package:learn_piano/src/training/wait_for_note_engine.dart';
import 'package:learn_piano/src/widgets/piano_keyboard.dart';
import 'package:learn_piano/src/widgets/training_stage.dart';

MidiNote note(int pitch, int index) => MidiNote(
  trackIndex: 0,
  channel: 0,
  midiNote: pitch,
  velocity: 100,
  startTick: index * 480,
  endTick: (index + 1) * 480,
  start: Duration(milliseconds: index * 500),
  duration: const Duration(milliseconds: 500),
);

final melody = [note(60, 0), note(72, 1), note(84, 2)];
final otherMelody = [note(90, 0), note(91, 1)];

Widget stage({
  required List<MidiNote> notes,
  int currentIndex = 0,
  int? detectedNote,
  TrainingPhase phase = TrainingPhase.ready,
  InstrumentRange range = const InstrumentRange(48, 108),
}) => MaterialApp(
  home: Scaffold(
    body: TrainingStage(
      key: const Key('tested-training-stage'),
      notes: notes,
      range: range,
      phase: phase,
      currentIndex: currentIndex,
      progress: currentIndex / notes.length,
      expectedNote: currentIndex < notes.length
          ? notes[currentIndex].midiNote
          : null,
      detectedNote: detectedNote,
      lastAttempt: TrainingAttempt.ignored,
      phaseLabel: 'Trening',
      attemptLabel: 'Zagraj nutę',
      songTitle: 'Test',
      listening: false,
      busy: false,
      inputMode: TrainingInputMode.keyboard,
      onInputModeChanged: (_) {},
      onNoteDown: (_) {},
      onNoteUp: (_) {},
      onBack: () {},
      onPrimary: () {},
      onReset: () {},
    ),
  ),
);

ScrollPosition trainingScroll(WidgetTester tester) {
  final scroll = find.descendant(
    of: find.byKey(const Key('training-stage-scroll')),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scroll).position;
}

void main() {
  testWidgets('initial placement shows the melody range without tracking notes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(stage(notes: melody));
    await tester.pump();

    final scroll = trainingScroll(tester);
    final layout = PianoKeyboardLayout(
      const InstrumentRange(48, 108),
      whiteKeyWidth: math.max(38, 840 / 21),
      height: (390 * 0.32).clamp(110.0, 210.0),
    );
    final lower = layout.keyForMidi(60)!.rect;
    final upper = layout.keyForMidi(84)!.rect;
    final expectedInitial = ((lower.left + upper.right - 840) / 2)
        .clamp(0.0, scroll.maxScrollExtent)
        .toDouble();
    expect(scroll.pixels, closeTo(expectedInitial, 0.01));
    expect(scroll.pixels, greaterThan(0));

    // Advancing through widely spaced notes must only repaint highlights.
    await tester.pumpWidget(stage(
      notes: melody,
      currentIndex: 1,
      detectedNote: 72,
      phase: TrainingPhase.running,
    ));
    await tester.pump();
    expect(scroll.pixels, closeTo(expectedInitial, 0.01));

    await tester.pumpWidget(stage(
      notes: melody,
      currentIndex: 2,
      detectedNote: 84,
      phase: TrainingPhase.running,
    ));
    await tester.pump();
    expect(scroll.pixels, closeTo(expectedInitial, 0.01));

    // Manual scrolling persists through detected notes, pause and reset.
    final manuallyChosen = math.min(scroll.maxScrollExtent, expectedInitial + 175);
    scroll.jumpTo(manuallyChosen);
    await tester.pump();
    await tester.pumpWidget(stage(
      notes: melody,
      currentIndex: 3,
      detectedNote: 84,
      phase: TrainingPhase.completed,
    ));
    await tester.pump();
    expect(scroll.pixels, closeTo(manuallyChosen, 0.01));

    await tester.pumpWidget(stage(
      notes: melody,
      currentIndex: 0,
      phase: TrainingPhase.ready,
    ));
    await tester.pump();
    expect(scroll.pixels, closeTo(manuallyChosen, 0.01));
  });

  testWidgets('new melody picks a new initial position only once', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(stage(notes: melody));
    await tester.pump();
    final scroll = trainingScroll(tester);
    final firstOffset = scroll.pixels;

    await tester.pumpWidget(stage(notes: otherMelody));
    await tester.pump();
    final otherOffset = scroll.pixels;
    expect(otherOffset, greaterThan(firstOffset));

    // Even after a new initial layout, subsequent updates do not snap back.
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pumpWidget(stage(
      notes: otherMelody,
      currentIndex: 1,
      phase: TrainingPhase.running,
    ));
    await tester.pump();
    expect(scroll.pixels, 0);

    // Changing the available viewport should preserve an existing manual
    // scroll position rather than re-centering on the expected pitch.
    scroll.jumpTo(100);
    await tester.pump();
    tester.view.physicalSize = const Size(1000, 390);
    await tester.pump();
    await tester.pump();
    expect(scroll.pixels, closeTo(100, 0.01));
  });
}

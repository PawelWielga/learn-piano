import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../instrument/instrument_range.dart';
import '../midi/midi_parser.dart';
import '../pitch/pitch_detector.dart';
import 'piano_keyboard.dart';

/// Position and size of a MIDI note on a vertical, time-based piano roll.
class FallingNoteBlock {
  const FallingNoteBlock(this.index, this.rect);

  final int index;
  final Rect rect;
}

/// Pure geometry: current MIDI note starts at the "teraz" line; later notes
/// appear above it. The caller owns progress, so time never advances on its own.
class FallingNotesLayout {
  FallingNotesLayout({
    required this.notes,
    required this.keyboard,
    required this.currentIndex,
    this.height = 260,
  }) : assert(notes.isNotEmpty),
       assert(currentIndex >= 0 && currentIndex < notes.length),
       assert(height > 48) {
    final anchorMicros = notes[currentIndex].start.inMicroseconds;
    // Keep up to five upcoming note starts in view even across long rests.
    // One scale applies to both start offsets and durations.
    final lookAhead = math.min(currentIndex + 5, notes.length - 1);
    final lookAheadMicros = notes[lookAhead].start.inMicroseconds - anchorMicros;
    pixelsPerSecond = math.min(
      88.0,
      (nowLineY - 24) * 1000000 / math.max(1, lookAheadMicros),
    );

    final blocks = <FallingNoteBlock>[];
    for (var i = currentIndex; i < notes.length; i++) {
      final note = notes[i];
      final key = keyboard.keyForMidi(note.midiNote);
      if (key == null) continue;
      final sinceAnchor = note.start.inMicroseconds - anchorMicros;
      final bottom = nowLineY - sinceAnchor * pixelsPerSecond / 1000000;
      if (bottom < -4) break;
      // Zero-length MIDI notes still get a small visible marker.
      final length = math.max(
        4.0,
        note.duration.inMicroseconds * pixelsPerSecond / 1000000,
      );
      final width = math.min(
        key.rect.width * 0.8,
        keyboard.whiteKeyWidth * 0.82,
      );
      final rect = Rect.fromLTWH(
        key.rect.center.dx - width / 2,
        bottom - length,
        width,
        length,
      );
      if (rect.bottom >= 0 && rect.top <= height) {
        blocks.add(FallingNoteBlock(i, rect));
      }
    }
    visibleBlocks = List.unmodifiable(blocks);
  }

  final List<MidiNote> notes;
  final PianoKeyboardLayout keyboard;
  final int currentIndex;
  final double height;
  late final double pixelsPerSecond;
  late final List<FallingNoteBlock> visibleBlocks;

  double get nowLineY => height - 18;
}

/// One shared horizontal coordinate system for blocks and physical keys.
class FallingNotesView extends StatefulWidget {
  const FallingNotesView({
    super.key,
    required this.notes,
    required this.range,
    required this.currentIndex,
  }) : assert(notes.length > 0),
       assert(currentIndex >= 0 && currentIndex < notes.length);

  final List<MidiNote> notes;
  final InstrumentRange range;
  final int currentIndex;

  @override
  State<FallingNotesView> createState() => _FallingNotesViewState();
}

class _FallingNotesViewState extends State<FallingNotesView> {
  final ScrollController _controller = ScrollController();
  int? _lastFocus;
  InstrumentRange? _lastRange;
  double? _lastViewport;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _focus(PianoKeyboardLayout keyboard, double viewportWidth) {
    final note = widget.notes[widget.currentIndex].midiNote;
    if (_lastFocus == note &&
        _lastRange == widget.range &&
        _lastViewport == viewportWidth) {
      return;
    }
    _lastFocus = note;
    _lastRange = widget.range;
    _lastViewport = viewportWidth;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final key = keyboard.keyForMidi(note);
      if (key == null) return;
      final target = (key.rect.center.dx - viewportWidth / 2).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      _controller.jumpTo(target.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    const expectedColor = Color(0xFF00796D);
    const futureColor = Color(0xFF347CB5);
    final currentNote = widget.notes[widget.currentIndex];
    final keyboard = PianoKeyboardLayout(widget.range, height: 128);
    final layout = FallingNotesLayout(
      notes: widget.notes,
      keyboard: keyboard,
      currentIndex: widget.currentIndex,
    );

    return Column(
      key: const Key('falling-notes-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Teraz: ${PitchEstimate.nameForMidi(currentNote.midiNote)} • '
          'nuta ${widget.currentIndex + 1} z ${widget.notes.length}',
          key: const Key('falling-current-note'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Zielona: oczekiwana • niebieskie: kolejne • linia: teraz',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            _focus(keyboard, constraints.maxWidth);
            return Semantics(
              label: 'Podgląd melodii nad klawiaturą, przewijany poziomo. '
                  'Teraz ${PitchEstimate.nameForMidi(currentNote.midiNote)}, '
                  'nuta ${widget.currentIndex + 1} z ${widget.notes.length}.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  key: const Key('falling-notes-scroll'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: keyboard.width,
                    child: Column(
                      children: [
                        SizedBox(
                          width: keyboard.width,
                          height: layout.height,
                          child: CustomPaint(
                            key: const Key('falling-notes-canvas'),
                            painter: _FallingNotesPainter(
                              layout: layout,
                              currentColor: expectedColor,
                              futureColor: futureColor,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: keyboard.width,
                          height: keyboard.height,
                          child: CustomPaint(
                            painter: PianoKeyboardPainter(
                              layout: keyboard,
                              expectedNote: currentNote.midiNote,
                              detectedNote: null,
                              expectedColor: expectedColor,
                              detectedColor: const Color(0xFFAB5300),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'Przesuń podgląd w bok, aby zobaczyć inne klawisze. '
          'Widok nie odtwarza MIDI ani nie przesuwa się sam.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _FallingNotesPainter extends CustomPainter {
  const _FallingNotesPainter({
    required this.layout,
    required this.currentColor,
    required this.futureColor,
  });

  final FallingNotesLayout layout;
  final Color currentColor;
  final Color futureColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF15252D),
    );

    // Pitch guides share the exact x coordinates of the keyboard below.
    for (final key in layout.keyboard.keys) {
      canvas.drawLine(
        Offset(key.rect.center.dx, 0),
        Offset(key.rect.center.dx, size.height),
        Paint()
          ..color = key.isBlack
              ? const Color(0xFF3C4A52)
              : const Color(0xFF263842)
          ..strokeWidth = 1,
      );
    }

    for (final block in layout.visibleBlocks) {
      final current = block.index == layout.currentIndex;
      final fill = current ? currentColor : futureColor;
      final shape = RRect.fromRectAndRadius(
        block.rect,
        const Radius.circular(3),
      );
      canvas.drawRRect(shape, Paint()..color = fill);
      if (current) {
        canvas.drawRRect(
          shape,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    canvas.drawLine(
      Offset(0, layout.nowLineY),
      Offset(size.width, layout.nowLineY),
      Paint()
        ..color = const Color(0xFFFFC46B)
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FallingNotesPainter oldDelegate) =>
      oldDelegate.layout.notes != layout.notes ||
      oldDelegate.layout.currentIndex != layout.currentIndex ||
      oldDelegate.layout.keyboard.range != layout.keyboard.range;
}

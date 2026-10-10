import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../instrument/instrument_range.dart';
import '../pitch/pitch_detector.dart';

/// Geometry shared by the painter and the scroll-to-note behavior.
/// Black keys sit on the boundary between adjacent white keys, including
/// ranges that start or end with a black key.
class PianoKeyGeometry {
  const PianoKeyGeometry(this.midiNote, this.isBlack, this.rect);

  final int midiNote;
  final bool isBlack;
  final Rect rect;
}

class PianoKeyboardLayout {
  PianoKeyboardLayout(this.range, {this.whiteKeyWidth = 40, this.height = 160})
    : assert(whiteKeyWidth > 0),
      assert(height > 0) {
    final blackWidth = whiteKeyWidth * 0.62;
    final raw = <PianoKeyGeometry>[];
    for (var note = range.low; note <= range.high; note++) {
      final isBlack = isBlackKey(note);
      final position = _whiteIndex(note) * whiteKeyWidth;
      final rect = isBlack
          ? Rect.fromLTWH(
              position - blackWidth / 2,
              0,
              blackWidth,
              height * 0.63,
            )
          : Rect.fromLTWH(position, 0, whiteKeyWidth, height);
      raw.add(PianoKeyGeometry(note, isBlack, rect));
    }

    final left = raw.map((key) => key.rect.left).reduce(math.min);
    final right = raw.map((key) => key.rect.right).reduce(math.max);
    width = right - left;
    keys = List.unmodifiable(
      raw.map(
        (key) => PianoKeyGeometry(
          key.midiNote,
          key.isBlack,
          key.rect.shift(Offset(-left, 0)),
        ),
      ),
    );
  }

  final InstrumentRange range;
  final double whiteKeyWidth;
  final double height;
  late final double width;
  late final List<PianoKeyGeometry> keys;

  static const _whiteKeysBefore = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6];

  static bool isBlackKey(int note) =>
      const [1, 3, 6, 8, 10].contains(note % 12);

  static int _whiteIndex(int note) =>
      (note ~/ 12) * 7 + _whiteKeysBefore[note % 12];

  PianoKeyGeometry? keyForMidi(int note) =>
      range.contains(note) ? keys[note - range.low] : null;
}

/// Reusable view for MIDI preview, microphone tester and future training.
/// The range is physical (inclusive), not a normalized 88-key keyboard.
class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({
    super.key,
    required this.range,
    this.expectedNote,
    this.detectedNote,
    this.showRangeLabel = true,
  });

  final InstrumentRange range;
  final int? expectedNote;
  final int? detectedNote;
  final bool showRangeLabel;

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final ScrollController _scrollController = ScrollController();
  int? _lastFocus;
  InstrumentRange? _lastRange;
  double? _lastViewport;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _focusActiveNote(PianoKeyboardLayout layout, double viewportWidth) {
    final expected = widget.expectedNote;
    final detected = widget.detectedNote;
    final focus = expected != null && widget.range.contains(expected)
        ? expected
        : detected != null && widget.range.contains(detected)
        ? detected
        : null;

    if (_lastFocus == focus &&
        _lastRange == widget.range &&
        _lastViewport == viewportWidth) {
      return;
    }
    _lastFocus = focus;
    _lastRange = widget.range;
    _lastViewport = viewportWidth;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final key = focus == null ? null : layout.keyForMidi(focus);
      final desired = key == null
          ? 0.0
          : key.rect.center.dx - viewportWidth / 2;
      final clamped = desired.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(clamped.toDouble());
    });
  }

  String _noteLabel(int? note) {
    if (note == null) return '—';
    final name = PitchEstimate.nameForMidi(note);
    return widget.range.contains(note) ? name : '$name (poza zakresem)';
  }

  @override
  Widget build(BuildContext context) {
    final layout = PianoKeyboardLayout(widget.range);
    const expectedColor = Color(0xFF00796D);
    const detectedColor = Color(0xFFAB5300);

    return Column(
      key: const Key('piano-keyboard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showRangeLabel)
          Text(
            'Klawiatura: ${PitchEstimate.nameForMidi(widget.range.low)}–'
            '${PitchEstimate.nameForMidi(widget.range.high)} '
            '(${widget.range.keyCount} klawiszy)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            Text(
              '■ Oczekiwana: ${_noteLabel(widget.expectedNote)}',
              key: const Key('piano-expected-label'),
              style: const TextStyle(
                color: expectedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '■ Wykryta: ${_noteLabel(widget.detectedNote)}',
              key: const Key('piano-detected-label'),
              style: const TextStyle(
                color: detectedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth;
            _focusActiveNote(layout, viewportWidth);
            return Semantics(
              label: 'Klawiatura pianina, przewijana poziomo',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  key: const Key('piano-keyboard-scroll'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: layout.width,
                    height: layout.height,
                    child: CustomPaint(
                      painter: PianoKeyboardPainter(
                        layout: layout,
                        expectedNote: widget.expectedNote,
                        detectedNote: widget.detectedNote,
                        expectedColor: expectedColor,
                        detectedColor: detectedColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'Przesuń klawiaturę w bok, aby zobaczyć pozostałe klawisze.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class PianoKeyboardPainter extends CustomPainter {
  const PianoKeyboardPainter({
    required this.layout,
    required this.expectedNote,
    required this.detectedNote,
    required this.expectedColor,
    required this.detectedColor,
  });

  final PianoKeyboardLayout layout;
  final int? expectedNote;
  final int? detectedNote;
  final Color expectedColor;
  final Color detectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    // White keys first; black keys must overlap their white neighbors.
    for (final key in layout.keys.where((key) => !key.isBlack)) {
      _drawKey(canvas, key);
    }
    for (final key in layout.keys.where((key) => key.isBlack)) {
      _drawKey(canvas, key);
    }
  }

  void _drawKey(Canvas canvas, PianoKeyGeometry key) {
    final rect = key.rect;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    final base = key.isBlack
        ? const Color(0xFF20252B)
        : const Color(0xFFFDFDFD);
    canvas.drawRRect(shape, Paint()..color = base);

    final isExpected = key.midiNote == expectedNote;
    final isDetected = key.midiNote == detectedNote;
    if (isExpected || isDetected) {
      canvas.save();
      canvas.clipRRect(shape);
      if (isExpected && isDetected) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height / 2),
          Paint()..color = expectedColor,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left,
            rect.top + rect.height / 2,
            rect.width,
            rect.height / 2,
          ),
          Paint()..color = detectedColor,
        );
      } else {
        canvas.drawRRect(
          shape,
          Paint()..color = isExpected ? expectedColor : detectedColor,
        );
      }
      canvas.restore();
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = key.isBlack
            ? const Color(0xFF101418)
            : const Color(0xFF89949B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (!key.isBlack &&
        (key.midiNote % 12 == 0 ||
            key.midiNote == layout.range.low ||
            key.midiNote == layout.range.high)) {
      final label = TextPainter(
        text: TextSpan(
          text: PitchEstimate.nameForMidi(key.midiNote),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isExpected || isDetected
                ? Colors.white
                : const Color(0xFF303840),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 2);
      label.paint(
        canvas,
        Offset(
          rect.center.dx - label.width / 2,
          rect.bottom - label.height - 7,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PianoKeyboardPainter oldDelegate) =>
      oldDelegate.layout.range != layout.range ||
      oldDelegate.expectedNote != expectedNote ||
      oldDelegate.detectedNote != detectedNote;
}

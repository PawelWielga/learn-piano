import 'package:flutter/material.dart';

import '../instrument/instrument_range.dart';
import 'piano_keyboard.dart';

/// Touch-playable keyboard. It keeps its initial scroll position instead of
/// following recorded notes, and supports several simultaneous pointers.
class RecordingKeyboard extends StatefulWidget {
  const RecordingKeyboard({
    super.key,
    required this.range,
    required this.enabled,
    required this.onNoteDown,
    required this.onNoteUp,
  });

  final InstrumentRange range;
  final bool enabled;
  final ValueChanged<int> onNoteDown;
  final ValueChanged<int> onNoteUp;

  @override
  State<RecordingKeyboard> createState() => _RecordingKeyboardState();
}

class _RecordingKeyboardState extends State<RecordingKeyboard> {
  final ScrollController _scroll = ScrollController();
  final Map<int, int> _pressed = {};
  InstrumentRange? _positionedRange;

  void _release(int pointer) {
    final note = _pressed.remove(pointer);
    if (note == null) return;
    if (!_pressed.containsValue(note)) widget.onNoteUp(note);
    if (mounted) setState(() {});
  }

  void _press(PointerDownEvent event, PianoKeyboardLayout layout) {
    if (!widget.enabled || _pressed.containsKey(event.pointer)) return;
    final note = layout.noteAt(event.localPosition);
    if (note == null) return;
    final alreadyHeld = _pressed.containsValue(note);
    setState(() => _pressed[event.pointer] = note);
    if (!alreadyHeld) widget.onNoteDown(note);
  }

  @override
  void didUpdateWidget(RecordingKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.enabled && oldWidget.enabled) ||
        widget.range != oldWidget.range) {
      for (final note in _pressed.values.toSet()) {
        widget.onNoteUp(note);
      }
      _pressed.clear();
      if (widget.range != oldWidget.range) _positionedRange = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = PianoKeyboardLayout(
      widget.range,
      whiteKeyWidth: 42,
      height: 132,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_positionedRange != widget.range) {
          _positionedRange = widget.range;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final initialNote = 60
                .clamp(widget.range.low, widget.range.high)
                .toInt();
            final key = layout.keyForMidi(initialNote);
            final offset =
                (key?.rect.center.dx ?? 0) - constraints.maxWidth / 2;
            _scroll.jumpTo(
              offset.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
            );
          });
        }
        return SingleChildScrollView(
          key: const Key('recording-keyboard-scroll'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Listener(
            onPointerDown: (event) => _press(event, layout),
            onPointerMove: (event) {
              final held = _pressed[event.pointer];
              if (held != null && layout.noteAt(event.localPosition) != held) {
                _release(event.pointer);
              }
            },
            onPointerUp: (event) => _release(event.pointer),
            onPointerCancel: (event) => _release(event.pointer),
            child: SizedBox(
              width: layout.width,
              height: layout.height,
              child: CustomPaint(
                painter: PianoKeyboardPainter(
                  layout: layout,
                  expectedNote: null,
                  detectedNote: _pressed.isEmpty ? null : _pressed.values.last,
                  expectedColor: const Color(0xFF087E77),
                  detectedColor: const Color(0xFFAB5300),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

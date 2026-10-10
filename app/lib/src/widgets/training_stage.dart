import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../instrument/instrument_range.dart';
import '../midi/midi_parser.dart';
import '../pitch/pitch_detector.dart';
import '../training/wait_for_note_engine.dart';
import 'falling_notes_view.dart';
import 'piano_keyboard.dart';

/// A landscape-first, single-surface training view. The roll and keyboard
/// share one scroll position and one MIDI-to-X mapping.
class TrainingStage extends StatefulWidget {
  const TrainingStage({
    super.key,
    required this.notes,
    required this.range,
    required this.phase,
    required this.currentIndex,
    required this.progress,
    required this.expectedNote,
    required this.detectedNote,
    required this.lastAttempt,
    required this.phaseLabel,
    required this.attemptLabel,
    required this.songTitle,
    required this.listening,
    required this.busy,
    required this.onBack,
    required this.onPrimary,
    required this.onReset,
    this.error,
  });

  final List<MidiNote> notes;
  final InstrumentRange range;
  final TrainingPhase phase;
  final int currentIndex;
  final double progress;
  final int? expectedNote;
  final int? detectedNote;
  final TrainingAttempt lastAttempt;
  final String phaseLabel;
  final String attemptLabel;
  final String songTitle;
  final bool listening;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback? onPrimary;
  final VoidCallback? onReset;

  @override
  State<TrainingStage> createState() => _TrainingStageState();
}

class _TrainingStageState extends State<TrainingStage> {
  final ScrollController _scrollController = ScrollController();
  bool _showControls = true;
  int? _lastFocus;
  InstrumentRange? _lastRange;
  double? _lastWidth;

  @override
  void didUpdateWidget(TrainingStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      if (widget.phase == TrainingPhase.running) {
        _showControls = false;
      } else {
        _showControls = true;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _focus(PianoKeyboardLayout keyboard, double width) {
    final focus = widget.expectedNote ?? widget.detectedNote;
    if (_lastFocus == focus &&
        _lastRange == widget.range &&
        _lastWidth == width) {
      return;
    }
    _lastFocus = focus;
    _lastRange = widget.range;
    _lastWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final key = focus == null ? null : keyboard.keyForMidi(focus);
      final target = key == null
          ? 0.0
          : (key.rect.center.dx - width / 2).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            );
      _scrollController.jumpTo(target.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = _showControls || widget.phase != TrainingPhase.running;
    final completed = widget.phase == TrainingPhase.completed;
    final expected = widget.expectedNote == null
        ? '—'
        : PitchEstimate.nameForMidi(widget.expectedNote!);
    final detected = widget.detectedNote == null
        ? '—'
        : PitchEstimate.nameForMidi(widget.detectedNote!);
    const accent = Color(0xFFD547E9);
    const foreground = Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final keyboardHeight = (height * 0.32).clamp(110.0, 210.0);
        final keyboard = PianoKeyboardLayout(
          widget.range,
          whiteKeyWidth: math.max(38.0, width / 21),
          height: keyboardHeight,
        );
        final rollHeight = height - keyboardHeight;
        _focus(keyboard, width);
        final focusedIndex = widget.notes.isEmpty
            ? 0
            : widget.currentIndex.clamp(0, widget.notes.length - 1).toInt();
        final roll = widget.notes.isEmpty || rollHeight <= 48
            ? null
            : FallingNotesLayout(
                notes: widget.notes,
                keyboard: keyboard,
                currentIndex: focusedIndex,
                height: rollHeight,
              );

        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: 'Nutowy widok ćwiczenia i przewijana klawiatura pianina',
                child: SingleChildScrollView(
                  key: const Key('training-stage-scroll'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(width, keyboard.width),
                    height: height,
                    child: CustomPaint(
                      key: const Key('training-stage-canvas'),
                      painter: _TrainingStagePainter(
                        keyboard: keyboard,
                        roll: completed ? null : roll,
                        expectedNote: widget.expectedNote,
                        detectedNote: widget.detectedNote,
                        rollHeight: rollHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showOverlay)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x29000000)),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: const Color(0xB710071D),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('training-change-song'),
                      tooltip: 'Zmień utwór',
                      color: foreground,
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.currentIndex} / ${widget.notes.length} nut',
                      key: const Key('training-progress-label'),
                      style: const TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          key: const Key('training-progress'),
                          value: widget.progress,
                          minHeight: 9,
                          backgroundColor: const Color(0xFF292131),
                          valueColor: const AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.circle,
                      size: 11,
                      color: widget.listening
                          ? const Color(0xFF00D36B)
                          : const Color(0xFF77727B),
                    ),
                    IconButton(
                      key: const Key('training-primary'),
                      tooltip: widget.phase == TrainingPhase.running
                          ? 'Pauza'
                          : widget.phase == TrainingPhase.paused
                          ? 'Wznów'
                          : 'Start i mikrofon',
                      onPressed: widget.busy ? null : widget.onPrimary,
                      color: foreground,
                      icon: Icon(
                        widget.phase == TrainingPhase.running
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                    IconButton(
                      key: const Key('training-reset'),
                      tooltip: 'Reset',
                      onPressed: widget.busy ? null : widget.onReset,
                      color: foreground,
                      icon: const Icon(Icons.restart_alt),
                    ),
                    IconButton(
                      key: const Key('training-controls-toggle'),
                      tooltip: showOverlay ? 'Ukryj panel' : 'Pokaż panel',
                      onPressed: () =>
                          setState(() => _showControls = !_showControls),
                      color: foreground,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 48,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.phaseLabel,
                    key: const Key('training-phase'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Oczekiwana: $expected',
                        key: const Key('training-expected'),
                        style: const TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Wykryta: $detected',
                        key: const Key('training-detected'),
                        style: const TextStyle(color: foreground, fontSize: 12),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          widget.listening
                              ? 'Mikrofon aktywny. Dźwięk jest analizowany lokalnie.'
                              : 'Mikrofon wyłączony. Dźwięk nie jest wysyłany na serwer.',
                          key: const Key('training-microphone-status'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAA6B2),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (showOverlay &&
                !completed &&
                widget.phase != TrainingPhase.error)
              Positioned(
                top: 91,
                left: 12,
                right: 12,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xF0181021),
                        border: Border.all(color: const Color(0xFF5A4663)),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            TextButton.icon(
                              key: const Key('training-mic-control'),
                              onPressed: widget.busy ? null : widget.onPrimary,
                              icon: Icon(
                                widget.listening ? Icons.mic : Icons.mic_none,
                              ),
                              label: Text(widget.listening ? 'Mic ON' : 'Mic'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(68, 44),
                                foregroundColor: foreground,
                                backgroundColor: widget.listening
                                    ? const Color(0xFF7B258F)
                                    : const Color(0xFF392341),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.check_circle, color: accent),
                            const SizedBox(width: 4),
                            const Text(
                              'Wait Mode',
                              style: TextStyle(color: foreground),
                            ),
                            const SizedBox(width: 16),
                            const Tooltip(
                              message: 'Zmiana tempa nie jest dostępna w trybie Wait for Note.',
                              child: _UnavailableControl(label: '1.0× Tempo'),
                            ),
                            const SizedBox(width: 8),
                            const Tooltip(
                              message:
                                  'Wybór ręki będzie dostępny w przyszłości.',
                              child: _UnavailableControl(label: 'L   Both   R'),
                            ),
                            const SizedBox(width: 8),
                            const Tooltip(
                              message:
                                  'Akompaniament nie jest jeszcze obsługiwany.',
                              child: _UnavailableControl(label: 'Accomp.'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (showOverlay &&
                widget.phase != TrainingPhase.running &&
                widget.phase != TrainingPhase.error &&
                !completed)
              Positioned(
                top: math.max(155, rollHeight * 0.64 - 30),
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filled(
                        key: const Key('training-center-play'),
                        tooltip: widget.phase == TrainingPhase.paused
                            ? 'Wznów ćwiczenie'
                            : 'Rozpocznij ćwiczenie',
                        onPressed: widget.busy ? null : widget.onPrimary,
                        iconSize: 38,
                        color: foreground,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xD1483E50),
                          minimumSize: const Size(70, 70),
                        ),
                        icon: const Icon(Icons.play_arrow),
                      ),
                      if (widget.phase == TrainingPhase.paused)
                        const Text(
                          'Wznów',
                          style: TextStyle(color: foreground),
                        ),
                    ],
                  ),
                ),
              ),
            if (completed)
              Positioned(
                top: 105,
                left: 12,
                right: 12,
                child: Center(
                  child: Container(
                    key: const Key('training-completed'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xF0181021),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Ukończono wszystkie nuty! Wybierz Reset, aby zagrać ponownie.',
                      style: TextStyle(color: foreground, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            if (widget.phase == TrainingPhase.error || widget.error != null)
              Positioned(
                top: 158,
                left: 16,
                right: 16,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.error ?? 'Nie można rozpocząć treningu.',
                    key: const Key('training-microphone-error'),
                    style: const TextStyle(
                      color: Color(0xFFFFB4AB),
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            Positioned(
              bottom: keyboardHeight + 6,
              left: 12,
              right: 12,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.attemptLabel,
                  key: const Key('training-feedback'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.lastAttempt == TrainingAttempt.incorrect
                        ? const Color(0xFFFFB4AB)
                        : foreground,
                    fontSize: 12,
                    shadows: const [Shadow(blurRadius: 5, color: Colors.black)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 2,
              child: Text(
                widget.songTitle,
                key: const Key('training-song-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF59505F), fontSize: 10),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Disabled until the corresponding audio/MIDI feature actually exists.
class _UnavailableControl extends StatelessWidget {
  const _UnavailableControl({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFF27212B),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF493D50)),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Color(0xFF8C8594), fontSize: 12),
    ),
  );
}

class _TrainingStagePainter extends CustomPainter {
  const _TrainingStagePainter({
    required this.keyboard,
    required this.roll,
    required this.expectedNote,
    required this.detectedNote,
    required this.rollHeight,
  });

  final PianoKeyboardLayout keyboard;
  final FallingNotesLayout? roll;
  final int? expectedNote;
  final int? detectedNote;
  final double rollHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1F0A34), Color(0xFF100E16), Color(0xFF070707)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    for (final key in keyboard.keys.where((key) => !key.isBlack)) {
      if (key.midiNote % 12 == 0) {
        canvas.drawLine(
          Offset(key.rect.left, 0),
          Offset(key.rect.left, rollHeight),
          Paint()
            ..color = const Color(0x308A698D)
            ..strokeWidth = 1.5,
        );
      }
    }
    for (var y = 54.0; y < rollHeight; y += 44) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0x15FFFFFF)
          ..strokeWidth = 1,
      );
    }

    if (roll != null) {
      for (final block in roll!.visibleBlocks) {
        final isCurrent = block.index == roll!.currentIndex;
        final shape = RRect.fromRectAndRadius(
          block.rect,
          const Radius.circular(4),
        );
        canvas.drawRRect(
          shape,
          Paint()
            ..color = isCurrent
                ? const Color(0xFFD547E9)
                : const Color(0xFF6B4EBD),
        );
      }
      canvas.drawLine(
        Offset(0, roll!.nowLineY),
        Offset(size.width, roll!.nowLineY),
        Paint()
          ..color = const Color(0x8CD547E9)
          ..strokeWidth = 2,
      );
    }

    canvas.save();
    canvas.translate(0, rollHeight);
    for (final key in keyboard.keys.where((key) => !key.isBlack)) {
      _drawKey(canvas, key);
    }
    for (final key in keyboard.keys.where((key) => key.isBlack)) {
      _drawKey(canvas, key);
    }
    canvas.restore();
  }

  void _drawKey(Canvas canvas, PianoKeyGeometry key) {
    final rect = key.rect;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    final isExpected = key.midiNote == expectedNote;
    final isDetected = key.midiNote == detectedNote;
    canvas.drawRRect(
      shape,
      Paint()..color = key.isBlack ? const Color(0xFF050505) : Colors.white,
    );
    if (isExpected || isDetected) {
      canvas.drawRRect(
        shape,
        Paint()
          ..color = isExpected
              ? const Color(0x55D547E9)
              : const Color(0x6600BE9C),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..color = isExpected
              ? const Color(0xFFD547E9)
              : const Color(0xFF00BE9C)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = key.isBlack
            ? const Color(0xFF3B3B3B)
            : const Color(0xFFB7B7B7)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    final label = TextPainter(
      text: TextSpan(
        text: PitchEstimate.nameForMidi(key.midiNote),
        style: TextStyle(
          fontSize: key.isBlack
              ? math.min(18, keyboard.whiteKeyWidth * 0.3)
              : math.min(25, keyboard.whiteKeyWidth * 0.37),
          fontWeight: FontWeight.bold,
          color: isExpected
              ? const Color(0xFFB825D3)
              : key.isBlack
              ? Colors.white
              : const Color(0xFF111111),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: rect.width - 2);
    label.paint(
      canvas,
      Offset(
        rect.center.dx - label.width / 2,
        key.isBlack
            ? rect.bottom - label.height - 8
            : rect.bottom - label.height - 9,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _TrainingStagePainter oldDelegate) =>
      oldDelegate.keyboard.range != keyboard.range ||
      oldDelegate.keyboard.whiteKeyWidth != keyboard.whiteKeyWidth ||
      oldDelegate.keyboard.height != keyboard.height ||
      oldDelegate.expectedNote != expectedNote ||
      oldDelegate.detectedNote != detectedNote ||
      oldDelegate.roll?.currentIndex != roll?.currentIndex ||
      oldDelegate.roll?.notes != roll?.notes ||
      oldDelegate.rollHeight != rollHeight;
}

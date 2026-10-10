import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/spectrum_analyzer.dart';
import '../pitch/pitch_detector.dart';

/// Optional diagnostics for the microphone tester, not a second detector.
class SpectrumChart extends StatelessWidget {
  const SpectrumChart({super.key, required this.spectrum, this.pitch});

  final SpectrumSnapshot? spectrum;
  final PitchEstimate? pitch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Widmo częstotliwości 60 do 1200 Hz. '
          'Piki mogą oznaczać harmoniczne, nie osobne naciśnięcia.',
      child: Container(
        key: const Key('spectrum-chart'),
        height: 210,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SpectrumPainter(
                  snapshot: spectrum,
                  pitch: pitch,
                  grid: colors.outlineVariant,
                  bars: colors.primary,
                  peaks: colors.secondary,
                  candidate: colors.tertiary,
                  textColor: colors.onSurfaceVariant,
                ),
              ),
            ),
            if (spectrum == null)
              const Center(
                child: Text(
                  'Włącz mikrofon i zagraj dźwięk',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({
    required this.snapshot,
    required this.pitch,
    required this.grid,
    required this.bars,
    required this.peaks,
    required this.candidate,
    required this.textColor,
  });

  final SpectrumSnapshot? snapshot;
  final PitchEstimate? pitch;
  final Color grid;
  final Color bars;
  final Color peaks;
  final Color candidate;
  final Color textColor;

  double _x(double hz, Rect rect) {
    return rect.left +
        math.log(hz / SpectrumAnalyzer.minFrequencyHz) /
            math.log(
              SpectrumAnalyzer.maxFrequencyHz /
                  SpectrumAnalyzer.minFrequencyHz,
            ) *
            rect.width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(36, 32, size.width - 12, size.height - 29);
    if (rect.width <= 20 || rect.height <= 20) return;
    final axis = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (final octave in [36, 48, 60, 72, 84]) {
      final hz = 440 * math.pow(2, (octave - 69) / 12);
      final x = _x(hz.toDouble(), rect);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), axis);
      _write(
        canvas,
        PitchEstimate.nameForMidi(octave),
        Offset(x - 10, rect.bottom + 7),
        textColor,
      );
    }

    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.bottom),
      axis,
    );
    _write(canvas, '0 dB', const Offset(4, 27), textColor);
    _write(
      canvas,
      '-55',
      Offset(8, rect.bottom - 9),
      textColor,
    );

    final data = snapshot;
    if (data == null) return;
    final binPaint = Paint()
      ..color = bars.withValues(alpha: 0.72)
      ..strokeWidth = 1.5;
    for (final point in data.points) {
      if (point.level <= 0) continue;
      final x = _x(point.frequencyHz, rect);
      final y = rect.bottom - point.level * rect.height;
      canvas.drawLine(Offset(x, rect.bottom), Offset(x, y), binPaint);
    }

    final peakPaint = Paint()
      ..color = peaks
      ..strokeWidth = 2.5;
    // Only a few readable labels are shown; all peaks remain visible.
    var lastLabelRight = rect.left - 6;
    for (final peak in data.peaks) {
      final x = _x(peak.frequencyHz, rect);
      final y = rect.bottom - peak.level * rect.height;
      canvas.drawLine(Offset(x, rect.bottom), Offset(x, y), peakPaint);
      canvas.drawCircle(Offset(x, y), 3, peakPaint);

      if (peak.level < 0.52) continue;
      final midi = (69 +
              12 * math.log(peak.frequencyHz / 440) / math.ln2)
          .round()
          .clamp(0, 127);
      final painter = TextPainter(
        text: TextSpan(
          text: PitchEstimate.nameForMidi(midi),
          style: TextStyle(
            color: peaks,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (x - painter.width / 2)
          .clamp(rect.left, rect.right - painter.width)
          .toDouble();
      if (left < lastLabelRight + 5) continue;
      painter.paint(canvas, Offset(left, 5));
      lastLabelRight = left + painter.width;
    }

    // YIN identifies the candidate fundamental; FFT peaks can be overtones.
    if (pitch case final detected?) {
      final hz = detected.frequencyHz;
      if (hz >= SpectrumAnalyzer.minFrequencyHz &&
          hz <= SpectrumAnalyzer.maxFrequencyHz) {
        final x = _x(hz, rect);
        final marker = Paint()
          ..color = candidate
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(x, rect.top),
          Offset(x, rect.bottom),
          marker,
        );
        canvas.drawCircle(Offset(x, rect.top), 4, marker);
      }
    }
  }

  void _write(Canvas canvas, String label, Offset position, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      !identical(snapshot, old.snapshot) ||
      pitch != old.pitch ||
      grid != old.grid ||
      bars != old.bars ||
      peaks != old.peaks ||
      candidate != old.candidate ||
      textColor != old.textColor;
}

import 'note_event_tracker.dart';
import 'pitch_detector.dart';

/// Local, user-controlled thresholds for acoustic note recognition.
///
/// This does not amplify microphone PCM or transpose MIDI pitches. It only
/// changes the silence gate and the accepted deviation from the nearest note.
class DetectionPreferences {
  const DetectionPreferences({
    this.increasedSensitivity = false,
    this.widerTuningTolerance = false,
  });

  final bool increasedSensitivity;
  final bool widerTuningTolerance;

  /// Minimum input RMS; a lower threshold accepts quieter piano notes.
  double get minimumRms => increasedSensitivity ? 0.005 : 0.015;

  /// Keep a margin from the +/-50-cent boundary between adjacent MIDI notes.
  double get maximumCentsDeviation => widerTuningTolerance ? 45 : 35;

  PitchDetector createDetector() => PitchDetector(minRms: minimumRms);

  NoteEventTracker createTracker() =>
      NoteEventTracker(maxCentsDeviation: maximumCentsDeviation);

  String encode() =>
      'v1:${increasedSensitivity ? '1' : '0'}:${widerTuningTolerance ? '1' : '0'}';

  static DetectionPreferences? decode(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 3 || parts.first != 'v1') return null;
    if ((parts[1] != '0' && parts[1] != '1') ||
        (parts[2] != '0' && parts[2] != '1')) {
      return null;
    }
    return DetectionPreferences(
      increasedSensitivity: parts[1] == '1',
      widerTuningTolerance: parts[2] == '1',
    );
  }
}

/// Physical keyboard limits in MIDI numbers (MIDI 60 is middle C4).
///
/// This is the single range model consumed by import validation and future
/// keyboard/training views. Both endpoints are inclusive; no transposition.
class InstrumentRange {
  const InstrumentRange(this.low, this.high)
    : assert(low >= 0 && low <= 127),
      assert(high >= 0 && high <= 127),
      assert(low <= high);

  final int low;
  final int high;

  static const defaultRange = InstrumentRange(36, 96); // 61 keys, C2–C7

  int get keyCount => high - low + 1;

  bool contains(int midiNote) => midiNote >= low && midiNote <= high;

  static InstrumentRange? tryCreate(int low, int high) {
    if (low < 0 || high > 127 || high < low) return null;
    return InstrumentRange(low, high);
  }

  /// Versioned local-only representation; invalid stored data is discarded.
  String encode() => 'v1:$low:$high';

  static InstrumentRange? decode(String value) {
    final match = RegExp(r'^v1:(\d{1,3}):(\d{1,3})$').firstMatch(value);
    if (match == null) return null;
    return tryCreate(int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// Every occurrence is counted, so repeated unreachable notes are visible.
  RangeCheck checkNotes(Iterable<int> midiNotes) {
    var total = 0;
    final outside = <int>{};
    for (final note in midiNotes) {
      if (!contains(note)) {
        total++;
        outside.add(note);
      }
    }
    return RangeCheck(
      outsideCount: total,
      distinctOutsideNotes: List.unmodifiable(outside.toList()..sort()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InstrumentRange && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);
}

class RangeCheck {
  const RangeCheck({
    required this.outsideCount,
    required this.distinctOutsideNotes,
  });

  final int outsideCount;
  final List<int> distinctOutsideNotes;

  bool get canPractice => outsideCount == 0;
}

enum KeyboardPreset {
  keys37(37, 48),
  keys49(49, 48),
  keys61(61, 36),
  keys88(88, 21);

  const KeyboardPreset(this.keys, this.defaultLow);

  final int keys;
  final int defaultLow;

  InstrumentRange get range =>
      InstrumentRange(defaultLow, defaultLow + keys - 1);
}

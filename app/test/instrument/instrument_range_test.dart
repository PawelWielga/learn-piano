import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';

void main() {
  test('default and common keyboard presets are inclusive', () {
    expect(InstrumentRange.defaultRange, const InstrumentRange(36, 96));
    expect(InstrumentRange.defaultRange.keyCount, 61);
    expect(KeyboardPreset.keys37.range, const InstrumentRange(48, 84));
    expect(KeyboardPreset.keys49.range, const InstrumentRange(48, 96));
    expect(KeyboardPreset.keys61.range, const InstrumentRange(36, 96));
    expect(KeyboardPreset.keys88.range, const InstrumentRange(21, 108));
    for (final preset in KeyboardPreset.values) {
      expect(preset.range.keyCount, preset.keys);
    }
  });

  test('inclusive end points and repeated outside notes are accounted for', () {
    final range = const InstrumentRange(60, 72);
    expect(range.contains(60), isTrue);
    expect(range.contains(72), isTrue);
    expect(range.contains(59), isFalse);
    expect(range.contains(73), isFalse);

    final result = range.checkNotes([59, 60, 72, 73, 59, 95, 73]);
    expect(result.outsideCount, 5);
    expect(result.distinctOutsideNotes, [59, 73, 95]);
    expect(result.canPractice, isFalse);
    expect(range.checkNotes([60, 72, 65]).canPractice, isTrue);
    expect(range.checkNotes([]).canPractice, isTrue);
  });

  test('range validates MIDI limits and octave-independent key count', () {
    expect(InstrumentRange.tryCreate(0, 127)?.keyCount, 128);
    expect(InstrumentRange.tryCreate(0, 0)?.keyCount, 1);
    expect(InstrumentRange.tryCreate(127, 127), const InstrumentRange(127, 127));
    expect(InstrumentRange.tryCreate(-1, 127), isNull);
    expect(InstrumentRange.tryCreate(0, 128), isNull);
    expect(InstrumentRange.tryCreate(90, 80), isNull);
    expect(InstrumentRange.tryCreate(130, 140), isNull);
  });

  test('stored preference is versioned, validated and local-only', () {
    const range = InstrumentRange(34, 82);
    expect(range.encode(), 'v1:34:82');
    expect(InstrumentRange.decode('v1:34:82'), range);
    for (final malformed in [
      '',
      'v2:34:82',
      'v1:-1:30',
      'v1:90:20',
      'v1:10:128',
      'v1:abc:20',
      'v1:20:30:40',
      'garbage',
    ]) {
      expect(InstrumentRange.decode(malformed), isNull);
    }
  });
}

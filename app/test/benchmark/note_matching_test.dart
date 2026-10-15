import 'package:flutter_test/flutter_test.dart';

import '../../tool/note_matching.dart';

BenchmarkNote n(int pitch, int onsetMs, int offsetMs) => BenchmarkNote(
  pitch: pitch,
  onsetUs: onsetMs * 1000,
  offsetUs: offsetMs * 1000,
);

void main() {
  test('greedy failure: augmenting path recovers maximum-cardinality matching', () {
    final result = compareNotes(
      [n(60, 50, 100), n(60, 115, 165)],
      [n(60, 65, 115), n(60, 0, 60)],
      onsetToleranceUs: 50000,
    );
    expect(result.onset.truePositives, 2);
    expect(result.onset.pairs.map((p) => p.detectedIndex), [1, 0]);
    expect(result.onset.falsePositives, 0);
    expect(result.onset.falseNegatives, 0);
  });

  test('repeated notes are not double matched', () {
    final result = compareNotes(
      [n(60, 0, 150), n(60, 200, 350), n(60, 400, 550)],
      [n(60, 0, 150), n(60, 400, 550)],
    );
    expect(result.onset.truePositives, 2);
    expect(result.onset.falseNegatives, 1);
    expect(result.onset.recall, closeTo(2 / 3, 0.000001));
  });

  test('chords with identical onset match pitch, not note order', () {
    final result = compareNotes(
      [n(60, 100, 500), n(64, 100, 500), n(67, 100, 500)],
      [n(67, 102, 498), n(60, 100, 500), n(64, 103, 501)],
    );
    expect(result.strict.truePositives, 3);
    expect(result.strict.f1, 1);
    expect(result.octaveConfusions, isEmpty);
  });

  test('strict offset errors are counted, with onset error statistics', () {
    final result = compareNotes(
      [n(60, 100, 400)],
      [n(60, 120, 700)],
    );
    expect(result.onset.truePositives, 1);
    expect(result.strict.truePositives, 0);
    expect(result.strict.falsePositives, 1);
    expect(result.strict.falseNegatives, 1);
    final stats = result.onset.toJson()['onsetErrorMs'] as Map<String, Object>;
    expect(stats['p95Abs'], 20);
  });

  test('octave confusion is separate and never credited as correct', () {
    final result = compareNotes([n(48, 100, 400)], [n(60, 110, 410)]);
    expect(result.onset.truePositives, 0);
    expect(result.onset.falsePositives, 1);
    expect(result.onset.falseNegatives, 1);
    expect(result.octaveConfusions, hasLength(1));
  });

  test('identical onset, repeated pitch, silence and no matches are deterministic', () {
    final input = [n(60, 0, 300), n(60, 0, 300)];
    final reference = [n(60, 0, 300), n(60, 0, 300)];
    final result = compareNotes(reference, input);
    expect(result.onset.pairs.map((p) => p.detectedIndex), [0, 1]);
    expect(compareNotes([n(60, 0, 100)], []).onset.f1, 0);
    expect(compareNotes([], [n(60, 0, 100)]).onset.f1, 0);
  });

  test('rejects invalid inputs and negative tolerances', () {
    expect(() => compareNotes([n(128, 0, 200)], []), throwsArgumentError);
    expect(() => compareNotes([n(60, 200, 100)], []), throwsArgumentError);
    expect(
      () => compareNotes([], [], onsetToleranceUs: -1),
      throwsArgumentError,
    );
  });

  test('matching cardinality unaffected by permutation of notes', () {
    final expected = [n(60, 0, 100), n(60, 60, 160), n(60, 120, 220)];
    final actual = [n(60, 5, 105), n(60, 65, 165), n(60, 125, 225)];
    expect(compareNotes(expected, actual).strict.truePositives, 3);
    expect(compareNotes(expected.reversed.toList(), actual.reversed.toList()).strict.truePositives, 3);
  });
}

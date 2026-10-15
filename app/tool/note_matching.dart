/// Deterministic, maximum-cardinality, one-to-one note-event matching.
///
/// This is benchmark tooling, not the realtime / transcription engine.
class BenchmarkNote {
  const BenchmarkNote({
    required this.pitch,
    required this.onsetUs,
    required this.offsetUs,
  });

  final int pitch;
  final int onsetUs;
  final int offsetUs;

  Map<String, Object> toJson() => {
    'pitch': pitch,
    'onsetMs': onsetUs / 1000,
    'offsetMs': offsetUs / 1000,
  };
}

class NotePair {
  const NotePair(this.referenceIndex, this.detectedIndex, this.onsetErrorUs, this.offsetErrorUs);

  final int referenceIndex;
  final int detectedIndex;
  // Signed: detected event time minus reference event time.
  final int onsetErrorUs;
  final int offsetErrorUs;
}

class MatchScore {
  const MatchScore({
    required this.referenceCount,
    required this.detectedCount,
    required this.pairs,
  });

  final int referenceCount;
  final int detectedCount;
  final List<NotePair> pairs;

  int get truePositives => pairs.length;
  int get falseNegatives => referenceCount - truePositives;
  int get falsePositives => detectedCount - truePositives;
  double get precision => detectedCount == 0
      ? (referenceCount == 0 ? 1.0 : 0.0)
      : truePositives / detectedCount;
  double get recall => referenceCount == 0 ? 1.0 : truePositives / referenceCount;
  double get f1 => (precision + recall) == 0
      ? 0.0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object> toJson() => {
    'reference': referenceCount,
    'detected': detectedCount,
    'matched': truePositives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'onsetErrorMs': _statistics(pairs.map((p) => p.onsetErrorUs)),
    'offsetErrorMs': _statistics(pairs.map((p) => p.offsetErrorUs)),
  };
}

Map<String, Object> _statistics(Iterable<int> microseconds) {
  final values = microseconds.map((value) => value.abs() / 1000).toList()..sort();
  if (values.isEmpty) {
    return {'count': 0, 'meanAbs': 0.0, 'p50Abs': 0.0, 'p95Abs': 0.0, 'maxAbs': 0.0};
  }
  double percentile(double p) {
    final index = ((values.length * p).ceil() - 1).clamp(0, values.length - 1).toInt();
    return values[index];
  }
  return {
    'count': values.length,
    'meanAbs': values.reduce((a, b) => a + b) / values.length,
    'p50Abs': percentile(0.5),
    'p95Abs': percentile(0.95),
    'maxAbs': values.last,
  };
}

class BenchmarkComparison {
  const BenchmarkComparison({
    required this.onset,
    required this.strict,
    required this.falsePositiveNotes,
    required this.falseNegativeNotes,
    required this.octaveConfusions,
  });

  final MatchScore onset;
  final MatchScore strict;
  // Unmatched after onset-only pitch-accurate matching.
  final List<BenchmarkNote> falsePositiveNotes;
  final List<BenchmarkNote> falseNegativeNotes;
  // Diagnostics only, never counted as true positives.
  final List<Map<String, Object>> octaveConfusions;

  Map<String, Object> toJson() => {
    'onset': onset.toJson(),
    'strict': strict.toJson(),
    'falsePositiveNotes': falsePositiveNotes.map((n) => n.toJson()).toList(),
    'falseNegativeNotes': falseNegativeNotes.map((n) => n.toJson()).toList(),
    'octaveConfusions': octaveConfusions,
  };
}

/// Applies a maximum-cardinality bipartite matching independently for each
/// scoring policy. Every note can occur in at most one matched pair.
///
/// Compatible edges have identical MIDI pitch and onset error <= 130ms.
/// Strict edges additionally require offset error <= 160ms. The matcher sorts
/// compatible edges by absolute timing difference and uses deterministic
/// augmenting paths to maximize TP; it does not promise minimum global error.
/// It is order independent in count for any permutation of input notes.
BenchmarkComparison compareNotes(
  List<BenchmarkNote> reference,
  List<BenchmarkNote> detected, {
  int onsetToleranceUs = 130000,
  int offsetToleranceUs = 160000,
}) {
  if (onsetToleranceUs < 0 || offsetToleranceUs < 0) {
    throw ArgumentError('Timing tolerances must be nonnegative.');
  }
  for (final note in [...reference, ...detected]) {
    if (note.pitch < 0 || note.pitch > 127 || note.onsetUs < 0 || note.offsetUs < note.onsetUs) {
      throw ArgumentError('Invalid benchmark note: pitch or timing.');
    }
  }
  final onsetPairs = _maximumMatch(reference, detected, onsetToleranceUs, null);
  final strictPairs = _maximumMatch(reference, detected, onsetToleranceUs, offsetToleranceUs);
  final matchedReference = onsetPairs.map((p) => p.referenceIndex).toSet();
  final matchedDetected = onsetPairs.map((p) => p.detectedIndex).toSet();
  final missing = <BenchmarkNote>[];
  final extra = <BenchmarkNote>[];
  for (var i = 0; i < reference.length; i++) {
    if (!matchedReference.contains(i)) missing.add(reference[i]);
  }
  for (var i = 0; i < detected.length; i++) {
    if (!matchedDetected.contains(i)) extra.add(detected[i]);
  }

  // Classify a likely octave confusion only among still unmatched notes.
  // Each such pair is diagnostic and stays in both FN and FP totals.
  final octaveCandidates = <({int ref, int det, int onsetError})>[];
  for (var i = 0; i < missing.length; i++) {
    for (var j = 0; j < extra.length; j++) {
      final distance = (missing[i].pitch - extra[j].pitch).abs();
      final error = (missing[i].onsetUs - extra[j].onsetUs).abs();
      if (distance >= 12 && distance % 12 == 0 && error <= onsetToleranceUs) {
        octaveCandidates.add((ref: i, det: j, onsetError: error));
      }
    }
  }
  octaveCandidates.sort((a, b) {
    final byTime = a.onsetError.compareTo(b.onsetError);
    if (byTime != 0) return byTime;
    final byRef = a.ref.compareTo(b.ref);
    return byRef != 0 ? byRef : a.det.compareTo(b.det);
  });
  final usedRef = <int>{};
  final usedDet = <int>{};
  final octaves = <Map<String, Object>>[];
  for (final item in octaveCandidates) {
    if (!usedRef.add(item.ref)) continue;
    if (!usedDet.add(item.det)) {
      usedRef.remove(item.ref);
      continue;
    }
    octaves.add({
      'expectedPitch': missing[item.ref].pitch,
      'detectedPitch': extra[item.det].pitch,
      'onsetDifferenceMs': item.onsetError / 1000,
    });
  }
  return BenchmarkComparison(
    onset: MatchScore(referenceCount: reference.length, detectedCount: detected.length, pairs: onsetPairs),
    strict: MatchScore(referenceCount: reference.length, detectedCount: detected.length, pairs: strictPairs),
    falsePositiveNotes: List.unmodifiable(extra),
    falseNegativeNotes: List.unmodifiable(missing),
    octaveConfusions: List.unmodifiable(octaves),
  );
}

List<NotePair> _maximumMatch(
  List<BenchmarkNote> reference,
  List<BenchmarkNote> detected,
  int onsetToleranceUs,
  int? offsetToleranceUs,
) {
  final byPitch = <int, List<int>>{};
  for (var j = 0; j < detected.length; j++) {
    (byPitch[detected[j].pitch] ??= []).add(j);
  }
  for (final candidates in byPitch.values) {
    candidates.sort((a, b) {
      final cmp = detected[a].onsetUs.compareTo(detected[b].onsetUs);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  }
  final adjacency = List<List<int>>.generate(reference.length, (i) {
    final target = reference[i];
    final options = <int>[];
    final minimum = target.onsetUs - onsetToleranceUs;
    final maximum = target.onsetUs + onsetToleranceUs;
    for (final j in byPitch[target.pitch] ?? const <int>[]) {
      final candidate = detected[j];
      if (candidate.onsetUs < minimum) continue;
      if (candidate.onsetUs > maximum) break;
      if (offsetToleranceUs != null &&
          (candidate.offsetUs - target.offsetUs).abs() > offsetToleranceUs) {
        continue;
      }
      options.add(j);
    }
    options.sort((a, b) {
      int cost(int j) {
        final c = detected[j];
        return (c.onsetUs - target.onsetUs).abs() +
            (offsetToleranceUs == null ? 0 : (c.offsetUs - target.offsetUs).abs());
      }
      final byCost = cost(a).compareTo(cost(b));
      return byCost != 0 ? byCost : a.compareTo(b);
    });
    return options;
  });

  final assigned = List<int>.filled(detected.length, -1);
  bool augment(int referenceIndex, Set<int> seenDetected) {
    for (final j in adjacency[referenceIndex]) {
      if (!seenDetected.add(j)) continue;
      final other = assigned[j];
      if (other < 0 || augment(other, seenDetected)) {
        assigned[j] = referenceIndex;
        return true;
      }
    }
    return false;
  }

  for (var i = 0; i < reference.length; i++) {
    augment(i, <int>{});
  }

  final result = <NotePair>[];
  for (var j = 0; j < assigned.length; j++) {
    final i = assigned[j];
    if (i < 0) continue;
    result.add(NotePair(
      i,
      j,
      detected[j].onsetUs - reference[i].onsetUs,
      detected[j].offsetUs - reference[i].offsetUs,
    ));
  }
  result.sort((a, b) {
    final byRef = a.referenceIndex.compareTo(b.referenceIndex);
    return byRef != 0 ? byRef : a.detectedIndex.compareTo(b.detectedIndex);
  });
  return result;
}

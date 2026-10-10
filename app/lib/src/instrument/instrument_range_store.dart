import 'instrument_range.dart';

/// Only this small preference may be stored, never imported MIDI or audio.
abstract class InstrumentRangeStore {
  Future<InstrumentRange?> load();
  Future<void> save(InstrumentRange range);
}

import 'instrument_range.dart';
import 'instrument_range_store.dart';

InstrumentRangeStore createStore() => SessionInstrumentRangeStore();

/// Graceful fallback for platforms without browser localStorage.
class SessionInstrumentRangeStore implements InstrumentRangeStore {
  InstrumentRange? _saved;

  @override
  Future<InstrumentRange?> load() async => _saved;

  @override
  Future<void> save(InstrumentRange range) async {
    _saved = range;
  }
}

import 'dart:js_interop';

import 'instrument_range.dart';
import 'instrument_range_store.dart';

@JS('learnPianoRange.read')
external JSString? _readStoredRange();

@JS('learnPianoRange.write')
external void _writeStoredRange(JSString value);

InstrumentRangeStore createStore() => BrowserInstrumentRangeStore();

class BrowserInstrumentRangeStore implements InstrumentRangeStore {
  @override
  Future<InstrumentRange?> load() async {
    final value = _readStoredRange()?.toDart;
    return value == null ? null : InstrumentRange.decode(value);
  }

  @override
  Future<void> save(InstrumentRange range) async {
    _writeStoredRange(range.encode().toJS);
  }
}

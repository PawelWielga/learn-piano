import 'instrument_range_store.dart';
import 'instrument_range_store_stub.dart'
    if (dart.library.js_interop) 'instrument_range_store_web.dart'
    as platform;

InstrumentRangeStore createInstrumentRangeStore() => platform.createStore();

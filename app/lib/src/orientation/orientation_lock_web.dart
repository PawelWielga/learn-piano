import 'dart:js_interop';

@JS('learnPianoOrientation.lockLandscape')
external JSPromise<JSBoolean> _lockLandscape();

Future<bool> requestLandscapeOrientation() async {
  try {
    return (await _lockLandscape().toDart).toDart;
  } catch (_) {
    return false;
  }
}

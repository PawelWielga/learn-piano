import 'orientation_lock_stub.dart'
    if (dart.library.js_interop) 'orientation_lock_web.dart'
    as platform;

/// Attempts to lock landscape on browsers that allow it.
/// Returns false when unsupported or refused by the browser.
Future<bool> requestLandscapeOrientation() =>
    platform.requestLandscapeOrientation();

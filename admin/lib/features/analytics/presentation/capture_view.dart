export 'capture_view_stub.dart'
    if (dart.library.io) 'capture_view_native.dart'
    if (dart.library.js_interop) 'capture_view_web.dart';

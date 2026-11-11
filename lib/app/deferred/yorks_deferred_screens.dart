/// Screens that most sessions never open.
///
/// On the web they are deferred libraries, so their code stays out of the
/// startup bundle and downloads the first time someone opens them. On other
/// platforms (the mobile apps and tests) everything is compiled ahead of
/// time, so they are built directly.
library;

export 'yorks_deferred_screens_direct.dart'
    if (dart.library.js_interop) 'yorks_deferred_screens_web.dart';

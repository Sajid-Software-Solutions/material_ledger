/// Recovers a browser tab that is still running an earlier release.
///
/// Screens that most people rarely open are downloaded on first use. After a
/// new release, a tab opened before it asks for page files that now belong to
/// the new build, and the download fails. Reloading picks up the current
/// release. A per-tab guard allows one automatic reload in a short window, so
/// a real outage never becomes a reload loop.
library;

import 'stale_build_recovery_stub.dart'
    if (dart.library.js_interop) 'stale_build_recovery_web.dart'
    as platform;

/// Reloads the page once to pick up the current release. Returns false when
/// nothing was done (not on the web, or a reload already happened recently),
/// so the caller shows its normal retry.
bool recoverFromStaleBuild() => platform.recoverFromStaleBuild();

/// [load] with stale-release recovery: if the download fails, the tab
/// reloads once to pick up the current release.
Future<void> loadOrRecover(Future<void> load) =>
    load.catchError((Object error) {
      recoverFromStaleBuild();
      throw error;
    });

import 'package:web/web.dart' as web;

const _key = 'yorks.stale_build_reload_at';

/// One automatic reload per tab every five minutes at most.
bool recoverFromStaleBuild() {
  try {
    final storage = web.window.sessionStorage;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(storage.getItem(_key) ?? '') ?? 0;
    if (now - last < const Duration(minutes: 5).inMilliseconds) return false;
    storage.setItem(_key, '$now');
    web.window.location.reload();
    return true;
  } catch (_) {
    return false;
  }
}

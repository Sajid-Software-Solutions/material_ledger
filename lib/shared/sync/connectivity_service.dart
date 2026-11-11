import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device network-interface availability, abstracted so sync and UI do not depend on a
/// concrete plugin (and so tests can drive online/offline deterministically).
///
/// The production implementation wraps `connectivity_plus` (+ an optional
/// reachability ping for "connected but no internet" on patchy 4G):
///
/// ```dart
/// class PlusConnectivity implements ConnectivityService {
///   final _c = Connectivity();
///   @override
///   Stream<bool> get onChange => _c.onConnectivityChanged
///       .map((r) => !r.contains(ConnectivityResult.none));
///   @override
///   Future<bool> get isOnline async =>
///       !(await _c.checkConnectivity()).contains(ConnectivityResult.none);
/// }
/// ```
///
/// It needs the `connectivity_plus` dependency + a native rebuild, so the
/// prototype ships [DefaultConnectivity] (online, manually toggleable) which
/// keeps the build green and lets you demo the offline → queued → synced flow.
abstract interface class ConnectivityService {
  bool get isOnline;
  Stream<bool> get onChange;
}

/// Local connectivity stand-in. Defaults to online; [setOnline] lets a debug
/// toggle (or tests) simulate going offline so the sync states are visible.
class DefaultConnectivity implements ConnectivityService {
  DefaultConnectivity({bool online = true}) : _online = online;

  bool _online;
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onChange => _controller.stream;

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _controller.add(value);
  }

  void dispose() => _controller.close();
}

/// Device interface signal from `connectivity_plus`, not backend reachability
/// or proof that a particular command committed. [isOnline] is kept in
/// sync synchronously from the plugin's change stream (seeded by an initial
/// check) so the rest of the app stays synchronous.
class PlusConnectivity implements ConnectivityService {
  PlusConnectivity() {
    _conn.checkConnectivity().then(_update);
    _sub = _conn.onConnectivityChanged.listen(_update);
  }

  final _conn = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  static bool _isUp(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);

  void _update(List<ConnectivityResult> r) {
    final up = _isUp(r);
    if (up == _online) return;
    _online = up;
    _controller.add(up);
  }

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onChange => _controller.stream;

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

/// The app's connectivity service. Debug builds keep the manually-toggleable
/// [DefaultConnectivity] (so the offline-simulator dev tool works); release /
/// profile use real reachability via [PlusConnectivity].
final connectivityProvider = Provider<ConnectivityService>((ref) {
  if (kDebugMode) {
    final c = DefaultConnectivity();
    ref.onDispose(c.dispose);
    return c;
  }
  final c = PlusConnectivity();
  ref.onDispose(c.dispose);
  return c;
});

/// Reactive online/offline flag for the UI and engine.
final isOnlineProvider = StateNotifierProvider<_OnlineNotifier, bool>((ref) {
  return _OnlineNotifier(ref.watch(connectivityProvider));
});

class _OnlineNotifier extends StateNotifier<bool> {
  _OnlineNotifier(this._service) : super(_service.isOnline) {
    _sub = _service.onChange.listen((v) => state = v);
  }

  final ConnectivityService _service;
  late final StreamSubscription<bool> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

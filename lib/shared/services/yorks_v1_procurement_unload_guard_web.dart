import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'yorks_v1_procurement_unload_guard.dart';

YorksV1ProcurementUnloadGuard createGuard() => _BrowserGuard();

class _BrowserGuard implements YorksV1ProcurementUnloadGuard {
  _BrowserGuard() {
    _listener = ((web.Event event) {
      if (!_active) return;
      event.preventDefault();
      (event as web.BeforeUnloadEvent).returnValue = '';
    }).toJS;
    web.window.addEventListener('beforeunload', _listener);
  }
  late final JSFunction _listener;
  bool _active = false;
  @override
  void setActive(bool active) => _active = active;
  @override
  void dispose() {
    _active = false;
    web.window.removeEventListener('beforeunload', _listener);
  }
}

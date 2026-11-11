import 'yorks_v1_procurement_unload_guard.dart';

YorksV1ProcurementUnloadGuard createGuard() => _NoopGuard();

class _NoopGuard implements YorksV1ProcurementUnloadGuard {
  @override
  void setActive(bool active) {}
  @override
  void dispose() {}
}

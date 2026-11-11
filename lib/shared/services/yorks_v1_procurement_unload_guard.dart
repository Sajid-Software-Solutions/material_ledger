import 'yorks_v1_procurement_unload_guard_stub.dart'
    if (dart.library.js_interop) 'yorks_v1_procurement_unload_guard_web.dart'
    as platform;

/// Best-effort browser warning only. Browsers may suppress it, and no final
/// command or asynchronous persistence is attempted during page unloading.
abstract interface class YorksV1ProcurementUnloadGuard {
  void setActive(bool active);
  void dispose();
}

YorksV1ProcurementUnloadGuard createYorksV1ProcurementUnloadGuard() =>
    platform.createGuard();

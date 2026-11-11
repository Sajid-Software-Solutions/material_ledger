import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';

/// Installed app version/build, read once from the platform at startup and
/// injected via override in `main.dart` (same pattern as SharedPreferences) so
/// the gate logic stays synchronous.
class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.build});
  final String version; // e.g. "1.0.0"
  final int build; // e.g. 1

  String get label => 'v$version ($build)';
}

final appVersionProvider = Provider<AppVersionInfo>((ref) {
  throw UnimplementedError('Must be overridden in main() from PackageInfo');
});

/// Remote app config that drives the gates. Local default today; the controller
/// is where a Firebase Remote Config / Firestore listener will push updates.
/// Exposes debug setters so the gates can be exercised without a backend.
final appConfigProvider = StateNotifierProvider<AppConfigController, AppConfig>(
  (ref) {
    return AppConfigController();
  },
);

class AppConfigController extends StateNotifier<AppConfig> {
  AppConfigController() : super(const AppConfig());

  // ─── Firebase seam ───────────────────────────────────────────────
  // void bindRemoteConfig(...) => listen and `state = AppConfig.fromJson(...)`.

  // ─── Debug controls (exercise the gates with no backend) ─────────
  void setMaintenance(bool on, {String message = ''}) =>
      state = state.copyWith(maintenanceMode: on, maintenanceMessage: message);
  void setMinSupportedBuild(int build) =>
      state = state.copyWith(minSupportedBuild: build);
  void setLatestBuild(int build) => state = state.copyWith(latestBuild: build);
}

/// The current blocking gate (force-update / maintenance / none).
final appGateProvider = Provider<AppGate>((ref) {
  final config = ref.watch(appConfigProvider);
  final installed = ref.watch(appVersionProvider).build;
  return resolveGate(config, installed);
});

/// Whether a soft "update available" nudge should show.
final updateAvailableProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider);
  final installed = ref.watch(appVersionProvider).build;
  return updateAvailable(config, installed);
});

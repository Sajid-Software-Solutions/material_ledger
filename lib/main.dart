import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/projects/presentation/overview/yorks_v1_role_overview_deferred.dart';
import 'app/app.dart';
import 'core/constants/app_colors.dart';
import 'core/widgets/brand_logo.dart';
import 'shared/models/app_strings.dart';
import 'shared/models/analytics_configuration.dart';
import 'shared/models/backend_configuration.dart';
import 'shared/models/backend_failure_copy.dart';
import 'shared/models/yorks_v1_shell_strings.dart';
import 'shared/models/yorks_v1_feature_flags.dart';
import 'shared/providers/language_provider.dart';
import 'shared/services/app_config_service.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/observability_service.dart';
import 'shared/services/posthog_analytics_sink.dart';
import 'shared/services/push_service.dart'
    show registerFirebaseBackgroundHandler;
import 'shared/services/sentry_observability.dart';
import 'shared/sync/supabase_bootstrap.dart';
import 'shared/sync/supabase_sync_backend.dart';
import 'shared/sync/sync_backend.dart';

/// Sentry DSN, injected at build time:
///   flutter run/build --dart-define=SENTRY_DSN=https://…@…ingest…/…
/// Empty (the default) → crash reporting is OFF and the app uses the no-op
/// reporter, so local/dev builds and anyone without a DSN run unchanged.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0',
);
const _appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '1');

/// Backend connection. Every environment supplies its own explicit values.
/// There is deliberately no shared remote fallback: a release with forgotten
/// configuration must fail closed rather than write to another environment.
///   --dart-define=SUPABASE_URL=https://your-uae-instance
///   --dart-define=SUPABASE_ANON_KEY=…
const _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _envSupabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _allowLocalDevelopment = bool.fromEnvironment('ALLOW_LOCAL_DEVELOPMENT');
const _localDemoPassword = String.fromEnvironment('LOCAL_DEMO_PASSWORD');
const _buildDiagnostic = bool.fromEnvironment('YORKS_BUILD_DIAGNOSTIC');
const _postHogRequested = bool.fromEnvironment('POSTHOG_ENABLED');

void main() {
  final observability = _StartupObservability();
  _bootstrap(observability);
  // Crash transport is useful but never a prerequisite for useful pixels.
  // Start it after the native/Flutter launch surface has painted; the stable
  // proxy below upgrades every existing caller once initialization succeeds.
  if (_sentryDsn.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(observability.initializeSentry()),
    );
  }
}

class _StartupObservability implements ObservabilityService {
  ObservabilityService _delegate = const NoopObservability();

  Future<void> initializeSentry() async {
    try {
      await SentryFlutter.init((options) {
        options.dsn = _sentryDsn;
        options.environment = const String.fromEnvironment(
          'SENTRY_ENV',
          defaultValue: 'production',
        );
        // Privacy first — this app holds salaries, financials and HR data.
        options.sendDefaultPii = false;
        options.beforeBreadcrumb = SentryObservability.scrubBreadcrumb;
        options.beforeSend = SentryObservability.scrubEvent;
        options.attachStacktrace = true;
        options.tracesSampleRate = 0.0;
      });
      _delegate = const SentryObservability();
      _StartupTimeline.mark('observability_ready');
    } catch (error, stack) {
      await _delegate.recordError(
        error,
        stack,
        reason: 'SENTRY_INITIALIZATION_FAILED',
      );
    }
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) => _delegate.recordError(error, stack, fatal: fatal, reason: reason);

  @override
  void logEvent(String name, {Map<String, Object?> params = const {}}) {
    _delegate.logEvent(name, params: params);
  }
}

/// Boots the app with [observability] wired into every error path. Identical
/// whether or not Sentry is active — the seam is the single source of truth, so
/// no call site ever branches on the backend.
void _bootstrap(ObservabilityService observability) {
  runZonedGuarded(
    () {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      registerFirebaseBackgroundHandler();
      _StartupTimeline.mark('binding_ready');

      // Framework + platform errors → crash reporting.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        observability.recordError(
          details.exception,
          details.stack,
          fatal: true,
        );
      };
      binding.platformDispatcher.onError = (error, stack) {
        observability.recordError(error, stack, fatal: true);
        return true;
      };

      // Never show the raw red/grey crash box to a (non-technical) user: when a
      // widget fails to build, swap in a calm, self-contained fallback so one bad
      // screen can't take the whole app down. Debug still surfaces the details.
      ErrorWidget.builder = (details) => _CrashFallback(details: details);

      // Match the native launch surface before the first Flutter frame. The
      // normal application theme takes over as soon as startup completes.
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF041E42),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
      // The temporary startup Navigator may report '/' while disk / Auth
      // initialize. Capture the original OS/browser intent before it mounts.
      final initialLocation = captureAppLaunchLocation();
      runApp(
        _RuntimeBootstrapHost(
          observability: observability,
          initialLocation: initialLocation,
        ),
      );
    },
    // Uncaught async errors.
    (error, stack) => observability.recordError(error, stack, fatal: true),
  );
}

/// Mounts useful pixels before any disk or network initialization. The old
/// startup awaited the complete SharedPreferences cache and Supabase before
/// calling runApp, leaving the platform surface blank and unrecoverable when a
/// plugin failed. This host makes initialization an explicit, retryable state.
class _RuntimeBootstrapHost extends StatefulWidget {
  const _RuntimeBootstrapHost({
    required this.observability,
    required this.initialLocation,
  });

  final ObservabilityService observability;
  final String? initialLocation;

  @override
  State<_RuntimeBootstrapHost> createState() => _RuntimeBootstrapHostState();
}

class _RuntimeBootstrapHostState extends State<_RuntimeBootstrapHost> {
  Future<Widget>? _initialization;
  bool _reportedInitializationError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _StartupTimeline.mark('first_flutter_frame');
      if (mounted) _start();
    });
  }

  void _start() {
    setState(() {
      _reportedInitializationError = false;
      _initialization = _initializeRuntime(
        widget.observability,
        initialLocation: widget.initialLocation,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialization = _initialization;
    if (initialization == null) {
      return _StartupSurface(initialLocation: widget.initialLocation);
    }
    return FutureBuilder<Widget>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (!_reportedInitializationError) {
            _reportedInitializationError = true;
            unawaited(
              widget.observability.recordError(
                snapshot.error!,
                snapshot.stackTrace,
                fatal: true,
              ),
            );
          }
          return _StartupFailure(
            onRetry: _start,
            initialLocation: widget.initialLocation,
          );
        }
        final application = snapshot.data;
        if (application == null) {
          return _StartupSurface(initialLocation: widget.initialLocation);
        }
        return _ApplicationReadyReporter(child: application);
      },
    );
  }
}

Future<Widget> _initializeRuntime(
  ObservabilityService observability, {
  String? initialLocation,
}) async {
  _StartupTimeline.mark('runtime_initialization_started');
  final prefs = await SharedPreferences.getInstance();
  _StartupTimeline.mark('preferences_ready');
  final backend = BackendConfiguration.resolve(
    supabaseUrl: _envSupabaseUrl,
    supabaseAnonKey: _envSupabaseKey,
    isRelease: kReleaseMode,
    allowLocalDevelopment: _allowLocalDevelopment,
    localDemoPassword: _localDemoPassword,
  );
  if (backend.mode == BackendStartupMode.blocked) {
    return _BackendConfigurationFailure(
      reason: backend.failureReason,
      initialLocation: initialLocation,
    );
  }
  const r35Flags = YorksV1FeatureFlags.fromEnvironment();
  if (kReleaseMode && !r35Flags.isCompleteR35) {
    return _BackendConfigurationFailure(
      reason: 'The complete Yorks V1 R35 feature chain is required.',
      initialLocation: initialLocation,
    );
  }
  if (kDebugMode || _buildDiagnostic) {
    final backendHost = backend.usesSupabase
        ? Uri.tryParse(backend.supabaseUrl)?.host ?? 'configured'
        : 'local development';
    debugPrint(
      'Yorks V1 build profile: '
      '${r35Flags.isCompleteR35 ? 'R35 COMPLETE' : 'INCOMPLETE'}\n'
      'Backend: $backendHost\n'
      'Feature chain: '
      '${r35Flags.isCompleteR35 ? '9/9 enabled' : 'not complete'}\n'
      'Legacy operational routes: disabled',
    );
  }

  final versionInfo = AppVersionInfo(
    version: _appVersion,
    build: int.tryParse(_appBuild) ?? 1,
  );
  final analytics = _createAnalyticsService();
  final overrides = <Override>[
    appLaunchLocationProvider.overrideWithValue(initialLocation),
    sharedPreferencesProvider.overrideWithValue(prefs),
    appVersionProvider.overrideWithValue(versionInfo),
    observabilityProvider.overrideWithValue(observability),
    analyticsServiceProvider.overrideWithValue(analytics),
  ];

  if (backend.usesSupabase) {
    await Supabase.initialize(
      url: backend.supabaseUrl,
      publishableKey: backend.supabaseAnonKey,
    );
    _StartupTimeline.mark('supabase_ready');
    final client = Supabase.instance.client;
    // A signed-in user lands on the Overview: fetch its code now, in parallel
    // with session and permission verification, instead of after them.
    if (r35Flags.roleOverviewV2 && client.auth.currentSession != null) {
      prefetchYorksV1RoleOverview();
    }
    overrides.add(supabaseClientProvider.overrideWithValue(client));
    overrides.add(
      syncBackendProvider.overrideWithValue(SupabaseSyncBackend(client)),
    );
    // Retain the legacy bootstrap only for deliberately incomplete local V1
    // builds. Complete R35 repositories are normalized and server-authorized.
    if (client.auth.currentSession != null && !r35Flags.isCompleteR35) {
      await SupabaseBootstrap(client, prefs).run();
    } else if (client.auth.currentSession == null) {
      await prefs.remove(kAuthUserIdPrefKey);
    }
  }

  _StartupTimeline.mark('application_dependencies_ready');
  return ProviderScope(
    overrides: overrides,
    child: _AnalyticsInitializationHost(
      analytics: analytics,
      child: const MaterialLedgerApp(),
    ),
  );
}

AnalyticsService _createAnalyticsService() {
  if (!_postHogRequested) return const NoopAnalyticsService();
  return GuardedAnalyticsService(
    configuration: AnalyticsConfiguration.fromEnvironment(
      appVersion: _appVersion,
      appBuild: _appBuild,
    ),
    sink: const PostHogAnalyticsSink(),
  );
}

/// Starts telemetry only after the operational shell has rendered. Setup and
/// transport failures remain isolated from auth and every business command.
class _AnalyticsInitializationHost extends StatefulWidget {
  const _AnalyticsInitializationHost({
    required this.analytics,
    required this.child,
  });

  final AnalyticsService analytics;
  final Widget child;

  @override
  State<_AnalyticsInitializationHost> createState() =>
      _AnalyticsInitializationHostState();
}

class _AnalyticsInitializationHostState
    extends State<_AnalyticsInitializationHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(widget.analytics.initialize()),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ApplicationReadyReporter extends StatefulWidget {
  const _ApplicationReadyReporter({required this.child});

  final Widget child;

  @override
  State<_ApplicationReadyReporter> createState() =>
      _ApplicationReadyReporterState();
}

class _ApplicationReadyReporterState extends State<_ApplicationReadyReporter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _StartupTimeline.mark('application_shell_frame'),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

abstract final class _StartupTimeline {
  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String name) {
    developer.Timeline.instantSync(
      'yorks.startup.$name',
      arguments: {'elapsed_ms': _clock.elapsedMilliseconds},
    );
  }
}

/// Holds the original route while a temporary startup / retry page renders.
/// A home-only Navigator would reject an OS deep link and report '/' before
/// the authenticated GoRouter has even been created.
class YorksStartupPage extends StatelessWidget {
  const YorksStartupPage({
    super.key,
    this.initialLocation,
    required this.child,
  });

  final String? initialLocation;
  final Widget child;

  Route<void> _route(RouteSettings settings) =>
      MaterialPageRoute<void>(settings: settings, builder: (context) => child);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    initialRoute: initialLocation ?? '/',
    onGenerateRoute: _route,
    onGenerateInitialRoutes: (route) => [_route(RouteSettings(name: route))],
  );
}

class _StartupSurface extends StatelessWidget {
  const _StartupSurface({this.initialLocation});

  final String? initialLocation;

  @override
  Widget build(BuildContext context) => YorksStartupPage(
    initialLocation: initialLocation,
    child: Scaffold(
      backgroundColor: const Color(0xFF041E42),
      body: Semantics(
        liveRegion: true,
        label: YorksV1ShellStrings.preparingWorkspace.primary,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: 88),
              const SizedBox(height: 18),
              Text(
                YorksV1ShellStrings.companyName.primary,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                YorksV1ShellStrings.preparingWorkspace.primary,
                style: const TextStyle(color: Color(0xC2FFFFFF), fontSize: 14),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 42,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0x29FFFFFF),
                  color: Color(0xFF3B97FF),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.onRetry, this.initialLocation});

  final VoidCallback onRetry;
  final String? initialLocation;

  @override
  Widget build(BuildContext context) => YorksStartupPage(
    initialLocation: initialLocation,
    child: Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 46,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  YorksV1ShellStrings.startupFailedTitle.primary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  YorksV1ShellStrings.startupFailedBody.primary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(AppStrings.retry.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Operationally closed startup state. No repositories, routes or local data
/// are exposed when backend configuration fails validation.
class _BackendConfigurationFailure extends StatelessWidget {
  const _BackendConfigurationFailure({
    required this.reason,
    this.initialLocation,
  });

  final String reason;
  final String? initialLocation;

  @override
  Widget build(BuildContext context) {
    return YorksStartupPage(
      initialLocation: initialLocation,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F9FB),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 42,
                    color: Color(0xFF5F6368),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    BackendFailureCopy.title.primary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF191C1E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    BackendFailureCopy.body.primary,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF5F6368)),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9B1C1C),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Calm replacement for Flutter's red/grey error box. Fully self-contained (no
/// theme, Material, or Directionality ancestor required) so it renders wherever
/// a widget failed — the rest of the app keeps working around it.
class _CrashFallback extends StatelessWidget {
  const _CrashFallback({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFF7F9FB),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Color(0xFF9AA0A6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF191C1E),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please go back and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF5F6368)),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Text(
                '${details.exception}',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB00020)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

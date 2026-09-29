import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/app.dart' show appRouterProvider;
import '../../firebase_options.dart';
import '../models/app_notification.dart';
import '../models/yorks_v1_notification.dart';
import '../providers/language_provider.dart'
    show supabaseClientProvider, sharedPreferencesProvider;
import '../providers/yorks_v1_notification_provider.dart';
import 'observability_service.dart';

/// Enroll only the explicitly configured site, never arbitrary preview URLs.
const _webPushOrigin = String.fromEnvironment(
  'YORKS_WEB_PUSH_ORIGIN',
  defaultValue: 'https://yorks-r35.vercel.app',
);

/// Project-specific public Web Push key, required by production builds.
const _webPushVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

const _androidChannel = AndroidNotificationChannel(
  'yorks_push',
  'Yorks notifications',
  description: 'Workflow and Team Chat alerts.',
  importance: Importance.high,
);

/// A push notification delivered from a server (its payload already maps onto
/// the in-app [AppNotification] model — `type`, `refId`, `route`, `audience` —
/// so a tapped push deep-links exactly like an in-app alert).
class PushMessage {
  const PushMessage({
    this.notificationId = '',
    this.eventCode = '',
    this.surface = '',
    required this.type,
    required this.title,
    this.titleSecondary = '',
    this.body = '',
    this.refId = '',
    this.route = '',
    this.audience = '',
  });

  final String notificationId;
  final String eventCode;
  final String surface;
  final NotificationType type;
  final String title;
  final String titleSecondary;
  final String body;
  final String refId;
  final String route;
  final String audience;

  bool get isTeamChat =>
      surface == 'team_chat' ||
      yorksV1IsChatTransportEvent(eventCode: eventCode);

  factory PushMessage.fromData(Map<String, String> data) => PushMessage(
    notificationId: data['notificationId'] ?? '',
    eventCode: data['eventCode'] ?? '',
    surface: data['surface'] ?? '',
    type: NotificationType.fromKey(data['type'] ?? 'info'),
    title: data['title'] ?? '',
    titleSecondary: data['titleSecondary'] ?? '',
    body: data['body'] ?? '',
    refId: data['refId'] ?? '',
    route: data['route'] ?? '',
    audience: data['audience'] ?? '',
  );
}

enum PushAuthorizationState {
  checking,
  notDetermined,
  authorized,
  provisional,
  denied,
  unsupported,
  error,
}

/// User-visible health of this installation's alert transport. It deliberately
/// contains no registration token, backend detail or notification payload.
class PushDeliveryStatus {
  const PushDeliveryStatus({
    required this.authorization,
    this.deviceRegistered = false,
    this.errorCode = '',
  });

  const PushDeliveryStatus.checking()
    : authorization = PushAuthorizationState.checking,
      deviceRegistered = false,
      errorCode = '';

  const PushDeliveryStatus.unsupported()
    : authorization = PushAuthorizationState.unsupported,
      deviceRegistered = false,
      errorCode = '';

  final PushAuthorizationState authorization;
  final bool deviceRegistered;
  final String errorCode;

  bool get isAllowed =>
      authorization == PushAuthorizationState.authorized ||
      authorization == PushAuthorizationState.provisional;

  PushDeliveryStatus copyWith({
    PushAuthorizationState? authorization,
    bool? deviceRegistered,
    String? errorCode,
  }) => PushDeliveryStatus(
    authorization: authorization ?? this.authorization,
    deviceRegistered: deviceRegistered ?? this.deviceRegistered,
    errorCode: errorCode ?? this.errorCode,
  );
}

/// Server push behind one interface. [FcmPushService] is the real
/// implementation (Firebase Cloud Messaging as pure TRANSPORT — Supabase
/// stays the backend/auth/db); [NoopPushService] remains the deterministic
/// test/unsupported-platform implementation.
///
/// IMPORTANT: `notifications` is now a SYNCED table (realtime + hydrate), so
/// the actual [AppNotification] record already reaches every device on its
/// own. A push's job is narrower than the original design here: wake the
/// device and, on tap, deep-link via the payload's `route` — NOT create a
/// second in-app notification record (that would duplicate the synced one).
abstract interface class PushService {
  /// Initializes transport and silently restores an already-granted device.
  /// It never opens a browser or OS permission prompt.
  Future<String?> register();

  /// Requests permission from a direct user action, then registers this device.
  Future<PushDeliveryStatus> enable();

  PushDeliveryStatus get status;

  Stream<PushDeliveryStatus> get onStatus;

  /// Stream of inbound push messages (empty in the no-op).
  Stream<PushMessage> get onMessage;
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<String?> register() async => null;

  @override
  Future<PushDeliveryStatus> enable() async => status;

  @override
  PushDeliveryStatus get status => const PushDeliveryStatus.unsupported();

  @override
  Stream<PushDeliveryStatus> get onStatus => const Stream.empty();

  @override
  Stream<PushMessage> get onMessage => const Stream.empty();
}

/// Required top-level entry point for background FCM messages (invoked in its
/// own isolate). It must remain short and cannot update Riverpod or UI state.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _debugMessage('background', message);
  } catch (error, stackTrace) {
    _debugFailure('background initialization', error, stackTrace);
  }
}

/// Registers the required top-level handler before the app starts building.
/// Keeping it outside a widget prevents release tree-shaking from dropping the
/// callback and means a background delivery can be handled after the first
/// normal launch.
void registerFirebaseBackgroundHandler() {
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
}

void _debugMessage(String phase, RemoteMessage _) {
  // FCM registration tokens, identifiers, notification text, and data payloads
  // are device/user data. Development logs record delivery only; production
  // observability receives only failures through the scrubbed reporter below.
  if (!kDebugMode) return;
  debugPrint('[fcm][$phase] message received');
}

void _debugFailure(String phase, Object error, StackTrace stackTrace) {
  if (kDebugMode) {
    debugPrint('[fcm][$phase] $error\n$stackTrace');
  }
}

/// Real push transport (FCM). Every step is defensive: a missing/misconfigured
/// Firebase project (no `google-services.json` / `GoogleService-Info.plist`
/// yet) must never crash or block the app — [initialize] simply leaves push
/// inactive, exactly like Sentry/Supabase when their own config is absent.
class FcmPushService implements PushService {
  FcmPushService(this._ref);
  final Ref _ref;

  final _localPlugin = FlutterLocalNotificationsPlugin();
  final _controller = StreamController<PushMessage>.broadcast();
  final _statusController = StreamController<PushDeliveryStatus>.broadcast();
  bool _ready = false;
  bool _listenersAttached = false;
  Future<void>? _initializing;
  PushDeliveryStatus _status = const PushDeliveryStatus.checking();

  @override
  Stream<PushMessage> get onMessage => _controller.stream;

  @override
  PushDeliveryStatus get status => _status;

  @override
  Stream<PushDeliveryStatus> get onStatus => _statusController.stream;

  @override
  Future<String?> register() async {
    await initialize();
    if (!_ready || !_status.isAllowed) return null;
    try {
      final token = await _getToken();
      // [initialize] can run before authentication exists. Repeat this
      // owner-bound registration after a later sign-in instead of leaving a
      // token unassociated with that user.
      final registered = await _registerToken(token);
      _setStatus(_status.copyWith(deviceRegistered: registered, errorCode: ''));
      return token;
    } catch (e, st) {
      _reportFailure('TOKEN_REGISTRATION_FAILED', e, st);
      return null;
    }
  }

  @override
  Future<PushDeliveryStatus> enable() async {
    await initialize();
    if (!_ready) return _status;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _setAuthorization(settings.authorizationStatus);
      if (_status.isAllowed) await register();
    } catch (e, st) {
      _reportFailure('PERMISSION_REQUEST_FAILED', e, st);
    }
    return _status;
  }

  /// Full setup: Firebase, permission status, background handler, foreground
  /// event delivery to the in-app alert host, tap → deep-link, and device-token
  /// registration (+ refresh). Call once at app start; later calls no-op.
  Future<void> initialize() {
    if (_ready) return Future<void>.value();
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;
    final attempt = _initialize();
    _initializing = attempt;
    return attempt.whenComplete(() {
      if (identical(_initializing, attempt)) _initializing = null;
    });
  }

  Future<void> _initialize() async {
    // Preview origins must never silently enroll against the production backend.
    if (kIsWeb && Uri.base.origin != _webPushOrigin) {
      _setStatus(const PushDeliveryStatus.unsupported());
      return;
    }
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e, st) {
      // Unsupported desktop targets and missing native configuration must not
      // block Yorks. Android, iOS and web use the generated options above.
      _debugFailure('initialization', e, st);
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux)) {
        _setStatus(const PushDeliveryStatus.unsupported());
      } else {
        _reportFailure('FIREBASE_INITIALIZATION_FAILED', e, st);
      }
      return;
    }
    _ready = true;

    try {
      if (!kIsWeb) {
        await _localPlugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(),
          ),
          onDidReceiveNotificationResponse: (resp) => _openRoute(resp.payload),
        );
        final android = _localPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(_androidChannel);
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              // The cross-platform in-app alert host owns foreground
              // presentation and sound. Suppressing the parallel Apple banner
              // prevents duplicate pop-ups for one authoritative event.
              alert: false,
              badge: true,
              sound: false,
            );
      }
    } catch (e, st) {
      _observe(e, st);
    }

    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      _setAuthorization(settings.authorizationStatus);
      if (kDebugMode) {
        debugPrint('[fcm] permission: ${settings.authorizationStatus.name}');
      }
    } catch (e, st) {
      _reportFailure('PERMISSION_STATUS_FAILED', e, st);
    }

    if (_listenersAttached) return;
    _listenersAttached = true;
    // Foreground: FCM does not auto-display consistently, so publish it to the
    // cross-platform alert host. The real record separately syncs from the
    // protected notification table and is de-duplicated by notification ID.
    FirebaseMessaging.onMessage.listen((m) {
      _debugMessage('foreground', m);
      _controller.add(_toPushMessage(m));
    });
    // Backgrounded (app alive, tapped from the tray) → deep-link.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      _debugMessage('opened', m);
      _openMessage(m);
    });
    // Terminated (the tap launched the app fresh) → check once at startup.
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _debugMessage('initial', initial);
        _openMessage(initial);
      }
    } catch (e, st) {
      _observe(e, st);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(
        _registerToken(token).then((registered) {
          _setStatus(
            _status.copyWith(deviceRegistered: registered, errorCode: ''),
          );
        }),
      );
    });
  }

  void _setAuthorization(AuthorizationStatus authorization) {
    final mapped = switch (authorization) {
      AuthorizationStatus.authorized => PushAuthorizationState.authorized,
      AuthorizationStatus.provisional => PushAuthorizationState.provisional,
      AuthorizationStatus.denied => PushAuthorizationState.denied,
      AuthorizationStatus.notDetermined => PushAuthorizationState.notDetermined,
    };
    _setStatus(
      PushDeliveryStatus(
        authorization: mapped,
        deviceRegistered: mapped == _status.authorization
            ? _status.deviceRegistered
            : false,
      ),
    );
  }

  void _setStatus(PushDeliveryStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _reportFailure(String errorCode, Object error, StackTrace stackTrace) {
    _setStatus(
      PushDeliveryStatus(
        authorization: PushAuthorizationState.error,
        errorCode: errorCode,
      ),
    );
    _observe(error, stackTrace);
  }

  Future<String?> _getToken() {
    if (!kIsWeb) return FirebaseMessaging.instance.getToken();
    if (_webPushVapidKey.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[fcm] FIREBASE_WEB_VAPID_KEY is not configured; using Firebase default.',
        );
      }
      return FirebaseMessaging.instance.getToken(
        serviceWorkerScriptPath: 'firebase-messaging-sw.js',
      );
    }
    return FirebaseMessaging.instance.getToken(
      vapidKey: _webPushVapidKey,
      // The dedicated FCM worker owns push without importing Flutter's
      // generated cleanup worker or blocking the application's first paint.
      serviceWorkerScriptPath: 'firebase-messaging-sw.js',
    );
  }

  PushMessage _toPushMessage(RemoteMessage m) {
    final fromData = PushMessage.fromData(
      m.data.map((key, value) => MapEntry(key, '$value')),
    );
    return PushMessage(
      notificationId: fromData.notificationId,
      eventCode: fromData.eventCode,
      surface: fromData.surface,
      type: fromData.type,
      title: fromData.title.isNotEmpty
          ? fromData.title
          : m.notification?.title ?? '',
      titleSecondary: fromData.titleSecondary,
      body: fromData.body.isNotEmpty
          ? fromData.body
          : m.notification?.body ?? '',
      refId: fromData.refId,
      route: fromData.route,
      audience: fromData.audience,
    );
  }

  /// Navigates via the CURRENT router read fresh from Riverpod each time (the
  /// router is recreated on role/session changes — mirrors the existing
  /// pattern in `hardwareActionProvider`, which solves the same "navigate with
  /// no widget context" problem). Never throws — a bad/stale route on tap must
  /// never crash the app.
  void _openRoute(String? route) {
    if (route == null || route.isEmpty) return;
    try {
      _ref.read(appRouterProvider).push(route);
    } catch (e, st) {
      _observe(e, st);
    }
  }

  void _openMessage(RemoteMessage message) {
    final push = _toPushMessage(message);
    if (push.notificationId.isNotEmpty) {
      unawaited(() async {
        try {
          await _ref
              .read(yorksV1NotificationsProvider.notifier)
              .markSeen(push.notificationId);
        } catch (error, stackTrace) {
          _observe(error, stackTrace);
        }
      }());
    }
    _openRoute(_routeWithAcknowledgement(push));
  }

  String _routeWithAcknowledgement(PushMessage push) {
    if (push.route.isEmpty || push.notificationId.isEmpty) return push.route;
    try {
      final route = Uri.parse(push.route);
      return route
          .replace(
            queryParameters: {
              ...route.queryParameters,
              'notificationId': push.notificationId,
            },
          )
          .toString();
    } catch (_) {
      return push.route;
    }
  }

  /// Registers (or refreshes) this device's token against the signed-in user.
  /// Best-effort: push is a convenience, never a requirement to use the app.
  Future<bool> _registerToken([String? currentToken]) async {
    final client = _ref.read(supabaseClientProvider);
    final authUserId = client?.auth.currentUser?.id;
    if (client == null || authUserId == null || authUserId.isEmpty) {
      return false;
    }
    try {
      final token = currentToken ?? await _getToken();
      if (token == null) return false;
      final prefs = _ref.read(sharedPreferencesProvider);
      var installationId = prefs.getString('yorks_push_installation_id');
      if (kIsWeb && installationId == null) {
        installationId = const Uuid().v4();
        await prefs.setString('yorks_push_installation_id', installationId);
      }
      await client.rpc(
        kIsWeb ? 'v1_register_push_installation' : 'v1_register_push_device',
        params: {
          'p_token': token,
          'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          if (kIsWeb) 'p_web_origin': Uri.base.origin,
          if (kIsWeb) 'p_installation_id': installationId,
        },
      );
      return true;
    } catch (e, st) {
      _observe(e, st);
      return false;
    }
  }

  /// De-registers this device — call on sign-out so a stale token can't keep
  /// receiving pushes meant for the account that just signed out.
  Future<void> unregisterToken() async {
    if (!_ready) return;
    final client = _ref.read(supabaseClientProvider);
    if (client == null) return;
    try {
      final token = await _getToken();
      if (token == null) return;
      await client.rpc('v1_unregister_push_device', params: {'p_token': token});
    } catch (e, st) {
      _observe(e, st);
    }
  }

  void _observe(Object e, StackTrace st) {
    try {
      _ref.read(observabilityProvider).recordError(e, st, fatal: false);
    } catch (_) {
      // Observability itself unavailable — nothing further we can do.
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => FcmPushService(ref));

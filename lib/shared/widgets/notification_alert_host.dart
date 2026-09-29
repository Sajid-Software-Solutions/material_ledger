import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart' show appRouterProvider;
import '../../app/router.dart' show RoutePaths;
import '../../core/widgets/yorks_app_toast.dart';
import '../models/app_notification.dart';
import '../models/app_strings.dart';
import '../models/yorks_v1_notification.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/yorks_v1_feature_flags_provider.dart';
import '../providers/yorks_v1_notification_provider.dart';
import '../providers/yorks_v1_notification_preferences_provider.dart';
import '../providers/yorks_v1_team_chat_provider.dart';
import '../services/notification_alert_sound.dart';
import '../services/push_service.dart';

/// Turns authorized notification records into immediate foreground feedback.
///
/// Realtime remains only a refresh signal: this host alerts from the protected
/// notification projection, never from an untrusted client-side workflow
/// mutation. FCM only requests an authorized refresh; its text never becomes
/// a standalone notification outside that feed.
class NotificationAlertHost extends ConsumerStatefulWidget {
  const NotificationAlertHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationAlertHost> createState() =>
      _NotificationAlertHostState();
}

class _NotificationAlertHostState extends ConsumerState<NotificationAlertHost>
    with WidgetsBindingObserver {
  final Set<String> _knownServerIds = <String>{};
  final Set<String> _knownLegacyIds = <String>{};
  final Set<String> _alertedIds = <String>{};
  ProviderSubscription<AsyncValue<List<YorksV1NotificationRecord>>>?
  _serverSubscription;
  ProviderSubscription<List<AppNotification>>? _legacySubscription;
  StreamSubscription<PushMessage>? _pushSubscription;
  bool _serverPrimed = false;
  bool _legacyPrimed = false;
  Future<bool>? _soundPreparation;
  DateTime? _lastSoundAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverSubscription = ref.listenManual(yorksV1NotificationsProvider, (
      _,
      next,
    ) {
      final records = next.valueOrNull;
      if (records == null) {
        if (next.isLoading) _serverPrimed = false;
        return;
      }
      if (!_serverPrimed) {
        _serverPrimed = true;
        _knownServerIds.addAll(records.map((record) => record.id));
        return;
      }
      final newRecords = records
          .where(
            (record) =>
                record.seenAt == null && !_knownServerIds.contains(record.id),
          )
          .toList(growable: false);
      _knownServerIds.addAll(records.map((record) => record.id));
      final language = ref.read(languageProvider);
      for (final record in newRecords.reversed) {
        _show(
          record.toAppNotification(language),
          icon: record.isChatTransport
              ? Icons.chat_bubble_rounded
              : Icons.notifications_active_rounded,
        );
      }
    }, fireImmediately: true);
    _legacySubscription = ref.listenManual(notificationsProvider, (_, next) {
      if (!_legacyPrimed) {
        _legacyPrimed = true;
        _knownLegacyIds.addAll(next.map((notification) => notification.id));
        return;
      }
      final visibleIds = ref
          .read(visibleNotificationsProvider)
          .map((notification) => notification.id)
          .toSet();
      final additions = next
          .where(
            (notification) =>
                !notification.isRead &&
                visibleIds.contains(notification.id) &&
                !_knownLegacyIds.contains(notification.id),
          )
          .toList(growable: false);
      _knownLegacyIds.addAll(next.map((notification) => notification.id));
      for (final notification in additions.reversed) {
        _show(notification);
      }
    }, fireImmediately: true);
    _pushSubscription = ref.read(pushServiceProvider).onMessage.listen((push) {
      // Push is only a refresh signal. Test/console messages and stale payloads
      // cannot create an alert absent from the recipient's authorized feed.
      unawaited(ref.read(yorksV1NotificationsProvider.notifier).refresh());
      if (push.isTeamChat) _refreshChat();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Web Audio contexts and native audio sessions can be suspended while
      // the app is backgrounded. Re-prepare on resume and on the next pointer
      // gesture so a successful first alert does not make later alerts silent.
      unawaited(_prepareSound());
      unawaited(ref.read(yorksV1NotificationsProvider.notifier).refresh());
      _refreshChat();
      unawaited(ref.read(pushServiceProvider).register());
    }
  }

  Future<bool> _prepareSound() {
    final inFlight = _soundPreparation;
    if (inFlight != null) return inFlight;
    late final Future<bool> attempt;
    attempt = prepareNotificationAlertSound().whenComplete(() {
      if (identical(_soundPreparation, attempt)) _soundPreparation = null;
    });
    _soundPreparation = attempt;
    return attempt;
  }

  Future<void> _playSound() async {
    if (await _prepareSound()) await playNotificationAlertSound();
  }

  Future<void> _markRead(AppNotification notification) async {
    try {
      await ref.read(notificationActionsProvider).markRead(notification);
    } catch (_) {
      // The optimistic server state rolls back and Realtime/polling retries.
    }
  }

  void _refreshChat() {
    if (!ref.read(yorksV1FeatureFlagsProvider).teamChat) return;
    unawaited(ref.read(yorksV1TeamChatProvider.notifier).refresh());
  }

  String? _activeRoutePath() {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      try {
        return ref
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path;
      } catch (_) {
        // This host is also reusable in embedded MaterialApp trees that do
        // not have a GoRouter ancestor. Those trees must still receive alerts.
        return null;
      }
    }
  }

  void _show(
    AppNotification notification, {
    IconData icon = Icons.notifications_active_rounded,
  }) {
    if (!mounted || notification.title.trim().isEmpty) return;
    final notificationPath = notification.route.isEmpty
        ? ''
        : Uri.tryParse(notification.route)?.path ?? '';
    if (notificationPath.startsWith(RoutePaths.yorksV1TeamChat) &&
        _activeRoutePath() == notificationPath) {
      unawaited(_markRead(notification));
      return;
    }
    if (!ref.read(yorksV1ForegroundAlertsEnabledProvider)) return;
    if (notification.id.isNotEmpty) {
      if (_alertedIds.contains(notification.id)) return;
      _alertedIds.add(notification.id);
    }
    final now = DateTime.now();
    if (ref.read(yorksV1NotificationSoundEnabledProvider) &&
        (_lastSoundAt == null ||
            now.difference(_lastSoundAt!) >
                const Duration(milliseconds: 700))) {
      _lastSoundAt = now;
      unawaited(_playSound());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final localNavigator = Navigator.maybeOf(context, rootNavigator: true);
      final routerNavigator = localNavigator == null
          ? ref.read(appRouterProvider).routerDelegate.navigatorKey.currentState
          : null;
      final alertContext =
          (localNavigator ?? routerNavigator)?.overlay?.context;
      if (alertContext == null) return;
      YorksAppToast.show(
        alertContext,
        title: notification.title,
        message: notification.body,
        duration: const Duration(seconds: 4),
        maxWidth: 560,
        icon: icon,
        actionLabel: notification.route.isEmpty
            ? null
            : AppStrings.viewDetails.active(ref.read(languageProvider)),
        onAction: notification.route.isEmpty
            ? null
            : () {
                unawaited(_markRead(notification));
                try {
                  ref.read(appRouterProvider).push(notification.route);
                } catch (_) {
                  // A stale deep link must not make the alert action fatal.
                }
              },
        dismissible: true,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverSubscription?.close();
    _legacySubscription?.close();
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => unawaited(_prepareSound()),
      child: widget.child,
    );
  }
}

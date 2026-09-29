import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/notification_provider.dart';
import 'package:material_ledger/shared/screens/notifications_screen.dart';
import 'package:material_ledger/shared/services/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(_loadGoldenFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final evidence in <({String name, Size size})>[
    (name: 'notification_center_desktop.png', size: const Size(1366, 768)),
    (name: 'notification_center_mobile.png', size: const Size(360, 800)),
  ]) {
    testWidgets('authoritative notification centre — ${evidence.size}', (
      tester,
    ) async {
      tester.view.physicalSize = evidence.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final notification = YorksV1NotificationRecord(
        id: '21000000-0000-4000-8000-000000000001',
        eventCode: 'company_material_request_approval_requested',
        entityType: 'company_material_request',
        entityId: '22000000-0000-4000-8000-000000000001',
        createdAt: DateTime.now(),
      ).toAppNotification(AppLanguage.english);
      final unavailable = YorksV1NotificationRecord(
        id: '21000000-0000-4000-8000-000000000002',
        eventCode: 'historical_event',
        entityType: 'historical_record',
        entityId: 'unknown',
        createdAt: DateTime.now(),
      ).toAppNotification(AppLanguage.english);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
          GoRoute(
            path: notification.route,
            builder: (_, _) =>
                const Scaffold(body: Text('Company request detail target')),
          ),
        ],
      );
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            pushServiceProvider.overrideWithValue(
              const _RegisteredPushService(),
            ),
            visibleNotificationsProvider.overrideWithValue([
              notification,
              unavailable,
            ]),
            unreadNotificationCountProvider.overrideWithValue(1),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Company request approval required'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.byType(Dismissible), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      expect(unavailable.route, isEmpty);
      await expectLater(
        find.byType(NotificationsScreen),
        matchesGoldenFile('goldens/push_p0/${evidence.name}'),
      );
      await tester.tap(find.text('Company request approval required'));
      await tester.pumpAndSettle();
      expect(find.text('Company request detail target'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }
}

class _RegisteredPushService implements PushService {
  const _RegisteredPushService();
  @override
  Stream<PushMessage> get onMessage => const Stream.empty();
  @override
  Stream<PushDeliveryStatus> get onStatus => const Stream.empty();
  @override
  PushDeliveryStatus get status => const PushDeliveryStatus(
    authorization: PushAuthorizationState.authorized,
    deviceRegistered: true,
  );
  @override
  Future<String?> register() async => null;
  @override
  Future<PushDeliveryStatus> enable() async => status;
}

Future<void> _loadGoldenFonts() async {
  final nexus = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final cache = _flutterCacheDirectory();
  final icons = await File(
    '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await Future.wait([nexus.load(), materialIcons.load()]);
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

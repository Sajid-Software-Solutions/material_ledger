import 'package:material_ledger/shared/providers/language_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/workforce_providers.dart';
import 'package:material_ledger/features/workforce/application/workforce_team_workers_controller.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/presentation/screens/yorks_workforce_team_workers_screen.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var cache = File(Platform.resolvedExecutable).parent;
    for (
      var i = 0;
      i < 5 && !Directory('${cache.path}/artifacts').existsSync();
      i++
    ) {
      cache = cache.parent;
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await Future.wait([font.load(), icons.load()]);
  });
  for (final width in [360.0, 1366.0]) {
    testWidgets('assigned-team worker creation at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _Repo();
      final controller = WorkforceTeamWorkersController(
        repo,
        YorksV1CriticalCommandKeyStore(
          preferences: await SharedPreferences.getInstance(),
          actorAuthUserId: 'actor',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            yorksWorkforceTeamWorkersProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksWorkforceTeamWorkersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Own team'), findsOneWidget);
      await tester.tap(find.text('Add worker'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(4), '2026-01-01');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/workforce_team_worker_form_${width.toInt()}.png',
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Test worker');
      await tester.enterText(fields.at(2), 'Technician');
      await tester.enterText(fields.at(3), 'Test employer');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Add worker'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.payload!['worker_number'], '');
      expect(repo.team, 'team-a');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Repo implements YorksWorkforceTeamWorkerRepository {
  String? team;
  Map<String, Object?>? payload;
  @override
  Future<Map<String, dynamic>> getTeamWorkers({
    String? teamId,
    int offset = 0,
  }) async => {
    'teams': [
      {'id': 'team-a', 'name': 'Own team'},
    ],
    'workers': [],
  };
  @override
  Future<Map<String, dynamic>> createTeamWorker(
    String teamId,
    Map<String, Object?> p,
    String idempotencyKey,
  ) async {
    team = teamId;
    payload = p;
    return {'worker_id': 'worker'};
  }
}

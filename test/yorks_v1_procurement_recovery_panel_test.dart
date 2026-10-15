import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_procurement_progress_controller.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_procurement_progress.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_procurement_progress_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_procurement_recovery_store.dart';
import 'package:material_ledger/shared/widgets/yorks_v1_procurement_progress_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    var directory = File(Platform.resolvedExecutable).parent;
    for (var level = 0; level < 8; level++) {
      if (directory.path.endsWith('${Platform.pathSeparator}cache')) break;
      directory = directory.parent;
    }
    final bytes = await File(
      '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await Future.wait([font.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [1366.0, 360.0]) {
    testWidgets(
      'truthful recovery panel checking unknown confirmed ${width.toInt()}',
      (tester) async {
        tester.view.physicalSize = Size(width, 450);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final repository = _Repository();
        final editor = YorksV1ProcurementProgressController(
          repository: repository,
          recoveryStore: YorksV1ProcurementRecoveryStore(
            preferences: await SharedPreferences.getInstance(),
            backendIdentity: 'local',
            actorAuthUserId: 'procurement',
          ),
          scope: _draft.scope,
          delay: (_) async {},
        );
        addTearDown(editor.dispose);
        await editor.initialize(_draft);
        await editor.prepareFinalIntent(
          commandName: 'v1_dispatch_materials',
          commandKey: 'frozen-key',
          commandPayload: {'request_id': 'request', 'lines': <Object?>[]},
        );
        repository.wait = Completer<YorksV1ProcurementCommandOutcome>();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: YorksV1ProcurementProgressPanel(
                    controller: editor,
                    language: AppLanguage.english,
                  ),
                ),
              ),
            ),
          ),
        );
        final recovering = editor.rejectFinalIntent(
          const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
        await tester.pump();
        expect(
          find.text(
            'Checking whether the dispatch completed… Your dispatch details are preserved.',
          ),
          findsOneWidget,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/procurement_recovery_checking_${width.toInt()}.png',
          ),
        );
        repository.wait!.complete(
          const YorksV1ProcurementCommandOutcome(
            status: 'not_found',
            automaticChecksRemaining: 0,
          ),
        );
        await recovering;
        await tester.pump();
        expect(find.text('Check status'), findsOneWidget);
        expect(
          find.textContaining('We could not confirm the result yet.'),
          findsOneWidget,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/procurement_recovery_unknown_${width.toInt()}.png',
          ),
        );
        repository.wait = null;
        repository.confirmed = true;
        await tester.tap(find.text('Check status'));
        await tester.pump();
        expect(find.text('Dispatch confirmed — DN-EXACT-42.'), findsOneWidget);
        expect(find.text('Check status'), findsNothing);
        expect(find.textContaining('We could not confirm'), findsNothing);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r35/procurement_recovery_confirmed_${width.toInt()}.png',
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

final _draft = YorksV1ProcurementProgressDraft(
  requestId: 'request',
  editorKind: YorksV1ProcurementEditorKind.dispatch,
  baseRequestVersion: 5,
  inputs: {'dispatch_date': '2026-10-15', 'lines': <Object?>[]},
);

class _Repository implements YorksV1ProcurementProgressRepository {
  Completer<YorksV1ProcurementCommandOutcome>? wait;
  bool confirmed = false;
  @override
  Future<YorksV1ProcurementProgressRead> get(
    YorksV1ProcurementProgressScope scope,
  ) async => const YorksV1ProcurementProgressRead();
  @override
  Future<YorksV1ProcurementProgressCheckpoint> save({
    required YorksV1ProcurementProgressDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => YorksV1ProcurementProgressCheckpoint(
    draft: draft,
    revision: expectedRevision + 1,
    savedAt: DateTime.utc(2026),
  );
  @override
  Future<int> discard({
    required YorksV1ProcurementProgressScope scope,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => expectedRevision + 1;
  @override
  Future<YorksV1ProcurementPendingCommand> prepare({
    required YorksV1ProcurementProgressScope scope,
    required int checkpointRevision,
    required String commandName,
    required String commandKey,
    required Map<String, Object?> commandPayload,
    required String idempotencyKey,
  }) async => YorksV1ProcurementPendingCommand(
    attemptId: 'attempt',
    commandName: commandName,
    commandKey: commandKey,
  );
  @override
  Future<String> abandon({
    required String requestId,
    required String commandName,
    required String commandKey,
  }) async => 'abandoned';
  @override
  Future<YorksV1ProcurementCommandOutcome> outcome({
    required String requestId,
    required String commandName,
    required String commandKey,
    bool automatic = false,
  }) async =>
      wait?.future ??
      Future.value(
        YorksV1ProcurementCommandOutcome(
          status: confirmed ? 'confirmed' : 'not_found',
          effectId: confirmed ? 'dispatch-exact-42' : null,
          effectReference: confirmed ? 'DN-EXACT-42' : null,
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_completion.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';

import '../tool/project_setup_completion_fixture.dart';

void main() {
  final copy = YorksV1ProjectSetupCompletionCopy.localized(AppLanguage.english);
  const permissions = YorksV1ProjectSetupCompletionPermissions(
    canOpenProject: true,
    canEditProject: true,
    canAddBoq: true,
    canInviteTeam: true,
    canUploadDocuments: true,
    canCreateMaterialRequests: true,
    canReturnToProjects: true,
  );
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 1200,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1024),
              textScaler: TextScaler.linear(scale),
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('completion copy covers every configured language and text key', () {
    for (final language in AppLanguage.values) {
      final localized = YorksV1ProjectSetupCompletionCopy.localized(language);
      for (final key in YorksV1ProjectSetupCompletionText.values) {
        expect(
          localized[key].trim(),
          isNotEmpty,
          reason: '${language.name}: $key',
        );
      }
    }
  });

  testWidgets('no completion is shown for an uncertain create outcome', (
    tester,
  ) async {
    final operation = projectSetupCompletionFixtureOperation().copyWith(
      core: YorksV1ProjectSetupCommand(
        kind: YorksV1ProjectSetupCommandKind.create,
        idempotencyKey: 'original-intent',
        payload: {'project_ref': 'YRA-322'},
        status: YorksV1ProjectSetupCommandStatus.outcomeUncertain,
      ),
    );
    await pump(
      tester,
      YorksV1ProjectSetupCompletion(
        operation: operation,
        copy: copy,
        permissions: permissions,
      ),
    );
    expect(
      find.text(copy[YorksV1ProjectSetupCompletionText.createdTitle]),
      findsNothing,
    );
    expect(find.text('YRA-322'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'known Active result shows confirmed summary and explicit permitted actions',
    (tester) async {
      var openCalls = 0;
      var boqCalls = 0;
      await pump(
        tester,
        YorksV1ProjectSetupCompletion(
          operation: projectSetupCompletionFixtureOperation(),
          copy: copy,
          permissions: permissions,
          onOpenProject: () => openCalls++,
          onAddBoq: () => boqCalls++,
          onInviteTeam: () {},
          onUploadDocuments: () {},
          onReturnToProjects: () {},
        ),
      );
      expect(find.text('YRA-322'), findsOneWidget);
      expect(find.text('NEXUS — Four substations'), findsOneWidget);
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.activeState]),
        findsOneWidget,
      );
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.createRequests]),
        findsOneWidget,
      );
      expect(openCalls, 0);
      expect(boqCalls, 0);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          copy[YorksV1ProjectSetupCompletionText.openProject],
        ),
      );
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          copy[YorksV1ProjectSetupCompletionText.addBoq],
        ),
      );
      expect(openCalls, 1);
      expect(boqCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending activation and files retain Draft, recovery and safe next actions',
    (tester) async {
      final operation = projectSetupCompletionFixtureOperation(
        activationPending: true,
        filesPending: true,
      );
      final originalJson = operation.toJson();
      await pump(
        tester,
        YorksV1ProjectSetupCompletion(
          operation: operation,
          copy: copy,
          permissions: permissions,
          recoveryPanel: const Text('Original intent recovery controls'),
          onOpenProject: () {},
          onEditProject: () {},
          onAddBoq: () {},
          onInviteTeam: () {},
          onUploadDocuments: () {},
          onReturnToProjects: () {},
        ),
      );
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.draftState]),
        findsOneWidget,
      );
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.activationPending]),
        findsOneWidget,
      );
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.filesPending]),
        findsOneWidget,
      );
      expect(find.text('Original intent recovery controls'), findsOneWidget);
      expect(
        find.widgetWithText(
          FilledButton,
          copy[YorksV1ProjectSetupCompletionText.openProject],
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          copy[YorksV1ProjectSetupCompletionText.uploadDocuments],
        ),
        findsOneWidget,
      );
      for (final key in [
        YorksV1ProjectSetupCompletionText.addBoq,
        YorksV1ProjectSetupCompletionText.inviteTeam,
        YorksV1ProjectSetupCompletionText.editProject,
        YorksV1ProjectSetupCompletionText.createRequests,
      ]) {
        expect(find.text(copy[key]), findsNothing);
      }
      expect(operation.toJson(), originalJson);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful create grants no action without explicit permissions',
    (tester) async {
      await pump(
        tester,
        YorksV1ProjectSetupCompletion(
          operation: projectSetupCompletionFixtureOperation(),
          copy: copy,
          permissions: const YorksV1ProjectSetupCompletionPermissions(),
          onOpenProject: () {},
          onEditProject: () {},
          onAddBoq: () {},
          onInviteTeam: () {},
          onUploadDocuments: () {},
          onReturnToProjects: () {},
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dismissing cosmetic success banner keeps all pending-work warnings',
    (tester) async {
      await pump(
        tester,
        YorksV1ProjectSetupCompletion(
          operation: projectSetupCompletionFixtureOperation(
            activationPending: true,
            filesPending: true,
          ),
          copy: copy,
          permissions: permissions,
          showBanner: false,
          localRecoveryPending: true,
        ),
      );
      expect(
        find.text(copy[YorksV1ProjectSetupCompletionText.createdTitle]),
        findsNothing,
      );
      for (final key in [
        YorksV1ProjectSetupCompletionText.activationPending,
        YorksV1ProjectSetupCompletionText.filesPending,
        YorksV1ProjectSetupCompletionText.recoveryPending,
      ]) {
        expect(find.text(copy[key]), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in [
    AppLanguage.english,
    AppLanguage.arabic,
    AppLanguage.urdu,
    AppLanguage.hindi,
  ]) {
    testWidgets('360px completion supports ${language.name} at 2x text size', (
      tester,
    ) async {
      await pump(
        tester,
        buildProjectSetupCompletionFixture(
          language: language,
          activationPending: true,
          filesPending: true,
        ),
        width: 360,
        scale: 2,
      );
      final context = tester.element(
        find.byType(YorksV1ProjectSetupCompletion),
      );
      final directionality = find
          .descendant(
            of: find.byType(YorksV1ProjectSetupCompletion),
            matching: find.byType(Directionality),
          )
          .first;
      expect(
        (tester.widget(directionality) as Directionality).textDirection,
        language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(context.mounted, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

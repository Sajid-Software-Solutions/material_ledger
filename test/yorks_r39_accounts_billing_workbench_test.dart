import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_models.dart';
import 'package:material_ledger/features/accounts/presentation/widgets/yorks_accounts_billing_workbench.dart';
import 'package:material_ledger/shared/models/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await Future.wait([font.load(), arabic.load()]);
  });

  testWidgets('multi-building workbench matches the desktop design hierarchy', (
    tester,
  ) async {
    await _pumpWorkbench(tester, const Size(1440, 900));

    expect(find.text('DF3W'), findsWidgets);
    expect(find.text('DF4W'), findsOneWidget);
    expect(find.text('DF6W'), findsOneWidget);
    expect(find.text('DF7W'), findsOneWidget);
    expect(find.text('Material Supply'), findsWidgets);
    expect(find.text('Line details'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksAccountsBillingWorkbench),
      matchesGoldenFile(
        'goldens/yorks_r39_accounts_billing_workbench_component_desktop.png',
      ),
    );
  });

  testWidgets(
    'multi-building workbench is card-based and expandable on mobile',
    (tester) async {
      await _pumpWorkbench(tester, const Size(390, 1900));

      expect(find.byType(DataTable), findsNothing);
      expect(
        find.byKey(const ValueKey('accounts-building-expanded-df3w')),
        findsOneWidget,
      );
      await tester.tap(find.text('DF4W').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('accounts-building-expanded-df3w')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('accounts-building-expanded-df4w')),
        findsOneWidget,
      );
      expect(find.text('Line details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksAccountsBillingWorkbench),
        matchesGoldenFile(
          'goldens/yorks_r39_accounts_billing_workbench_component_mobile.png',
        ),
      );
    },
  );

  for (final size in const [Size(1440, 900), Size(360, 800)]) {
    testWidgets(
      'reduced motion: buildings open and close without a layout error '
      'at ${size.width.toInt()}px',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _pumpWorkbench(tester, size);
        final df4w = find.text('DF4W').first;

        // DF3W closes while DF4W opens.
        await tester.ensureVisible(df4w);
        await tester.pumpAndSettle();
        await tester.tap(df4w);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          tester
              .renderObjectList<RenderAnimatedSize>(find.byType(AnimatedSize))
              .where((size) => size.isAnimating),
          isEmpty,
          reason: 'reduced motion runs the size change in one frame',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('accounts-building-expanded-df3w')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('accounts-building-expanded-df4w')),
          findsOneWidget,
        );

        await tester.ensureVisible(df4w);
        await tester.pumpAndSettle();
        await tester.tap(df4w);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('accounts-building-expanded-df4w')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpWorkbench(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: YorksAccountsBillingWorkbench(
              baseline: _baseline,
              progress: _progress,
              language: AppLanguage.english,
              onAction: (_) async => false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _capabilities = YorksAccountsCapabilities(
  canView: true,
  canViewValues: true,
  canConfigure: true,
  canSuggest: false,
  canConfirm: false,
  canReview: true,
);

const _buildings = <({String id, String name})>[
  (id: 'df3w', name: 'DF3W'),
  (id: 'df4w', name: 'DF4W'),
  (id: 'df6w', name: 'DF6W'),
  (id: 'df7w', name: 'DF7W'),
];

const _stages = <({String key, String label, int position, String allocation})>[
  (key: 'design', label: 'Design', position: 1, allocation: '10'),
  (
    key: 'material_supply',
    label: 'Material Supply',
    position: 2,
    allocation: '50',
  ),
  (key: 'installation', label: 'Installation', position: 3, allocation: '30'),
  (key: 'commissioning', label: 'Commissioning', position: 4, allocation: '5'),
  (key: 'energizing', label: 'Energizing', position: 5, allocation: '5'),
];

final _baseline = YorksAccountsBaselineProjection(
  schemaVersion: 2,
  projectId: 'fixture-project',
  baseline: YorksAccountsBaselineRevision(
    revisionId: 'baseline-1',
    revisionNumber: 1,
    recordVersion: 1,
    status: 'active',
    contractValue: YorksAccountsDecimal.parse('17192000'),
    currencyCode: 'AED',
    vatRate: YorksAccountsDecimal.parse('5'),
    paymentTermsDays: 90,
    reminderLeadDays: 10,
    reason: 'Visual fixture',
    createdAt: DateTime.utc(2026, 9, 19),
    createdBy: 'fixture-user',
    managementReviewPolicy: YorksAccountsManagementReviewPolicy(
      alwaysRequired: false,
      thresholdAmount: null,
      confirmingExactRoles: const ['project_manager'],
    ),
  ),
  physicalBuildings: [
    for (final building in _buildings)
      YorksAccountsPhysicalBuilding(
        buildingScopeId: building.id,
        buildingName: building.name,
        scopeCode: building.name,
      ),
  ],
  stageTemplates: [
    for (final stage in _stages)
      YorksAccountsStageTemplate(
        stageKey: stage.key,
        stageLabel: stage.label,
        position: stage.position,
        allocationPercent: YorksAccountsDecimal.parse(stage.allocation),
      ),
  ],
  buildingAllocations: [
    for (final building in _buildings)
      YorksAccountsBuildingAllocation(
        allocationId: 'allocation-${building.id}',
        buildingScopeId: building.id,
        buildingName: building.name,
        allocationPercent: YorksAccountsDecimal.parse('25'),
        allocatedValue: YorksAccountsDecimal.parse('4298000'),
      ),
  ],
  stageAllocations: [
    for (final stage in _stages)
      YorksAccountsStageAllocation(
        allocationId: 'stage-${stage.key}',
        stageKey: stage.key,
        stageLabel: stage.label,
        position: stage.position,
        allocationPercent: YorksAccountsDecimal.parse(stage.allocation),
        stageValue: YorksAccountsDecimal.parse(switch (stage.key) {
          'design' => '1719200',
          'material_supply' => '8596000',
          'installation' => '5157600',
          _ => '859600',
        }),
      ),
  ],
  capabilities: _capabilities,
  commands: YorksAccountsCommandAvailability.fromRpcJson(const {
    'revise_baseline': true,
  }),
);

final _progress = YorksAccountsProgressProjection(
  schemaVersion: 2,
  projectId: 'fixture-project',
  baselineRevisionId: 'baseline-1',
  baselineRevisionNumber: 1,
  progress: [
    for (final building in _buildings)
      for (final stage in _stages) _progressEntry(building, stage),
  ],
  totals: YorksAccountsProgressTotals(
    confirmedPercent: YorksAccountsDecimal.parse('15'),
    contractValue: YorksAccountsDecimal.parse('17192000'),
    confirmedEligible: YorksAccountsDecimal.parse('2578800'),
    availableToClaim: YorksAccountsDecimal.parse('2578800'),
  ),
  capabilities: _capabilities,
  commands: YorksAccountsCommandAvailability.fromRpcJson(const {
    'review_progress': true,
  }),
  nextActions: const [],
);

YorksAccountsProgressEntry _progressEntry(
  ({String id, String name}) building,
  ({String key, String label, int position, String allocation}) stage,
) {
  final isDesign = stage.key == 'design';
  final isSelectedReview =
      building.id == 'df3w' && stage.key == 'material_supply';
  final confirmed = isDesign ? '100' : (isSelectedReview ? '40' : '0');
  final suggested = isSelectedReview ? '55' : confirmed;
  final stageValue = switch (stage.key) {
    'design' => '429800',
    'material_supply' => '2149000',
    'installation' => '1289400',
    _ => '214900',
  };
  final eligible = isDesign ? '429800' : (isSelectedReview ? '859600' : '0');
  return YorksAccountsProgressEntry(
    progressEntryId: '${building.id}-${stage.key}',
    projectId: 'fixture-project',
    baselineRevisionId: 'baseline-1',
    buildingScopeId: building.id,
    buildingName: building.name,
    stageKey: stage.key,
    stageLabel: stage.label,
    stagePosition: stage.position,
    recordVersion: 1,
    suggestedPercent: YorksAccountsDecimal.parse(suggested),
    confirmedPercent: YorksAccountsDecimal.parse(confirmed),
    reviewStatus: isSelectedReview
        ? YorksAccountsReviewStatus.pending
        : (isDesign
              ? YorksAccountsReviewStatus.approved
              : YorksAccountsReviewStatus.notRequired),
    evidenceSummary: isSelectedReview
        ? 'Three protected evidence files are ready for review.'
        : null,
    evidenceDocumentIds: isSelectedReview
        ? const ['evidence-1', 'evidence-2', 'evidence-3']
        : (isDesign ? const ['design-evidence'] : const []),
    actionOwner: isSelectedReview ? 'project_manager' : 'accountant',
    stageValue: YorksAccountsDecimal.parse(stageValue),
    confirmedEligible: YorksAccountsDecimal.parse(eligible),
    previouslyClaimedAmount: YorksAccountsDecimal.zero,
    availableToClaim: YorksAccountsDecimal.parse(eligible),
    revisions: const [],
    nextActions: isSelectedReview
        ? const [
            YorksAccountsNextAction(
              code: 'review_progress',
              entityId: 'df3w-material_supply',
              ownerRole: 'project_manager',
              blockingReasonCode: null,
              isAvailable: true,
            ),
          ]
        : const [],
    updatedAt: DateTime.utc(2026, 9, 19, 12),
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/overview/yorks_v1_role_overview_builders.dart';
import 'package:material_ledger/features/projects/presentation/overview/yorks_v1_role_overview_layout.dart';
import 'package:material_ledger/features/projects/presentation/overview/yorks_v1_role_overview_spec.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_audit_workspace.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_portfolio.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';

/// Role-based Overview (`YORKS_V1_ROLE_OVERVIEW_V2`): builder mapping,
/// every role at desktop and phone width, queue behaviour and visual evidence
/// under `test/goldens/role_overview/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  group('work kind and stage mapping', () {
    test('reads the next step from state and the server action code', () {
      expect(
        yorksOverviewWorkKind(
          _req('a', YorksV1MaterialRequestState.awaitingRequestApproval),
        ),
        YorksOverviewWorkKind.approve,
      );
      expect(
        yorksOverviewWorkKind(
          _req('b', YorksV1MaterialRequestState.awaitingApproval),
        ),
        YorksOverviewWorkKind.approveArrangement,
      );
      expect(
        yorksOverviewWorkKind(
          _req('c', YorksV1MaterialRequestState.approvedForArrangement),
        ),
        YorksOverviewWorkKind.arrange,
      );
      expect(
        yorksOverviewWorkKind(_req('d', YorksV1MaterialRequestState.approved)),
        YorksOverviewWorkKind.dispatch,
      );
      expect(
        yorksOverviewWorkKind(
          _req('e', YorksV1MaterialRequestState.dispatched),
        ),
        YorksOverviewWorkKind.receipt,
      );
      expect(
        yorksOverviewWorkKind(
          _req(
            'f',
            YorksV1MaterialRequestState.partiallyReceived,
            code: 'replacement_dispatch_required',
          ),
        ),
        YorksOverviewWorkKind.replacement,
      );
      expect(
        yorksOverviewWorkKind(
          _req(
            'g',
            YorksV1MaterialRequestState.received,
            code: 'material_request_close_review',
          ),
        ),
        YorksOverviewWorkKind.close,
      );
      expect(
        yorksOverviewWorkKind(
          _req('h', YorksV1MaterialRequestState.changesRequested),
        ),
        YorksOverviewWorkKind.changes,
      );
    });

    test('places every state on the seven-step tracker', () {
      for (final state in YorksV1MaterialRequestState.values) {
        final stage = yorksOverviewStage(state);
        expect(stage, inInclusiveRange(1, 7), reason: state.name);
      }
      expect(yorksOverviewStage(YorksV1MaterialRequestState.closed), 7);
      expect(yorksOverviewStage(YorksV1MaterialRequestState.approved), 4);
    });
  });

  group('builders', () {
    test(
      'Project Engineer queue lists only actionable records, urgent first',
      () {
        final spec = _spec(YorksV1Role.projectEngineer);
        final queue = spec.left.first as YorksOverviewQueueSection;
        expect(queue.id, 'work');
        expect(queue.rows.first.tag, 'Urgent');
        expect(queue.rows.map((r) => r.reference), contains('YRA-322-MR021'));
        expect(
          spec.kpis.firstWhere((k) => k.id == 'approve').value,
          '3',
          reason: 'two request approvals and one arrangement approval',
        );
        expect(spec.full.single.id, 'proj');
      },
    );

    test('Procurement sees arrange and dispatch work and low stock', () {
      final spec = _spec(YorksV1Role.procurement);
      expect(spec.kpis.firstWhere((k) => k.id == 'arrange').value, '1');
      expect(spec.kpis.firstWhere((k) => k.id == 'dispatch').value, '1');
      expect(spec.kpis.firstWhere((k) => k.id == 'stock').value, '2');
      final stock =
          spec.allSections.firstWhere((s) => s.id == 'stock')
              as YorksOverviewTableSection;
      expect(
        stock.rows.first.cells.first.text,
        'Motorized fire damper 600×400',
      );
    });

    test('Site Engineer queue includes private drafts', () {
      final spec = _spec(YorksV1Role.siteEngineer);
      final queue = spec.left.first as YorksOverviewQueueSection;
      expect(queue.rows.where((r) => r.tab == 'draft'), hasLength(2));
      expect(spec.kpis.firstWhere((k) => k.id == 'drafts').value, '2');
    });

    test('nothing to act on shows the all-clear copy and green zero tiles', () {
      final spec = _spec(YorksV1Role.projectEngineer, empty: true);
      final queue = spec.left.first as YorksOverviewQueueSection;
      expect(queue.rows, isEmpty);
      final approve = spec.kpis.firstWhere((k) => k.id == 'approve');
      expect(approve.value, '0');
      expect(approve.caption, 'Nothing waiting');
    });

    test('a revoked project is hidden from every list', () {
      final spec = _spec(
        YorksV1Role.projectEngineer,
        canRead: (projectId) => projectId != 'p1',
      );
      final queue = spec.left.first as YorksOverviewQueueSection;
      expect(
        queue.rows.where((r) => r.reference!.startsWith('YRA-322')),
        isEmpty,
      );
      final table = spec.full.single as YorksOverviewTableSection;
      expect(
        table.rows.where((r) => r.cells.first.text.startsWith('YRA-322')),
        isEmpty,
      );
    });

    test('loading and failed projections are shown, not guessed', () {
      final spec = _spec(YorksV1Role.projectEngineer, loading: true);
      expect(spec.left.first.load, YorksOverviewLoad.loading);
      expect(
        spec.kpis.firstWhere((k) => k.id == 'approve').load,
        YorksOverviewLoad.loading,
      );
      final failed = _spec(YorksV1Role.projectEngineer, failed: true);
      expect(failed.left.first.load, YorksOverviewLoad.error);
      // A failed projection is never shown as a green zero.
      for (final id in ['approve', 'receipt', 'exceptions']) {
        final tile = failed.kpis.firstWhere((k) => k.id == id);
        expect(tile.value, '—', reason: id);
        expect(tile.caption, isNot('Nothing waiting'), reason: id);
        expect(tile.load, YorksOverviewLoad.error, reason: id);
      }
    });

    test('a failed audit load shows an error, not endless loading', () {
      final spec = _spec(YorksV1Role.admin, auditFailed: true);
      final act = spec.allSections.firstWhere((s) => s.id == 'act');
      expect(act.load, YorksOverviewLoad.error);
    });

    test('a capped request page is shown as a lower bound', () {
      final spec = _spec(YorksV1Role.siteEngineer, mineHasMore: true);
      expect(spec.kpis.firstWhere((k) => k.id == 'mine').value, endsWith('+'));
    });

    test('Admin keeps the rental and audit summaries', () {
      final spec = _spec(YorksV1Role.admin);
      final ids = spec.allSections.map((s) => s.id).toSet();
      expect(ids, containsAll(['rent', 'act', 'projects', 'flow']));
      final rent =
          spec.allSections.firstWhere((s) => s.id == 'rent')
              as YorksOverviewMoneySection;
      expect(rent.rows.first.value, '7 of 8 units');
      expect(
        _spec(YorksV1Role.projectEngineer).allSections.map((s) => s.id),
        isNot(contains('rent')),
      );
    });

    test('every role builds a complete Overview', () {
      for (final role in YorksV1Role.values) {
        final spec = _spec(role);
        expect(spec.kpis, isNotEmpty, reason: role.name);
        final ids = spec.allSections.map((s) => s.id).toSet();
        for (final id in spec.phoneOrder) {
          expect(ids, contains(id), reason: '${role.name} phone $id');
        }
        for (final kpi in spec.kpis) {
          if (kpi.targetSection != null) {
            expect(ids, contains(kpi.targetSection), reason: kpi.id);
          }
        }
      }
    });
  });

  test('the role Overview flag is off by default and needs requests', () {
    expect(const YorksV1FeatureFlags().roleOverviewV2, isFalse);
    expect(
      const YorksV1FeatureFlags(roleOverviewV2: true).roleOverviewV2,
      isFalse,
    );
    expect(
      const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        roleOverviewV2: true,
      ).roleOverviewV2,
      isTrue,
    );
  });

  testWidgets('selecting a tile filters the queue', (tester) async {
    await _pump(tester, YorksV1Role.projectEngineer, const Size(1440, 1000));
    expect(find.text('Confirm receipt'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('role-overview-kpi-approve')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm receipt'), findsNothing);
    expect(find.text('Approve request'), findsWidgets);
  });

  for (final role in [
    YorksV1Role.projectEngineer,
    YorksV1Role.siteEngineer,
    YorksV1Role.procurement,
    YorksV1Role.seniorMechanicalEngineer,
    YorksV1Role.projectManager,
    YorksV1Role.workshopInCharge,
    YorksV1Role.documentController,
    YorksV1Role.admin,
  ]) {
    for (final view in [
      (name: 'desktop', size: const Size(1440, 1400)),
      (name: 'phone', size: const Size(390, 2200)),
      (name: 'narrow', size: const Size(360, 2400)),
    ]) {
      testWidgets('${role.name} renders at ${view.name} width', (tester) async {
        await _pump(tester, role, view.size);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('role-overview-title')),
          findsOneWidget,
        );
        if (view.name != 'narrow') {
          await expectLater(
            find.byType(YorksRoleOverviewLayout),
            matchesGoldenFile(
              'goldens/role_overview/${role.claimValue}_${view.name}.png',
            ),
          );
        }
      });
    }
  }
}

// ─── Harness ──────────────────────────────────────────────────────────────

Future<void> _pump(WidgetTester tester, YorksV1Role role, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksRoleOverviewLayout(
            spec: _spec(role),
            language: AppLanguage.english,
            updatedAt: DateTime(2026, 11, 9, 9, 42),
            onRefresh: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _now = DateTime(2026, 11, 9, 10);

YorksRoleOverviewSpec _spec(
  YorksV1Role role, {
  bool empty = false,
  bool loading = false,
  bool failed = false,
  bool auditFailed = false,
  bool mineHasMore = false,
  bool Function(String projectId)? canRead,
}) {
  AsyncValue<T> wrap<T>(T value) => loading
      ? AsyncLoading<T>()
      : failed
      ? AsyncError<T>(StateError('offline'), StackTrace.empty)
      : AsyncData<T>(value);
  final work = empty ? <YorksV1MaterialRequestSummary>[] : _work(role);
  return buildYorksRoleOverviewSpec(
    YorksRoleOverviewInputs(
      role: role,
      language: AppLanguage.english,
      now: _now,
      displayName: _names[role],
      projects: AsyncData(
        YorksV1ProjectOverview(
          items: _portfolio.take(6).toList(),
          total: 5,
          active: 4,
          onHold: 1,
          completed: 0,
        ),
      ),
      portfolio: AsyncData(_portfolio),
      requests: AsyncData(
        YorksV1MaterialRequestOverview(
          items: const [],
          total: 313,
          open: 41,
          needsAction: work.length,
          approvals: 4,
          deliveryExceptions: 5,
          receiptPending: 3,
          draftsAndChanges: 2,
          received: 1,
          closed: 260,
          dispatchReady: 3,
          newToArrange: 6,
        ),
      ),
      myWork: wrap(_page(work)),
      exceptions: wrap(_page(empty ? const [] : _exceptions)),
      active: AsyncData(_page(_active)),
      delivery: AsyncData(_page(_active)),
      mine: AsyncData(_page(_active.take(5).toList(), hasMore: mineHasMore)),
      closed: AsyncData(_page(_closedItems)),
      inventory: AsyncData(_inventory),
      operations: const AsyncData(
        YorksV1MaterialRequestOperationsDashboard(
          myWorkCount: 2,
          exceptionRequestCount: 4,
          requiredDateOverdueCount: 1,
          actionDuePolicy: 'not_configured',
          outstandingReplacementQuantity: '30',
          averageArrangementHours: 33.6,
          warehouseFillRatePercent: 86,
          averageReceiptTurnaroundHours: 50.4,
        ),
      ),
      drafts: AsyncData(_drafts),
      rentals: role == YorksV1Role.admin ? AsyncData(_rentals) : null,
      audit: role == YorksV1Role.admin && !auditFailed ? _audit : null,
      auditFailed: role == YorksV1Role.admin && auditFailed,
      canCreateProject: role != YorksV1Role.procurement,
      canCreateRequest: role != YorksV1Role.procurement,
      canBrowseInventory: true,
      canManageUsers:
          role == YorksV1Role.admin ||
          role == YorksV1Role.seniorMechanicalEngineer,
      canReadProject: canRead ?? (_) => true,
      canReadRequest: canRead ?? (_) => true,
    ),
    YorksRoleOverviewNavigation(
      openRequest: (_) {},
      openRequests: () {},
      openProjects: () {},
      openProject: (_) {},
      newRequest: () {},
      newProject: () {},
      openDraft: (_) {},
      openInventory: () {},
      openDispatches: () {},
      openReturns: () {},
      newReturn: () {},
      openUsers: () {},
      openDuctSizer: () {},
      openEspCalculator: () {},
    ),
  );
}

const _names = {
  YorksV1Role.projectEngineer: 'Faisal Rahman',
  YorksV1Role.siteEngineer: 'Imran Qureshi',
  YorksV1Role.procurement: 'Naveed Akhtar',
  YorksV1Role.seniorMechanicalEngineer: 'Rajesh Nair',
  YorksV1Role.projectManager: 'Sameer Haddad',
  YorksV1Role.workshopInCharge: 'Babu Thomas',
  YorksV1Role.documentController: 'Aisha Karim',
  YorksV1Role.admin: 'Owner',
  YorksV1Role.accountant: 'Priya Menon',
};

const _projectsInfo = {
  'p1': ('YRA-322', 'Nexus 132/33kV Substations'),
  'p2': ('YRA-318', 'Al Reem Tower C'),
  'p3': ('YRA-326', 'Mussafah Warehouse M-44'),
  'p4': ('YRA-329', 'Masdar Lab Building'),
};

YorksV1MaterialRequestSummary _req(
  String id,
  YorksV1MaterialRequestState state, {
  String project = 'p1',
  String? number,
  String scope = 'DF4W',
  String? title,
  bool urgent = false,
  DateTime? scheduled,
  String? code,
  double age = 5,
  bool overdue = false,
  bool canAct = true,
  List<YorksV1MaterialRequestExceptionCode> exceptions = const [],
  int items = 6,
  String requester = 'Imran Qureshi',
}) {
  final info = _projectsInfo[project]!;
  return YorksV1MaterialRequestSummary(
    id: id,
    projectId: project,
    projectReference: info.$1,
    projectName: info.$2,
    scopeId: '$project-$scope',
    scopeName: scope,
    state: state,
    recordVersion: 1,
    requestNumber: number ?? '${info.$1}-MR0$id',
    title: title,
    timing: urgent
        ? YorksV1MaterialRequestTiming.urgent
        : scheduled != null
        ? YorksV1MaterialRequestTiming.scheduled
        : YorksV1MaterialRequestTiming.normal,
    scheduledDate: scheduled,
    requesterDisplayName: requester,
    requesterExactRole: 'site_engineer',
    currentActionCode: code,
    currentActionAgeHours: age,
    requiredOnSiteOverdue: overdue,
    actorCanAct: canAct,
    exceptionCodes: exceptions,
    itemCount: items,
    createdAt: _now.subtract(const Duration(days: 9)),
    updatedAt: _now.subtract(Duration(hours: age.round())),
    workAssignment: YorksV1MaterialRequestWorkAssignment(
      requestId: id,
      assignmentVersion: 0,
      canManage: false,
    ),
  );
}

List<YorksV1MaterialRequestSummary> _work(YorksV1Role role) => switch (role) {
  YorksV1Role.procurement => [
    _req(
      '31',
      YorksV1MaterialRequestState.approvedForArrangement,
      project: 'p2',
      scope: 'Level 15',
      urgent: true,
      age: 2,
      items: 14,
      requester: 'Faisal Rahman',
    ),
    _req(
      '19',
      YorksV1MaterialRequestState.approved,
      scope: 'DF6W',
      scheduled: DateTime(2026, 11, 10),
      age: 26,
    ),
  ],
  YorksV1Role.siteEngineer => [
    _req(
      '18',
      YorksV1MaterialRequestState.dispatched,
      scope: 'DF3W',
      code: 'receipt_review_required',
      age: 2,
      items: 8,
    ),
    _req(
      '20',
      YorksV1MaterialRequestState.changesRequested,
      scope: 'DF6W',
      age: 30,
      items: 9,
    ),
  ],
  _ => [
    _req(
      '21',
      YorksV1MaterialRequestState.awaitingRequestApproval,
      urgent: true,
      age: 50,
      items: 12,
    ),
    _req(
      '09',
      YorksV1MaterialRequestState.dispatched,
      scope: 'DF3W',
      code: 'receipt_review_required',
      age: 2,
      items: 8,
    ),
    _req(
      '08',
      YorksV1MaterialRequestState.awaitingRequestApproval,
      project: 'p2',
      scope: 'Level 14',
      scheduled: DateTime(2026, 11, 15),
      age: 26,
      items: 5,
      requester: 'Yusuf Ibrahim',
    ),
    _req(
      '12',
      YorksV1MaterialRequestState.awaitingApproval,
      project: 'p3',
      scope: 'Building A',
      age: 3,
      items: 7,
      requester: 'Karthik Raj',
    ),
    _req(
      '11',
      YorksV1MaterialRequestState.received,
      project: 'p3',
      scope: 'Building A',
      code: 'material_request_close_review',
      age: 48,
      items: 9,
    ),
    _req(
      '04',
      YorksV1MaterialRequestState.dispatched,
      project: 'p4',
      scope: 'Level 2',
      code: 'receipt_review_required',
      age: 26,
      items: 4,
    ),
  ],
};

final _exceptions = [
  _req(
    '17',
    YorksV1MaterialRequestState.arranging,
    exceptions: const [YorksV1MaterialRequestExceptionCode.unavailableSupply],
    age: 150,
    canAct: false,
    items: 8,
  ),
  _req(
    '06',
    YorksV1MaterialRequestState.awaitingApproval,
    project: 'p2',
    scope: 'Level 14',
    exceptions: const [
      YorksV1MaterialRequestExceptionCode.partialArrangement,
      YorksV1MaterialRequestExceptionCode.lateExternalSupply,
    ],
    age: 72,
    canAct: false,
  ),
  _req(
    '12',
    YorksV1MaterialRequestState.partiallyReceived,
    scope: 'DF3W',
    exceptions: const [YorksV1MaterialRequestExceptionCode.missingReceipt],
    age: 48,
    canAct: false,
  ),
  _req(
    '09',
    YorksV1MaterialRequestState.partiallyReceived,
    project: 'p3',
    scope: 'Building A',
    exceptions: const [YorksV1MaterialRequestExceptionCode.damagedReceipt],
    age: 96,
    canAct: false,
  ),
];

final _active = [
  _req(
    '05',
    YorksV1MaterialRequestState.arranging,
    project: 'p4',
    scope: 'Level 2',
    title: 'Fume extract fan',
    scheduled: DateTime(2026, 11, 6),
    overdue: true,
    canAct: false,
  ),
  _req(
    '19',
    YorksV1MaterialRequestState.approved,
    scope: 'DF6W',
    title: 'Ventilation fans',
    scheduled: DateTime(2026, 11, 10),
    canAct: false,
  ),
  _req(
    '07',
    YorksV1MaterialRequestState.arranging,
    project: 'p2',
    scope: 'Level 14',
    title: 'Chilled water valves',
    scheduled: DateTime(2026, 11, 12),
    canAct: false,
  ),
  _req(
    '18',
    YorksV1MaterialRequestState.dispatched,
    scope: 'DF3W',
    title: 'Duct accessories',
    age: 2,
  ),
  _req(
    '21',
    YorksV1MaterialRequestState.awaitingRequestApproval,
    title: 'Package units and supports',
    urgent: true,
    age: 50,
    canAct: false,
  ),
  _req(
    '13',
    YorksV1MaterialRequestState.dispatched,
    project: 'p3',
    scope: 'Building A',
    title: 'Insulation',
    age: 110,
    canAct: false,
  ),
];

final _closedItems = [
  _req(
    '11',
    YorksV1MaterialRequestState.closed,
    project: 'p3',
    scope: 'Building A',
    items: 9,
    canAct: false,
  ),
  _req('14', YorksV1MaterialRequestState.closed, items: 22, canAct: false),
];

YorksV1MaterialRequestSummaryPage _page(
  List<YorksV1MaterialRequestSummary> items, {
  bool hasMore = false,
}) => YorksV1MaterialRequestSummaryPage(
  items: items,
  totalCount: hasMore ? items.length + 50 : items.length,
  limit: 100,
  offset: 0,
  hasMore: hasMore,
  metrics: YorksV1MaterialRequestSummaryMetrics(
    total: items.length,
    open: items.length,
    inProgress: 0,
    dispatched: 0,
    received: 0,
    closed: 0,
  ),
);

YorksV1ProjectPortfolioItem _p(
  String id,
  YorksV1ProjectLifecycle state, {
  int pe = 1,
  int buildings = 4,
}) {
  final info = _projectsInfo[id] ?? ('YRA-309', 'Khalifa City Villa Compound');
  return YorksV1ProjectPortfolioItem(
    project: YorksV1Project(
      id: id,
      reference: info.$1,
      name: info.$2,
      state: state,
      version: 1,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: _now.subtract(Duration(days: id.hashCode % 5 + 1)),
      siteLocation: 'Abu Dhabi',
    ),
    activeBuildingCount: buildings,
    activeProjectEngineerCount: pe,
    activeSiteEngineerCount: 2,
  );
}

final _portfolio = [
  _p('p1', YorksV1ProjectLifecycle.active),
  _p('p2', YorksV1ProjectLifecycle.active, buildings: 1),
  _p('p3', YorksV1ProjectLifecycle.active, buildings: 2),
  _p('p4', YorksV1ProjectLifecycle.active, pe: 0, buildings: 1),
  _p('p5', YorksV1ProjectLifecycle.onHold, buildings: 6),
];

YorksV1LogisticsInventoryItem _item(
  String id,
  String description,
  String category,
  String unit,
  String onHand,
  String reserved,
  String available,
  String minimum,
) => YorksV1LogisticsInventoryItem(
  id: id,
  description: description,
  categoryName: category,
  unit: unit,
  minimumStock: minimum,
  isActive: true,
  onHandQuantity: onHand,
  reservedQuantity: reserved,
  availableQuantity: available,
  recordVersion: 1,
);

final _inventory = YorksV1InventoryWorkspace(
  items: [
    _item(
      'i1',
      'Copper pipe 7/8″ ACR',
      'Copper',
      'm',
      '180',
      '160',
      '20',
      '200',
    ),
    _item(
      'i2',
      'Motorized fire damper 600×400',
      'Dampers',
      'Nos',
      '0',
      '0',
      '0',
      '10',
    ),
    _item(
      'i3',
      'Threaded rod M10 × 3 m',
      'Fixings',
      'pcs',
      '900',
      '80',
      '820',
      '300',
    ),
  ],
);

final _drafts = [
  for (final (id, title, days) in [
    ('d1', 'Fire dampers DF6W', 0),
    ('d2', 'Common area consumables', 1),
  ])
    YorksV1PrivateMaterialRequestDraftRecord(
      draftId: id,
      syncVersion: 1,
      clientUpdatedAt: _now.subtract(Duration(days: days, hours: 2)),
      serverUpdatedAt: _now.subtract(Duration(days: days, hours: 2)),
      draft: YorksV1MaterialRequestDraft(
        id: id,
        ownerAuthUserId: 'u1',
        submissionIdempotencyKey: 'k-$id',
        updatedAt: _now,
        title: title,
      ),
    ),
];

Future<void> _loadFonts() async {
  final sans = FontLoader('NexusSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) break;
    directory = directory.parent;
  }
  final icons = await File(
    '${directory.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await Future.wait([sans.load(), materialIcons.load()]);
}

final _rentals = YorksV1RentalPortfolio(
  asOf: _now,
  summary: const YorksV1RentalSummary(
    totalProperties: 8,
    occupied: 7,
    monthlyRentRoll: 95000,
    collectedThisMonth: 88000,
    outstanding: 7000,
    securityDeposits: 120000,
    expiringWithin90: 1,
    chequeAttention: 1,
  ),
  properties: const [],
  recentPayments: const [],
  cheques: const [],
);

final _audit = YorksV1AuditWorkspace(
  generatedAt: _now,
  summary: const YorksV1AuditSummary(
    totalActivities: 214,
    criticalActivities: 1,
    activeUsers: 18,
    entitiesMonitored: 64,
    auditAlerts: 1,
    dataIntegrityPercent: 100,
    currentPeriodActivities: 39,
    previousPeriodActivities: 35,
  ),
  filteredCount: 2,
  limit: 12,
  offset: 0,
  events: [
    YorksV1AuditEvent(
      id: 'audit-1',
      eventType: 'configuration_published',
      entityType: 'configuration',
      entityId: 'config-13',
      module: YorksV1AuditModule.system,
      severity: YorksV1AuditSeverity.warning,
      actorAuthUserId: 'owner',
      actorDisplayName: 'Owner',
      actorExactRole: 'admin',
      occurredAt: _now.subtract(const Duration(hours: 1)),
      reference: 'Configuration v1.3.0',
      facts: const {},
      attributionVerified: true,
    ),
    YorksV1AuditEvent(
      id: 'audit-2',
      eventType: 'configuration_published',
      entityType: 'configuration',
      entityId: 'config-12',
      module: YorksV1AuditModule.system,
      severity: YorksV1AuditSeverity.critical,
      actorAuthUserId: 'sme',
      actorDisplayName: 'Rajesh Nair',
      actorExactRole: 'senior_mechanical_engineer',
      occurredAt: _now.subtract(const Duration(days: 2)),
      reference: 'Configuration v1.2.0',
      facts: const {},
      attributionVerified: true,
    ),
  ],
  topEntities: const [],
  moduleActivity: const [],
  trend: const [],
  quickFilterCounts: const {},
  alerts: const [],
);

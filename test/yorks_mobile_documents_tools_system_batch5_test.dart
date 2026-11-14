import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/engineer/presentation/screens/engineer_profile_screen.dart';
import 'package:material_ledger/features/engineering_tools/presentation/screens/yorks_v1_engineering_calculator_screens.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_documents_screen.dart';
import 'package:material_ledger/shared/models/employee.dart';
import 'package:material_ledger/shared/models/user_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile.dart';
import 'package:material_ledger/shared/models/yorks_v1_my_profile_workspace.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_workspace_status.dart';
import 'package:material_ledger/shared/providers/employee_provider.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/session_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_feature_flags_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_my_profile_workspace_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_workspace_status_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_my_profile_workspace_repository.dart';
import 'package:material_ledger/shared/services/app_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _projectId = 'mobile-batch-five-project';
const _profileActor = '10000000-0000-4000-8000-000000000024';

void main() {
  setUpAll(() async {
    final nexusFontLoader = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabicFontLoader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final flutterCache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([
      nexusFontLoader.load(),
      arabicFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(360, 800)]) {
    final suffix = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('ref40 documents $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpDocuments(tester, _documents);

      expect(find.text('Controlled document register'), findsOneWidget);
      expect(find.text('Nexus BOQ.xlsx'), findsOneWidget);
      await _golden(tester, '40_documents_$suffix');
    });

    testWidgets('ref41 document viewer $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpDocuments(tester, _documents);
      await tester.tap(find.text('Nexus BOQ.xlsx'));
      await tester.pumpAndSettle();

      expect(find.text('Document viewer'), findsOneWidget);
      expect(find.text('Preview is available for PDF files'), findsOneWidget);
      expect(find.text('Download'), findsWidgets);
      await _golden(tester, '41_document_viewer_$suffix');
    });

    testWidgets('ref48 duct sizer $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pump(tester, const YorksV1DuctSizerScreen());

      expect(find.text('Duct sizer'), findsOneWidget);
      expect(find.text('Flow rate'), findsOneWidget);
      await _golden(tester, '48_duct_sizer_$suffix');
    });

    testWidgets('ref49 ESP calculator $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pump(
        tester,
        YorksV1EspCalculatorScreen(initialDate: DateTime.utc(2026, 8, 9)),
      );

      expect(find.text('System components'), findsOneWidget);
      expect(find.text('Add row'), findsOneWidget);
      await _golden(tester, '49_esp_calculator_$suffix');
    });

    testWidgets('ref50 profile and settings $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpProfile(tester);

      expect(find.text('Workspace sync'), findsOneWidget);
      expect(find.text('Preferences'), findsWidgets);
      expect(find.text('Omar Farooq'), findsOneWidget);
      await _golden(tester, '50_profile_settings_$suffix');
    });

    testWidgets('ref51 truthful sync status $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpProfile(
        tester,
        status: const YorksV1WorkspaceStatus(
          state: YorksV1WorkspaceConnectionState.offline,
          pendingChangeCount: 2,
        ),
      );
      await tester.ensureVisible(find.text('Workspace sync'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspace sync'));
      await tester.pumpAndSettle();

      expect(find.text('Sync status'), findsOneWidget);
      expect(find.text('Offline workspace'), findsOneWidget);
      expect(find.text('Conflict handling'), findsOneWidget);
      await _golden(tester, '51_offline_sync_$suffix');
    });

    testWidgets('ref52 real empty state $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpDocuments(tester, const []);

      expect(find.text('No authorized documents yet'), findsOneWidget);
      expect(find.text('Add document'), findsWidgets);
      await _golden(tester, '52_empty_documents_$suffix');
    });
  }

  testWidgets('document scope filters use actual record links', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpDocuments(tester, _documents);

    await tester.tap(find.text('BOQ'));
    await tester.pumpAndSettle();
    expect(find.text('Nexus BOQ.xlsx'), findsOneWidget);
    expect(find.text('Project execution plan.pdf'), findsNothing);

    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery clarification.docx'), findsOneWidget);
    expect(find.text('Nexus BOQ.xlsx'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync panel leaves record conflict resolution on its record', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpProfile(
      tester,
      status: const YorksV1WorkspaceStatus(
        state: YorksV1WorkspaceConnectionState.connected,
      ),
    );
    await tester.ensureVisible(find.text('Workspace sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace sync'));
    await tester.pumpAndSettle();

    expect(find.text('Conflict handling'), findsOneWidget);
    expect(find.textContaining('never silently overwritten'), findsOneWidget);
    expect(find.text('Use server'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDocuments(
  WidgetTester tester,
  List<YorksV1Document> documents,
) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1DocumentWorkspaceProvider(_projectId).overrideWith(
          (ref) async => YorksV1DocumentWorkspace(
            projectId: _projectId,
            documents: documents,
            auditEntries: const [],
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksV1DocumentsScreen(projectId: _projectId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  YorksV1WorkspaceStatus status = const YorksV1WorkspaceStatus(
    state: YorksV1WorkspaceConnectionState.connected,
  ),
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        employeeProvider.overrideWithValue(
          const EmployeeProfile(
            name: 'Omar Farooq',
            title: 'Project Engineer',
            employeeId: 'YR-024',
            email: 'omar@yorks.ae',
            phone: '—',
            department: 'Projects',
            nationality: '—',
            linked: true,
            today: SelfAttendance.present,
            annualUsed: 0,
            annualEntitlement: 24,
            pendingRequests: 0,
          ),
        ),
        currentRoleProvider.overrideWithValue(UserRole.engineer),
        yorksV1AuthUserIdProvider.overrideWithValue(_profileActor),
        yorksV1CurrentRoleProvider.overrideWithValue(
          YorksV1Role.projectEngineer,
        ),
        yorksV1MyProfileRepositoryProvider.overrideWithValue(
          const _ProfileRepository(),
        ),
        yorksV1MyProfileWorkspaceRepositoryProvider.overrideWithValue(
          const _ProfileWorkspaceRepository(),
        ),
        yorksV1WorkspaceStatusProvider.overrideWithValue(status),
        yorksV1FeatureFlagsProvider.overrideWithValue(_features),
        appVersionProvider.overrideWithValue(
          const AppVersionInfo(version: '1.0.0', build: 35),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const EngineerProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Preferences and workspace sync are on the Settings tab.
  final settings = find.byKey(const ValueKey('my-yorks-section-settings'));
  await tester.ensureVisible(settings);
  await tester.pumpAndSettle();
  await tester.tap(settings);
  await tester.pumpAndSettle();
}

class _ProfileRepository implements YorksV1MyProfileRepository {
  const _ProfileRepository();

  @override
  Future<YorksV1MyProfile> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    int projectOffset = 0,
    int projectLimit = 25,
  }) async => YorksV1MyProfile.fromRpcJson({
    'schema_version': 1,
    'generated_at': '2026-09-05T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': 4,
    'account': {
      'auth_user_id': _profileActor,
      'app_user_id': 'usr-omar',
      'display_name': 'Omar Farooq',
      'email': 'omar@yorks.ae',
      'exact_role': YorksV1Role.projectEngineer.claimValue,
      'status': 'active',
      'workspace_key': YorksV1Role.projectEngineer.claimValue,
    },
    'work_identity': {
      'legacy_employee': {'state': 'not_projected'},
      'workforce_worker': {
        'state': 'unlinked',
        'worker_id': null,
        'grants_self_service': false,
      },
    },
    'projects': {
      'total': 0,
      'offset': 0,
      'has_more': false,
      'items': <Object?>[],
    },
    'capabilities': <Object?>[],
    'actions': <Object?>[],
    'operational_summary_state': 'not_projected',
    'workforce_scope_state': 'requires_work_date_context',
  });
}

class _ProfileWorkspaceRepository
    implements YorksV1MyProfileWorkspaceRepository {
  const _ProfileWorkspaceRepository();

  @override
  Future<YorksV1MyProfileWorkspace> load({
    required String expectedAuthUserId,
    required YorksV1Role expectedRole,
    required int expectedPermissionRevision,
  }) async => YorksV1MyProfileWorkspace.fromRpcJson({
    'schema_version': 1,
    'generated_at': '2026-09-05T00:00:00Z',
    'next_transition_at': null,
    'permission_revision': expectedPermissionRevision,
    'account': {
      'auth_user_id': expectedAuthUserId,
      'exact_role': expectedRole.claimValue,
    },
    'today': {'state': 'available', 'metrics': <Object?>[]},
    'access_scope': {
      'technical_project_count': 0,
      'accounts_project_count': 0,
      'active_direct_membership_count': 0,
      'effective_source_kinds': <Object?>[],
      'accounts_portfolio_available': false,
    },
    'work_identity': {
      'legacy_employee': {'state': 'not_projected'},
      'workforce_worker': {
        'state': 'unlinked',
        'worker_id': null,
        'worker_number': null,
        'display_name': null,
        'designation': null,
        'department': null,
        'worker_type': null,
        'current_status': null,
        'grants_self_service': false,
      },
    },
  });
}

const _features = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
);

final _documents = <YorksV1Document>[
  _document(
    id: 'document-project',
    name: 'Project execution plan.pdf',
    mimeType: 'application/pdf',
    classification: YorksV1DocumentClassification.operational,
    links: [
      YorksV1DocumentLink(
        id: 'link-project',
        projectId: _projectId,
        entityType: YorksV1DocumentEntityType.project,
        entityId: _projectId,
        linkedAt: _date,
      ),
    ],
  ),
  _document(
    id: 'document-boq',
    name: 'Nexus BOQ.xlsx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    classification: YorksV1DocumentClassification.operational,
    links: [
      YorksV1DocumentLink(
        id: 'link-boq',
        projectId: _projectId,
        entityType: YorksV1DocumentEntityType.boqGroup,
        entityId: 'boq-group-1',
        linkedAt: _date,
      ),
    ],
  ),
  _document(
    id: 'document-request',
    name: 'Delivery clarification.docx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    classification: YorksV1DocumentClassification.operational,
    links: [
      YorksV1DocumentLink(
        id: 'link-request',
        projectId: _projectId,
        entityType: YorksV1DocumentEntityType.materialRequest,
        entityId: 'mr-101',
        linkedAt: _date,
      ),
    ],
  ),
];

final _date = DateTime(2026, 8, 9, 10, 30);

YorksV1Document _document({
  required String id,
  required String name,
  required String mimeType,
  required YorksV1DocumentClassification classification,
  required List<YorksV1DocumentLink> links,
}) => YorksV1Document(
  id: id,
  classification: classification,
  createdAt: _date,
  links: links,
  currentVersion: YorksV1DocumentVersion(
    id: '$id-version',
    revisionNumber: 2,
    bucketId: 'controlled-documents',
    objectPath: '$id/$name',
    fileName: name,
    mimeType: mimeType,
    byteSize: 248000,
    sha256: 'a' * 64,
    origin: YorksV1DocumentOrigin.uploaded,
    uploadedAt: _date,
    uploadedByAuthUserId: 'user-omar',
    uploadedByRole: 'project_engineer',
    uploadedByDisplayName: 'Omar Farooq',
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 26);
  tester.view.viewPadding = const FakeViewPadding(top: 26);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/mobile_batch5/$name.png'),
  );
  expect(tester.takeException(), isNull);
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

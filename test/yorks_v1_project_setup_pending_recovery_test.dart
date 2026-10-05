import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_setup_pending_recovery.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_project_setup_coordinator.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_project.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_setup_operation.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_setup_journal_store.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _owner = 'original-owner';
const _projectId = 'saved-project';
const _scope = (
  ownerAuthUserId: _owner,
  draftId: 'original-draft',
  projectId: null,
);
const _permissions = {
  YorksV1CapabilityKeys.projectsView,
  YorksV1CapabilityKeys.projectsEdit,
  YorksV1CapabilityKeys.projectsChangeState,
  YorksV1CapabilityKeys.documentsView,
  YorksV1CapabilityKeys.documentsUpload,
};
final _actorProvider = StateProvider<String?>((_) => _owner);

void main() {
  testWidgets(
    'mount restores prior work without replay or changing edit input',
    (tester) async {
      final fixture = _Fixture(activation: true);
      await fixture.pump(tester);
      expect(fixture.commands.calls, isEmpty);
      expect(fixture.documents.inputs, isEmpty);
      expect(fixture.keysGenerated, 0);
      expect(fixture.edit.text, 'Current unsaved edit proposal');
      expect(
        find.byKey(
          const ValueKey('project-setup-pending-activate-original-draft'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('project-setup-pending-file-original-file')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit activation check sends original key and payload', (
    tester,
  ) async {
    final fixture = _Fixture(activation: true);
    final original = fixture.operation.activation!;
    await fixture.pump(tester);
    await tester.tap(
      find.byKey(
        const ValueKey('project-setup-pending-activate-original-draft'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.commands.calls, hasLength(1));
    expect(
      fixture.commands.calls.single.idempotencyKey,
      original.idempotencyKey,
    );
    expect(
      fixture.commands.calls.single.canonicalPayload,
      original.canonicalPayload,
    );
    expect(fixture.keysGenerated, 0);
    expect(
      fixture.coordinator.currentState.project!.state,
      YorksV1ProjectLifecycle.active,
    );
    expect(fixture.edit.text, 'Current unsaved edit proposal');
    expect(fixture.documents.inputs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-name different content is rejected before uploading', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.picker.selected = YorksV1SelectedDocument(
      fileName: 'original.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([9, 8, 7]),
    );
    await fixture.pump(tester);
    await tester.tap(
      find.byKey(
        const ValueKey('project-setup-pending-reselect-original-file'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.documents.inputs, isEmpty);
    expect(fixture.commands.calls, isEmpty);
    expect(
      fixture.coordinator.currentState.operation!.files.single.status,
      YorksV1ProjectSetupFileStatus.needsReselect,
    );
    expect(
      find.text(YorksV1ProjectStrings.fileContentMismatch.primary),
      findsOneWidget,
    );
    expect(fixture.edit.text, 'Current unsaved edit proposal');
  });

  testWidgets(
    'exact original file resumes original upload and preserves edit',
    (tester) async {
      final fixture = _Fixture();
      fixture.picker.selected = fixture.originalFile;
      await fixture.pump(tester);
      await tester.tap(
        find.byKey(
          const ValueKey('project-setup-pending-reselect-original-file'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.documents.inputs, hasLength(1));
      final upload = fixture.documents.inputs.single;
      expect(upload.idempotencyKey, 'original-upload-key');
      expect(upload.projectId, _projectId);
      expect(upload.classification, YorksV1DocumentClassification.operational);
      expect(upload.bytes, fixture.originalFile.bytes);
      expect(
        fixture.coordinator.currentState.operation!.files.single.status,
        YorksV1ProjectSetupFileStatus.ready,
      );
      expect(
        fixture.coordinator.currentState.operation!.cleanupComplete,
        isTrue,
      );
      expect(fixture.edit.text, 'Current unsaved edit proposal');
      expect(fixture.keysGenerated, 0);
      expect(fixture.commands.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'never-dispatched file removal writes original manifest tombstone',
    (tester) async {
      final fixture = _Fixture();
      await fixture.pump(tester);
      await tester.tap(
        find.byKey(
          const ValueKey('project-setup-pending-remove-original-file'),
        ),
      );
      await tester.pumpAndSettle();
      final file = fixture.coordinator.currentState.operation!.files.single;
      expect(file.status, YorksV1ProjectSetupFileStatus.removed);
      expect(file.idempotencyKey, 'original-upload-key');
      expect(
        file.contentHash,
        sha256.convert(fixture.originalFile.bytes).toString(),
      );
      expect(fixture.documents.inputs, isEmpty);
      expect(fixture.edit.text, 'Current unsaved edit proposal');
      expect(fixture.keysGenerated, 0);
    },
  );

  testWidgets('uncertain upload has reselection but no removal action', (
    tester,
  ) async {
    final fixture = _Fixture(
      fileStatus: YorksV1ProjectSetupFileStatus.outcomeUncertain,
    );
    await fixture.pump(tester);
    expect(
      find.byKey(
        const ValueKey('project-setup-pending-reselect-original-file'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-setup-pending-remove-original-file')),
      findsNothing,
    );
    expect(fixture.documents.inputs, isEmpty);
  });

  for (final role in [YorksV1Role.procurement, YorksV1Role.accountant]) {
    testWidgets(
      '${role.name} cannot see or replay engineering setup recovery',
      (tester) async {
        final fixture = _Fixture(activation: true);
        await fixture.pump(tester, role: role);
        expect(
          find.byKey(const ValueKey('project-setup-pending-recovery')),
          findsNothing,
        );
        expect(find.text('original.pdf'), findsNothing);
        expect(fixture.commands.calls, isEmpty);
        expect(fixture.documents.inputs, isEmpty);
      },
    );
  }

  testWidgets('stale permissions disable all recovery actions', (tester) async {
    final fixture = _Fixture(activation: true);
    await fixture.pump(tester, stale: true);
    for (final element in find.byType(OutlinedButton).evaluate()) {
      expect((element.widget as OutlinedButton).onPressed, isNull);
    }
    expect(fixture.commands.calls, isEmpty);
    expect(fixture.documents.inputs, isEmpty);
  });

  testWidgets('denied file access hides manifest names and upload controls', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pump(
      tester,
      capabilities: {
        YorksV1CapabilityKeys.projectsView,
        YorksV1CapabilityKeys.projectsEdit,
      },
    );
    expect(find.text('original.pdf'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('project-setup-pending-reselect-original-file'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'owner switch while picker is open cannot upload prior-owner file',
    (tester) async {
      final fixture = _Fixture();
      fixture.picker.pending = Completer<YorksV1SelectedDocument?>();
      final container = await fixture.pump(tester);
      await tester.tap(
        find.byKey(
          const ValueKey('project-setup-pending-reselect-original-file'),
        ),
      );
      await tester.pump();
      container.read(_actorProvider.notifier).state = 'another-owner';
      await tester.pump();
      fixture.picker.pending!.complete(fixture.originalFile);
      await tester.pumpAndSettle();
      expect(fixture.documents.inputs, isEmpty);
      expect(fixture.commands.calls, isEmpty);
      expect(fixture.edit.text, 'Current unsaved edit proposal');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone RTL large text preserves labels and 44px actions', (
    tester,
  ) async {
    final fixture = _Fixture(activation: true);
    await fixture.pump(tester, width: 360, scale: 2, rtl: true);
    for (final element in find.byType(OutlinedButton).evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(find.text('original.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture({
    bool activation = false,
    YorksV1ProjectSetupFileStatus fileStatus =
        YorksV1ProjectSetupFileStatus.needsReselect,
  }) {
    operation = YorksV1ProjectSetupOperation(
      backendIdentity: 'test-backend',
      ownerAuthUserId: _owner,
      draftId: _scope.draftId,
      mode: YorksV1ProjectSetupMode.create,
      core: YorksV1ProjectSetupCommand(
        kind: YorksV1ProjectSetupCommandKind.create,
        idempotencyKey: 'original-create-key',
        payload: {
          'project_ref': 'YRA-01',
          'name': 'Saved',
          'buildings': [],
          'attachments': [],
        },
        status: YorksV1ProjectSetupCommandStatus.confirmedSuccess,
        result: {'project': _projectJson('draft')},
      ),
      activation: activation
          ? YorksV1ProjectSetupCommand(
              kind: YorksV1ProjectSetupCommandKind.activate,
              idempotencyKey: 'original-activation-key',
              payload: {
                'project_id': _projectId,
                'state': 'active',
                'expected_version': 1,
              },
              status: YorksV1ProjectSetupCommandStatus.outcomeUncertain,
              attempts: 1,
              nextRetryAt: DateTime.utc(2026, 1, 1),
            )
          : null,
      files: [
        YorksV1ProjectSetupFile(
          localId: 'original-file',
          idempotencyKey: 'original-upload-key',
          fileName: originalFile.fileName,
          mimeType: originalFile.mimeType,
          sizeBytes: originalFile.bytes.length,
          contentHash: sha256.convert(originalFile.bytes).toString(),
          classification: YorksV1DocumentClassification.operational,
          status: fileStatus,
        ),
      ],
    );
    storage.values['scope:journal:${_scope.draftId}'] = jsonEncode(
      operation.toJson(),
    );
    coordinator = YorksV1ProjectSetupCoordinator(
      store: YorksV1ProjectSetupJournalStore(
        storage: storage,
        journalKey: 'scope:journal:${_scope.draftId}',
        backendIdentity: 'test-backend',
        ownerAuthUserId: _owner,
        draftId: _scope.draftId,
        atomicOwned: <T>(work) => storage.transaction('scope', work),
      ),
      repository: commands,
      keyFactory: () => 'unexpected-new-key-${++keysGenerated}',
      retryDelay: (_) async {},
    );
  }

  final originalFile = YorksV1SelectedDocument(
    fileName: 'original.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  final storage = _Storage();
  final commands = _Commands();
  final documents = _Documents();
  final picker = _Picker();
  final edit = TextEditingController(text: 'Current unsaved edit proposal');
  late YorksV1ProjectSetupOperation operation;
  late YorksV1ProjectSetupCoordinator coordinator;
  int keysGenerated = 0;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    YorksV1Role role = YorksV1Role.admin,
    Set<String> capabilities = _permissions,
    bool stale = false,
    double width = 800,
    double scale = 1,
    bool rtl = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'selected_language':
          (rtl ? AppLanguage.arabic : AppLanguage.english).code,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          yorksV1AuthUserIdProvider.overrideWith(
            (ref) => ref.watch(_actorProvider),
          ),
          yorksV1CurrentRoleProvider.overrideWithValue(role),
          yorksV1CurrentPermissionSnapshotProvider.overrideWith(
            (_) => YorksV1TestPermissionController(
              yorksV1TrustedFeaturePermissionState(
                role: role,
                capabilities: capabilities,
                stale: stale,
              ),
            ),
          ),
          yorksV1ProjectSetupPendingOperationsProvider.overrideWith(
            (ref, context) => context.ownerAuthUserId == _owner
                ? [(scope: _scope, operation: operation)]
                : [],
          ),
          yorksV1ProjectSetupCoordinatorProvider.overrideWith(
            (_, _) => coordinator,
          ),
          yorksV1DocumentsRepositoryProvider.overrideWithValue(documents),
          yorksV1DocumentFileServiceProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(controller: edit),
                      YorksV1ProjectSetupPendingRecovery(
                        project: operation.core.project!,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }
}

Map<String, dynamic> _projectJson(String state) => {
  'id': _projectId,
  'project_ref': 'YRA-01',
  'name': 'Saved',
  'state': state,
  'record_version': state == 'active' ? 2 : 1,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

class _Commands implements YorksV1ProjectReviewedCommandRepository {
  final calls = <YorksV1ProjectSetupCommand>[];
  @override
  Future<Map<String, dynamic>> executeReviewedCommand(
    YorksV1ProjectSetupCommand command,
  ) async {
    calls.add(command);
    return {'project': _projectJson('active')};
  }
}

class _Documents implements YorksV1DocumentsRepository {
  final inputs = <YorksV1DocumentUploadInput>[];
  @override
  Future<YorksV1DocumentWorkspace> upload(
    YorksV1DocumentUploadInput input,
  ) async {
    inputs.add(input);
    return const YorksV1DocumentWorkspace(
      projectId: _projectId,
      documents: [],
      auditEntries: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker implements YorksV1DocumentFileService {
  YorksV1SelectedDocument? selected;
  Completer<YorksV1SelectedDocument?>? pending;
  @override
  Future<YorksV1SelectedDocument?> selectDocument() async =>
      pending != null ? pending!.future : selected;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage
    implements ProjectDraftAtomicStorage, ProjectDraftAtomicTransaction {
  final values = <String, String>{};
  @override
  bool get supportsAtomicOwnership => true;
  @override
  String? read(String key) => values[key];
  @override
  void remove(String key) => values.remove(key);
  @override
  void write(String key, String value) => values[key] = value;
  @override
  Future<T> transaction<T>(
    String lockKey,
    T Function(ProjectDraftAtomicTransaction) work,
  ) async => work(this);
}

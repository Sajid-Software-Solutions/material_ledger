import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/app/yorks_localizations.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/accounts/application/accounts_controller.dart';
import 'package:material_ledger/features/accounts/application/accounts_providers.dart';
import 'package:material_ledger/features/accounts/data/accounts_evidence_repository.dart';
import 'package:material_ledger/features/accounts/data/accounts_repository.dart';
import 'package:material_ledger/features/accounts/domain/accounts_decimal.dart';
import 'package:material_ledger/features/accounts/domain/accounts_evidence_models.dart';
import 'package:material_ledger/features/accounts/domain/accounts_inputs.dart';
import 'package:material_ledger/features/accounts/domain/accounts_models.dart';
import 'package:material_ledger/features/accounts/presentation/widgets/yorks_accounts_progress_action_sheet.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final iconBytes = await File(
      '${_flutterCacheDirectory().path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([font.load(), arabic.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'repository rejects mismatched project and excessive search results',
    () async {
      final rpc = _EvidenceRpc()..responseProject = 'different-project';
      final repository = YorksSupabaseAccountsEvidenceRepository(
        rpcClient: rpc,
        documentsRepository: _Documents(),
      );
      await expectLater(
        repository.search(projectId: 'project-1'),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.unexpectedResponse,
          ),
        ),
      );
    },
  );

  test('preview checks current revision before any Storage read', () async {
    final rpc = _EvidenceRpc()..currentVersion = 'new-version';
    final documents = _Documents();
    final repository = YorksSupabaseAccountsEvidenceRepository(
      rpcClient: rpc,
      documentsRepository: documents,
    );
    await expectLater(
      repository.preview(projectId: 'project-1', document: _document),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.conflict,
        ),
      ),
    );
    expect(documents.downloads, 0);
  });

  test(
    'authorized current evidence preview uses the controlled Storage read',
    () async {
      final documents = _Documents();
      final repository = YorksSupabaseAccountsEvidenceRepository(
        rpcClient: _EvidenceRpc(),
        documentsRepository: documents,
      );
      final bytes = await repository.preview(
        projectId: 'project-1',
        document: _document,
      );
      expect(bytes, isEmpty);
      expect(documents.downloads, 1);
    },
  );

  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('selected evidence and reason remain reachable at $size', (
      tester,
    ) async {
      final fixture = await _pumpSheet(tester, size);
      await tester.pumpAndSettle();
      expect(find.text('Search project documents'), findsOneWidget);
      expect(find.text('No eligible project documents found'), findsNothing);
      expect(find.text('Site photo.pdf'), findsOneWidget);
      expect(find.text('Evidence document IDs'), findsNothing);
      expect(find.text('Confirmed progress: 40%'), findsOneWidget);
      expect(fixture.commandRepository.suggestions, isEmpty);

      await tester.ensureVisible(find.byTooltip('Select evidence').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select evidence').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Current revision 1'), findsWidgets);
      expect(find.byTooltip('Preview evidence'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(find.byType(TextFormField).last, 'Site check');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Suggest progress').last);
      await tester.tap(find.text('Suggest progress').last);
      await tester.pumpAndSettle();
      expect(fixture.commandRepository.suggestions, hasLength(1));
      expect(
        fixture.commandRepository.suggestions.single.percent.canonicalText,
        '55',
      );
      expect(fixture.commandRepository.suggestions.single.evidenceDocumentIds, [
        'document-1',
      ]);
      expect(find.text('Search project documents'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('newly inaccessible evidence is not submitted', (tester) async {
    final fixture = await _pumpSheet(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, 'Site check');
    fixture.evidence.available = false;
    await tester.ensureVisible(find.text('Suggest progress').last);
    await tester.tap(find.text('Suggest progress').last);
    await tester.pumpAndSettle();
    expect(fixture.commandRepository.suggestions, isEmpty);
    expect(find.textContaining('Selected evidence changed'), findsOneWidget);
  });

  testWidgets('a suggestion needs summary or selected evidence', (
    tester,
  ) async {
    final fixture = await _pumpSheet(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, 'Site check');
    await tester.ensureVisible(find.text('Suggest progress').last);
    await tester.tap(find.text('Suggest progress').last);
    await tester.pumpAndSettle();
    expect(fixture.commandRepository.suggestions, isEmpty);
    expect(find.textContaining('Add a site evidence summary'), findsOneWidget);
  });

  testWidgets(
    'summary-only suggestion survives optional document search failure',
    (tester) async {
      final fixture = await _pumpSheet(tester, const Size(390, 844));
      fixture.evidence.failSearch = true;
      final search = find.widgetWithText(TextField, 'Search project documents');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'site');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).at(1));
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Site inspection',
      );
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(find.byType(TextFormField).last, 'Site check');
      await tester.ensureVisible(find.text('Suggest progress').last);
      await tester.tap(find.text('Suggest progress').last);
      await tester.pumpAndSettle();
      expect(fixture.commandRepository.suggestions, hasLength(1));
      expect(
        fixture.commandRepository.suggestions.single.evidenceDocumentIds,
        isEmpty,
      );
    },
  );

  testWidgets('a newer document revision requires an explicit reselection', (
    tester,
  ) async {
    final fixture = await _pumpSheet(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, 'Site check');
    fixture.evidence.revision = 2;
    await tester.ensureVisible(find.text('Suggest progress').last);
    await tester.tap(find.text('Suggest progress').last);
    await tester.pumpAndSettle();
    expect(fixture.commandRepository.suggestions, isEmpty);
    expect(find.textContaining('Selected evidence changed'), findsOneWidget);
  });

  testWidgets('competing edit preserves proposal until an explicit retry', (
    tester,
  ) async {
    final fixture = await _pumpSheet(tester, const Size(390, 844));
    fixture.commandRepository.conflictFirstSuggest = true;
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, 'Site check');
    await tester.ensureVisible(find.text('Suggest progress').last);
    await tester.tap(find.text('Suggest progress').last);
    await tester.pumpAndSettle();
    expect(fixture.commandRepository.suggestions, isEmpty);
    expect(find.textContaining('This record changed'), findsOneWidget);
    expect(find.textContaining('Current record version 2'), findsOneWidget);
    expect(find.text('Site check'), findsWidgets);
    await tester.tap(find.text('Suggest progress').last);
    await tester.pumpAndSettle();
    expect(fixture.commandRepository.suggestions, hasLength(1));
    expect(fixture.commandRepository.suggestions.single.expectedVersion, 2);
  });

  testWidgets('desktop evidence sheet renders a stable actual Flutter frame', (
    tester,
  ) async {
    await _pumpSheet(tester, const Size(1366, 768));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('goldens/accounts_progress_evidence_desktop.png'),
    );
  });

  testWidgets('phone evidence sheet remains legible after selection', (
    tester,
  ) async {
    await _pumpSheet(tester, const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select evidence').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -85),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('goldens/accounts_progress_evidence_phone.png'),
    );
  });

  testWidgets(
    'phone displays inaccessible evidence recovery without overflow',
    (tester) async {
      final fixture = await _pumpSheet(tester, const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Select evidence').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select evidence').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(find.byType(TextFormField).last, 'Site check');
      fixture.evidence.available = false;
      await tester.ensureVisible(find.text('Suggest progress').last);
      await tester.tap(find.text('Suggest progress').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.textContaining('Selected evidence changed'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Overlay).first,
        matchesGoldenFile('goldens/accounts_progress_evidence_error_phone.png'),
      );
    },
  );

  testWidgets('360px Arabic RTL keeps the keyboard action reachable', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      const Size(360, 800),
      language: AppLanguage.arabic,
    );
    await tester.pumpAndSettle();
    expect(find.text('ابحث في مستندات المشروع'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('اقتراح التقدم').last);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('goldens/accounts_progress_evidence_rtl_phone.png'),
    );
  });
}

const _document = YorksAccountsEvidenceDocument(
  id: 'document-1',
  fileName: 'Site photo.pdf',
  currentVersionId: 'version-1',
  revisionNumber: 1,
  mimeType: 'application/pdf',
  bucketId: 'yorks-documents',
  objectPath: 'test/site-photo.pdf',
);

class _EvidenceRpc extends Fake implements YorksAccountsRpcClient {
  String responseProject = 'project-1';
  String currentVersion = 'version-1';

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async => {
    'project_id': responseProject,
    'documents': <Object?>[],
    'selected': [
      {
        'id': _document.id,
        'file_name': _document.fileName,
        'current_version_id': currentVersion,
        'revision_number': 1,
        'mime_type': _document.mimeType,
        'bucket_id': _document.bucketId,
        'object_path': _document.objectPath,
      },
    ],
    'has_more': false,
  };
}

class _Documents extends Fake implements YorksV1DocumentsRepository {
  int downloads = 0;

  @override
  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  }) async {
    downloads++;
    return Uint8List(0);
  }
}

class _Evidence extends Fake implements YorksAccountsEvidenceRepository {
  bool available = true;
  bool failSearch = false;
  int revision = 1;

  @override
  Future<YorksAccountsEvidenceSearch> search({
    required String projectId,
    String? query,
    List<String> selectedDocumentIds = const [],
  }) async {
    if (failSearch) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    return YorksAccountsEvidenceSearch(
      projectId: projectId,
      documents: available ? [_currentDocument] : const [],
      selected: available && selectedDocumentIds.contains(_document.id)
          ? [_currentDocument]
          : const [],
      hasMore: false,
    );
  }

  YorksAccountsEvidenceDocument get _currentDocument =>
      YorksAccountsEvidenceDocument(
        id: _document.id,
        fileName: _document.fileName,
        currentVersionId: revision == 1 ? 'version-1' : 'version-$revision',
        revisionNumber: revision,
        mimeType: _document.mimeType,
        bucketId: _document.bucketId,
        objectPath: _document.objectPath,
      );
}

class _CommandRepository extends Fake implements YorksAccountsRepository {
  final suggestions = <YorksAccountsProgressInput>[];
  bool conflictFirstSuggest = false;
  int _version = 1;

  @override
  Future<YorksAccountsBaselineProjection> getBaseline(String projectId) async =>
      _baseline;

  @override
  Future<YorksAccountsProgressProjection> listProgress(
    String projectId, {
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async => _version == 1 ? _progress : _progressAtVersion(_version);

  @override
  Future<YorksAccountsCommandResult> suggestProgress(
    YorksAccountsProgressInput input, {
    required String idempotencyKey,
  }) async {
    if (conflictFirstSuggest && _version == 1) {
      _version = 2;
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    suggestions.add(input);
    return const YorksAccountsCommandResult(
      replayed: false,
      projectId: 'project-1',
      entityId: 'progress-1',
      baselineRevisionNumber: 1,
      recordVersion: 2,
      status: 'suggested',
      updatedAt: null,
    );
  }
}

YorksAccountsProgressProjection _progressAtVersion(int version) {
  final entry = _progress.progress.single;
  return YorksAccountsProgressProjection(
    schemaVersion: _progress.schemaVersion,
    projectId: _progress.projectId,
    baselineRevisionId: _progress.baselineRevisionId,
    baselineRevisionNumber: _progress.baselineRevisionNumber,
    progress: [
      YorksAccountsProgressEntry(
        progressEntryId: entry.progressEntryId,
        projectId: entry.projectId,
        baselineRevisionId: entry.baselineRevisionId,
        buildingScopeId: entry.buildingScopeId,
        buildingName: entry.buildingName,
        stageKey: entry.stageKey,
        stageLabel: entry.stageLabel,
        stagePosition: entry.stagePosition,
        recordVersion: version,
        suggestedPercent: entry.suggestedPercent,
        confirmedPercent: entry.confirmedPercent,
        reviewStatus: entry.reviewStatus,
        evidenceSummary: entry.evidenceSummary,
        evidenceDocumentIds: entry.evidenceDocumentIds,
        actionOwner: entry.actionOwner,
        stageValue: entry.stageValue,
        confirmedEligible: entry.confirmedEligible,
        previouslyClaimedAmount: entry.previouslyClaimedAmount,
        availableToClaim: entry.availableToClaim,
        revisions: entry.revisions,
        nextActions: entry.nextActions,
        updatedAt: entry.updatedAt,
      ),
    ],
    totals: _progress.totals,
    capabilities: _progress.capabilities,
    commands: _progress.commands,
    nextActions: _progress.nextActions,
  );
}

Future<({_Evidence evidence, _CommandRepository commandRepository})> _pumpSheet(
  WidgetTester tester,
  Size size, {
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final evidence = _Evidence();
  final commandRepository = _CommandRepository();
  final controller = YorksAccountsProjectController(
    projectId: 'project-1',
    repository: commandRepository,
    commandKeys: YorksV1CriticalCommandKeyStore(
      preferences: await SharedPreferences.getInstance(),
      actorAuthUserId: 'actor-1',
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        yorksAccountsProjectControllerProvider(
          'project-1',
        ).overrideWith((ref) => controller),
        yorksAccountsEvidenceRepositoryProvider.overrideWithValue(evidence),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: language == AppLanguage.arabic
            ? const Locale('ar')
            : const Locale('en'),
        supportedLocales: yorksSupportedLocales,
        localizationsDelegates: yorksLocalizationDelegates,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showYorksAccountsProgressActionSheet(
                context,
                projectId: 'project-1',
                projectReference: 'TEST-ONLY',
                entry: _progress.progress.single,
                projection: _progress,
                language: language,
              ),
              child: const Text('Open fixture'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open fixture'));
  await tester.pumpAndSettle();
  return (evidence: evidence, commandRepository: commandRepository);
}

const _capabilities = YorksAccountsCapabilities(
  canView: true,
  canViewValues: false,
  canConfigure: false,
  canSuggest: true,
  canConfirm: false,
  canReview: false,
);

final _commands = YorksAccountsCommandAvailability.fromRpcJson({
  'suggest_progress': true,
});

final _baseline = YorksAccountsBaselineProjection(
  schemaVersion: 2,
  projectId: 'project-1',
  baseline: const YorksAccountsBaselineRevision(
    revisionId: 'baseline-1',
    revisionNumber: 1,
    recordVersion: 1,
    status: 'current',
    contractValue: null,
    currencyCode: null,
    vatRate: null,
    paymentTermsDays: null,
    reminderLeadDays: null,
    reason: null,
    createdAt: null,
    createdBy: null,
    managementReviewPolicy: null,
  ),
  physicalBuildings: const [],
  stageTemplates: const [],
  buildingAllocations: const [],
  stageAllocations: const [],
  capabilities: _capabilities,
  commands: _commands,
);

final _progress = YorksAccountsProgressProjection(
  schemaVersion: 2,
  projectId: 'project-1',
  baselineRevisionId: 'baseline-1',
  baselineRevisionNumber: 1,
  progress: [
    YorksAccountsProgressEntry(
      progressEntryId: 'progress-1',
      projectId: 'project-1',
      baselineRevisionId: 'baseline-1',
      buildingScopeId: 'building-1',
      buildingName: 'DF3W',
      stageKey: 'material_supply',
      stageLabel: 'Material Supply',
      stagePosition: 2,
      recordVersion: 1,
      suggestedPercent: YorksAccountsDecimal.parse('55'),
      confirmedPercent: YorksAccountsDecimal.parse('40'),
      reviewStatus: YorksAccountsReviewStatus.notRequired,
      evidenceSummary: null,
      evidenceDocumentIds: const [],
      actionOwner: 'site_engineer',
      stageValue: null,
      confirmedEligible: null,
      previouslyClaimedAmount: null,
      availableToClaim: null,
      revisions: const [],
      nextActions: const [
        YorksAccountsNextAction(
          code: 'suggest_progress',
          entityId: 'progress-1',
          ownerRole: 'site_engineer',
          blockingReasonCode: null,
          isAvailable: true,
        ),
      ],
      updatedAt: null,
    ),
  ],
  totals: null,
  capabilities: _capabilities,
  commands: _commands,
  nextActions: const [],
);

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

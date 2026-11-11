import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_documents_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_document_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_document_file_service_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_file_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_upload_journal.dart';

void main() {
  setUpAll(() async {
    final nexus = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    var cache = File(Platform.resolvedExecutable).parent;
    for (
      var i = 0;
      i < 8 && !cache.path.endsWith('${Platform.pathSeparator}cache');
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
    await Future.wait([nexus.load(), arabic.load(), icons.load()]);
  });
  for (final size in [const Size(1366, 900), const Size(360, 800)]) {
    testWidgets('upload status and safe reselect at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final journal = YorksV1DocumentUploadJournal(
        storage: createProjectDraftAtomicStorage(preferences),
        backend: 'local',
        owner: 'actor',
      );
      final input = YorksV1DocumentUploadInput(
        projectId: 'project',
        entityType: YorksV1DocumentEntityType.project,
        entityId: 'project',
        classification: YorksV1DocumentClassification.operational,
        fileName: 'Project ventilation drawings.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List(10 * 1024 * 1024),
        idempotencyKey: 'original-key',
      );
      await journal.acquire(
        input: input,
        operation: 'v1_prepare_document_upload',
        contentHash: sha256.convert(input.bytes).toString(),
        payload: input.toRpcPayload(sha256.convert(input.bytes).toString()),
      );
      final repository = _Repository();
      final picker = _Picker(
        YorksV1SelectedDocument(
          fileName: input.fileName,
          mimeType: input.mimeType,
          bytes: input.bytes,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            yorksV1AuthUserIdProvider.overrideWithValue('actor'),
            yorksV1CurrentRoleProvider.overrideWithValue(
              YorksV1Role.projectEngineer,
            ),
            yorksV1DocumentUploadJournalProvider.overrideWithValue(journal),
            yorksV1DocumentsRepositoryProvider.overrideWithValue(repository),
            yorksV1DocumentFileServiceProvider.overrideWithValue(picker),
            yorksV1DocumentWorkspaceProvider(
              'project',
            ).overrideWith((ref) async => _workspace),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1DocumentsScreen(projectId: 'project'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1DocumentStrings.uploadOutcomeUnknown.primary),
        findsOneWidget,
      );
      expect(find.textContaining('10.0 MB'), findsOneWidget);
      await tester.tap(
        find.text(YorksV1DocumentStrings.reselectUpload.primary),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.inputs.single.idempotencyKey, 'original-key');
      expect(
        find.text(YorksV1DocumentStrings.uploadInProgress.primary),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/p0_upload/upload_${size.width.toInt()}.png'),
      );
      repository.completion.complete(_workspace);
      await tester.pumpAndSettle();
      expect(
        find.text(YorksV1DocumentStrings.uploadSucceeded.primary),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

const _workspace = YorksV1DocumentWorkspace(
  projectId: 'project',
  documents: [],
  auditEntries: [],
);

class _Repository implements YorksV1DocumentsRepository {
  final completion = Completer<YorksV1DocumentWorkspace>();
  final inputs = <YorksV1DocumentUploadInput>[];
  @override
  Future<YorksV1DocumentWorkspace> upload(YorksV1DocumentUploadInput input) {
    inputs.add(input);
    return completion.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker implements YorksV1DocumentFileService {
  _Picker(this.selected);
  final YorksV1SelectedDocument selected;
  @override
  Future<YorksV1SelectedDocument?> selectDocument() async => selected;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

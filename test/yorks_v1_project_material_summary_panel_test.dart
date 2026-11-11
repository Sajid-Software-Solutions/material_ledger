import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/features/projects/presentation/widgets/yorks_v1_project_material_summary_panel.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_material_summary.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_workbook_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_material_summary_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop shows overall, monthly and weekly summaries together', (
    tester,
  ) async {
    final repository = _SummaryRepository();
    await _pump(tester, repository: repository, size: const Size(1366, 900));

    expect(find.byKey(const ValueKey('material-summary-overall')), findsOne);
    expect(
      find.byKey(const ValueKey('material-summary-month-section')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('material-summary-week-section')),
      findsOne,
    );
    // Different spellings stay separate rows; nothing is merged.
    expect(find.text('Aluminium Tape'), findsWidgets);
    expect(find.text('Aluminium Tap'), findsWidgets);
    expect(find.text('November 2026'), findsOne);
    expect(find.text('Mon 2 Nov – Sun 8 Nov 2026'), findsOne);
    // The latest month and week open by default.
    expect(find.text('Share of item total'), findsNWidgets(2));
    expect(repository.queries.single.projectId, 'project-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Material Request numbers open the request', (tester) async {
    await _pump(
      tester,
      repository: _SummaryRepository(),
      size: const Size(1366, 900),
    );
    await tester.tap(
      find.byKey(const ValueKey('material-summary-request-request-3')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Opened request-3'), findsOne);
  });

  testWidgets('search is debounced and sent to the server', (tester) async {
    final repository = _SummaryRepository();
    await _pump(tester, repository: repository, size: const Size(1366, 900));

    await tester.enterText(
      find.byKey(const ValueKey('material-summary-search')),
      'aluminum',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const ValueKey('material-summary-search')),
      'aluminum tape',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.queries.map((query) => query.normalizedSearch), [
      null,
      'aluminum tape',
    ]);
    expect(
      find.byKey(const ValueKey('material-summary-clear-filters')),
      findsOne,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-summary-clear-filters')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-summary-clear-filters')),
      findsNothing,
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('material-summary-search')),
    );
    expect(field.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('building filter limits the summary to one scope', (
    tester,
  ) async {
    final repository = _SummaryRepository();
    await _pump(tester, repository: repository, size: const Size(1366, 900));

    await tester.tap(find.byKey(const ValueKey('material-summary-building')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Building A').last);
    await tester.pumpAndSettle();

    expect(repository.queries.last.scopeId, 'scope-a');
  });

  testWidgets('period presets send Gulf calendar dates', (tester) async {
    final repository = _SummaryRepository();
    await _pump(tester, repository: repository, size: const Size(1366, 900));

    await tester.tap(find.byKey(const ValueKey('material-summary-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month').last);
    await tester.pumpAndSettle();

    final query = repository.queries.last;
    final today = yorksV1GulfToday();
    expect(query.from, DateTime.utc(today.year, today.month));
    expect(query.to, today);
  });

  testWidgets('Register switch keeps the existing movement register', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _SummaryRepository(),
      size: const Size(1366, 900),
    );
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(find.text('REGISTER CONTENT'), findsOne);
    expect(
      find.byKey(const ValueKey('material-summary-overall')),
      findsNothing,
    );

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-summary-overall')), findsOne);
  });

  testWidgets('360px phone layout renders cards without overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _SummaryRepository(),
      size: const Size(360, 800),
    );
    expect(find.byKey(const ValueKey('material-summary-card-1')), findsWidgets);
    expect(find.byKey(const ValueKey('material-summary-row-1')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('material-summary-week-section')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic secondary language renders the summary', (tester) async {
    await _pump(
      tester,
      repository: _SummaryRepository(),
      size: const Size(390, 844),
      language: AppLanguage.arabic,
    );
    expect(find.text('الملخص'), findsOne);
    expect(find.text('الإجمالي'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty project explains that no request was submitted', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _SummaryRepository(empty: true),
      size: const Size(1366, 900),
    );
    expect(
      find.text(
        'No Material Requests have been submitted for this project yet.',
      ),
      findsOne,
    );
    final excel = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const ValueKey('material-summary-export-excel')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(excel.onPressed, isNull);
  });

  testWidgets('denied access never offers a retry', (tester) async {
    await _pump(
      tester,
      repository: _SummaryRepository(
        error: const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthorized,
        ),
      ),
      size: const Size(1366, 900),
    );
    expect(
      find.text('You do not have access to this project’s Material Summary.'),
      findsOne,
    );
    expect(find.byKey(const ValueKey('material-summary-retry')), findsNothing);
  });

  testWidgets('backend failure offers a retry that refetches', (tester) async {
    final repository = _SummaryRepository(
      error: const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      ),
    );
    await _pump(tester, repository: repository, size: const Size(1366, 900));
    expect(find.byKey(const ValueKey('material-summary-retry')), findsOne);

    repository.error = null;
    await tester.tap(find.byKey(const ValueKey('material-summary-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-summary-overall')), findsOne);
    expect(repository.queries.length, 2);
  });

  testWidgets('Export Excel saves the filtered workbook', (tester) async {
    final files = _WorkbookFiles();
    await _pump(
      tester,
      repository: _SummaryRepository(),
      size: const Size(1366, 900),
      files: files,
    );
    await tester.tap(
      find.byKey(const ValueKey('material-summary-export-excel')),
    );
    await tester.pumpAndSettle();

    expect(files.savedName, startsWith('YRA-322_material_summary_'));
    expect(files.savedName, endsWith('.xlsx'));
    // XLSX is a ZIP package.
    expect(files.savedBytes!.sublist(0, 2), [0x50, 0x4B]);
    expect(find.text('Export saved'), findsOne);
    await tester.pump(const Duration(seconds: 6));
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _SummaryRepository repository,
  required Size size,
  AppLanguage language = AppLanguage.english,
  _WorkbookFiles? files,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: YorksV1ProjectMaterialMovementWorkspace(
              projectId: 'project-1',
              projectReference: 'YRA-322',
              projectName: 'Tower A',
              language: language,
              register: const Text('REGISTER CONTENT'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/yorks/material-requests/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1LogisticsRepositoryProvider.overrideWithValue(repository),
        if (files != null)
          yorksV1BoqWorkbookFileServiceProvider.overrideWithValue(files),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Implements only the read-only summary boundary; every other logistics
/// command is unreachable from this panel and fails loudly if called.
class _SummaryRepository
    implements
        YorksV1LogisticsRepository,
        YorksV1ProjectMaterialSummaryRepository {
  _SummaryRepository({this.empty = false, this.error});

  final bool empty;
  YorksV1DomainException? error;
  final queries = <YorksV1MaterialSummaryQuery>[];

  @override
  Future<YorksV1ProjectMaterialSummary> getProjectMaterialSummary(
    YorksV1MaterialSummaryQuery query,
  ) async {
    queries.add(query);
    final failure = error;
    if (failure != null) throw failure;
    final json = yorksV1MaterialSummaryFixture();
    if (empty) {
      json['items'] = <Object?>[];
      json['requests'] = <Object?>[];
      json['months'] = <Object?>[];
      json['weeks'] = <Object?>[];
    }
    return YorksV1ProjectMaterialSummary.fromRpcJson(json);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkbookFiles implements YorksV1BoqWorkbookFileService {
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<bool> saveWorkbook({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    savedBytes = bytes;
    savedName = suggestedName;
    return true;
  }

  @override
  Future<YorksV1BoqSelectedWorkbook?> selectWorkbook() async => null;
}

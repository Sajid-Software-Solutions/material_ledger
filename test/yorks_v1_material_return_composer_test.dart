import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/widgets/yorks_v1_material_return_composer.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_candidates.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_workflow.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_material_return_candidates_fixture.dart';

const _pipeKey = 'copper pipe\u001f15mm\u001fmtr';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop: search, add, allocate newest delivery first', (
    tester,
  ) async {
    final repository = _CandidatesRepository();
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1366, 900));

    expect(find.text('Copper Pipe'), findsOneWidget);
    expect(find.text('13 Mtr returnable'), findsOneWidget);
    expect(find.text('5 not yet confirmed by site'), findsOneWidget);
    expect(repository.queries.single.normalizedSearch, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('material-return-search')),
      'gloves',
    );
    await tester.pump();
    expect(find.text('Copper Pipe'), findsNothing);
    expect(find.text('Safety Gloves'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('material-return-search')),
      'pipe',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.queries.last.normalizedSearch, 'pipe');

    await tester.tap(
      find.byKey(const ValueKey('material-return-add-$_pipeKey')),
    );
    await tester.pumpAndSettle();
    expect(controller.selections.single.key, _pipeKey);
    expect(find.text('Added'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('material-return-qty-$_pipeKey')),
      '7',
    );
    await tester.pumpAndSettle();
    expect(find.text('Deliveries used'), findsOneWidget);
    expect(find.text('Takes 5 of 5'), findsOneWidget);
    expect(find.text('Takes 2 of 8'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('material-return-qty-$_pipeKey')),
      '14',
    );
    await tester.pumpAndSettle();
    expect(find.text('Only 13 can be returned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a close spelling is found through the server search', (
    tester,
  ) async {
    final repository = _CandidatesRepository();
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1366, 900));

    await tester.enterText(
      find.byKey(const ValueKey('material-return-search')),
      'coper',
    );
    await tester.pump();
    expect(find.text('Copper Pipe'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.queries.last.normalizedSearch, 'coper');
    expect(find.text('Copper Pipe'), findsOneWidget);
  });

  testWidgets('building filter limits deliveries to the return building', (
    tester,
  ) async {
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      _CandidatesRepository(),
      controller,
      const Size(1366, 900),
    );
    await tester.tap(
      find.byKey(const ValueKey('material-return-only-building')),
    );
    await tester.pumpAndSettle();
    expect(find.text('8 Mtr returnable'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('material-return-add-$_pipeKey')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.selections.single.item?.sources.single.dispatchLineId,
      'dl-1',
    );
  });

  testWidgets('360px phone and Arabic render without overflow', (tester) async {
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      _CandidatesRepository(),
      controller,
      const Size(360, 800),
      language: AppLanguage.arabic,
    );
    await tester.tap(
      find.byKey(const ValueKey('material-return-add-$_pipeKey')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('material-return-qty-$_pipeKey')),
      '6',
    );
    await tester.pumpAndSettle();
    expect(find.text('المواد المراد إرجاعها'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure offers a retry', (tester) async {
    final repository = _CandidatesRepository(fail: true);
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1366, 900));
    expect(
      find.text('Delivered material could not be loaded.'),
      findsOneWidget,
    );
    repository.fail = false;
    await tester.tap(
      find.byKey(const ValueKey('material-return-candidates-retry')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copper Pipe'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _CandidatesRepository repository,
  YorksV1ReturnComposerController controller,
  Size size, {
  AppLanguage language = AppLanguage.english,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1LogisticsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: YorksV1MaterialReturnComposer(
              projectId: 'project-1',
              scopeId: 'scope-a',
              scopes: const [
                YorksV1MaterialReturnScope(
                  id: 'scope-a',
                  name: 'Building A',
                  kind: 'building',
                ),
              ],
              controller: controller,
              language: language,
              enabled: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Implements only the candidates read; every other command fails loudly.
class _CandidatesRepository
    implements
        YorksV1LogisticsRepository,
        YorksV1MaterialReturnItemCandidatesRepository {
  _CandidatesRepository({this.fail = false});

  bool fail;
  final queries = <YorksV1MaterialReturnCandidatesQuery>[];

  @override
  Future<YorksV1MaterialReturnItemCandidates> getMaterialReturnItemCandidates(
    YorksV1MaterialReturnCandidatesQuery query,
  ) async {
    queries.add(query);
    if (fail) throw StateError('offline');
    final json = yorksV1MaterialReturnCandidatesFixture();
    final search = query.normalizedSearch;
    // The server's trigram search also finds close spellings.
    if (search == 'gloves') {
      json['items'] = [(json['items']! as List).last];
    } else if (search != null && search != 'pipe' && search != 'coper') {
      json['items'] = <Object?>[];
    } else if (search != null) {
      json['items'] = [(json['items']! as List).first];
    }
    return YorksV1MaterialReturnItemCandidates.fromRpcJson(json);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

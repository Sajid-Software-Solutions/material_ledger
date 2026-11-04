import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/widgets/yorks_v1_material_return_composer.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_candidates.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_configuration_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_logistics_repository_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_logistics_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_material_return_candidates_fixture.dart';

const _pipeKey = 'copper pipe\u001f15mm\u001fmtr';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop: type-ahead adds a delivered row to the MR grid', (
    tester,
  ) async {
    final repository = _CandidatesRepository();
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1440, 900));

    expect(find.byKey(const ValueKey('material-return-search')), findsOne);
    expect(repository.queries.single.normalizedSearch, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('material-return-search')),
      'pipe',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('13 Mtr returnable'), findsOneWidget);
    expect(find.text('5 not yet confirmed by site'), findsOneWidget);

    await tester.tap(find.text('Copper Pipe'));
    await tester.pumpAndSettle();
    expect(controller.lines.single.description, 'Copper Pipe');
    expect(find.byKey(const ValueKey('mr-lines-desktop-table')), findsOne);
    expect(find.text('of 13 available'), findsOneWidget);
    expect(find.text('From delivery'), findsOneWidget);

    final id = controller.lines.single.id;
    await tester.enterText(find.byKey(ValueKey('$id-quantity')), '14');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.lines.single.quantity, '14');
    expect(
      find.byKey(const ValueKey('material-return-attention')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(ValueKey('$id-quantity')), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-return-attention')),
      findsNothing,
    );
    await tester.tap(find.byKey(ValueKey('material-return-deliveries-$id')));
    await tester.pumpAndSettle();
    expect(find.text('Takes 5 of 5'), findsOneWidget);
    expect(find.text('Takes 2 of 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a close spelling is found through the server search', (
    tester,
  ) async {
    final repository = _CandidatesRepository();
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1440, 900));

    await tester.enterText(
      find.byKey(const ValueKey('material-return-search')),
      'coper',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.queries.last.normalizedSearch, 'coper');
    expect(find.text('Copper Pipe'), findsOneWidget);
  });

  testWidgets('Add from Deliveries selects several and filters by building', (
    tester,
  ) async {
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      _CandidatesRepository(),
      controller,
      const Size(1440, 900),
      withPickerButton: true,
    );
    await tester.tap(find.text('OPEN PICKER'));
    await tester.pumpAndSettle();
    expect(find.text('Add delivered material'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('material-return-only-building')),
    );
    await tester.pumpAndSettle();
    expect(find.text('8 Mtr returnable'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('material-return-all-buildings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('material-return-pick-$_pipeKey')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('material-return-pick-safety gloves\u001f\u001fpairs'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 items selected'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('material-return-add-selected')),
    );
    await tester.pumpAndSettle();
    expect(controller.lines.map((line) => line.description), [
      'Copper Pipe',
      'Safety Gloves',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360px phone and Arabic render the MR focused editor', (
    tester,
  ) async {
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      _CandidatesRepository(),
      controller,
      const Size(360, 800),
      language: AppLanguage.arabic,
    );
    final candidates = YorksV1MaterialReturnItemCandidates.fromRpcJson(
      yorksV1MaterialReturnCandidatesFixture(),
    );
    controller.addItem(candidates.items.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mr-lines-desktop-table')), findsNothing);
    expect(
      find.byKey(
        ValueKey('material-return-delivered-${controller.lines.single.id}'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure offers a retry', (tester) async {
    final repository = _CandidatesRepository(fail: true);
    final controller = YorksV1ReturnComposerController();
    addTearDown(controller.dispose);
    await _pump(tester, repository, controller, const Size(1440, 900));
    expect(
      find.text('Delivered material could not be loaded.'),
      findsOneWidget,
    );
    repository.fail = false;
    await tester.tap(
      find.byKey(const ValueKey('material-return-candidates-retry')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('material-return-search')), findsOne);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _CandidatesRepository repository,
  YorksV1ReturnComposerController controller,
  Size size, {
  AppLanguage language = AppLanguage.english,
  bool withPickerButton = false,
}) async {
  final preferences = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1LogisticsRepositoryProvider.overrideWithValue(repository),
        yorksV1ConfigurationUnitCodesProvider.overrideWith(
          (ref) async => const ['Mtr', 'Pairs', 'Nos'],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (withPickerButton)
                    TextButton(
                      onPressed: () => showYorksV1DeliveredMaterialPicker(
                        context,
                        projectId: 'project-1',
                        returnId: null,
                        scopeId: 'scope-a',
                        scopeName: 'Building A',
                        projectReference: 'YRA-313',
                        controller: controller,
                        language: language,
                      ),
                      child: const Text('OPEN PICKER'),
                    ),
                  YorksV1MaterialReturnItems(
                    projectId: 'project-1',
                    scopeId: 'scope-a',
                    controller: controller,
                    language: language,
                    enabled: true,
                  ),
                  const SizedBox(height: 400),
                ],
              ),
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
    if (search == 'coper' || search == 'pipe') {
      json['items'] = [(json['items']! as List).first];
    } else if (search != null) {
      json['items'] = <Object?>[];
    }
    return YorksV1MaterialReturnItemCandidates.fromRpcJson(json);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

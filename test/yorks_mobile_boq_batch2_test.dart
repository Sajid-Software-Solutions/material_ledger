import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/constants/constants.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_boq_screens.dart';
import 'package:material_ledger/shared/models/app_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_permission_management.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/permissions_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_boq_workbook_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_material_request_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_permission_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_boq_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/yorks_v1_permission_test_support.dart';

const _projectId = 'mobile-boq-project';
const _groupId = 'mobile-boq-ac-units';
const _df3wScopeId = 'mobile-boq-scope-df3w';

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

    testWidgets('mobile BOQ 15 scope Overview $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpGroups(tester);

      expect(
        find.byKey(const ValueKey('boq-mobile-scope-overview')),
        findsOneWidget,
      );
      expect(find.text('Common / All Buildings'), findsNWidgets(2));
      expect(find.text('DF3W'), findsAtLeastNWidgets(1));
      expect(find.text('DF4W'), findsAtLeastNWidgets(1));
      expect(find.text(YorksV1BoqStrings.newGroup.primary), findsNothing);
      final export = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, YorksDataTransferIcons.exportData),
      );
      expect(export.onPressed, isNull);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/mobile_batch2/boq_scope_overview_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 16 building folders $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpGroups(tester, selectedScopeId: _df3wScopeId);

      expect(find.text('All 6'), findsOneWidget);
      expect(find.text('Started 5'), findsOneWidget);
      expect(find.text('Empty 1'), findsOneWidget);
      expect(find.textContaining('01 · AC Units'), findsOneWidget);
      expect(find.textContaining('05 · Cable Tray'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
      expect(find.text('Not started'), findsNothing);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/mobile_batch2/boq_building_folders_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 17 materials $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorksheet(tester);

      expect(find.byKey(const ValueKey('boq-mobile-add-material')), findsOne);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('boq-linked-work-strip')))
            .height,
        lessThanOrEqualTo(64),
        reason: 'Linked metadata must remain a compact, single-line strip.',
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('yorks-v1-boq-mobile-list')))
            .height,
        greaterThanOrEqualTo(size.height * 0.5),
        reason: 'At least half of the mobile viewport belongs to BOQ rows.',
      );
      expect(find.text('Split AC Indoor Unit'), findsOneWidget);
      expect(find.text('Split AC Outdoor Unit'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-boq-row-row-5')),
        findsNothing,
        reason: 'The material list must stay lazily built at mobile size.',
      );
      expect(find.text('AED 2,500 confidential'), findsNothing);
      expect(find.text('Unit Cost'), findsNothing);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/mobile_batch2/boq_materials_$suffix.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 18 focused editor $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorksheet(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
      await tester.pumpAndSettle();

      expect(find.text(YorksV1BoqStrings.editMaterial.primary), findsWidgets);
      expect(find.text('Item Description'), findsOneWidget);
      expect(find.text('Equipment Tag'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Unit Cost'), findsNothing);
      expect(find.text('AED 2,500 confidential'), findsNothing);
      expect(find.text(YorksV1BoqStrings.previous.primary), findsOneWidget);
      expect(find.text(YorksV1BoqStrings.next.primary), findsOneWidget);
      expect(find.text(YorksV1BoqStrings.save.primary), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text(YorksV1BoqStrings.previous.primary))
            .maxLines,
        1,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/mobile_batch2/boq_material_editor_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 19 import upload $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorksheet(tester);
      await _openImport(tester);

      expect(
        find.text(YorksV1BoqStrings.chooseWorkbookTitle.primary),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('boq-mobile-import-choose-file')),
        findsOne,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/mobile_batch2/boq_import_upload_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 20 import map $suffix', (tester) async {
      await _setViewport(tester, size);
      await _pumpWorksheet(tester);
      await _advanceImportTo(tester, 2);

      expect(find.text(YorksV1BoqStrings.mapColumnsTitle.primary), findsOne);
      expect(find.text('Air flow (L/s)'), findsOneWidget);
      expect(
        find.text(YorksV1BoqStrings.otherColumnsStayAvailable.primary),
        findsOneWidget,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/mobile_batch2/boq_import_map_$suffix.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile BOQ 21 import review $suffix', (tester) async {
      await _setViewport(tester, size);
      final harness = await _pumpWorksheet(tester);
      await _advanceImportTo(tester, 3);

      expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsOne);
      expect(find.text('Imported AC Schedule'), findsOneWidget);
      expect(harness.repository.importInputs, isEmpty);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/mobile_batch2/boq_import_review_$suffix.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile BOQ remains usable at 200 percent text scale', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpWorksheet(tester);

    expect(find.byKey(const ValueKey('yorks-v1-boq-mobile-list')), findsOne);
    await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
    await tester.pumpAndSettle();
    expect(find.text(YorksV1BoqStrings.editMaterial.primary), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop BOQ worksheet prioritises the editable grid', (
    tester,
  ) async {
    const size = Size(1366, 768);
    await _setViewport(tester, size);
    await _pumpWorksheet(tester);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('boq-worksheet-context-bar')))
          .height,
      60,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('boq-linked-work-strip')))
          .height,
      lessThanOrEqualTo(AppSpacing.colossal),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('yorks-v1-boq-desktop-grid')))
          .height,
      greaterThanOrEqualTo(size.height * 0.5),
      reason: 'The worksheet grid must remain the dominant desktop surface.',
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/boq_worksheet_desktop.png'),
    );
  });

  for (final width in [768.0, 1024.0]) {
    testWidgets('tablet BOQ worksheet has no overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await _setViewport(tester, Size(width, 900));
      await _pumpWorksheet(tester);

      expect(
        find.byKey(const ValueKey('yorks-v1-boq-desktop-grid')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('boq-add-row-footer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/boq_worksheet_tablet_${width.toInt()}x900.png',
        ),
      );
    });
  }

  testWidgets('tablet BOQ remains usable at 200 percent text scale', (
    tester,
  ) async {
    await _setViewport(tester, const Size(768, 900));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpWorksheet(tester);

    expect(find.byKey(const ValueKey('boq-add-row-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Overview is summary-only and real folder filters stay truthful',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final harness = await _pumpGroups(tester);

      expect(find.text(YorksV1BoqStrings.addMaterial.primary), findsNothing);
      expect(find.text(YorksV1BoqStrings.sendWholeGroup.primary), findsNothing);
      expect(find.text(YorksV1BoqStrings.newGroup.primary), findsNothing);

      harness.container
              .read(yorksV1BoqScopeSelectionProvider(_projectId).notifier)
              .state =
          _df3wScopeId;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('05 · Cable Tray'), findsOneWidget);
      expect(find.textContaining('01 · AC Units'), findsNothing);
      expect(find.text('0 materials'), findsOneWidget);

      await tester.tap(find.text('Started 5'));
      await tester.pumpAndSettle();
      expect(find.textContaining('01 · AC Units'), findsOneWidget);
      expect(find.textContaining('05 · Cable Tray'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop scope browser search filter and view controls work', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 900));
    await _pumpGroups(
      tester,
      selectedScopeId: _df3wScopeId,
      embedded: true,
      desktopEmbeddedHost: true,
    );

    expect(
      find.byKey(const ValueKey('boq-desktop-group-browser')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('boq-group-search')),
      'Cable Tray',
    );
    await tester.pumpAndSettle();
    expect(find.text('Cable Tray'), findsNWidgets(2));
    expect(find.text('AC Units'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('boq-group-search')), '');
    await tester.tap(find.text(YorksV1MaterialRequestStrings.listView.primary));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('boq-group-list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('boq-group-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(YorksV1BoqStrings.notStartedStatus.primary).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cable Tray'), findsOneWidget);
    expect(find.text('AC Units'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <({Size size, String suffix})>[
    (size: const Size(390, 844), suffix: 'mobile'),
    (size: const Size(1366, 768), suffix: 'desktop'),
  ]) {
    testWidgets('scope-local folder manager is usable on ${entry.suffix}', (
      tester,
    ) async {
      await _setViewport(tester, entry.size);
      final managerGroups = [
        for (final group in _groups)
          if (group.id == 'df3w-fans')
            _group(
              id: _workshopGroupId,
              scope: _scopes[1],
              order: 2,
              title: 'Workshop Materials',
              rows: 8,
            )
          else
            group,
      ];
      final repository = _FixtureBoqRepository(
        worksheet: _worksheet,
        groups: managerGroups,
      );
      await _pumpGroups(
        tester,
        selectedScopeId: _df3wScopeId,
        repository: repository,
      );

      if (entry.suffix == 'mobile') {
        await tester.tap(
          find.byKey(const ValueKey('boq-manage-folders-mobile')),
        );
      } else {
        await tester.tap(find.text(YorksV1BoqStrings.manageFolders.primary));
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('boq-folder-manager')), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('boq-folder-manager-create')))
            .height,
        greaterThanOrEqualTo(AppSpacing.minTapTarget),
      );
      final rename = tester.widget<IconButton>(
        find.byKey(const ValueKey('boq-folder-rename-mobile-boq-ac-units')),
      );
      final archive = tester.widget<IconButton>(
        find.byKey(const ValueKey('boq-folder-archive-mobile-boq-ac-units')),
      );
      expect(rename.onPressed, isNotNull);
      expect(archive.onPressed, isNotNull);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(
                const ValueKey('boq-folder-archive-$_workshopGroupId'),
              ),
            )
            .onPressed,
        isNotNull,
      );

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r35/boq_folder_manager_${entry.suffix}.png'),
      );

      if (entry.suffix == 'mobile') {
        await tester.tap(
          find.byKey(const ValueKey('boq-folder-rename-mobile-boq-ac-units')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(0),
          'Tower A equipment package',
        );
        await tester.enterText(
          find.byType(TextField).at(1),
          'Match the site filing convention',
        );
        await tester.tap(find.text(YorksV1BoqStrings.save.primary));
        await tester.pumpAndSettle();
        expect(repository.renameInputs, hasLength(1));
        expect(repository.renameInputs.single.groupId, _groupId);
        expect(
          repository.renameInputs.single.name,
          'Tower A equipment package',
        );
        expect(
          repository.renameInputs.single.reason,
          'Match the site filing convention',
        );
      } else {
        await tester.tap(
          find.byKey(const ValueKey('boq-folder-archive-mobile-boq-ac-units')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'The scope no longer uses this package',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.text(YorksV1BoqStrings.archiveGroup.primary),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.archiveInputs, hasLength(1));
        expect(repository.archiveInputs.single.groupId, _groupId);
        expect(
          repository.archiveInputs.single.reason,
          'The scope no longer uses this package',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('embedded project BOQ keeps every folder scrollable', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await _pumpGroups(tester, selectedScopeId: _df3wScopeId, embedded: true);

    expect(
      find.byKey(const ValueKey('boq-mobile-embedded-workspace')),
      findsOneWidget,
    );
    final lastFolder = find.textContaining('06 · Sound Attenuator');
    await tester.scrollUntilVisible(
      lastFolder,
      320,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('boq-mobile-embedded-workspace')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(lastFolder),
      alignment: .5,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    expect(lastFolder, findsOneWidget);
    expect(lastFolder.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'focused editor preserves read-only and conflict states and hides commercials',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await _pumpWorksheet(tester, role: YorksV1Role.procurement);
      await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
      await tester.pumpAndSettle();

      expect(find.text(YorksV1BoqStrings.readOnly.primary), findsOneWidget);
      expect(find.text('Unit Cost'), findsNothing);
      expect(find.text('AED 2,500 confidential'), findsNothing);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((field) => field.enabled == false),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      final repository = _FixtureBoqRepository(
        worksheet: _worksheet,
        groups: _groups,
        saveConflict: true,
      );
      final harness = await _pumpWorksheet(tester, repository: repository);
      final controller = harness.container.read(
        yorksV1BoqWorksheetControllerProvider(_groupId).notifier,
      );
      controller.updateTitle('Locally edited title');
      expect(await controller.save(), isFalse);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
      await tester.pumpAndSettle();

      expect(find.text(YorksV1BoqStrings.syncConflict.primary), findsOneWidget);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((field) => field.enabled == false),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focused editor confirms deletion before changing local rows', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    final harness = await _pumpWorksheet(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
    await tester.pumpAndSettle();

    final delete = find.widgetWithText(
      OutlinedButton,
      YorksV1BoqStrings.deleteRow.primary,
    );
    final editorList = find.byType(ListView).last;
    for (var index = 0; index < 4 && delete.evaluate().isEmpty; index++) {
      await tester.drag(editorList, const Offset(0, -320));
      await tester.pumpAndSettle();
    }
    expect(delete, findsOneWidget);
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      harness.container
          .read(yorksV1BoqWorksheetControllerProvider(_groupId))
          .worksheet!
          .rows,
      hasLength(5),
    );

    await tester.tap(find.text(YorksV1BoqStrings.cancel.primary));
    await tester.pumpAndSettle();
    expect(
      harness.container
          .read(yorksV1BoqWorksheetControllerProvider(_groupId))
          .worksheet!
          .rows,
      hasLength(5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'focused editor inserts a similar row directly below its source',
    (tester) async {
      await _setViewport(tester, const Size(360, 800));
      final harness = await _pumpWorksheet(tester);
      final row = find.byKey(const ValueKey('mobile-boq-row-row-1'));
      await Scrollable.ensureVisible(tester.element(row), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      final similar = find.byKey(const ValueKey('boq-mobile-similar-row'));
      final editorList = find.byType(ListView).last;
      for (var index = 0; index < 5 && similar.evaluate().isEmpty; index++) {
        await tester.drag(editorList, const Offset(0, -320));
        await tester.pumpAndSettle();
      }
      expect(similar, findsOneWidget);
      await tester.tap(similar);
      await tester.pumpAndSettle();

      final rows = harness.container
          .read(yorksV1BoqWorksheetControllerProvider(_groupId))
          .worksheet!
          .rows;
      expect(rows, hasLength(6));
      expect(rows[1].valueFor('description'), 'Split AC Indoor Unit');
      expect(rows[1].valueFor('tag'), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focused editor guards dirty Back and discards explicitly', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    final harness = await _pumpWorksheet(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-boq-row-row-1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Changed locally');
    final backTooltip = MaterialLocalizations.of(
      tester.element(find.byType(TextFormField).first),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pumpAndSettle();

    expect(find.text(YorksV1BoqStrings.discardRowChanges.primary), findsOne);
    await tester.tap(find.text(AppStrings.keepEditing.primary));
    await tester.pumpAndSettle();
    expect(find.text('Changed locally'), findsOneWidget);

    await tester.tap(find.byTooltip(backTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.discard.primary));
    await tester.pumpAndSettle();

    expect(find.text(YorksV1BoqStrings.editMaterial.primary), findsNothing);
    expect(
      harness.container
          .read(yorksV1BoqWorksheetControllerProvider(_groupId))
          .worksheet!
          .rows
          .first
          .valueFor('description'),
      'Split AC Indoor Unit',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('import blocks Back until the server command resolves', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final pendingImport = Completer<YorksV1BoqWorksheet>();
    final repository = _FixtureBoqRepository(
      worksheet: _worksheet,
      groups: _groups,
      pendingImport: pendingImport,
    );
    await _pumpWorksheet(tester, repository: repository);
    await _advanceImportTo(tester, 3);

    await tester.tap(find.byKey(const ValueKey('boq-mobile-import-continue')));
    await tester.pump();
    expect(repository.importInputs, hasLength(1));

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsOneWidget);

    pendingImport.complete(repository.importInputs.single.worksheet);
    await tester.pumpAndSettle();
    expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsNothing);
    expect(
      find.byKey(const ValueKey('yorks-v1-boq-desktop-grid')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('yorks-v1-boq-mobile-list')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import preview preserves arbitrary columns and mutates only on final commit',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final repository = _FixtureBoqRepository(
        worksheet: _worksheet,
        groups: _groups,
        importConflict: true,
      );
      final harness = await _pumpWorksheet(tester, repository: repository);
      final before = harness.container
          .read(yorksV1BoqWorksheetControllerProvider(_groupId))
          .worksheet;

      await _advanceImportTo(tester, 3);

      expect(repository.importInputs, isEmpty);
      expect(
        harness.container
            .read(yorksV1BoqWorksheetControllerProvider(_groupId))
            .worksheet,
        same(before),
      );
      expect(find.text('Air flow (L/s)'), findsNothing);
      expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsOne);

      await tester.tap(
        find.byKey(const ValueKey('boq-mobile-import-continue')),
      );
      await tester.pumpAndSettle();

      expect(repository.importInputs, hasLength(1));
      expect(
        repository.importInputs.single.worksheet.columns.map(
          (column) => column.heading,
        ),
        contains('Air flow (L/s)'),
      );
      expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsOne);
      expect(
        find.text(YorksV1BoqStrings.importConflictTitle.primary),
        findsOneWidget,
      );
      expect(
        find.text(YorksV1BoqStrings.previewRetainedAfterFailure.primary),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('boq-mobile-import-continue')),
            )
            .onPressed,
        isNull,
      );
      expect(
        harness.container
            .read(yorksV1BoqWorksheetControllerProvider(_groupId))
            .worksheet,
        same(before),
      );

      final refresh = find.widgetWithText(
        TextButton,
        YorksV1BoqStrings.refresh.primary,
      );
      await Scrollable.ensureVisible(tester.element(refresh), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text(YorksV1BoqStrings.reviewWorkbook.primary), findsNothing);
      expect(find.byKey(const ValueKey('yorks-v1-boq-mobile-list')), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'engineer commercial workbook is blocked before any repository mutation',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final repository = _FixtureBoqRepository(
        worksheet: _worksheet,
        groups: _groups,
      );
      await _pumpWorksheet(
        tester,
        repository: repository,
        importWorksheet: _commercialImportWorksheet,
      );
      await _advanceImportTo(tester, 2);

      expect(
        find.text(YorksV1BoqStrings.commercialImportPermissionRequired.primary),
        findsOneWidget,
      );
      final unitCostMapping = find.ancestor(
        of: find.text(YorksV1MaterialRequestStrings.unitCost.primary),
        matching: find.byType(
          DropdownButtonFormField<YorksV1BoqCanonicalField?>,
        ),
      );
      expect(unitCostMapping, findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<YorksV1BoqCanonicalField?>>(
              unitCostMapping,
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('boq-mobile-import-continue')),
            )
            .onPressed,
        isNull,
      );
      expect(repository.importInputs, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authorized commercial workbook keeps protected classification', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final repository = _FixtureBoqRepository(
      worksheet: _worksheet,
      groups: _groups,
    );
    await _pumpWorksheet(
      tester,
      role: YorksV1Role.admin,
      repository: repository,
      canManageCommercials: true,
      importWorksheet: _commercialImportWorksheet,
    );
    await _advanceImportTo(tester, 3);

    expect(
      find.text(YorksV1BoqStrings.commercialImportPermissionRequired.primary),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('boq-mobile-import-continue')));
    await tester.pumpAndSettle();

    expect(repository.importInputs, hasLength(1));
    expect(
      repository.importInputs.single.worksheet.columns
          .firstWhere((column) => column.heading == 'Unit Cost')
          .isCommercial,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<_BoqHarness> _pumpGroups(
  WidgetTester tester, {
  String? selectedScopeId,
  bool embedded = false,
  bool desktopEmbeddedHost = false,
  _FixtureBoqRepository? repository,
}) async {
  final effectiveRepository =
      repository ??
      _FixtureBoqRepository(worksheet: _worksheet, groups: _groups);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.projectEngineer),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          yorksV1TrustedFeaturePermissionState(
            role: YorksV1Role.projectEngineer,
          ),
        ),
      ),
      canViewCommercialsProvider.overrideWithValue(false),
      yorksV1BoqRepositoryProvider.overrideWithValue(effectiveRepository),
      yorksV1MaterialRequestScopesProvider(
        _projectId,
      ).overrideWith((ref) async => _scopes),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: desktopEmbeddedHost
            ? Scaffold(
                body: SingleChildScrollView(
                  child: YorksV1BoqGroupsScreen(
                    projectId: _projectId,
                    embedded: embedded,
                  ),
                ),
              )
            : YorksV1BoqGroupsScreen(projectId: _projectId, embedded: embedded),
      ),
    ),
  );
  container.read(yorksV1BoqScopeSelectionProvider(_projectId).notifier).state =
      selectedScopeId;
  await tester.pumpAndSettle();
  return _BoqHarness(container: container, repository: effectiveRepository);
}

Future<_BoqHarness> _pumpWorksheet(
  WidgetTester tester, {
  YorksV1Role role = YorksV1Role.projectEngineer,
  _FixtureBoqRepository? repository,
  bool canManageCommercials = false,
  YorksV1BoqWorksheet? importWorksheet,
}) async {
  final effectiveRepository =
      repository ??
      _FixtureBoqRepository(worksheet: _worksheet, groups: _groups);
  final preferences = await SharedPreferences.getInstance();
  final codec = const YorksV1BoqWorkbookCodec();
  final fileService = _FixtureWorkbookFileService(
    selected: YorksV1BoqSelectedWorkbook(
      fileName: 'equipment_schedule.xlsx',
      bytes: codec.encodeWorksheet(importWorksheet ?? _importWorksheet),
    ),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      yorksV1CurrentRoleProvider.overrideWithValue(role),
      yorksV1CurrentPermissionSnapshotProvider.overrideWith(
        (ref) => YorksV1TestPermissionController(
          yorksV1TrustedFeaturePermissionState(
            role: role,
            capabilities: role == YorksV1Role.procurement
                ? const {YorksV1CapabilityKeys.boqView}
                : yorksV1EnforcedFeatureActionCapabilities,
          ),
        ),
      ),
      canViewCommercialsProvider.overrideWithValue(false),
      canManageCommercialsProvider.overrideWithValue(canManageCommercials),
      yorksV1BoqRepositoryProvider.overrideWithValue(effectiveRepository),
      yorksV1BoqWorkbookFileServiceProvider.overrideWithValue(fileService),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksV1BoqWorksheetScreen(
          projectId: _projectId,
          groupId: _groupId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _BoqHarness(container: container, repository: effectiveRepository);
}

Future<void> _openImport(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('boq-mobile-more-actions'));
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('boq-import-workbook')));
  await tester.pumpAndSettle();
}

Future<void> _advanceImportTo(WidgetTester tester, int targetStep) async {
  await _openImport(tester);
  if (targetStep == 0) return;
  await tester.tap(find.byKey(const ValueKey('boq-mobile-import-choose-file')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('boq-mobile-import-continue')));
  await tester.pumpAndSettle();
  if (targetStep == 1) return;
  await tester.tap(find.byKey(const ValueKey('boq-mobile-import-continue')));
  await tester.pumpAndSettle();
  if (targetStep == 2) return;
  await tester.tap(find.byKey(const ValueKey('boq-mobile-import-continue')));
  await tester.pumpAndSettle();
}

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

class _BoqHarness {
  const _BoqHarness({required this.container, required this.repository});

  final ProviderContainer container;
  final _FixtureBoqRepository repository;
}

class _FixtureWorkbookFileService implements YorksV1BoqWorkbookFileService {
  const _FixtureWorkbookFileService({required this.selected});

  final YorksV1BoqSelectedWorkbook selected;

  @override
  Future<YorksV1BoqSelectedWorkbook?> selectWorkbook() async => selected;

  @override
  Future<bool> saveWorkbook({required bytes, required suggestedName}) async =>
      true;
}

class _FixtureBoqRepository implements YorksV1BoqRepository {
  _FixtureBoqRepository({
    required this.worksheet,
    required this.groups,
    this.saveConflict = false,
    this.importConflict = false,
    this.pendingImport,
  });

  final YorksV1BoqWorksheet worksheet;
  final List<YorksV1BoqGroup> groups;
  final bool saveConflict;
  final bool importConflict;
  final Completer<YorksV1BoqWorksheet>? pendingImport;
  final List<YorksV1SaveBoqWorksheetInput> saveInputs = [];
  final List<YorksV1ImportBoqWorksheetInput> importInputs = [];
  final List<YorksV1RenameBoqGroupInput> renameInputs = [];
  final List<YorksV1ArchiveBoqGroupInput> archiveInputs = [];
  final List<YorksV1RestoreBoqGroupInput> restoreInputs = [];

  @override
  Future<List<YorksV1BoqGroup>> listGroups(String projectId) async => groups;

  @override
  Future<List<YorksV1BoqGroup>> listGroupsForScope(
    String projectId, {
    String? scopeId,
  }) async => scopeId == null
      ? groups
      : groups.where((group) => group.scopeId == scopeId).toList();

  @override
  Future<List<YorksV1BoqFolderManagementItem>> listFolderManagement(
    String projectId, {
    required String scopeId,
    bool includeArchived = true,
  }) async => [
    for (final group in groups)
      if (group.scopeId == scopeId && (includeArchived || !group.isArchived))
        YorksV1BoqFolderManagementItem(
          group: group,
          isSystemDefault: !group.isCustom,
          canRename: !group.isArchived,
          canArchive:
              (group.isCustom ||
                  group.id == _groupId ||
                  group.id == _workshopGroupId) &&
              !group.isArchived,
          canRestore:
              (group.isCustom ||
                  group.id == _groupId ||
                  group.id == _workshopGroupId) &&
              group.isArchived,
        ),
  ];

  @override
  Future<YorksV1BoqWorksheet> getWorksheet(String groupId) async => worksheet;

  @override
  Future<YorksV1BoqWorksheet> saveWorksheet(
    YorksV1SaveBoqWorksheetInput input,
  ) async {
    saveInputs.add(input);
    if (saveConflict) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    return input.worksheet;
  }

  @override
  Future<YorksV1BoqWorksheet> importWorksheet(
    YorksV1ImportBoqWorksheetInput input,
  ) async {
    importInputs.add(input);
    if (pendingImport != null) return pendingImport!.future;
    if (importConflict) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    return input.worksheet;
  }

  @override
  Future<YorksV1BoqGroup> createCustomGroup(
    YorksV1CreateBoqGroupInput input,
  ) async => groups.first;

  @override
  Future<YorksV1BoqGroup> renameGroup(YorksV1RenameBoqGroupInput input) async {
    renameInputs.add(input);
    return groups.firstWhere((group) => group.id == input.groupId);
  }

  @override
  Future<YorksV1BoqGroup> assignLegacyGroupScope(
    YorksV1AssignLegacyBoqGroupScopeInput input,
  ) async => groups.first;

  @override
  Future<YorksV1BoqGroup> archiveGroup(
    YorksV1ArchiveBoqGroupInput input,
  ) async {
    archiveInputs.add(input);
    return groups.firstWhere((group) => group.id == input.groupId);
  }

  @override
  Future<YorksV1BoqGroup> restoreGroup(
    YorksV1RestoreBoqGroupInput input,
  ) async {
    restoreInputs.add(input);
    return groups.firstWhere((group) => group.id == input.groupId);
  }
}

const _scopes = [
  YorksV1MaterialRequestScopeOption(
    id: 'mobile-boq-scope-common',
    projectId: _projectId,
    name: 'Common / All Buildings',
    kind: 'common',
  ),
  YorksV1MaterialRequestScopeOption(
    id: _df3wScopeId,
    projectId: _projectId,
    name: 'DF3W',
    kind: 'building',
  ),
  YorksV1MaterialRequestScopeOption(
    id: 'mobile-boq-scope-df4w',
    projectId: _projectId,
    name: 'DF4W',
    kind: 'building',
  ),
];

final _groups = [
  _group(
    id: 'common-ac',
    scope: _scopes[0],
    order: 1,
    title: 'AC Units',
    rows: 4,
  ),
  _group(
    id: 'common-fans',
    scope: _scopes[0],
    order: 2,
    title: 'Ventilation Fans',
  ),
  _group(
    id: _groupId,
    scope: _scopes[1],
    order: 1,
    title: 'AC Units',
    rows: 12,
  ),
  _group(
    id: 'df3w-fans',
    scope: _scopes[1],
    order: 2,
    title: 'Ventilation Fans',
    rows: 8,
  ),
  _group(
    id: 'df3w-dampers',
    scope: _scopes[1],
    order: 3,
    title: 'MFD, MSFD, MSD, MVCD & VCD',
    rows: 15,
  ),
  _group(
    id: 'df3w-inlets',
    scope: _scopes[1],
    order: 4,
    title: 'Air Inlet & Outlet',
    rows: 18,
  ),
  _group(id: 'df3w-cable', scope: _scopes[1], order: 5, title: 'Cable Tray'),
  _group(
    id: 'df3w-sound',
    scope: _scopes[1],
    order: 6,
    title: 'Sound Attenuator',
    rows: 6,
  ),
  _group(
    id: 'df4w-ac',
    scope: _scopes[2],
    order: 1,
    title: 'AC Units',
    rows: 7,
  ),
  _group(
    id: 'df4w-fans',
    scope: _scopes[2],
    order: 2,
    title: 'Ventilation Fans',
    rows: 3,
  ),
];

const _workshopGroupId = 'mobile-boq-workshop-materials';

YorksV1BoqGroup _group({
  required String id,
  required YorksV1MaterialRequestScopeOption scope,
  required int order,
  required String title,
  int rows = 0,
}) => YorksV1BoqGroup(
  id: id,
  projectId: _projectId,
  name: title,
  worksheetTitle: title,
  displayOrder: order,
  isCustom: false,
  isArchived: false,
  version: 1,
  rowCount: rows,
  columnCount: 9,
  updatedAt: DateTime.utc(2026, 8, 9),
  scopeId: scope.id,
  scopeKind: scope.kind,
  scopeCode: scope.name == 'DF3W' || scope.name == 'DF4W' ? scope.name : null,
  scopeName: scope.name,
);

final _worksheet = YorksV1BoqWorksheet(
  group: _groups.firstWhere((group) => group.id == _groupId),
  columns: const [
    YorksV1BoqColumn(
      id: 'description',
      heading: 'Item Description',
      displayOrder: 1,
      canonicalField: YorksV1BoqCanonicalField.description,
    ),
    YorksV1BoqColumn(
      id: 'size',
      heading: 'Size',
      displayOrder: 2,
      canonicalField: YorksV1BoqCanonicalField.size,
    ),
    YorksV1BoqColumn(
      id: 'model',
      heading: 'Model',
      displayOrder: 3,
      canonicalField: YorksV1BoqCanonicalField.model,
    ),
    YorksV1BoqColumn(
      id: 'tag',
      heading: 'Equipment Tag',
      displayOrder: 4,
      canonicalField: YorksV1BoqCanonicalField.equipmentTag,
    ),
    YorksV1BoqColumn(
      id: 'brand',
      heading: 'Make / Origin',
      displayOrder: 5,
      canonicalField: YorksV1BoqCanonicalField.brandOrigin,
    ),
    YorksV1BoqColumn(
      id: 'quantity',
      heading: 'Quantity',
      displayOrder: 6,
      canonicalField: YorksV1BoqCanonicalField.quantity,
    ),
    YorksV1BoqColumn(
      id: 'unit',
      heading: 'Unit',
      displayOrder: 7,
      canonicalField: YorksV1BoqCanonicalField.unit,
    ),
    YorksV1BoqColumn(
      id: 'air-flow',
      heading: 'Air flow (L/s)',
      displayOrder: 8,
    ),
    YorksV1BoqColumn(
      id: 'unit-cost',
      heading: 'Unit Cost',
      displayOrder: 9,
      isCommercial: true,
    ),
  ],
  rows: [
    _row('row-1', 1, 'Split AC Indoor Unit', '2.0 TR', 'FXAQ50', 'ACU-01', 4),
    _row('row-2', 2, 'Split AC Outdoor Unit', '2.0 TR', 'RXAQ50', 'ACU-02', 4),
    _row('row-3', 3, 'Condensate Drain Pump', '24 L/H', 'DP-24', 'CDP-01', 4),
    _row(
      'row-4',
      4,
      'Insulated Copper Pipe',
      '3/8"',
      'CP-38',
      'CP-01',
      50,
      unit: 'Meter',
    ),
    _row(
      'row-5',
      5,
      'Flexible Duct Connector',
      '300 mm',
      'FDC-300',
      'FDC-01',
      8,
    ),
  ],
);

YorksV1BoqRow _row(
  String id,
  int order,
  String description,
  String size,
  String model,
  String tag,
  int quantity, {
  String unit = 'Nos',
}) => YorksV1BoqRow(
  id: id,
  displayOrder: order,
  values: {
    'description': description,
    'size': size,
    'model': model,
    'tag': tag,
    'brand': 'Daikin / Japan',
    'quantity': '$quantity',
    'unit': unit,
    'air-flow': '${quantity * 125}',
    'unit-cost': 'AED 2,500 confidential',
  },
  canonicalValues: {
    'description': description,
    'size': size,
    'model': model,
    'equipment_tag': tag,
    'brand_origin': 'Daikin / Japan',
    'quantity': '$quantity',
    'unit': unit,
  },
);

final _importWorksheet = YorksV1BoqWorksheet(
  group: YorksV1BoqGroup(
    id: 'import-source',
    projectId: _projectId,
    name: 'Imported AC Schedule',
    worksheetTitle: 'Imported AC Schedule',
    displayOrder: 1,
    isCustom: false,
    isArchived: false,
    version: 1,
    rowCount: 2,
    columnCount: 5,
    updatedAt: DateTime.utc(2026, 8, 9),
  ),
  columns: const [
    YorksV1BoqColumn(
      id: 'import-description',
      heading: 'Item Description',
      displayOrder: 1,
      canonicalField: YorksV1BoqCanonicalField.description,
    ),
    YorksV1BoqColumn(
      id: 'import-size',
      heading: 'Size',
      displayOrder: 2,
      canonicalField: YorksV1BoqCanonicalField.size,
    ),
    YorksV1BoqColumn(
      id: 'import-quantity',
      heading: 'Quantity',
      displayOrder: 3,
      canonicalField: YorksV1BoqCanonicalField.quantity,
    ),
    YorksV1BoqColumn(
      id: 'import-unit',
      heading: 'Unit',
      displayOrder: 4,
      canonicalField: YorksV1BoqCanonicalField.unit,
    ),
    YorksV1BoqColumn(
      id: 'import-air-flow',
      heading: 'Air flow (L/s)',
      displayOrder: 5,
    ),
  ],
  rows: [
    YorksV1BoqRow(
      id: 'import-row-1',
      displayOrder: 1,
      values: const {
        'import-description': 'Fresh Air Handling Unit',
        'import-size': '2500 x 1400',
        'import-quantity': '2',
        'import-unit': 'Nos',
        'import-air-flow': '6600',
      },
      canonicalValues: const {},
    ),
    YorksV1BoqRow(
      id: 'import-row-2',
      displayOrder: 2,
      values: const {
        'import-description': 'Extract Air Fan',
        'import-size': '500 mm',
        'import-quantity': '1',
        'import-unit': 'Nos',
        'import-air-flow': '4200',
      },
      canonicalValues: const {},
    ),
  ],
);

final _commercialImportWorksheet = _importWorksheet.copyWith(
  columns: const [
    YorksV1BoqColumn(
      id: 'import-description',
      heading: 'Item Description',
      displayOrder: 1,
    ),
    YorksV1BoqColumn(
      id: 'import-unit-cost',
      heading: 'Unit Cost',
      displayOrder: 2,
    ),
    YorksV1BoqColumn(
      id: 'import-operating-cost-index',
      heading: 'Operating Cost Index',
      displayOrder: 3,
    ),
  ],
  rows: [
    YorksV1BoqRow(
      id: 'commercial-import-row',
      displayOrder: 1,
      values: {
        'import-description': 'Fresh Air Handling Unit',
        'import-unit-cost': '125.50',
        'import-operating-cost-index': 'OCI-7',
      },
      canonicalValues: {},
    ),
  ],
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

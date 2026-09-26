import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/projects/presentation/screens/yorks_v1_boq_screens.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_boq_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_boq_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_recovery_store.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Yorks V1 BOQ worksheet controller', () {
    test(
      'inserts blank and similar rows directly below the active row',
      () async {
        final repository = _FakeBoqRepository(_worksheet());
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        final similar = controller.addSimilarRow(sourceRowId: _rowId);
        final blank = controller.addBlankRow(afterRowId: similar.id);

        final rows = controller.state.worksheet!.rows;
        expect(rows.map((row) => row.id), [_rowId, similar.id, blank.id]);
        expect(similar.valueFor(_columnId), 'Motorized Smoke Damper');
        expect(blank.values, isEmpty);
        expect(rows.map((row) => row.displayOrder), [1, 2, 3]);
        expect(controller.state.hasUnsavedChanges, isTrue);
      },
    );

    test(
      'pastes multiple cells and appended rows as one undoable edit',
      () async {
        final source = _worksheet().copyWith(
          columns: const [
            YorksV1BoqColumn(
              id: _columnId,
              heading: 'Item Description',
              displayOrder: 1,
              canonicalField: YorksV1BoqCanonicalField.description,
            ),
            YorksV1BoqColumn(
              id: 'technical',
              heading: 'Technical',
              displayOrder: 2,
            ),
          ],
        );
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: _FakeBoqRepository(source),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);
        await controller.load();

        controller.pasteCells(
          startRowId: _rowId,
          columnIds: const [_columnId, 'technical'],
          values: const [
            ['Air damper', '500 x 500'],
            ['Fire damper', '600 x 600'],
          ],
        );
        expect(controller.state.worksheet!.rows, hasLength(2));
        expect(
          controller.state.worksheet!.rows.first.valueFor(_columnId),
          'Air damper',
        );
        expect(
          controller.state.worksheet!.rows.last.valueFor('technical'),
          '600 x 600',
        );
        expect(
          controller.state.worksheet!.rows.first.canonicalValues['description'],
          'Air damper',
        );

        controller.undo();
        expect(controller.state.worksheet!.rows, hasLength(1));
        expect(
          controller.state.worksheet!.rows.single.valueFor(_columnId),
          'Motorized Smoke Damper',
        );
      },
    );

    test(
      'Similar Row keeps reusable context and clears unique equipment data',
      () async {
        final source = _worksheet().copyWith(
          columns: const [
            YorksV1BoqColumn(
              id: 'description',
              heading: 'Description',
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
              id: 'make',
              heading: 'Make',
              displayOrder: 3,
              canonicalField: YorksV1BoqCanonicalField.brandOrigin,
            ),
            YorksV1BoqColumn(
              id: 'unit',
              heading: 'Unit',
              displayOrder: 4,
              canonicalField: YorksV1BoqCanonicalField.unit,
            ),
            YorksV1BoqColumn(
              id: 'tag',
              heading: 'Tag No.',
              displayOrder: 5,
              canonicalField: YorksV1BoqCanonicalField.equipmentTag,
            ),
            YorksV1BoqColumn(
              id: 'model',
              heading: 'Model',
              displayOrder: 6,
              canonicalField: YorksV1BoqCanonicalField.model,
            ),
            YorksV1BoqColumn(
              id: 'qty',
              heading: 'Qty',
              displayOrder: 7,
              canonicalField: YorksV1BoqCanonicalField.quantity,
            ),
            YorksV1BoqColumn(id: 'mass', heading: 'MASS', displayOrder: 8),
            YorksV1BoqColumn(id: 'status', heading: 'STATUS', displayOrder: 9),
            YorksV1BoqColumn(
              id: 'cost',
              heading: 'Unit Cost',
              displayOrder: 10,
            ),
          ],
          rows: [
            YorksV1BoqRow(
              id: _rowId,
              displayOrder: 1,
              values: const {
                'description': 'Smoke damper',
                'size': '600 x 600',
                'make': 'Yorks',
                'unit': 'Nos',
                'tag': 'MSD-01',
                'model': 'M-600',
                'qty': '1',
                'mass': 'MTS-1',
                'status': 'AP',
                'cost': '100',
              },
              canonicalValues: const {
                'description': 'Smoke damper',
                'size': '600 x 600',
                'brand_origin': 'Yorks',
                'unit': 'Nos',
                'equipment_tag': 'MSD-01',
                'model': 'M-600',
                'quantity': '1',
              },
            ),
          ],
        );
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: _FakeBoqRepository(source),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        final similar = controller.addSimilarRow(sourceRowId: _rowId);

        expect(similar.values, {
          'description': 'Smoke damper',
          'size': '600 x 600',
          'make': 'Yorks',
          'unit': 'Nos',
        });
        expect(similar.canonicalValues, {
          'description': 'Smoke damper',
          'size': '600 x 600',
          'brand_origin': 'Yorks',
          'unit': 'Nos',
        });
      },
    );

    test(
      'keeps raw arbitrary values while saving a version-checked snapshot',
      () async {
        final repository = _FakeBoqRepository(_worksheet());
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        controller.addColumn(heading: 'Air flow (L/s)');
        final newColumn = controller.state.worksheet!.columns.last;
        controller.updateCell(
          rowId: _rowId,
          columnId: newColumn.id,
          value: '708',
        );

        expect(await controller.save(), isTrue);
        final submitted = repository.saved.single;
        expect(submitted.expectedVersion, 1);
        expect(submitted.worksheet.rows.single.valueFor(newColumn.id), '708');
        expect(controller.state.status, YorksV1BoqSyncStatus.saved);
      },
    );

    test(
      'edits canonical cells and archives omitted rows and columns on save',
      () async {
        final repository = _FakeBoqRepository(_worksheet());
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        controller.updateCell(
          rowId: _rowId,
          columnId: _columnId,
          value: 'Updated damper',
        );
        final extra = controller.addBlankRow(afterRowId: _rowId);
        controller.removeRow(extra.id);
        controller.removeColumn(_columnId);

        expect(controller.state.worksheet!.rows.single.canonicalValues, {
          'description': 'Updated damper',
        });
        expect(await controller.save(), isTrue);
        expect(repository.saved.single.worksheet.rows, hasLength(1));
        expect(repository.saved.single.worksheet.columns, isEmpty);
      },
    );

    test(
      'material selection fills mapped details once and preserves quantity',
      () async {
        final source = _worksheet().copyWith(
          columns: const [
            YorksV1BoqColumn(
              id: 'description',
              heading: 'Description',
              displayOrder: 1,
              canonicalField: YorksV1BoqCanonicalField.description,
            ),
            YorksV1BoqColumn(
              id: 'brand',
              heading: 'Brand / Origin',
              displayOrder: 2,
              canonicalField: YorksV1BoqCanonicalField.brandOrigin,
            ),
            YorksV1BoqColumn(
              id: 'model',
              heading: 'Model',
              displayOrder: 3,
              canonicalField: YorksV1BoqCanonicalField.model,
            ),
            YorksV1BoqColumn(
              id: 'quantity',
              heading: 'Quantity',
              displayOrder: 4,
              canonicalField: YorksV1BoqCanonicalField.quantity,
            ),
            YorksV1BoqColumn(
              id: 'unit',
              heading: 'Unit',
              displayOrder: 5,
              canonicalField: YorksV1BoqCanonicalField.unit,
            ),
          ],
          rows: [
            YorksV1BoqRow(
              id: _rowId,
              displayOrder: 1,
              values: const {
                'description': '',
                'brand': '',
                'model': '',
                'quantity': '25',
                'unit': 'Nos',
              },
              canonicalValues: const {'quantity': '25', 'unit': 'Nos'},
            ),
          ],
        );
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: _FakeBoqRepository(source),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        controller.updateMaterialCells(
          rowId: _rowId,
          values: const {
            YorksV1BoqCanonicalField.description: 'Motorized Smoke Damper',
            YorksV1BoqCanonicalField.brandOrigin: 'Yorks UAE',
            YorksV1BoqCanonicalField.model: 'MSD-500',
            YorksV1BoqCanonicalField.unit: 'Set',
          },
        );

        final row = controller.state.worksheet!.rows.single;
        expect(row.valueFor('description'), 'Motorized Smoke Damper');
        expect(row.valueFor('brand'), 'Yorks UAE');
        expect(row.valueFor('model'), 'MSD-500');
        expect(row.valueFor('unit'), 'Set');
        expect(row.valueFor('quantity'), '25');
        expect(row.canonicalValues['quantity'], '25');
        expect(controller.state.hasUnsavedChanges, isTrue);
      },
    );

    test(
      'keeps local edits visible when the server reports a conflict',
      () async {
        final repository = _FakeBoqRepository(
          _worksheet(),
          conflictOnSave: true,
        );
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        controller.updateTitle('Changed by this editor');

        expect(await controller.save(), isFalse);
        expect(controller.state.status, YorksV1BoqSyncStatus.conflict);
        expect(
          controller.state.worksheet!.group.worksheetTitle,
          'Changed by this editor',
        );
      },
    );

    test(
      'commits a reviewed workbook preview as a new worksheet revision',
      () async {
        final repository = _FakeBoqRepository(_worksheet());
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.load();
        final preview = YorksV1BoqImportPreview(
          fileName: 'MSD Equipment Schedule.xlsx',
          worksheetName: 'MSD Schedule',
          title: 'Imported MSD Equipment Schedule',
          headerRowIndex: 2,
          columns: const [
            YorksV1BoqImportColumn(
              sourceIndex: 0,
              heading: 'Item Description',
              canonicalField: YorksV1BoqCanonicalField.description,
            ),
            YorksV1BoqImportColumn(sourceIndex: 1, heading: 'Air flow (L/s)'),
          ],
          rows: [
            YorksV1BoqImportRow(
              sourceRowNumber: 4,
              values: const {0: 'Motorized Smoke Damper', 1: '708'},
            ),
          ],
          validationIssues: const [],
        );

        expect(await controller.importWorkbook(preview), isTrue);
        final imported = repository.saved.last.worksheet;
        expect(
          imported.group.worksheetTitle,
          'Imported MSD Equipment Schedule',
        );
        expect(imported.columns.map((column) => column.heading), [
          'Item Description',
          'Air flow (L/s)',
        ]);
        expect(imported.rows.single.valueFor(imported.columns.last.id), '708');
      },
    );

    test(
      'protects dirty work from an unconfirmed reload and supports undo',
      () async {
        final repository = _FakeBoqRepository(_worksheet());
        final controller = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        expect(await controller.load(), isTrue);
        controller.updateTitle('Local title');
        expect(controller.canUndo, isTrue);
        expect(await controller.load(), isFalse);
        expect(repository.getCalls, 1);
        expect(controller.state.worksheet!.group.worksheetTitle, 'Local title');

        controller.undo();
        expect(
          controller.state.worksheet!.group.worksheetTitle,
          'Damper Schedule',
        );
        expect(controller.canRedo, isTrue);
        controller.redo();
        expect(controller.state.worksheet!.group.worksheetTitle, 'Local title');
      },
    );

    test(
      'recovery restores operational edits and rejoins authorized commercial data',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final store = YorksV1BoqRecoveryStore(
          preferences: preferences,
          ownerAuthUserId: 'engineer-1',
        );
        final source = _worksheet().copyWith(
          columns: const [
            YorksV1BoqColumn(
              id: _columnId,
              heading: 'Item Description',
              displayOrder: 1,
              canonicalField: YorksV1BoqCanonicalField.description,
            ),
            YorksV1BoqColumn(
              id: 'unit-cost',
              heading: 'Unit Cost',
              displayOrder: 2,
              canonicalField: YorksV1BoqCanonicalField.unitCost,
              isCommercial: true,
            ),
          ],
          rows: [
            YorksV1BoqRow(
              id: _rowId,
              displayOrder: 1,
              values: const {
                _columnId: 'Motorized Smoke Damper',
                'unit-cost': '150',
              },
              canonicalValues: const {
                'description': 'Motorized Smoke Damper',
                'unit_cost': '150',
              },
            ),
          ],
        );
        final first = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: _FakeBoqRepository(source),
          recoveryStore: store,
          uuidFactory: _Ids().next,
        );
        addTearDown(first.dispose);
        await first.load();
        first.updateCell(
          rowId: _rowId,
          columnId: _columnId,
          value: 'Recovered damper',
        );
        await store.save(first.state.worksheet!);

        final repository = _FakeBoqRepository(source);
        final recovered = YorksV1BoqWorksheetController(
          groupId: _groupId,
          repository: repository,
          recoveryStore: store,
          canManageCommercials: true,
          uuidFactory: _Ids().next,
        );
        addTearDown(recovered.dispose);

        expect(await recovered.load(), isTrue);
        expect(recovered.state.recoveredLocally, isTrue);
        expect(recovered.state.status, YorksV1BoqSyncStatus.dirty);
        expect(recovered.state.worksheet!.columns, hasLength(2));
        expect(
          recovered.state.worksheet!.rows.single.valueFor('unit-cost'),
          '150',
        );
        expect(
          recovered.state.worksheet!.rows.single.valueFor(_columnId),
          'Recovered damper',
        );
        expect(await recovered.save(), isTrue);
        expect(repository.saved.single.worksheet.columns, hasLength(2));
      },
    );

    test('view-only users cannot mutate commercial worksheet fields', () async {
      final source = _worksheet().copyWith(
        columns: const [
          YorksV1BoqColumn(
            id: 'unit-cost',
            heading: 'Unit Cost',
            displayOrder: 1,
            canonicalField: YorksV1BoqCanonicalField.unitCost,
            isCommercial: true,
          ),
        ],
      );
      final controller = YorksV1BoqWorksheetController(
        groupId: _groupId,
        repository: _FakeBoqRepository(source),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(
        () => controller.updateCell(
          rowId: _rowId,
          columnId: 'unit-cost',
          value: '99',
        ),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.unauthorized,
          ),
        ),
      );
      expect(
        () => controller.pasteCells(
          startRowId: _rowId,
          columnIds: const ['unit-cost'],
          values: const [
            ['99'],
          ],
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(
        () => controller.removeColumn('unit-cost'),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(
        () => controller.addColumn(
          heading: 'Total Cost',
          canonicalField: YorksV1BoqCanonicalField.totalCost,
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
    });

    test('rejects duplicate visible headings and canonical mappings', () async {
      final controller = YorksV1BoqWorksheetController(
        groupId: _groupId,
        repository: _FakeBoqRepository(_worksheet()),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(
        () => controller.addColumn(heading: ' item description '),
        throwsA(isA<YorksV1DomainException>()),
      );
      expect(
        () => controller.addColumn(
          heading: 'Description 2',
          canonicalField: YorksV1BoqCanonicalField.description,
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
    });

    test('uses local recovery when the server is unavailable', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = YorksV1BoqRecoveryStore(
        preferences: preferences,
        ownerAuthUserId: 'engineer-2',
      );
      await store.save(_worksheet());
      final controller = YorksV1BoqWorksheetController(
        groupId: _groupId,
        repository: _FakeBoqRepository(_worksheet(), unexpectedOnLoad: true),
        recoveryStore: store,
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      expect(await controller.load(), isTrue);
      expect(controller.state.recoveredLocally, isTrue);
      expect(
        controller.state.errorCode,
        YorksV1DomainErrorCode.backendUnavailable,
      );
      expect(controller.state.worksheet!.rows, hasLength(1));
    });
  });

  group('Yorks V1 BOQ XLSX codec', () {
    const codec = YorksV1BoqWorkbookCodec();

    test('exports, imports and previews arbitrary headings and row values', () {
      final original = _worksheet().copyWith(
        columns: const [
          YorksV1BoqColumn(
            id: _columnId,
            heading: 'Item Description',
            displayOrder: 1,
            canonicalField: YorksV1BoqCanonicalField.description,
          ),
          YorksV1BoqColumn(
            id: '10000000-0000-4000-8000-000000000014',
            heading: 'Air flow (L/s)',
            displayOrder: 2,
          ),
        ],
        rows: [
          YorksV1BoqRow(
            id: _rowId,
            displayOrder: 1,
            values: const {
              _columnId: 'Motorized Smoke Damper',
              '10000000-0000-4000-8000-000000000014': '708',
            },
            canonicalValues: const {'description': 'Motorized Smoke Damper'},
          ),
        ],
      );

      final workbook = codec.decode(
        bytes: codec.encodeWorksheet(original),
        fileName: 'MSD Equipment Schedule.xlsx',
      );
      final preview = codec.preview(
        workbook: workbook,
        sheet: workbook.sheets.single,
        fallbackTitle: 'Fallback',
      );

      expect(preview.title, 'Damper Schedule');
      expect(preview.headerRowNumber, 2);
      expect(preview.columns.map((column) => column.heading), [
        'Item Description',
        'Air flow (L/s)',
      ]);
      expect(preview.rows.single.valueFor(1), '708');
      expect(preview.isValid, isTrue);
    });

    test('exports a project workbook with one worksheet per BOQ group', () {
      final first = _worksheet();
      final second = _worksheet().copyWith(
        group: YorksV1BoqGroup(
          id: '10000000-0000-4000-8000-000000000099',
          projectId: first.group.projectId,
          name: 'Ventilation Fans',
          worksheetTitle: 'Ventilation Fans',
          displayOrder: 2,
          isCustom: false,
          isArchived: false,
          version: 1,
          rowCount: first.group.rowCount,
          columnCount: first.group.columnCount,
          updatedAt: first.group.updatedAt,
        ),
      );

      final workbook = codec.decode(
        bytes: codec.encodeWorksheets([first, second]),
        fileName: 'Yorks_BOQ.xlsx',
      );

      expect(workbook.sheets.map((sheet) => sheet.name), [
        'Damper Schedule',
        'Ventilation Fans',
      ]);
      expect(workbook.sheets.first.rows, isNotEmpty);
      expect(workbook.sheets.last.rows, isNotEmpty);
    });

    test('flags blank and duplicate headings before an import command', () {
      final workbook = YorksV1BoqParsedWorkbook(
        fileName: 'invalid.xlsx',
        sheets: [
          YorksV1BoqWorkbookSheet(
            name: 'BOQ',
            rows: const [
              ['Damper Schedule'],
              ['Description', '', 'description'],
              ['MSD', '708', 'MSD-01'],
            ],
          ),
        ],
      );
      final preview = codec.preview(
        workbook: workbook,
        sheet: workbook.sheets.single,
        fallbackTitle: 'Fallback',
        headerRowIndex: 1,
      );

      expect(preview.isValid, isFalse);
      expect(
        preview.validationIssues.map((issue) => issue.code),
        containsAll([
          YorksV1BoqImportValidationCode.blankHeading,
          YorksV1BoqImportValidationCode.duplicateHeading,
        ]),
      );
    });

    test('imports a two-level Package Unit header without blank headings', () {
      final workbook = YorksV1BoqParsedWorkbook(
        fileName: 'Equipment Schedule.xlsx',
        sheets: [
          YorksV1BoqWorkbookSheet(
            name: 'Package Unit',
            rows: [
              List<String>.filled(22, ''),
              [
                '',
                'PACKAGE UNIT SCHEDULE',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
              ],
              [
                '',
                'S: No',
                'Unit Refrence',
                'PU-TAG',
                'Model',
                'T. Cooling Capacity (KW)',
                '',
                'S. Cooling Capacity (KW)',
                '',
                'Air Flow (L/s)',
                '',
                'ESP',
                '',
                'Electrical Details',
                'Total Power Input (Kw)',
                'Dimension (LxWxH)',
                'QTY',
                'Make',
                'Mass No',
                'Material Status',
                'Remarks',
              ],
              [
                '',
                '',
                '',
                '',
                '',
                'Calculated',
                'Selected',
                'Calculated',
                'Selected',
                'Calculated',
                'Selected',
                'Calculated',
                'Selected',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
              ],
              [
                '',
                '1',
                'SYSTEM-01',
                'PU-01A',
                'AMPR52052AM',
                '148.8',
                '148.8',
                '106.9',
                '108.3',
                '4972',
                '4972',
                '500',
                '500',
                '415/3/50',
                '75.4',
                '4406 x 2235 x 3630',
                '3',
                'SKM/UAE',
                'MTS-CS-0220',
                'AP',
                '2 duty / 1 standby',
              ],
            ],
          ),
        ],
      );

      final preview = codec.preview(
        workbook: workbook,
        sheet: workbook.sheets.single,
        fallbackTitle: 'Fallback',
      );

      expect(preview.title, 'PACKAGE UNIT SCHEDULE');
      expect(preview.headerRowIndexes, [2, 3]);
      expect(preview.headerRowNumber, 3);
      expect(preview.headerRowNumbers, [3, 4]);
      expect(preview.columns, hasLength(20));
      expect(
        preview.columns.map((column) => column.heading),
        containsAll([
          'T. Cooling Capacity (KW) — Calculated',
          'T. Cooling Capacity (KW) — Selected',
          'Air Flow (L/s) — Calculated',
          'Air Flow (L/s) — Selected',
        ]),
      );
      expect(
        preview.columns.map((column) => column.heading),
        isNot(contains('')),
      );
      expect(preview.headerHierarchy, hasLength(preview.columns.length));
      expect(preview.rows.single.sourceRowNumber, 5);
      expect(preview.rows.single.valueFor(6), '148.8');
      expect(preview.isValid, isTrue);
    });

    test(
      'retains the widest source boundary for sparse equipment schedules',
      () {
        final workbook = YorksV1BoqParsedWorkbook(
          fileName: 'Equipment Schedule.xlsx',
          sheets: [
            _equipmentScheduleSheet(
              name: 'MSD',
              title: 'MOTORIZED SMOKE DAMPER-(MSD)',
              headings: const [
                'TAG NO',
                'SIZE (mm x mm)',
                'SLAB/WALL',
                'DESCRIPTION',
                'MAKE',
                'MASS',
                'STATUS',
              ],
              dataRows: [
                const [
                  'MSD-01A',
                  '600 x 600',
                  'Slab-GF',
                  'Stair-5',
                  'BeteccadUAE',
                  'MTS-0190',
                  'AP',
                ],
                for (var index = 2; index <= 22; index++)
                  [
                    'MSD-${index.toString().padLeft(2, '0')}',
                    '450x450',
                    'Slab-FF',
                    'Smoke damper $index',
                    'BeteccadUAE',
                    '',
                    '',
                  ],
              ],
            ),
            _equipmentScheduleSheet(
              name: 'VCD',
              title: 'VOLUME CONTROL DAMPER - (VCD)',
              headings: const [
                'TAG NO',
                'SIZE (mm x mm)',
                'LOCATION',
                'DESCRIPTION',
                'MAKE',
                'REMARKS',
                'MASS',
                'STATUS',
              ],
              dataRows: const [
                [
                  'VCD-01',
                  '1100c450',
                  'Basement',
                  'Fresh-air damper',
                  'LEMINAR',
                  'FIRE RATED',
                  'MTS-0210',
                  'AP',
                ],
                [
                  'VCD-02',
                  '1200 x 600',
                  'Basement',
                  'Extract-air damper',
                  'LEMINAR',
                  '',
                  '',
                  '',
                ],
              ],
            ),
            _equipmentScheduleSheet(
              name: 'SAR',
              title: 'SUPPLY AIR REGISTER - (SAR)',
              headings: const [
                'TAG NO',
                'SIZE (mm x mm)',
                'LOCATION',
                'DESCRIPTION',
                'AIR FLOW (L/S)',
                'MAKE',
                'MASS',
                'STATUS',
              ],
              dataRows: const [
                [
                  'SAR-01-04',
                  '1000 x 350',
                  'Basement',
                  'Supply Air Register',
                  '708',
                  'BETA/UAE',
                  'MTS-0063',
                  'AP',
                ],
                [
                  'SAR-05-08',
                  '900 x 300',
                  'Basement',
                  'Supply Air Register',
                  '502',
                  'BETA/UAE',
                  '',
                  '',
                ],
              ],
            ),
            _equipmentScheduleSheet(
              name: 'VENT.FAN',
              title: 'VENTILATION/EXTRACT FAN SCHEDULE',
              headings: const [
                'Fan Tag#',
                'Specified Air Flow (L/s)',
                'Specified ESP (Pa)',
                'Serving Area',
                'Model',
                'Offered Air Flow (L/s)',
                'Offered ESP (Pa)',
                'Fan RPM',
                'Motor Power',
                'Full Load Amps',
                'Voltage',
                'Phase',
                'Hz',
                'Motor Enclosure/Class',
                'Fan Make',
                'Sound dB(A)',
                'Fan Qty',
                'MASS',
                'STATUS',
              ],
              dataRows: const [
                [
                  'BSEF-1A & 1B',
                  '3329',
                  '226',
                  'Basement Zone-1',
                  'TA-HT-560',
                  '3395',
                  '235',
                  '2880',
                  '3 kW',
                  '5.57 A',
                  '415',
                  '3',
                  '50',
                  'IP55/H',
                  'DYNAIR',
                  '76',
                  '2',
                  'MTS-0254',
                  'AEN',
                ],
                [
                  'FPR-EF-02',
                  '413',
                  '140',
                  'Fire Pump Room',
                  'TA-HT-450',
                  '511',
                  '233',
                  '2880',
                  '0.55 kW',
                  '1.29 A',
                  '415',
                  '3',
                  '50',
                  'IP55/F',
                  'DYNAIR',
                  '68',
                  '1',
                  '',
                  '',
                ],
              ],
            ),
            _packageUnitScheduleSheet(),
          ],
        );

        final previews = {
          for (final sheet in workbook.sheets)
            sheet.name: codec.preview(
              workbook: workbook,
              sheet: sheet,
              fallbackTitle: sheet.name,
            ),
        };

        final msd = previews['MSD']!;
        expect(msd.columns, hasLength(7));
        expect(msd.rows, hasLength(22));
        expect(
          msd.columns.map((column) => column.heading).toList().sublist(5),
          ['MASS', 'STATUS'],
        );
        expect(msd.rows.first.valueFor(5), 'MTS-0190');
        expect(msd.rows.first.valueFor(6), 'AP');

        final vcd = previews['VCD']!;
        expect(vcd.columns, hasLength(8));
        expect(vcd.rows.first.valueFor(1), '1100c450');

        expect(previews['SAR']!.columns, hasLength(8));
        expect(previews['VENT.FAN']!.columns, hasLength(19));

        final packageUnit = previews['Package Unit']!;
        expect(packageUnit.headerRowNumbers, [3, 4]);
        expect(packageUnit.columns, hasLength(20));
        expect(
          packageUnit.columns.map((column) => column.heading),
          contains('ESP — Selected'),
        );
      },
    );

    test('rejects malformed non-XLSX bytes', () {
      expect(
        () => codec.decode(
          bytes: Uint8List.fromList(const [1, 2, 3]),
          fileName: 'not-a-workbook.xlsx',
        ),
        throwsA(isA<YorksV1DomainException>()),
      );
    });
  });

  group('Yorks V1 responsive BOQ spreadsheet', () {
    testWidgets('uses a focused mobile row editor at 360px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_spreadsheetHarness(size: const Size(360, 700)));

      expect(
        find.byKey(const ValueKey('yorks-v1-boq-mobile-list')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mobile-boq-row-$_rowId')));
      await tester.pumpAndSettle();

      expect(find.text('Edit row 1'), findsOneWidget);
      expect(find.text('Item Description'), findsWidgets);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a virtualized desktop grid usable with 500 rows', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = _worksheet();
      final worksheet = base.copyWith(
        rows: List.generate(
          500,
          (index) => YorksV1BoqRow(
            id: 'row-$index',
            displayOrder: index + 1,
            values: {_columnId: 'Damper ${index + 1}'},
            canonicalValues: const {},
          ),
        ),
      );
      await tester.pumpWidget(_spreadsheetHarness(worksheet: worksheet));

      expect(
        find.byKey(const ValueKey('yorks-v1-boq-desktop-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('boq-cell-row-0-$_columnId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('boq-cell-row-499-$_columnId')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('boq-add-row-footer')), findsOneWidget);
      expect(find.byType(PaginatedDataTable), findsNothing);
      await tester.tap(find.byKey(const ValueKey('boq-cell-row-0-$_columnId')));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'row-1:$_columnId',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'row-0:$_columnId',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('boq-cell-row-499-$_columnId')),
        1000,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('boq-body-list')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      expect(
        find.byKey(const ValueKey('boq-cell-row-499-$_columnId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab crosses editable columns and rows without paging', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final worksheet = _worksheet().copyWith(
        columns: const [
          YorksV1BoqColumn(
            id: _columnId,
            heading: 'Item Description',
            displayOrder: 1,
            canonicalField: YorksV1BoqCanonicalField.description,
          ),
          YorksV1BoqColumn(
            id: 'quantity',
            heading: 'Quantity',
            displayOrder: 2,
            canonicalField: YorksV1BoqCanonicalField.quantity,
          ),
        ],
        rows: [
          ..._worksheet().rows,
          YorksV1BoqRow(
            id: 'row-2',
            displayOrder: 2,
            values: {},
            canonicalValues: {},
          ),
        ],
      );
      await tester.pumpWidget(_spreadsheetHarness(worksheet: worksheet));
      await tester.tap(
        find.byKey(const ValueKey('boq-cell-$_rowId-$_columnId')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '$_rowId:quantity',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'row-2:$_columnId',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '$_rowId:quantity',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop clipboard paste starts at the selected cell', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'Dampers\t500 x 500\nValves\t600 x 600'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      List<List<String>>? pasted;
      String? pastedRow;
      List<String>? pastedColumns;
      final worksheet = _worksheet().copyWith(
        columns: const [
          YorksV1BoqColumn(
            id: _columnId,
            heading: 'Item Description',
            displayOrder: 1,
            canonicalField: YorksV1BoqCanonicalField.description,
          ),
          YorksV1BoqColumn(
            id: 'technical',
            heading: 'Technical',
            displayOrder: 2,
          ),
        ],
      );
      await tester.pumpWidget(
        _spreadsheetHarness(
          worksheet: worksheet,
          onPasteCells:
              ({required startRowId, required columnIds, required values}) {
                pastedRow = startRowId;
                pastedColumns = columnIds;
                pasted = values;
              },
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('boq-cell-$_rowId-$_columnId')),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(pastedRow, _rowId);
      expect(pastedColumns, [_columnId, 'technical']);
      expect(pasted, [
        ['Dampers', '500 x 500'],
        ['Valves', '600 x 600'],
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('commits a desktop cell only after blur or Enter', (
      tester,
    ) async {
      final updates = <String>[];
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _spreadsheetHarness(
          onUpdateCell: ({required rowId, required columnId, required value}) {
            updates.add('$rowId:$columnId:$value');
          },
        ),
      );

      final cell = find.byKey(const ValueKey('boq-cell-$_rowId-$_columnId'));
      await tester.tap(cell);
      await tester.enterText(cell, 'Edited smoke damper');
      await tester.pump();
      expect(updates, isEmpty);

      await tester.tap(find.byKey(const ValueKey('boq-column-$_columnId')));
      await tester.pump();
      expect(updates, ['$_rowId:$_columnId:Edited smoke damper']);
    });

    testWidgets('desktop description autocomplete selects a safe material', (
      tester,
    ) async {
      YorksV1MaterialRequestInventorySuggestion? selected;
      String? selectedRowId;
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _spreadsheetHarness(
          onSearchMaterials: (query, excludedRowId) async {
            expect(query, 'smart');
            expect(excludedRowId, _rowId);
            return const [_smartDamperSuggestion];
          },
          onApplyMaterialSuggestion: (rowId, suggestion) {
            selectedRowId = rowId;
            selected = suggestion;
          },
        ),
      );

      final cell = find.byKey(const ValueKey('boq-cell-$_rowId-$_columnId'));
      await tester.enterText(cell, 'sm');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(cell, 'smart');
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pumpAndSettle();

      expect(find.text('Smart Damper'), findsOneWidget);
      await tester.tap(find.text('Smart Damper'));
      await tester.pumpAndSettle();
      expect(selectedRowId, _rowId);
      expect(selected, same(_smartDamperSuggestion));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile autocomplete fills details but preserves quantity', (
      tester,
    ) async {
      final updates = <String, String>{};
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _spreadsheetHarness(
          worksheet: _materialWorksheet(),
          size: const Size(360, 700),
          onSearchMaterials: (_, excludedRowId) async {
            expect(excludedRowId, _rowId);
            return const [_smartDamperSuggestion];
          },
          onUpdateCell: ({required rowId, required columnId, required value}) {
            updates[columnId] = value;
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('mobile-boq-row-$_rowId')));
      await tester.pumpAndSettle();
      final description = find.byKey(
        const ValueKey('mobile-boq-description-$_rowId'),
      );
      await tester.enterText(
        find.descendant(of: description, matching: find.byType(TextFormField)),
        'smart',
      );
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart Damper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(updates['description'], 'Smart Damper');
      expect(updates['brand'], 'Yorks UAE');
      expect(updates['unit'], 'Set');
      expect(updates['quantity'], '25');
      expect(tester.takeException(), isNull);
    });
  });
}

const _projectId = '10000000-0000-4000-8000-000000000010';
const _groupId = '10000000-0000-4000-8000-000000000011';
const _rowId = '10000000-0000-4000-8000-000000000012';
const _columnId = '10000000-0000-4000-8000-000000000013';
const _smartDamperSuggestion = YorksV1MaterialRequestInventorySuggestion(
  id: 'inventory-smart-damper',
  source: YorksV1MaterialRequestSuggestionSource.inventory,
  itemCode: 'INV-001',
  description: 'Smart Damper',
  brandOrigin: 'Yorks UAE',
  size: '500 x 500',
  model: 'SD-500',
  unit: 'Set',
);

YorksV1BoqWorksheet _materialWorksheet() => _worksheet().copyWith(
  columns: const [
    YorksV1BoqColumn(
      id: 'description',
      heading: 'Item Description',
      displayOrder: 1,
      canonicalField: YorksV1BoqCanonicalField.description,
    ),
    YorksV1BoqColumn(
      id: 'brand',
      heading: 'Brand / Origin',
      displayOrder: 2,
      canonicalField: YorksV1BoqCanonicalField.brandOrigin,
    ),
    YorksV1BoqColumn(
      id: 'quantity',
      heading: 'Quantity',
      displayOrder: 3,
      canonicalField: YorksV1BoqCanonicalField.quantity,
    ),
    YorksV1BoqColumn(
      id: 'unit',
      heading: 'Unit',
      displayOrder: 4,
      canonicalField: YorksV1BoqCanonicalField.unit,
    ),
  ],
  rows: [
    YorksV1BoqRow(
      id: _rowId,
      displayOrder: 1,
      values: const {
        'description': '',
        'brand': '',
        'quantity': '25',
        'unit': 'Nos',
      },
      canonicalValues: const {'quantity': '25', 'unit': 'Nos'},
    ),
  ],
);

YorksV1BoqWorksheet _worksheet() {
  return YorksV1BoqWorksheet(
    group: YorksV1BoqGroup(
      id: _groupId,
      projectId: _projectId,
      name: 'MFD, MSFD, MSD, MVCD & VCD',
      worksheetTitle: 'Damper Schedule',
      displayOrder: 3,
      isCustom: false,
      isArchived: false,
      version: 1,
      rowCount: 1,
      columnCount: 1,
      updatedAt: DateTime.utc(2026, 8, 2),
    ),
    columns: const [
      YorksV1BoqColumn(
        id: _columnId,
        heading: 'Item Description',
        displayOrder: 1,
        canonicalField: YorksV1BoqCanonicalField.description,
      ),
    ],
    rows: [
      YorksV1BoqRow(
        id: _rowId,
        displayOrder: 1,
        values: const {_columnId: 'Motorized Smoke Damper'},
        canonicalValues: const {'description': 'Motorized Smoke Damper'},
      ),
    ],
  );
}

YorksV1BoqWorkbookSheet _equipmentScheduleSheet({
  required String name,
  required String title,
  required List<String> headings,
  required List<List<String>> dataRows,
}) => YorksV1BoqWorkbookSheet(
  name: name,
  rows: [title.split('|'), headings, ...dataRows],
);

YorksV1BoqWorkbookSheet _packageUnitScheduleSheet() => YorksV1BoqWorkbookSheet(
  name: 'Package Unit',
  rows: const [
    [],
    ['', 'PACKAGE UNIT SCHEDULE'],
    [
      '',
      'S: No',
      'Unit Refrence',
      'PU-TAG',
      'Model',
      'T. Cooling Capacity (KW)',
      '',
      'S. Cooling Capacity (KW)',
      '',
      'Air Flow (L/s)',
      '',
      'ESP',
      '',
      'Electrical Details',
      'Total Power Input (Kw)',
      'Dimension (LxWxH)',
      'QTY',
      'Make',
      'Mass No',
      'Material Status',
      'Remarks',
    ],
    [
      '',
      '',
      '',
      '',
      '',
      'Calculated',
      'Selected',
      'Calculated',
      'Selected',
      'Calculated',
      'Selected',
      'Calculated',
      'Selected',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
    ],
    [
      '',
      '1',
      'SYSTEM-01',
      'PU-01A',
      'AMPR52052AM',
      '148.8',
      '148.8',
      '106.9',
      '108.3',
      '4972',
      '4972',
      '500',
      '500',
      '415/3/50',
      '75.4',
      '4406 x 2235 x 3630',
      '3',
      'SKM/UAE',
      'MTS-CS-0220',
      'AP',
      '2 duty / 1 standby',
    ],
    [
      '',
      '2',
      'SYSTEM-01',
      'PU-02A',
      'AMPR52052AM',
      '151.5',
      '158',
      '119.3',
      '122.4',
      '6698',
      '6698',
      '578',
      '600',
      '415/3/50',
      '80',
      '4406 x 2235 x 3630',
      '3',
      '',
      '',
      '',
      '2 duty / 1 standby',
    ],
  ],
);

Widget _spreadsheetHarness({
  YorksV1BoqWorksheet? worksheet,
  Size size = const Size(1200, 700),
  void Function({
    required String rowId,
    required String columnId,
    required String value,
  })?
  onUpdateCell,
  void Function({
    required String? startRowId,
    required List<String> columnIds,
    required List<List<String>> values,
  })?
  onPasteCells,
  Future<List<YorksV1MaterialRequestInventorySuggestion>> Function(
    String query,
    String? excludedRowId,
  )?
  onSearchMaterials,
  void Function(
    String rowId,
    YorksV1MaterialRequestInventorySuggestion suggestion,
  )?
  onApplyMaterialSuggestion,
}) {
  final effective = worksheet ?? _worksheet();
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: YorksV1BoqSpreadsheet(
          worksheet: effective,
          editable: true,
          showEditActions: true,
          onSearchMaterials: onSearchMaterials,
          onApplyMaterialSuggestion: onApplyMaterialSuggestion,
          onUpdateCell:
              onUpdateCell ??
              ({required rowId, required columnId, required value}) {},
          onPasteCells: onPasteCells,
          onAddBlankRow: ({afterRowId}) => effective.rows.first,
          onAddSimilarRow: ({required sourceRowId}) => effective.rows.first,
          onRemoveRow: (_) {},
          onAddColumn: ({required heading, canonicalField}) {},
          onRenameColumn: (_, _) {},
          onRemoveColumn: (_) {},
        ),
      ),
    ),
  );
}

class _FakeBoqRepository implements YorksV1BoqRepository {
  _FakeBoqRepository(
    this.worksheet, {
    this.conflictOnSave = false,
    this.unexpectedOnLoad = false,
  });

  final YorksV1BoqWorksheet worksheet;
  final bool conflictOnSave;
  final bool unexpectedOnLoad;
  int getCalls = 0;
  final List<YorksV1SaveBoqWorksheetInput> saved = [];

  @override
  Future<YorksV1BoqGroup> archiveGroup(
    YorksV1ArchiveBoqGroupInput input,
  ) async => worksheet.group;

  @override
  Future<YorksV1BoqGroup> createCustomGroup(
    YorksV1CreateBoqGroupInput input,
  ) async => worksheet.group;

  @override
  Future<YorksV1BoqGroup> renameGroup(YorksV1RenameBoqGroupInput input) async =>
      worksheet.group;

  @override
  Future<YorksV1BoqGroup> restoreGroup(
    YorksV1RestoreBoqGroupInput input,
  ) async => worksheet.group;

  @override
  Future<YorksV1BoqGroup> assignLegacyGroupScope(
    YorksV1AssignLegacyBoqGroupScopeInput input,
  ) async => worksheet.group;

  @override
  Future<YorksV1BoqWorksheet> getWorksheet(String groupId) async {
    getCalls += 1;
    if (unexpectedOnLoad) throw StateError('network unavailable');
    return worksheet;
  }

  @override
  Future<YorksV1BoqWorksheet> importWorksheet(
    YorksV1ImportBoqWorksheetInput input,
  ) async => saveWorksheet(
    YorksV1SaveBoqWorksheetInput(
      worksheet: input.worksheet,
      worksheetTitle: input.worksheetTitle,
      expectedVersion: input.expectedVersion,
      idempotencyKey: input.idempotencyKey,
    ),
  );

  @override
  Future<List<YorksV1BoqGroup>> listGroups(String projectId) async => [
    worksheet.group,
  ];

  @override
  Future<List<YorksV1BoqGroup>> listGroupsForScope(
    String projectId, {
    String? scopeId,
  }) async => [worksheet.group];

  @override
  Future<List<YorksV1BoqFolderManagementItem>> listFolderManagement(
    String projectId, {
    required String scopeId,
    bool includeArchived = true,
  }) async => [
    YorksV1BoqFolderManagementItem(
      group: worksheet.group,
      isSystemDefault: !worksheet.group.isCustom,
      canRename: true,
      canArchive: worksheet.group.isCustom,
      canRestore: false,
    ),
  ];

  @override
  Future<YorksV1BoqWorksheet> saveWorksheet(
    YorksV1SaveBoqWorksheetInput input,
  ) async {
    saved.add(input);
    if (conflictOnSave) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
    }
    return input.worksheet.copyWith(
      group: YorksV1BoqGroup(
        id: input.worksheet.group.id,
        projectId: input.worksheet.group.projectId,
        name: input.worksheet.group.name,
        worksheetTitle: input.worksheetTitle,
        displayOrder: input.worksheet.group.displayOrder,
        isCustom: input.worksheet.group.isCustom,
        isArchived: input.worksheet.group.isArchived,
        version: input.expectedVersion + 1,
        rowCount: input.worksheet.rows.length,
        columnCount: input.worksheet.columns.length,
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
    );
  }
}

class _Ids {
  var _value = 20;
  String next() =>
      '10000000-0000-4000-8000-${(_value++).toString().padLeft(12, '0')}';
}

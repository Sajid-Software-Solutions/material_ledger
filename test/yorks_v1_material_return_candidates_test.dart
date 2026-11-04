import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/widgets/yorks_v1_material_return_composer.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_candidates.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_workflow.dart';

import 'support/yorks_v1_material_return_candidates_fixture.dart';

void main() {
  late YorksV1MaterialReturnItemCandidates candidates;
  late YorksV1MaterialReturnItem pipe;

  setUp(() {
    candidates = YorksV1MaterialReturnItemCandidates.fromRpcJson(
      yorksV1MaterialReturnCandidatesFixture(),
    );
    pipe = candidates.items.first;
  });

  group('fromRpcJson', () {
    test('decodes grouped material with its deliveries', () {
      expect(candidates.items, hasLength(2));
      expect(pipe.description, 'Copper Pipe');
      expect(pipe.size, '15mm');
      expect(pipe.itemCodes, ['CP-015']);
      expect(pipe.returnableQuantity, '13');
      expect(pipe.hasUnconfirmed, isTrue);
      expect(pipe.sources.first.isUnconfirmed, isTrue);
      expect(pipe.sources.last.receiptReviewLineId, 'rrl-1');
      expect(
        candidates.itemForKey('safety gloves\u001f\u001fpairs'),
        isNotNull,
      );
    });

    test('rejects malformed responses instead of guessing', () {
      Matcher unexpected() => throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
      );
      expect(
        () => YorksV1MaterialReturnItemCandidates.fromRpcJson([]),
        unexpected(),
      );
      final badBasis = yorksV1MaterialReturnCandidatesFixture();
      ((badBasis['items']! as List).first as Map)['sources'] = [
        {
          ...(((badBasis['items']! as List).first as Map)['sources'] as List)
                  .first
              as Map<String, Object?>,
          'basis_kind': 'guessed',
        },
      ];
      expect(
        () => YorksV1MaterialReturnItemCandidates.fromRpcJson(badBasis),
        unexpected(),
      );
      final badQuantity = yorksV1MaterialReturnCandidatesFixture();
      ((badQuantity['items']! as List).first as Map)['returnable_qty'] = 'ten';
      expect(
        () => YorksV1MaterialReturnItemCandidates.fromRpcJson(badQuantity),
        unexpected(),
      );
    });
  });

  group('allocation', () {
    test('takes the newest delivery first', () {
      final slices = yorksV1AllocateReturnQuantity(pipe.sources, '7')!;
      expect(slices.map((slice) => slice.source.dispatchLineId), [
        'dl-3',
        'dl-1',
      ]);
      expect(slices.map((slice) => slice.quantity), ['5', '2']);
    });

    test('is exact for decimals and the full returnable quantity', () {
      expect(
        yorksV1AllocateReturnQuantity(
          pipe.sources,
          '5.25',
        )!.map((slice) => slice.quantity),
        ['5', '0.25'],
      );
      expect(
        yorksV1AllocateReturnQuantity(
          pipe.sources,
          '13',
        )!.map((slice) => slice.quantity),
        ['5', '8'],
      );
    });

    test('refuses zero, invalid and over-available quantities', () {
      expect(yorksV1AllocateReturnQuantity(pipe.sources, '0'), isNull);
      expect(yorksV1AllocateReturnQuantity(pipe.sources, 'abc'), isNull);
      expect(yorksV1AllocateReturnQuantity(pipe.sources, '13.0001'), isNull);
    });
  });

  group('helpers', () {
    test('item key mirrors the server grouping key', () {
      expect(
        yorksV1MaterialReturnItemKey(
          description: '  copper   PIPE ',
          size: '15mm',
          unit: ' MTR',
        ),
        pipe.key,
      );
      expect(
        yorksV1MaterialReturnItemKey(
          description: 'Safety Gloves',
          unit: 'Pairs',
        ),
        'safety gloves\u001f\u001fpairs',
      );
    });

    test('building filter keeps only that building and re-totals', () {
      final scoped = yorksV1MaterialReturnItemForScope(pipe, 'scope-a');
      expect(scoped.sources.single.dispatchLineId, 'dl-1');
      expect(scoped.returnableQuantity, '8');
      expect(scoped.hasUnconfirmed, isFalse);
      expect(
        identical(yorksV1MaterialReturnItemForScope(pipe, null), pipe),
        isTrue,
      );
    });

    test('instant search matches every word anywhere in the material', () {
      expect(yorksV1MaterialReturnItemMatches(pipe, 'pipe 15mm'), isTrue);
      expect(yorksV1MaterialReturnItemMatches(pipe, 'cp-015'), isTrue);
      expect(yorksV1MaterialReturnItemMatches(pipe, 'YRA-MR-002'), isTrue);
      expect(yorksV1MaterialReturnItemMatches(pipe, 'gloves'), isFalse);
      expect(yorksV1MaterialReturnItemMatches(pipe, '   '), isTrue);
    });

    test('query normalizes and bounds the search', () {
      const a = YorksV1MaterialReturnCandidatesQuery(
        projectId: 'p',
        search: ' copper   pipe ',
      );
      expect(a.toRpcParameters(), {
        'p_project_id': 'p',
        'p_return_id': null,
        'p_search': 'copper pipe',
        'p_scope_id': null,
      });
      expect(
        a,
        const YorksV1MaterialReturnCandidatesQuery(
          projectId: 'p',
          search: 'copper pipe',
        ),
      );
      expect(
        YorksV1MaterialReturnCandidatesQuery(
          projectId: 'p',
          search: 'x' * 200,
        ).normalizedSearch!.length,
        YorksV1MaterialReturnCandidatesQuery.maxSearchLength,
      );
    });
  });

  group('composer controller', () {
    test('turns one material into newest-first delivery lines', () {
      final controller = YorksV1ReturnComposerController();
      addTearDown(controller.dispose);
      controller
        ..addItem(pipe)
        ..resolve(candidates);
      controller.selections.single.quantity.text = '6';
      controller.selections.single.note.text = 'Surplus';
      final built = controller.buildLines();
      expect(built.hasIssues, isFalse);
      expect(built.lines.map((line) => line.toRpcJson()), [
        {
          'origin_kind': 'delivered',
          'dispatch_line_id': 'dl-3',
          'receipt_review_line_id': null,
          'item_description': null,
          'brand_origin': null,
          'unit': null,
          'return_qty': '5',
          'note': 'Surplus',
        },
        {
          'origin_kind': 'delivered',
          'dispatch_line_id': 'dl-1',
          'receipt_review_line_id': 'rrl-1',
          'item_description': null,
          'brand_origin': null,
          'unit': null,
          'return_qty': '1',
          'note': 'Surplus',
        },
      ]);
    });

    test('flags quantities above what can be returned', () {
      final controller = YorksV1ReturnComposerController();
      addTearDown(controller.dispose);
      controller
        ..addItem(pipe)
        ..resolve(candidates);
      final selection = controller.selections.single;
      expect(
        controller.issueFor(selection),
        YorksV1ReturnSelectionIssue.quantityRequired,
      );
      selection.quantity.text = '14';
      expect(
        controller.issueFor(selection),
        YorksV1ReturnSelectionIssue.exceedsAvailable,
      );
      expect(controller.buildLines().hasIssues, isTrue);
      expect(controller.showIssues, isTrue);
    });

    test('hydrates saved lines back into one material per key', () {
      final controller = YorksV1ReturnComposerController();
      addTearDown(controller.dispose);
      controller.hydrate(const [
        YorksV1MaterialReturnLineRecord(
          id: 'l1',
          origin: YorksV1ReturnLineOrigin.delivered,
          dispatchLineId: 'dl-3',
          displayOrder: 1,
          description: 'Copper Pipe',
          size: '15mm',
          unit: 'Mtr',
          sourceKind: 'external_supplier',
          returnQuantity: '5.0000',
          lineNote: 'Surplus',
        ),
        YorksV1MaterialReturnLineRecord(
          id: 'l2',
          origin: YorksV1ReturnLineOrigin.delivered,
          dispatchLineId: 'dl-1',
          displayOrder: 2,
          description: 'Copper Pipe',
          size: '15mm',
          unit: 'Mtr',
          sourceKind: 'warehouse',
          returnQuantity: '1.0000',
        ),
        YorksV1MaterialReturnLineRecord(
          id: 'l3',
          origin: YorksV1ReturnLineOrigin.custom,
          displayOrder: 3,
          description: 'Pipe clamp',
          size: '15mm',
          model: 'C-15',
          unit: 'Nos',
          sourceKind: 'custom',
          returnQuantity: '12',
        ),
      ]);
      expect(controller.selections.single.key, pipe.key);
      expect(controller.selections.single.quantity.text, '6');
      expect(controller.selections.single.note.text, 'Surplus');
      expect(controller.customLines.single.model, 'C-15');
      expect(controller.isResolved, isFalse);
      controller.resolve(candidates);
      expect(controller.selections.single.item?.returnableQuantity, '13');
    });

    test('a material that is no longer returnable is reported', () {
      final controller = YorksV1ReturnComposerController();
      addTearDown(controller.dispose);
      controller.hydrate(const [
        YorksV1MaterialReturnLineRecord(
          id: 'l1',
          origin: YorksV1ReturnLineOrigin.delivered,
          displayOrder: 1,
          description: 'Discontinued Valve',
          unit: 'Nos',
          sourceKind: 'warehouse',
          returnQuantity: '1',
        ),
      ]);
      controller.resolve(candidates);
      expect(
        controller.issueFor(controller.selections.single),
        YorksV1ReturnSelectionIssue.unavailable,
      );
    });

    test(
      'custom lines carry size, model and tag; blank rows are ignored',
      () async {
        final controller = YorksV1ReturnComposerController();
        addTearDown(controller.dispose);
        await controller.addCustomLine();
        await controller.addCustomLine();
        final first = controller.customLines.first.id;
        await controller.updateLine(
          first,
          (line) => line.copyWith(
            description: 'Pipe clamp',
            size: '15mm',
            model: 'C-15',
            equipmentTag: 'CH-01',
            quantity: '12',
            unit: 'Nos',
          ),
        );
        final built = controller.buildLines();
        expect(built.customIncomplete, isFalse);
        expect(built.lines.single.toRpcJson(), {
          'origin_kind': 'custom',
          'receipt_review_line_id': null,
          'item_description': 'Pipe clamp',
          'brand_origin': null,
          'unit': 'Nos',
          'size': '15mm',
          'model': 'C-15',
          'equipment_tag': 'CH-01',
          'return_qty': '12',
          'note': null,
        });
        await controller.updateLine(
          controller.customLines.last.id,
          (line) => line.copyWith(description: 'Ladder'),
        );
        expect(controller.buildLines().customIncomplete, isTrue);
      },
    );
  });
}

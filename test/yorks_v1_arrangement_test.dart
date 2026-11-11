import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_arrangement_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('quantity derives full, partial and zero with exact decimals', () {
    expect(
      yorksV1ArrangementDecisionForQuantity(
        requestedQuantity: '1.0001',
        arrangedQuantity: '1.0001',
      ),
      YorksV1ArrangementDecision.full,
    );
    expect(
      yorksV1ArrangementDecisionForQuantity(
        requestedQuantity: '1.0001',
        arrangedQuantity: '1.0000',
      ),
      YorksV1ArrangementDecision.partial,
    );
    expect(
      yorksV1ArrangementDecisionForQuantity(
        requestedQuantity: '1',
        arrangedQuantity: '0',
      ),
      YorksV1ArrangementDecision.unavailable,
    );
    for (final raw in ['', ' ', '1.', '-1', '2', 'x', '0.00001']) {
      expect(
        yorksV1ArrangementDecisionForQuantity(
          requestedQuantity: '1',
          arrangedQuantity: raw,
        ),
        isNull,
        reason: raw,
      );
    }
  });

  test('automatic warehouse match needs a unique exact unit-safe identity', () {
    const line = YorksV1ArrangementLine(
      id: 'l',
      requestLineId: 'r',
      displayOrder: 1,
      description: ' Access Door ',
      brandOrigin: 'BETA',
      unit: 'Nos',
      requestedQuantity: '3',
      source: YorksV1ArrangementSource.warehouse,
    );
    YorksV1InventoryItem item(
      String id, {
      String description = 'access door',
      String brand = 'beta',
      String unit = 'nos',
    }) => YorksV1InventoryItem(
      id: id,
      description: description,
      brandOrigin: brand,
      unit: unit,
      onHandQuantity: '0',
      reservedQuantity: '0',
      availableQuantity: '0',
      recordVersion: 1,
    );
    final match = item('match');
    expect(
      yorksV1ArrangementInventoryMatch(line, [
        item('other', description: 'Motor'),
        match,
      ]),
      same(match),
    );
    expect(
      yorksV1ArrangementInventoryMatch(line, [
        item('fuzzy', description: 'Access door large'),
      ]),
      isNull,
    );
    expect(
      yorksV1ArrangementInventoryMatch(line, [item('brand', brand: 'Other')]),
      isNull,
    );
    expect(
      yorksV1ArrangementInventoryMatch(line, [item('unit', unit: 'Set')]),
      isNull,
    );
    expect(
      yorksV1ArrangementInventoryMatch(line, [match, item('duplicate')]),
      isNull,
    );
  });

  test('arrangement workspace preserves non-commercial review facts only', () {
    final workspace = YorksV1ArrangementWorkspace.fromRpcJson(_workspaceJson());

    expect(workspace.canDecide, true);
    expect(workspace.clarificationReviewRequired, true);
    expect(workspace.canClarify, true);
    expect(workspace.procurementClarificationRevision, 2);
    expect(workspace.approvedProcurementClarificationRevision, 1);
    expect(workspace.currentArrangement?.lines.single.requestedQuantity, '4');
    expect(workspace.currentArrangement?.lines.single.arrangedQuantity, '2');
    expect(workspace.currentArrangement?.lines.single.reservedQuantity, '2');
    expect(
      workspace.currentArrangement?.lines.single.inventoryItemId,
      'item-1',
    );
    expect(workspace.currentArrangement?.lines.single.isBoqCorrelated, isTrue);
    expect(
      workspace.currentArrangement?.lines.single.sourceBoqGroupName,
      'Dampers & Fire Control',
    );
    final inventory = YorksV1InventoryItem.fromRpcJson({
      'id': 'item-1',
      'item_code': 'MSD-600',
      'location_bin': 'Rack B / Shelf 3',
      'item_description': 'Motorized smoke damper',
      'unit': 'Nos',
      'on_hand_qty': '12',
      'reserved_qty': '0',
      'available_qty': '12',
      'record_version': 1,
    });
    expect(inventory.itemCode, 'MSD-600');
    expect(inventory.locationBin, 'Rack B / Shelf 3');
  });

  test(
    'requested editor default never becomes a committed projection fact',
    () {
      final json = _workspaceJson();
      final arrangement = (json['arrangements'] as List).single as Map;
      final line =
          (arrangement['lines'] as List).single as Map<String, dynamic>;
      line['decision'] = null;
      line['arranged_qty'] = null;
      var result = YorksV1ArrangementWorkspace.fromRpcJson(
        json,
      ).currentArrangement!.lines.single;
      expect(result.requestedQuantity, '4');
      expect(result.arrangedQuantity, isNull);
      expect(result.decision, isNull);

      for (final saved in ['0', '2.5000', '4']) {
        line['arranged_qty'] = saved;
        result = YorksV1ArrangementWorkspace.fromRpcJson(
          json,
        ).currentArrangement!.lines.single;
        expect(result.arrangedQuantity, saved);
        expect(result.requestedQuantity, '4');
      }
    },
  );

  test('save input emits complete server-recognized line decisions', () {
    final input = YorksV1SaveArrangementInput(
      requestId: 'request-1',
      arrangementId: 'arrangement-1',
      expectedRequestVersion: 4,
      expectedArrangementVersion: 1,
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
      procurementNote: 'Supplier allocation checked',
      lines: const [
        YorksV1ArrangementLineInput(
          arrangementLineId: 'line-1',
          source: YorksV1ArrangementSource.warehouse,
          decision: YorksV1ArrangementDecision.partial,
          arrangedQuantity: '2.5',
          inventoryItemId: 'item-1',
          reason: 'Balance is held for another project',
          unitCost: '125.50',
        ),
      ],
    );

    expect(input.toRpcPayload(), {
      'request_id': 'request-1',
      'arrangement_id': 'arrangement-1',
      'expected_request_version': 4,
      'expected_arrangement_version': 1,
      'procurement_note': 'Supplier allocation checked',
      'lines': [
        {
          'arrangement_line_id': 'line-1',
          'source_kind': 'warehouse',
          'external_supplier': null,
          'external_source_ready': false,
          'external_expected_date': null,
          'external_reference': null,
          'inventory_item_id': 'item-1',
          'decision': 'partial',
          'arranged_qty': '2.5',
          'reason': 'Balance is held for another project',
          'unit_cost': '125.50',
        },
      ],
    });
  });

  test(
    'procurement clarification payload is trimmed and keeps model optional',
    () {
      const input = YorksV1UpdateProcurementMaterialItemInput(
        requestId: 'request-1',
        requestLineId: 'request-line-1',
        expectedRequestVersion: 4,
        itemDescription: '  Motorized smoke damper  ',
        modelReference: '  MSD-600  ',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      );

      expect(input.toRpcPayload(), {
        'request_id': 'request-1',
        'request_line_id': 'request-line-1',
        'expected_request_version': 4,
        'item_description': 'Motorized smoke damper',
        'model_reference': 'MSD-600',
      });
    },
  );

  test('arrangement projection retains requested and clarified identity', () {
    final json = _workspaceJson();
    final line =
        ((json['arrangements'] as List).single as Map<String, dynamic>)['lines']
            as List;
    (line.single as Map<String, dynamic>).addAll({
      'item_description': 'Motorized smoke damper',
      'model_reference': 'MSD-600',
      'requested_item_description': 'Smoke damper',
      'requested_model_reference': null,
      'procurement_clarification_version': 1,
      'procurement_clarified_at': '2026-09-07T08:00:00Z',
      'procurement_clarified_by_display_name': 'Procurement User',
    });

    final projected = YorksV1ArrangementWorkspace.fromRpcJson(
      json,
    ).currentArrangement!.lines.single;
    expect(projected.wasProcurementClarified, isTrue);
    expect(projected.requestedDescription, 'Smoke damper');
    expect(projected.modelReference, 'MSD-600');
    expect(projected.procurementClarificationVersion, 1);
  });

  test('repository sends clarification only through the trusted RPC', () async {
    final client = _RecordingRpcClient();
    final repository = YorksV1SupabaseArrangementRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
      ),
      connectivity: DefaultConnectivity(),
      rpcClient: client,
    );

    await repository.updateProcurementItem(
      const YorksV1UpdateProcurementMaterialItemInput(
        requestId: 'request-1',
        requestLineId: 'request-line-1',
        expectedRequestVersion: 4,
        itemDescription: 'Smoke damper MSD-600',
        modelReference: 'MSD-600',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      ),
    );

    expect(client.calls, ['v1_update_material_request_procurement_item']);
  });

  test(
    'the arrangement repository fails closed before any RPC when disabled',
    () async {
      final client = _RecordingRpcClient();
      final repository = YorksV1SupabaseArrangementRepository(
        featureFlags: const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
        ),
        connectivity: DefaultConnectivity(),
        rpcClient: client,
      );

      await expectLater(
        repository.getWorkspace('request-1'),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.featureDisabled,
          ),
        ),
      );
      expect(client.calls, isEmpty);
    },
  );

  test('the arrangement repository bounds a stalled RPC', () async {
    final repository = YorksV1SupabaseArrangementRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
      ),
      connectivity: DefaultConnectivity(),
      rpcClient: _HangingRpcClient(),
      rpcTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      repository.getWorkspace('request-1'),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.backendUnavailable,
        ),
      ),
    );
  });

  test('reservation shortage keeps its actionable domain error', () async {
    final repository = YorksV1SupabaseArrangementRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
      ),
      connectivity: DefaultConnectivity(),
      rpcClient: _FailingRpcClient(
        const PostgrestException(
          message: 'V1_INVENTORY_RESERVATION_EXCEEDS_AVAILABLE',
          code: '22023',
        ),
      ),
    );

    await expectLater(
      repository.getWorkspace('request-1'),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.insufficientStock,
        ),
      ),
    );
  });

  test('other invalid arrangement input remains a validation error', () async {
    final repository = YorksV1SupabaseArrangementRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
      ),
      connectivity: DefaultConnectivity(),
      rpcClient: _FailingRpcClient(
        const PostgrestException(
          message: 'V1_ARRANGEMENT_LINE_INVALID',
          code: '22023',
        ),
      ),
    );

    await expectLater(
      repository.getWorkspace('request-1'),
      throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.invalidInput,
        ),
      ),
    );
  });
}

Map<String, dynamic> _workspaceJson() => {
  'request_id': 'request-1',
  'request_number': 'Y-001-MR001',
  'request_state': 'awaiting_approval',
  'request_record_version': 4,
  'can_begin': false,
  'can_save': false,
  'can_decide': true,
  'clarification_review_required': true,
  'can_clarify': true,
  'procurement_clarification_revision': 2,
  'approved_procurement_clarification_revision': 1,
  'arrangements': [
    {
      'id': 'arrangement-1',
      'arrangement_version': 1,
      'status': 'awaiting_approval',
      'is_current': true,
      'record_version': 2,
      'started_by_display_name': 'Procurement User',
      'started_at': '2026-08-02T00:00:00Z',
      'saved_at': '2026-08-02T00:05:00Z',
      'saved_by_display_name': 'Procurement User',
      'lines': [
        {
          'id': 'line-1',
          'request_line_id': 'request-line-1',
          'display_order': 1,
          'item_description': 'Duct Damper',
          'request_source_kind': 'boq',
          'source_boq_group_id': 'boq-group-1',
          'source_boq_row_id': 'boq-row-1',
          'source_boq_group_name': 'Dampers & Fire Control',
          'source_scope_name': 'Building A',
          'brand_origin': 'UAE',
          'requested_qty': '4',
          'unit': 'Nos',
          'source_kind': 'warehouse',
          'external_supplier': null,
          'decision': 'partial',
          'arranged_qty': '2',
          'reason': 'Only two in stock',
          'inventory_item_id': 'item-1',
          'inventory_item_description': 'Duct Damper',
          'warehouse_available_at_save': '5',
          'reservation_state': 'active',
          'reserved_qty': '2',
        },
      ],
    },
  ],
};

class _RecordingRpcClient implements YorksV1MaterialRequestRpcClient {
  final List<String> calls = [];

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add(functionName);
    return _workspaceJson();
  }
}

class _HangingRpcClient implements YorksV1MaterialRequestRpcClient {
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) => Completer<Object?>().future;
}

class _FailingRpcClient implements YorksV1MaterialRequestRpcClient {
  const _FailingRpcClient(this.error);

  final PostgrestException error;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) => Future.error(error);
}

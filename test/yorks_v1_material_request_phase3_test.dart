import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_arrangement.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  test('arrangement workspace preserves external readiness evidence', () {
    final workspace = YorksV1ArrangementWorkspace.fromRpcJson({
      'request_id': 'request-1',
      'request_state': 'arranging',
      'request_record_version': 3,
      'can_begin': false,
      'can_save': true,
      'can_decide': false,
      'external_source_readiness_required': true,
      'arrangements': [
        {
          'id': 'arrangement-1',
          'arrangement_version': 1,
          'status': 'working',
          'is_current': false,
          'record_version': 1,
          'started_by_display_name': 'Procurement User',
          'started_at': '2026-08-21T00:00:00Z',
          'lines': [
            {
              'id': 'arrangement-line-1',
              'request_line_id': 'request-line-1',
              'display_order': 1,
              'item_description': 'External smoke damper',
              'requested_qty': '4',
              'unit': 'Nos',
              'source_kind': 'external_supplier',
              'external_source_ready': true,
              'external_expected_date': '2026-09-01',
              'external_reference': 'SUP-COMMIT-001',
            },
          ],
        },
      ],
    });

    final line = workspace.workingArrangement!.lines.single;
    expect(workspace.externalSourceReadinessRequired, isTrue);
    expect(line.externalSourceReady, isTrue);
    expect(line.externalExpectedDate, DateTime.utc(2026, 9));
    expect(line.externalReference, 'SUP-COMMIT-001');
  });

  test('external readiness input uses the strict server contract', () {
    const input = YorksV1ArrangementLineInput(
      arrangementLineId: 'arrangement-line-1',
      source: YorksV1ArrangementSource.externalSupplier,
      decision: YorksV1ArrangementDecision.full,
      arrangedQuantity: '4',
      externalSupplier: '  Supplier LLC  ',
      externalSourceReady: true,
      externalExpectedDate: ' 2026-09-01 ',
      externalReference: ' SUP-COMMIT-001 ',
    );

    expect(input.toRpcJson(), {
      'arrangement_line_id': 'arrangement-line-1',
      'source_kind': 'external_supplier',
      'external_supplier': 'Supplier LLC',
      'external_source_ready': true,
      'external_expected_date': '2026-09-01',
      'external_reference': 'SUP-COMMIT-001',
      'inventory_item_id': null,
      'decision': 'full',
      'arranged_qty': '4',
      'reason': null,
    });
  });

  test('Phase 3 policy parses replacement provenance and published rules', () {
    final policy = YorksV1MaterialRequestPhase3Policy.fromRpcJson(const {
      'request_id': 'source-request',
      'allow_authorized_creator_self_approval': false,
      'require_external_source_readiness': true,
      'can_create_replacement': false,
      'replacement_exists': true,
      'replacement_request_id': 'replacement-request',
      'replacement_of_request_id': null,
    });

    expect(policy.allowAuthorizedCreatorSelfApproval, isFalse);
    expect(policy.requireExternalSourceReadiness, isTrue);
    expect(policy.replacementExists, isTrue);
    expect(policy.replacementRequestId, 'replacement-request');
  });

  test('repository invokes protected Phase 3 projection and command', () async {
    final connectivity = DefaultConnectivity();
    addTearDown(connectivity.dispose);
    final rpc = _Phase3RpcClient();
    final repository = YorksV1SupabaseMaterialRequestRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
      ),
      connectivity: connectivity,
      rpcClient: rpc,
    );

    final policy = await repository.getPhase3Policy('source-request');
    expect(policy.canCreateReplacement, isTrue);
    expect(rpc.calls.first, {
      'function': 'v1_material_request_phase3_policy_projection',
      'parameters': {'p_request_id': 'source-request'},
    });

    final created = await repository.createReplacement(
      const YorksV1CreateReplacementMaterialRequestInput(
        sourceRequestId: ' source-request ',
        expectedSourceVersion: 5,
        idempotencyKey: 'idempotency-1',
      ),
    );
    expect(created.id, 'replacement-request');
    expect(rpc.calls.last, {
      'function': 'v1_create_replacement_material_request',
      'parameters': {
        'p_payload': {
          'source_request_id': 'source-request',
          'expected_source_version': 5,
        },
        'p_idempotency_key': 'idempotency-1',
      },
    });
  });
}

class _Phase3RpcClient implements YorksV1MaterialRequestRpcClient {
  final List<Map<String, Object?>> calls = [];

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add({'function': functionName, 'parameters': parameters});
    if (functionName == 'v1_material_request_phase3_policy_projection') {
      return const {
        'request_id': 'source-request',
        'allow_authorized_creator_self_approval': true,
        'require_external_source_readiness': false,
        'can_create_replacement': true,
        'replacement_exists': false,
        'replacement_request_id': null,
        'replacement_of_request_id': null,
      };
    }
    return const {
      'id': 'replacement-request',
      'project_id': 'project-1',
      'project_ref': 'YRA-001',
      'project_name': 'Replacement Project',
      'scope_id': 'scope-1',
      'scope_name': 'Common',
      'state': 'draft',
      'record_version': 1,
      'created_at': '2026-08-21T00:00:00Z',
      'updated_at': '2026-08-21T00:00:00Z',
      'timing': 'normal',
      'lines': <Object?>[],
    };
  }
}

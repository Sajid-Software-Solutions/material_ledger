import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_request_draft_controller.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/models/yorks_v1_company_document_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request_strings.dart';
import 'package:material_ledger/shared/repositories/collection_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_material_request_document_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ranked material suggestion retains safe BOQ provenance', () {
    final suggestion = YorksV1MaterialRequestInventorySuggestion.fromRpcJson({
      'id': 'boq-row-1',
      'source_kind': 'scope_boq',
      'item_description': 'Motorized smoke damper',
      'brand_origin': 'UAE',
      'size': '500 x 500',
      'model': 'MSD-500',
      'equipment_tag': 'MSD-A1',
      'unit': 'Nos',
      'source_boq_group_id': 'boq-group-1',
      'source_boq_row_id': 'boq-row-1',
      'source_scope_id': 'scope-1',
      'source_scope_name': 'Building A',
      'source_group_name': 'Dampers & Fire Control',
    });
    const custom = YorksV1MaterialRequestLine(
      id: 'line-1',
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: '',
      quantity: '1',
      unit: 'Nos',
    );
    final correlated = custom.copyWith(
      source: YorksV1MaterialRequestLineSource.boq,
      sourceBoqGroupId: suggestion.sourceBoqGroupId,
      sourceBoqRowId: suggestion.sourceBoqRowId,
      description: suggestion.description,
    );

    expect(
      suggestion.source,
      YorksV1MaterialRequestSuggestionSource.selectedScopeBoq,
    );
    expect(suggestion.retainsBoqProvenance, isTrue);
    expect(suggestion.sourceScopeName, 'Building A');
    expect(suggestion.equipmentTag, 'MSD-A1');
    expect(correlated.source, YorksV1MaterialRequestLineSource.boq);
    expect(correlated.sourceBoqGroupId, 'boq-group-1');
    expect(correlated.sourceBoqRowId, 'boq-row-1');
    expect(correlated.toRpcJson()['source_kind'], 'boq');
  });

  test('inventory suggestion defaults to a non-BOQ custom source', () {
    final suggestion = YorksV1MaterialRequestInventorySuggestion.fromRpcJson({
      'id': 'inventory-1',
      'source_kind': 'inventory',
      'item_code': 'INV-001',
      'item_description': 'Flexible duct',
      'unit': 'Meter',
    });

    expect(suggestion.source, YorksV1MaterialRequestSuggestionSource.inventory);
    expect(suggestion.retainsBoqProvenance, isFalse);
    expect(suggestion.sourceBoqRowId, isNull);
  });

  test(
    'normalizes request descriptions and preserves the new controlled units',
    () {
      const line = YorksV1MaterialRequestLine(
        id: 'description-unit-line',
        displayOrder: 1,
        source: YorksV1MaterialRequestLineSource.custom,
        description: 'motorized smoke damper',
        quantity: '1',
        unit: 'Ton',
      );

      expect(
        normalizeYorksV1MaterialRequestItemDescription(
          '  motorized smoke damper  ',
        ),
        'Motorized smoke damper',
      );
      expect(line.toRpcJson()['item_description'], 'Motorized smoke damper');
      expect(line.toRpcJson()['unit'], 'Ton');
      expect(line.copyWith(unit: 'Boxes').toRpcJson()['unit'], 'Boxes');
    },
  );

  test(
    'controlled line status summarizes current operational truth concisely',
    () {
      final inTransit = YorksV1MaterialRequestLineLifecycle.fromRpcJson(const {
        'request_line_id': 'line-1',
        'requested_qty': '10',
        'arranged_qty': '10',
        'cannot_provide_qty': '0',
        'approved_qty': '10',
        'reserved_qty': '3',
        'dispatched_qty': '5',
        'in_transit_qty': '5',
        'reviewed_good_qty': '0',
        'reviewed_missing_qty': '0',
        'reviewed_damaged_qty': '0',
        'remaining_approved_qty': '5',
        'replacement_eligible_qty': '0',
        'ordinary_outstanding_qty': '5',
        'returned_qty': '1',
        'still_needed_qty': '5',
        'source_kind': 'external_supplier',
        'status': 'Awaiting receipt review',
      });
      final replacement =
          YorksV1MaterialRequestLineLifecycle.fromRpcJson(const {
            'request_line_id': 'line-1',
            'requested_qty': '10',
            'arranged_qty': '10',
            'cannot_provide_qty': '0',
            'approved_qty': '10',
            'dispatched_qty': '5',
            'in_transit_qty': '0',
            'reviewed_good_qty': '3',
            'reviewed_missing_qty': '2',
            'reviewed_damaged_qty': '0',
            'remaining_approved_qty': '7',
            'replacement_eligible_qty': '2',
            'ordinary_outstanding_qty': '5',
            'source_kind': 'external_supplier',
            'status': 'Replacement required',
          });

      expect(
        inTransit.compactSummary,
        '5 / 10 dispatched · 5 in transit · external supplier · '
        'Awaiting receipt review',
      );
      expect(inTransit.reservedQuantity, '3');
      expect(inTransit.returnedQuantity, '1');
      expect(inTransit.stillNeededQuantity, '5');
      expect(
        replacement.compactSummary,
        '3 / 10 received · 2 missing · 2 replacement · external supplier · '
        'Replacement required',
      );
    },
  );

  group('Yorks V1 Material Request draft controller', () {
    test('new custom rows do not fabricate a controlled unit', () async {
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: _FakeRequestRepository(),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.addCustomLine();

      expect(controller.state.draft.lines.single.unit, isEmpty);
      expect(controller.state.draft.canSubmitLocally, isFalse);
    });

    test('inserts a similar line directly below the selected row', () async {
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: _FakeRequestRepository(),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.addCustomLine();
      await controller.addCustomLine();
      await controller.addCustomLine();
      final selected = controller.state.draft.lines[1];
      await controller.updateLine(
        selected.id,
        (line) => line.copyWith(
          description: 'Selected flexible duct',
          brandOrigin: 'Yorks',
          size: '12 inch',
          model: 'FD-12',
          quantity: '4',
          unit: 'Meter',
        ),
      );

      await controller.addSimilarLine(afterLineId: selected.id);

      final lines = controller.state.draft.lines;
      expect(lines, hasLength(4));
      expect(lines.map((line) => line.displayOrder), [1, 2, 3, 4]);
      expect(lines[1].id, selected.id);
      expect(lines[2].description, 'Selected flexible duct');
      expect(lines[2].brandOrigin, 'Yorks');
      expect(lines[2].size, '12 inch');
      expect(lines[2].unit, 'Meter');
      expect(lines[2].quantity, isEmpty);
      expect(lines[2].model, isNull);
      expect(lines[2].source, YorksV1MaterialRequestLineSource.custom);
      expect(lines[2].sourceBoqRowId, isNull);
    });

    test('inserts a custom line directly below the selected row', () async {
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: _FakeRequestRepository(),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.addCustomLine();
      await controller.addCustomLine();
      final selected = controller.state.draft.lines.first;

      await controller.addCustomLine(afterLineId: selected.id);

      final lines = controller.state.draft.lines;
      expect(lines, hasLength(3));
      expect(lines.map((line) => line.displayOrder), [1, 2, 3]);
      expect(lines.first.id, selected.id);
      expect(lines[1].description, isEmpty);
      expect(lines[1].quantity, isEmpty);
      expect(lines[1].unit, isEmpty);
      expect(lines[1].source, YorksV1MaterialRequestLineSource.custom);
    });

    test(
      'changing project preserves entered rows without old BOQ provenance',
      () async {
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        final boqLine = controller.state.draft.lines.single;
        await controller.updateLine(
          boqLine.id,
          (line) => line.copyWith(
            source: YorksV1MaterialRequestLineSource.boq,
            sourceBoqGroupId: _boqGroupId,
            sourceBoqRowId: _boqRowId,
            description: 'Existing BOQ access door',
            quantity: '2',
            unit: 'Nos',
          ),
        );
        await controller.addCustomLine();
        final customLine = controller.state.draft.lines.last;
        await controller.updateLine(
          customLine.id,
          (line) => line.copyWith(
            description: 'Engineer custom item',
            quantity: '1',
            unit: 'Set',
          ),
        );

        final changed = await controller.setProject(
          '73000000-0000-4000-8000-000000000099',
          preserveExistingLines: true,
        );

        final draft = controller.state.draft;
        expect(changed, isTrue);
        expect(draft.scopeId, isNull);
        expect(draft.lines, hasLength(2));
        expect(draft.lines.first.description, 'Existing BOQ access door');
        expect(
          draft.lines.first.source,
          YorksV1MaterialRequestLineSource.custom,
        );
        expect(draft.lines.first.sourceBoqGroupId, isNull);
        expect(draft.lines.first.sourceBoqRowId, isNull);
        expect(draft.lines.last.description, 'Engineer custom item');
      },
    );

    test(
      'keeps draft recovery private and submits one versioned command',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _FakeRequestRepository();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        final line = controller.state.draft.lines.single;
        await controller.updateLine(
          line.id,
          (current) => current.copyWith(
            description: 'Motorized Smoke Damper',
            brandOrigin: 'UAE',
            quantity: '4',
            unit: 'Nos',
          ),
        );

        final submitted = await controller.submit();

        expect(submitted?.requestNumber, 'B5TEST-MR001');
        expect(repository.saveAndSubmitInputs, hasLength(1));
        expect(repository.saveAndSubmitInputs.single.id, _draftId);
        expect(
          repository.saveAndSubmitInputs.single.submissionIdempotencyKey,
          isNotEmpty,
        );
        expect(store.readAll(), isEmpty);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitted,
        );
      },
    );

    test(
      'atomically submits and approves a new request through one repository command',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _FakeRequestRepository();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        final line = controller.state.draft.lines.single;
        await controller.updateLine(
          line.id,
          (current) => current.copyWith(
            description: 'Motorized Smoke Damper',
            brandOrigin: 'UAE',
            quantity: '4',
            unit: 'Nos',
          ),
        );

        final approved = await controller.submitAndApprove();

        expect(
          approved?.state,
          YorksV1MaterialRequestState.approvedForArrangement,
        );
        expect(repository.saveAndSubmitInputs, isEmpty);
        expect(repository.saveSubmitAndApproveInputs, hasLength(1));
        expect(
          repository.saveSubmitAndApproveInputs.single.submissionIdempotencyKey,
          isNotEmpty,
        );
        expect(store.readAll(), isEmpty);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitted,
        );
      },
    );

    test(
      'recovers an ambiguous first save before submitting newer local rows',
      () async {
        final repository = _FakeRequestRepository()
          ..submitFailures.add(
            const YorksV1DomainException(
              YorksV1DomainErrorCode.conflict,
              serverCode: '40001',
            ),
          );
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        final firstLine = controller.state.draft.lines.single;
        await controller.updateLine(
          firstLine.id,
          (current) => current.copyWith(
            description: 'Saved server line',
            quantity: '1',
            unit: 'Nos',
          ),
        );
        repository.requestResult = _request(
          requestId: _draftId,
          version: 1,
          lines: [
            firstLine
                .copyWith(
                  description: 'Saved server line',
                  quantity: '1',
                  unit: 'Nos',
                )
                .toRpcJson(),
          ],
        );
        await controller.addCustomLine(afterLineId: firstLine.id);
        final secondLine = controller.state.draft.lines.last;
        await controller.updateLine(
          secondLine.id,
          (current) => current.copyWith(
            description: 'New local line',
            quantity: '2',
            unit: 'Nos',
          ),
        );

        final submitted = await controller.submit();

        expect(submitted?.requestNumber, 'B5TEST-MR001');
        expect(repository.saveAndSubmitInputs, hasLength(2));
        expect(repository.saveAndSubmitInputs.first.serverRecordVersion, 0);
        expect(repository.saveAndSubmitInputs.last.serverRecordVersion, 1);
        expect(
          repository.saveAndSubmitInputs.last.submissionIdempotencyKey,
          isNot(repository.saveAndSubmitInputs.first.submissionIdempotencyKey),
        );
        expect(repository.saveAndSubmitInputs.last.lines, hasLength(2));
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitted,
        );
      },
    );

    test('keeps later server-version conflicts fail-closed', () async {
      final repository = _FakeRequestRepository()
        ..submitFailure = const YorksV1DomainException(
          YorksV1DomainErrorCode.conflict,
          serverCode: '40001',
        );
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: repository,
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.hydrateFromServer(
        _request(
          requestId: _draftId,
          version: 2,
          lines: const [
            {
              'id': '73000000-0000-4000-8000-000000000010',
              'display_order': 1,
              'source_kind': 'custom',
              'item_description': 'Saved damper',
              'requested_qty': '2',
              'unit': 'Nos',
            },
          ],
        ),
      );

      final submitted = await controller.submit();

      expect(submitted, isNull);
      expect(repository.saveAndSubmitInputs, hasLength(1));
      expect(repository.saveAndSubmitInputs.single.serverRecordVersion, 2);
      expect(
        controller.state.status,
        YorksV1MaterialRequestDraftSyncStatus.conflict,
      );
      expect(controller.lastErrorCode, YorksV1DomainErrorCode.conflict);
    });

    test(
      'does not leave the draft in submitting after an unexpected error',
      () async {
        final repository = _FakeRequestRepository()
          ..submitFailure = StateError('simulated backend failure');
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        final line = controller.state.draft.lines.single;
        await controller.updateLine(
          line.id,
          (current) => current.copyWith(
            description: 'Motorized Smoke Damper',
            quantity: '1',
            unit: 'Nos',
          ),
        );

        expect(await controller.submit(), isNull);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
        );
        expect(
          controller.state.errorCode,
          YorksV1DomainErrorCode.backendUnavailable,
        );
      },
    );

    for (final entry in {
      '28000': YorksV1DomainErrorCode.unauthenticated,
      'PGRST301': YorksV1DomainErrorCode.unauthenticated,
      'PGRST302': YorksV1DomainErrorCode.unauthenticated,
      'PGRST303': YorksV1DomainErrorCode.unauthenticated,
      '42501': YorksV1DomainErrorCode.unauthorized,
      'PGRST300': YorksV1DomainErrorCode.serverRejected,
    }.entries) {
      test(
        'MR RPC preserves authentication versus denial: ${entry.key}',
        () async {
          final connectivity = DefaultConnectivity();
          addTearDown(connectivity.dispose);
          final repository = YorksV1SupabaseMaterialRequestRepository(
            featureFlags: const YorksV1FeatureFlags(
              foundation: true,
              projects: true,
              boq: true,
              excel: true,
              requests: true,
            ),
            connectivity: connectivity,
            rpcClient: _RejectingRpcClient(entry.key),
          );
          await expectLater(
            repository.listDraftProjects(),
            throwsA(
              isA<YorksV1DomainException>()
                  .having((error) => error.code, 'category', entry.value)
                  .having(
                    (error) => error.serverCode,
                    'original safe code',
                    entry.key,
                  ),
            ),
          );
        },
      );
    }

    test('maps a stalled RPC to a bounded backend failure', () async {
      final connectivity = DefaultConnectivity();
      addTearDown(connectivity.dispose);
      final repository = YorksV1SupabaseMaterialRequestRepository(
        featureFlags: const YorksV1FeatureFlags(
          foundation: true,
          projects: true,
          boq: true,
          excel: true,
          requests: true,
        ),
        connectivity: connectivity,
        rpcClient: _DelayedRpcClient(),
        rpcTimeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        repository.listDraftProjects(),
        throwsA(
          isA<YorksV1DomainException>().having(
            (error) => error.code,
            'code',
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        ),
      );
    });

    test(
      'ranked search sends both project and selected scope context',
      () async {
        final connectivity = DefaultConnectivity();
        addTearDown(connectivity.dispose);
        final rpcClient = _CandidateSearchRpcClient();
        final repository = YorksV1SupabaseMaterialRequestRepository(
          featureFlags: const YorksV1FeatureFlags(
            foundation: true,
            projects: true,
            boq: true,
            excel: true,
            requests: true,
          ),
          connectivity: connectivity,
          rpcClient: rpcClient,
        );

        final results = await repository.searchInventory(
          projectId: _projectId,
          scopeId: _scopeId,
          query: 'damper',
        );

        expect(rpcClient.functionName, 'v1_search_material_request_candidates');
        expect(rpcClient.parameters, {
          'p_project_id': _projectId,
          'p_scope_id': _scopeId,
          'p_query': 'damper',
          'p_limit': 18,
        });
        expect(
          results.single.source,
          YorksV1MaterialRequestSuggestionSource.selectedScopeBoq,
        );
      },
    );

    test(
      'operational dashboard uses the protected project-scoped RPC',
      () async {
        final connectivity = DefaultConnectivity();
        addTearDown(connectivity.dispose);
        final rpcClient = _OperationsDashboardRpcClient();
        final repository = YorksV1SupabaseMaterialRequestRepository(
          featureFlags: const YorksV1FeatureFlags(
            foundation: true,
            projects: true,
            boq: true,
            excel: true,
            requests: true,
          ),
          connectivity: connectivity,
          rpcClient: rpcClient,
        );

        final dashboard = await repository.getOperationsDashboard(
          projectId: _projectId,
        );

        expect(
          rpcClient.functionName,
          'v1_material_request_operations_dashboard',
        );
        expect(rpcClient.parameters, {'p_project_id': _projectId});
        expect(dashboard.myWorkCount, 2);
        expect(dashboard.exceptionRequestCount, 1);
        expect(dashboard.outstandingReplacementQuantity, '3');
      },
    );

    test('does not send overlapping connected draft commands', () async {
      final blocker = Completer<void>();
      final repository = _FakeRequestRepository()..saveDelay = blocker.future;
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: repository,
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.setProject(_projectId);
      await controller.setScope(_scopeId);
      await controller.addCustomLine();
      final line = controller.state.draft.lines.single;
      await controller.updateLine(
        line.id,
        (current) => current.copyWith(
          description: 'Motorized Smoke Damper',
          quantity: '1',
          unit: 'Nos',
        ),
      );

      final first = controller.saveConnected();
      await Future<void>.delayed(Duration.zero);
      final second = controller.saveConnected();

      expect(await second, isFalse);
      blocker.complete();
      expect(await first, isNotNull);
      expect(repository.saveInputs, hasLength(1));
    });

    test(
      'uses a one-pass Excel iterable without losing imported lines',
      () async {
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        Iterable<YorksV1MaterialRequestLine> imported() sync* {
          yield _line('external-1', 'First import');
          yield _line('external-2', 'Second import');
        }

        await controller.addExcelLines(imported());

        expect(controller.state.draft.lines.map((line) => line.description), [
          'First import',
          'Second import',
        ]);
        expect(controller.state.draft.lines.map((line) => line.displayOrder), [
          1,
          2,
        ]);
        expect(
          controller.state.draft.lines.every(
            (line) => line.source == YorksV1MaterialRequestLineSource.excel,
          ),
          isTrue,
        );
      },
    );

    test('publishes text edits before local persistence completes', () async {
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _SlowMemoryStore<YorksV1MaterialRequestDraft>(),
        repository: _FakeRequestRepository(),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);

      await controller.addCustomLine();
      final line = controller.state.draft.lines.single;
      final pending = controller.updateLine(
        line.id,
        (current) => current.copyWith(
          description: 'Fast edit',
          quantity: '1',
          unit: 'Nos',
        ),
      );

      expect(controller.state.draft.lines.single.description, 'Fast edit');
      expect(controller.state.draft.canSubmitLocally, isFalse);
      await pending;
    });

    test(
      'Save Draft keeps incomplete input locally without a remote write',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _FakeRequestRepository();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.addCustomLine();
        final saved = await controller.saveDraft();

        expect(saved, isTrue);
        expect(repository.saveInputs, isEmpty);
        expect(store.readAll().single.lines.single.description, isEmpty);
        expect(controller.acceptedDraft.lines, hasLength(1));
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.local,
        );
      },
    );

    test(
      'lost draft-save response persists one intent and reconciles its receipt after restart',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _DraftSaveRecoveryRepository()
          ..loseNextResponse = true
          ..commitBeforeLoss = true;
        final controller = await _validSaveController(repository, store);

        expect(await controller.saveConnected(), isFalse);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
        );
        final pending = controller.currentDraft;
        expect(pending.hasPendingSave, isTrue);
        expect(store.readAll().single.pendingSaveOperationId, isNotEmpty);
        final frozenTitle = pending.title;
        await controller.setTitle('Must not replace unresolved save');
        expect(controller.currentDraft.title, frozenTitle);
        controller.dispose();

        final reopened = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(reopened.dispose);
        expect(reopened.currentDraft.hasPendingSave, isTrue);
        expect(await reopened.reconcileDraftSave(), isTrue);
        expect(repository.saveOperationIds, hasLength(1));
        expect(repository.receiptReads, 1);
        expect(reopened.currentDraft.serverRecordVersion, 1);
        expect(reopened.currentDraft.hasPendingSave, isFalse);
      },
    );

    test(
      'unconfirmed draft save replays only the same operation and payload',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _DraftSaveRecoveryRepository()
          ..loseNextResponse = true
          ..commitBeforeLoss = false;
        final controller = await _validSaveController(repository, store);
        addTearDown(controller.dispose);

        expect(await controller.saveConnected(), isFalse);
        final operationId = controller.currentDraft.pendingSaveOperationId;
        final payloadHash = controller.currentDraft.pendingSavePayloadHash;
        expect(await controller.reconcileDraftSave(), isFalse);
        expect(repository.saveOperationIds, [operationId]);
        expect(controller.state.canRetryUnconfirmed, isTrue);

        expect(
          await controller.reconcileDraftSave(retryIfAbsent: true),
          isTrue,
        );
        expect(repository.saveOperationIds, [operationId, operationId]);
        expect(repository.payloadHashes.toSet(), {payloadHash});
        expect(repository.commitCount, 1);
      },
    );

    test(
      'discard restores the draft snapshot from before this editing visit',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.setTitle('Earlier saved title');
        final baseline = controller.state.draft;
        await controller.setTitle('Unsaved replacement');

        await controller.restoreLocalSnapshot(baseline);

        expect(controller.state.draft.title, 'Earlier saved title');
        expect(store.readAll().single.title, 'Earlier saved title');
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.local,
        );
      },
    );

    test('cannot restore a draft snapshot owned by another editor', () async {
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: _FakeRequestRepository(),
        uuidFactory: _Ids().next,
      );
      addTearDown(controller.dispose);
      final foreign = YorksV1MaterialRequestDraft.empty(
        id: _draftId,
        ownerAuthUserId: 'someone-else',
        submissionIdempotencyKey: 'foreign-key',
      );

      await expectLater(
        controller.restoreLocalSnapshot(foreign),
        throwsArgumentError,
      );
    });

    test(
      'indexes recoverable local input and restores it for the same owner',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        var localDraftChanges = 0;
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
          onLocalDraftsChanged: () => localDraftChanges++,
        );
        addTearDown(controller.dispose);

        expect(controller.state.draft.hasRecoverableContent, isFalse);
        await controller.setTitle('Level 2 equipment');
        await controller.addCustomLine();

        expect(controller.state.draft.hasRecoverableContent, isTrue);
        expect(localDraftChanges, greaterThanOrEqualTo(2));
        expect(store.readAll(), hasLength(1));

        final restored = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(restored.dispose);
        expect(restored.state.draft.title, 'Level 2 equipment');
        expect(restored.state.draft.lines, hasLength(1));
      },
    );

    test(
      'copies an entire BOQ folder into an editable private draft',
      () async {
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        final worksheet = YorksV1BoqWorksheet(
          group: YorksV1BoqGroup(
            id: _boqGroupId,
            projectId: _projectId,
            name: 'Dampers',
            worksheetTitle: 'Dampers',
            displayOrder: 1,
            isCustom: false,
            isArchived: false,
            version: 1,
            rowCount: 2,
            columnCount: 4,
            updatedAt: DateTime.utc(2026, 8, 2),
            scopeId: _scopeId,
            scopeKind: 'common',
            scopeName: 'Common / All Buildings',
          ),
          columns: const [
            YorksV1BoqColumn(
              id: 'description-column',
              heading: 'Description',
              displayOrder: 1,
              canonicalField: YorksV1BoqCanonicalField.description,
            ),
            YorksV1BoqColumn(
              id: 'quantity-column',
              heading: 'Qty',
              displayOrder: 2,
              canonicalField: YorksV1BoqCanonicalField.quantity,
            ),
            YorksV1BoqColumn(
              id: 'unit-column',
              heading: 'Unit',
              displayOrder: 3,
              canonicalField: YorksV1BoqCanonicalField.unit,
            ),
          ],
          rows: [
            YorksV1BoqRow(
              id: 'boq-row-1',
              displayOrder: 1,
              values: const {
                'description-column': 'Damper A',
                'quantity-column': '4',
                'unit-column': 'Nos',
              },
              canonicalValues: const {},
            ),
            YorksV1BoqRow(
              id: 'boq-row-2',
              displayOrder: 2,
              values: const {
                'description-column': 'Damper B',
                'quantity-column': '2',
                'unit-column': 'Nos',
              },
              canonicalValues: const {},
            ),
          ],
        );

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addBoqRows(
          worksheet: worksheet,
          rowIds: worksheet.rows.map((row) => row.id),
        );

        expect(controller.state.draft.lines, hasLength(2));
        expect(controller.state.draft.lines.first.description, 'Damper A');
        expect(controller.state.draft.lines.first.quantity, '4');
        await controller.removeLine(controller.state.draft.lines.first.id);
        expect(controller.state.draft.lines, hasLength(1));
      },
    );

    test(
      'does not mix BOQ rows when the selected request scope changes',
      () async {
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);
        final worksheet = _scopedWorksheet(scopeId: _scopeId);

        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addBoqRows(
          worksheet: worksheet,
          rowIds: worksheet.rows.map((row) => row.id),
        );
        await controller.addCustomLine();

        expect(await controller.setScope('different-scope'), isFalse);
        expect(controller.state.draft.scopeId, _scopeId);
        expect(controller.state.draft.lines, hasLength(3));

        expect(
          await controller.setScope(
            'different-scope',
            discardIncompatibleBoqRows: true,
          ),
          isTrue,
        );
        expect(controller.state.draft.scopeId, 'different-scope');
        expect(controller.state.draft.lines.map((line) => line.source), [
          YorksV1MaterialRequestLineSource.custom,
        ]);
      },
    );

    test(
      'hydrates a saved server draft into the same editable local model',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: _FakeRequestRepository(),
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);

        await controller.hydrateFromServer(
          _request(
            requestId: _draftId,
            version: 7,
            lines: [
              {
                'id': '73000000-0000-4000-8000-000000000010',
                'display_order': 1,
                'source_kind': 'custom',
                'item_description': 'Saved damper',
                'requested_qty': '2',
                'unit': 'Nos',
              },
            ],
          ),
        );

        expect(controller.state.draft.serverRecordVersion, 7);
        expect(controller.state.draft.lines.single.description, 'Saved damper');
        expect(store.readAll().single.lines.single.quantity, '2');
      },
    );

    test(
      'Project Engineer saves a shared pre-approval edit through the trusted command',
      () async {
        final repository = _FakeRequestRepository();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: 'project-engineer',
          draftId: _draftId,
          store: _MemoryStore<YorksV1MaterialRequestDraft>(),
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);
        final request = YorksV1MaterialRequest.fromRpcJson({
          'id': _draftId,
          'project_id': _projectId,
          'project_ref': 'B5-TEST',
          'project_name': 'Test Project',
          'scope_id': _scopeId,
          'scope_name': 'Common',
          'state': 'awaiting_request_approval',
          'record_version': 4,
          'created_at': '2026-08-13T00:00:00Z',
          'updated_at': '2026-08-13T00:00:00Z',
          'timing': 'normal',
          'can_edit_before_approval': true,
          'lines': [
            {
              'id': 'preapproval-line',
              'display_order': 1,
              'source_kind': 'custom',
              'item_description': 'Editable damper',
              'requested_qty': '2',
              'unit': 'Nos',
            },
          ],
        });

        await controller.hydrateFromServer(request);
        await controller.setTitle('Engineer-corrected request');
        final saved = await controller.saveConnected();

        expect(saved, isNotNull);
        expect(repository.updateForApprovalInputs, hasLength(1));
        expect(
          repository.updateForApprovalInputs.single.draft.serverRecordVersion,
          4,
        );
        expect(
          repository.updateForApprovalInputs.single.draft.title,
          'Engineer-corrected request',
        );
        expect(repository.saveInputs, isEmpty);
      },
    );

    test(
      'returned request resubmission accepts a custom non-inventory line and clears stale recovery',
      () async {
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final repository = _FakeRequestRepository();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(controller.dispose);
        final returnedRequest = YorksV1MaterialRequest.fromRpcJson({
          'id': _draftId,
          'project_id': _projectId,
          'project_ref': 'B5-TEST',
          'project_name': 'Test Project',
          'scope_id': _scopeId,
          'scope_name': 'Common',
          'state': 'changes_requested',
          'record_version': 5,
          'created_at': '2026-08-13T00:00:00Z',
          'updated_at': '2026-08-13T00:05:00Z',
          'timing': 'normal',
          'can_edit_before_approval': true,
          'lines': [
            {
              'id': '73000000-0000-4000-8000-000000000020',
              'display_order': 1,
              'source_kind': 'custom',
              'item_description': 'Existing requested item',
              'requested_qty': '1',
              'unit': 'Nos',
            },
          ],
        });

        await controller.hydrateFromServer(returnedRequest);
        await controller.addCustomLine();
        final addedLine = controller.state.draft.lines.last;
        await controller.updateLine(
          addedLine.id,
          (line) => line.copyWith(
            description: 'Material not currently in inventory',
            quantity: '2',
            unit: 'Set',
          ),
        );

        final resubmitted = await controller.submit();

        expect(resubmitted, isNotNull);
        expect(repository.updateForApprovalInputs, hasLength(1));
        final input = repository.updateForApprovalInputs.single;
        expect(input.draft.serverRecordVersion, 5);
        expect(input.draft.lines, hasLength(2));
        expect(
          input.draft.lines.last.source,
          YorksV1MaterialRequestLineSource.custom,
        );
        expect(
          input.draft.lines.last.toRpcJson(),
          isNot(contains('inventory_item_id')),
        );
        expect(store.readAll(), isEmpty);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitted,
        );

        // A later return opens a fresh editor and must use the newer server
        // version instead of reviving the just-submitted version from local
        // recovery.
        final reopened = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(reopened.dispose);
        await reopened.hydrateFromServer(
          YorksV1MaterialRequest.fromRpcJson({
            'id': _draftId,
            'project_id': _projectId,
            'project_ref': 'B5-TEST',
            'project_name': 'Test Project',
            'scope_id': _scopeId,
            'scope_name': 'Common',
            'state': 'changes_requested',
            'record_version': 7,
            'created_at': '2026-08-13T00:00:00Z',
            'updated_at': '2026-08-13T00:10:00Z',
            'timing': 'normal',
            'can_edit_before_approval': true,
            'lines': [for (final line in input.draft.lines) line.toRpcJson()],
          }),
        );

        expect((await reopened.submit()), isNotNull);
        expect(repository.updateForApprovalInputs, hasLength(2));
        expect(
          repository.updateForApprovalInputs.last.draft.serverRecordVersion,
          7,
        );
        expect(store.readAll(), isEmpty);
      },
    );
  });

  test('material request export is accepted by the shared BOQ importer', () {
    final draft = YorksV1MaterialRequestDraft(
      id: _draftId,
      ownerAuthUserId: _siteEngineer,
      submissionIdempotencyKey: 'submission-key',
      projectId: _projectId,
      scopeId: _scopeId,
      updatedAt: DateTime.utc(2026, 8, 2),
      lines: [
        YorksV1MaterialRequestLine(
          id: '73000000-0000-4000-8000-000000000011',
          displayOrder: 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: 'Motorized Smoke Damper',
          size: '600 x 600',
          planningModelTag: 'MSD-01A',
          brandOrigin: 'Betec UAE',
          quantity: '1',
          unit: 'Nos',
        ),
      ],
    );

    const codec = YorksV1BoqWorkbookCodec();
    final workbook = codec.decode(
      bytes: YorksV1MaterialRequestDocumentService().buildDraftExcel(draft),
      fileName: 'material_request_draft.xlsx',
    );
    final preview = codec.preview(
      workbook: workbook,
      sheet: workbook.sheets.single,
      fallbackTitle: 'Material Request Draft',
    );
    final fields = {
      for (final column in preview.columns)
        if (column.canonicalField != null)
          column.canonicalField!: column.sourceIndex,
    };

    expect(fields[YorksV1BoqCanonicalField.description], isNotNull);
    expect(fields[YorksV1BoqCanonicalField.quantity], isNotNull);
    expect(fields[YorksV1BoqCanonicalField.unit], isNotNull);
    final exportedDescription = preview.rows.single.valueFor(
      fields[YorksV1BoqCanonicalField.description]!,
    );
    expect(exportedDescription, startsWith('Motorized Smoke Damper'));
    expect(exportedDescription, contains('Size: 600 x 600'));
    expect(exportedDescription, contains('Model / Tag: MSD-01A'));
    expect(
      preview.rows.single.valueFor(fields[YorksV1BoqCanonicalField.quantity]!),
      '1',
    );
    expect(
      preview.rows.single.valueFor(fields[YorksV1BoqCanonicalField.unit]!),
      'Nos',
    );
  });

  test('import-ready draft export keeps technical columns explicit', () {
    final draft = YorksV1MaterialRequestDraft(
      id: _draftId,
      ownerAuthUserId: _siteEngineer,
      submissionIdempotencyKey: 'submission-key',
      projectId: _projectId,
      scopeId: _scopeId,
      updatedAt: DateTime.utc(2026, 8, 27),
      lines: const [
        YorksV1MaterialRequestLine(
          id: '73000000-0000-4000-8000-000000000013',
          displayOrder: 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: 'Access Door - Single Leaf',
          size: '1000 x 2100 mm',
          model: 'AD-SL-1000',
          brandOrigin: 'Yorks / UAE',
          quantity: '2',
          unit: 'Each',
        ),
      ],
    );
    const codec = YorksV1BoqWorkbookCodec();
    final service = YorksV1MaterialRequestDocumentService();
    final workbook = codec.decode(
      bytes: service.buildDraftImportExcel(draft),
      fileName: service.suggestedDraftImportExcelName(
        draft,
        projectReference: 'YRA-322',
      ),
    );
    final preview = codec.preview(
      workbook: workbook,
      sheet: workbook.sheets.single,
      fallbackTitle: 'MR Import',
    );
    final fields = {
      for (final column in preview.columns)
        if (column.canonicalField != null)
          column.canonicalField!: column.sourceIndex,
    };

    expect(fields.keys, contains(YorksV1BoqCanonicalField.description));
    expect(fields.keys, contains(YorksV1BoqCanonicalField.size));
    expect(fields.keys, contains(YorksV1BoqCanonicalField.planningModelTag));
    expect(fields.keys, contains(YorksV1BoqCanonicalField.quantity));
    expect(fields.keys, contains(YorksV1BoqCanonicalField.unit));
    expect(fields.keys, isNot(contains(YorksV1BoqCanonicalField.unitCost)));
    expect(
      preview.rows.single.valueFor(fields[YorksV1BoqCanonicalField.size]!),
      '1000 x 2100 mm',
    );
    expect(
      preview.rows.single.valueFor(
        fields[YorksV1BoqCanonicalField.planningModelTag]!,
      ),
      'AD-SL-1000',
    );
    expect(
      service.suggestedDraftImportExcelName(draft, projectReference: 'YRA-322'),
      'YRA-322_Material_Request_Import_Ready.xlsx',
    );
  });

  test('round-trip export preserves an incomplete editable line', () {
    final draft = YorksV1MaterialRequestDraft(
      id: _draftId,
      ownerAuthUserId: _siteEngineer,
      submissionIdempotencyKey: 'submission-key',
      updatedAt: DateTime.utc(2026, 8, 2),
      lines: [
        YorksV1MaterialRequestLine(
          id: '73000000-0000-4000-8000-000000000012',
          displayOrder: 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: 'Line awaiting quantity',
          quantity: '',
          unit: 'Nos',
        ),
      ],
    );
    const codec = YorksV1BoqWorkbookCodec();
    final workbook = codec.decode(
      bytes: YorksV1MaterialRequestDocumentService().buildDraftExcel(draft),
      fileName: 'material_request_draft.xlsx',
    );
    final preview = codec.preview(
      workbook: workbook,
      sheet: workbook.sheets.single,
      fallbackTitle: 'Material Request Draft',
    );

    expect(preview.rows, hasLength(1));
    expect(
      preview.rows.single.valueFor(
        preview.columns
            .firstWhere(
              (column) =>
                  column.canonicalField == YorksV1BoqCanonicalField.description,
            )
            .sourceIndex,
      ),
      'Line awaiting quantity',
    );
  });

  test('accepts legacy BOQ and material-request headings on re-import', () {
    final worksheet = YorksV1BoqWorksheet(
      group: YorksV1BoqGroup(
        id: _boqGroupId,
        projectId: _projectId,
        name: 'Legacy export',
        worksheetTitle: 'Legacy export',
        displayOrder: 1,
        isCustom: false,
        isArchived: false,
        version: 1,
        rowCount: 1,
        columnCount: 7,
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
      columns: const [
        YorksV1BoqColumn(id: 'a', heading: 'S:No', displayOrder: 1),
        YorksV1BoqColumn(id: 'b', heading: 'Item Description', displayOrder: 2),
        YorksV1BoqColumn(id: 'c', heading: 'Model/Serial No.', displayOrder: 3),
        YorksV1BoqColumn(id: 'd', heading: 'Make/Origin', displayOrder: 4),
        YorksV1BoqColumn(id: 'e', heading: 'Qty.', displayOrder: 5),
        YorksV1BoqColumn(id: 'f', heading: 'Unit', displayOrder: 6),
        YorksV1BoqColumn(id: 'g', heading: 'Unit Cost', displayOrder: 7),
      ],
      rows: [
        YorksV1BoqRow(
          id: 'legacy-row',
          displayOrder: 1,
          values: const {
            'a': '1',
            'b': 'Fire damper',
            'c': 'MSD-01A',
            'd': 'Betec UAE',
            'e': '2',
            'f': 'Nos',
            'g': '0',
          },
          canonicalValues: const {},
        ),
      ],
    );
    const codec = YorksV1BoqWorkbookCodec();
    final workbook = codec.decode(
      bytes: codec.encodeWorksheet(worksheet),
      fileName: 'legacy_export.xlsx',
    );
    final preview = codec.preview(
      workbook: workbook,
      sheet: workbook.sheets.single,
      fallbackTitle: 'Legacy export',
    );
    final mapped = {
      for (final column in preview.columns)
        if (column.canonicalField != null)
          column.canonicalField!: column.sourceIndex,
    };

    expect(mapped[YorksV1BoqCanonicalField.description], isNotNull);
    expect(mapped[YorksV1BoqCanonicalField.quantity], isNotNull);
    expect(mapped[YorksV1BoqCanonicalField.unit], isNotNull);
    expect(mapped[YorksV1BoqCanonicalField.planningModelTag], isNotNull);
    expect(mapped[YorksV1BoqCanonicalField.brandOrigin], isNotNull);
  });

  test(
    'recognizes equipment schedule tag, description, make and quantity headings',
    () {
      final worksheet = YorksV1BoqWorksheet(
        group: YorksV1BoqGroup(
          id: _boqGroupId,
          projectId: _projectId,
          name: 'Equipment schedule',
          worksheetTitle: 'VENT.FAN',
          displayOrder: 1,
          isCustom: false,
          isArchived: false,
          version: 1,
          rowCount: 1,
          columnCount: 5,
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
        columns: const [
          YorksV1BoqColumn(id: 'tag', heading: 'Fan Tag#', displayOrder: 1),
          YorksV1BoqColumn(
            id: 'size',
            heading: 'Size (mm x mm)',
            displayOrder: 2,
          ),
          YorksV1BoqColumn(
            id: 'description',
            heading: 'Serving Area',
            displayOrder: 3,
          ),
          YorksV1BoqColumn(id: 'make', heading: 'Fan Make', displayOrder: 4),
          YorksV1BoqColumn(id: 'qty', heading: 'Fan Qty', displayOrder: 5),
        ],
        rows: [
          YorksV1BoqRow(
            id: 'equipment-row',
            displayOrder: 1,
            values: const {
              'tag': 'VF-01',
              'size': '600 x 600',
              'description': 'Substation room',
              'make': 'Yorks',
              'qty': '2',
            },
            canonicalValues: const {},
          ),
        ],
      );
      const codec = YorksV1BoqWorkbookCodec();
      final workbook = codec.decode(
        bytes: codec.encodeWorksheet(worksheet),
        fileName: 'equipment_schedule.xlsx',
      );
      final preview = codec.preview(
        workbook: workbook,
        sheet: workbook.sheets.single,
        fallbackTitle: 'Equipment schedule',
      );
      final mapped = {
        for (final column in preview.columns)
          if (column.canonicalField != null)
            column.canonicalField!: column.sourceIndex,
      };

      expect(mapped[YorksV1BoqCanonicalField.equipmentTag], isNotNull);
      expect(mapped[YorksV1BoqCanonicalField.size], isNotNull);
      expect(mapped[YorksV1BoqCanonicalField.brandOrigin], isNotNull);
      expect(mapped[YorksV1BoqCanonicalField.quantity], isNotNull);
      expect(
        preview.rows.single.valueFor(
          mapped[YorksV1BoqCanonicalField.equipmentTag]!,
        ),
        'VF-01',
      );
      expect(
        preview.rows.single.valueFor(
          mapped[YorksV1BoqCanonicalField.quantity]!,
        ),
        '2',
      );
    },
  );

  test('maps a tagged BOQ row into a complete reviewable MR line', () async {
    final controller = YorksV1MaterialRequestDraftController(
      ownerAuthUserId: _siteEngineer,
      draftId: _draftId,
      store: _MemoryStore<YorksV1MaterialRequestDraft>(),
      repository: _FakeRequestRepository(),
      uuidFactory: _Ids().next,
    );
    addTearDown(controller.dispose);
    final worksheet = YorksV1BoqWorksheet(
      group: YorksV1BoqGroup(
        id: _boqGroupId,
        projectId: _projectId,
        name: 'Ventilation Fans',
        worksheetTitle: 'VENT.FAN',
        displayOrder: 1,
        isCustom: false,
        isArchived: false,
        version: 1,
        rowCount: 1,
        columnCount: 5,
        updatedAt: DateTime.utc(2026, 8, 4),
        scopeId: _scopeId,
        scopeKind: 'common',
        scopeName: 'Common / All Buildings',
      ),
      columns: const [
        YorksV1BoqColumn(
          id: 'tag',
          heading: 'Fan Tag#',
          displayOrder: 1,
          canonicalField: YorksV1BoqCanonicalField.equipmentTag,
        ),
        YorksV1BoqColumn(id: 'area', heading: 'Serving Area', displayOrder: 2),
        YorksV1BoqColumn(
          id: 'model',
          heading: 'Model',
          displayOrder: 3,
          canonicalField: YorksV1BoqCanonicalField.model,
        ),
        YorksV1BoqColumn(
          id: 'make',
          heading: 'Fan Make',
          displayOrder: 4,
          canonicalField: YorksV1BoqCanonicalField.brandOrigin,
        ),
        YorksV1BoqColumn(
          id: 'size',
          heading: 'Dimension',
          displayOrder: 5,
          canonicalField: YorksV1BoqCanonicalField.size,
        ),
      ],
      rows: [
        YorksV1BoqRow(
          id: 'boq-row',
          displayOrder: 1,
          values: const {
            'tag': 'VF-01',
            'area': 'Generator room',
            'model': 'TA-HT-560',
            'make': 'DYNAIR',
            'size': '560 mm',
          },
          canonicalValues: const {
            'equipment_tag': 'VF-01',
            'model': 'TA-HT-560',
            'brand_origin': 'DYNAIR',
            'size': '560 mm',
          },
        ),
      ],
    );

    await controller.setProject(_projectId);
    await controller.setScope(_scopeId);
    await controller.addBoqRows(
      worksheet: worksheet,
      rowIds: const ['boq-row'],
    );

    final line = controller.state.draft.lines.single;
    expect(line.description, 'VF-01 — Generator room');
    expect(line.size, '560 mm');
    expect(line.model, 'TA-HT-560');
    expect(line.equipmentTag, 'VF-01');
    expect(line.brandOrigin, 'DYNAIR');
    expect(line.quantity, '1');
    expect(line.quantityIsSuggested, isTrue);
    expect(line.unit, 'Nos');
  });

  test('non-commercial response has no commercial client state', () {
    final request = YorksV1MaterialRequest.fromRpcJson({
      'id': _draftId,
      'project_id': _projectId,
      'project_ref': 'B5-TEST',
      'project_name': 'Test Project',
      'job_contract_reference': 'N-19957.2',
      'scope_id': _scopeId,
      'scope_name': 'Common',
      'state': 'submitted',
      'record_version': 1,
      'created_at': '2026-08-02T00:00:00Z',
      'updated_at': '2026-08-02T00:00:00Z',
      'timing': 'normal',
      'lines': [
        {
          'id': '73000000-0000-4000-8000-000000000001',
          'display_order': 1,
          'source_kind': 'custom',
          'item_description': 'Duct tape',
          'requested_qty': '2',
          'unit': 'Roll',
        },
      ],
    });

    expect(request.lines.single.unitCost, isNull);
    expect(request.lines.single.totalCost, isNull);
    expect(request.lines.single.currencyCode, isNull);
    expect(request.jobContractReference, 'N-19957.2');
  });

  test('normalizes only the first material-description character', () {
    final line = YorksV1MaterialRequestLine(
      id: _draftId,
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: 'duct insulation 25 mm',
      quantity: '1',
      unit: 'Roll',
    );

    expect(
      line.copyWith(description: 'fire rated sealant').description,
      'Fire rated sealant',
    );
    expect(line.toDraftJson()['description'], 'Duct insulation 25 mm');
    expect(line.toRpcJson()['item_description'], 'Duct insulation 25 mm');

    final normalized = line.copyWith(
      brandOrigin: 'betec CAD / uAE',
      size: 'large 600 x 600',
      model: 'model-x remains mixed',
      equipmentTag: 'tag-a1 remains mixed',
      planningModelTag: 'planning-a1 remains mixed',
    );
    expect(normalized.brandOrigin, 'Betec CAD / uAE');
    expect(normalized.size, 'Large 600 x 600');
    expect(normalized.model, 'Model-x remains mixed');
    expect(normalized.equipmentTag, 'Tag-a1 remains mixed');
    expect(normalized.planningModelTag, 'Planning-a1 remains mixed');
    expect(normalized.toRpcJson()['brand_origin'], 'Betec CAD / uAE');
    expect(normalized.toRpcJson()['technical_attributes'], {
      'size': 'Large 600 x 600',
      'model': 'Model-x remains mixed',
      'equipment_tag': 'Tag-a1 remains mixed',
      'planning_model_tag': 'Planning-a1 remains mixed',
    });
  });

  test(
    'technical planning fields stay separate from commercial and receipt data',
    () {
      final line = YorksV1MaterialRequestLine.fromRpcJson({
        'id': _draftId,
        'display_order': 1,
        'source_kind': 'boq',
        'item_description': 'Fire damper',
        'technical_attributes': {
          'size': '600 x 600',
          'model': 'MSD-600',
          'equipment_tag': 'MSD-01A',
          'quantity_suggested': 'true',
          'planning_model_tag': 'MSD-01A',
        },
        'requested_qty': '2',
        'unit': 'Nos',
      });

      expect(line.size, '600 x 600');
      expect(line.model, 'MSD-600');
      expect(line.equipmentTag, 'MSD-01A');
      expect(line.quantityIsSuggested, isTrue);
      expect(line.planningModelTag, 'MSD-01A');
      expect(line.unitCost, isNull);
      expect(line.toRpcJson()['technical_attributes'], {
        'size': '600 x 600',
        'model': 'MSD-600',
        'equipment_tag': 'MSD-01A',
        'planning_model_tag': 'MSD-01A',
        'quantity_suggested': true,
      });
    },
  );

  test('Material Request PDF uses the controlled A4 print layout', () async {
    final request = YorksV1MaterialRequest(
      id: _draftId,
      projectId: _projectId,
      projectReference: 'YRA-123',
      projectName: 'Yorks Test Project',
      jobContractReference: 'N-19957.2',
      scopeId: _scopeId,
      scopeName: 'Common / All Buildings',
      state: YorksV1MaterialRequestState.submitted,
      recordVersion: 2,
      createdAt: DateTime.utc(2026, 8, 3),
      updatedAt: DateTime.utc(2026, 8, 3),
      submittedAt: DateTime.utc(2026, 8, 3),
      timing: YorksV1MaterialRequestTiming.normal,
      requestNumber: 'YRA123-MR101',
      requesterDisplayName: 'Project Engineer',
      requesterProjectRole: 'Project Engineer',
      requesterExactRole: 'senior_mechanical_engineer',
      lines: const [
        YorksV1MaterialRequestLine(
          id: 'line-1',
          displayOrder: 1,
          source: YorksV1MaterialRequestLineSource.custom,
          description: 'Motorized smoke damper',
          size: '600 x 600',
          planningModelTag: 'MSD-01A',
          brandOrigin: 'UAE',
          quantity: '2',
          unit: 'Nos',
          unitCost: '110.29',
          totalCost: '220.58',
          currencyCode: 'AED',
        ),
      ],
    );

    final bytes = await YorksV1MaterialRequestDocumentService()
        .buildDocumentPdf(
          YorksV1MaterialRequestDocumentModel(
            request: request,
            arrangement: YorksV1MaterialRequestDocumentActor(
              displayName: 'Procurement User',
              role: 'procurement',
              reference: 'Arrangement v1',
              actedAt: DateTime.utc(2026, 8, 3, 9),
            ),
            approval: YorksV1MaterialRequestDocumentActor(
              displayName: 'Senior Engineer',
              role: 'senior_mechanical_engineer',
              reference: 'Request v2',
              actedAt: DateTime.utc(2026, 8, 3, 8),
            ),
            dispatch: YorksV1MaterialRequestDocumentActor(
              displayName: 'Procurement User',
              role: 'procurement',
              reference: 'YRA/DN/101/2026',
              actedAt: DateTime.utc(2026, 8, 3, 10),
            ),
            receiptStatuses: const {'line-1': 'received'},
          ),
          PdfPageFormat.a4,
        );

    expect(bytes.length, greaterThan(500));
    expect(utf8.decode(bytes.take(4).toList()), equals('%PDF'));
    expect(YorksV1MaterialRequestStrings.procurement.primary, 'Procurement by');
    expect(YorksV1MaterialRequestStrings.approvedBy.primary, 'Approved by');
    expect(
      YorksV1MaterialRequestStrings.orderedDispatched.primary,
      'Ordered / Dispatched by',
    );
    expect(
      YorksV1CompanyDocumentStrings.legalName.ar,
      'يوركس للتكييف والتبريد - ذ.م.م - ش.ش.و',
    );
    if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
      await Directory('output/pdf').create(recursive: true);
      await File(
        'output/pdf/r35-material-request.pdf',
      ).writeAsBytes(bytes, flush: true);
    }
    expect(
      YorksV1CompanyDocumentStrings.qualifiedProjectName(
        projectName: request.projectName,
        jobContractReference: request.jobContractReference,
      ),
      'N-19957.2-Yorks Test Project',
    );
  });

  test('Material Request projections retain the exact requester role', () {
    final request = YorksV1MaterialRequest.fromRpcJson({
      'id': _draftId,
      'project_id': _projectId,
      'project_ref': 'YRA-123',
      'project_name': 'Yorks Test Project',
      'scope_id': _scopeId,
      'scope_name': 'Common / All Buildings',
      'state': 'submitted',
      'record_version': 2,
      'created_at': '2026-08-11T00:00:00Z',
      'updated_at': '2026-08-11T00:00:00Z',
      'timing': 'normal',
      'requester_project_role': 'project_engineer',
      'requester_exact_role': 'senior_mechanical_engineer',
      'lines': const [],
    });

    expect(request.requesterProjectRole, 'project_engineer');
    expect(request.requesterExactRole, 'senior_mechanical_engineer');
    expect(
      YorksV1MaterialRequestDocumentService.requesterRoleLabel(request),
      'Senior Mechanical Engineer',
    );
  });

  test(
    'parses approval-first decision, comments, mentions and action flags',
    () {
      final request = YorksV1MaterialRequest.fromRpcJson({
        'id': _draftId,
        'project_id': _projectId,
        'project_ref': 'YRA-123',
        'project_name': 'Yorks Test Project',
        'scope_id': _scopeId,
        'scope_name': 'Common / All Buildings',
        'state': 'awaiting_request_approval',
        'record_version': 2,
        'created_at': '2026-08-13T00:00:00Z',
        'updated_at': '2026-08-13T00:00:00Z',
        'timing': 'normal',
        'can_edit_before_approval': true,
        'can_decide_request': true,
        'request_decision': {
          'id': 'decision-1',
          'decision': 'returned',
          'reason': 'Clarify the model',
          'request_record_version': 1,
          'decided_by_display_name': 'Senior Engineer',
          'decided_by_role': 'project_engineer',
          'decided_by_exact_role': 'senior_mechanical_engineer',
          'decided_at': '2026-08-13T01:00:00Z',
        },
        'comments': [
          {
            'id': 'comment-1',
            'request_id': _draftId,
            'body': 'Please review this item.',
            'author_auth_user_id': 'author-1',
            'author_role': 'project_engineer',
            'author_exact_role': 'project_manager',
            'author_display_name': 'Project Manager',
            'created_at': '2026-08-13T02:00:00Z',
            'conversation_id': 'conversation-1',
            'parent_comment_id': 'comment-root',
            'reply_preview': {
              'id': 'comment-root',
              'sender_display_name': 'Site Engineer',
              'body': 'Please confirm the model.',
            },
            'context': {'type': 'request_line', 'entity_id': 'line-1'},
            'attachments': [
              {
                'id': 'attachment-1',
                'file_name': 'drawing.pdf',
                'mime_type': 'application/pdf',
                'byte_size': 2048,
              },
            ],
            'mentions': [
              {
                'auth_user_id': 'mentioned-1',
                'display_name': 'Site Engineer',
                'exact_role': 'site_engineer',
              },
            ],
          },
        ],
        'lines': const [],
      });

      expect(
        request.state,
        YorksV1MaterialRequestState.awaitingRequestApproval,
      );
      expect(request.canEditBeforeApproval, isTrue);
      expect(request.canDecideRequest, isTrue);
      expect(
        request.requestDecision?.decidedByExactRole,
        'senior_mechanical_engineer',
      );
      expect(request.comments.single.authorExactRole, 'project_manager');
      expect(request.comments.single.mentions.single.authUserId, 'mentioned-1');
      expect(request.comments.single.conversationId, 'conversation-1');
      expect(request.comments.single.parentCommentId, 'comment-root');
      expect(request.comments.single.replyPreview?.body, contains('model'));
      expect(request.comments.single.contextType, 'request_line');
      expect(
        request.comments.single.attachments.single.fileName,
        'drawing.pdf',
      );
    },
  );

  test(
    'Material Request document parses truthful partial-dispatch progress',
    () {
      final model = YorksV1MaterialRequestDocumentModel.fromRpcJson({
        'request': {
          'id': _draftId,
          'project_id': _projectId,
          'project_ref': 'YRA-123',
          'project_name': 'Yorks Test Project',
          'scope_id': _scopeId,
          'scope_name': 'Common / All Buildings',
          'state': 'approved',
          'record_version': 3,
          'created_at': '2026-08-11T00:00:00Z',
          'updated_at': '2026-08-11T00:00:00Z',
          'timing': 'normal',
          'lines': [
            {
              'id': 'line-1',
              'display_order': 1,
              'source': 'custom',
              'item_description': 'Damper',
              'requested_qty': '10',
              'unit': 'Nos',
            },
          ],
        },
        'show_line_status': true,
        'receipt_statuses': const [
          {
            'request_line_id': 'line-1',
            'requested_qty': '10.0000',
            'fulfilled_qty': '5.0000',
            'status': 'Partial',
          },
        ],
      });

      expect(model.showLineStatus, isTrue);
      expect(model.receiptStatuses['line-1'], '5 / 10 · Partial');
    },
  );

  test('Phase 2 summary stays lightweight while retaining register counts', () {
    final page = YorksV1MaterialRequestSummaryPage.fromRpcJson({
      'items': [
        {
          'id': _draftId,
          'project_id': _projectId,
          'project_ref': 'YRA-313',
          'project_name': 'Phase 2 Project',
          'scope_id': _scopeId,
          'scope_name': 'Common / All Buildings',
          'state': 'submitted',
          'record_version': 2,
          'request_number': 'YRA313-MR001',
          'title': 'Dampers',
          'timing': 'normal',
          'current_action_started_at': '2026-08-21T04:00:00Z',
          'current_action_age_hours': 4.5,
          'required_on_site_overdue': false,
          'actor_can_act': true,
          'exception_codes': ['partial_arrangement', 'late_external_supply'],
          'item_count': 27,
          'created_at': '2026-08-20T08:00:00Z',
          'updated_at': '2026-08-21T08:00:00Z',
          'work_assignment': {
            'request_id': _draftId,
            'assignment_version': 0,
            'assignee_auth_user_id': null,
            'assignee_display_name': null,
            'assignee_exact_role': null,
            'assigned_at': null,
            'can_manage': true,
          },
          'change_summary': null,
        },
      ],
      'total_count': 31,
      'limit': 15,
      'offset': 0,
      'has_more': true,
      'metrics': {
        'total': 31,
        'open': 9,
        'in_progress': 8,
        'dispatched': 5,
        'received': 4,
        'closed': 5,
        'my_work': 3,
        'exceptions': 2,
        'required_date_overdue': 1,
      },
    });

    final register = page.items.single.toRegisterProjection();
    expect(page.totalCount, 31);
    expect(page.limit, 15);
    expect(page.hasMore, isTrue);
    expect(register.lines, isEmpty);
    expect(register.comments, isEmpty);
    expect(register.displayItemCount, 27);
    expect(register.requestNumber, 'YRA313-MR001');
    expect(register.actorCanAct, isTrue);
    expect(register.currentActionAgeHours, 4.5);
    expect(register.exceptionCodes, const [
      YorksV1MaterialRequestExceptionCode.partialArrangement,
      YorksV1MaterialRequestExceptionCode.lateExternalSupply,
    ]);
    expect(page.metrics.myWork, 3);
    expect(page.metrics.exceptions, 2);
    expect(page.metrics.requiredDateOverdue, 1);
  });

  test('action intelligence parses metrics and register views safely', () {
    final dashboard =
        YorksV1MaterialRequestOperationsDashboard.fromRpcJson(const {
          'my_work_count': 4,
          'exception_request_count': 3,
          'required_date_overdue_count': 2,
          'action_due_policy': 'not_configured',
          'average_approval_hours': 6.25,
          'average_arrangement_hours': 9.5,
          'warehouse_fill_rate_percent': 82.75,
          'average_receipt_turnaround_hours': 3.5,
          'outstanding_replacement_quantity': '12.5000',
          'average_return_closure_hours': 18,
        });
    final myWorkQuery = YorksV1MaterialRequestSummaryQuery(
      registerView: YorksV1MaterialRequestRegisterView.myWork,
    );
    final exceptionQuery = YorksV1MaterialRequestSummaryQuery(
      registerView: YorksV1MaterialRequestRegisterView.exceptions,
    );

    expect(dashboard.myWorkCount, 4);
    expect(dashboard.exceptionRequestCount, 3);
    expect(dashboard.requiredDateOverdueCount, 2);
    expect(dashboard.actionDuePolicy, 'not_configured');
    expect(dashboard.averageApprovalHours, 6.25);
    expect(dashboard.warehouseFillRatePercent, 82.75);
    expect(dashboard.outstandingReplacementQuantity, '12.5000');
    expect(myWorkQuery.toRpcParameters()['p_register_view'], 'my_work');
    expect(exceptionQuery.toRpcParameters()['p_register_view'], 'exceptions');
  });

  test(
    'phone register groups every current and retained workflow state once',
    () {
      expect(
        yorksV1MaterialRequestSubmittedRegisterStates,
        equals({
          YorksV1MaterialRequestState.submitted,
          YorksV1MaterialRequestState.awaitingRequestApproval,
          YorksV1MaterialRequestState.changesRequested,
          YorksV1MaterialRequestState.approvedForArrangement,
          YorksV1MaterialRequestState.arranging,
          YorksV1MaterialRequestState.awaitingApproval,
        }),
      );
      expect(
        yorksV1MaterialRequestApprovedRegisterStates,
        equals({
          YorksV1MaterialRequestState.approved,
          YorksV1MaterialRequestState.partiallyDispatched,
          YorksV1MaterialRequestState.dispatched,
          YorksV1MaterialRequestState.partiallyReceived,
          YorksV1MaterialRequestState.received,
          YorksV1MaterialRequestState.closed,
        }),
      );
      expect(
        yorksV1MaterialRequestSubmittedRegisterStates.intersection(
          yorksV1MaterialRequestApprovedRegisterStates,
        ),
        isEmpty,
      );
      expect(
        yorksV1MaterialRequestSubmittedRegisterStates.contains(
          YorksV1MaterialRequestState.cancelled,
        ),
        isFalse,
      );
    },
  );

  test('register owner and next action use authoritative projection facts', () {
    final request = YorksV1MaterialRequest(
      id: 'owner-action-request',
      projectId: 'project-1',
      projectReference: 'YRA-001',
      projectName: 'Project one',
      scopeId: 'scope-1',
      scopeName: 'Building A',
      state: YorksV1MaterialRequestState.partiallyReceived,
      recordVersion: 1,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 2),
      timing: YorksV1MaterialRequestTiming.normal,
      lines: const [],
      currentActionOwnerRole: 'procurement',
      currentActionCode: 'replacement_dispatch_required',
    );

    expect(
      yorksV1MaterialRequestOwnerRoleCopy(
        request.currentActionOwnerRole,
      ).primary,
      'Procurement',
    );
    expect(
      yorksV1MaterialRequestNextActionCopy(request).primary,
      'Replacement dispatch required',
    );
    expect(
      yorksV1MaterialRequestOwnerRoleCopy(null).primary,
      'No active owner',
    );
  });

  for (final syncFailure in <Object?>[
    null,
    const YorksV1DomainException(YorksV1DomainErrorCode.conflict),
    StateError('transport interrupted'),
  ]) {
    test(
      'private sync cannot replace pending submission: $syncFailure',
      () async {
        final syncBlocker = Completer<void>();
        final submitBlocker = Completer<void>();
        final repository = _Phase2FakeRequestRepository()
          ..privateSyncDelay = syncBlocker.future
          ..privateSyncFailure = syncFailure
          ..submitDelay = submitBlocker.future;
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
          privateSyncDebounce: Duration.zero,
        );
        addTearDown(controller.dispose);
        await controller.setProject(_projectId);
        await controller.setScope(_scopeId);
        await controller.addCustomLine();
        await controller.updateLine(
          controller.currentDraft.lines.single.id,
          (line) =>
              line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
        );
        await repository.firstPrivateSyncStarted.future;
        final submission = controller.submit();
        final intentKey = controller.currentDraft.submissionIdempotencyKey;
        syncBlocker.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitting,
        );
        expect(controller.currentDraft.submissionIdempotencyKey, intentKey);
        expect(await controller.submit(), isNull);
        expect(repository.saveAndSubmitInputs, hasLength(1));
        submitBlocker.complete();
        expect(await submission, isNotNull);
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.submitted,
        );
        expect(store.readAll(), isEmpty);
      },
    );
  }

  test(
    'late recovery success cannot recreate a submitted local draft',
    () async {
      final blocker = Completer<void>();
      final repository = _Phase2FakeRequestRepository()
        ..privateSyncDelay = blocker.future;
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: store,
        repository: repository,
        uuidFactory: _Ids().next,
        privateSyncDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.setProject(_projectId);
      await controller.setScope(_scopeId);
      await controller.addCustomLine();
      await controller.updateLine(
        controller.currentDraft.lines.single.id,
        (line) =>
            line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
      );
      await repository.firstPrivateSyncStarted.future;
      expect(await controller.submit(), isNotNull);
      blocker.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.state.status,
        YorksV1MaterialRequestDraftSyncStatus.submitted,
      );
      expect(store.readAll(), isEmpty);
    },
  );

  test(
    'connected submission cancels queued autosave and rejects pending edits',
    () async {
      final blocker = Completer<void>();
      final repository = _Phase2FakeRequestRepository()
        ..submitDelay = blocker.future;
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: repository,
        uuidFactory: _Ids().next,
        privateSyncDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.setProject(_projectId);
      await controller.setScope(_scopeId);
      await controller.addCustomLine();
      await controller.updateLine(
        controller.currentDraft.lines.single.id,
        (line) =>
            line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
      );
      final intent = controller.currentDraft;
      final submission = controller.submit();
      await controller.setTitle('Late callback');
      await Future<void>.delayed(Duration.zero);
      expect(repository.privateSyncCallCount, 0);
      expect(
        controller.currentDraft.toSaveInput().toRpcPayload(),
        intent.toSaveInput().toRpcPayload(),
      );
      expect(
        controller.currentDraft.submissionIdempotencyKey,
        intent.submissionIdempotencyKey,
      );
      blocker.complete();
      expect(await submission, isNotNull);
    },
  );

  for (final saveOnly in [false, true]) {
    for (final failure in <Object?>[
      null,
      const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
    ]) {
      test(
        'disposed command ignores late result: save=$saveOnly, $failure',
        () async {
          final blocker = Completer<void>();
          final repository = _FakeRequestRepository()
            ..submitDelay = blocker.future
            ..submitFailure = failure
            ..saveDelay = blocker.future
            ..saveFailure = failure;
          final store = _MemoryStore<YorksV1MaterialRequestDraft>();
          final controller = YorksV1MaterialRequestDraftController(
            ownerAuthUserId: _siteEngineer,
            draftId: _draftId,
            store: store,
            repository: repository,
            uuidFactory: _Ids().next,
          );
          await controller.setProject(_projectId);
          await controller.setScope(_scopeId);
          await controller.addCustomLine();
          await controller.updateLine(
            controller.currentDraft.lines.single.id,
            (line) =>
                line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
          );
          final submission = saveOnly
              ? controller.saveConnected()
              : controller.submit();
          await Future<void>.delayed(Duration.zero);
          controller.dispose();
          blocker.complete();
          expect(await submission, saveOnly ? isFalse : isNull);
          expect(store.readAll(), hasLength(1));
        },
      );
    }
  }

  for (final approve in [false, true]) {
    test(
      'lost response reconciles original frozen intent, approve=$approve',
      () async {
        final repository = _RecoveryRequestRepository();
        final store = _MemoryStore<YorksV1MaterialRequestDraft>();
        final controller = await _recoveryController(repository, store);
        expect(
          approve
              ? await controller.submitAndApprove()
              : await controller.submit(),
          isNull,
        );
        expect(
          controller.state.status,
          YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
        );
        final intent = controller.currentDraft;
        expect(intent.pendingSubmissionApproval, approve);
        await controller.setTitle('Must not change unresolved intent');
        await controller.saveConnected();
        expect(controller.currentDraft, same(intent));
        expect(repository.writeCount, 1);
        // Simulate a browser restart using the actual draft JSON format.
        final persisted = YorksV1MaterialRequestDraft.fromJson(
          store.readAll().single.toJson(),
        );
        controller.dispose();
        await store.writeAll([persisted]);
        final reopened = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: _siteEngineer,
          draftId: _draftId,
          store: store,
          repository: repository,
          uuidFactory: _Ids().next,
        );
        addTearDown(reopened.dispose);
        expect(
          reopened.state.status,
          YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
        );
        final result = await reopened.reconcileSubmission();
        expect(result?.id, _draftId);
        expect(repository.checkedModes, [approve]);
        expect(repository.writeCount, 1);
        expect(repository.commitCount, 1);
        expect(store.readAll(), isEmpty);
      },
    );
  }

  test(
    'unconfirmed read permits only explicit retry of unchanged intent',
    () async {
      final repository = _RecoveryRequestRepository()
        ..commitBeforeFailure = false;
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = await _recoveryController(repository, store);
      addTearDown(controller.dispose);
      expect(await controller.submit(), isNull);
      expect(await controller.retryUnconfirmedSubmission(), isNull);
      expect(repository.writeCount, 1);
      expect(await controller.reconcileSubmission(), isNull);
      expect(controller.state.canRetryUnconfirmed, isTrue);
      expect(repository.writeCount, 1);
      repository.loseResponse = false;
      expect(await controller.retryUnconfirmedSubmission(), isNotNull);
      expect(repository.writeCount, 2);
      expect(repository.commitCount, 1);
      expect(
        repository.intents[0].submissionIdempotencyKey,
        repository.intents[1].submissionIdempotencyKey,
      );
      expect(
        repository.intents[0].toSaveInput().toRpcPayload(),
        repository.intents[1].toSaveInput().toRpcPayload(),
      );
    },
  );

  test('a denied retry cannot resolve the original unknown outcome', () async {
    final repository = _RecoveryRequestRepository()
      ..commitBeforeFailure = false;
    final store = _MemoryStore<YorksV1MaterialRequestDraft>();
    final controller = await _recoveryController(repository, store);
    addTearDown(controller.dispose);
    await controller.submit();
    final key = controller.currentDraft.submissionIdempotencyKey;
    await controller.reconcileSubmission();
    repository.writeFailure = const YorksV1DomainException(
      YorksV1DomainErrorCode.unauthorized,
      serverCode: '42501',
    );
    expect(await controller.retryUnconfirmedSubmission(), isNull);
    expect(
      controller.state.status,
      YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
    );
    expect(controller.currentDraft.submissionIdempotencyKey, key);
    expect(controller.currentDraft.pendingSubmissionApproval, isFalse);
    expect(store.readAll(), isNotEmpty);
    expect(controller.state.canRetryUnconfirmed, isFalse);
  });

  test(
    'unavailable or denied reconciliation never clears draft or enables retry',
    () async {
      final repository = _RecoveryRequestRepository()
        ..lookupFailure = const YorksV1DomainException(
          YorksV1DomainErrorCode.unauthorized,
        );
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = await _recoveryController(repository, store);
      addTearDown(controller.dispose);
      await controller.submit();
      expect(await controller.reconcileSubmission(), isNull);
      expect(
        controller.state.status,
        YorksV1MaterialRequestDraftSyncStatus.outcomeUnknown,
      );
      expect(controller.state.canRetryUnconfirmed, isFalse);
      expect(store.readAll(), hasLength(1));
      expect(await controller.retryUnconfirmedSubmission(), isNull);
      expect(repository.writeCount, 1);
    },
  );

  test(
    'disposal during status read retains owner recovery and ignores late result',
    () async {
      final blocker = Completer<void>();
      final repository = _RecoveryRequestRepository()
        ..lookupDelay = blocker.future;
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = await _recoveryController(repository, store);
      await controller.submit();
      final check = controller.reconcileSubmission();
      expect(await controller.reconcileSubmission(), isNull);
      controller.dispose();
      blocker.complete();
      expect(await check, isNull);
      expect(store.readAll(), hasLength(1));
      expect(repository.checkedModes, hasLength(1));
    },
  );

  test(
    'account switch during result check cannot clear the prior owner draft',
    () async {
      var currentOwner = true;
      final blocker = Completer<void>();
      final repository = _RecoveryRequestRepository()
        ..lookupDelay = blocker.future;
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = await _recoveryController(
        repository,
        store,
        isCurrentOwner: () => currentOwner,
      );
      addTearDown(controller.dispose);
      await controller.submit();
      final check = controller.reconcileSubmission();
      currentOwner = false;
      blocker.complete();
      expect(await check, isNull);
      expect(store.readAll(), hasLength(1));
      expect(await controller.submit(), isNull);
      expect(repository.writeCount, 1);
    },
  );

  test(
    'private autosave serializes requests and never restores an older row edit',
    () async {
      final repository = _Phase2FakeRequestRepository();
      final blocker = Completer<void>();
      repository
        ..privateSyncDelay = blocker.future
        ..privateSyncFailure = Exception('offline');
      final store = _MemoryStore<YorksV1MaterialRequestDraft>();
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: store,
        repository: repository,
        uuidFactory: _Ids().next,
        privateSyncDebounce: const Duration(milliseconds: 1),
      );
      addTearDown(controller.dispose);

      await controller.addCustomLine();
      final lineId = controller.state.draft.lines.single.id;
      await controller.updateLine(
        lineId,
        (line) => line.copyWith(
          description: 'Supply air diffuser',
          quantity: '10',
          unit: 'Nos',
        ),
      );
      await repository.firstPrivateSyncStarted.future;
      expect(repository.activePrivateSyncs, 1);

      await controller.updateLine(
        lineId,
        (line) => line.copyWith(quantity: '25'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repository.maxConcurrentPrivateSyncs, 1);

      blocker.complete();
      await repository.secondPrivateSyncStarted.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.privateSyncCallCount, 2);
      expect(repository.maxConcurrentPrivateSyncs, 1);
      expect(controller.state.draft.lines.single.quantity, '25');
      expect(store.readAll().single.lines.single.quantity, '25');
    },
  );

  test(
    'delayed private hydration cannot overwrite edits made after opening',
    () async {
      final repository = _Phase2FakeRequestRepository();
      final blocker = Completer<void>();
      final remoteUpdatedAt = DateTime.utc(2026, 8, 28, 8);
      final remoteDraft =
          YorksV1MaterialRequestDraft.empty(
            id: _draftId,
            ownerAuthUserId: _siteEngineer,
            submissionIdempotencyKey: 'remote-submission-key',
          ).copyWith(
            title: 'Older server title',
            privateSyncVersion: 1,
            updatedAt: remoteUpdatedAt,
          );
      repository
        ..privateDraft = YorksV1PrivateMaterialRequestDraftRecord(
          draftId: _draftId,
          syncVersion: 1,
          draft: remoteDraft,
          clientUpdatedAt: remoteUpdatedAt,
          serverUpdatedAt: remoteUpdatedAt,
        )
        ..privateHydrationDelay = blocker.future;
      final controller = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: repository,
        uuidFactory: _Ids().next,
        privateSyncDebounce: const Duration(hours: 1),
      );
      addTearDown(controller.dispose);

      final firstHydration = controller.hydratePrivateDraft();
      final duplicateHydration = controller.hydratePrivateDraft();
      await controller.setTitle('Live engineer edit');
      blocker.complete();
      await Future.wait([firstHydration, duplicateHydration]);

      expect(repository.privateHydrationCallCount, 1);
      expect(controller.state.draft.title, 'Live engineer edit');
      expect(controller.state.draft.privateSyncVersion, 0);
      expect(
        controller.state.status,
        YorksV1MaterialRequestDraftSyncStatus.conflict,
      );
    },
  );

  test(
    'Phase 2 draft recovery follows the owner and deletes across devices',
    () async {
      final repository = _Phase2FakeRequestRepository();
      final first = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: _MemoryStore<YorksV1MaterialRequestDraft>(),
        repository: repository,
        uuidFactory: _Ids().next,
        privateSyncDebounce: const Duration(milliseconds: 10),
      );
      addTearDown(first.dispose);

      await first.setTitle('Cross-device dampers');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repository.privateDraft?.syncVersion, 1);
      expect(
        first.state.status,
        YorksV1MaterialRequestDraftSyncStatus.savedToAccount,
      );

      final secondStore = _MemoryStore<YorksV1MaterialRequestDraft>();
      final second = YorksV1MaterialRequestDraftController(
        ownerAuthUserId: _siteEngineer,
        draftId: _draftId,
        store: secondStore,
        repository: repository,
        uuidFactory: _Ids().next,
      );
      addTearDown(second.dispose);
      await second.hydratePrivateDraft();

      expect(second.state.draft.title, 'Cross-device dampers');
      expect(second.state.draft.privateSyncVersion, 1);
      expect(
        second.state.status,
        YorksV1MaterialRequestDraftSyncStatus.savedToAccount,
      );

      await second.discardLocal(requireServerConfirmation: true);
      expect(repository.privateDraft, isNull);
      expect(secondStore.readAll(), isEmpty);
    },
  );
}

const _siteEngineer = '10000000-0000-4000-8000-000000000002';
const _projectId = '71000000-0000-4000-8000-000000000001';
const _scopeId = '72000000-0000-4000-8000-000000000001';
const _draftId = '73000000-0000-4000-8000-000000000001';
const _boqGroupId = '75000000-0000-4000-8000-000000000001';
const _boqRowId = '75000000-0000-4000-8000-000000000002';

YorksV1BoqWorksheet _scopedWorksheet({required String scopeId}) =>
    YorksV1BoqWorksheet(
      group: YorksV1BoqGroup(
        id: _boqGroupId,
        projectId: _projectId,
        name: 'Dampers',
        worksheetTitle: 'Dampers',
        displayOrder: 1,
        isCustom: false,
        isArchived: false,
        version: 1,
        rowCount: 2,
        columnCount: 3,
        updatedAt: DateTime.utc(2026, 8, 2),
        scopeId: scopeId,
        scopeKind: 'common',
        scopeName: 'Common / All Buildings',
      ),
      columns: const [
        YorksV1BoqColumn(
          id: 'description-column',
          heading: 'Description',
          displayOrder: 1,
          canonicalField: YorksV1BoqCanonicalField.description,
        ),
        YorksV1BoqColumn(
          id: 'quantity-column',
          heading: 'Qty',
          displayOrder: 2,
          canonicalField: YorksV1BoqCanonicalField.quantity,
        ),
        YorksV1BoqColumn(
          id: 'unit-column',
          heading: 'Unit',
          displayOrder: 3,
          canonicalField: YorksV1BoqCanonicalField.unit,
        ),
      ],
      rows: [
        YorksV1BoqRow(
          id: 'boq-row-1',
          displayOrder: 1,
          values: const {
            'description-column': 'Damper A',
            'quantity-column': '4',
            'unit-column': 'Nos',
          },
          canonicalValues: const {},
        ),
        YorksV1BoqRow(
          id: 'boq-row-2',
          displayOrder: 2,
          values: const {
            'description-column': 'Damper B',
            'quantity-column': '2',
            'unit-column': 'Nos',
          },
          canonicalValues: const {},
        ),
      ],
    );

YorksV1MaterialRequestLine _line(String id, String description) =>
    YorksV1MaterialRequestLine(
      id: id,
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: description,
      quantity: '1',
      unit: 'Nos',
    );

class _MemoryStore<T> implements CollectionStore<T> {
  final List<T> _items = [];

  @override
  bool get isSeeded => true;

  @override
  List<T> readAll() => List<T>.of(_items);

  @override
  Future<void> writeAll(List<T> items) async {
    _items
      ..clear()
      ..addAll(items);
  }
}

class _SlowMemoryStore<T> extends _MemoryStore<T> {
  @override
  Future<void> writeAll(List<T> items) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await super.writeAll(items);
  }
}

class _Ids {
  int _value = 0;
  String next() =>
      '74000000-0000-4000-8000-${(_value++).toString().padLeft(12, '0')}';
}

class _FakeRequestRepository implements YorksV1MaterialRequestRepository {
  final List<YorksV1SaveMaterialRequestDraftInput> saveInputs = [];
  final List<YorksV1SubmitMaterialRequestInput> submitInputs = [];
  final List<YorksV1MaterialRequestDraft> saveAndSubmitInputs = [];
  final List<YorksV1MaterialRequestDraft> saveSubmitAndApproveInputs = [];
  final List<YorksV1UpdateMaterialRequestForApprovalInput>
  updateForApprovalInputs = [];
  Object? saveFailure;
  Object? submitFailure;
  final List<Object> submitFailures = [];
  YorksV1MaterialRequest? requestResult;
  Future<void>? saveDelay;
  Future<void>? submitDelay;

  @override
  Future<List<YorksV1MaterialRequestComment>> addComment(
    YorksV1AddMaterialRequestCommentInput input,
  ) async => const [];

  @override
  Future<YorksV1MaterialRequest> decideRequest(
    YorksV1DecideMaterialRequestInput input,
  ) async => _request(
    requestId: input.requestId,
    version: input.expectedVersion + 1,
    number: 'B5TEST-MR001',
  );

  @override
  Future<List<YorksV1MaterialRequestMention>> listMentionCandidates(
    String requestId,
  ) async => const [];

  @override
  Future<List<YorksV1MaterialRequestInventorySuggestion>> searchInventory({
    required String projectId,
    required String scopeId,
    required String query,
  }) async => const [];

  @override
  Future<YorksV1MaterialRequest> updateForApproval(
    YorksV1UpdateMaterialRequestForApprovalInput input,
  ) async {
    updateForApprovalInputs.add(input);
    return _request(
      requestId: input.draft.id,
      version: input.draft.serverRecordVersion + 1,
      number: 'B5TEST-MR001',
    );
  }

  @override
  Future<YorksV1MaterialRequest> cancel(
    YorksV1CancelMaterialRequestInput input,
  ) async => _request(
    requestId: input.requestId,
    version: input.expectedVersion + 1,
    number: 'B5TEST-MR001',
  );

  @override
  Future<YorksV1MaterialRequest> close(
    YorksV1CloseMaterialRequestInput input,
  ) async => _request(
    requestId: input.requestId,
    version: input.expectedVersion + 1,
    number: 'B5TEST-MR001',
  );

  @override
  Future<void> deleteDraft(String requestId) async {}

  @override
  Future<YorksV1MaterialRequest> getRequest(String requestId) async =>
      requestResult ??
      _request(requestId: requestId, version: 2, number: 'B5TEST-MR001');

  @override
  Future<YorksV1MaterialRequestDocumentModel> getDocumentModel(
    String requestId,
  ) async => YorksV1MaterialRequestDocumentModel.fromRequest(
    _request(requestId: requestId, version: 2, number: 'B5TEST-MR001'),
  );

  @override
  Future<List<YorksV1MaterialRequestProjectOption>> listDraftProjects() async =>
      const [];

  @override
  Future<List<YorksV1MaterialRequest>> listRequests({
    String? projectId,
  }) async => const [];

  @override
  Future<List<YorksV1MaterialRequestScopeOption>> listScopes(
    String projectId,
  ) async => const [];

  @override
  Future<YorksV1MaterialRequest> saveDraft(
    YorksV1SaveMaterialRequestDraftInput input,
  ) async {
    await saveDelay;
    final failure = saveFailure;
    if (failure != null) throw failure;
    saveInputs.add(input);
    return _request(requestId: input.draft.id, version: 1);
  }

  @override
  Future<YorksV1MaterialRequest> saveAndSubmit(
    YorksV1MaterialRequestDraft draft,
  ) async {
    saveAndSubmitInputs.add(draft);
    await submitDelay;
    if (submitFailures.isNotEmpty) throw submitFailures.removeAt(0);
    final failure = submitFailure;
    if (failure != null) throw failure;
    return _request(requestId: draft.id, version: 2, number: 'B5TEST-MR001');
  }

  @override
  Future<YorksV1MaterialRequest> saveSubmitAndApprove(
    YorksV1MaterialRequestDraft draft,
  ) async {
    saveSubmitAndApproveInputs.add(draft);
    if (submitFailures.isNotEmpty) throw submitFailures.removeAt(0);
    final failure = submitFailure;
    if (failure != null) throw failure;
    return _request(
      requestId: draft.id,
      version: 3,
      number: 'B5TEST-MR001',
      state: YorksV1MaterialRequestState.approvedForArrangement,
    );
  }

  @override
  Future<YorksV1MaterialRequest> submit(
    YorksV1SubmitMaterialRequestInput input,
  ) async {
    final failure = submitFailure;
    if (failure != null) throw failure;
    submitInputs.add(input);
    return _request(
      requestId: input.requestId,
      version: 2,
      number: 'B5TEST-MR001',
    );
  }
}

class _Phase2FakeRequestRepository extends _FakeRequestRepository
    implements YorksV1MaterialRequestPhase2Repository {
  YorksV1PrivateMaterialRequestDraftRecord? privateDraft;
  Future<void>? privateHydrationDelay;
  Future<void>? privateSyncDelay;
  Object? privateSyncFailure;
  int privateHydrationCallCount = 0;
  int privateSyncCallCount = 0;
  int activePrivateSyncs = 0;
  int maxConcurrentPrivateSyncs = 0;
  final Completer<void> firstPrivateSyncStarted = Completer<void>();
  final Completer<void> secondPrivateSyncStarted = Completer<void>();

  @override
  Future<void> deletePrivateDraft({
    required String draftId,
    required int expectedSyncVersion,
    required String idempotencyKey,
  }) async {
    if (privateDraft?.draftId == draftId) privateDraft = null;
  }

  @override
  Future<YorksV1MaterialRequestChangeSummary?> getChangeSummary(
    String requestId,
  ) async => null;

  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord?> getPrivateDraft({
    required String draftId,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) async {
    privateHydrationCallCount++;
    final delay = privateHydrationDelay;
    if (delay != null) await delay;
    return privateDraft?.draftId == draftId ? privateDraft : null;
  }

  @override
  Future<YorksV1MaterialRequestWorkAssignment> getWorkAssignment(
    String requestId,
  ) async => YorksV1MaterialRequestWorkAssignment(
    requestId: requestId,
    assignmentVersion: 0,
    canManage: true,
  );

  @override
  Future<YorksV1MaterialRequestWorkAssignment> assignWork(
    YorksV1AssignMaterialRequestWorkInput input,
  ) async => YorksV1MaterialRequestWorkAssignment(
    requestId: input.requestId,
    assignmentVersion: input.expectedAssignmentVersion + 1,
    assigneeAuthUserId: input.assigneeAuthUserId,
    canManage: true,
  );

  @override
  Future<YorksV1MaterialRequestCommentPage> listComments({
    required String requestId,
    DateTime? beforeCreatedAt,
    String? beforeId,
    int limit = 20,
  }) async =>
      YorksV1MaterialRequestCommentPage(items: const [], hasMore: false);

  @override
  Future<List<YorksV1MaterialRequestComment>> getCommentWindow({
    required String requestId,
    required String commentId,
    int radius = 10,
  }) async => const [];

  @override
  Future<List<YorksV1PrivateMaterialRequestDraftRecord>> listPrivateDrafts({
    required String ownerAuthUserId,
    required String Function() submissionIdempotencyKeyFactory,
    int limit = 50,
  }) async => [?privateDraft];

  @override
  Future<YorksV1MaterialRequestSummaryPage> listRequestSummaries(
    YorksV1MaterialRequestSummaryQuery query,
  ) async => YorksV1MaterialRequestSummaryPage(
    items: const [],
    totalCount: 0,
    limit: query.limit,
    offset: query.offset,
    hasMore: false,
    metrics: const YorksV1MaterialRequestSummaryMetrics(
      total: 0,
      open: 0,
      inProgress: 0,
      dispatched: 0,
      received: 0,
      closed: 0,
    ),
  );

  @override
  Future<List<YorksV1MaterialRequestMention>> listWorkCandidates(
    String requestId,
  ) async => const [];

  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord> syncPrivateDraft(
    YorksV1SyncPrivateMaterialRequestDraftInput input,
  ) async {
    privateSyncCallCount++;
    if (privateSyncCallCount == 1 && !firstPrivateSyncStarted.isCompleted) {
      firstPrivateSyncStarted.complete();
    } else if (privateSyncCallCount == 2 &&
        !secondPrivateSyncStarted.isCompleted) {
      secondPrivateSyncStarted.complete();
    }
    activePrivateSyncs++;
    if (activePrivateSyncs > maxConcurrentPrivateSyncs) {
      maxConcurrentPrivateSyncs = activePrivateSyncs;
    }
    try {
      final delay = privateSyncDelay;
      if (delay != null) await delay;
      final failure = privateSyncFailure;
      if (failure != null) throw failure;
      final currentVersion = privateDraft?.syncVersion ?? 0;
      if (input.draft.privateSyncVersion != currentVersion) {
        throw const YorksV1DomainException(YorksV1DomainErrorCode.conflict);
      }
      final now = DateTime.now().toUtc();
      final version = currentVersion + 1;
      final record = YorksV1PrivateMaterialRequestDraftRecord(
        draftId: input.draft.id,
        syncVersion: version,
        draft: input.draft.copyWith(
          privateSyncVersion: version,
          privateSyncedAt: now,
        ),
        clientUpdatedAt: input.draft.updatedAt,
        serverUpdatedAt: now,
      );
      privateDraft = record;
      return record;
    } finally {
      activePrivateSyncs--;
    }
  }
}

class _DelayedRpcClient implements YorksV1MaterialRequestRpcClient {
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const [];
  }
}

class _CandidateSearchRpcClient implements YorksV1MaterialRequestRpcClient {
  String? functionName;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.functionName = functionName;
    this.parameters = parameters;
    return const [
      {
        'id': 'boq-row-1',
        'source_kind': 'scope_boq',
        'item_description': 'Motorized smoke damper',
        'unit': 'Nos',
        'source_boq_group_id': 'boq-group-1',
        'source_boq_row_id': 'boq-row-1',
      },
    ];
  }
}

class _OperationsDashboardRpcClient implements YorksV1MaterialRequestRpcClient {
  String? functionName;
  Map<String, Object?>? parameters;

  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    this.functionName = functionName;
    this.parameters = parameters;
    return const {
      'my_work_count': 2,
      'exception_request_count': 1,
      'required_date_overdue_count': 1,
      'action_due_policy': 'not_configured',
      'outstanding_replacement_quantity': '3',
    };
  }
}

YorksV1MaterialRequest _request({
  required String requestId,
  required int version,
  String? number,
  YorksV1MaterialRequestState? state,
  List<Map<String, dynamic>> lines = const [],
}) => YorksV1MaterialRequest.fromRpcJson({
  'id': requestId,
  'project_id': _projectId,
  'project_ref': 'B5-TEST',
  'project_name': 'Test Project',
  'scope_id': _scopeId,
  'scope_name': 'Common',
  'state': state?.wireValue ?? (number == null ? 'draft' : 'submitted'),
  'record_version': version,
  'created_at': '2026-08-02T00:00:00Z',
  'updated_at': '2026-08-02T00:00:00Z',
  'timing': 'normal',
  'request_number': number,
  'lines': lines,
});

class _RejectingRpcClient implements YorksV1MaterialRequestRpcClient {
  _RejectingRpcClient(this.code);
  final String code;
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async =>
      throw PostgrestException(message: 'Private server detail', code: code);
}

Future<YorksV1MaterialRequestDraftController> _validSaveController(
  YorksV1MaterialRequestRepository repository,
  _MemoryStore<YorksV1MaterialRequestDraft> store,
) async {
  final controller = YorksV1MaterialRequestDraftController(
    ownerAuthUserId: _siteEngineer,
    draftId: _draftId,
    store: store,
    repository: repository,
    uuidFactory: _Ids().next,
  );
  await controller.setProject(_projectId);
  await controller.setScope(_scopeId);
  await controller.addCustomLine();
  await controller.updateLine(
    controller.currentDraft.lines.single.id,
    (line) => line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
  );
  return controller;
}

class _DraftSaveRecoveryRepository extends _FakeRequestRepository
    implements YorksV1MaterialRequestDraftSaveRecoveryRepository {
  bool loseNextResponse = false;
  bool commitBeforeLoss = true;
  int commitCount = 0;
  int receiptReads = 0;
  final List<String> saveOperationIds = [];
  final List<String> payloadHashes = [];
  final Map<String, YorksV1MaterialRequestDraftSaveAcknowledgement> receipts =
      {};

  @override
  Future<YorksV1MaterialRequestDraftSaveAcknowledgement> saveDraftIdempotent(
    YorksV1SaveMaterialRequestDraftInput input, {
    required String operationId,
  }) async {
    saveOperationIds.add(operationId);
    payloadHashes.add(input.draft.savePayloadHash());
    if (!receipts.containsKey(operationId) &&
        (!loseNextResponse || commitBeforeLoss)) {
      commitCount++;
      receipts[operationId] = YorksV1MaterialRequestDraftSaveAcknowledgement(
        requestId: input.draft.id,
        recordVersion: input.draft.serverRecordVersion + 1,
        operationId: operationId,
        payloadHash: 'server-payload-hash',
        committedAt: DateTime.utc(2026, 9, 18, 10),
      );
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: TimeoutException('lost draft save response'),
      );
    }
    final existing = receipts[operationId];
    if (existing != null) return existing;
    commitCount++;
    return receipts[operationId] =
        YorksV1MaterialRequestDraftSaveAcknowledgement(
          requestId: input.draft.id,
          recordVersion: input.draft.serverRecordVersion + 1,
          operationId: operationId,
          payloadHash: 'server-payload-hash',
          committedAt: DateTime.utc(2026, 9, 18, 10),
        );
  }

  @override
  Future<YorksV1MaterialRequestDraftSaveAcknowledgement?> findDraftSaveResult(
    YorksV1SaveMaterialRequestDraftInput input, {
    required String operationId,
  }) async {
    receiptReads++;
    return receipts[operationId];
  }
}

Future<YorksV1MaterialRequestDraftController> _recoveryController(
  _RecoveryRequestRepository repository,
  _MemoryStore<YorksV1MaterialRequestDraft> store, {
  bool Function()? isCurrentOwner,
}) async {
  final controller = YorksV1MaterialRequestDraftController(
    ownerAuthUserId: _siteEngineer,
    isCurrentOwner: isCurrentOwner,
    draftId: _draftId,
    store: store,
    repository: repository,
    uuidFactory: _Ids().next,
  );
  await controller.setProject(_projectId);
  await controller.setScope(_scopeId);
  await controller.addCustomLine();
  await controller.updateLine(
    controller.currentDraft.lines.single.id,
    (line) => line.copyWith(description: 'Duct', quantity: '2', unit: 'Nos'),
  );
  return controller;
}

class _RecoveryRequestRepository extends _FakeRequestRepository
    implements YorksV1MaterialRequestSubmissionRecoveryRepository {
  bool commitBeforeFailure = true;
  bool loseResponse = true;
  int writeCount = 0;
  int commitCount = 0;
  Object? lookupFailure;
  Object? writeFailure;
  Future<void>? lookupDelay;
  YorksV1MaterialRequest? committed;
  final List<bool> checkedModes = [];
  final List<YorksV1MaterialRequestDraft> intents = [];

  Future<YorksV1MaterialRequest> _write(
    YorksV1MaterialRequestDraft draft,
    bool approve,
  ) async {
    writeCount++;
    intents.add(draft);
    final failure = writeFailure;
    if (failure != null) throw failure;
    if ((!loseResponse || commitBeforeFailure) && committed == null) {
      commitCount++;
      committed = _request(
        requestId: draft.id,
        version: 2,
        number: 'B5TEST-MR001',
        state: approve
            ? YorksV1MaterialRequestState.approvedForArrangement
            : YorksV1MaterialRequestState.awaitingRequestApproval,
      );
    }
    if (loseResponse) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: TimeoutException('lost response'),
      );
    }
    return committed!;
  }

  @override
  Future<YorksV1MaterialRequest> saveAndSubmit(
    YorksV1MaterialRequestDraft draft,
  ) => _write(draft, false);
  @override
  Future<YorksV1MaterialRequest> saveSubmitAndApprove(
    YorksV1MaterialRequestDraft draft,
  ) => _write(draft, true);
  @override
  Future<YorksV1MaterialRequest?> findSubmissionResult(
    YorksV1MaterialRequestDraft draft, {
    required bool approveImmediately,
  }) async {
    checkedModes.add(approveImmediately);
    await lookupDelay;
    final error = lookupFailure;
    if (error != null) throw error;
    return committed;
  }
}

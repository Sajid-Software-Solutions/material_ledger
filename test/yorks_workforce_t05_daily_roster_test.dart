import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/workforce/application/workforce_daily_roster_controller.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/workforce_attendance_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_daily_roster_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_timesheet_models.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'quick marking uses shift hours and stale undo cannot overwrite a newer edit',
    () async {
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Worker',
            ),
          ],
        ),
      );
      final repository = _RosterRepository(onGet: (_, _) async => projection);
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      await controller.load(workDate: _currentDate);
      final before = controller.state.rows.single;
      expect(controller.markPresent(_worker1), isTrue);
      final after = controller.state.rows.single;
      expect(after.regularMinutes, 480);
      expect(after.overtimeMinutes, 0);
      expect(repository.saveCalls, isEmpty);
      controller.updateRow(_worker1, regularMinutes: 420);
      controller.undoQuickMark(before, after);
      expect(controller.state.rows.single.regularMinutes, 420);
      controller.purgeProtectedState();
      expect(controller.markPresent(_worker1), isFalse);
      controller.undoQuickMark(before, after);
      expect(controller.state.rows, isEmpty);
    },
  );

  test(
    'quick Present never invents hours when the retained suggestion is zero',
    () async {
      final row = _rowJson(
        workerId: _worker1,
        workerNumber: 'WF-001',
        workerName: 'Worker',
      );
      (row['schedule_suggestion']
              as Map<String, dynamic>)['suggested_regular_minutes'] =
          0;
      (row['schedule_suggestion']
              as Map<String, dynamic>)['suggested_attendance_status'] =
          'not_entered';
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(_currentDate, rows: [row]),
      );
      final controller = await _controller(
        _RosterRepository(onGet: (_, _) async => projection),
      );
      addTearDown(controller.dispose);
      await controller.load(workDate: _currentDate);
      expect(controller.markPresent(_worker1), isFalse);
      expect(controller.state.dirtyRows, isEmpty);
    },
  );

  test('strict worker and restricted allocation shapes fail closed', () {
    final restricted = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Restricted Worker',
            tradeId: _trade1,
            tradeName: 'Ductman',
            attendance: _attendanceJson(
              workerId: _worker1,
              attendanceId: _attendance1,
              workDate: _currentDate,
              regularMinutes: 480,
            ),
            hasActiveAllocationLock: true,
            allocationDetailsRestricted: true,
            canMaintainTimesheet: false,
          ),
        ],
      ),
    );

    final row = restricted.rows.single;
    expect(row.workerType, 'yorks_employee');
    expect(row.hasActiveAllocationLock, isTrue);
    expect(row.allocationDetailsRestricted, isTrue);
    expect(row.allocationSet, isNull);
    expect(row.isAttendanceEditable, isFalse);

    final malformedWorker = _rosterResponse(
      _currentDate,
      rows: [
        _rowJson(
          workerId: _worker1,
          workerNumber: 'WF-001',
          workerName: 'Malformed Worker',
        )..['worker_type'] = 'consultant',
      ],
    );
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(malformedWorker),
      throwsFormatException,
    );

    final leakingRestricted = _rosterResponse(
      _currentDate,
      rows: [
        _rowJson(
          workerId: _worker1,
          workerNumber: 'WF-001',
          workerName: 'Leaking Worker',
          attendance: _attendanceJson(
            workerId: _worker1,
            attendanceId: _attendance1,
            workDate: _currentDate,
            regularMinutes: 480,
          ),
          allocationSet: _allocationSetJson(
            workerId: _worker1,
            attendanceId: _attendance1,
            workDate: _currentDate,
            regularMinutes: 480,
          ),
          hasActiveAllocationLock: true,
          allocationDetailsRestricted: true,
          canMaintainTimesheet: false,
        ),
      ],
    );
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(leakingRestricted),
      throwsFormatException,
    );
  });

  test('selectors retain exact team/project/scope/location relationships', () {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(_currentDate),
    );

    expect(projection.selectors.teams.map((item) => item.id), [_team1, _team2]);
    expect(projection.selectors.projects.single.id, _projectId);
    expect(projection.selectors.projectScopes.single.projectId, _projectId);
    expect(projection.selectors.internalLocations.single.id, _locationId);
    expect(projection.allocationTargets.projects.single.id, _projectId);
    expect(projection.allocationTargets.projectScopes.single.kind, 'common');
    expect(projection.allocationTargets.internalLocations.single.code, 'MAIN');

    final orphanScope = _rosterResponse(_currentDate);
    final selectors = orphanScope['selectors']! as Map<String, dynamic>;
    final scopes = selectors['project_scopes']! as List<Object?>;
    (scopes.single as Map<String, dynamic>)['project_id'] = _otherProjectId;
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(orphanScope),
      throwsFormatException,
    );
  });

  test('T05 projection and save shapes require exact schema-v1 keys', () {
    final extraProjection = _rosterResponse(_currentDate)
      ..['restricted_commercial_value'] = 1;
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(extraProjection),
      throwsFormatException,
    );

    final missingNullableFilter = _rosterResponse(_currentDate);
    final filters = missingNullableFilter['filters']! as Map<String, dynamic>;
    filters.remove('query');
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(
        missingNullableFilter,
      ),
      throwsFormatException,
    );

    final extraRow = _rosterResponse(
      _currentDate,
      rows: [
        _rowJson(
          workerId: _worker1,
          workerNumber: 'WF-001',
          workerName: 'Strict Worker',
        )..['salary'] = 100,
      ],
    );
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(extraRow),
      throwsFormatException,
    );

    final missingTargetEvidence = _rosterResponse(_currentDate);
    final targets =
        missingTargetEvidence['allocation_targets']! as Map<String, dynamic>;
    final scopes = targets['project_scopes']! as List<Object?>;
    (scopes.single as Map<String, dynamic>).remove('project_scope_code');
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(
        missingTargetEvidence,
      ),
      throwsFormatException,
    );

    final save = _saveResponse(_currentDate, [_presentSaveRow(_worker1)])
      ..['unexpected'] = true;
    expect(
      () => YorksWorkforceDailyRosterSaveResult.fromRpcJson(save),
      throwsFormatException,
    );
  });

  test(
    'mixed extreme-timezone restricted rows retain the selected work date',
    () {
      final kiritimatiAttendance = _attendanceJson(
        workerId: _worker1,
        attendanceId: _attendance1,
        workDate: _currentDate,
        regularMinutes: 480,
      );
      kiritimatiAttendance['created_at'] = '2026-08-30T08:00:00+14:00';
      kiritimatiAttendance['updated_at'] = '2026-08-30T08:30:00+14:00';
      final kiritimatiSchedule =
          kiritimatiAttendance['schedule']! as Map<String, dynamic>;
      kiritimatiSchedule['calendar_timezone'] = 'Pacific/Kiritimati';
      final kiritimati = _rowJson(
        workerId: _worker1,
        workerNumber: 'WF-001',
        workerName: 'Restricted Kiritimati Worker',
        attendance: kiritimatiAttendance,
        hasActiveAllocationLock: true,
        allocationDetailsRestricted: true,
        canMaintainTimesheet: false,
      );
      final kiritimatiSuggestion =
          kiritimati['schedule_suggestion']! as Map<String, dynamic>;
      kiritimatiSuggestion['calendar_timezone'] = 'Pacific/Kiritimati';

      final pagoPago = _rowJson(
        workerId: _worker2,
        workerNumber: 'WF-002',
        workerName: 'Editable Pago Pago Worker',
      );
      final pagoPagoSuggestion =
          pagoPago['schedule_suggestion']! as Map<String, dynamic>;
      pagoPagoSuggestion['calendar_timezone'] = 'Pacific/Pago_Pago';
      final response = _rosterResponse(
        _currentDate,
        rows: [kiritimati, pagoPago],
      );
      response['server_time'] = '2026-08-30T00:15:00-11:00';

      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        response,
      );
      expect(projection.workDate, _currentDate);
      expect(projection.serverTime, '2026-08-30T00:15:00-11:00');
      expect(
        projection.rows.first.scheduleSuggestion.schedule.calendarTimezone,
        'Pacific/Kiritimati',
      );
      expect(projection.rows.first.allocationDetailsRestricted, isTrue);
      expect(projection.rows.first.isAttendanceEditable, isFalse);
      expect(
        projection.rows.last.scheduleSuggestion.schedule.calendarTimezone,
        'Pacific/Pago_Pago',
      );
      expect(projection.rows.last.isAttendanceEditable, isTrue);
    },
  );

  test('replacement allocation totals must equal attendance totals', () async {
    final invalid = YorksWorkforceDailyRosterSaveRow(
      workerId: _worker1,
      expectedAttendanceVersion: 1,
      status: YorksWorkforceAttendanceStatus.present,
      regularMinutes: 480,
      overtimeMinutes: 30,
      overtimeReason: 'Approved overtime',
      reason: 'Daily roster attendance edit',
      allocationAction: YorksWorkforceRosterAllocationAction.replace,
      expectedAllocationVersion: 1,
      allocations: const [
        YorksWorkforceAllocationInput(
          targetKind: YorksWorkforceAllocationTargetKind.projectWork,
          projectId: _projectId,
          projectScopeId: _scopeId,
          regularMinutes: 479,
          overtimeMinutes: 30,
        ),
      ],
    );
    expect(invalid.isValid, isFalse);

    final rpc = _RpcClient((_, _) => throw StateError('must not call'));
    await expectLater(
      _supabaseRepository(rpc).saveDailyRoster(
        workDate: _currentDate,
        rows: [invalid],
        reason: 'Daily roster attendance save',
        idempotencyKey: _idempotencyKey,
      ),
      throwsA(_domainCode(YorksV1DomainErrorCode.invalidInput)),
    );
    expect(rpc.calls, isEmpty);
  });

  test('daily-roster read sends the exact normalized RPC parameters', () async {
    final rpc = _RpcClient((functionName, parameters) {
      expect(functionName, 'v1_get_workforce_daily_roster');
      expect(parameters, {
        'p_work_date': _currentDate,
        'p_team_id': _team1,
        'p_project_id': _projectId,
        'p_project_scope_id': _scopeId,
        'p_internal_location_id': _locationId,
        'p_query': 'duct worker',
        'p_limit': 25,
        'p_offset': 5,
      });
      return _rosterResponse(
        _currentDate,
        limit: 25,
        offset: 5,
        filters: {
          'team_id': _team1,
          'project_id': _projectId,
          'project_scope_id': _scopeId,
          'internal_location_id': _locationId,
          'query': 'duct worker',
        },
      );
    });

    final projection = await _supabaseRepository(rpc).getDailyRoster(
      workDate: ' $_currentDate ',
      filters: const YorksWorkforceRosterFilters(
        teamId: ' $_team1 ',
        projectId: ' $_projectId ',
        projectScopeId: ' $_scopeId ',
        internalLocationId: ' $_locationId ',
        query: ' duct worker ',
        limit: 25,
        offset: 5,
      ),
    );

    expect(projection.workDate, _currentDate);
    expect(rpc.calls, ['v1_get_workforce_daily_roster']);
  });

  test(
    'roster read rejects invalid filters and mismatched response context',
    () async {
      final never = _RpcClient((_, _) => throw StateError('must not call'));
      await expectLater(
        _supabaseRepository(never).getDailyRoster(
          workDate: _currentDate,
          filters: const YorksWorkforceRosterFilters(projectScopeId: _scopeId),
        ),
        throwsA(_domainCode(YorksV1DomainErrorCode.invalidInput)),
      );
      expect(never.calls, isEmpty);

      final wrongDate = _RpcClient((_, _) => _rosterResponse(_previousDate));
      await expectLater(
        _supabaseRepository(wrongDate).getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );

      final wrongFilter = _RpcClient(
        (_, _) => _rosterResponse(
          _currentDate,
          filters: {
            'team_id': _team2,
            'project_id': null,
            'project_scope_id': null,
            'internal_location_id': null,
            'query': null,
          },
        ),
      );
      await expectLater(
        _supabaseRepository(wrongFilter).getDailyRoster(
          workDate: _currentDate,
          filters: const YorksWorkforceRosterFilters(teamId: _team1),
        ),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );

      final oversizedPage = _RpcClient(
        (_, _) => _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'First Page Worker',
            ),
            _rowJson(
              workerId: _worker2,
              workerNumber: 'WF-002',
              workerName: 'Unexpected Second Worker',
            ),
          ],
        ),
      );
      await expectLater(
        _supabaseRepository(oversizedPage).getDailyRoster(
          workDate: _currentDate,
          filters: const YorksWorkforceRosterFilters(limit: 1),
        ),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    },
  );

  test('atomic roster save sends the exact accepted RPC payload', () async {
    final input = YorksWorkforceDailyRosterSaveRow(
      workerId: _worker1,
      expectedAttendanceVersion: null,
      status: YorksWorkforceAttendanceStatus.absent,
      regularMinutes: 0,
      overtimeMinutes: 0,
      overtimeReason: null,
      reason: ' Daily roster attendance edit ',
      allocationAction: YorksWorkforceRosterAllocationAction.preserve,
      expectedAllocationVersion: null,
    );
    final rpc = _RpcClient((functionName, parameters) {
      expect(functionName, 'v1_save_workforce_daily_roster');
      expect(parameters, {
        'p_work_date': _currentDate,
        'p_rows': [
          {
            'worker_id': _worker1,
            'expected_attendance_version': null,
            'attendance_status': 'absent',
            'regular_minutes': 0,
            'overtime_minutes': 0,
            'overtime_reason': null,
            'reason': 'Daily roster attendance edit',
            'allocation_action': 'preserve',
            'expected_allocation_version': null,
            'allocations': null,
          },
        ],
        'p_reason': 'Daily roster attendance save',
        'p_idempotency_key': _idempotencyKey,
      });
      return _saveResponse(_currentDate, [input]);
    });

    final result = await _supabaseRepository(rpc).saveDailyRoster(
      workDate: ' $_currentDate ',
      rows: [input],
      reason: ' Daily roster attendance save ',
      idempotencyKey: ' $_idempotencyKey ',
    );

    expect(result.rowCount, 1);
    expect(
      result.rows.single.attendance.status,
      YorksWorkforceAttendanceStatus.absent,
    );
    expect(rpc.calls, ['v1_save_workforce_daily_roster']);
  });

  test(
    'atomic repository accepts 500 rows and rejects 501 before RPC',
    () async {
      final accepted = [
        for (var index = 1; index <= 500; index += 1)
          _presentSaveRow(_workerIdAt(index)),
      ];
      final rpc = _RpcClient((functionName, parameters) {
        expect(functionName, 'v1_save_workforce_daily_roster');
        final payloadRows = parameters['p_rows']! as List<Object?>;
        expect(payloadRows, hasLength(500));
        return _saveResponse(_currentDate, accepted);
      });
      final repository = _supabaseRepository(rpc);
      final result = await repository.saveDailyRoster(
        workDate: _currentDate,
        rows: accepted,
        reason: 'Daily roster attendance save',
        idempotencyKey: _idempotencyKey,
      );
      expect(result.rowCount, 500);
      expect(rpc.calls, hasLength(1));

      final rejected = [...accepted, _presentSaveRow(_workerIdAt(501))];
      await expectLater(
        repository.saveDailyRoster(
          workDate: _currentDate,
          rows: rejected,
          reason: 'Daily roster attendance save',
          idempotencyKey: _otherIdempotencyKey,
        ),
        throwsA(_domainCode(YorksV1DomainErrorCode.invalidInput)),
      );
      expect(rpc.calls, hasLength(1));
    },
  );

  test(
    'flag-off, offline and missing backend fail before roster RPC',
    () async {
      final rpc = _RpcClient((_, _) => _rosterResponse(_currentDate));
      final flagOff = YorksSupabaseWorkforceRepository(
        featureFlags: const YorksV1FeatureFlags(),
        connectivity: const _Connectivity(true),
        rpcClient: rpc,
      );
      await expectLater(
        flagOff.getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.featureDisabled)),
      );
      expect(rpc.calls, isEmpty);

      final offline = YorksSupabaseWorkforceRepository(
        featureFlags: _workforceFlags,
        connectivity: const _Connectivity(false),
        rpcClient: rpc,
      );
      await expectLater(
        offline.getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.offline)),
      );
      expect(rpc.calls, isEmpty);

      final missingBackend = YorksSupabaseWorkforceRepository(
        featureFlags: _workforceFlags,
        connectivity: const _Connectivity(true),
      );
      await expectLater(
        missingBackend.getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.backendUnavailable)),
      );
    },
  );

  test(
    'denied, stale and malformed roster responses map fail closed',
    () async {
      final denied = _RpcClient(
        (_, _) => throw const PostgrestException(
          message: 'Workforce roster denied',
          code: '42501',
        ),
      );
      await expectLater(
        _supabaseRepository(denied).getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.unauthorized)),
      );

      final stale = _RpcClient(
        (_, _) => throw const PostgrestException(
          message: 'V1_WORKFORCE_ATTENDANCE_STALE_VERSION',
          code: '40001',
        ),
      );
      await expectLater(
        _supabaseRepository(stale).getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.conflict)),
      );

      final malformed = _RpcClient((_, _) => <String, dynamic>{});
      await expectLater(
        _supabaseRepository(malformed).getDailyRoster(workDate: _currentDate),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
    },
  );

  test('future roster is readable but every mutation stays disabled', () async {
    final response = _rosterResponse(
      _currentDate,
      rows: [
        _rowJson(
          workerId: _worker1,
          workerNumber: 'WF-001',
          workerName: 'Future Worker',
          canMaintainAttendance: false,
          canMaintainTimesheet: false,
        ),
      ],
    );
    response['is_future'] = true;
    final capabilities = response['capabilities']! as Map<String, dynamic>;
    capabilities['can_maintain_attendance'] = false;
    capabilities['can_maintain_timesheet'] = false;
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      response,
    );
    expect(projection.isFuture, isTrue);
    expect(projection.rows.single.isAttendanceEditable, isFalse);

    final repository = _RosterRepository(onGet: (_, _) async => projection);
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);

    controller.selectVisible();
    expect(controller.state.selectedWorkerIds, isEmpty);
    controller.updateRow(
      _worker1,
      status: YorksWorkforceAttendanceStatus.present,
      regularMinutes: 480,
    );
    expect(controller.state.dirtyRows, isEmpty);
    expect(controller.reviewDay(), isFalse);
    expect(await controller.saveDay(), isNull);
    expect(repository.saveCalls, isEmpty);

    final malformed = _rosterResponse(
      _currentDate,
      rows: [
        _rowJson(
          workerId: _worker1,
          workerNumber: 'WF-001',
          workerName: 'Mutable Future Worker',
        ),
      ],
    );
    malformed['is_future'] = true;
    final malformedCapabilities =
        malformed['capabilities']! as Map<String, dynamic>;
    malformedCapabilities['can_maintain_attendance'] = false;
    malformedCapabilities['can_maintain_timesheet'] = false;
    expect(
      () => YorksWorkforceDailyRosterProjection.fromRpcJson(malformed),
      throwsFormatException,
    );
  });

  test('uncertain save retry reuses the original command key', () async {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Retry Worker',
          ),
        ],
      ),
    );
    late _RosterRepository repository;
    repository = _RosterRepository(
      onGet: (_, _) async => projection,
      onSave: (workDate, rows, reason, idempotencyKey) async {
        if (repository.saveCalls.length == 1) {
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          );
        }
        return YorksWorkforceDailyRosterSaveResult.fromRpcJson(
          _saveResponse(workDate, rows),
        );
      },
    );
    var generatedKeys = 0;
    final controller = await _controller(
      repository,
      uuidFactory: () {
        generatedKeys += 1;
        return generatedKeys == 1 ? _idempotencyKey : _otherIdempotencyKey;
      },
    );
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();
    controller.applyStandardMinutes();

    expect(controller.reviewDay(), isTrue);
    expect(await controller.saveDay(), isNull);
    expect(controller.state.status, YorksWorkforceDailyRosterStatus.uncertain);
    expect(controller.state.dirtyRows, hasLength(1));
    expect(controller.reviewDay(), isTrue);
    expect(await controller.saveDay(), isNotNull);

    expect(repository.saveCalls, hasLength(2));
    expect(
      repository.saveCalls.map((call) => call.idempotencyKey),
      everyElement(_idempotencyKey),
    );
    expect(generatedKeys, 1);
  });

  test(
    'capability loss purges protected projection and retained drafts',
    () async {
      var authorized = true;
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Protected Worker',
            ),
          ],
        ),
      );
      final repository = _RosterRepository(
        onGet: (_, _) async {
          if (!authorized) {
            throw const YorksV1DomainException(
              YorksV1DomainErrorCode.unauthorized,
            );
          }
          return projection;
        },
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.selectVisible();
      controller.applyStandardMinutes();
      expect(controller.state.dirtyRows, hasLength(1));

      authorized = false;
      expect(
        await controller.changeFilters(
          const YorksWorkforceRosterFilters(query: 'denied'),
        ),
        isFalse,
      );
      expect(
        controller.state.status,
        YorksWorkforceDailyRosterStatus.forbidden,
      );
      expect(controller.state.projection, isNull);
      expect(controller.state.rows, isEmpty);
      expect(controller.state.selectedWorkerIds, isEmpty);

      authorized = true;
      expect(
        await controller.changeFilters(const YorksWorkforceRosterFilters()),
        isTrue,
      );
      expect(controller.state.dirtyRows, isEmpty);
      expect(
        controller.state.rows.single.status,
        YorksWorkforceAttendanceStatus.notEntered,
      );
    },
  );

  test(
    'same-day filters retain local drafts until an authoritative version changes',
    () async {
      var committedVersionArrived = false;
      final repository = _RosterRepository(
        onGet: (_, filters) async {
          if (filters.query == 'hidden') {
            return YorksWorkforceDailyRosterProjection.fromRpcJson(
              _rosterResponse(_currentDate),
            );
          }
          return YorksWorkforceDailyRosterProjection.fromRpcJson(
            _rosterResponse(
              _currentDate,
              rows: [
                _rowJson(
                  workerId: _worker1,
                  workerNumber: 'WF-001',
                  workerName: 'Filtered Worker',
                  attendance: committedVersionArrived
                      ? _attendanceJson(
                          workerId: _worker1,
                          attendanceId: _attendance1,
                          workDate: _currentDate,
                          status: YorksWorkforceAttendanceStatus.absent,
                          regularMinutes: 0,
                          recordVersion: 1,
                        )
                      : null,
                ),
              ],
            ),
          );
        },
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.selectVisible();
      controller.applyStandardMinutes();
      expect(controller.state.dirtyRows.single.regularMinutes, 480);

      expect(
        await controller.changeFilters(
          const YorksWorkforceRosterFilters(query: 'hidden'),
        ),
        isTrue,
      );
      expect(controller.state.rows, isEmpty);
      expect(
        await controller.changeFilters(const YorksWorkforceRosterFilters()),
        isTrue,
      );
      expect(controller.state.dirtyRows.single.regularMinutes, 480);

      committedVersionArrived = true;
      expect(
        await controller.changeFilters(
          const YorksWorkforceRosterFilters(query: 'hidden'),
        ),
        isTrue,
      );
      expect(
        await controller.changeFilters(const YorksWorkforceRosterFilters()),
        isTrue,
      );
      final refreshed = controller.state.rows.single;
      expect(refreshed.expectedAttendanceVersion, 1);
      expect(refreshed.status, YorksWorkforceAttendanceStatus.absent);
      expect(refreshed.isDirty, isFalse);
    },
  );

  test('offline date change clears the prior protected projection', () async {
    final connectivity = _MutableConnectivity(true);
    addTearDown(connectivity.dispose);
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Offline Worker',
          ),
        ],
      ),
    );
    final repository = _RosterRepository(onGet: (_, _) async => projection);
    final controller = await _controller(
      repository,
      connectivity: connectivity,
    );
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    expect(controller.state.rows, hasLength(1));

    connectivity.setOnline(false);
    expect(controller.state.status, YorksWorkforceDailyRosterStatus.offline);
    expect(await controller.changeDate(_previousDate), isFalse);
    expect(controller.state.workDate, _previousDate);
    expect(controller.state.projection, isNull);
    expect(controller.state.rows, isEmpty);
    expect(repository.getDates, [_currentDate]);
  });

  test(
    'newer load generation cannot be overwritten by an older response',
    () async {
      final first = Completer<YorksWorkforceDailyRosterProjection>();
      final second = Completer<YorksWorkforceDailyRosterProjection>();
      final repository = _RosterRepository(
        onGet: (workDate, _) =>
            workDate == _previousDate ? first.future : second.future,
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);

      final olderLoad = controller.load(workDate: _previousDate);
      final newerLoad = controller.load(workDate: _currentDate);
      second.complete(
        YorksWorkforceDailyRosterProjection.fromRpcJson(
          _rosterResponse(
            _currentDate,
            rows: [
              _rowJson(
                workerId: _worker2,
                workerNumber: 'WF-002',
                workerName: 'Newest Worker',
              ),
            ],
          ),
        ),
      );

      expect(await newerLoad, isTrue);
      first.complete(
        YorksWorkforceDailyRosterProjection.fromRpcJson(
          _rosterResponse(
            _previousDate,
            rows: [
              _rowJson(
                workerId: _worker1,
                workerNumber: 'WF-001',
                workerName: 'Stale Worker',
              ),
            ],
          ),
        ),
      );

      expect(await olderLoad, isFalse);
      expect(controller.state.workDate, _currentDate);
      expect(controller.state.rows.single.workerId, _worker2);
      expect(repository.getDates, [_previousDate, _currentDate]);
    },
  );

  test(
    'team, trade and missing selectors drive only editable bulk rows',
    () async {
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'First Worker',
              teamId: _team1,
              teamName: 'Duct Team',
              tradeId: _trade1,
              tradeName: 'Ductman',
            ),
            _rowJson(
              workerId: _worker2,
              workerNumber: 'WF-002',
              workerName: 'Second Worker',
              teamId: _team1,
              teamName: 'Duct Team',
              tradeId: _trade2,
              tradeName: 'Electrician',
              attendance: _attendanceJson(
                workerId: _worker2,
                attendanceId: _attendance2,
                workDate: _currentDate,
                regularMinutes: 480,
              ),
            ),
            _rowJson(
              workerId: _worker3,
              workerNumber: 'WF-003',
              workerName: 'Locked Worker',
              teamId: _team2,
              teamName: 'Electrical Team',
              tradeId: _trade1,
              tradeName: 'Ductman',
              hasActiveAllocationLock: true,
              allocationDetailsRestricted: true,
              canMaintainTimesheet: false,
            ),
          ],
        ),
      );
      final controller = await _controller(
        _RosterRepository(onGet: (_, _) async => projection),
      );
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);

      controller.selectTeam(_team1);
      expect(controller.state.selectedWorkerIds, {_worker1, _worker2});
      controller.selectTrade(_trade1);
      expect(controller.state.selectedWorkerIds, {_worker1});
      controller.selectMissing();
      expect(controller.state.selectedWorkerIds, {_worker1});

      controller.applyStandardMinutes();
      final first = _draft(controller, _worker1);
      expect(first.status, YorksWorkforceAttendanceStatus.present);
      expect(first.regularMinutes, 480);
      expect(
        first.draftSource,
        YorksWorkforceRosterDraftSource.scheduleStandard,
      );

      controller.selectTeam(_team1);
      controller.markAbsent();
      expect(
        _draft(controller, _worker1).status,
        YorksWorkforceAttendanceStatus.absent,
      );
      expect(
        _draft(controller, _worker2).status,
        YorksWorkforceAttendanceStatus.absent,
      );
      expect(
        _draft(controller, _worker3).status,
        YorksWorkforceAttendanceStatus.notEntered,
      );
    },
  );

  test(
    'allocation commands never derive authority from read selectors',
    () async {
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          allocationTargets: {
            'projects': <Object?>[],
            'project_scopes': <Object?>[],
            'internal_locations': [
              {
                'internal_location_id': _locationId,
                'location_code': 'MAIN',
                'location_name': 'Main Workshop',
                'department_cost_centre': null,
              },
            ],
          },
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Target Authority Worker',
            ),
          ],
        ),
      );
      expect(projection.selectors.projects.single.id, _projectId);
      expect(projection.allocationTargets.projects, isEmpty);

      final controller = await _controller(
        _RosterRepository(onGet: (_, _) async => projection),
      );
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.selectVisible();
      controller.applyStandardMinutes();
      controller.assignProject(
        _worker1,
        projectId: _projectId,
        projectScopeId: _scopeId,
      );
      expect(_draft(controller, _worker1).allocations, isEmpty);

      controller.assignInternalLocation(_worker1, _locationId);
      final authorized = _draft(controller, _worker1).allocations.single;
      expect(
        authorized.targetKind,
        YorksWorkforceAllocationTargetKind.internalWork,
      );
      expect(authorized.internalLocationId, _locationId);
    },
  );

  test('focused editor splits time only across authorized targets', () async {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Split Allocation Worker',
          ),
        ],
      ),
    );
    final controller = await _controller(
      _RosterRepository(onGet: (_, _) async => projection),
    );
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();
    controller.applyStandardMinutes();
    controller.replaceAllocations(_worker1, const [
      YorksWorkforceAllocationInput(
        targetKind: YorksWorkforceAllocationTargetKind.projectWork,
        projectId: _projectId,
        projectScopeId: _scopeId,
        activityTask: 'Duct installation',
        regularMinutes: 360,
        overtimeMinutes: 0,
      ),
      YorksWorkforceAllocationInput(
        targetKind: YorksWorkforceAllocationTargetKind.internalWork,
        internalLocationId: _locationId,
        activityTask: 'Workshop support',
        regularMinutes: 120,
        overtimeMinutes: 0,
      ),
    ]);

    final split = _draft(controller, _worker1);
    expect(split.allocations, hasLength(2));
    expect(
      split.allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.regularMinutes,
      ),
      split.regularMinutes,
    );
    expect(split.isValid, isTrue);

    controller.replaceAllocations(_worker1, const [
      YorksWorkforceAllocationInput(
        targetKind: YorksWorkforceAllocationTargetKind.internalWork,
        internalLocationId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        regularMinutes: 480,
        overtimeMinutes: 0,
      ),
    ]);
    expect(_draft(controller, _worker1).allocations, same(split.allocations));
  });

  test(
    'previous-day copy uses current schedule and only safe retained target',
    () async {
      final current = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Copy Target',
              tradeId: _trade1,
              tradeName: 'Ductman',
            ),
            _rowJson(
              workerId: _worker2,
              workerNumber: 'WF-002',
              workerName: 'Committed Target',
              attendance: _attendanceJson(
                workerId: _worker2,
                attendanceId: _attendance2,
                workDate: _currentDate,
                regularMinutes: 480,
              ),
            ),
          ],
        ),
      );
      final previous = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _previousDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Copy Source',
              attendance: _attendanceJson(
                workerId: _worker1,
                attendanceId: _attendance1,
                workDate: _previousDate,
                regularMinutes: 600,
                overtimeMinutes: 30,
                overtimeReason: 'Emergency work',
              ),
              allocationSet: _allocationSetJson(
                workerId: _worker1,
                attendanceId: _attendance1,
                workDate: _previousDate,
                regularMinutes: 600,
                overtimeMinutes: 30,
                activityTask: 'Sensitive prior activity',
                notes: 'Sensitive prior note',
              ),
              hasActiveAllocationLock: true,
            ),
          ],
        ),
      );
      final repository = _RosterRepository(
        onGet: (date, _) async => date == _previousDate ? previous : current,
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.toggleSelection(_worker1);
      controller.toggleSelection(_worker2);

      expect(await controller.copyPreviousDay(), 1);
      final copied = _draft(controller, _worker1);
      expect(copied.draftSource, YorksWorkforceRosterDraftSource.previousDay);
      expect(copied.status, YorksWorkforceAttendanceStatus.present);
      expect(copied.regularMinutes, 480);
      expect(copied.overtimeMinutes, 0);
      expect(copied.overtimeReason, isNull);
      expect(copied.allocations, hasLength(1));
      expect(copied.allocations.single.projectId, _projectId);
      expect(copied.allocations.single.projectScopeId, _scopeId);
      expect(copied.allocations.single.regularMinutes, 480);
      expect(copied.allocations.single.overtimeMinutes, 0);
      expect(copied.allocations.single.activityTask, isNull);
      expect(copied.allocations.single.notes, isNull);
      expect(_draft(controller, _worker2).isDirty, isFalse);
      expect(repository.getDates, [_currentDate, _previousDate]);
    },
  );

  test('previous-day copy pages in 100-row slices beyond page one', () async {
    final currentRows = [
      for (var index = 1; index <= 101; index += 1)
        _rowJson(
          workerId: _workerIdAt(index),
          workerNumber: 'WF-${index.toString().padLeft(3, '0')}',
          workerName: 'Current Worker $index',
        ),
    ];
    final previousRows = [
      for (var index = 1; index <= 101; index += 1)
        _rowJson(
          workerId: _workerIdAt(index),
          workerNumber: 'WF-${index.toString().padLeft(3, '0')}',
          workerName: 'Previous Worker $index',
          attendance: _attendanceJson(
            workerId: _workerIdAt(index),
            attendanceId: _attendanceIdAt(index),
            workDate: _previousDate,
            regularMinutes: 480,
          ),
        ),
    ];
    final current = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(_currentDate, rows: currentRows),
    );
    final repository = _RosterRepository(
      onGet: (date, filters) async {
        if (date == _currentDate) return current;
        final end = filters.offset + filters.limit < previousRows.length
            ? filters.offset + filters.limit
            : previousRows.length;
        return YorksWorkforceDailyRosterProjection.fromRpcJson(
          _rosterResponse(
            _previousDate,
            rows: previousRows.sublist(filters.offset, end),
            totalCount: previousRows.length,
          ),
        );
      },
    );
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();

    expect(await controller.copyPreviousDay(), 101);
    expect(
      repository.getFilters
          .where((call) => call.$1 == _previousDate)
          .map((call) => (call.$2.limit, call.$2.offset)),
      [(100, 0), (100, 100)],
    );
    expect(controller.state.dirtyRows, hasLength(101));
    expect(
      controller.state.dirtyRows.every(
        (row) => row.draftSource == YorksWorkforceRosterDraftSource.previousDay,
      ),
      isTrue,
    );
  });

  test(
    'previous-day copy fails visibly at the unresolved 500-row bound',
    () async {
      final current = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Bounded Copy Worker',
            ),
          ],
        ),
      );
      final repository = _RosterRepository(
        onGet: (date, filters) async {
          if (date == _currentDate) return current;
          final page = [
            for (
              var index = filters.offset + 1;
              index <= filters.offset + filters.limit;
              index += 1
            )
              _rowJson(
                workerId: _workerIdAt(index),
                workerNumber: 'WF-${index.toString().padLeft(3, '0')}',
                workerName: 'Unselected Previous Worker $index',
                attendance: _attendanceJson(
                  workerId: _workerIdAt(index),
                  attendanceId: _attendanceIdAt(index),
                  workDate: _previousDate,
                  regularMinutes: 480,
                ),
              ),
          ];
          return YorksWorkforceDailyRosterProjection.fromRpcJson(
            _rosterResponse(_previousDate, rows: page, totalCount: 501),
          );
        },
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.selectVisible();

      expect(await controller.copyPreviousDay(), 0);
      expect(controller.state.status, YorksWorkforceDailyRosterStatus.failure);
      expect(
        controller.state.error?.code,
        YorksV1DomainErrorCode.unexpectedResponse,
      );
      expect(controller.state.dirtyRows, isEmpty);
      expect(
        repository.getFilters
            .where((call) => call.$1 == _previousDate)
            .map((call) => call.$2.offset),
        [0, 100, 200, 300, 400],
      );
    },
  );

  test('stale previous-day response cannot cross a date change', () async {
    final previous = Completer<YorksWorkforceDailyRosterProjection>();
    final current = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Current Date Worker',
          ),
        ],
      ),
    );
    final next = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _nextDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Next Date Worker',
          ),
        ],
      ),
    );
    final repository = _RosterRepository(
      onGet: (date, _) {
        if (date == _previousDate) return previous.future;
        return Future.value(date == _nextDate ? next : current);
      },
    );
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();

    final copy = controller.copyPreviousDay();
    expect(await controller.changeDate(_nextDate), isTrue);
    previous.complete(
      YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _previousDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'Previous Date Worker',
              attendance: _attendanceJson(
                workerId: _worker1,
                attendanceId: _attendance1,
                workDate: _previousDate,
                regularMinutes: 480,
              ),
            ),
          ],
        ),
      ),
    );
    expect(await copy, 0);
    expect(controller.state.workDate, _nextDate);
    expect(controller.state.dirtyRows, isEmpty);
  });

  test('restricted evidence-only edit preserves hidden allocations', () async {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          _rowJson(
            workerId: _worker1,
            workerNumber: 'WF-001',
            workerName: 'Evidence Worker',
            attendance: _attendanceJson(
              workerId: _worker1,
              attendanceId: _attendance1,
              workDate: _currentDate,
              regularMinutes: 480,
              overtimeMinutes: 60,
              overtimeReason: 'Original evidence',
            ),
            hasActiveAllocationLock: true,
            allocationDetailsRestricted: true,
            canMaintainTimesheet: false,
          ),
        ],
      ),
    );
    late _RosterRepository repository;
    repository = _RosterRepository(
      onGet: (_, _) async => projection,
      onSave: (workDate, rows, reason, idempotencyKey) async {
        expect(rows, hasLength(1));
        expect(
          rows.single.allocationAction,
          YorksWorkforceRosterAllocationAction.preserve,
        );
        expect(rows.single.expectedAllocationVersion, isNull);
        expect(rows.single.allocations, isNull);
        return YorksWorkforceDailyRosterSaveResult.fromRpcJson(
          _saveResponse(workDate, rows),
        );
      },
    );
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);

    final original = _draft(controller, _worker1);
    expect(original.isEditable, isFalse);
    expect(original.canEditAttendanceEvidence, isTrue);
    controller.updateRow(
      _worker1,
      overtimeReason: ' Corrected overtime evidence ',
    );

    final edited = _draft(controller, _worker1);
    expect(edited.isDirty, isTrue);
    expect(edited.overtimeReason, ' Corrected overtime evidence ');
    final save = edited.toSaveRow();
    expect(
      save.allocationAction,
      YorksWorkforceRosterAllocationAction.preserve,
    );
    expect(save.allocations, isNull);
    expect(save.expectedAllocationVersion, isNull);
    expect(save.toRpcJson()['overtime_reason'], 'Corrected overtime evidence');
    expect(controller.reviewDay(), isTrue);
    final result = await controller.saveDay();
    expect(result, isNotNull);
    expect(result!.rows.single.allocationSet, isNull);
    expect(result.rows.single.allocationSetId, isNull);
    expect(result.rows.single.allocationSetRecordVersion, isNull);
    expect(result.rows.single.allocationState, isNull);
    expect(
      result.rows.single.attendance.overtimeReason,
      'Corrected overtime evidence',
    );
    expect(repository.saveCalls, hasLength(1));
    final reconciled = _draft(controller, _worker1);
    expect(reconciled.allocations, isEmpty);
    expect(reconciled.originalAllocationWasActive, isTrue);
    expect(reconciled.isDirty, isFalse);
  });

  test(
    'Review Day stays local and Save Day submits one atomic batch',
    () async {
      final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
        _rosterResponse(
          _currentDate,
          rows: [
            _rowJson(
              workerId: _worker1,
              workerNumber: 'WF-001',
              workerName: 'First Atomic Worker',
            ),
            _rowJson(
              workerId: _worker2,
              workerNumber: 'WF-002',
              workerName: 'Second Atomic Worker',
            ),
          ],
        ),
      );
      late _RosterRepository repository;
      repository = _RosterRepository(
        onGet: (_, _) async => projection,
        onSave: (workDate, rows, reason, idempotencyKey) async {
          expect(workDate, _currentDate);
          expect(rows, hasLength(2));
          expect(reason, 'Daily roster attendance save');
          expect(idempotencyKey, _idempotencyKey);
          return YorksWorkforceDailyRosterSaveResult.fromRpcJson(
            _saveResponse(workDate, rows),
          );
        },
      );
      final controller = await _controller(repository);
      addTearDown(controller.dispose);
      expect(await controller.load(workDate: _currentDate), isTrue);
      controller.selectVisible();
      controller.applyStandardMinutes();
      expect(controller.state.dirtyRows, hasLength(2));

      expect(controller.reviewDay(), isTrue);
      expect(
        controller.state.status,
        YorksWorkforceDailyRosterStatus.reviewing,
      );
      expect(repository.saveCalls, isEmpty);

      final result = await controller.saveDay();
      expect(result, isNotNull);
      expect(result!.rowCount, 2);
      expect(repository.saveCalls, hasLength(1));
      expect(repository.saveCalls.single.rows, hasLength(2));
      expect(controller.state.status, YorksWorkforceDailyRosterStatus.saved);
      expect(controller.state.dirtyRows, isEmpty);
      expect(controller.state.selectedWorkerIds, isEmpty);
      expect(controller.state.lastSavedAt, '2026-08-30T12:30:00Z');
    },
  );

  test('controller saves 101 dirty workers as one atomic command', () async {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          for (var index = 1; index <= 101; index += 1)
            _rowJson(
              workerId: _workerIdAt(index),
              workerNumber: 'WF-${index.toString().padLeft(3, '0')}',
              workerName: 'Save Worker $index',
            ),
        ],
      ),
    );
    late _RosterRepository repository;
    repository = _RosterRepository(
      onGet: (_, _) async => projection,
      onSave: (workDate, rows, reason, idempotencyKey) async =>
          YorksWorkforceDailyRosterSaveResult.fromRpcJson(
            _saveResponse(workDate, rows),
          ),
    );
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();
    controller.applyStandardMinutes();
    expect(controller.state.dirtyRows, hasLength(101));

    expect(controller.reviewDay(), isTrue);
    final result = await controller.saveDay();
    expect(result?.rowCount, 101);
    expect(repository.saveCalls, hasLength(1));
    expect(repository.saveCalls.single.rows, hasLength(101));
    expect(controller.state.dirtyRows, isEmpty);
  });

  test('controller reports 501 dirty rows before any save RPC', () async {
    final projection = YorksWorkforceDailyRosterProjection.fromRpcJson(
      _rosterResponse(
        _currentDate,
        rows: [
          for (var index = 1; index <= 501; index += 1)
            _rowJson(
              workerId: _workerIdAt(index),
              workerNumber: 'WF-${index.toString().padLeft(3, '0')}',
              workerName: 'Bounded Save Worker $index',
            ),
        ],
      ),
    );
    final repository = _RosterRepository(onGet: (_, _) async => projection);
    final controller = await _controller(repository);
    addTearDown(controller.dispose);
    expect(await controller.load(workDate: _currentDate), isTrue);
    controller.selectVisible();
    controller.applyStandardMinutes();
    expect(controller.state.dirtyRows, hasLength(501));

    expect(controller.reviewDay(), isFalse);
    expect(controller.state.status, YorksWorkforceDailyRosterStatus.failure);
    expect(controller.state.error?.code, YorksV1DomainErrorCode.invalidInput);
    expect(repository.saveCalls, isEmpty);
  });
}

const _actorId = '60000000-0000-4000-8000-000000000001';
const _worker1 = '60010000-0000-4000-8000-000000000001';
const _worker2 = '60010000-0000-4000-8000-000000000002';
const _worker3 = '60010000-0000-4000-8000-000000000003';
const _team1 = '60020000-0000-4000-8000-000000000001';
const _team2 = '60020000-0000-4000-8000-000000000002';
const _trade1 = '60030000-0000-4000-8000-000000000001';
const _trade2 = '60030000-0000-4000-8000-000000000002';
const _projectId = '60040000-0000-4000-8000-000000000001';
const _otherProjectId = '60040000-0000-4000-8000-000000000002';
const _scopeId = '60050000-0000-4000-8000-000000000001';
const _locationId = '60060000-0000-4000-8000-000000000001';
const _attendance1 = '60070000-0000-4000-8000-000000000001';
const _attendance2 = '60070000-0000-4000-8000-000000000002';
const _allocationSetId = '60080000-0000-4000-8000-000000000001';
const _allocationRevisionId = '60090000-0000-4000-8000-000000000001';
const _allocationId = '60100000-0000-4000-8000-000000000001';
const _idempotencyKey = '60110000-0000-4000-8000-000000000001';
const _otherIdempotencyKey = '60110000-0000-4000-8000-000000000002';
const _currentDate = '2026-08-30';
const _previousDate = '2026-08-29';
const _nextDate = '2026-08-31';

String _workerIdAt(int index) =>
    '62010000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

String _attendanceIdAt(int index) =>
    '62070000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

String _attendanceIdForWorker(String workerId) {
  if (workerId == _worker1) return _attendance1;
  if (workerId == _worker2) return _attendance2;
  return '62070000-0000-4000-8000-${workerId.substring(workerId.length - 12)}';
}

YorksWorkforceDailyRosterSaveRow _presentSaveRow(String workerId) =>
    YorksWorkforceDailyRosterSaveRow(
      workerId: workerId,
      expectedAttendanceVersion: null,
      status: YorksWorkforceAttendanceStatus.present,
      regularMinutes: 480,
      overtimeMinutes: 0,
      overtimeReason: null,
      reason: 'Daily roster attendance edit',
      allocationAction: YorksWorkforceRosterAllocationAction.preserve,
      expectedAllocationVersion: null,
    );

Future<YorksWorkforceDailyRosterController> _controller(
  YorksWorkforceRepository repository, {
  ConnectivityService connectivity = const _Connectivity(true),
  String Function()? uuidFactory,
}) async {
  final preferences = await SharedPreferences.getInstance();
  return YorksWorkforceDailyRosterController(
    repository: repository,
    commandKeys: YorksV1CriticalCommandKeyStore(
      preferences: preferences,
      actorAuthUserId: _actorId,
      uuidFactory: uuidFactory ?? () => _idempotencyKey,
    ),
    connectivity: connectivity,
    clock: () => DateTime.utc(2026, 8, 30, 12),
  );
}

YorksSupabaseWorkforceRepository _supabaseRepository(
  YorksWorkforceRpcClient rpc,
) => YorksSupabaseWorkforceRepository(
  featureFlags: _workforceFlags,
  connectivity: const _Connectivity(true),
  rpcClient: rpc,
);

const _workforceFlags = YorksV1FeatureFlags(
  foundation: true,
  projects: true,
  boq: true,
  excel: true,
  requests: true,
  arrangement: true,
  logistics: true,
  returnsDocuments: true,
  documents: true,
  workforce: true,
);

Matcher _domainCode(YorksV1DomainErrorCode code) =>
    isA<YorksV1DomainException>().having((error) => error.code, 'code', code);

YorksWorkforceDailyRosterDraftRow _draft(
  YorksWorkforceDailyRosterController controller,
  String workerId,
) => controller.state.rows.singleWhere((row) => row.workerId == workerId);

Map<String, dynamic> _rosterResponse(
  String workDate, {
  List<Map<String, dynamic>> rows = const [],
  int? totalCount,
  Map<String, dynamic>? filters,
  Map<String, dynamic>? allocationTargets,
  int limit = 100,
  int offset = 0,
}) => {
  'schema_version': 1,
  'authorization_mode': 'enforced_t05',
  'actor_auth_user_id': _actorId,
  'work_date': workDate,
  'is_future': false,
  'server_time': '${workDate}T12:00:00Z',
  'filters': {
    'team_id': null,
    'project_id': null,
    'project_scope_id': null,
    'internal_location_id': null,
    'query': null,
    'limit': limit,
    'offset': offset,
    ...?filters,
  },
  'capabilities': {
    'can_view': true,
    'can_maintain_attendance': true,
    'can_maintain_timesheet': true,
  },
  'selectors': {
    'teams': [
      {'team_id': _team1, 'team_name': 'Duct Team'},
      {'team_id': _team2, 'team_name': 'Electrical Team'},
    ],
    'projects': [
      {
        'project_id': _projectId,
        'project_ref': 'YRA-313',
        'project_name': 'Riyadh Substation',
      },
    ],
    'project_scopes': [
      {
        'project_id': _projectId,
        'project_scope_id': _scopeId,
        'project_scope_name': 'Common / All Buildings',
      },
    ],
    'internal_locations': [
      {
        'internal_location_id': _locationId,
        'internal_location_name': 'Main Workshop',
      },
    ],
  },
  'allocation_targets':
      allocationTargets ??
      {
        'projects': [
          {
            'project_id': _projectId,
            'project_ref': 'YRA-313',
            'project_name': 'Riyadh Substation',
          },
        ],
        'project_scopes': [
          {
            'project_id': _projectId,
            'project_scope_id': _scopeId,
            'project_scope_kind': 'common',
            'project_scope_code': 'common',
            'project_scope_name': 'Common / All Buildings',
          },
        ],
        'internal_locations': [
          {
            'internal_location_id': _locationId,
            'location_code': 'MAIN',
            'location_name': 'Main Workshop',
            'department_cost_centre': null,
          },
        ],
      },
  'total_count': totalCount ?? rows.length,
  'rows': rows,
};

Map<String, dynamic> _rowJson({
  required String workerId,
  required String workerNumber,
  required String workerName,
  String teamId = _team1,
  String teamName = 'Duct Team',
  String? tradeId,
  String? tradeName,
  Map<String, dynamic>? attendance,
  Map<String, dynamic>? allocationSet,
  bool hasActiveAllocationLock = false,
  bool allocationDetailsRestricted = false,
  bool canMaintainAttendance = true,
  bool canMaintainTimesheet = true,
}) => {
  'worker_id': workerId,
  'worker_number': workerNumber,
  'worker_name': workerName,
  'designation': 'Technician',
  'trade_id': tradeId,
  'trade_name': tradeName,
  'department': 'Operations',
  'employer_company': 'Yorks AC & Ref.',
  'worker_type': 'yorks_employee',
  'assignment': _assignmentJson(teamId: teamId, teamName: teamName),
  'schedule_suggestion': _scheduleSuggestionJson(),
  'attendance': attendance,
  'allocation_set': allocationSet,
  'has_active_allocation_lock': hasActiveAllocationLock,
  'allocation_details_restricted': allocationDetailsRestricted,
  'can_maintain_attendance': canMaintainAttendance,
  'can_maintain_timesheet': canMaintainTimesheet,
};

Map<String, dynamic> _assignmentJson({
  String teamId = _team1,
  String teamName = 'Duct Team',
}) => {
  'assignment_id': '60120000-0000-4000-8000-000000000001',
  'assignment_kind': 'primary',
  'team_id': teamId,
  'team_name': teamName,
  'supervisor_auth_user_id': _actorId,
  'supervisor_name': 'Workforce Supervisor',
  'project_id': _projectId,
  'project_ref': 'YRA-313',
  'project_name': 'Riyadh Substation',
  'project_scope_id': _scopeId,
  'project_scope_name': 'Common / All Buildings',
  'internal_location_id': null,
  'internal_location_name': null,
  'valid_from': '2026-01-01',
  'valid_to': null,
  'record_version': 1,
};

Map<String, dynamic> _scheduleSuggestionJson() => {
  ..._scheduleJson(),
  'source': 'schedule_only',
  'suggested_attendance_status': 'present',
  'suggested_regular_minutes': 480,
  'suggested_overtime_minutes': 0,
  'requires_confirmation': true,
};

Map<String, dynamic> _scheduleJson() => {
  'team_schedule_link_id': '60130000-0000-4000-8000-000000000001',
  'team_schedule_record_version': 1,
  'calendar_id': '60140000-0000-4000-8000-000000000001',
  'calendar_code': 'UAE-SITE',
  'calendar_name': 'UAE Site Calendar',
  'calendar_timezone': 'Asia/Dubai',
  'calendar_record_version': 1,
  'calendar_date_override_id': null,
  'calendar_date_override_version': null,
  'calendar_override_kind': null,
  'calendar_exception_name': null,
  'day_type_source': 'weekday',
  'iso_weekday': 7,
  'day_type': 'regular_working_day',
  'scheduled_minutes': 480,
  'break_minutes': 60,
  'shift_template_id': null,
  'shift_code': null,
  'shift_name': null,
  'shift_kind': null,
  'shift_start_time': null,
  'shift_end_time': null,
  'shift_scheduled_minutes': null,
  'shift_break_minutes': null,
  'shift_crosses_midnight': null,
  'shift_work_date_basis': null,
  'shift_record_version': null,
};

Map<String, dynamic> _attendanceJson({
  required String workerId,
  required String attendanceId,
  required String workDate,
  YorksWorkforceAttendanceStatus status =
      YorksWorkforceAttendanceStatus.present,
  int regularMinutes = 480,
  int overtimeMinutes = 0,
  String? overtimeReason,
  int recordVersion = 1,
}) => {
  'attendance_day_id': attendanceId,
  'worker_id': workerId,
  'worker_number': workerId == _worker2 ? 'WF-002' : 'WF-001',
  'worker_name': workerId == _worker2 ? 'Second Worker' : 'First Worker',
  'worker_joining_date': '2026-01-01',
  'worker_leaving_date': null,
  'worker_status_at_creation': 'active',
  'work_date': workDate,
  'attendance_status': status.wireValue,
  'regular_minutes': regularMinutes,
  'overtime_minutes': overtimeMinutes,
  'overtime_reason': overtimeReason,
  'reason': 'Daily roster attendance save',
  'record_version': recordVersion,
  'created_at': '${workDate}T08:00:00Z',
  'updated_at': '${workDate}T08:00:00Z',
  'assignment': _assignmentJson(),
  'initial_authority': {
    'authority_kind': 'responsibility',
    'responsibility_assignment_id': '60150000-0000-4000-8000-000000000001',
    'scope_kind': 'project',
    'scope_reference': 'project:$_projectId',
    'record_version': 1,
  },
  'schedule': _scheduleJson(),
};

Map<String, dynamic> _allocationSetJson({
  required String workerId,
  required String attendanceId,
  required String workDate,
  required int regularMinutes,
  int overtimeMinutes = 0,
  String? activityTask,
  String? notes,
}) => {
  'allocation_set_id': _allocationSetId,
  'attendance_day_id': attendanceId,
  'worker_id': workerId,
  'work_date': workDate,
  'state': 'active',
  'record_version': 1,
  'current_revision': {
    'revision_id': _allocationRevisionId,
    'revision_number': 1,
    'state': 'active',
    'attendance_record_version_basis': 1,
    'total_regular_minutes': regularMinutes,
    'total_overtime_minutes': overtimeMinutes,
    'reason': 'Retained allocation evidence',
    'created_by_auth_user_id': _actorId,
    'created_at': '${workDate}T08:00:00Z',
  },
  'attendance': {
    'status': 'present',
    'regular_minutes': regularMinutes,
    'overtime_minutes': overtimeMinutes,
    'record_version': 1,
    'calendar_timezone': 'Asia/Dubai',
  },
  'allocations': [
    {
      'allocation_id': _allocationId,
      'line_number': 1,
      'target_kind': 'project_work',
      'project': {
        'project_id': _projectId,
        'project_ref': 'YRA-313',
        'project_name': 'Riyadh Substation',
        'project_record_version': 1,
        'project_scope_id': _scopeId,
        'project_scope_kind': 'common',
        'project_scope_code': 'common',
        'project_scope_name': 'Common / All Buildings',
        'project_scope_record_version': 1,
      },
      'internal_location': null,
      'activity_task': activityTask,
      'notes': notes,
      'regular_minutes': regularMinutes,
      'overtime_minutes': overtimeMinutes,
      'start_time': null,
      'end_time': null,
      'crosses_midnight': null,
    },
  ],
  'created_at': '${workDate}T08:00:00Z',
  'updated_at': '${workDate}T08:00:00Z',
};

Map<String, dynamic> _saveResponse(
  String workDate,
  List<YorksWorkforceDailyRosterSaveRow> rows,
) => {
  'schema_version': 1,
  'authorization_mode': 'enforced_t05',
  'work_date': workDate,
  'saved_at': '2026-08-30T12:30:00Z',
  'row_count': rows.length,
  'rows': [
    for (final row in rows)
      {
        'worker_id': row.workerId,
        'attendance_day_id': _attendanceIdForWorker(row.workerId),
        'attendance_record_version': 1,
        'attendance': _attendanceJson(
          workerId: row.workerId,
          attendanceId: _attendanceIdForWorker(row.workerId),
          workDate: workDate,
          status: row.status,
          regularMinutes: row.regularMinutes,
          overtimeMinutes: row.overtimeMinutes,
          overtimeReason: row.overtimeReason,
        ),
        'allocation_set': null,
        'allocation_set_id': null,
        'allocation_set_record_version': null,
        'allocation_state': null,
      },
  ],
};

final class _RpcClient implements YorksWorkforceRpcClient {
  _RpcClient(this.handler);

  final Map<String, dynamic> Function(
    String functionName,
    Map<String, Object?> parameters,
  )
  handler;
  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add(functionName);
    return handler(functionName, parameters);
  }
}

final class _RosterRepository implements YorksWorkforceRepository {
  _RosterRepository({required this.onGet, this.onSave});

  final Future<YorksWorkforceDailyRosterProjection> Function(
    String workDate,
    YorksWorkforceRosterFilters filters,
  )
  onGet;
  final Future<YorksWorkforceDailyRosterSaveResult> Function(
    String workDate,
    List<YorksWorkforceDailyRosterSaveRow> rows,
    String reason,
    String idempotencyKey,
  )?
  onSave;
  final List<String> getDates = [];
  final List<(String, YorksWorkforceRosterFilters)> getFilters = [];
  final List<_SaveCall> saveCalls = [];

  @override
  Future<YorksWorkforceDailyRosterProjection> getDailyRoster({
    required String workDate,
    YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  }) {
    getDates.add(workDate);
    getFilters.add((workDate, filters));
    return onGet(workDate, filters);
  }

  @override
  Future<YorksWorkforceDailyRosterSaveResult> saveDailyRoster({
    required String workDate,
    required List<YorksWorkforceDailyRosterSaveRow> rows,
    required String reason,
    required String idempotencyKey,
  }) {
    saveCalls.add(
      _SaveCall(
        workDate: workDate,
        rows: List.unmodifiable(rows),
        reason: reason,
        idempotencyKey: idempotencyKey,
      ),
    );
    final handler = onSave;
    if (handler == null) {
      return Future.error(StateError('Unexpected save'));
    }
    return handler(workDate, rows, reason, idempotencyKey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SaveCall {
  const _SaveCall({
    required this.workDate,
    required this.rows,
    required this.reason,
    required this.idempotencyKey,
  });

  final String workDate;
  final List<YorksWorkforceDailyRosterSaveRow> rows;
  final String reason;
  final String idempotencyKey;
}

final class _Connectivity implements ConnectivityService {
  const _Connectivity(this.isOnline);

  @override
  final bool isOnline;

  @override
  Stream<bool> get onChange => const Stream.empty();
}

final class _MutableConnectivity implements ConnectivityService {
  _MutableConnectivity(this.isOnline);

  @override
  bool isOnline;

  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  Stream<bool> get onChange => _changes.stream;

  void setOnline(bool value) {
    isOnline = value;
    _changes.add(value);
  }

  Future<void> dispose() => _changes.close();
}

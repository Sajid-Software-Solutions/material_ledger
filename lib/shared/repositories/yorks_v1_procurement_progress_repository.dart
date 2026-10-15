import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_procurement_progress.dart';
import '../sync/connectivity_service.dart';
import 'yorks_v1_material_request_repository.dart';

class YorksV1ProcurementProgressRead {
  const YorksV1ProcurementProgressRead({
    this.checkpoint,
    this.revision = 0,
    this.discarded = false,
    this.pendingCommand,
  });
  final YorksV1ProcurementProgressCheckpoint? checkpoint;
  final int revision;
  final bool discarded;
  final YorksV1ProcurementPendingCommand? pendingCommand;
}

class YorksV1ProcurementCommandOutcome {
  const YorksV1ProcurementCommandOutcome({
    required this.status,
    this.attemptId,
    this.commandPayload,
    this.workspace,
    this.effectId,
    this.effectReference,
    this.committedVersion,
    this.automaticChecksRemaining,
    this.retryAfter = Duration.zero,
    this.checkDeferred = false,
  });
  final String status;
  final String? attemptId;
  final Map<String, Object?>? commandPayload;
  final Map<String, Object?>? workspace;
  final String? effectId, effectReference;
  final int? committedVersion, automaticChecksRemaining;
  final Duration retryAfter;
  final bool checkDeferred;
  bool get isConfirmed => status == 'confirmed';
  bool get isAccessChanged => status == 'access_changed';
}

abstract interface class YorksV1ProcurementProgressRepository {
  Future<YorksV1ProcurementProgressRead> get(
    YorksV1ProcurementProgressScope scope,
  );
  Future<YorksV1ProcurementProgressCheckpoint> save({
    required YorksV1ProcurementProgressDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> discard({
    required YorksV1ProcurementProgressScope scope,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<YorksV1ProcurementPendingCommand> prepare({
    required YorksV1ProcurementProgressScope scope,
    required int checkpointRevision,
    required String commandName,
    required String commandKey,
    required Map<String, Object?> commandPayload,
    required String idempotencyKey,
  });
  Future<String> abandon({
    required String requestId,
    required String commandName,
    required String commandKey,
  });
  Future<YorksV1ProcurementCommandOutcome> outcome({
    required String requestId,
    required String commandName,
    required String commandKey,
    bool automatic = false,
  });
}

class YorksV1SupabaseProcurementProgressRepository
    implements YorksV1ProcurementProgressRepository {
  const YorksV1SupabaseProcurementProgressRepository({
    required ConnectivityService connectivity,
    YorksV1MaterialRequestRpcClient? rpcClient,
    Duration timeout = const Duration(seconds: 20),
    Duration outcomeTimeout = const Duration(seconds: 5),
  }) : _connectivity = connectivity,
       _rpc = rpcClient,
       _timeout = timeout,
       _outcomeTimeout = outcomeTimeout;
  final ConnectivityService _connectivity;
  final YorksV1MaterialRequestRpcClient? _rpc;
  final Duration _timeout, _outcomeTimeout;

  @override
  Future<YorksV1ProcurementProgressRead> get(
    YorksV1ProcurementProgressScope scope,
  ) async {
    final raw = await _invoke('v1_get_procurement_progress_recovery', {
      'p_request_id': scope.requestId,
      'p_editor_kind': scope.editorKind.name,
      'p_arrangement_id': scope.arrangementId,
    });
    if (raw == null) return const YorksV1ProcurementProgressRead();
    final json = _object(raw);
    if (json['discarded'] == true) {
      final revision = json['revision'];
      if (revision is! int || revision < 1) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      return YorksV1ProcurementProgressRead(
        revision: revision,
        discarded: true,
      );
    }
    final checkpoint = _checkpoint(json);
    if (checkpoint.draft.scope != scope) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProcurementProgressRead(
      checkpoint: checkpoint,
      revision: checkpoint.revision,
      pendingCommand: json['pending_command'] == null
          ? null
          : YorksV1ProcurementPendingCommand.fromJson(
              _object(json['pending_command']),
            ),
    );
  }

  @override
  Future<YorksV1ProcurementProgressCheckpoint> save({
    required YorksV1ProcurementProgressDraft draft,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _checkpoint(
    _object(
      await _invoke('v1_save_procurement_progress', {
        'p_payload': {...draft.toJson(), 'expected_revision': expectedRevision},
        'p_idempotency_key': idempotencyKey,
      }),
    ),
  );

  @override
  Future<int> discard({
    required YorksV1ProcurementProgressScope scope,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final json = _object(
      await _invoke('v1_discard_procurement_progress', {
        'p_payload': {
          ..._identity(scope),
          'expected_revision': expectedRevision,
        },
        'p_idempotency_key': idempotencyKey,
      }),
    );
    if (json['discarded'] != true || json['revision'] is! int) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return json['revision'] as int;
  }

  @override
  Future<YorksV1ProcurementPendingCommand> prepare({
    required YorksV1ProcurementProgressScope scope,
    required int checkpointRevision,
    required String commandName,
    required String commandKey,
    required Map<String, Object?> commandPayload,
    required String idempotencyKey,
  }) async {
    final json = _object(
      await _invoke('v1_prepare_procurement_command', {
        'p_payload': {
          ..._identity(scope),
          'checkpoint_revision': checkpointRevision,
          'command_name': commandName,
          'command_key': commandKey,
          'command_payload': commandPayload,
        },
        'p_idempotency_key': idempotencyKey,
      }),
    );
    if (json['attempt_id'] is! String ||
        json['command_key'] != commandKey ||
        json['command_name'] != commandName) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProcurementPendingCommand(
      attemptId: json['attempt_id'] as String,
      commandName: commandName,
      commandKey: commandKey,
    );
  }

  @override
  Future<String> abandon({
    required String requestId,
    required String commandName,
    required String commandKey,
  }) async {
    final json = _object(
      await _invoke('v1_abandon_procurement_command', {
        'p_request_id': requestId,
        'p_command_name': commandName,
        'p_idempotency_key': commandKey,
      }),
    );
    if (json['status'] != 'abandoned' && json['status'] != 'confirmed') {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return json['status'] as String;
  }

  @override
  Future<YorksV1ProcurementCommandOutcome> outcome({
    required String requestId,
    required String commandName,
    required String commandKey,
    bool automatic = false,
  }) async {
    final json = _object(
      await _invoke('v1_reconcile_procurement_command_outcome', {
        'p_request_id': requestId,
        'p_command_name': commandName,
        'p_idempotency_key': commandKey,
        'p_automatic': automatic,
      }, timeout: _outcomeTimeout),
    );
    final status = json['status'];
    if (status is! String ||
        !{
          'confirmed',
          'not_found',
          'pending',
          'prepared',
          'access_changed',
          'rejected',
          'abandoned',
        }.contains(status)) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    if (json['request_id'] != requestId ||
        json['command_name'] != commandName ||
        json['idempotency_key'] != commandKey) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final receipt = json['receipt'] is Map ? _object(json['receipt']) : null;
    if (status == 'confirmed' &&
        (receipt?['effect_id'] is! String ||
            (receipt!['effect_id'] as String).isEmpty)) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1ProcurementCommandOutcome(
      status: status,
      attemptId: json['attempt_id'] is String
          ? json['attempt_id'] as String
          : null,
      commandPayload: json['command_payload'] == null
          ? null
          : _object(json['command_payload']),
      // Optional projection problems cannot invalidate an authoritative receipt.
      workspace: json['workspace'] is Map ? _object(json['workspace']) : null,
      effectId: receipt?['effect_id'] as String?,
      effectReference: receipt?['effect_reference'] is String
          ? receipt!['effect_reference'] as String
          : null,
      committedVersion: receipt?['committed_version'] is int
          ? receipt!['committed_version'] as int
          : null,
      automaticChecksRemaining: json['automatic_checks_remaining'] as int?,
      retryAfter: Duration(milliseconds: (json['retry_after_ms'] as int?) ?? 0),
      checkDeferred: json['check_deferred'] == true,
    );
  }

  Future<Object?> _invoke(
    String function,
    Map<String, Object?> parameters, {
    Duration? timeout,
  }) async {
    if (!_connectivity.isOnline) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
    if (_rpc == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    try {
      return await _rpc
          .invoke(functionName: function, parameters: parameters)
          .timeout(timeout ?? _timeout);
    } on YorksV1DomainException {
      rethrow;
    } on PostgrestException catch (error) {
      throw YorksV1DomainException(
        switch (error.code) {
          '42501' => YorksV1DomainErrorCode.unauthorized,
          '28000' ||
          'PGRST301' ||
          'PGRST302' => YorksV1DomainErrorCode.unauthenticated,
          '40001' || '23505' || '55P03' => YorksV1DomainErrorCode.conflict,
          '22023' ||
          '22007' ||
          '22P02' ||
          '23514' => YorksV1DomainErrorCode.invalidInput,
          _ => YorksV1DomainErrorCode.serverRejected,
        },
        serverCode: error.code,
        cause: error,
      );
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      );
    }
  }

  static Map<String, Object?> _identity(
    YorksV1ProcurementProgressScope scope,
  ) => {
    'request_id': scope.requestId,
    'editor_kind': scope.editorKind.name,
    'arrangement_id': scope.arrangementId,
  };
  static Map<String, Object?> _object(Object? raw) {
    if (raw is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return Map<String, Object?>.from(raw);
  }

  static YorksV1ProcurementProgressCheckpoint _checkpoint(
    Map<String, Object?> raw,
  ) {
    try {
      return YorksV1ProcurementProgressCheckpoint.fromJson(raw);
    } catch (error) {
      throw YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
        cause: error,
      );
    }
  }
}

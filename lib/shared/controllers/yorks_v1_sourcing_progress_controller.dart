import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/yorks_v1_sourcing_progress.dart';
import '../models/yorks_v1_domain_error.dart';
import '../repositories/yorks_v1_sourcing_progress_repository.dart';

class YorksV1SourcingProgressState {
  const YorksV1SourcingProgressState({
    this.progress,
    this.loading = false,
    this.saving = false,
    this.error,
  });
  final YorksV1SourcingProgress? progress;
  final bool loading;
  final bool saving;
  final Object? error;
}

class YorksV1SourcingProgressController
    extends StateNotifier<YorksV1SourcingProgressState> {
  YorksV1SourcingProgressController(this.repository, this.scope)
    : super(const YorksV1SourcingProgressState(loading: true));
  final YorksV1SourcingProgressRepository repository;
  final YorksV1SourcingScope scope;
  String? _fingerprint;
  String? _key;
  bool _blocked = false;
  bool get canRefresh =>
      mounted && !state.loading && !state.saving && state.error == null;
  int _generation = 0;
  void deny() {
    ++_generation;
    _blocked = true;
    state = const YorksV1SourcingProgressState(
      error: YorksV1DomainException(YorksV1DomainErrorCode.unauthorized),
    );
  }

  Future<void> load({bool refresh = false}) async {
    if (state.saving) return;
    final generation = ++_generation;
    state = YorksV1SourcingProgressState(
      progress: refresh ? state.progress : null,
      loading: true,
    );
    try {
      final progress = await repository.read(scope);
      if (!mounted || generation != _generation) return;
      _checkIdentity(progress);
      _blocked = false;
      state = YorksV1SourcingProgressState(progress: progress);
    } catch (e) {
      if (mounted && generation == _generation) {
        _blocked = true;
        state = YorksV1SourcingProgressState(error: e);
      }
    }
  }

  Future<bool> save({
    required int requestVersion,
    required int arrangementVersion,
    required List<YorksV1SourcingLine> lines,
  }) async {
    if (state.loading ||
        state.saving ||
        _blocked ||
        scope.arrangementId == null) {
      return false;
    }
    final payload = <String, Object?>{
      'request_id': scope.requestId,
      'arrangement_id': scope.arrangementId,
      'expected_request_version': requestVersion,
      'expected_arrangement_version': arrangementVersion,
      'expected_revision': state.progress?.revision ?? 0,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
    final fingerprint = jsonEncode(payload);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _key = const Uuid().v4();
    }
    final prior = state.progress;
    final generation = ++_generation;
    state = YorksV1SourcingProgressState(progress: prior, saving: true);
    try {
      final progress = await repository.save(payload, _key!);
      if (!mounted || generation != _generation) return false;
      _checkIdentity(progress);
      _key = _fingerprint = null;
      state = YorksV1SourcingProgressState(progress: progress);
      return true;
    } catch (e) {
      if (!mounted || generation != _generation) return false;
      final denied =
          e is YorksV1DomainException &&
          e.code == YorksV1DomainErrorCode.unauthorized;
      _blocked =
          denied ||
          (e is YorksV1DomainException &&
              e.code == YorksV1DomainErrorCode.conflict);
      state = YorksV1SourcingProgressState(
        progress: denied ? null : prior,
        error: e,
      );
      return false;
    }
  }

  void _checkIdentity(YorksV1SourcingProgress? progress) {
    if (progress != null &&
        (progress.requestId != scope.requestId ||
            (scope.arrangementId != null &&
                progress.arrangementId != scope.arrangementId))) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
  }
}

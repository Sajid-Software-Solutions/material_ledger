import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/yorks_v1_document.dart';
import '../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/repositories/yorks_v1_documents_repository.dart';
import '../data/accounts_records_repository.dart';
import '../domain/accounts_records_models.dart';
import 'accounts_controller.dart';

final class YorksAccountsDocumentsState {
  const YorksAccountsDocumentsState({
    this.status = YorksAccountsViewStatus.idle,
    this.workspace,
    this.error,
    this.isUploading = false,
    this.search,
    this.documentType,
  });

  final YorksAccountsViewStatus status;
  final YorksV1AccountsDocumentWorkspace? workspace;
  final YorksV1DomainException? error;
  final bool isUploading;
  final String? search;
  final YorksV1AccountsDocumentType? documentType;
}

final class YorksAccountsDocumentsController
    extends StateNotifier<YorksAccountsDocumentsState> {
  YorksAccountsDocumentsController({
    required String projectId,
    required YorksV1AccountsDocumentsRepository repository,
  }) : _projectId = projectId.trim(),
       _repository = repository,
       super(const YorksAccountsDocumentsState());

  final String _projectId;
  final YorksV1AccountsDocumentsRepository _repository;

  Future<bool> load({
    String? search,
    YorksV1AccountsDocumentType? documentType,
  }) async {
    state = YorksAccountsDocumentsState(
      status: YorksAccountsViewStatus.loading,
      workspace: state.workspace,
      search: search,
      documentType: documentType,
    );
    try {
      final workspace = await _repository.getAccountsWorkspace(
        _projectId,
        search: search,
        documentType: documentType,
      );
      state = YorksAccountsDocumentsState(
        status: YorksAccountsViewStatus.success,
        workspace: workspace,
        search: search,
        documentType: documentType,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      final status = _statusFor(error.code);
      state = YorksAccountsDocumentsState(
        status: status,
        workspace: _mustPurgeAccountsRecords(status) ? null : state.workspace,
        error: error,
        search: search,
        documentType: documentType,
      );
      return false;
    }
  }

  Future<bool> upload(YorksV1DocumentUploadInput input) async {
    state = YorksAccountsDocumentsState(
      status: state.status,
      workspace: state.workspace,
      search: state.search,
      documentType: state.documentType,
      isUploading: true,
    );
    try {
      await _repository.uploadAccounts(input);
      await load(search: state.search, documentType: state.documentType);
      return true;
    } on YorksV1CommittedViewUnavailable catch (error) {
      state = YorksAccountsDocumentsState(
        status: state.workspace == null
            ? YorksAccountsViewStatus.idle
            : YorksAccountsViewStatus.success,
        workspace: state.workspace,
        error: error,
        search: state.search,
        documentType: state.documentType,
      );
      // Upload succeeded; the existing error state offers a read-only refresh.
      return true;
    } on YorksV1DomainException catch (error) {
      state = YorksAccountsDocumentsState(
        status: state.workspace == null
            ? _statusFor(error.code)
            : YorksAccountsViewStatus.success,
        workspace: state.workspace,
        error: error,
        search: state.search,
        documentType: state.documentType,
      );
      return false;
    }
  }

  Future<Uint8List> download(YorksV1DocumentVersion version) =>
      _repository.downloadDocument(
        bucketId: version.bucketId,
        objectPath: version.objectPath,
      );
}

final class YorksAccountsActivityState {
  const YorksAccountsActivityState({
    this.status = YorksAccountsViewStatus.idle,
    this.projection,
    this.filters = const YorksAccountsActivityFilters(),
    this.error,
    this.isLoadingMore = false,
  });

  final YorksAccountsViewStatus status;
  final YorksAccountsActivityProjection? projection;
  final YorksAccountsActivityFilters filters;
  final YorksV1DomainException? error;
  final bool isLoadingMore;
}

final class YorksAccountsActivityController
    extends StateNotifier<YorksAccountsActivityState> {
  YorksAccountsActivityController({
    required String projectId,
    required YorksAccountsRecordsRepository repository,
  }) : _projectId = projectId.trim(),
       _repository = repository,
       super(const YorksAccountsActivityState());

  final String _projectId;
  final YorksAccountsRecordsRepository _repository;

  Future<bool> load([YorksAccountsActivityFilters? filters]) async {
    final next = filters ?? state.filters;
    state = YorksAccountsActivityState(
      status: YorksAccountsViewStatus.loading,
      projection: state.projection,
      filters: next,
    );
    try {
      final projection = await _repository.getActivity(_projectId, next);
      state = YorksAccountsActivityState(
        status: YorksAccountsViewStatus.success,
        projection: projection,
        filters: next,
      );
      return true;
    } on YorksV1DomainException catch (error) {
      final status = _statusFor(error.code);
      state = YorksAccountsActivityState(
        status: status,
        projection: _mustPurgeAccountsRecords(status) ? null : state.projection,
        filters: next,
        error: error,
      );
      return false;
    }
  }

  Future<bool> loadMore() async {
    final current = state.projection;
    if (current == null || !current.hasMore || state.isLoadingMore) {
      return false;
    }
    state = YorksAccountsActivityState(
      status: YorksAccountsViewStatus.success,
      projection: current,
      filters: state.filters,
      isLoadingMore: true,
    );
    final nextFilters = YorksAccountsActivityFilters(
      entityType: state.filters.entityType,
      action: state.filters.action,
      actorAuthUserId: state.filters.actorAuthUserId,
      from: state.filters.from,
      to: state.filters.to,
      limit: state.filters.limit,
      offset: current.offset + current.entries.length,
    );
    try {
      final next = await _repository.getActivity(_projectId, nextFilters);
      state = YorksAccountsActivityState(
        status: YorksAccountsViewStatus.success,
        filters: state.filters,
        projection: YorksAccountsActivityProjection(
          projectId: current.projectId,
          total: next.total,
          limit: current.limit,
          offset: current.offset,
          entries: [...current.entries, ...next.entries],
        ),
      );
      return true;
    } on YorksV1DomainException catch (error) {
      state = YorksAccountsActivityState(
        status: YorksAccountsViewStatus.success,
        projection: current,
        filters: state.filters,
        error: error,
      );
      return false;
    }
  }
}

bool _mustPurgeAccountsRecords(YorksAccountsViewStatus status) =>
    status == YorksAccountsViewStatus.forbidden ||
    status == YorksAccountsViewStatus.sessionExpired ||
    status == YorksAccountsViewStatus.unavailable;

YorksAccountsViewStatus _statusFor(YorksV1DomainErrorCode code) =>
    switch (code) {
      YorksV1DomainErrorCode.featureDisabled =>
        YorksAccountsViewStatus.unavailable,
      YorksV1DomainErrorCode.offline => YorksAccountsViewStatus.offline,
      YorksV1DomainErrorCode.unauthenticated =>
        YorksAccountsViewStatus.sessionExpired,
      YorksV1DomainErrorCode.unauthorized => YorksAccountsViewStatus.forbidden,
      YorksV1DomainErrorCode.conflict => YorksAccountsViewStatus.conflict,
      _ => YorksAccountsViewStatus.failure,
    };

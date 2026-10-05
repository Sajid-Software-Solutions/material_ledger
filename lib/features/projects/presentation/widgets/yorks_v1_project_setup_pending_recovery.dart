import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/controllers/yorks_v1_project_setup_coordinator.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_setup_operation.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';
import 'yorks_v1_project_setup_completion_strings.dart';

/// Project-linked follow-up for a confirmed historical setup operation. Reading
/// never dispatches a command. Every explicit action uses the original journal
/// scope, independently of the current edit proposal and its form controllers.
class YorksV1ProjectSetupPendingRecovery extends ConsumerWidget {
  const YorksV1ProjectSetupPendingRecovery({
    super.key,
    required this.project,
    this.activeMembers = const [],
  });

  final YorksV1Project project;
  final List<YorksV1ProjectMember> activeMembers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(yorksV1AuthUserIdProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permission = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final language = ref.watch(languageProvider);
    if (owner == null ||
        !_engineeringAccess(role, owner, project.id, activeMembers) ||
        !permission.hybridAllows(
          YorksV1CapabilityKeys.projectsView,
          legacyAllowed: true,
          projectId: project.id,
        )) {
      return const SizedBox.shrink();
    }
    List<YorksV1ProjectSetupPendingOperation> pending;
    try {
      pending = ref.watch(
        yorksV1ProjectSetupPendingOperationsProvider((
          ownerAuthUserId: owner,
          projectId: project.id,
        )),
      );
    } catch (_) {
      // Unsupported recovery stays preserved and is never coerced into a new
      // command or allowed to break the separate editable project form.
      return Text(
        YorksV1ProjectStrings.localRecoveryUnavailable.active(language),
        style: AppTypography.bodySmall,
      );
    }
    return Column(
      key: const ValueKey('project-setup-pending-recovery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in pending)
          if (item.operation.ownerAuthUserId == owner &&
              item.operation.coreSucceeded &&
              item.operation.project?.id == project.id)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _PendingOperationCard(
                key: ValueKey('$owner:${project.id}:${item.scope.draftId}'),
                item: item,
                project: project,
                activeMembers: activeMembers,
                language: language,
              ),
            ),
      ],
    );
  }
}

bool _engineeringAccess(
  YorksV1Role? role,
  String owner,
  String projectId,
  List<YorksV1ProjectMember> members,
) =>
    role == YorksV1Role.admin ||
    role?.isGlobalProjectEngineer == true ||
    (role?.isEngineering == true &&
        members.any(
          (member) =>
              member.projectId == projectId &&
              member.memberAuthUserId == owner &&
              member.isActiveAt(DateTime.now()),
        ));

class _PendingOperationCard extends ConsumerStatefulWidget {
  const _PendingOperationCard({
    super.key,
    required this.item,
    required this.project,
    required this.activeMembers,
    required this.language,
  });

  final YorksV1ProjectSetupPendingOperation item;
  final YorksV1Project project;
  final List<YorksV1ProjectMember> activeMembers;
  final AppLanguage language;

  @override
  ConsumerState<_PendingOperationCard> createState() =>
      _PendingOperationCardState();
}

class _PendingOperationCardState extends ConsumerState<_PendingOperationCard> {
  static const _actionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(44, 44)),
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );

  bool _working = false;
  TranslatableString? _message;

  YorksV1ProjectSetupScope get _scope => widget.item.scope;

  bool _current(YorksV1ProjectSetupScope scope, String projectId) =>
      mounted &&
      _scope == scope &&
      widget.project.id == projectId &&
      ref.read(yorksV1AuthUserIdProvider) == scope.ownerAuthUserId;

  bool _access(String capability) {
    if (capability == YorksV1CapabilityKeys.documentsUpload &&
        !ref.read(yorksV1FeatureFlagsProvider).documents) {
      return false;
    }
    final role = ref.read(yorksV1CurrentRoleProvider);
    final owner = _scope.ownerAuthUserId;
    if (!_engineeringAccess(
      role,
      owner,
      widget.project.id,
      widget.activeMembers,
    )) {
      return false;
    }
    final manage =
        role == YorksV1Role.admin ||
        role?.isGlobalProjectEngineer == true ||
        widget.activeMembers.any(
          (member) =>
              member.projectId == widget.project.id &&
              member.memberAuthUserId == owner &&
              member.isActiveAt(DateTime.now()) &&
              member.projectRole ==
                  YorksV1ProjectMembershipRole.projectEngineer,
        );
    return yorksV1FeatureActionAccess(
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      capability,
      legacyAllowed:
          capability != YorksV1CapabilityKeys.projectsChangeState || manage,
      projectId: widget.project.id,
    ).canWrite;
  }

  bool _canReadFile(
    YorksV1ProjectSetupFile file,
    YorksV1CurrentPermissionSnapshotState permission,
    YorksV1Role? role,
  ) => permission.hybridAllows(
    switch (file.classification) {
      YorksV1DocumentClassification.operational =>
        YorksV1CapabilityKeys.documentsView,
      YorksV1DocumentClassification.commercial =>
        YorksV1CapabilityKeys.documentsCommercialView,
      YorksV1DocumentClassification.adminRestricted =>
        YorksV1CapabilityKeys.documentsAdminRestrictedView,
    },
    legacyAllowed:
        file.classification == YorksV1DocumentClassification.operational ||
        role == YorksV1Role.admin,
    projectId: widget.project.id,
  );

  bool _activationPending(YorksV1ProjectSetupOperation operation) =>
      operation.activation != null &&
      operation.activation!.status !=
          YorksV1ProjectSetupCommandStatus.confirmedSuccess;

  Future<void> _run(
    String capability,
    Future<void> Function(YorksV1ProjectSetupCoordinator coordinator) action,
  ) async {
    final scope = _scope;
    final projectId = widget.project.id;
    if (_working || !_current(scope, projectId) || !_access(capability)) return;
    final coordinator = ref.read(
      yorksV1ProjectSetupCoordinatorProvider(scope).notifier,
    );
    if (coordinator.currentState.busy) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action(coordinator);
      if (!_current(scope, projectId)) return;
      await coordinator.captureKnownOutcome();
      if (!_current(scope, projectId)) return;
      final operation = coordinator.currentState.operation;
      if (operation != null &&
          operation.coreSucceeded &&
          !operation.filesPending &&
          !operation.hasUnresolvedCommand &&
          !_activationPending(operation)) {
        await coordinator.markCleanupComplete();
      }
    } on YorksV1ProjectSetupRecoveryException catch (error) {
      if (_current(scope, projectId)) {
        _message = switch (error.code) {
          YorksV1ProjectSetupRecoveryError.fileMismatch =>
            YorksV1ProjectStrings.fileContentMismatch,
          YorksV1ProjectSetupRecoveryError.retryLimit =>
            YorksV1ProjectStrings.commandRetryLimit,
          YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent =>
            YorksV1ProjectStrings.originalSubmissionPending,
          YorksV1ProjectSetupRecoveryError.recoveryBlocked =>
            YorksV1ProjectStrings.localRecoveryUnavailable,
          YorksV1ProjectSetupRecoveryError.journalUnavailable =>
            YorksV1ProjectStrings.journalUnavailable,
        };
      }
    } on YorksV1DomainException catch (error) {
      if (_current(scope, projectId)) {
        _message = YorksV1ProjectStrings.errorFor(error.code);
      }
    } catch (_) {
      if (_current(scope, projectId)) {
        _message = YorksV1ProjectStrings.projectSavedHousekeeping;
      }
    } finally {
      if (_current(scope, projectId)) {
        ref.invalidate(
          yorksV1ProjectSetupPendingOperationsProvider((
            ownerAuthUserId: scope.ownerAuthUserId,
            projectId: projectId,
          )),
        );
        setState(() => _working = false);
      }
    }
  }

  Future<void> _reselect(YorksV1ProjectSetupFile file) async {
    final scope = _scope;
    final projectId = widget.project.id;
    if (_working ||
        !_current(scope, projectId) ||
        !_access(YorksV1CapabilityKeys.documentsUpload)) {
      return;
    }
    // The picker may stay open while the session or route changes. No upload
    // begins until the original owner/project and permissions are checked again.
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final selected = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (!_current(scope, projectId)) return;
      setState(() => _working = false);
      if (selected == null ||
          !_access(YorksV1CapabilityKeys.documentsUpload) ||
          !_canReadFile(
            file,
            ref.read(yorksV1CurrentPermissionSnapshotProvider),
            ref.read(yorksV1CurrentRoleProvider),
          )) {
        return;
      }
      if (selected.fileName != file.fileName ||
          selected.mimeType != file.mimeType ||
          selected.bytes.lengthInBytes != file.sizeBytes ||
          file.contentHash == null ||
          sha256.convert(selected.bytes).toString() != file.contentHash) {
        setState(() => _message = YorksV1ProjectStrings.fileContentMismatch);
        return;
      }
      await _run(YorksV1CapabilityKeys.documentsUpload, (coordinator) async {
        await coordinator.uploadFile(
          localId: file.localId,
          bytes: selected.bytes,
          documents: ref.read(yorksV1DocumentsRepositoryProvider),
        );
        if (_current(scope, projectId)) {
          ref.invalidate(yorksV1DocumentWorkspaceProvider(projectId));
        }
      });
    } catch (_) {
      if (_current(scope, projectId)) {
        setState(() {
          _working = false;
          _message = YorksV1ProjectStrings.fileFailed;
        });
      }
    }
  }

  Future<void> _remove(YorksV1ProjectSetupFile file) async {
    if (!_canReadFile(
      file,
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      ref.read(yorksV1CurrentRoleProvider),
    )) {
      return;
    }
    await _run(
      YorksV1CapabilityKeys.documentsUpload,
      (coordinator) => coordinator.removePendingFile(file.localId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permission = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    ref.watch(yorksV1FeatureFlagsProvider);
    final state = ref.watch(yorksV1ProjectSetupCoordinatorProvider(_scope));
    final operation = state.operation;
    if (operation == null ||
        !operation.coreSucceeded ||
        operation.project?.id != widget.project.id ||
        (operation.cleanupComplete &&
            !operation.filesPending &&
            !operation.hasUnresolvedCommand)) {
      return const SizedBox.shrink();
    }
    final language = widget.language;
    final busy = _working || state.busy;
    final activationPending = _activationPending(operation);
    final canActivate = _access(YorksV1CapabilityKeys.projectsChangeState);
    final canUpload =
        widget.project.state != YorksV1ProjectLifecycle.archived &&
        _access(YorksV1CapabilityKeys.documentsUpload);
    final copy = YorksV1ProjectSetupCompletionCopy.localized(language);
    final title = operation.filesPending
        ? YorksV1ProjectStrings.projectSavedFilesPending
        : activationPending
        ? YorksV1ProjectStrings.projectCreatedDraft
        : YorksV1ProjectStrings.projectSavedHousekeeping;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('project-setup-pending-${_scope.draftId}'),
        initiallyExpanded: true,
        maintainState: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.restore_outlined, color: AppColors.muted),
        title: Text(title.active(language), style: AppTypography.labelLarge),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            '${YorksV1ProjectStrings.supportReference.active(language)}: ${operation.supportReference}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          if (activationPending) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              copy[YorksV1ProjectSetupCompletionText.activationPending],
              style: AppTypography.bodySmall,
            ),
            if (canActivate)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  key: ValueKey(
                    'project-setup-pending-activate-${_scope.draftId}',
                  ),
                  style: _actionStyle,
                  onPressed: busy
                      ? null
                      : () => _run(YorksV1CapabilityKeys.projectsChangeState, (
                          coordinator,
                        ) async {
                          await coordinator.activate();
                        }),
                  child: Text(
                    (operation.activation!.status.unresolved
                            ? YorksV1ProjectStrings.checkSavedStatus
                            : YorksV1ProjectStrings.activateProject)
                        .active(language),
                  ),
                ),
              ),
          ],
          for (final file in operation.files)
            if (_canReadFile(file, permission, role))
              Padding(
                key: ValueKey('project-setup-pending-file-${file.localId}'),
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(file.fileName, style: AppTypography.labelLarge),
                    Text(
                      _fileStatus(file).active(language),
                      style: AppTypography.bodySmall,
                    ),
                    if (canUpload &&
                        file.status != YorksV1ProjectSetupFileStatus.ready &&
                        file.status != YorksV1ProjectSetupFileStatus.removed)
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          OutlinedButton(
                            key: ValueKey(
                              'project-setup-pending-reselect-${file.localId}',
                            ),
                            style: _actionStyle,
                            onPressed: busy ? null : () => _reselect(file),
                            child: Text(
                              YorksV1ProjectStrings.fileReselect.active(
                                language,
                              ),
                            ),
                          ),
                          if (file.status ==
                                  YorksV1ProjectSetupFileStatus.selected ||
                              file.status ==
                                  YorksV1ProjectSetupFileStatus.needsReselect)
                            TextButton(
                              key: ValueKey(
                                'project-setup-pending-remove-${file.localId}',
                              ),
                              style: _actionStyle,
                              onPressed: busy ? null : () => _remove(file),
                              child: Text(
                                YorksV1ProjectStrings.removePendingFile.active(
                                  language,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          if (!operation.filesPending && !activationPending)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey(
                  'project-setup-pending-cleanup-${_scope.draftId}',
                ),
                style: _actionStyle,
                onPressed: busy || !_access(YorksV1CapabilityKeys.projectsEdit)
                    ? null
                    : () => _run(
                        YorksV1CapabilityKeys.projectsEdit,
                        (_) async {},
                      ),
                child: Text(
                  YorksV1ProjectStrings.checkSavedStatus.active(language),
                ),
              ),
            ),
          if (_message != null || state.recoveryError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                (_message ?? YorksV1ProjectStrings.localRecoveryUnavailable)
                    .active(language),
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

TranslatableString _fileStatus(
  YorksV1ProjectSetupFile file,
) => switch (file.status) {
  YorksV1ProjectSetupFileStatus.selected => YorksV1ProjectStrings.fileSelected,
  YorksV1ProjectSetupFileStatus.needsReselect =>
    YorksV1ProjectStrings.fileReselect,
  YorksV1ProjectSetupFileStatus.uploading => YorksV1ProjectStrings.fileChecking,
  YorksV1ProjectSetupFileStatus.ready => YorksV1ProjectStrings.fileReady,
  YorksV1ProjectSetupFileStatus.failed => YorksV1ProjectStrings.fileFailed,
  YorksV1ProjectSetupFileStatus.outcomeUncertain =>
    YorksV1ProjectStrings.fileChecking,
  YorksV1ProjectSetupFileStatus.removed => YorksV1ProjectStrings.fileRemoved,
};

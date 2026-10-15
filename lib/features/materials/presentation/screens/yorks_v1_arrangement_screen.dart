import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_arrangement.dart';
import '../../../../shared/models/yorks_v1_arrangement_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../../shared/widgets/yorks_v1_material_workflow_recovery_panel.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_workbook.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/models/yorks_v1_sourcing_strings.dart';
import '../../../../shared/providers/yorks_v1_sourcing_progress_provider.dart';
import '../../../../shared/widgets/yorks_v1_sourcing_progress_panel.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/permissions_provider.dart';
import '../../../../shared/providers/yorks_v1_arrangement_provider.dart';
import '../../../../shared/providers/yorks_v1_arrangement_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_material_workflow_command_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/providers/yorks_v1_procurement_progress_provider.dart';
import '../../../../shared/services/yorks_v1_procurement_unload_guard.dart';
import '../../../../shared/sync/connectivity_service.dart';
import '../../../../shared/widgets/yorks_v1_procurement_progress_panel.dart';
import '../yorks_v1_feature_action_access.dart';
import '../widgets/yorks_v1_request_information.dart';

/// One responsive view for Procurement arrangement and immutable history.
/// Server-derived action flags decide whether the current viewer can edit;
/// this screen never infers authority from a local role label.
class YorksV1ArrangementScreen extends ConsumerWidget {
  const YorksV1ArrangementScreen({
    super.key,
    required this.requestId,
    this.embedded = false,
    this.onClose,
    this.onCompleted,
  });

  final String requestId;

  /// The record detail uses a bounded desktop dialog.  Its close control lives
  /// in the dialog header rather than being stacked over the workspace, which
  /// prevents it from drifting over the arrangement title at narrow heights.
  final bool embedded;
  final VoidCallback? onClose;

  /// The record-detail modal and the compact arrangement route both leave the
  /// editor after a successful, server-confirmed save. This keeps the UI in
  /// sync with the dispatch-ready state instead of leaving a stale form open.
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final legacyArrangementReview = ref
        .watch(yorksV1FeatureFlagsProvider)
        .legacyArrangementReview;
    final workspace = ref.watch(yorksV1ArrangementWorkspaceProvider(requestId));
    final request = ref.watch(yorksV1MaterialRequestDetailProvider(requestId));
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final mobile = YorksMobileUi.isActive(context) && !embedded;
    final compactRoute =
        !embedded &&
        !mobile &&
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    final body = workspace.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ArrangementError(
        language: language,
        onRetry: () => yorksV1InvalidateArrangementWorkspace(ref, requestId),
      ),
      data: (value) {
        if ((permissionState.snapshot == null &&
                permissionState.isInitialLoading) ||
            (request.valueOrNull == null && request.isLoading)) {
          return const Center(child: CircularProgressIndicator());
        }
        final requestValue = request.valueOrNull;
        if (requestValue == null) {
          return YorksV1ProjectReadBoundary(
            allowed: false,
            language: language,
            child: const SizedBox.shrink(),
          );
        }
        final canReadRequest = yorksV1CanReadProjectRecord(
          permissionState,
          YorksV1CapabilityKeys.materialRequestsView,
          legacyAllowed: true,
          projectId: requestValue.projectId,
        );
        final arrangeAccess = yorksV1FeatureActionAccess(
          permissionState,
          YorksV1CapabilityKeys.procurementArrange,
          legacyAllowed: value.canBegin || value.canSave || value.canClarify,
          projectId: requestValue.projectId,
        );
        final content = mobile
            ? _MobileArrangementWorkspaceBody(
                workspace: value,
                request: requestValue,
                language: language,
                legacyArrangementReview: legacyArrangementReview,
                showArrange: arrangeAccess.isVisible,
                canArrange: arrangeAccess.canWrite,
                onCompleted: onCompleted,
              )
            : _ArrangementWorkspaceBody(
                workspace: value,
                request: requestValue,
                language: language,
                legacyArrangementReview: legacyArrangementReview,
                showArrange: arrangeAccess.isVisible,
                canArrange: arrangeAccess.canWrite,
                showPageHeader: !compactRoute && !embedded,
                directEditor: embedded || compactRoute,
                onCompleted: onCompleted,
                onClose: onClose,
              );
        return YorksV1ProjectReadBoundary(
          allowed: canReadRequest,
          language: language,
          child: Column(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                padding: const EdgeInsetsDirectional.only(
                  end: AppSpacing.md,
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ArrangementTiming(
                        workspace: value,
                        language: language,
                      ),
                    ),
                    YorksV1RequestInformationButton(
                      request: requestValue,
                      language: language,
                    ),
                  ],
                ),
              ),
              YorksV1MaterialWorkflowRecoveryPanel(
                requestId: requestId,
                language: language,
                arrangementIds: [
                  for (final item in value.arrangements) item.id,
                ],
                onConfirmed: () {
                  yorksV1InvalidateArrangementWorkspace(ref, requestId);
                  yorksV1InvalidateMaterialRequestDetail(ref, requestId);
                  ref.invalidate(yorksV1MaterialRequestListProvider);
                },
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
    if (mobile) {
      return Scaffold(
        backgroundColor: AppColors.mobileSurface,
        body: Column(
          children: [
            YorksMobileAppBar(
              title:
                  workspace.valueOrNull?.requestNumber ??
                  YorksV1ArrangementStrings.arrangement.active(language),
              leading: YorksMobileIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              trailing: YorksMobileIconButton(
                icon: Icons.menu_rounded,
                tooltip: YorksV1ArrangementStrings.arrangement.active(language),
                onPressed: () =>
                    yorksV1InvalidateArrangementWorkspace(ref, requestId),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: compactRoute
          ? AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              title: _ActiveText(
                copy: YorksV1ArrangementStrings.arrangeMaterialRequest,
                language: language,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: YorksV1ArrangementStrings.arrangement.primary,
                  onPressed: () =>
                      yorksV1InvalidateArrangementWorkspace(ref, requestId),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      body: embedded
          ? Column(
              children: [
                _EmbeddedArrangementHeader(
                  language: language,
                  requestNumber:
                      workspace.valueOrNull?.requestNumber ?? requestId,
                  onClose: onClose,
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}

class _EmbeddedArrangementHeader extends StatelessWidget {
  const _EmbeddedArrangementHeader({
    required this.language,
    required this.requestNumber,
    this.onClose,
  });

  final AppLanguage language;
  final String requestNumber;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
    ),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ActiveText(
                    copy: YorksV1ArrangementStrings.arrangeMaterialRequest,
                    language: language,
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const _ArrangementStageChip(),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: requestNumber,
                      style: const TextStyle(
                        color: AppColors.inkSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' · ${YorksV1ArrangementStrings.arrangeMaterialRequestDescription.active(language)}',
                    ),
                  ],
                ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    ),
  );
}

class _ArrangementStageChip extends StatelessWidget {
  const _ArrangementStageChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      border: Border.all(color: AppColors.blue.withValues(alpha: .18)),
    ),
    child: Text(
      YorksV1MaterialRequestStrings.stageOfSeven(3).primary,
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.blue,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MobileArrangementWorkspaceBody extends ConsumerWidget {
  const _MobileArrangementWorkspaceBody({
    required this.workspace,
    required this.request,
    required this.language,
    required this.legacyArrangementReview,
    required this.showArrange,
    required this.canArrange,
    this.onCompleted,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool legacyArrangementReview;
  final bool showArrange;
  final bool canArrange;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final working = workspace.workingArrangement;
    if (working != null &&
        (workspace.canSave || workspace.canClarify) &&
        showArrange) {
      final inventory = workspace.canSave
          ? ref.watch(yorksV1ArrangementInventoryProvider)
          : const AsyncData<List<YorksV1InventoryItem>>([]);
      return inventory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ArrangementError(
          language: language,
          onRetry: () => ref.invalidate(yorksV1ArrangementInventoryProvider),
        ),
        data: (items) => _ArrangementEditor(
          key: ValueKey(working.id),
          workspace: workspace,
          request: request,
          arrangement: working,
          inventoryItems: items,
          language: language,
          mobileFlow: true,
          enabled: canArrange && workspace.canSave,
          canClarify: canArrange && (workspace.canClarify || workspace.canSave),
          onCompleted: onCompleted,
        ),
      );
    }
    final current = workspace.currentArrangement;
    if (current != null && workspace.canDecide && legacyArrangementReview) {
      return _MobileArrangementDecisionView(
        workspace: workspace,
        arrangement: current,
        language: language,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('mobile-arrangement-read-only'),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workspace.canBegin && showArrange && working == null)
            _BeginArrangementAction(
              workspace: workspace,
              language: language,
              enabled: canArrange,
            ),
          if (current != null) ...[
            YorksMobilePageTitle(
              eyebrow: YorksV1ArrangementStrings.arrangementReview.active(
                language,
              ),
              title: YorksV1ArrangementStrings.arrangement.active(language),
              description: YorksV1ArrangementStrings.reviewSummary.active(
                language,
              ),
            ),
            const SizedBox(height: 16),
            _ArrangementReadOnly(arrangement: current, language: language),
          ],
          if (workspace.arrangements.isEmpty && !workspace.canBegin)
            YorksMobileCard(
              child: _ActiveText(
                copy: YorksV1ArrangementStrings.noArrangement,
                language: language,
                center: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrangementWorkspaceBody extends ConsumerWidget {
  const _ArrangementWorkspaceBody({
    required this.workspace,
    required this.request,
    required this.language,
    required this.legacyArrangementReview,
    required this.showArrange,
    required this.canArrange,
    required this.showPageHeader,
    required this.directEditor,
    this.onCompleted,
    this.onClose,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final bool legacyArrangementReview;
  final bool showArrange;
  final bool canArrange;
  final bool showPageHeader;
  final bool directEditor;
  final VoidCallback? onCompleted;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final working = workspace.workingArrangement;
    final inventory = workspace.canSave && showArrange
        ? ref.watch(yorksV1ArrangementInventoryProvider)
        : const AsyncData<List<YorksV1InventoryItem>>([]);
    if (working != null &&
        (workspace.canSave || workspace.canClarify) &&
        showArrange) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!directEditor) ...[
                Text(
                  '${YorksV1ArrangementStrings.arrangeMaterialRequest.active(language)} · ${request.requestNumber}',
                  style: AppTypography.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Expanded(
                child: inventory.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _ArrangementError(
                    language: language,
                    onRetry: () =>
                        ref.invalidate(yorksV1ArrangementInventoryProvider),
                  ),
                  data: (items) => _ArrangementEditor(
                    workspace: workspace,
                    request: request,
                    arrangement: working,
                    inventoryItems: items,
                    language: language,
                    enabled: canArrange && workspace.canSave,
                    canClarify:
                        canArrange &&
                        (workspace.canClarify || workspace.canSave),
                    onCompleted: onCompleted,
                    onClose: onClose,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.pageMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showPageHeader) ...[
                  YorksR35PageHeader(
                    eyebrow: YorksV1ShellStrings.operationalWorkspace.primary,
                    title: YorksV1ArrangementStrings.arrangement.primary,
                    description:
                        YorksV1ArrangementStrings.reviewSummary.primary,
                    actions: [
                      SizedBox(
                        height: AppSpacing.controlHeight,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              yorksV1InvalidateArrangementWorkspace(
                                ref,
                                workspace.requestId,
                              ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            YorksV1ArrangementStrings.arrangement.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (!directEditor) ...[
                  _WorkspaceHeader(workspace: workspace),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (workspace.canBegin && showArrange && working == null)
                  _BeginArrangementAction(
                    workspace: workspace,
                    language: language,
                    enabled: canArrange,
                  ),
                if (working != null &&
                    (workspace.canSave || workspace.canClarify) &&
                    showArrange) ...[
                  _ArrangementEditorSurface(
                    directEditor: directEditor,
                    child: inventory.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: LinearProgressIndicator(),
                      ),
                      error: (_, _) => _ArrangementError(
                        language: language,
                        onRetry: () =>
                            ref.invalidate(yorksV1ArrangementInventoryProvider),
                      ),
                      data: (items) => _ArrangementEditor(
                        workspace: workspace,
                        request: request,
                        arrangement: working,
                        inventoryItems: items,
                        language: language,
                        enabled: canArrange && workspace.canSave,
                        canClarify:
                            canArrange &&
                            (workspace.canClarify || workspace.canSave),
                        onCompleted: onCompleted,
                        onClose: onClose,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (workspace.currentArrangement != null) ...[
                  NexusSectionCard(
                    title: YorksV1ArrangementStrings.reviewSummary.primary,
                    child: _ArrangementReadOnly(
                      arrangement: workspace.currentArrangement!,
                      language: language,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (workspace.canDecide && legacyArrangementReview)
                    _DecisionActions(
                      workspace: workspace,
                      arrangement: workspace.currentArrangement!,
                      language: language,
                    ),
                ],
                if (workspace.arrangements.isEmpty && !workspace.canBegin)
                  NexusSectionCard(
                    child: _ActiveText(
                      copy: YorksV1ArrangementStrings.noArrangement,
                      language: language,
                      center: true,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                if (workspace.arrangements.length > 1) ...[
                  const SizedBox(height: AppSpacing.lg),
                  NexusSectionCard(
                    title: YorksV1ArrangementStrings.arrangementHistory.primary,
                    child: Column(
                      children: [
                        for (final arrangement in workspace.arrangements.skip(
                          1,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: _ArrangementHistoryRow(
                              arrangement: arrangement,
                              language: language,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.workspace});

  final YorksV1ArrangementWorkspace workspace;

  @override
  Widget build(BuildContext context) => NexusSectionCard(
    child: Wrap(
      spacing: AppSpacing.xxl,
      runSpacing: AppSpacing.md,
      children: [
        _Meta(
          label: YorksV1ArrangementStrings.version.primary,
          value: workspace.currentArrangement == null
              ? workspace.requestRecordVersion.toString()
              : workspace.currentArrangement!.version.toString(),
        ),
        _Meta(
          label: YorksV1ArrangementStrings.arrangement.primary,
          value: workspace.requestNumber ?? '',
        ),
        if (workspace.currentArrangement != null)
          _Meta(
            label: YorksV1ArrangementStrings.decision.primary,
            value: yorksV1ArrangementStatusCopy(
              workspace.currentArrangement!.status,
            ).primary,
          ),
      ],
    ),
  );
}

class _ArrangementEditorSurface extends StatelessWidget {
  const _ArrangementEditorSurface({
    required this.directEditor,
    required this.child,
  });

  final bool directEditor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!directEditor) {
      return NexusSectionCard(
        title: YorksV1ArrangementStrings.arrangement.primary,
        child: child,
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ClarificationReviewBanner extends StatelessWidget {
  const _ClarificationReviewBanner({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('procurement-clarification-review-required'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      border: Border.all(color: AppColors.warning.withValues(alpha: .32)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.approval_outlined, color: AppColors.warning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1ArrangementStrings.clarificationReviewTitle.active(
                  language,
                ),
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                YorksV1ArrangementStrings.clarificationReviewMessage.active(
                  language,
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BeginArrangementAction extends ConsumerStatefulWidget {
  const _BeginArrangementAction({
    required this.workspace,
    required this.language,
    required this.enabled,
  });

  final YorksV1ArrangementWorkspace workspace;
  final AppLanguage language;
  final bool enabled;

  @override
  ConsumerState<_BeginArrangementAction> createState() =>
      _BeginArrangementActionState();
}

class _BeginArrangementActionState
    extends ConsumerState<_BeginArrangementAction> {
  bool _busy = false;
  late String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4();
  }

  @override
  Widget build(BuildContext context) => NexusSectionCard(
    child: PrimaryButton(
      label: YorksV1ArrangementStrings.startArrangement.primary,
      icon: Icons.playlist_add_check_rounded,
      isLoading: _busy,
      onPressed: _busy || !widget.enabled ? null : _begin,
    ),
  );

  Future<void> _begin() async {
    if (!widget.enabled) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .beginArrangement(
            YorksV1BeginArrangementInput(
              requestId: widget.workspace.requestId,
              expectedRequestVersion: widget.workspace.requestRecordVersion,
              idempotencyKey: _idempotencyKey,
            ),
          );
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      _idempotencyKey = const Uuid().v4();
    } on YorksV1CommittedViewUnavailable {
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
    } on YorksV1CommandOutcomeUnknown {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.commandUnknown.active(
            widget.language,
          ),
          tone: YorksAppToastTone.information,
        );
      }
    } on YorksV1DomainException catch (error) {
      if (mounted) _showFailure(context, error);
      return;
    } catch (_) {
      if (mounted) _showFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ArrangementEditor extends ConsumerStatefulWidget {
  const _ArrangementEditor({
    super.key,
    required this.workspace,
    required this.request,
    required this.arrangement,
    required this.inventoryItems,
    required this.language,
    required this.enabled,
    required this.canClarify,
    this.mobileFlow = false,
    this.onCompleted,
    this.onClose,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1MaterialRequest request;
  final YorksV1ProcurementArrangement arrangement;
  final List<YorksV1InventoryItem> inventoryItems;
  final AppLanguage language;
  final bool enabled;
  final bool canClarify;
  final bool mobileFlow;
  final VoidCallback? onCompleted;
  final VoidCallback? onClose;

  @override
  ConsumerState<_ArrangementEditor> createState() => _ArrangementEditorState();
}

class _ArrangementEditorState extends ConsumerState<_ArrangementEditor> {
  late YorksV1ProcurementArrangement _arrangement;
  late int _requestRecordVersion;
  late Map<String, _EditableArrangementLine> _lines;
  late List<YorksV1InventoryItem> _inventoryItems;
  late bool _canSave;
  late bool _canClarify;
  late bool _clarificationReviewRequired;
  final Map<String, TextEditingController> _arrangedQuantities = {};
  final Map<String, TextEditingController> _unitCosts = {};
  final Map<String, TextEditingController> _suppliers = {};
  final Map<String, TextEditingController> _reasons = {};
  final Map<String, GlobalKey> _lineKeys = {};
  Map<String, List<String>> _validationIssues = const {};
  late final TextEditingController _procurementNote;
  late String _saveIdempotencyKey;
  bool _busy = false;

  final _unloadGuard = createYorksV1ProcurementUnloadGuard();
  late YorksV1ProcurementProgressController _progress;
  late YorksV1ProcurementExitGuard _exitGuard;
  bool _syncingProgress = false;
  bool _allowExit = false;
  bool _reviewOpen = false;
  bool _progressReady = false;
  bool _recoveryCompletionStarted = false;
  final _incompleteRestoredChoices = <String>{};

  YorksV1ProcurementProgressScope get _progressScope =>
      YorksV1ProcurementProgressScope(
        requestId: widget.workspace.requestId,
        editorKind: YorksV1ProcurementEditorKind.arrangement,
        arrangementId: _arrangement.id,
      );

  YorksV1ProcurementProgressDraft _captureDraft() =>
      YorksV1ProcurementProgressDraft(
        requestId: widget.workspace.requestId,
        editorKind: YorksV1ProcurementEditorKind.arrangement,
        arrangementId: _arrangement.id,
        baseRequestVersion: _requestRecordVersion,
        baseArrangementVersion: _arrangement.recordVersion,
        inputs: {
          'note': _procurementNote.text,
          'lines': [
            for (final line in _lines.values)
              {
                'arrangement_line_id': line.arrangementLineId,
                'decision': line.decision?.wireValue ?? '',
                'source_kind': line.source.wireValue,
                'inventory_item_id': line.inventoryItemId,
                'arranged_qty':
                    _arrangedQuantities[line.arrangementLineId]!.text,
                'reason': _reasons[line.arrangementLineId]!.text,
                'external_supplier': _suppliers[line.arrangementLineId]!.text,
                'external_ready': line.externalSourceReady,
                'expected_available_date': line.externalExpectedDate ?? '',
                'external_reference': line.externalReference ?? '',
              },
          ],
        },
        commercialInputs: ref.read(canManageCommercialsProvider)
            ? {
                'lines': [
                  for (final line in _lines.values)
                    {
                      'arrangement_line_id': line.arrangementLineId,
                      'unit_cost': _unitCosts[line.arrangementLineId]!.text,
                    },
                ],
              }
            : null,
      );

  void _editorChanged() {
    if (!_progressReady || _syncingProgress) return;
    _progress.update(_captureDraft());
  }

  void _progressChanged() {
    if (!mounted) return;
    if (_progress.state.outcome?.isConfirmed == true &&
        !_recoveryCompletionStarted) {
      unawaited(
        Future<void>.microtask(() async {
          if (mounted) await _completeRecovered();
        }),
      );
    }
    _unloadGuard.setActive(
      _progress.state.isDirty || _progress.state.isPending,
    );
    final current = _progress.state.current;
    if (current != null &&
        !_syncingProgress &&
        current.fingerprint != _captureDraft().fingerprint) {
      _syncingProgress = true;
      final costs = {
        for (final raw in (current.commercialInputs?['lines'] as List? ?? []))
          (raw as Map)['arrangement_line_id']:
              raw['unit_cost']?.toString() ?? '',
      };
      for (final raw in current.inputs['lines'] as List) {
        final row = raw as Map;
        final id = row['arrangement_line_id'] as String;
        final line = _lines[id];
        if (line == null) continue;
        final source = YorksV1ArrangementSource.values
            .where((value) => value.wireValue == row['source_kind'])
            .firstOrNull;
        if (source == null) {
          _incompleteRestoredChoices.add(id);
        }
        _lines[id] = line.copyWith(
          arrangedQuantity: row['arranged_qty']?.toString() ?? '',
          source: source ?? line.source,
          inventoryItemId: row['inventory_item_id'] as String?,
          externalSourceReady: row['external_ready'] == true,
          externalExpectedDate: _trimmedOrNull(
            row['expected_available_date']?.toString() ?? '',
          ),
          externalReference: _trimmedOrNull(
            row['external_reference']?.toString() ?? '',
          ),
        );
        _arrangedQuantities[id]!.text = row['arranged_qty']?.toString() ?? '';
        _reasons[id]!.text = row['reason']?.toString() ?? '';
        _suppliers[id]!.text = row['external_supplier']?.toString() ?? '';
        _unitCosts[id]!.text = costs[id] ?? '';
      }
      _procurementNote.text = current.inputs['note']?.toString() ?? '';
      _syncingProgress = false;
    }
    setState(() {});
  }

  Future<bool> _canLeave() async {
    if (_allowExit) return true;
    if (_busy) return false;
    _editorChanged();
    return confirmYorksV1ProcurementLeave(
      context,
      controller: _progress,
      language: widget.language,
      isOnline: ref.read(connectivityProvider).isOnline,
    );
  }

  Future<bool> _beforeNavigation() async {
    if (!await _canLeave() || !mounted) return false;
    setState(() => _allowExit = true);
    return true;
  }

  Future<void> _saveProgress() async {
    _editorChanged();
    await _progress.saveProgress();
  }

  Widget _progressPanel({bool mobile = false}) =>
      YorksV1ProcurementProgressPanel(
        controller: _progress,
        language: widget.language,
        onSaveProgress: mobile ? _saveProgress : null,
        onRetryPending: _retryPending,
        onReload: _reloadWorkspace,
        onConfirmed: _completeRecovered,
        onCommandAbandoned: _releaseAbandoned,
      );

  bool get _scheduled =>
      widget.workspace.timing == YorksV1MaterialRequestTiming.scheduled;
  YorksV1SourcingScope get _sourcingScope =>
      (requestId: widget.workspace.requestId, arrangementId: _arrangement.id);

  Widget _sourcingPanel(bool editable) => YorksV1SourcingProgressPanel(
    scope: _sourcingScope,
    language: widget.language,
    itemLabels: {
      for (final line in _arrangement.lines)
        line.requestLineId: '${line.description} · ${line.unit}',
    },
    onUpdate: editable && !_busy ? _shareSourcingProgress : null,
  );

  bool _sharingPreview = false;
  Future<void> _shareSourcingProgress() async {
    if (_sharingPreview) return;
    _sharingPreview = true;
    try {
      await _prepareSourcingProgress();
    } finally {
      _sharingPreview = false;
    }
  }

  Future<void> _prepareSourcingProgress() async {
    if (_busy || !_canSave || !_progress.state.canEdit) return;
    _editorChanged();
    final lines = <YorksV1SourcingLine>[];
    for (final item in _arrangement.lines) {
      final draft = _lines[item.id]!;
      final raw = _arrangedQuantities[item.id]!.text.trim();
      final quantity = YorksV1DecimalQuantity.tryParse(raw.isEmpty ? '0' : raw);
      final requested = YorksV1DecimalQuantity.tryParse(
        item.requestedQuantity,
      )!;
      final date = draft.externalExpectedDate;
      if (quantity == null ||
          quantity.isNegative ||
          quantity.compareTo(requested) > 0 ||
          (draft.source == YorksV1ArrangementSource.externalSupplier &&
              date != null &&
              !yorksV1SourcingDateIsValid(date)) ||
          (quantity.isPositive &&
              draft.source == YorksV1ArrangementSource.warehouse &&
              draft.inventoryItemId == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              YorksV1SourcingStrings.invalid.active(widget.language),
            ),
          ),
        );
        return;
      }
      final ready =
          draft.source == YorksV1ArrangementSource.externalSupplier &&
              !draft.externalSourceReady
          ? YorksV1DecimalQuantity.zero
          : quantity;
      lines.add(
        YorksV1SourcingLine(
          requestLineId: item.requestLineId,
          readyQuantity: ready.canonicalText,
          requestedQuantity: requested.canonicalText,
          sourceKind: draft.source.wireValue,
          inventoryItemId: draft.source == YorksV1ArrangementSource.warehouse
              ? draft.inventoryItemId
              : null,
          expectedDate:
              draft.source == YorksV1ArrangementSource.externalSupplier
              ? date
              : null,
        ),
      );
    }
    var dialogClosed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1SourcingStrings.confirm.active(widget.language)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  YorksV1SourcingStrings.explanation.active(widget.language),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final line in lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _arrangement.lines
                          .firstWhere(
                            (item) => item.requestLineId == line.requestLineId,
                          )
                          .description,
                    ),
                    subtitle: Text(
                      '${YorksV1SourcingStrings.ready.active(widget.language)} ${line.readyQuantity} / ${line.requestedQuantity} ${_arrangement.lines.firstWhere((item) => item.requestLineId == line.requestLineId).unit}${line.expectedDate == null ? '' : ' · ${YorksV1SourcingStrings.expected.active(widget.language)} ${line.expectedDate}'}',
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  YorksV1SourcingStrings.externalWaiting.active(
                    widget.language,
                  ),
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (dialogClosed) return;
              dialogClosed = true;
              Navigator.pop(dialogContext, false);
            },
            child: Text(AppStrings.cancel.active(widget.language)),
          ),
          FilledButton(
            onPressed: () {
              if (dialogClosed) return;
              dialogClosed = true;
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              YorksV1SourcingStrings.updateTeam.active(widget.language),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_progress.state.canEdit) return;
    setState(() => _busy = true);
    final saved = await ref
        .read(yorksV1SourcingProgressProvider(_sourcingScope).notifier)
        .save(
          requestVersion: _requestRecordVersion,
          arrangementVersion: _arrangement.recordVersion,
          lines: lines,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) {
      ref.invalidate(
        yorksV1SourcingProgressProvider((
          requestId: widget.workspace.requestId,
          arrangementId: null,
        )),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(YorksV1SourcingStrings.failed.active(widget.language)),
        ),
      );
    }
  }

  String _query = '';
  YorksV1ArrangementDecision? _decisionFilter;
  String? _focusLineId;
  final _search = TextEditingController();
  final _tableHorizontal = ScrollController();

  List<YorksV1ArrangementLine> get _visibleLines => _arrangement.lines
      .where((line) {
        if (_focusLineId != null) return line.id == _focusLineId;
        if (_decisionFilter != null &&
            _lines[line.id]?.decision != _decisionFilter) {
          return false;
        }
        return '${line.description} ${line.brandOrigin ?? ''} ${line.modelReference ?? ''}'
            .toLowerCase()
            .contains(_query);
      })
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _arrangement = widget.arrangement;
    _requestRecordVersion = widget.workspace.requestRecordVersion;
    _lines = {
      for (final line in _arrangement.lines)
        line.id: _EditableArrangementLine.fromLine(line, widget.inventoryItems),
    };
    _inventoryItems = _inventoryItemsForRequest(widget.inventoryItems);
    _canSave = widget.enabled;
    _canClarify = widget.canClarify;
    _clarificationReviewRequired = widget.workspace.clarificationReviewRequired;
    _initializeLineKeys();
    _initializeLineControllers();
    _procurementNote = TextEditingController(
      text: widget.arrangement.procurementNote ?? '',
    );
    _saveIdempotencyKey = const Uuid().v4();
    _progress = ref.read(
      yorksV1ProcurementProgressControllerProvider(_progressScope),
    );
    _progress.addListener(_progressChanged);
    _progressReady = true;
    _procurementNote.addListener(_editorChanged);
    _exitGuard = ref.read(yorksV1ProcurementExitGuardProvider);
    _exitGuard.check = _canLeave;
    _exitGuard.beforeNavigation = _beforeNavigation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_progress.initialize(_captureDraft()));
    });
  }

  @override
  void didUpdateWidget(covariant _ArrangementEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _canSave = widget.enabled;
    _canClarify = widget.canClarify;
    _clarificationReviewRequired = widget.workspace.clarificationReviewRequired;
    if (oldWidget.arrangement.id == widget.arrangement.id) {
      final snapshot = _captureDraft().toJson();
      snapshot['base_request_version'] = widget.workspace.requestRecordVersion;
      snapshot['base_arrangement_version'] = widget.arrangement.recordVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _progress.observeLiveBase(
            YorksV1ProcurementProgressDraft.fromJson(snapshot),
          );
        }
      });
    }
    if (oldWidget.arrangement.id != widget.arrangement.id) {
      _arrangement = widget.arrangement;
      _requestRecordVersion = widget.workspace.requestRecordVersion;
      _inventoryItems = _inventoryItemsForRequest(widget.inventoryItems);
      _lines = {
        for (final line in _arrangement.lines)
          line.id: _EditableArrangementLine.fromLine(
            line,
            widget.inventoryItems,
          ),
      };
      _disposeLineControllers();
      _initializeLineKeys();
      _initializeLineControllers();
      _procurementNote.text = widget.arrangement.procurementNote ?? '';
      _saveIdempotencyKey = const Uuid().v4();
    }
  }

  @override
  void dispose() {
    _unloadGuard.dispose();
    _progress.removeListener(_progressChanged);
    unawaited(_progress.flushRecovery());
    if (_exitGuard.check == _canLeave) _exitGuard.check = null;
    if (_exitGuard.beforeNavigation == _beforeNavigation) {
      _exitGuard.beforeNavigation = null;
    }
    _search.dispose();
    _tableHorizontal.dispose();
    _disposeLineControllers();
    _procurementNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveProgress = ref.watch(
      yorksV1ProcurementProgressControllerProvider(_progressScope),
    );
    if (!identical(liveProgress, _progress)) {
      _progress.removeListener(_progressChanged);
      _progress = liveProgress;
      _progress.addListener(_progressChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_progress.initialize(_captureDraft()));
      });
    }
    final editable = _canSave && _progress.state.canEdit;
    final canManageCommercials = ref.watch(canManageCommercialsProvider);
    if (!canManageCommercials) {
      _syncingProgress = true;
      for (final controller in _unitCosts.values) {
        if (controller.text.isNotEmpty) controller.clear();
      }
      _syncingProgress = false;
    }

    if (widget.mobileFlow) {
      return PopScope(
        canPop:
            _allowExit ||
            (!_busy && !_progress.state.isDirty && !_progress.state.isPending),
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop && await _beforeNavigation() && context.mounted) {
            Navigator.of(context).maybePop();
          }
        },
        child: _MobileArrangementFlow(
          progressPanel: Column(
            children: [
              _progressPanel(mobile: true),
              if (_scheduled) _sourcingPanel(editable),
            ],
          ),
          workspace: widget.workspace,
          arrangement: _arrangement,
          inventoryItems: _inventoryItems,
          language: widget.language,
          lines: _lines,
          arrangedQuantities: _arrangedQuantities,
          unitCosts: _unitCosts,
          canManageCommercials: canManageCommercials,
          suppliers: _suppliers,
          reasons: _reasons,
          validationIssues: _validationIssues,
          procurementNote: _procurementNote,
          busy: _busy,
          enabled: editable,
          canClarify: _canClarify,
          clarificationReviewRequired: _clarificationReviewRequired,
          onChanged: _replace,
          onCreateInventoryItem: _createInventoryItem,
          onEditItem: _editItem,
          onSave: _save,
        ),
      );
    }
    return PopScope(
      canPop:
          _allowExit ||
          (!_busy && !_progress.state.isDirty && !_progress.state.isPending),
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _beforeNavigation() && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveProgress,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              _saveProgress,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _progressPanel(),
            const SizedBox(height: AppSpacing.sm),
            if (_scheduled) ...[
              _sourcingPanel(editable),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_clarificationReviewRequired) ...[
              _ClarificationReviewBanner(language: widget.language),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: YorksV1ArrangementStrings.searchItems.active(
                        widget.language,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty && _focusLineId == null
                          ? null
                          : IconButton(
                              tooltip: AppStrings.cancel.primary,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _query = '';
                                _focusLineId = null;
                                _search.clear();
                              }),
                            ),
                    ),
                    onChanged: (value) => setState(() {
                      _query = value.trim().toLowerCase();
                      _focusLineId = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<YorksV1ArrangementDecision?>(
                    initialValue: _decisionFilter,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          YorksV1ArrangementStrings.allItems.active(
                            widget.language,
                          ),
                        ),
                      ),
                      for (final decision in YorksV1ArrangementDecision.values)
                        DropdownMenuItem(
                          value: decision,
                          child: Text(
                            yorksV1ArrangementDecisionCopy(
                              decision,
                            ).active(widget.language),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _decisionFilter = value;
                      _focusLineId = null;
                    }),
                  ),
                ),
              ],
            ),
            if (_validationIssues.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _ArrangementValidationSummary(
                issues: _validationIssues,
                lines: _arrangement.lines,
                language: widget.language,
                onLineTap: _revealLine,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 980
                    ? _DesktopArrangementEditor(
                        horizontal: _tableHorizontal,
                        lines: _visibleLines,
                        drafts: _lines,
                        arrangedQuantities: _arrangedQuantities,
                        unitCosts: _unitCosts,
                        canManageCommercials: canManageCommercials,
                        suppliers: _suppliers,
                        reasons: _reasons,
                        inventoryItems: _inventoryItems,
                        enabled: editable && !_busy,
                        canClarify:
                            _canClarify && !_busy && _progress.state.canEdit,
                        onChanged: _replace,
                        onCreateInventoryItem: _createInventoryItem,
                        onEditItem: _editItem,
                        validationIssues: _validationIssues,
                        lineKeys: _lineKeys,
                        language: widget.language,
                        readinessRequired:
                            (widget.workspace.externalSourceReadinessRequired ||
                            widget.workspace.timing ==
                                YorksV1MaterialRequestTiming.scheduled),
                      )
                    : ListView(
                        children: [
                          for (final line in _visibleLines) ...[
                            _MobileArrangementEditor(
                              line: line,
                              draft: _lines[line.id]!,
                              arrangedQuantity: _arrangedQuantities[line.id]!,
                              unitCost: _unitCosts[line.id]!,
                              canManageCommercials: canManageCommercials,
                              supplier: _suppliers[line.id]!,
                              reason: _reasons[line.id]!,
                              inventoryItems: _inventoryItems,
                              enabled: editable && !_busy,
                              canClarify:
                                  _canClarify &&
                                  !_busy &&
                                  _progress.state.canEdit,
                              onChanged: _replace,
                              onCreateInventoryItem: _createInventoryItem,
                              onEditItem: _editItem,
                              validationMessages:
                                  _validationIssues[line.id] ?? const [],
                              language: widget.language,
                              readinessRequired:
                                  (widget
                                      .workspace
                                      .externalSourceReadinessRequired ||
                                  _scheduled),
                              key: _lineKeys[line.id],
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.notes_rounded),
                    label: Text(
                      YorksV1ArrangementStrings.procurementNote.active(
                        widget.language,
                      ),
                    ),
                    onPressed: _busy ? null : _editNote,
                  ),
                  if (widget.onClose != null)
                    SecondaryButton(
                      label: AppStrings.cancel.primary,
                      isExpanded: false,
                      onPressed: _busy ? null : widget.onClose,
                    ),
                  SecondaryButton(
                    label: YorksV1ProcurementProgressStrings.saveProgress
                        .active(widget.language),
                    icon: Icons.save_outlined,
                    isExpanded: false,
                    onPressed: _busy || !editable ? null : _saveProgress,
                  ),
                  PrimaryButton(
                    label: YorksV1ArrangementStrings.reviewArrangement.active(
                      widget.language,
                    ),
                    icon: Icons.send_rounded,
                    isExpanded: false,
                    isLoading: _busy,
                    onPressed: _busy || !editable ? null : _review,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _replace(_EditableArrangementLine value) {
    if (!_canSave) return;
    _incompleteRestoredChoices.remove(value.arrangementLineId);
    setState(() {
      _lines = {..._lines, value.arrangementLineId: value};
      _validationIssues = {..._validationIssues}
        ..remove(value.arrangementLineId);
    });
    _editorChanged();
  }

  Future<void> _createInventoryItem(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  ) async {
    if (_busy || !_canSave) return;
    YorksV1InventoryWorkspace inventory;
    try {
      inventory = await ref
          .read(yorksV1LogisticsRepositoryProvider)
          .getInventory();
    } on YorksV1DomainException catch (error) {
      if (mounted) _showFailure(context, error);
      return;
    } catch (_) {
      if (mounted) _showFailure(context);
      return;
    }
    if (!mounted) return;

    final created = await showDialog<YorksV1LogisticsInventoryItem>(
      context: context,
      builder: (_) =>
          _ArrangementInventoryItemCreator(line: line, inventory: inventory),
    );
    if (!mounted || created == null) return;

    final item = YorksV1InventoryItem(
      id: created.id,
      itemCode: created.itemCode,
      description: created.description,
      unit: created.unit,
      onHandQuantity: created.onHandQuantity,
      reservedQuantity: created.reservedQuantity,
      availableQuantity: created.availableQuantity,
      recordVersion: created.recordVersion,
      brandOrigin: created.brandOrigin,
      locationBin: created.locationBin,
    );
    setState(() {
      _inventoryItems = [
        for (final current in _inventoryItems)
          if (current.id != item.id) current,
        item,
      ];
    });

    final available = YorksV1DecimalQuantity.tryParse(
      created.availableQuantity,
    );
    if (available?.isPositive == true) {
      _replace(
        draft.copyWith(
          source: YorksV1ArrangementSource.warehouse,
          inventoryItemId: item.id,
        ),
      );
    }
    YorksAppToast.show(
      context,
      title: YorksV1ArrangementStrings.inventoryItemCreated.active(
        widget.language,
      ),
      message: available?.isPositive == true
          ? '${item.description} · ${yorksV1DisplayQuantity(item.availableQuantity)} ${item.unit}'
          : YorksV1ArrangementStrings.createdItemHasNoAvailableStock.active(
              widget.language,
            ),
      tone: available?.isPositive == true
          ? YorksAppToastTone.success
          : YorksAppToastTone.information,
    );
  }

  Future<void> _editItem(YorksV1ArrangementLine line) async {
    if (_busy || !_canClarify || _arrangement.savedAt != null) return;
    await _showProcurementItemEditor(
      context: context,
      request: widget.request,
      line: line,
      language: widget.language,
      onSave: (result) => _saveItemClarification(line, result),
    );
  }

  Future<String?> _saveItemClarification(
    YorksV1ArrangementLine line,
    _ProcurementItemEditResult result,
  ) async {
    if (!mounted) return YorksV1ArrangementStrings.clarificationFailed.primary;
    setState(() => _busy = true);
    try {
      final workspace = await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .updateProcurementMaterialItem(
            YorksV1UpdateProcurementMaterialItemInput(
              requestId: widget.workspace.requestId,
              requestLineId: line.requestLineId,
              expectedRequestVersion: _requestRecordVersion,
              itemDescription: result.description,
              modelReference: result.modelReference,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      final updated = workspace.workingArrangement;
      if (updated == null || updated.id != _arrangement.id) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      if (!mounted) return null;
      setState(() {
        _arrangement = updated;
        _requestRecordVersion = workspace.requestRecordVersion;
        _canSave = workspace.canSave;
        _canClarify = workspace.canClarify;
        _clarificationReviewRequired = workspace.clarificationReviewRequired;
      });
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      YorksAppToast.show(
        context,
        title: YorksV1ArrangementStrings.clarificationSaved.active(
          widget.language,
        ),
        message: YorksV1ArrangementStrings.clarificationSavedMessage.active(
          widget.language,
        ),
        tone: YorksAppToastTone.success,
      );
      return null;
    } on YorksV1DomainException catch (error) {
      return YorksV1MaterialRequestStrings.commandFailure(
        error.code,
      ).active(widget.language);
    } catch (_) {
      return YorksV1ArrangementStrings.clarificationFailed.active(
        widget.language,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadWorkspace() async {
    final workspace = await ref.refresh(
      yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId).future,
    );
    if (!mounted || workspace.workingArrangement == null) return;
    _syncingProgress = true;
    _arrangement = workspace.workingArrangement!;
    _requestRecordVersion = workspace.requestRecordVersion;
    _lines = {
      for (final line in _arrangement.lines)
        line.id: _EditableArrangementLine.fromLine(line, _inventoryItems),
    };
    _disposeLineControllers();
    _initializeLineKeys();
    _initializeLineControllers();
    _procurementNote.text = _arrangement.procurementNote ?? '';
    _syncingProgress = false;
    await _progress.reload(_captureDraft());
    if (mounted) setState(() {});
  }

  Future<void> _editNote() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          YorksV1ArrangementStrings.procurementNote.active(widget.language),
        ),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: _procurementNote,
            enabled: _canSave && _progress.state.canEdit,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: YorksV1ArrangementStrings.procurementNoteHint.active(
                widget.language,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.cancel.primary),
          ),
        ],
      ),
    );
  }

  List<YorksV1ArrangementLineInput> _commandLines() => [
    for (final line in _lines.values)
      line
          .copyWith(
            arrangedQuantity: _arrangedQuantities[line.arrangementLineId]!.text,
            externalSupplier: _trimmedOrNull(
              _suppliers[line.arrangementLineId]!.text,
            ),
            reason: _trimmedOrNull(_reasons[line.arrangementLineId]!.text),
            unitCost: ref.read(canManageCommercialsProvider)
                ? _unitCosts[line.arrangementLineId]!.text
                : null,
          )
          .toInput(),
  ];

  Future<void> _review() async {
    if (_reviewOpen || _busy || !_progress.state.canEdit) return;
    final inputs = _commandLines();
    final issues = _validateLines(inputs);
    if (issues.isNotEmpty) {
      setState(() {
        _validationIssues = issues;
        _focusLineId = issues.keys.first;
      });
      return;
    }
    _reviewOpen = true;
    var answered = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          YorksV1ArrangementStrings.reviewArrangement.active(widget.language),
        ),
        content: SizedBox(
          width: 760,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  YorksV1ArrangementStrings.reviewBeforeSave.active(
                    widget.language,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: inputs.length,
                    itemBuilder: (context, index) {
                      final line = _arrangement.lines[index];
                      final input = inputs[index];
                      final item = _inventoryItems
                          .where((item) => item.id == input.inventoryItemId)
                          .firstOrNull;
                      return ListTile(
                        title: Text(line.description),
                        subtitle: Text(
                          '${yorksV1ArrangementDecisionCopy(input.decision).active(widget.language)} · ${input.source == YorksV1ArrangementSource.warehouse ? (item?.description ?? YorksV1ArrangementStrings.warehouse.primary) : (input.externalSupplier ?? YorksV1ArrangementStrings.externalSupplier.primary)}${input.reason == null ? '' : '\n${input.reason}'}',
                        ),
                        trailing: Text(
                          '${yorksV1DisplayQuantity(input.arrangedQuantity)} / ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.cancel.primary),
          ),
          FilledButton(
            onPressed: () {
              if (answered) return;
              answered = true;
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              YorksV1ArrangementStrings.saveForApproval.active(widget.language),
            ),
          ),
        ],
      ),
    );
    _reviewOpen = false;
    if (confirmed == true && mounted) await _save();
  }

  Future<void> _completeRecovered() async {
    if (_recoveryCompletionStarted) return;
    _recoveryCompletionStarted = true;
    try {
      await _progress.retireAfterCommit();
      if (!mounted) return;
      setState(() => _allowExit = true);
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      widget.onCompleted?.call();
    } catch (_) {
      _progress.markViewRefreshDegraded();
    }
  }

  Future<void> _releaseAbandoned(YorksV1ProcurementPendingCommand command) =>
      ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .releaseRejectedPreparedCommand(
            operation: 'save_arrangement',
            entityId: _arrangement.id,
            idempotencyKey: command.commandKey,
          );

  Future<void> _rejectIntent(Object error) async {
    final pending = _progress.state.pendingCommand;
    await _progress.rejectFinalIntent(error);
    if (pending != null && _progress.state.pendingCommand == null && mounted) {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .releaseRejectedPreparedCommand(
            operation: 'save_arrangement',
            entityId: _arrangement.id,
            idempotencyKey: pending.commandKey,
          );
    }
  }

  Future<void> _retryPending() async {
    final pending = _progress.state.pendingCommand;
    final payload = _progress.pendingCommandPayload;
    if (pending == null || payload == null || _busy) return;
    final lines = (payload['lines'] as List).map((raw) {
      final row = raw as Map;
      return YorksV1ArrangementLineInput(
        arrangementLineId: row['arrangement_line_id'] as String,
        decision: YorksV1ArrangementDecision.fromWireValue(row['decision'])!,
        source: YorksV1ArrangementSource.fromWireValue(row['source_kind']),
        arrangedQuantity: row['arranged_qty'].toString(),
        inventoryItemId: row['inventory_item_id'] as String?,
        externalSupplier: row['external_supplier'] as String?,
        externalSourceReady: row['external_source_ready'] == true,
        externalExpectedDate: row['external_expected_date'] as String?,
        externalReference: row['external_reference'] as String?,
        reason: row['reason'] as String?,
        unitCost: row['unit_cost']?.toString(),
      );
    }).toList();
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .saveArrangement(
            YorksV1SaveArrangementInput(
              requestId: payload['request_id'] as String,
              arrangementId: payload['arrangement_id'] as String,
              expectedRequestVersion:
                  payload['expected_request_version'] as int,
              expectedArrangementVersion:
                  payload['expected_arrangement_version'] as int,
              lines: lines,
              procurementNote: payload['procurement_note'] as String?,
              idempotencyKey: pending.commandKey,
            ),
            recoveredIdempotencyKey: pending.commandKey,
          );
      await _completeRecovered();
    } catch (error) {
      await _rejectIntent(error);
      if (_progress.state.outcome?.isConfirmed == true) {
        await _completeRecovered();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_canSave || !_progress.state.canEdit) return;
    _editorChanged();
    final inputs = _commandLines();
    final validationIssues = _validateLines(inputs);
    if (validationIssues.isNotEmpty) {
      setState(() => _validationIssues = validationIssues);
      return;
    }
    var saved = false;
    setState(() => _busy = true);
    try {
      final input = YorksV1SaveArrangementInput(
        requestId: widget.workspace.requestId,
        arrangementId: _arrangement.id,
        expectedRequestVersion: _requestRecordVersion,
        expectedArrangementVersion: _arrangement.recordVersion,
        lines: inputs,
        procurementNote: _procurementNote.text,
        idempotencyKey: _saveIdempotencyKey,
      );
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .saveArrangement(
            input,
            beforeInvoke: (key) async {
              await _progress.prepareFinalIntent(
                commandName: 'v1_save_arrangement',
                commandKey: key,
                commandPayload: input.toRpcPayload(),
              );
              _progress.markFinalCommandSent();
            },
          );
      await _progress.retireAfterCommit();
      _allowExit = true;
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      _saveIdempotencyKey = const Uuid().v4();
      saved = true;
    } on YorksV1DomainException catch (error) {
      await _rejectIntent(error);
      if (_progress.state.outcome?.isConfirmed == true) {
        await _completeRecovered();
        return;
      }
      if (_progress.state.isPending) return;
      if (error.code == YorksV1DomainErrorCode.insufficientStock) {
        await _refreshInventoryAfterStockFailure();
      }
      if (mounted) _showFailure(context, error);
    } catch (error) {
      await _rejectIntent(error);
      if (_progress.state.outcome?.isConfirmed == true) {
        await _completeRecovered();
        return;
      }
      if (_progress.state.isPending) return;
      if (mounted) _showFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) {
      final full = inputs
          .where((line) => line.decision == YorksV1ArrangementDecision.full)
          .length;
      final partial = inputs
          .where((line) => line.decision == YorksV1ArrangementDecision.partial)
          .length;
      final unavailable = inputs
          .where(
            (line) => line.decision == YorksV1ArrangementDecision.unavailable,
          )
          .length;
      YorksAppToast.show(
        context,
        title: YorksV1ArrangementStrings.arrangementSaved.active(
          widget.language,
        ),
        message: YorksV1ArrangementStrings.arrangementSavedSummary(
          full: full,
          partial: partial,
          unavailable: unavailable,
        ).active(widget.language),
        tone: YorksAppToastTone.success,
      );
      widget.onCompleted?.call();
    }
  }

  void _initializeLineControllers() {
    for (final line in _lines.values) {
      _arrangedQuantities[line.arrangementLineId] = TextEditingController(
        text: yorksV1DisplayQuantity(line.arrangedQuantity),
      );
      _unitCosts[line.arrangementLineId] = TextEditingController(
        text: line.unitCost ?? '',
      );
      _suppliers[line.arrangementLineId] = TextEditingController(
        text: line.externalSupplier ?? '',
      );
      _reasons[line.arrangementLineId] = TextEditingController(
        text: line.reason ?? '',
      );
      for (final controller in [
        _arrangedQuantities[line.arrangementLineId]!,
        _unitCosts[line.arrangementLineId]!,
        _suppliers[line.arrangementLineId]!,
        _reasons[line.arrangementLineId]!,
      ]) {
        controller.addListener(() {
          if (!_syncingProgress && mounted) {
            final current = _lines[line.arrangementLineId]!;
            final raw = _arrangedQuantities[line.arrangementLineId]!.text;
            if (raw != current.arrangedQuantity) {
              setState(
                () => _lines[line.arrangementLineId] = current.copyWith(
                  arrangedQuantity: raw,
                ),
              );
            }
          }
          _clearValidationForLine(line.arrangementLineId);
          _editorChanged();
        });
      }
    }
  }

  void _initializeLineKeys() {
    _lineKeys
      ..clear()
      ..addEntries(
        widget.arrangement.lines.map((line) => MapEntry(line.id, GlobalKey())),
      );
    _validationIssues = const {};
  }

  void _clearValidationForLine(String lineId) {
    if (!mounted || !_validationIssues.containsKey(lineId)) return;
    setState(() {
      _validationIssues = {..._validationIssues}..remove(lineId);
    });
  }

  void _revealLine(String lineId) {
    setState(() => _focusLineId = lineId);
    final lineContext = _lineKeys[lineId]?.currentContext;
    if (lineContext != null) {
      Scrollable.ensureVisible(
        lineContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: .15,
      );
    }
  }

  void _disposeLineControllers() {
    for (final controller in _arrangedQuantities.values) {
      controller.dispose();
    }
    for (final controller in _unitCosts.values) {
      controller.dispose();
    }
    for (final controller in _suppliers.values) {
      controller.dispose();
    }
    for (final controller in _reasons.values) {
      controller.dispose();
    }
    _arrangedQuantities.clear();
    _unitCosts.clear();
    _suppliers.clear();
    _reasons.clear();
  }

  List<YorksV1InventoryItem> _inventoryItemsForRequest(
    List<YorksV1InventoryItem> items,
  ) {
    final retainedByItem = <String, YorksV1DecimalQuantity>{};
    for (final arrangement in widget.workspace.arrangements) {
      for (final line in arrangement.lines) {
        final itemId = line.inventoryItemId;
        final reserved = line.reservedQuantity == null
            ? null
            : YorksV1DecimalQuantity.tryParse(line.reservedQuantity!);
        if (itemId == null ||
            reserved == null ||
            (line.reservationState != 'active' &&
                line.reservationState != 'partially_consumed')) {
          continue;
        }
        retainedByItem[itemId] =
            (retainedByItem[itemId] ?? YorksV1DecimalQuantity.zero) + reserved;
      }
    }
    return [
      for (final item in items)
        YorksV1InventoryItem(
          id: item.id,
          itemCode: item.itemCode,
          description: item.description,
          brandOrigin: item.brandOrigin,
          locationBin: item.locationBin,
          unit: item.unit,
          onHandQuantity: item.onHandQuantity,
          reservedQuantity: item.reservedQuantity,
          // The server excludes this request's retained reservation when a
          // returned arrangement is replaced. Mirror that effective amount
          // locally so validation never rejects a replacement the RPC allows.
          availableQuantity:
              ((YorksV1DecimalQuantity.tryParse(item.availableQuantity) ??
                          YorksV1DecimalQuantity.zero) +
                      (retainedByItem[item.id] ?? YorksV1DecimalQuantity.zero))
                  .canonicalText,
          recordVersion: item.recordVersion,
        ),
    ];
  }

  Map<String, List<String>> _validateLines(
    List<YorksV1ArrangementLineInput> lines,
  ) {
    final issues = <String, List<String>>{};
    void add(String lineId, String message) {
      final lineIssues = issues.putIfAbsent(lineId, () => <String>[]);
      if (!lineIssues.contains(message)) lineIssues.add(message);
    }

    for (final id in _incompleteRestoredChoices) {
      add(
        id,
        YorksV1ArrangementStrings.decideEveryLine.active(widget.language),
      );
    }
    final reservedByInventoryItem = <String, YorksV1DecimalQuantity>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final arrangedLine = widget.arrangement.lines.firstWhere(
        (value) => value.id == line.arrangementLineId,
      );
      final label =
          '${YorksV1ArrangementStrings.rowNumber.primary} ${arrangedLine.displayOrder}';
      final quantity = YorksV1DecimalQuantity.tryParse(line.arrangedQuantity);
      if (quantity == null || quantity.isNegative) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.invalidQuantityFor(
            label,
          ).active(widget.language),
        );
        continue;
      }
      if (line.decision == YorksV1ArrangementDecision.unavailable) {
        if (!quantity.isZero ||
            line.reason == null ||
            line.reason!.trim().isEmpty) {
          add(
            line.arrangementLineId,
            YorksV1ArrangementStrings.unavailableReasonFor(
              label,
            ).active(widget.language),
          );
        }
        continue;
      }
      final requestedQuantity = YorksV1DecimalQuantity.tryParse(
        arrangedLine.requestedQuantity,
      );
      if (requestedQuantity == null) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.invalidQuantityFor(
            label,
          ).active(widget.language),
        );
        continue;
      }
      if (line.decision == YorksV1ArrangementDecision.full &&
          quantity != requestedQuantity) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.fullQuantityFor(
            label,
          ).active(widget.language),
        );
      }
      if (line.decision == YorksV1ArrangementDecision.partial &&
          (!quantity.isPositive ||
              quantity.compareTo(requestedQuantity) >= 0)) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.partialQuantityFor(
            label,
          ).active(widget.language),
        );
      }
      final unitCost = line.unitCost?.trim() ?? '';
      if (unitCost.isNotEmpty &&
          (YorksV1DecimalQuantity.tryParse(unitCost) == null ||
              YorksV1DecimalQuantity.tryParse(unitCost)!.isNegative)) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.invalidUnitCostFor(
            label,
          ).active(widget.language),
        );
      }
      if (line.source == YorksV1ArrangementSource.warehouse &&
          (line.inventoryItemId == null ||
              line.inventoryItemId!.trim().isEmpty)) {
        add(
          line.arrangementLineId,
          _inventoryItems.isEmpty
              ? YorksV1ArrangementStrings.emptyWarehouseFor(
                  label,
                ).active(widget.language)
              : YorksV1ArrangementStrings.warehouseItemRequiredFor(
                  label,
                ).active(widget.language),
        );
      }
      if (line.source == YorksV1ArrangementSource.warehouse &&
          line.inventoryItemId != null &&
          line.inventoryItemId!.trim().isNotEmpty) {
        final inventoryItemId = line.inventoryItemId!;
        reservedByInventoryItem[inventoryItemId] =
            (reservedByInventoryItem[inventoryItemId] ??
                YorksV1DecimalQuantity.zero) +
            quantity;
      }
      if (line.source == YorksV1ArrangementSource.externalSupplier &&
          (widget.workspace.externalSourceReadinessRequired ||
              widget.workspace.timing ==
                  YorksV1MaterialRequestTiming.scheduled) &&
          !line.externalSourceReady) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.externalReadinessRequired.active(
            widget.language,
          ),
        );
      }
      final expectedDate = line.externalExpectedDate?.trim() ?? '';
      if (expectedDate.isNotEmpty &&
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expectedDate)) {
        add(
          line.arrangementLineId,
          '${YorksV1ArrangementStrings.expectedAvailabilityDate.active(widget.language)}: YYYY-MM-DD',
        );
      }
      if ((line.decision == YorksV1ArrangementDecision.partial ||
              line.decision == YorksV1ArrangementDecision.unavailable) &&
          (line.reason == null || line.reason!.trim().isEmpty)) {
        add(
          line.arrangementLineId,
          YorksV1ArrangementStrings.partialReasonFor(
            label,
          ).active(widget.language),
        );
      }
    }
    for (final entry in reservedByInventoryItem.entries) {
      final inventoryItem = _inventoryItems
          .where((item) => item.id == entry.key)
          .firstOrNull;
      final available = inventoryItem == null
          ? null
          : YorksV1DecimalQuantity.tryParse(inventoryItem.availableQuantity);
      if (inventoryItem == null ||
          available == null ||
          entry.value.compareTo(available) > 0) {
        for (final input in lines.where(
          (line) =>
              line.source == YorksV1ArrangementSource.warehouse &&
              line.inventoryItemId == entry.key &&
              line.decision != YorksV1ArrangementDecision.unavailable,
        )) {
          final arrangedLine = _arrangement.lines.firstWhere(
            (line) => line.id == input.arrangementLineId,
          );
          final label =
              '${YorksV1ArrangementStrings.rowNumber.primary} ${arrangedLine.displayOrder}';
          add(
            arrangedLine.id,
            YorksV1ArrangementStrings.warehouseStockShortageFor(
              line: label,
              item:
                  inventoryItem?.description ??
                  arrangedLine.inventoryItemDescription ??
                  arrangedLine.description,
              requiredQuantity: entry.value.canonicalText,
              availableQuantity: available?.canonicalText ?? '0',
              unit: inventoryItem?.unit ?? arrangedLine.unit,
            ).active(widget.language),
          );
        }
      }
    }
    return issues;
  }

  Future<void> _refreshInventoryAfterStockFailure() async {
    try {
      final items = await ref
          .read(yorksV1ArrangementRepositoryProvider)
          .listInventoryItems();
      if (!mounted) return;
      setState(() => _inventoryItems = _inventoryItemsForRequest(items));
      ref.invalidate(yorksV1ArrangementInventoryProvider);
    } catch (_) {
      // Keep the original save error. A best-effort refresh failure is less
      // useful than the specific stock message already available to the user.
    }
  }
}

class _ProcurementItemEditResult {
  const _ProcurementItemEditResult({
    required this.description,
    this.modelReference,
  });

  final String description;
  final String? modelReference;
}

Future<_ProcurementItemEditResult?> _showProcurementItemEditor({
  required BuildContext context,
  required YorksV1MaterialRequest request,
  required YorksV1ArrangementLine line,
  required AppLanguage language,
  required Future<String?> Function(_ProcurementItemEditResult result) onSave,
}) {
  final editor = _ProcurementItemEditor(
    request: request,
    line: line,
    language: language,
    onSave: onSave,
  );
  if (MediaQuery.sizeOf(context).width < 700) {
    return showModalBottomSheet<_ProcurementItemEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => FractionallySizedBox(heightFactor: .94, child: editor),
    );
  }
  return showDialog<_ProcurementItemEditResult>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: editor,
      ),
    ),
  );
}

class _ProcurementItemEditor extends ConsumerStatefulWidget {
  const _ProcurementItemEditor({
    required this.request,
    required this.line,
    required this.language,
    required this.onSave,
  });

  final YorksV1MaterialRequest request;
  final YorksV1ArrangementLine line;
  final AppLanguage language;
  final Future<String?> Function(_ProcurementItemEditResult result) onSave;

  @override
  ConsumerState<_ProcurementItemEditor> createState() =>
      _ProcurementItemEditorState();
}

class _ProcurementItemEditorState
    extends ConsumerState<_ProcurementItemEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _search;
  late final TextEditingController _description;
  late final TextEditingController _model;
  Timer? _searchDebounce;
  String _searchQuery = '';
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _description = TextEditingController(text: widget.line.description);
    _model = TextEditingController(text: widget.line.modelReference ?? '');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _description.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typedQuery = _search.text.trim();
    final query = _searchQuery;
    final suggestions = query.length < 2
        ? const AsyncData<List<YorksV1MaterialRequestInventorySuggestion>>([])
        : ref.watch(
            yorksV1MaterialRequestInventorySearchProvider(
              YorksV1MaterialRequestInventorySearchKey(
                projectId: widget.request.projectId,
                scopeId: widget.request.scopeId,
                query: query,
              ),
            ),
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      YorksV1ArrangementStrings.clarifyItem.active(
                        widget.language,
                      ),
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      YorksV1ArrangementStrings.clarifyItemDescription.active(
                        widget.language,
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YorksV1ArrangementStrings.originallyRequested.active(
                            widget.language,
                          ),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          widget.line.requestedDescription ??
                              widget.line.description,
                          style: AppTypography.titleSmall,
                        ),
                        if (widget.line.requestedModelReference != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            '${YorksV1ArrangementStrings.modelReference.active(widget.language)}: ${widget.line.requestedModelReference}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('procurement-item-search'),
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _scheduleSearch,
                    decoration: InputDecoration(
                      labelText: YorksV1ArrangementStrings.searchKnownItems
                          .active(widget.language),
                      hintText: YorksV1ArrangementStrings.searchKnownItemsHint
                          .active(widget.language),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: typedQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _search.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  if (query.length >= 2) ...[
                    const SizedBox(height: AppSpacing.sm),
                    suggestions.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          yorksV1MaterialRequestInventorySearchProvider(
                            YorksV1MaterialRequestInventorySearchKey(
                              projectId: widget.request.projectId,
                              scopeId: widget.request.scopeId,
                              query: query,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          YorksV1MaterialRequestStrings.refresh.active(
                            widget.language,
                          ),
                        ),
                      ),
                      data: (items) => items.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: Text(
                                YorksV1ArrangementStrings.noMatchingItems
                                    .active(widget.language),
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    minTileHeight: 56,
                                    leading: Icon(
                                      item.source ==
                                              YorksV1MaterialRequestSuggestionSource
                                                  .inventory
                                          ? Icons.inventory_2_outlined
                                          : Icons.table_rows_outlined,
                                      color: AppColors.blue,
                                    ),
                                    title: Text(item.description),
                                    subtitle: Text(
                                      <String>[
                                        _suggestionSourceLabel(
                                          item.source,
                                          widget.language,
                                        ),
                                        ?item.model,
                                        ?item.brandOrigin,
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      _description.text = item.description;
                                      _model.text = item.model ?? '';
                                      _searchDebounce?.cancel();
                                      _search.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const ValueKey('procurement-item-description'),
                    controller: _description,
                    maxLength: 4000,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: YorksV1ArrangementStrings.itemName.active(
                        widget.language,
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? YorksV1ArrangementStrings.itemName.active(
                            widget.language,
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const ValueKey('procurement-item-model'),
                    controller: _model,
                    maxLength: 255,
                    decoration: InputDecoration(
                      labelText: YorksV1ArrangementStrings
                          .modelReferenceOptional
                          .active(widget.language),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          YorksV1ArrangementStrings.clarificationEvidenceHelp
                              .active(widget.language),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _saveError!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final cancel = SecondaryButton(
                label: AppStrings.cancel.active(widget.language),
                isExpanded: compact,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              );
              final save = PrimaryButton(
                key: const ValueKey('save-procurement-item-clarification'),
                label: YorksV1ArrangementStrings.saveClarification.active(
                  widget.language,
                ),
                icon: Icons.check_rounded,
                isExpanded: compact,
                onPressed: _saving
                    ? null
                    : () async {
                        if (!(_formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _saveError = null;
                        });
                        final result = _ProcurementItemEditResult(
                          description: _description.text.trim(),
                          modelReference: _trimmedOrNull(_model.text),
                        );
                        final error = await widget.onSave(result);
                        if (!mounted || !context.mounted) return;
                        if (error == null) {
                          Navigator.of(context).pop(result);
                          return;
                        }
                        setState(() {
                          _saving = false;
                          _saveError = error;
                        });
                      },
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (compact) Expanded(child: cancel) else cancel,
                  const SizedBox(width: AppSpacing.sm),
                  if (compact) Expanded(child: save) else save,
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = '');
    final query = value.trim();
    if (query.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _searchQuery = query);
    });
  }
}

String _suggestionSourceLabel(
  YorksV1MaterialRequestSuggestionSource source,
  AppLanguage language,
) => switch (source) {
  YorksV1MaterialRequestSuggestionSource.selectedScopeBoq =>
    YorksV1MaterialRequestStrings.selectedScopeBoq.active(language),
  YorksV1MaterialRequestSuggestionSource.projectBoq =>
    YorksV1MaterialRequestStrings.projectBoq.active(language),
  YorksV1MaterialRequestSuggestionSource.inventory =>
    YorksV1MaterialRequestStrings.inventoryCatalogue.active(language),
};

enum _MobileArrangementStage { lines, line, review }

class _MobileArrangementFlow extends StatefulWidget {
  const _MobileArrangementFlow({
    required this.progressPanel,
    required this.workspace,
    required this.arrangement,
    required this.inventoryItems,
    required this.language,
    required this.lines,
    required this.arrangedQuantities,
    required this.unitCosts,
    required this.canManageCommercials,
    required this.suppliers,
    required this.reasons,
    required this.validationIssues,
    required this.procurementNote,
    required this.busy,
    required this.enabled,
    required this.canClarify,
    required this.clarificationReviewRequired,
    required this.onChanged,
    required this.onCreateInventoryItem,
    required this.onEditItem,
    required this.onSave,
  });

  final Widget progressPanel;
  final YorksV1ArrangementWorkspace workspace;
  final YorksV1ProcurementArrangement arrangement;
  final List<YorksV1InventoryItem> inventoryItems;
  final AppLanguage language;
  final Map<String, _EditableArrangementLine> lines;
  final Map<String, TextEditingController> arrangedQuantities;
  final Map<String, TextEditingController> unitCosts;
  final bool canManageCommercials;
  final Map<String, TextEditingController> suppliers;
  final Map<String, TextEditingController> reasons;
  final Map<String, List<String>> validationIssues;
  final TextEditingController procurementNote;
  final bool busy;
  final bool enabled;
  final bool canClarify;
  final bool clarificationReviewRequired;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  )
  onCreateInventoryItem;
  final Future<void> Function(YorksV1ArrangementLine line) onEditItem;
  final Future<void> Function() onSave;

  @override
  State<_MobileArrangementFlow> createState() => _MobileArrangementFlowState();
}

class _MobileArrangementFlowState extends State<_MobileArrangementFlow> {
  _MobileArrangementStage _stage = _MobileArrangementStage.lines;
  int _lineIndex = 0;

  @override
  Widget build(BuildContext context) => switch (_stage) {
    _MobileArrangementStage.lines => _buildLines(),
    _MobileArrangementStage.line => _buildLine(),
    _MobileArrangementStage.review => _buildReview(),
  };

  Widget _buildLines() {
    final counts = _counts;
    return Column(
      key: const ValueKey('mobile-arrangement-list'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.progressPanel,
                const SizedBox(height: 12),
                YorksMobilePageTitle(
                  eyebrow:
                      '${widget.workspace.requestNumber ?? widget.workspace.requestId} · ${widget.workspace.requestState}',
                  title: YorksV1ArrangementStrings.arrangeRequestedItems.active(
                    widget.language,
                  ),
                  description: YorksV1ArrangementStrings.decideEveryLine.active(
                    widget.language,
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.clarificationReviewRequired) ...[
                  _ClarificationReviewBanner(language: widget.language),
                  const SizedBox(height: 14),
                ],
                _MobileArrangementCounts(counts: counts),
                if (widget.validationIssues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ArrangementValidationSummary(
                    issues: widget.validationIssues,
                    lines: widget.arrangement.lines,
                    language: widget.language,
                    onLineTap: _openLine,
                  ),
                ],
                const SizedBox(height: 10),
                for (
                  var index = 0;
                  index < widget.arrangement.lines.length;
                  index++
                ) ...[
                  _MobileArrangementLineCard(
                    line: widget.arrangement.lines[index],
                    draft: widget.lines[widget.arrangement.lines[index].id]!,
                    onTap: () => setState(() {
                      _lineIndex = index;
                      _stage = _MobileArrangementStage.line;
                    }),
                  ),
                  const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ),
        YorksMobileStickyActions(
          summary: YorksV1ArrangementStrings.linesDecided(
            widget.lines.values.where((line) => line.decision != null).length,
            widget.arrangement.lines.length,
          ).active(widget.language),
          children: [
            PrimaryButton(
              key: const ValueKey('mobile-arrangement-review-action'),
              label: YorksV1MaterialRequestStrings.reviewArrangement.active(
                widget.language,
              ),
              onPressed: widget.busy || !widget.enabled
                  ? null
                  : () =>
                        setState(() => _stage = _MobileArrangementStage.review),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLine() {
    final line = widget.arrangement.lines[_lineIndex];
    final draft = widget.lines[line.id]!;
    return Column(
      key: const ValueKey('mobile-arrangement-line'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.progressPanel,
                const SizedBox(height: 12),
                YorksMobilePageTitle(
                  eyebrow: YorksV1ArrangementStrings.itemPosition(
                    _lineIndex + 1,
                    widget.arrangement.lines.length,
                  ).active(widget.language),
                  title: line.description,
                  description: [
                    if (line.isBoqCorrelated)
                      _arrangementCorrelationText(line, widget.language),
                    line.brandOrigin,
                    '${YorksV1ArrangementStrings.requested.active(widget.language)} ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                  ].whereType<String>().join(' · '),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    key: const ValueKey('mobile-clarify-item-action'),
                    onPressed: widget.canClarify && !widget.busy
                        ? () => widget.onEditItem(line)
                        : null,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: Text(
                      YorksV1ArrangementStrings.clarifyItem.active(
                        widget.language,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.validationIssues[line.id]?.isNotEmpty ?? false) ...[
                  _ArrangementInlineIssue(
                    messages: widget.validationIssues[line.id]!,
                  ),
                  const SizedBox(height: 14),
                ],
                _QuantityField(
                  value: draft,
                  controller: widget.arrangedQuantities[line.id]!,
                  enabled: widget.enabled && !widget.busy,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _ArrangementDecisionChip(decision: draft.decision),
                ),
                const SizedBox(height: 14),
                _SourcePicker(
                  value: draft,
                  enabled: widget.enabled && !widget.busy,
                  onChanged: (value) {
                    widget.onChanged(value);
                    setState(() {});
                  },
                ),
                if (draft.decision !=
                    YorksV1ArrangementDecision.unavailable) ...[
                  const SizedBox(height: 14),
                  _InventoryOrSupplierField(
                    line: line,
                    value: draft,
                    supplier: widget.suppliers[line.id]!,
                    inventoryItems: widget.inventoryItems,
                    enabled: widget.enabled && !widget.busy,
                    onChanged: (value) {
                      widget.onChanged(value);
                      setState(() {});
                    },
                    onCreateInventoryItem: () async {
                      await widget.onCreateInventoryItem(line, draft);
                      if (mounted) setState(() {});
                    },
                  ),
                  if (draft.source ==
                      YorksV1ArrangementSource.externalSupplier) ...[
                    const SizedBox(height: 14),
                    _ExternalSourceReadinessFields(
                      value: draft,
                      enabled: widget.enabled && !widget.busy,
                      language: widget.language,
                      requiredByPolicy:
                          (widget.workspace.externalSourceReadinessRequired ||
                          widget.workspace.timing ==
                              YorksV1MaterialRequestTiming.scheduled),
                      onChanged: (value) {
                        widget.onChanged(value);
                        setState(() {});
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (widget.canManageCommercials) ...[
                    _UnitCostField(
                      value: draft,
                      controller: widget.unitCosts[line.id]!,
                      enabled: widget.enabled && !widget.busy,
                    ),
                  ],
                ],
                if (draft.decision == YorksV1ArrangementDecision.partial ||
                    draft.decision ==
                        YorksV1ArrangementDecision.unavailable) ...[
                  const SizedBox(height: 14),
                  _ReasonField(
                    value: draft,
                    controller: widget.reasons[line.id]!,
                    enabled: widget.enabled && !widget.busy,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      YorksV1ArrangementStrings.invalidLines.active(
                        widget.language,
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                YorksMobileCallout(
                  icon: Icons.lock_outline_rounded,
                  title: YorksV1ArrangementStrings.quantityRule.active(
                    widget.language,
                  ),
                  message:
                      '${YorksV1ArrangementStrings.arranged.active(widget.language)}: ${yorksV1DisplayQuantity(widget.arrangedQuantities[line.id]!.text)} / ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                ),
              ],
            ),
          ),
        ),
        YorksMobileStickyActions(
          children: [
            SecondaryButton(
              label: YorksV1ArrangementStrings.previous.active(widget.language),
              onPressed: widget.busy || !widget.enabled ? null : _previous,
            ),
            PrimaryButton(
              label: YorksV1ArrangementStrings.saveAndNext.active(
                widget.language,
              ),
              onPressed: widget.busy || !widget.enabled ? null : _next,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview() {
    final counts = _counts;
    final exceptions = widget.arrangement.lines
        .where((line) {
          final decision = widget.lines[line.id]!.decision;
          return decision != YorksV1ArrangementDecision.full;
        })
        .toList(growable: false);
    return Column(
      key: const ValueKey('mobile-arrangement-review'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.progressPanel,
                const SizedBox(height: 12),
                YorksMobilePageTitle(
                  eyebrow: YorksV1ArrangementStrings.arrangementReview.active(
                    widget.language,
                  ),
                  title: YorksV1ArrangementStrings.readyForProjectEngineer
                      .active(widget.language),
                  description: YorksV1ArrangementStrings
                      .approvalReleasesArranged
                      .active(widget.language),
                ),
                const SizedBox(height: 14),
                _MobileArrangementCounts(counts: counts),
                if (widget.validationIssues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ArrangementValidationSummary(
                    issues: widget.validationIssues,
                    lines: widget.arrangement.lines,
                    language: widget.language,
                    onLineTap: _openLine,
                  ),
                ],
                if (exceptions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  YorksMobileCallout(
                    icon: Icons.warning_amber_rounded,
                    warning: true,
                    title: YorksV1ArrangementStrings.exceptionsRequireAttention(
                      exceptions.length,
                    ).active(widget.language),
                    message: YorksV1ArrangementStrings.exceptionSummary(
                      counts.partial,
                      counts.unavailable,
                    ).active(widget.language),
                  ),
                  const SizedBox(height: 10),
                  YorksMobileCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var index = 0; index < exceptions.length; index++)
                          _MobileArrangementReviewLine(
                            line: exceptions[index],
                            draft: widget.lines[exceptions[index].id]!,
                            reason: widget.reasons[exceptions[index].id]!.text,
                            arrangedQuantity: widget
                                .arrangedQuantities[exceptions[index].id]!
                                .text,
                            onTap: () {
                              _lineIndex = widget.arrangement.lines.indexWhere(
                                (line) => line.id == exceptions[index].id,
                              );
                              setState(
                                () => _stage = _MobileArrangementStage.line,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _MobileFieldLabel(
                  label: YorksV1ArrangementStrings.procurementNote.active(
                    widget.language,
                  ),
                ),
                TextField(
                  controller: widget.procurementNote,
                  enabled: widget.enabled && !widget.busy,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: YorksV1ArrangementStrings.procurementNoteHint
                        .active(widget.language),
                  ),
                ),
              ],
            ),
          ),
        ),
        YorksMobileStickyActions(
          children: [
            SecondaryButton(
              label: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: widget.busy || !widget.enabled
                  ? null
                  : () =>
                        setState(() => _stage = _MobileArrangementStage.lines),
            ),
            PrimaryButton(
              label: YorksV1ArrangementStrings.saveForApproval.active(
                widget.language,
              ),
              isLoading: widget.busy,
              onPressed: widget.busy || !widget.enabled ? null : widget.onSave,
            ),
          ],
        ),
      ],
    );
  }

  void _openLine(String lineId) {
    final index = widget.arrangement.lines.indexWhere(
      (line) => line.id == lineId,
    );
    if (index < 0) return;
    setState(() {
      _lineIndex = index;
      _stage = _MobileArrangementStage.line;
    });
  }

  ({int full, int partial, int unavailable}) get _counts {
    var full = 0;
    var partial = 0;
    var unavailable = 0;
    for (final line in widget.lines.values) {
      switch (line.decision) {
        case YorksV1ArrangementDecision.full:
          full++;
        case YorksV1ArrangementDecision.partial:
          partial++;
        case YorksV1ArrangementDecision.unavailable:
          unavailable++;
        case null:
          break;
      }
    }
    return (full: full, partial: partial, unavailable: unavailable);
  }

  void _previous() {
    if (_lineIndex == 0) {
      setState(() => _stage = _MobileArrangementStage.lines);
      return;
    }
    setState(() => _lineIndex--);
  }

  void _next() {
    if (_lineIndex + 1 >= widget.arrangement.lines.length) {
      setState(() => _stage = _MobileArrangementStage.review);
      return;
    }
    setState(() => _lineIndex++);
  }
}

class _MobileArrangementCounts extends StatelessWidget {
  const _MobileArrangementCounts({required this.counts});

  final ({int full, int partial, int unavailable}) counts;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _MobileArrangementCount(
        value: counts.full,
        label: yorksV1ArrangementDecisionCopy(
          YorksV1ArrangementDecision.full,
        ).primary,
        color: AppColors.success,
        background: AppColors.successContainer,
      ),
      const SizedBox(width: 8),
      _MobileArrangementCount(
        value: counts.partial,
        label: yorksV1ArrangementDecisionCopy(
          YorksV1ArrangementDecision.partial,
        ).primary,
        color: AppColors.warning,
        background: AppColors.warningContainer,
      ),
      const SizedBox(width: 8),
      _MobileArrangementCount(
        value: counts.unavailable,
        label: yorksV1ArrangementDecisionCopy(
          YorksV1ArrangementDecision.unavailable,
        ).primary,
        color: AppColors.error,
        background: AppColors.errorContainer,
      ),
    ],
  );
}

class _MobileArrangementCount extends StatelessWidget {
  const _MobileArrangementCount({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
  });

  final int value;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: Text(
                  '$value',
                  style: AppTypography.titleSmall.copyWith(color: color),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _MobileArrangementLineCard extends StatelessWidget {
  const _MobileArrangementLineCard({
    required this.line,
    required this.draft,
    required this.onTap,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    onTap: onTap,
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${line.displayOrder}',
            style: AppTypography.labelLarge.copyWith(color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.description, style: AppTypography.titleSmall),
              if (line.brandOrigin != null) ...[
                const SizedBox(height: 2),
                Text(
                  line.brandOrigin!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                '${YorksV1ArrangementStrings.requested.primary} ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                style: AppTypography.labelMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ArrangementDecisionChip(decision: draft.decision),
      ],
    ),
  );
}

class _MobileArrangementReviewLine extends StatelessWidget {
  const _MobileArrangementReviewLine({
    required this.line,
    required this.draft,
    required this.reason,
    required this.arrangedQuantity,
    required this.onTap,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine draft;
  final String reason;
  final String arrangedQuantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 72,
    onTap: onTap,
    leading: Icon(
      draft.decision == YorksV1ArrangementDecision.unavailable
          ? Icons.warning_amber_rounded
          : Icons.inventory_2_outlined,
      color: draft.decision == YorksV1ArrangementDecision.unavailable
          ? AppColors.warning
          : AppColors.blue,
    ),
    title: Text(
      line.description,
      style: AppTypography.titleSmall.copyWith(
        decoration: draft.decision == YorksV1ArrangementDecision.unavailable
            ? TextDecoration.lineThrough
            : null,
      ),
    ),
    subtitle: Text(
      [
        '${yorksV1DisplayQuantity(arrangedQuantity)} ${line.unit}',
        yorksV1ArrangementSourceCopy(draft.source).primary,
        if (reason.trim().isNotEmpty) reason.trim(),
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: _ArrangementDecisionChip(decision: draft.decision),
  );
}

class _ArrangementDecisionChip extends StatelessWidget {
  const _ArrangementDecisionChip({required this.decision});

  final YorksV1ArrangementDecision? decision;

  @override
  Widget build(BuildContext context) {
    final color = switch (decision) {
      YorksV1ArrangementDecision.full => AppColors.success,
      YorksV1ArrangementDecision.partial => AppColors.warning,
      YorksV1ArrangementDecision.unavailable => AppColors.error,
      null => AppColors.muted,
    };
    final background = switch (decision) {
      YorksV1ArrangementDecision.full => AppColors.successContainer,
      YorksV1ArrangementDecision.partial => AppColors.warningContainer,
      YorksV1ArrangementDecision.unavailable => AppColors.errorContainer,
      null => AppColors.surfaceContainerLow,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        decision == null
            ? YorksV1ArrangementStrings.quantityNeeded.primary
            : yorksV1ArrangementDecisionCopy(decision!).primary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _MobileFieldLabel extends StatelessWidget {
  const _MobileFieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(label, style: AppTypography.labelLarge),
  );
}

class _MobileArrangementDecisionView extends ConsumerStatefulWidget {
  const _MobileArrangementDecisionView({
    required this.workspace,
    required this.arrangement,
    required this.language,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1ProcurementArrangement arrangement;
  final AppLanguage language;

  @override
  ConsumerState<_MobileArrangementDecisionView> createState() =>
      _MobileArrangementDecisionViewState();
}

class _MobileArrangementDecisionViewState
    extends ConsumerState<_MobileArrangementDecisionView> {
  bool _busy = false;
  bool _showLines = false;
  bool _exceptionsOnly = false;
  late String _approveIdempotencyKey;
  late String _returnIdempotencyKey;

  @override
  void initState() {
    super.initState();
    _approveIdempotencyKey = const Uuid().v4();
    _returnIdempotencyKey = const Uuid().v4();
  }

  @override
  Widget build(BuildContext context) {
    final showCommercials =
        ref.watch(canViewCommercialsProvider) &&
        widget.arrangement.lines.any((line) => line.unitCost != null);
    final full = widget.arrangement.lines
        .where((line) => line.decision == YorksV1ArrangementDecision.full)
        .length;
    final partial = widget.arrangement.lines
        .where((line) => line.decision == YorksV1ArrangementDecision.partial)
        .length;
    final unavailable = widget.arrangement.lines
        .where(
          (line) => line.decision == YorksV1ArrangementDecision.unavailable,
        )
        .length;
    final visibleLines = _exceptionsOnly
        ? widget.arrangement.lines
              .where((line) => line.decision != YorksV1ArrangementDecision.full)
              .toList(growable: false)
        : widget.arrangement.lines;
    return PopScope(
      canPop: !_busy,
      child: Column(
        key: const ValueKey('mobile-arrangement-approval'),
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  YorksMobilePageTitle(
                    eyebrow: YorksV1ArrangementStrings.projectEngineerReview
                        .active(widget.language),
                    title: YorksV1ArrangementStrings.arrangement.active(
                      widget.language,
                    ),
                    description: YorksV1ArrangementStrings.reviewExceptionsFirst
                        .active(widget.language),
                  ),
                  const SizedBox(height: 14),
                  _MobileArrangementCounts(
                    counts: (
                      full: full,
                      partial: partial,
                      unavailable: unavailable,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MobileDecisionOption(
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.warning,
                    title: YorksV1ArrangementStrings.exceptionsRequireAttention(
                      partial + unavailable,
                    ).active(widget.language),
                    subtitle: YorksV1ArrangementStrings.exceptionSummary(
                      partial,
                      unavailable,
                    ).active(widget.language),
                    onTap: () => setState(() {
                      _showLines = true;
                      _exceptionsOnly = true;
                    }),
                  ),
                  const SizedBox(height: 9),
                  _MobileDecisionOption(
                    icon: Icons.description_outlined,
                    iconColor: AppColors.blue,
                    title:
                        '${YorksV1ArrangementStrings.allMaterialLines.active(widget.language)} · ${widget.arrangement.lines.length}',
                    subtitle: YorksV1ArrangementStrings.materialLineFacts
                        .active(widget.language),
                    onTap: () => setState(() {
                      _showLines = true;
                      _exceptionsOnly = false;
                    }),
                  ),
                  if (_showLines) ...[
                    const SizedBox(height: 10),
                    YorksMobileCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final line in visibleLines)
                            _ReadOnlyLineCard(
                              line: line,
                              showCommercials: showCommercials,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  YorksMobileCallout(
                    icon: Icons.info_outline_rounded,
                    title: YorksV1ArrangementStrings.approvalMeaning.active(
                      widget.language,
                    ),
                    message: YorksV1ArrangementStrings.approvalMeaningMessage
                        .active(widget.language),
                  ),
                ],
              ),
            ),
          ),
          YorksMobileStickyActions(
            children: [
              SecondaryButton(
                label: YorksV1ArrangementStrings.returnAction.active(
                  widget.language,
                ),
                onPressed: _busy ? null : _return,
              ),
              PrimaryButton(
                label: YorksV1ArrangementStrings.approveAction.active(
                  widget.language,
                ),
                isLoading: _busy,
                onPressed: _busy
                    ? null
                    : () => _decide(
                        YorksV1ArrangementReviewDecision.approved,
                        null,
                        _approveIdempotencyKey,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _return() async {
    final reason = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierDismissible: false,
      builder: (context) =>
          _MobileReturnArrangementDialog(language: widget.language),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await _decide(
      YorksV1ArrangementReviewDecision.returned,
      reason,
      _returnIdempotencyKey,
    );
  }

  Future<void> _decide(
    YorksV1ArrangementReviewDecision decision,
    String? reason,
    String idempotencyKey,
  ) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .decideArrangement(
            YorksV1DecideArrangementInput(
              requestId: widget.workspace.requestId,
              arrangementId: widget.arrangement.id,
              expectedRequestVersion: widget.workspace.requestRecordVersion,
              expectedArrangementVersion: widget.arrangement.recordVersion,
              decision: decision,
              reason: reason,
              idempotencyKey: idempotencyKey,
            ),
          );
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (decision == YorksV1ArrangementReviewDecision.approved) {
        _approveIdempotencyKey = const Uuid().v4();
      } else {
        _returnIdempotencyKey = const Uuid().v4();
      }
    } on YorksV1CommittedViewUnavailable {
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
    } on YorksV1CommandOutcomeUnknown {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.commandUnknown.active(
            widget.language,
          ),
          tone: YorksAppToastTone.information,
        );
      }
    } on YorksV1DomainException catch (error) {
      if (mounted) _showFailure(context, error);
    } catch (_) {
      if (mounted) _showFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MobileDecisionOption extends StatelessWidget {
  const _MobileDecisionOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    onTap: onTap,
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(11),
          ),
          child: SizedBox.square(
            dimension: 42,
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      ],
    ),
  );
}

class _MobileReturnArrangementDialog extends StatefulWidget {
  const _MobileReturnArrangementDialog({required this.language});

  final AppLanguage language;

  @override
  State<_MobileReturnArrangementDialog> createState() =>
      _MobileReturnArrangementDialogState();
}

class _MobileReturnArrangementDialogState
    extends State<_MobileReturnArrangementDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      backgroundColor: AppColors.mobileSurface,
      body: Column(
        children: [
          YorksMobileAppBar(
            title: YorksV1ArrangementStrings.returnArrangement.active(
              widget.language,
            ),
            leading: YorksMobileIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  YorksMobilePageTitle(
                    eyebrow: YorksV1ArrangementStrings.returnArrangement.active(
                      widget.language,
                    ),
                    title: YorksV1ArrangementStrings.whatNeedsToChange.active(
                      widget.language,
                    ),
                    description: YorksV1ArrangementStrings.returnReasonRecorded
                        .active(widget.language),
                  ),
                  const SizedBox(height: 18),
                  _MobileFieldLabel(
                    label: YorksV1ArrangementStrings.returnReason.active(
                      widget.language,
                    ),
                  ),
                  TextField(
                    key: const ValueKey('mobile-return-arrangement-reason'),
                    controller: _reason,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 7,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    YorksV1ArrangementStrings.returnReasonHint.active(
                      widget.language,
                    ),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  YorksMobileCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YorksV1ArrangementStrings.whatHappensNext.active(
                            widget.language,
                          ),
                          style: AppTypography.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          YorksV1ArrangementStrings.returnedArrangementHistory
                              .active(widget.language),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          YorksMobileStickyActions(
            children: [
              SecondaryButton(
                label: AppStrings.cancel.active(widget.language),
                onPressed: () => Navigator.of(context).pop(),
              ),
              PrimaryButton(
                label: YorksV1ArrangementStrings.returnAction.active(
                  widget.language,
                ),
                onPressed: () {
                  final value = _reason.text.trim();
                  if (value.isEmpty) return;
                  Navigator.of(context).pop(value);
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DesktopArrangementEditor extends StatelessWidget {
  const _DesktopArrangementEditor({
    required this.horizontal,
    required this.lines,
    required this.drafts,
    required this.arrangedQuantities,
    required this.unitCosts,
    required this.canManageCommercials,
    required this.suppliers,
    required this.reasons,
    required this.inventoryItems,
    required this.enabled,
    required this.canClarify,
    required this.onChanged,
    required this.onCreateInventoryItem,
    required this.onEditItem,
    required this.validationIssues,
    required this.lineKeys,
    required this.language,
    required this.readinessRequired,
  });

  final ScrollController horizontal;
  final List<YorksV1ArrangementLine> lines;
  final Map<String, _EditableArrangementLine> drafts;
  final Map<String, TextEditingController> arrangedQuantities;
  final Map<String, TextEditingController> unitCosts;
  final bool canManageCommercials;
  final Map<String, TextEditingController> suppliers;
  final Map<String, TextEditingController> reasons;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final bool canClarify;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  )
  onCreateInventoryItem;
  final Future<void> Function(YorksV1ArrangementLine line) onEditItem;
  final Map<String, List<String>> validationIssues;
  final Map<String, GlobalKey> lineKeys;
  final AppLanguage language;
  final bool readinessRequired;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tableWidth = constraints.maxWidth < 1060
          ? 1060.0
          : constraints.maxWidth;
      // Match the exact row/header padding, gaps and flex totals. The pinned
      // identity must not cover source controls when the grid scrolls.
      final identityWidth =
          (tableWidth -
              AppSpacing.md * 2 -
              AppSpacing.md * (canManageCommercials ? 4 : 3)) *
          32 /
          (canManageCommercials ? 100 : 90);
      Widget pin(Widget body, Widget identity, {bool header = false}) => Stack(
        children: [
          body,
          AnimatedBuilder(
            animation: horizontal,
            child: identity,
            builder: (context, child) => PositionedDirectional(
              start: horizontal.hasClients ? horizontal.offset : 0,
              top: 0,
              bottom: 0,
              width: identityWidth + AppSpacing.md,
              child: Container(
                color: header
                    ? AppColors.surfaceContainerLow
                    : AppColors.surfaceContainerLowest,
                alignment: AlignmentDirectional.topStart,
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.md,
                  top: AppSpacing.md,
                  bottom: AppSpacing.md,
                ),
                child: child,
              ),
            ),
          ),
        ],
      );
      return SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Column(
              children: [
                pin(
                  _ArrangementTableHeader(
                    showCommercials: canManageCommercials,
                  ),
                  Text(
                    YorksV1ArrangementStrings.requestedItem.active(language),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  header: true,
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return pin(
                        _ArrangementTableRow(
                          hideIdentity: true,
                          key: lineKeys[line.id],
                          line: line,
                          draft: drafts[line.id]!,
                          arrangedQuantity: arrangedQuantities[line.id]!,
                          unitCost: unitCosts[line.id]!,
                          showCommercials: canManageCommercials,
                          supplier: suppliers[line.id]!,
                          reason: reasons[line.id]!,
                          inventoryItems: inventoryItems,
                          enabled: enabled,
                          canClarify: canClarify,
                          onChanged: onChanged,
                          onCreateInventoryItem: onCreateInventoryItem,
                          onEditItem: onEditItem,
                          validationMessages:
                              validationIssues[line.id] ?? const [],
                          language: language,
                          readinessRequired: readinessRequired,
                        ),
                        _ArrangementRequestedItem(
                          line: line,
                          language: language,
                          enabled: canClarify,
                          onEdit: () => onEditItem(line),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ArrangementValidationSummary extends StatelessWidget {
  const _ArrangementValidationSummary({
    required this.issues,
    required this.lines,
    required this.language,
    required this.onLineTap,
  });

  final Map<String, List<String>> issues;
  final List<YorksV1ArrangementLine> lines;
  final AppLanguage language;
  final ValueChanged<String> onLineTap;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('arrangement-validation-summary'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.errorContainer.withValues(alpha: .42),
      border: Border.all(color: AppColors.error.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                YorksV1ArrangementStrings.rowsNeedAttention(
                  issues.length,
                ).active(language),
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final line in lines)
              if (issues.containsKey(line.id))
                OutlinedButton.icon(
                  onPressed: () => onLineTap(line.id),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: Text(
                    YorksV1ArrangementStrings.validationItem(
                      line.displayOrder,
                    ).active(language),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: .45),
                    ),
                    minimumSize: const Size(0, AppSpacing.minTapTarget),
                  ),
                ),
          ],
        ),
      ],
    ),
  );
}

class _ArrangementInlineIssue extends StatelessWidget {
  const _ArrangementInlineIssue({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('arrangement-inline-validation'),
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.errorContainer.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      border: Border.all(color: AppColors.error.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}

class _ArrangementTableHeader extends StatelessWidget {
  const _ArrangementTableHeader({required this.showCommercials});

  final bool showCommercials;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceContainerLow,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      children: [
        _ArrangementTableHeading(
          YorksV1ArrangementStrings.requestedItem,
          flex: 32,
        ),
        const SizedBox(width: AppSpacing.md),
        _ArrangementTableHeading(
          YorksV1ArrangementStrings.supplierSource,
          flex: 34,
        ),
        const SizedBox(width: AppSpacing.md),
        _ArrangementTableHeading(YorksV1ArrangementStrings.requested, flex: 10),
        const SizedBox(width: AppSpacing.md),
        _ArrangementTableHeading(YorksV1ArrangementStrings.arranged, flex: 14),
        if (showCommercials) ...[
          const SizedBox(width: AppSpacing.md),
          const _ArrangementTableHeading(
            YorksV1ArrangementStrings.unitCost,
            flex: 10,
          ),
        ],
      ],
    ),
  );
}

class _ArrangementTableHeading extends StatelessWidget {
  const _ArrangementTableHeading(this.copy, {required this.flex});

  final TranslatableString copy;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      copy.primary.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    ),
  );
}

class _ArrangementTableRow extends StatelessWidget {
  const _ArrangementTableRow({
    super.key,
    this.hideIdentity = false,
    required this.line,
    required this.draft,
    required this.arrangedQuantity,
    required this.unitCost,
    required this.showCommercials,
    required this.supplier,
    required this.reason,
    required this.inventoryItems,
    required this.enabled,
    required this.canClarify,
    required this.onChanged,
    required this.onCreateInventoryItem,
    required this.onEditItem,
    required this.validationMessages,
    required this.language,
    required this.readinessRequired,
  });

  final bool hideIdentity;
  final YorksV1ArrangementLine line;
  final _EditableArrangementLine draft;
  final TextEditingController arrangedQuantity;
  final TextEditingController unitCost;
  final bool showCommercials;
  final TextEditingController supplier;
  final TextEditingController reason;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final bool canClarify;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  )
  onCreateInventoryItem;
  final Future<void> Function(YorksV1ArrangementLine line) onEditItem;
  final List<String> validationMessages;
  final AppLanguage language;
  final bool readinessRequired;

  @override
  Widget build(BuildContext context) {
    final reasonRequired =
        draft.decision == YorksV1ArrangementDecision.partial ||
        draft.decision == YorksV1ArrangementDecision.unavailable;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 32,
                child: Visibility(
                  visible: !hideIdentity,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: _ArrangementRequestedItem(
                    line: line,
                    language: language,
                    enabled: canClarify,
                    onEdit: () => onEditItem(line),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 34,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ArrangementSourceEditor(
                      line: line,
                      value: draft,
                      supplier: supplier,
                      inventoryItems: inventoryItems,
                      enabled: enabled,
                      onChanged: onChanged,
                      onCreateInventoryItem: onCreateInventoryItem,
                    ),
                    if (draft.source ==
                            YorksV1ArrangementSource.externalSupplier &&
                        draft.decision !=
                            YorksV1ArrangementDecision.unavailable) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _ExternalSourceReadinessFields(
                        value: draft,
                        enabled: enabled,
                        language: language,
                        requiredByPolicy: readinessRequired,
                        onChanged: onChanged,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 10,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                    style: AppTypography.labelLarge,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _QuantityField(
                      value: draft,
                      controller: arrangedQuantity,
                      enabled: enabled,
                      compact: true,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _ArrangementDecisionChip(decision: draft.decision),
                    ),
                    if (reasonRequired) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ReasonField(
                        value: draft,
                        controller: reason,
                        enabled: enabled,
                      ),
                    ],
                  ],
                ),
              ),
              if (showCommercials) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 10,
                  child: _UnitCostField(
                    value: draft,
                    controller: unitCost,
                    enabled: enabled,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
          if (validationMessages.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _ArrangementInlineIssue(messages: validationMessages),
          ],
        ],
      ),
    );
  }
}

class _ArrangementRequestedItem extends StatelessWidget {
  const _ArrangementRequestedItem({
    required this.line,
    required this.language,
    this.enabled = false,
    this.onEdit,
  });

  final YorksV1ArrangementLine line;
  final AppLanguage language;
  final bool enabled;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.description,
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
        ),
        if (line.isBoqCorrelated) ...[
          const SizedBox(height: AppSpacing.xxs),
          _ArrangementCorrelationChip(line: line),
        ],
        if (line.brandOrigin?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            line.brandOrigin!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
        if (line.modelReference != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${YorksV1ArrangementStrings.modelReference.active(language)}: ${line.modelReference}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
        if (line.wasProcurementClarified) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${YorksV1ArrangementStrings.originallyRequested.active(language)}: ${line.requestedDescription ?? line.description}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
        if (enabled && onEdit != null) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: Text(YorksV1ArrangementStrings.clarifyItem.active(language)),
          ),
        ],
      ],
    ),
  );
}

String _arrangementCorrelationText(
  YorksV1ArrangementLine line,
  AppLanguage language,
) {
  final label = YorksV1ArrangementStrings.boqCorrelation.active(language);
  return <String>[
    label,
    ?line.sourceScopeName,
    ?line.sourceBoqGroupName,
  ].where((value) => value.trim().isNotEmpty).toSet().join(' · ');
}

class _ArrangementCorrelationChip extends ConsumerWidget {
  const _ArrangementCorrelationChip({required this.line});

  final YorksV1ArrangementLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: line.isBoqCorrelated
          ? AppColors.successContainer
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      _arrangementCorrelationText(line, ref.watch(languageProvider)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(
        color: line.isBoqCorrelated ? AppColors.success : AppColors.muted,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ArrangementSourceEditor extends StatelessWidget {
  const _ArrangementSourceEditor({
    required this.line,
    required this.value,
    required this.supplier,
    required this.inventoryItems,
    required this.enabled,
    required this.onChanged,
    required this.onCreateInventoryItem,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine value;
  final TextEditingController supplier;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  )
  onCreateInventoryItem;

  @override
  Widget build(BuildContext context) {
    if (value.decision == YorksV1ArrangementDecision.unavailable) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          YorksV1ArrangementStrings.noSourceRequired.primary,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SourcePicker(value: value, enabled: enabled, onChanged: onChanged),
        const SizedBox(height: AppSpacing.xs),
        _InventoryOrSupplierField(
          line: line,
          value: value,
          supplier: supplier,
          inventoryItems: inventoryItems,
          enabled: enabled,
          compact: true,
          onChanged: onChanged,
          onCreateInventoryItem: () => onCreateInventoryItem(line, value),
        ),
      ],
    );
  }
}

class _MobileArrangementEditor extends StatelessWidget {
  const _MobileArrangementEditor({
    super.key,
    required this.line,
    required this.draft,
    required this.arrangedQuantity,
    required this.unitCost,
    required this.canManageCommercials,
    required this.supplier,
    required this.reason,
    required this.inventoryItems,
    required this.enabled,
    required this.canClarify,
    required this.onChanged,
    required this.onCreateInventoryItem,
    required this.onEditItem,
    required this.validationMessages,
    required this.language,
    required this.readinessRequired,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine draft;
  final TextEditingController arrangedQuantity;
  final TextEditingController unitCost;
  final bool canManageCommercials;
  final TextEditingController supplier;
  final TextEditingController reason;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final bool canClarify;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function(
    YorksV1ArrangementLine line,
    _EditableArrangementLine draft,
  )
  onCreateInventoryItem;
  final Future<void> Function(YorksV1ArrangementLine line) onEditItem;
  final List<String> validationMessages;
  final AppLanguage language;
  final bool readinessRequired;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${line.displayOrder}. ${line.description}',
          style: AppTypography.titleSmall,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: canClarify ? () => onEditItem(line) : null,
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: Text(YorksV1ArrangementStrings.clarifyItem.active(language)),
          ),
        ),
        if (validationMessages.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _ArrangementInlineIssue(messages: validationMessages),
        ],
        Text(
          '${YorksV1ArrangementStrings.requested.primary}: ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        _ArrangementDecisionChip(decision: draft.decision),
        const SizedBox(height: AppSpacing.md),
        _SourcePicker(value: draft, enabled: enabled, onChanged: onChanged),
        const SizedBox(height: AppSpacing.md),
        _QuantityField(
          value: draft,
          controller: arrangedQuantity,
          enabled: enabled,
        ),
        if (canManageCommercials) ...[
          const SizedBox(height: AppSpacing.md),
          _UnitCostField(value: draft, controller: unitCost, enabled: enabled),
        ],
        const SizedBox(height: AppSpacing.md),
        _InventoryOrSupplierField(
          line: line,
          value: draft,
          supplier: supplier,
          inventoryItems: inventoryItems,
          enabled: enabled,
          onChanged: onChanged,
          onCreateInventoryItem: () => onCreateInventoryItem(line, draft),
        ),
        if (draft.source == YorksV1ArrangementSource.externalSupplier &&
            draft.decision != YorksV1ArrangementDecision.unavailable) ...[
          const SizedBox(height: AppSpacing.md),
          _ExternalSourceReadinessFields(
            value: draft,
            enabled: enabled,
            language: language,
            requiredByPolicy: readinessRequired,
            onChanged: onChanged,
          ),
        ],
        if (draft.decision == YorksV1ArrangementDecision.partial ||
            draft.decision == YorksV1ArrangementDecision.unavailable) ...[
          const SizedBox(height: AppSpacing.md),
          _ReasonField(value: draft, controller: reason, enabled: enabled),
        ],
      ],
    ),
  );
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final _EditableArrangementLine value;
  final bool enabled;
  final ValueChanged<_EditableArrangementLine> onChanged;

  @override
  Widget build(BuildContext context) {
    if (value.decision == YorksV1ArrangementDecision.unavailable) {
      return Text(
        YorksV1ArrangementStrings.noSourceRequired.primary,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final source in YorksV1ArrangementSource.values)
          ChoiceChip(
            key: ValueKey(
              'source-${value.arrangementLineId}-${source.wireValue}',
            ),
            label: Text(yorksV1ArrangementSourceCopy(source).primary),
            selected: value.source == source,
            selectedColor: AppColors.blueContainer,
            checkmarkColor: AppColors.blue,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: !enabled
                ? null
                : (_) => onChanged(
                    value.copyWith(
                      source: source,
                      inventoryItemId:
                          source == YorksV1ArrangementSource.warehouse
                          ? value.inventoryItemId
                          : null,
                      externalSupplier:
                          source == YorksV1ArrangementSource.externalSupplier
                          ? value.externalSupplier
                          : null,
                      externalSourceReady:
                          source == YorksV1ArrangementSource.externalSupplier
                          ? null
                          : false,
                      externalExpectedDate:
                          source == YorksV1ArrangementSource.externalSupplier
                          ? _keep
                          : null,
                      externalReference:
                          source == YorksV1ArrangementSource.externalSupplier
                          ? _keep
                          : null,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _QuantityField extends StatelessWidget {
  const _QuantityField({
    required this.value,
    required this.controller,
    required this.enabled,
    this.compact = false,
  });

  final _EditableArrangementLine value;
  final TextEditingController controller;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 112 : null,
    child: TextFormField(
      key: ValueKey('arranged-${value.arrangementLineId}'),
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        labelText: compact ? null : YorksV1ArrangementStrings.arranged.primary,
        contentPadding: compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 12,
              )
            : null,
      ),
    ),
  );
}

class _UnitCostField extends StatelessWidget {
  const _UnitCostField({
    required this.value,
    required this.controller,
    required this.enabled,
    this.compact = false,
  });

  final _EditableArrangementLine value;
  final TextEditingController controller;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116,
    child: TextFormField(
      key: ValueKey('unit-cost-${value.arrangementLineId}'),
      controller: controller,
      enabled:
          enabled && value.decision != YorksV1ArrangementDecision.unavailable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: compact ? null : YorksV1ArrangementStrings.unitCost.primary,
        contentPadding: compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 12,
              )
            : null,
      ),
    ),
  );
}

class _InventoryOrSupplierField extends StatefulWidget {
  const _InventoryOrSupplierField({
    required this.line,
    required this.value,
    required this.supplier,
    required this.inventoryItems,
    required this.enabled,
    required this.onChanged,
    required this.onCreateInventoryItem,
    this.compact = false,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine value;
  final TextEditingController supplier;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final Future<void> Function() onCreateInventoryItem;
  final bool compact;

  @override
  State<_InventoryOrSupplierField> createState() =>
      _InventoryOrSupplierFieldState();
}

class _InventoryOrSupplierFieldState extends State<_InventoryOrSupplierField> {
  late bool _showSupplierDetails;

  @override
  void initState() {
    super.initState();
    _showSupplierDetails = widget.supplier.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant _InventoryOrSupplierField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.source == YorksV1ArrangementSource.externalSupplier &&
        widget.supplier.text.trim().isNotEmpty) {
      _showSupplierDetails = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value.decision == YorksV1ArrangementDecision.unavailable) {
      return Text(
        YorksV1ArrangementStrings.noSourceRequired.primary,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    if (widget.value.source == YorksV1ArrangementSource.externalSupplier) {
      if (!_showSupplierDetails) {
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: ValueKey(
              'add-supplier-details-${widget.value.arrangementLineId}',
            ),
            onPressed: widget.enabled
                ? () => setState(() => _showSupplierDetails = true)
                : null,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(YorksV1ArrangementStrings.addSupplierDetails.primary),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, AppSpacing.minTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      }
      return Row(
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey(
                'supplier-${widget.value.arrangementLineId}-${widget.value.source.wireValue}',
              ),
              controller: widget.supplier,
              enabled: widget.enabled,
              decoration: InputDecoration(
                hintText: widget.compact
                    ? YorksV1ArrangementStrings.supplierNameOptional.primary
                    : null,
                labelText: widget.compact
                    ? null
                    : YorksV1ArrangementStrings.supplierNameOptional.primary,
                contentPadding: widget.compact
                    ? const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      )
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: widget.enabled
                ? () {
                    widget.supplier.clear();
                    setState(() => _showSupplierDetails = false);
                  }
                : null,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      );
    }
    return SizedBox(
      width: widget.compact ? 220 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarehouseItemAutocomplete(
            line: widget.line,
            value: widget.value,
            inventoryItems: widget.inventoryItems,
            enabled: widget.enabled,
            compact: widget.compact,
            onSelected: (item) => widget.onChanged(
              widget.value.copyWith(inventoryItemId: item.id),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: ValueKey('arrangement-create-inventory-${widget.line.id}'),
              onPressed: widget.enabled ? widget.onCreateInventoryItem : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                YorksV1ArrangementStrings.createInventoryItem.primary,
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, AppSpacing.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ranked, unit-safe inventory picker. The server remains responsible for
/// availability and reservation validation when the arrangement is saved.
class _WarehouseItemAutocomplete extends StatefulWidget {
  const _WarehouseItemAutocomplete({
    required this.line,
    required this.value,
    required this.inventoryItems,
    required this.enabled,
    required this.compact,
    required this.onSelected,
  });

  final YorksV1ArrangementLine line;
  final _EditableArrangementLine value;
  final List<YorksV1InventoryItem> inventoryItems;
  final bool enabled;
  final bool compact;
  final ValueChanged<YorksV1InventoryItem> onSelected;

  @override
  State<_WarehouseItemAutocomplete> createState() =>
      _WarehouseItemAutocompleteState();
}

class _WarehouseItemAutocompleteState
    extends State<_WarehouseItemAutocomplete> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedLabel);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _WarehouseItemAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.inventoryItemId != widget.value.inventoryItemId ||
        oldWidget.inventoryItems != widget.inventoryItems) {
      _controller.text = _selectedLabel;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _selectedLabel {
    final selected = widget.inventoryItems
        .where((item) => item.id == widget.value.inventoryItemId)
        .firstOrNull;
    return selected == null ? '' : _labelFor(selected);
  }

  bool _hasAvailableStock(YorksV1InventoryItem item) =>
      YorksV1DecimalQuantity.tryParse(item.availableQuantity)?.isPositive ==
      true;

  String _labelFor(YorksV1InventoryItem item) {
    final identity = item.itemCode?.trim().isNotEmpty == true
        ? '${item.itemCode} · ${item.description}'
        : item.description;
    return identity;
  }

  List<YorksV1InventoryItem> _matches(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final requestedQuery = query.isEmpty
        ? widget.line.description.trim().toLowerCase()
        : query;
    final sameUnit = widget.inventoryItems
        .where(
          (item) =>
              item.unit.trim().toLowerCase() ==
              widget.line.unit.trim().toLowerCase(),
        )
        .toList(growable: false);
    sameUnit.sort((left, right) {
      final leftScore = _matchScore(left, requestedQuery);
      final rightScore = _matchScore(right, requestedQuery);
      if (leftScore != rightScore) return leftScore.compareTo(rightScore);
      return _labelFor(left).compareTo(_labelFor(right));
    });
    return sameUnit
        .where((item) => query.isEmpty || _matchScore(item, query) < 4)
        .take(8)
        .toList(growable: false);
  }

  int _matchScore(YorksV1InventoryItem item, String query) {
    if (query.isEmpty) return 5;
    final code = item.itemCode?.trim().toLowerCase() ?? '';
    final description = item.description.toLowerCase();
    final brand = item.brandOrigin?.toLowerCase() ?? '';
    if (code == query) return 0;
    if (code.startsWith(query) || description.startsWith(query)) return 1;
    if (description.contains(query)) return 2;
    if (brand.contains(query) || code.contains(query)) return 3;
    return 4;
  }

  String _inventoryItemContext(YorksV1InventoryItem item) => [
    '${YorksV1ArrangementStrings.available.primary}: ${yorksV1DisplayQuantity(item.availableQuantity)} ${item.unit}',
    item.locationBin?.trim().isNotEmpty == true
        ? '${YorksV1ArrangementStrings.shelfLocation.primary}: ${item.locationBin!.trim()}'
        : YorksV1ArrangementStrings.shelfLocationMissing.primary,
    if (item.brandOrigin?.trim().isNotEmpty == true) item.brandOrigin!,
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final selected = widget.inventoryItems
        .where((item) => item.id == widget.value.inventoryItemId)
        .firstOrNull;
    final selectedHasStock = selected != null && _hasAvailableStock(selected);
    final shelf = selected?.locationBin?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RawAutocomplete<YorksV1InventoryItem>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: _labelFor,
          optionsBuilder: (value) => _matches(value.text),
          onSelected: (item) {
            _controller.text = _labelFor(item);
            widget.onSelected(item);
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
              TextFormField(
                key: ValueKey(
                  'warehouse-search-${widget.value.arrangementLineId}',
                ),
                controller: controller,
                focusNode: focusNode,
                enabled: widget.enabled,
                onTap: () => setState(() {}),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.compact
                      ? null
                      : YorksV1ArrangementStrings.warehouseItem.primary,
                  hintText:
                      YorksV1ArrangementStrings.searchWarehouseItem.primary,
                  helperText:
                      controller.text.trim().isNotEmpty &&
                          controller.text != _selectedLabel &&
                          _matches(controller.text).isEmpty
                      ? YorksV1ArrangementStrings.noMatchingWarehouse.primary
                      : null,
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: widget.value.inventoryItemId == null
                      ? null
                      : Icon(
                          selectedHasStock
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: selectedHasStock
                              ? AppColors.muted
                              : AppColors.error,
                        ),
                  contentPadding: widget.compact
                      ? const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        )
                      : null,
                ),
              ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: AlignmentDirectional.topStart,
            child: Material(
              elevation: 8,
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 320,
                  maxWidth: 460,
                ),
                child: SizedBox(
                  width: 420,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    shrinkWrap: true,
                    children: [
                      for (final item in options)
                        ListTile(
                          enabled: _hasAvailableStock(item),
                          minTileHeight: AppSpacing.minTapTarget,
                          leading: Icon(
                            Icons.inventory_2_outlined,
                            color: _hasAvailableStock(item)
                                ? AppColors.blue
                                : AppColors.muted,
                          ),
                          title: Text(
                            item.itemCode?.trim().isNotEmpty == true
                                ? '${item.itemCode} · ${item.description}'
                                : item.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall,
                          ),
                          subtitle: Text(
                            _inventoryItemContext(item),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          onTap: _hasAvailableStock(item)
                              ? () => onSelected(item)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${YorksV1ArrangementStrings.available.primary}: ${yorksV1DisplayQuantity(selected.availableQuantity)} ${selected.unit}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            key: ValueKey('warehouse-shelf-${widget.value.arrangementLineId}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.ink,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  shelf?.isNotEmpty == true
                      ? '${YorksV1ArrangementStrings.shelfLocation.primary}: $shelf'
                      : YorksV1ArrangementStrings.shelfLocationMissing.primary,
                  style: AppTypography.bodySmall.copyWith(
                    color: shelf?.isNotEmpty == true
                        ? AppColors.ink
                        : AppColors.muted,
                    fontWeight: shelf?.isNotEmpty == true
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A deliberately small item-master handoff for Procurement arrangement.
/// It reuses the same server command as Warehouse Inventory and never adds a
/// balance unless Procurement provides an opening quantity with a reason.
class _ArrangementInventoryItemCreator extends ConsumerStatefulWidget {
  const _ArrangementInventoryItemCreator({
    required this.line,
    required this.inventory,
  });

  final YorksV1ArrangementLine line;
  final YorksV1InventoryWorkspace inventory;

  @override
  ConsumerState<_ArrangementInventoryItemCreator> createState() =>
      _ArrangementInventoryItemCreatorState();
}

class _ArrangementInventoryItemCreatorState
    extends ConsumerState<_ArrangementInventoryItemCreator> {
  late final TextEditingController _description;
  final _brand = TextEditingController();
  final _location = TextEditingController(text: 'Main Warehouse');
  final _opening = TextEditingController(text: '0');
  final _reason = TextEditingController();
  String? _categoryId;
  String? _newCategoryName;
  String? _sourceCategoryText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: widget.line.description);
    _brand.text = widget.line.brandOrigin ?? '';
  }

  @override
  void dispose() {
    _description.dispose();
    _brand.dispose();
    _location.dispose();
    _opening.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final compact = YorksMobileUi.isActive(context);
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YorksMobileCallout(
            icon: Icons.inventory_2_outlined,
            title: YorksV1ArrangementStrings.createInventoryItem.active(
              language,
            ),
            message: YorksV1ArrangementStrings.createInventoryItemHelp.active(
              language,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ArrangementFormField(
            fieldKey: const ValueKey('arrangement-new-inventory-description'),
            controller: _description,
            label: YorksV1LogisticsStrings.itemDescription.active(language),
            hint: YorksV1InventoryStrings.materialEquipmentDescription.active(
              language,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementReadOnlyFormField(
            label: YorksV1LogisticsStrings.unit.active(language),
            value: widget.line.unit,
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementFormField(
            controller: _brand,
            label: YorksV1LogisticsStrings.brandOrigin.active(language),
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementCategoryAutocomplete(
            categories: widget.inventory.categories,
            enabled: !_saving,
            language: language,
            onSelection: (categoryId, newCategoryName, sourceCategoryText) {
              setState(() {
                _categoryId = categoryId;
                _newCategoryName = newCategoryName;
                _sourceCategoryText = sourceCategoryText;
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementFormField(
            controller: _location,
            label: YorksV1InventoryStrings.location.active(language),
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementFormField(
            controller: _opening,
            label: YorksV1ArrangementStrings.openingBalanceOptional.active(
              language,
            ),
            numeric: true,
          ),
          const SizedBox(height: AppSpacing.md),
          _ArrangementFormField(
            controller: _reason,
            label: YorksV1ArrangementStrings.physicalStockReason.active(
              language,
            ),
            hint: _opening.text.trim() == '0'
                ? null
                : YorksV1LogisticsStrings.reason.active(language),
            lines: 3,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            YorksV1ArrangementStrings.createdItemHasNoAvailableStock.active(
              language,
            ),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    final body = PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Column(
          children: [
            _ArrangementCreatorHeader(
              title: YorksV1ArrangementStrings.createInventoryItem.active(
                language,
              ),
              subtitle: widget.line.description,
              onClose: _saving ? null : () => Navigator.of(context).pop(),
            ),
            Expanded(child: content),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SecondaryButton(
                    label: AppStrings.cancel.active(language),
                    isExpanded: false,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  PrimaryButton(
                    key: const ValueKey('arrangement-create-inventory-confirm'),
                    label: YorksV1ArrangementStrings.createInventoryItem.active(
                      language,
                    ),
                    isExpanded: false,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (compact) return Dialog.fullscreen(child: body);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height - 72,
        child: body,
      ),
    );
  }

  Future<void> _save() async {
    final opening = YorksV1DecimalQuantity.tryParse(_opening.text);
    if (_description.text.trim().isEmpty ||
        opening == null ||
        opening.isNegative ||
        (opening.isPositive && _reason.text.trim().isEmpty)) {
      _failure();
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .createInventoryItem(
            requestLineId: widget.line.requestLineId,
            input: YorksV1InventoryAdjustmentInput(
              description: _description.text,
              brandOrigin: _brand.text,
              unit: widget.line.unit,
              categoryId: _categoryId,
              newCategoryName: _newCategoryName,
              sourceCategoryText: _sourceCategoryText,
              locationBin: _location.text,
              quantityDelta: _opening.text,
              reason: _reason.text,
              // The controller replaces this placeholder with a persistent
              // fingerprinted retry identity before invoking the repository.
              idempotencyKey: '',
            ),
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (_) {
      if (mounted) _failure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _failure() => YorksAppToast.show(
    context,
    title: YorksV1InventoryStrings.savingFailed.active(
      ref.read(languageProvider),
    ),
    tone: YorksAppToastTone.error,
  );
}

class _ArrangementCreatorHeader extends StatelessWidget {
  const _ArrangementCreatorHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _ArrangementFormField extends StatelessWidget {
  const _ArrangementFormField({
    this.fieldKey,
    required this.controller,
    required this.label,
    this.hint,
    this.numeric = false,
    this.lines = 1,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool numeric;
  final int lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        key: fieldKey,
        controller: controller,
        maxLines: lines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );
}

class _ArrangementReadOnlyFormField extends StatelessWidget {
  const _ArrangementReadOnlyFormField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(initialValue: value, readOnly: true),
    ],
  );
}

class _ArrangementCategoryAutocomplete extends StatefulWidget {
  const _ArrangementCategoryAutocomplete({
    required this.categories,
    required this.enabled,
    required this.language,
    required this.onSelection,
  });

  final List<YorksV1InventoryCategory> categories;
  final bool enabled;
  final AppLanguage language;
  final void Function(
    String? categoryId,
    String? newCategoryName,
    String? sourceCategoryText,
  )
  onSelection;

  @override
  State<_ArrangementCategoryAutocomplete> createState() =>
      _ArrangementCategoryAutocompleteState();
}

class _ArrangementCategoryAutocompleteState
    extends State<_ArrangementCategoryAutocomplete> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _selectedId;
  bool _createNew = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<YorksV1InventoryCategory> get _matches {
    final query = _controller.text.trim().toLowerCase();
    return widget.categories
        .where(
          (category) =>
              category.isActive &&
              (query.isEmpty ||
                  [
                    category.displayPath,
                    ...category.aliases,
                  ].join(' ').toLowerCase().contains(query)),
        )
        .take(8)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final activeLanguage = widget.language;
    final query = _controller.text.trim();
    final showChoices = _focus.hasFocus && !_createNew;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1InventoryStrings.category.active(activeLanguage),
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          key: const ValueKey('arrangement-new-inventory-category'),
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          onChanged: (_) {
            setState(() {
              _selectedId = null;
              _createNew = false;
            });
            widget.onSelection(null, null, null);
          },
          decoration: InputDecoration(
            hintText: YorksV1InventoryStrings.typeCategory.active(
              activeLanguage,
            ),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _selectedId == null
                ? null
                : const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
          ),
        ),
        if (showChoices) ...[
          const SizedBox(height: AppSpacing.xs),
          Material(
            color: AppColors.surfaceContainerLowest,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              side: const BorderSide(color: AppColors.line),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 270),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.xs),
                children: [
                  for (final category in _matches)
                    ListTile(
                      minTileHeight: AppSpacing.minTapTarget,
                      leading: const Icon(
                        Icons.account_tree_outlined,
                        color: AppColors.blue,
                      ),
                      title: Text(
                        category.displayPath,
                        style: AppTypography.titleSmall,
                      ),
                      subtitle: Text(
                        '${category.itemCount} ${YorksV1InventoryStrings.items.active(activeLanguage)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      onTap: () => _select(category),
                    ),
                  if (query.isNotEmpty)
                    ListTile(
                      minTileHeight: AppSpacing.minTapTarget,
                      tileColor: AppColors.blueContainer.withValues(alpha: .4),
                      leading: const Icon(
                        Icons.add_rounded,
                        color: AppColors.blue,
                      ),
                      title: Text(
                        YorksV1ArrangementStrings.newParentCategory.active(
                          activeLanguage,
                        ),
                        style: AppTypography.titleSmall,
                      ),
                      subtitle: Text(
                        yorksV1InventoryCategoryDisplayName(query),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      onTap: _selectNewParent,
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_createNew)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              YorksV1ArrangementStrings.categoryRequiredForNewItem.active(
                activeLanguage,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
      ],
    );
  }

  void _select(YorksV1InventoryCategory category) {
    final sourceText = _controller.text.trim();
    setState(() {
      _selectedId = category.id;
      _createNew = false;
      _controller.text = category.displayPath;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    widget.onSelection(category.id, null, sourceText);
    _focus.unfocus();
  }

  void _selectNewParent() {
    final sourceText = _controller.text.trim();
    setState(() {
      _selectedId = null;
      _createNew = true;
    });
    widget.onSelection(
      null,
      yorksV1InventoryCategoryDisplayName(sourceText),
      sourceText,
    );
    _focus.unfocus();
  }
}

class _ExternalSourceReadinessFields extends StatelessWidget {
  const _ExternalSourceReadinessFields({
    required this.value,
    required this.enabled,
    required this.language,
    required this.requiredByPolicy,
    required this.onChanged,
  });

  final _EditableArrangementLine value;
  final bool enabled;
  final AppLanguage language;
  final bool requiredByPolicy;
  final ValueChanged<_EditableArrangementLine> onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.blueContainer.withValues(alpha: .42),
        border: Border.all(color: AppColors.blue.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              key: ValueKey('external-ready-${value.arrangementLineId}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: value.externalSourceReady,
              onChanged: !enabled
                  ? null
                  : (ready) => onChanged(
                      value.copyWith(externalSourceReady: ready == true),
                    ),
              title: Text(
                YorksV1ArrangementStrings.externalReadyConfirmed.active(
                  language,
                ),
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                (requiredByPolicy
                        ? YorksV1ArrangementStrings.externalReadinessRequired
                        : YorksV1ArrangementStrings
                              .externalReadinessRecommended)
                    .active(language),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackFields = constraints.maxWidth < 540;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      key: PageStorageKey(
                        'expected-scroll-${value.arrangementLineId}',
                      ),
                      width: stackFields ? constraints.maxWidth : 210,
                      child: TextFormField(
                        key: ValueKey(
                          'external-expected-${value.arrangementLineId}',
                        ),
                        initialValue: value.externalExpectedDate,
                        enabled: enabled,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: YorksV1ArrangementStrings
                              .expectedAvailabilityDate
                              .active(language),
                          hintText: YorksV1ArrangementStrings.dateFormatHint
                              .active(language),
                          prefixIcon: const Icon(Icons.event_outlined),
                        ),
                        onChanged: (text) => onChanged(
                          value.copyWith(
                            externalExpectedDate: _trimmedOrNull(text),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      key: PageStorageKey(
                        'reference-scroll-${value.arrangementLineId}',
                      ),
                      width: stackFields ? constraints.maxWidth : 300,
                      child: TextFormField(
                        key: ValueKey(
                          'external-reference-${value.arrangementLineId}',
                        ),
                        initialValue: value.externalReference,
                        enabled: enabled,
                        maxLength: 180,
                        decoration: InputDecoration(
                          labelText: YorksV1ArrangementStrings.supplierReference
                              .active(language),
                          prefixIcon: const Icon(Icons.link_rounded),
                          counterText: '',
                        ),
                        onChanged: (text) => onChanged(
                          value.copyWith(
                            externalReference: _trimmedOrNull(text),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
    if (requiredByPolicy) return fields;
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: PageStorageKey('external-details-${value.arrangementLineId}'),
        minTileHeight: AppSpacing.minTapTarget,
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded:
            value.externalSourceReady ||
            value.externalExpectedDate != null ||
            value.externalReference != null,
        maintainState: true,
        tilePadding: EdgeInsets.zero,
        title: Text(
          YorksV1ArrangementStrings.optionalAvailabilityDetails.active(
            language,
          ),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        children: [fields],
      ),
    );
  }
}

class _ReasonField extends StatelessWidget {
  const _ReasonField({
    required this.value,
    required this.controller,
    required this.enabled,
  });

  final _EditableArrangementLine value;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: TextFormField(
      key: ValueKey('reason-${value.arrangementLineId}'),
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: YorksV1ArrangementStrings.reason.primary,
      ),
    ),
  );
}

class _ArrangementReadOnly extends ConsumerWidget {
  const _ArrangementReadOnly({
    required this.arrangement,
    required this.language,
  });

  final YorksV1ProcurementArrangement arrangement;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showCommercials =
        ref.watch(canViewCommercialsProvider) &&
        arrangement.lines.any((line) => line.unitCost != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xxl,
          runSpacing: AppSpacing.md,
          children: [
            _Meta(
              label: YorksV1ArrangementStrings.version.primary,
              value: arrangement.version.toString(),
            ),
            _Meta(
              label: YorksV1ArrangementStrings.startedBy.primary,
              value: arrangement.startedByDisplayName,
            ),
            _Meta(
              label: YorksV1ArrangementStrings.decision.primary,
              value: yorksV1ArrangementStatusCopy(arrangement.status).primary,
            ),
          ],
        ),
        if (arrangement.reviewReason != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(arrangement.reviewReason!, style: AppTypography.bodyMedium),
        ],
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 760
              ? _ReadOnlyDesktopTable(
                  lines: arrangement.lines,
                  showCommercials: showCommercials,
                )
              : Column(
                  children: [
                    for (final line in arrangement.lines) ...[
                      _ReadOnlyLineCard(
                        line: line,
                        showCommercials: showCommercials,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ReadOnlyDesktopTable extends StatelessWidget {
  const _ReadOnlyDesktopTable({
    required this.lines,
    required this.showCommercials,
  });
  final List<YorksV1ArrangementLine> lines;
  final bool showCommercials;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: [
        DataColumn(label: Text(YorksV1ArrangementStrings.rowNumber.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.requested.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.decision.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.source.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.arranged.primary)),
        if (showCommercials)
          DataColumn(label: Text(YorksV1ArrangementStrings.unitCost.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.availability.primary)),
        DataColumn(label: Text(YorksV1ArrangementStrings.reason.primary)),
      ],
      rows: [
        for (final line in lines)
          DataRow(
            color: WidgetStatePropertyAll(_lineBackground(line)),
            cells: [
              DataCell(Text(line.displayOrder.toString())),
              DataCell(
                Text(
                  '${line.description}\n${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                ),
              ),
              DataCell(
                Text(
                  line.decision == null
                      ? ''
                      : yorksV1ArrangementDecisionCopy(line.decision!).primary,
                ),
              ),
              DataCell(Text(yorksV1ArrangementSourceCopy(line.source).primary)),
              DataCell(
                Text(yorksV1DisplayQuantity(line.arrangedQuantity ?? '')),
              ),
              if (showCommercials) DataCell(Text(line.unitCost ?? '')),
              DataCell(
                Text(
                  line.source == YorksV1ArrangementSource.warehouse
                      ? (line.warehouseAvailableAtSave ?? '')
                      : _externalSourceEvidenceText(line),
                ),
              ),
              DataCell(Text(line.reason ?? '')),
            ],
          ),
      ],
    ),
  );
}

class _ReadOnlyLineCard extends StatelessWidget {
  const _ReadOnlyLineCard({required this.line, required this.showCommercials});
  final YorksV1ArrangementLine line;
  final bool showCommercials;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: _lineBackground(line),
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${line.displayOrder}. ${line.description}',
          style: AppTypography.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${YorksV1ArrangementStrings.requested.primary}: ${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
        ),
        Text(
          '${YorksV1ArrangementStrings.arranged.primary}: ${yorksV1DisplayQuantity(line.arrangedQuantity ?? '')}',
        ),
        if (showCommercials && line.unitCost != null)
          Text(
            '${YorksV1ArrangementStrings.unitCost.primary}: ${line.unitCost}',
          ),
        Text(
          '${YorksV1ArrangementStrings.source.primary}: ${yorksV1ArrangementSourceCopy(line.source).primary}',
        ),
        if (line.source == YorksV1ArrangementSource.externalSupplier)
          Text(_externalSourceEvidenceText(line)),
        if (line.reason != null)
          Text('${YorksV1ArrangementStrings.reason.primary}: ${line.reason}'),
      ],
    ),
  );
}

String _externalSourceEvidenceText(YorksV1ArrangementLine line) => [
  line.externalSupplier,
  if (line.externalSourceReady)
    YorksV1ArrangementStrings.externalReadyConfirmed.primary,
  if (line.externalExpectedDate != null)
    line.externalExpectedDate!.toIso8601String().split('T').first,
  line.externalReference,
].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

Color _lineBackground(YorksV1ArrangementLine line) => switch (line.decision) {
  YorksV1ArrangementDecision.partial => AppColors.warningContainer,
  YorksV1ArrangementDecision.unavailable => AppColors.errorContainer,
  _ => Colors.transparent,
};

class _DecisionActions extends ConsumerStatefulWidget {
  const _DecisionActions({
    required this.workspace,
    required this.arrangement,
    required this.language,
  });

  final YorksV1ArrangementWorkspace workspace;
  final YorksV1ProcurementArrangement arrangement;
  final AppLanguage language;

  @override
  ConsumerState<_DecisionActions> createState() => _DecisionActionsState();
}

class _DecisionActionsState extends ConsumerState<_DecisionActions> {
  bool _busy = false;
  late String _approveIdempotencyKey;
  late String _returnIdempotencyKey;

  @override
  void initState() {
    super.initState();
    _approveIdempotencyKey = const Uuid().v4();
    _returnIdempotencyKey = const Uuid().v4();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      PrimaryButton(
        label: YorksV1ArrangementStrings.approveArrangement.primary,
        icon: Icons.verified_rounded,
        isExpanded: false,
        isLoading: _busy,
        onPressed: _busy
            ? null
            : () => _decide(YorksV1ArrangementReviewDecision.approved),
      ),
      SecondaryButton(
        label: YorksV1ArrangementStrings.returnToProcurement.primary,
        icon: Icons.reply_rounded,
        isExpanded: false,
        onPressed: _busy
            ? null
            : () => _decide(YorksV1ArrangementReviewDecision.returned),
      ),
    ],
  );

  Future<void> _decide(YorksV1ArrangementReviewDecision decision) async {
    String? reason;
    if (decision == YorksV1ArrangementReviewDecision.returned) {
      reason = await _returnReason(context);
      if (reason == null || reason.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .decideArrangement(
            YorksV1DecideArrangementInput(
              requestId: widget.workspace.requestId,
              arrangementId: widget.arrangement.id,
              expectedRequestVersion: widget.workspace.requestRecordVersion,
              expectedArrangementVersion: widget.arrangement.recordVersion,
              decision: decision,
              reason: reason,
              idempotencyKey:
                  decision == YorksV1ArrangementReviewDecision.approved
                  ? _approveIdempotencyKey
                  : _returnIdempotencyKey,
            ),
          );
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (decision == YorksV1ArrangementReviewDecision.approved) {
        _approveIdempotencyKey = const Uuid().v4();
      } else {
        _returnIdempotencyKey = const Uuid().v4();
      }
    } on YorksV1CommittedViewUnavailable {
      yorksV1InvalidateArrangementWorkspace(ref, widget.workspace.requestId);
      yorksV1InvalidateMaterialRequestDetail(ref, widget.workspace.requestId);
      ref.invalidate(yorksV1MaterialRequestListProvider);
    } on YorksV1CommandOutcomeUnknown {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.commandUnknown.active(
            widget.language,
          ),
          tone: YorksAppToastTone.information,
        );
      }
    } on YorksV1DomainException catch (error) {
      if (mounted) _showFailure(context, error);
    } catch (_) {
      if (mounted) _showFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ArrangementHistoryRow extends StatelessWidget {
  const _ArrangementHistoryRow({
    required this.arrangement,
    required this.language,
  });
  final YorksV1ProcurementArrangement arrangement;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.history_rounded),
    title: Text(
      '${YorksV1ArrangementStrings.version.primary} ${arrangement.version}',
    ),
    subtitle: Text(arrangement.startedByDisplayName),
    trailing: Text(yorksV1ArrangementStatusCopy(arrangement.status).primary),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: AppTypography.bodyMedium),
      ],
    ),
  );
}

class _ArrangementError extends StatelessWidget {
  const _ArrangementError({required this.language, required this.onRetry});
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: NexusSectionCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 40,
          ),
          const SizedBox(height: AppSpacing.md),
          _ActiveText(
            copy: YorksV1ArrangementStrings.savingFailed,
            language: language,
            center: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: YorksV1ArrangementStrings.arrangement.primary,
            icon: Icons.refresh_rounded,
            isExpanded: false,
            onPressed: onRetry,
          ),
        ],
      ),
    ),
  );
}

class _EditableArrangementLine {
  const _EditableArrangementLine({
    required this.arrangementLineId,
    required this.source,
    required this.requestedQuantity,
    required this.arrangedQuantity,
    this.externalSupplier,
    this.externalSourceReady = false,
    this.externalExpectedDate,
    this.externalReference,
    this.inventoryItemId,
    this.reason,
    this.unitCost,
  });

  final String arrangementLineId;
  final YorksV1ArrangementSource source;
  final String requestedQuantity;
  final String arrangedQuantity;
  YorksV1ArrangementDecision? get decision =>
      yorksV1ArrangementDecisionForQuantity(
        requestedQuantity: requestedQuantity,
        arrangedQuantity: arrangedQuantity,
      );
  final String? externalSupplier;
  final bool externalSourceReady;
  final String? externalExpectedDate;
  final String? externalReference;
  final String? inventoryItemId;
  final String? reason;
  final String? unitCost;

  factory _EditableArrangementLine.fromLine(
    YorksV1ArrangementLine line,
    List<YorksV1InventoryItem> inventory,
  ) {
    final matchingItem = yorksV1ArrangementInventoryMatch(line, inventory);
    final isFresh =
        line.decision == null &&
        line.arrangedQuantity == null &&
        line.inventoryItemId == null &&
        line.externalSupplier == null &&
        line.source == YorksV1ArrangementSource.warehouse;
    return _EditableArrangementLine(
      arrangementLineId: line.id,
      requestedQuantity: line.requestedQuantity,
      source: isFresh && matchingItem == null
          ? YorksV1ArrangementSource.externalSupplier
          : line.source,
      // This is an editable proposal only. Restored raw input overrides it;
      // committed projection quantities remain unchanged.
      arrangedQuantity: yorksV1DisplayQuantity(
        line.arrangedQuantity ??
            (line.decision == null ? line.requestedQuantity : ''),
      ),
      externalSupplier: line.externalSupplier,
      externalSourceReady: line.externalSourceReady,
      externalExpectedDate: line.externalExpectedDate
          ?.toIso8601String()
          .split('T')
          .first,
      externalReference: line.externalReference,
      inventoryItemId:
          line.inventoryItemId ?? (isFresh ? matchingItem?.id : null),
      reason: line.reason,
      unitCost: line.unitCost,
    );
  }

  _EditableArrangementLine copyWith({
    YorksV1ArrangementSource? source,
    String? arrangedQuantity,
    Object? externalSupplier = _keep,
    bool? externalSourceReady,
    Object? externalExpectedDate = _keep,
    Object? externalReference = _keep,
    Object? inventoryItemId = _keep,
    Object? reason = _keep,
    Object? unitCost = _keep,
  }) => _EditableArrangementLine(
    arrangementLineId: arrangementLineId,
    source: source ?? this.source,
    requestedQuantity: requestedQuantity,
    arrangedQuantity: arrangedQuantity ?? this.arrangedQuantity,
    externalSupplier: identical(externalSupplier, _keep)
        ? this.externalSupplier
        : externalSupplier as String?,
    externalSourceReady: externalSourceReady ?? this.externalSourceReady,
    externalExpectedDate: identical(externalExpectedDate, _keep)
        ? this.externalExpectedDate
        : externalExpectedDate as String?,
    externalReference: identical(externalReference, _keep)
        ? this.externalReference
        : externalReference as String?,
    inventoryItemId: identical(inventoryItemId, _keep)
        ? this.inventoryItemId
        : inventoryItemId as String?,
    reason: identical(reason, _keep) ? this.reason : reason as String?,
    unitCost: identical(unitCost, _keep) ? this.unitCost : unitCost as String?,
  );

  YorksV1ArrangementLineInput toInput() => YorksV1ArrangementLineInput(
    arrangementLineId: arrangementLineId,
    source: source,
    // Invalid raw input is rejected before command preparation. A wire value
    // is still required by this immutable command DTO.
    decision: decision ?? YorksV1ArrangementDecision.full,
    arrangedQuantity: arrangedQuantity,
    externalSupplier: decision == YorksV1ArrangementDecision.unavailable
        ? null
        : externalSupplier,
    externalSourceReady: externalSourceReady,
    externalExpectedDate: externalExpectedDate,
    externalReference: externalReference,
    inventoryItemId: decision == YorksV1ArrangementDecision.unavailable
        ? null
        : inventoryItemId,
    reason: reason,
    unitCost: decision == YorksV1ArrangementDecision.unavailable
        ? null
        : unitCost,
  );
}

const _keep = Object();

String? _trimmedOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<String?> _returnReason(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(YorksV1ArrangementStrings.returnToProcurement.primary),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: YorksV1ArrangementStrings.returnReason.primary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(YorksV1ArrangementStrings.returnToProcurement.primary),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void _showFailure(BuildContext context, [YorksV1DomainException? error]) =>
    _showMessage(
      context,
      error == null
          ? YorksV1ArrangementStrings.savingFailed.primary
          : error.code == YorksV1DomainErrorCode.insufficientStock
          ? YorksV1ArrangementStrings.stockChangedBeforeSave.primary
          : YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
    );

void _showMessage(BuildContext context, String message) =>
    YorksAppToast.show(context, title: message, tone: YorksAppToastTone.error);

class _ActiveText extends StatelessWidget {
  const _ActiveText({
    required this.copy,
    required this.language,
    this.style,
    this.center = false,
    this.maxLines,
    this.overflow,
  });

  final TranslatableString copy;
  final AppLanguage language;
  final TextStyle? style;
  final bool center;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
    copy.active(language),
    textAlign: center ? TextAlign.center : null,
    textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
    style: style,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class _ArrangementTiming extends StatelessWidget {
  const _ArrangementTiming({required this.workspace, required this.language});
  final YorksV1ArrangementWorkspace workspace;
  final AppLanguage language;
  @override
  Widget build(BuildContext context) {
    final urgent = workspace.timing == YorksV1MaterialRequestTiming.urgent;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              urgent
                  ? Icons.priority_high_rounded
                  : workspace.timing == YorksV1MaterialRequestTiming.scheduled
                  ? Icons.event_outlined
                  : Icons.schedule_outlined,
              size: 18,
              color: urgent ? AppColors.error : AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                '${yorksV1MaterialRequestTimingCopy(workspace.timing).active(language)}${workspace.scheduledDate == null ? '' : ' · ${MaterialLocalizations.of(context).formatMediumDate(workspace.scheduledDate!)}'}',
                style: AppTypography.labelLarge.copyWith(
                  color: urgent ? AppColors.error : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

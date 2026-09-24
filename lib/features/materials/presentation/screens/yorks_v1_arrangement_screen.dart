import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_arrangement.dart';
import '../../../../shared/models/yorks_v1_arrangement_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_workbook.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/permissions_provider.dart';
import '../../../../shared/providers/yorks_v1_arrangement_provider.dart';
import '../../../../shared/providers/yorks_v1_arrangement_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_material_workflow_command_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
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
        onRetry: () =>
            ref.invalidate(yorksV1ArrangementWorkspaceProvider(requestId)),
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
              YorksV1RequestInformationToolbar(
                request: requestValue,
                language: language,
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
                onPressed: () => ref.invalidate(
                  yorksV1ArrangementWorkspaceProvider(requestId),
                ),
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
                  onPressed: () => ref.invalidate(
                    yorksV1ArrangementWorkspaceProvider(requestId),
                  ),
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
                          onPressed: () => ref.invalidate(
                            yorksV1ArrangementWorkspaceProvider(
                              workspace.requestId,
                            ),
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
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      _idempotencyKey = const Uuid().v4();
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
  }

  @override
  void didUpdateWidget(covariant _ArrangementEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _canSave = widget.enabled;
    _canClarify = widget.canClarify;
    _clarificationReviewRequired = widget.workspace.clarificationReviewRequired;
    _requestRecordVersion = widget.workspace.requestRecordVersion;
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
    _disposeLineControllers();
    _procurementNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManageCommercials = ref.watch(canManageCommercialsProvider);
    if (widget.mobileFlow) {
      return PopScope(
        canPop: !_busy,
        child: _MobileArrangementFlow(
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
          enabled: _canSave,
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
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_clarificationReviewRequired) ...[
            _ClarificationReviewBanner(language: widget.language),
            const SizedBox(height: AppSpacing.md),
          ],
          _ArrangementOverview(lines: _lines.values.toList(growable: false)),
          const SizedBox(height: AppSpacing.md),
          const _ArrangementQuantityGuidance(),
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
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 980
                ? _DesktopArrangementEditor(
                    lines: _arrangement.lines,
                    drafts: _lines,
                    arrangedQuantities: _arrangedQuantities,
                    unitCosts: _unitCosts,
                    canManageCommercials: canManageCommercials,
                    suppliers: _suppliers,
                    reasons: _reasons,
                    inventoryItems: _inventoryItems,
                    enabled: _canSave && !_busy,
                    canClarify: _canClarify && !_busy,
                    onChanged: _replace,
                    onCreateInventoryItem: _createInventoryItem,
                    onEditItem: _editItem,
                    validationIssues: _validationIssues,
                    lineKeys: _lineKeys,
                    language: widget.language,
                    readinessRequired:
                        widget.workspace.externalSourceReadinessRequired,
                  )
                : Column(
                    children: [
                      for (final line in _arrangement.lines) ...[
                        _MobileArrangementEditor(
                          line: line,
                          draft: _lines[line.id]!,
                          arrangedQuantity: _arrangedQuantities[line.id]!,
                          unitCost: _unitCosts[line.id]!,
                          canManageCommercials: canManageCommercials,
                          supplier: _suppliers[line.id]!,
                          reason: _reasons[line.id]!,
                          inventoryItems: _inventoryItems,
                          enabled: _canSave && !_busy,
                          canClarify: _canClarify && !_busy,
                          onChanged: _replace,
                          onCreateInventoryItem: _createInventoryItem,
                          onEditItem: _editItem,
                          validationMessages:
                              _validationIssues[line.id] ?? const [],
                          language: widget.language,
                          readinessRequired:
                              widget.workspace.externalSourceReadinessRequired,
                          key: _lineKeys[line.id],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: PageStorageKey('arrangement-note-${_arrangement.id}'),
              initiallyExpanded: _procurementNote.text.trim().isNotEmpty,
              maintainState: true,
              tilePadding: EdgeInsets.zero,
              title: Text(
                YorksV1ArrangementStrings.procurementNote.primary,
                style: AppTypography.labelLarge,
              ),
              children: [
                TextFormField(
                  controller: _procurementNote,
                  enabled: _canSave && !_busy,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText:
                        YorksV1ArrangementStrings.procurementNoteHint.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (widget.onClose != null)
                  SecondaryButton(
                    label: AppStrings.cancel.primary,
                    isExpanded: false,
                    onPressed: _busy ? null : widget.onClose,
                  ),
                PrimaryButton(
                  label: YorksV1ArrangementStrings.saveForApproval.primary,
                  icon: Icons.send_rounded,
                  isExpanded: false,
                  isLoading: _busy,
                  onPressed: _busy || !_canSave ? null : _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _replace(_EditableArrangementLine value) {
    if (!_canSave) return;
    final previous = _lines[value.arrangementLineId];
    if (value.decision == YorksV1ArrangementDecision.unavailable &&
        previous?.decision != YorksV1ArrangementDecision.unavailable) {
      _arrangedQuantities[value.arrangementLineId]?.text = '0';
    }
    setState(() {
      _lines = {..._lines, value.arrangementLineId: value};
      _validationIssues = {..._validationIssues}
        ..remove(value.arrangementLineId);
    });
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
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
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

  Future<void> _save() async {
    if (_busy || !_canSave) return;
    final canManageCommercials = ref.read(canManageCommercialsProvider);
    final inputs = [
      for (final line in _lines.values)
        line
            .copyWith(
              arrangedQuantity:
                  _arrangedQuantities[line.arrangementLineId]!.text,
              externalSupplier: _trimmedOrNull(
                _suppliers[line.arrangementLineId]!.text,
              ),
              reason: _trimmedOrNull(_reasons[line.arrangementLineId]!.text),
              unitCost: canManageCommercials
                  ? _unitCosts[line.arrangementLineId]!.text
                  : null,
            )
            .toInput(),
    ];
    final validationIssues = _validateLines(inputs);
    if (validationIssues.isNotEmpty) {
      setState(() => _validationIssues = validationIssues);
      return;
    }
    var saved = false;
    setState(() => _busy = true);
    try {
      await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .saveArrangement(
            YorksV1SaveArrangementInput(
              requestId: widget.workspace.requestId,
              arrangementId: _arrangement.id,
              expectedRequestVersion: _requestRecordVersion,
              expectedArrangementVersion: _arrangement.recordVersion,
              lines: inputs,
              procurementNote: _procurementNote.text,
              idempotencyKey: _saveIdempotencyKey,
            ),
          );
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      _saveIdempotencyKey = const Uuid().v4();
      saved = true;
    } on YorksV1DomainException catch (error) {
      if (error.code == YorksV1DomainErrorCode.insufficientStock) {
        await _refreshInventoryAfterStockFailure();
      }
      if (mounted) _showFailure(context, error);
    } catch (_) {
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
        controller.addListener(
          () => _clearValidationForLine(line.arrangementLineId),
        );
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

    final reservedByInventoryItem = <String, YorksV1DecimalQuantity>{};
    final firstLineByInventoryItem = <String, YorksV1ArrangementLine>{};
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
        firstLineByInventoryItem.putIfAbsent(
          inventoryItemId,
          () => arrangedLine,
        );
      }
      if (line.source == YorksV1ArrangementSource.externalSupplier &&
          widget.workspace.externalSourceReadinessRequired &&
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
        final arrangedLine = firstLineByInventoryItem[entry.key]!;
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
            widget.lines.length,
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
    final inventoryItem = widget.inventoryItems
        .where((item) => item.id == draft.inventoryItemId)
        .firstOrNull;
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
                _MobileFieldLabel(
                  label: YorksV1ArrangementStrings.decision.active(
                    widget.language,
                  ),
                ),
                _MobileArrangementDecisionSelector(
                  selected: draft.decision,
                  enabled: widget.enabled && !widget.busy,
                  language: widget.language,
                  onSelected: (decision) => _selectDecision(draft, decision),
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
                          widget.workspace.externalSourceReadinessRequired,
                      onChanged: (value) {
                        widget.onChanged(value);
                        setState(() {});
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _QuantityField(
                          value: draft,
                          controller: widget.arrangedQuantities[line.id]!,
                          enabled: widget.enabled && !widget.busy,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MobileReadOnlyField(
                          label: YorksV1ArrangementStrings.available.active(
                            widget.language,
                          ),
                          value: inventoryItem == null
                              ? '—'
                              : '${yorksV1DisplayQuantity(inventoryItem.availableQuantity)} ${inventoryItem.unit}',
                        ),
                      ),
                    ],
                  ),
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

  void _selectDecision(
    _EditableArrangementLine draft,
    YorksV1ArrangementDecision decision,
  ) {
    widget.onChanged(
      draft.copyWith(
        decision: decision,
        arrangedQuantity: decision == YorksV1ArrangementDecision.unavailable
            ? '0'
            : draft.arrangedQuantity,
        inventoryItemId: decision == YorksV1ArrangementDecision.unavailable
            ? null
            : _keep,
        externalSupplier: decision == YorksV1ArrangementDecision.unavailable
            ? null
            : _keep,
        externalSourceReady: decision == YorksV1ArrangementDecision.unavailable
            ? false
            : null,
        externalExpectedDate: decision == YorksV1ArrangementDecision.unavailable
            ? null
            : _keep,
        externalReference: decision == YorksV1ArrangementDecision.unavailable
            ? null
            : _keep,
      ),
    );
    setState(() {});
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

class _MobileArrangementDecisionSelector extends StatelessWidget {
  const _MobileArrangementDecisionSelector({
    required this.selected,
    required this.enabled,
    required this.language,
    required this.onSelected,
  });

  final YorksV1ArrangementDecision selected;
  final bool enabled;
  final AppLanguage language;
  final ValueChanged<YorksV1ArrangementDecision> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: _option(YorksV1ArrangementDecision.full)),
          const SizedBox(width: 8),
          Expanded(child: _option(YorksV1ArrangementDecision.partial)),
        ],
      ),
      const SizedBox(height: 8),
      _option(YorksV1ArrangementDecision.unavailable),
    ],
  );

  Widget _option(YorksV1ArrangementDecision decision) {
    final isSelected = selected == decision;
    return Semantics(
      button: true,
      selected: isSelected,
      child: SizedBox(
        key: ValueKey('mobile-arrangement-decision-${decision.name}'),
        height: AppSpacing.minTapTarget,
        child: Material(
          color: isSelected
              ? AppColors.blueContainer
              : AppColors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: BorderSide(
              color: isSelected ? AppColors.blue : AppColors.line,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            onTap: enabled ? () => onSelected(decision) : null,
            child: Center(
              child: Text(
                yorksV1ArrangementDecisionCopy(decision).active(language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: isSelected ? AppColors.blue : AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

  final YorksV1ArrangementDecision decision;

  @override
  Widget build(BuildContext context) {
    final color = switch (decision) {
      YorksV1ArrangementDecision.full => AppColors.success,
      YorksV1ArrangementDecision.partial => AppColors.warning,
      YorksV1ArrangementDecision.unavailable => AppColors.error,
    };
    final background = switch (decision) {
      YorksV1ArrangementDecision.full => AppColors.successContainer,
      YorksV1ArrangementDecision.partial => AppColors.warningContainer,
      YorksV1ArrangementDecision.unavailable => AppColors.errorContainer,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        yorksV1ArrangementDecisionCopy(decision).primary,
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

class _MobileReadOnlyField extends StatelessWidget {
  const _MobileReadOnlyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MobileFieldLabel(label: label),
      Container(
        height: 56,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(value, style: AppTypography.bodyMedium),
      ),
    ],
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
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (decision == YorksV1ArrangementReviewDecision.approved) {
        _approveIdempotencyKey = const Uuid().v4();
      } else {
        _returnIdempotencyKey = const Uuid().v4();
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
      return SingleChildScrollView(
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
                _ArrangementTableHeader(showCommercials: canManageCommercials),
                for (final line in lines)
                  _ArrangementTableRow(
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
                    validationMessages: validationIssues[line.id] ?? const [],
                    language: language,
                    readinessRequired: readinessRequired,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ArrangementOverview extends StatelessWidget {
  const _ArrangementOverview({required this.lines});

  final List<_EditableArrangementLine> lines;

  @override
  Widget build(BuildContext context) {
    final full = lines
        .where((line) => line.decision == YorksV1ArrangementDecision.full)
        .length;
    final partial = lines
        .where((line) => line.decision == YorksV1ArrangementDecision.partial)
        .length;
    final unavailable = lines
        .where(
          (line) => line.decision == YorksV1ArrangementDecision.unavailable,
        )
        .length;
    final external = lines
        .where(
          (line) => line.source == YorksV1ArrangementSource.externalSupplier,
        )
        .length;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 980
              ? (constraints.maxWidth - AppSpacing.md * 4) / 5
              : constraints.maxWidth >= 560
              ? (constraints.maxWidth - AppSpacing.md * 2) / 3
              : constraints.maxWidth;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _ArrangementOverviewTile(
                width: width,
                label: YorksV1MaterialRequestStrings.items.primary,
                value: '${lines.length}',
                tone: AppColors.blue,
              ),
              _ArrangementOverviewTile(
                width: width,
                label: yorksV1ArrangementDecisionCopy(
                  YorksV1ArrangementDecision.full,
                ).primary,
                value: '$full',
                tone: AppColors.success,
              ),
              _ArrangementOverviewTile(
                width: width,
                label: yorksV1ArrangementDecisionCopy(
                  YorksV1ArrangementDecision.partial,
                ).primary,
                value: '$partial',
                tone: AppColors.warning,
              ),
              _ArrangementOverviewTile(
                width: width,
                label: yorksV1ArrangementDecisionCopy(
                  YorksV1ArrangementDecision.unavailable,
                ).primary,
                value: '$unavailable',
                tone: AppColors.error,
              ),
              _ArrangementOverviewTile(
                width: width,
                label: YorksV1ArrangementStrings.externalSupplier.primary,
                value: '$external',
                tone: AppColors.tertiary,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ArrangementOverviewTile extends StatelessWidget {
  const _ArrangementOverviewTile({
    required this.width,
    required this.label,
    required this.value,
    required this.tone,
  });

  final double width;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ArrangementQuantityGuidance extends StatelessWidget {
  const _ArrangementQuantityGuidance();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .42),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          color: AppColors.blue,
          size: 21,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            YorksV1ArrangementStrings.quantityRule.primary,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    ),
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
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Row(
      children: [
        _ArrangementTableHeading(
          YorksV1ArrangementStrings.requestedItem,
          flex: 30,
        ),
        _ArrangementTableHeading(YorksV1ArrangementStrings.decision, flex: 17),
        _ArrangementTableHeading(
          YorksV1ArrangementStrings.supplierSource,
          flex: 21,
        ),
        _ArrangementTableHeading(YorksV1ArrangementStrings.requested, flex: 10),
        _ArrangementTableHeading(YorksV1ArrangementStrings.arranged, flex: 10),
        if (showCommercials)
          const _ArrangementTableHeading(
            YorksV1ArrangementStrings.unitCost,
            flex: 12,
          ),
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
    final rowColor = switch (draft.decision) {
      YorksV1ArrangementDecision.full => AppColors.surfaceContainerLowest,
      YorksV1ArrangementDecision.partial =>
        AppColors.warningContainer.withValues(alpha: .32),
      YorksV1ArrangementDecision.unavailable =>
        AppColors.errorContainer.withValues(alpha: .28),
    };
    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 30,
                child: _ArrangementRequestedItem(
                  line: line,
                  language: language,
                  enabled: canClarify,
                  onEdit: () => onEditItem(line),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 17,
                child: _DecisionPicker(
                  value: draft,
                  enabled: enabled,
                  compact: true,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 21,
                child: _ArrangementSourceEditor(
                  line: line,
                  value: draft,
                  supplier: supplier,
                  inventoryItems: inventoryItems,
                  enabled: enabled,
                  onChanged: onChanged,
                  onCreateInventoryItem: onCreateInventoryItem,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 10,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${yorksV1DisplayQuantity(line.requestedQuantity)} ${line.unit}',
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 10,
                child: _QuantityField(
                  value: draft,
                  controller: arrangedQuantity,
                  enabled: enabled,
                  compact: true,
                ),
              ),
              if (showCommercials) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 12,
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
          if (reasonRequired) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReasonField(value: draft, controller: reason, enabled: enabled),
          ],
          if (draft.source == YorksV1ArrangementSource.externalSupplier &&
              draft.decision != YorksV1ArrangementDecision.unavailable) ...[
            const SizedBox(height: AppSpacing.sm),
            _ExternalSourceReadinessFields(
              value: draft,
              enabled: enabled,
              language: language,
              requiredByPolicy: readinessRequired,
              onChanged: onChanged,
            ),
          ],
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
        _DecisionPicker(value: draft, enabled: enabled, onChanged: onChanged),
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

class _DecisionPicker extends StatelessWidget {
  const _DecisionPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final _EditableArrangementLine value;
  final bool enabled;
  final ValueChanged<_EditableArrangementLine> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<YorksV1ArrangementDecision>(
        initialValue: value.decision,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: compact
              ? null
              : YorksV1ArrangementStrings.decision.primary,
          contentPadding: compact
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                )
              : null,
        ),
        items: [
          for (final decision in YorksV1ArrangementDecision.values)
            DropdownMenuItem(
              value: decision,
              child: Text(yorksV1ArrangementDecisionCopy(decision).primary),
            ),
        ],
        onChanged: !enabled
            ? null
            : (decision) {
                if (decision == null) return;
                onChanged(
                  value.copyWith(
                    decision: decision,
                    arrangedQuantity:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? '0'
                        : value.arrangedQuantity,
                    inventoryItemId:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? null
                        : _keep,
                    externalSupplier:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? null
                        : _keep,
                    externalSourceReady:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? false
                        : null,
                    externalExpectedDate:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? null
                        : _keep,
                    externalReference:
                        decision == YorksV1ArrangementDecision.unavailable
                        ? null
                        : _keep,
                  ),
                );
              },
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
    width: 112,
    child: TextFormField(
      key: ValueKey(
        'arranged-${value.arrangementLineId}-${value.decision.wireValue}',
      ),
      controller: controller,
      enabled:
          enabled && value.decision != YorksV1ArrangementDecision.unavailable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: compact ? null : YorksV1ArrangementStrings.arranged.primary,
        contentPadding: compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
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
      key: ValueKey(
        'unit-cost-${value.arrangementLineId}-${value.decision.wireValue}',
      ),
      controller: controller,
      enabled:
          enabled && value.decision != YorksV1ArrangementDecision.unavailable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: compact ? null : YorksV1ArrangementStrings.unitCost.primary,
        contentPadding: compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
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
                'supplier-${widget.value.arrangementLineId}-${widget.value.source.wireValue}-${widget.value.decision.wireValue}',
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
    return '$identity · ${yorksV1DisplayQuantity(item.availableQuantity)} ${item.unit}';
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
    return sameUnit.take(8).toList(growable: false);
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

  @override
  Widget build(BuildContext context) {
    final selected = widget.inventoryItems
        .where((item) => item.id == widget.value.inventoryItemId)
        .firstOrNull;
    final selectedHasStock = selected != null && _hasAvailableStock(selected);
    return RawAutocomplete<YorksV1InventoryItem>(
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
            key: ValueKey('warehouse-search-${widget.value.arrangementLineId}'),
            controller: controller,
            focusNode: focusNode,
            enabled: widget.enabled,
            onTap: () => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.compact
                  ? null
                  : YorksV1ArrangementStrings.warehouseItem.primary,
              hintText: YorksV1ArrangementStrings.searchWarehouseItem.primary,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: widget.value.inventoryItemId == null
                  ? null
                  : Icon(
                      selectedHasStock
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: selectedHasStock
                          ? AppColors.success
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
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 460),
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
                        '${YorksV1ArrangementStrings.available.primary}: ${yorksV1DisplayQuantity(item.availableQuantity)} ${item.unit}${item.brandOrigin?.trim().isNotEmpty == true ? ' · ${item.brandOrigin}' : ''}',
                        maxLines: 1,
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
      key: ValueKey(
        'reason-${value.arrangementLineId}-${value.decision.wireValue}',
      ),
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
      ref.invalidate(
        yorksV1ArrangementWorkspaceProvider(widget.workspace.requestId),
      );
      ref.invalidate(
        yorksV1MaterialRequestDetailProvider(widget.workspace.requestId),
      );
      ref.invalidate(yorksV1MaterialRequestListProvider);
      if (decision == YorksV1ArrangementReviewDecision.approved) {
        _approveIdempotencyKey = const Uuid().v4();
      } else {
        _returnIdempotencyKey = const Uuid().v4();
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
    required this.decision,
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
  final YorksV1ArrangementDecision decision;
  final String arrangedQuantity;
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
    final matchingItem = inventory.where(
      (item) =>
          item.unit == line.unit &&
          item.description == line.description &&
          YorksV1DecimalQuantity.tryParse(item.availableQuantity)?.isPositive ==
              true,
    );
    return _EditableArrangementLine(
      arrangementLineId: line.id,
      // A fresh deployment may not have warehouse opening stock yet. Choosing
      // Warehouse in that state makes a valid arrangement impossible because
      // every non-unavailable line must reserve a real item. Default to the
      // explicit external-supplier route instead. The supplier name is useful
      // context when known but remains optional in the approved V1 workflow.
      source: line.inventoryItemId == null && inventory.isEmpty
          ? YorksV1ArrangementSource.externalSupplier
          : line.source,
      decision: line.decision ?? YorksV1ArrangementDecision.full,
      arrangedQuantity: yorksV1DisplayQuantity(
        line.arrangedQuantity ?? line.requestedQuantity,
      ),
      externalSupplier: line.externalSupplier,
      externalSourceReady: line.externalSourceReady,
      externalExpectedDate: line.externalExpectedDate
          ?.toIso8601String()
          .split('T')
          .first,
      externalReference: line.externalReference,
      inventoryItemId:
          line.inventoryItemId ??
          (matchingItem.isEmpty ? null : matchingItem.first.id),
      reason: line.reason,
      unitCost: line.unitCost,
    );
  }

  _EditableArrangementLine copyWith({
    YorksV1ArrangementSource? source,
    YorksV1ArrangementDecision? decision,
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
    decision: decision ?? this.decision,
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
    decision: decision,
    arrangedQuantity: arrangedQuantity,
    externalSupplier: externalSupplier,
    externalSourceReady: externalSourceReady,
    externalExpectedDate: externalExpectedDate,
    externalReference: externalReference,
    inventoryItemId: inventoryItemId,
    reason: reason,
    unitCost: unitCost,
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

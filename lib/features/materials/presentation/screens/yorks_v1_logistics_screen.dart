import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_dispatch_preparation.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_material_request_document.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_procurement_progress_provider.dart';
import '../../../../shared/widgets/yorks_v1_procurement_progress_panel.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_material_request_provider.dart';
import '../../../../shared/providers/yorks_v1_material_workflow_command_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/services/yorks_v1_logistics_document_service.dart';
import '../../../../shared/services/yorks_v1_procurement_unload_guard.dart';
import '../../../../shared/sync/connectivity_service.dart';
import '../../../../shared/services/yorks_v1_material_request_document_service.dart';
import '../yorks_v1_feature_action_access.dart';
import '../widgets/yorks_v1_request_information.dart';

/// Role-aware request logistics. Server-derived action flags distinguish the
/// Procurement dispatch form from Project/Site Engineer receipt review.
class YorksV1LogisticsScreen extends ConsumerWidget {
  const YorksV1LogisticsScreen({
    super.key,
    required this.requestId,
    this.focusReceiptReview = false,
    this.focusedDispatchId,
    this.initialDispatchDate,
  });

  final String requestId;

  /// Opens the supplied dispatched delivery in the R35 receipt-review dialog.
  /// This lets the Material Request remain the primary workflow surface while
  /// still using the protected logistics command for the receipt commit.
  final bool focusReceiptReview;
  final String? focusedDispatchId;

  /// Allows a caller restoring a partially prepared dispatch to retain the
  /// intended date. Normal workflow starts with today's date.
  final DateTime? initialDispatchDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final workspace = ref.watch(yorksV1LogisticsWorkspaceProvider(requestId));
    final requestDetail = ref.watch(
      yorksV1MaterialRequestDetailProvider(requestId),
    );
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final mobile = YorksMobileUi.isActive(context);
    final compactRoute =
        !mobile &&
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    final content = workspace.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _LogisticsError(onRetry: () => _refresh(ref)),
      data: (value) {
        final canReadRequest = yorksV1CanReadProjectRecord(
          permissionState,
          YorksV1CapabilityKeys.materialRequestsView,
          legacyAllowed: true,
          projectId: value.projectId,
        );
        final dispatchAccess = yorksV1FeatureActionAccess(
          permissionState,
          YorksV1CapabilityKeys.dispatchCreate,
          legacyAllowed: value.canDispatch,
          projectId: value.projectId,
        );
        final receiptAccess = yorksV1FeatureActionAccess(
          permissionState,
          YorksV1CapabilityKeys.receiptsConfirm,
          legacyAllowed: value.dispatches.any(
            (dispatch) => dispatch.canConfirmReceipt,
          ),
          projectId: value.projectId,
        );
        final focusedBody = _FocusedLogisticsBody(
          workspace: value,
          language: language,
          onChanged: () => _refresh(ref),
          showPageHeader: !compactRoute && !mobile,
          showDispatch: dispatchAccess.isVisible,
          canDispatch: dispatchAccess.canWrite,
          showReceiptReview: receiptAccess.isVisible,
          canConfirmReceipt: receiptAccess.canWrite,
          focusReceiptReview: focusReceiptReview,
          focusedDispatchId: focusedDispatchId,
          initialDispatchDate: initialDispatchDate,
        );
        final requestValue = requestDetail.valueOrNull;
        return YorksV1ProjectReadBoundary(
          allowed: canReadRequest,
          language: language,
          child: requestValue == null
              ? focusedBody
              : Column(
                  children: [
                    YorksV1RequestInformationToolbar(
                      request: requestValue,
                      language: language,
                    ),
                    Expanded(child: focusedBody),
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
              title: workspace.valueOrNull?.canDispatch == true
                  ? YorksV1LogisticsStrings.createDispatch.active(language)
                  : YorksV1LogisticsStrings.dispatchAndReceipt.active(language),
              leading: YorksMobileIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              trailing: YorksMobileIconButton(
                icon: Icons.refresh_rounded,
                tooltip: YorksV1LogisticsStrings.refresh.active(language),
                onPressed: () => _refresh(ref),
              ),
            ),
            Expanded(child: content),
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
                copy: YorksV1LogisticsStrings.dispatchAndReceipt,
                language: language,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: YorksV1LogisticsStrings.refresh.primary,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _refresh(ref),
                ),
              ],
            )
          : null,
      body: content,
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(yorksV1LogisticsWorkspaceProvider(requestId));
    // The request detail remains mounted while Procurement opens this route.
    // A committed dispatch is immediately a Delivery Order candidate, so its
    // role-safe documents projection must be refreshed before the user
    // returns to the detail page. Receipt review is a later, independent
    // workflow fact and is not required for this refresh.
    ref.invalidate(yorksV1ReturnsDocumentsWorkspaceProvider(requestId));
    yorksV1InvalidateMaterialRequestDetail(ref, requestId);
  }
}

class _FocusedLogisticsBody extends StatefulWidget {
  const _FocusedLogisticsBody({
    required this.workspace,
    required this.language,
    required this.onChanged,
    required this.showPageHeader,
    required this.showDispatch,
    required this.canDispatch,
    required this.showReceiptReview,
    required this.canConfirmReceipt,
    required this.focusReceiptReview,
    required this.focusedDispatchId,
    required this.initialDispatchDate,
  });

  final YorksV1LogisticsWorkspace workspace;
  final AppLanguage language;
  final VoidCallback onChanged;
  final bool showPageHeader;
  final bool showDispatch;
  final bool canDispatch;
  final bool showReceiptReview;
  final bool canConfirmReceipt;
  final bool focusReceiptReview;
  final String? focusedDispatchId;
  final DateTime? initialDispatchDate;

  @override
  State<_FocusedLogisticsBody> createState() => _FocusedLogisticsBodyState();
}

class _FocusedLogisticsBodyState extends State<_FocusedLogisticsBody> {
  bool _focusHandled = false;

  @override
  void initState() {
    super.initState();
    _scheduleFocusedReceiptReview();
  }

  @override
  void didUpdateWidget(covariant _FocusedLogisticsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusReceiptReview != widget.focusReceiptReview ||
        oldWidget.focusedDispatchId != widget.focusedDispatchId) {
      _focusHandled = false;
    }
    _scheduleFocusedReceiptReview();
  }

  void _scheduleFocusedReceiptReview() {
    if (!widget.focusReceiptReview || _focusHandled) return;
    _focusHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      YorksV1MaterialDispatch? target;
      for (final dispatch in widget.workspace.dispatches) {
        if (widget.focusedDispatchId == dispatch.id) {
          target = dispatch;
          break;
        }
      }
      if (target == null ||
          !target.canConfirmReceipt ||
          !widget.canConfirmReceipt) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.recordChanged.primary,
          tone: YorksAppToastTone.error,
        );
        return;
      }
      final confirmed = await showYorksV1ReceiptReviewDialog(
        context,
        workspace: widget.workspace,
        dispatch: target,
        onChanged: widget.onChanged,
      );
      if (confirmed == true && mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _LogisticsBody(
    workspace: widget.workspace,
    language: widget.language,
    onChanged: widget.onChanged,
    showPageHeader: widget.showPageHeader,
    showDispatch: widget.showDispatch,
    canDispatch: widget.canDispatch,
    showReceiptReview: widget.showReceiptReview,
    canConfirmReceipt: widget.canConfirmReceipt,
    initialDispatchDate: widget.initialDispatchDate,
  );
}

class _LogisticsBody extends StatelessWidget {
  const _LogisticsBody({
    required this.workspace,
    required this.language,
    required this.onChanged,
    required this.showPageHeader,
    required this.showDispatch,
    required this.canDispatch,
    required this.showReceiptReview,
    required this.canConfirmReceipt,
    required this.initialDispatchDate,
  });

  final YorksV1LogisticsWorkspace workspace;
  final AppLanguage language;
  final VoidCallback onChanged;
  final bool showPageHeader;
  final bool showDispatch;
  final bool canDispatch;
  final bool showReceiptReview;
  final bool canConfirmReceipt;
  final DateTime? initialDispatchDate;

  @override
  Widget build(BuildContext context) {
    if (YorksMobileUi.isActive(context) ||
        MediaQuery.sizeOf(context).width < 720) {
      if (showDispatch) {
        return _DispatchEditor(
          workspace: workspace,
          onChanged: onChanged,
          enabled: canDispatch,
          mobileFlow: true,
          initialDispatchDate: initialDispatchDate,
        );
      }
      return _MobileDispatchHistory(
        workspace: workspace,
        onChanged: onChanged,
        showReceiptReview: showReceiptReview,
        canConfirmReceipt: canConfirmReceipt,
      );
    }
    if (showDispatch) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YorksV1LogisticsStrings.prepareDispatch.active(
                            language,
                          ),
                          style: AppTypography.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${workspace.requestNumber ?? ''} · ${workspace.projectName} · ${workspace.scopeName}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (workspace.dispatches.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => Dialog(
                          child: SizedBox(
                            width: 1000,
                            height: 640,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          YorksV1LogisticsStrings
                                              .dispatchHistory
                                              .active(language),
                                          style: AppTypography.titleMedium,
                                        ),
                                      ),
                                      CloseButton(),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    children: [
                                      for (final dispatch
                                          in workspace.dispatches)
                                        _DispatchCard(
                                          dispatch: dispatch,
                                          workspace: workspace,
                                          onChanged: onChanged,
                                          showReceiptReview: showReceiptReview,
                                          canConfirmReceipt: canConfirmReceipt,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: Text(
                        YorksV1LogisticsStrings.dispatchHistoryOpen.active(
                          language,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _DispatchEditor(
                  workspace: workspace,
                  onChanged: onChanged,
                  enabled: canDispatch,
                  initialDispatchDate: initialDispatchDate,
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
                    title: YorksV1LogisticsStrings.dispatchAndReceipt.primary,
                    description:
                        YorksV1LogisticsStrings.dispatchHistory.primary,
                    actions: [
                      SizedBox(
                        height: AppSpacing.controlHeight,
                        child: OutlinedButton.icon(
                          onPressed: onChanged,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(YorksV1LogisticsStrings.refresh.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                _WorkspaceHeader(workspace: workspace),
                const SizedBox(height: AppSpacing.lg),
                if (showDispatch) ...[
                  NexusSectionCard(
                    title: YorksV1LogisticsStrings.dispatchNow.primary,
                    child: _DispatchEditor(
                      workspace: workspace,
                      onChanged: onChanged,
                      enabled: canDispatch,
                      initialDispatchDate: initialDispatchDate,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                NexusSectionCard(
                  title: YorksV1LogisticsStrings.dispatchHistory.primary,
                  child: workspace.dispatches.isEmpty
                      ? _ActiveText(
                          copy: YorksV1LogisticsStrings.noDispatch,
                          language: language,
                          center: true,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.muted,
                          ),
                        )
                      : Column(
                          children: [
                            for (final dispatch in workspace.dispatches)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _DispatchCard(
                                  dispatch: dispatch,
                                  workspace: workspace,
                                  onChanged: onChanged,
                                  showReceiptReview: showReceiptReview,
                                  canConfirmReceipt: canConfirmReceipt,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileDispatchHistory extends ConsumerWidget {
  const _MobileDispatchHistory({
    required this.workspace,
    required this.onChanged,
    required this.showReceiptReview,
    required this.canConfirmReceipt,
  });

  final YorksV1LogisticsWorkspace workspace;
  final VoidCallback onChanged;
  final bool showReceiptReview;
  final bool canConfirmReceipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final document = ref
        .watch(yorksV1MaterialRequestDocumentProvider(workspace.requestId))
        .valueOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
      children: [
        YorksMobilePageTitle(
          eyebrow: workspace.requestNumber ?? '',
          title: YorksV1LogisticsStrings.dispatchAndReceipt.active(language),
          description: YorksV1LogisticsStrings.dispatchHistory.active(language),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: OutlinedButton.icon(
            key: const ValueKey('mobile-dispatch-print-material-request'),
            onPressed: document == null
                ? null
                : () => _printMaterialRequest(context, document),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(
              YorksV1LogisticsStrings.printMaterialRequest.active(language),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (workspace.dispatches.isEmpty)
          YorksMobileCard(
            child: Text(
              YorksV1LogisticsStrings.noDispatch.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
          )
        else
          for (final dispatch in workspace.dispatches) ...[
            _DispatchCard(
              dispatch: dispatch,
              workspace: workspace,
              onChanged: onChanged,
              showReceiptReview: showReceiptReview,
              canConfirmReceipt: canConfirmReceipt,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Future<void> _printMaterialRequest(
    BuildContext context,
    YorksV1MaterialRequestDocumentModel document,
  ) async {
    try {
      await const YorksV1MaterialRequestDocumentService().printDocumentPdf(
        document,
      );
    } catch (_) {
      if (!context.mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.savingFailed.primary,
        tone: YorksAppToastTone.error,
      );
    }
  }
}

class _WorkspaceHeader extends ConsumerWidget {
  const _WorkspaceHeader({required this.workspace});
  final YorksV1LogisticsWorkspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final document = ref
        .watch(yorksV1MaterialRequestDocumentProvider(workspace.requestId))
        .valueOrNull;
    return NexusSectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final facts = Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.md,
            children: [
              _Fact(
                label: YorksV1MaterialRequestStrings.materialRequest.active(
                  language,
                ),
                value: workspace.requestNumber ?? '',
              ),
              _Fact(
                label: YorksV1LogisticsStrings.project.active(language),
                value: workspace.projectName,
              ),
              _Fact(
                label: YorksV1LogisticsStrings.scope.active(language),
                value: workspace.scopeName,
              ),
            ],
          );
          final print = SizedBox(
            height: AppSpacing.minTapTarget,
            child: OutlinedButton.icon(
              key: const ValueKey('dispatch-print-material-request'),
              onPressed: document == null
                  ? null
                  : () => _printMaterialRequest(context, document),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(
                YorksV1LogisticsStrings.printMaterialRequest.active(language),
              ),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                facts,
                const SizedBox(height: AppSpacing.md),
                print,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: facts),
              const SizedBox(width: AppSpacing.lg),
              print,
            ],
          );
        },
      ),
    );
  }

  Future<void> _printMaterialRequest(
    BuildContext context,
    YorksV1MaterialRequestDocumentModel document,
  ) async {
    try {
      await const YorksV1MaterialRequestDocumentService().printDocumentPdf(
        document,
      );
    } catch (_) {
      if (!context.mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.savingFailed.primary,
        tone: YorksAppToastTone.error,
      );
    }
  }
}

class _DispatchEditor extends ConsumerStatefulWidget {
  const _DispatchEditor({
    required this.workspace,
    required this.onChanged,
    required this.enabled,
    this.mobileFlow = false,
    this.initialDispatchDate,
  });

  final YorksV1LogisticsWorkspace workspace;
  final VoidCallback onChanged;
  final bool enabled;
  final bool mobileFlow;
  final DateTime? initialDispatchDate;

  @override
  ConsumerState<_DispatchEditor> createState() => _DispatchEditorState();
}

class _DispatchEditorState extends ConsumerState<_DispatchEditor> {
  final _deliveryReference = TextEditingController();
  final _driver = TextEditingController();
  final _vehicle = TextEditingController();
  final Map<String, TextEditingController> _quantities = {};
  late String _commandIdempotencyKey;
  late DateTime _dispatchDate;
  bool _reviewOpen = false;
  bool _saving = false;
  bool _restoring = false, _allowPop = false, _committed = false;
  final _unloadGuard = createYorksV1ProcurementUnloadGuard();
  late int _baseRequestVersion;
  YorksV1ProcurementProgressController? _progress;
  late final YorksV1ProcurementExitGuard _exitGuard;
  YorksV1ProcurementProgressScope get _scope => YorksV1ProcurementProgressScope(
    requestId: widget.workspace.requestId,
    editorKind: YorksV1ProcurementEditorKind.dispatch,
  );
  bool get _editable =>
      widget.enabled && !_saving && (_progress?.state.canEdit ?? false);

  Map<String, YorksV1DispatchQuantityIssue> _quantityErrors = {};
  String t(TranslatableString text) => text.active(ref.read(languageProvider));

  @override
  void initState() {
    super.initState();
    _dispatchDate = widget.initialDispatchDate ?? DateTime.now();
    _commandIdempotencyKey = const Uuid().v4();
    _baseRequestVersion = widget.workspace.requestRecordVersion;
    _syncControllers();
    for (final controller in [_deliveryReference, _driver, _vehicle]) {
      controller.addListener(_inputChanged);
    }
    _exitGuard = ref.read(yorksV1ProcurementExitGuardProvider);
    _exitGuard.check = _canLeave;
    _exitGuard.beforeNavigation = _canLeave;
    HardwareKeyboard.instance.addHandler(_keyboard);
  }

  @override
  void didUpdateWidget(covariant _DispatchEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.requestRecordVersion !=
        widget.workspace.requestRecordVersion) {
      // Keep the immutable edit base and raw input until explicit reload.
      Future<void>.microtask(() {
        if (mounted && _committed) {
          unawaited(_reloadProgress());
        } else if (mounted) {
          _progress?.observeLiveBase(
            _snapshot(baseVersion: widget.workspace.requestRecordVersion),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyboard);
    if (_exitGuard.check == _canLeave) {
      _exitGuard.check = null;
      _exitGuard.beforeNavigation = null;
    }
    _progress?.removeListener(_progressChanged);
    if (!_committed) unawaited(_progress?.flushRecovery());
    _unloadGuard.dispose();
    _deliveryReference.dispose();
    _driver.dispose();
    _vehicle.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final ids = widget.workspace.dispatchCandidates
        .map((candidate) => candidate.requestLineId)
        .toSet();
    for (final entry in Map<String, TextEditingController>.from(
      _quantities,
    ).entries) {
      if (!ids.contains(entry.key)) {
        entry.value.dispose();
        _quantities.remove(entry.key);
      }
    }
    final suggestions = YorksV1DispatchPreparation.suggest(
      widget.workspace.dispatchCandidates,
    );
    for (final candidate in widget.workspace.dispatchCandidates) {
      if (_quantities.containsKey(candidate.requestLineId)) continue;
      _quantities[candidate.requestLineId] = TextEditingController(
        text: suggestions[candidate.requestLineId] ?? '',
      )..addListener(_inputChanged);
    }
  }

  YorksV1ProcurementProgressDraft _snapshot({int? baseVersion}) =>
      YorksV1ProcurementProgressDraft(
        requestId: widget.workspace.requestId,
        editorKind: YorksV1ProcurementEditorKind.dispatch,
        baseRequestVersion: baseVersion ?? _baseRequestVersion,
        inputs: {
          'dispatch_date': _dispatchDate.toIso8601String().split('T').first,
          'delivery_reference': _deliveryReference.text,
          'driver_name': _driver.text,
          'vehicle_reference': _vehicle.text,
          'lines': [
            for (final entry in _quantities.entries)
              {'request_line_id': entry.key, 'dispatch_qty': entry.value.text},
          ],
        },
      );

  void _inputChanged() {
    if (_restoring || !mounted) return;
    _progress?.update(_snapshot());
    setState(() {
      _quantityErrors = {};
    });
  }

  void _progressChanged() {
    if (!mounted) return;
    if (_progress?.state.outcome?.isConfirmed == true && !_committed) {
      unawaited(
        Future<void>.microtask(() async {
          if (mounted) await _confirmedRecovery();
        }),
      );
    }
    _unloadGuard.setActive(
      _progress?.state.isDirty == true || _progress?.state.isPending == true,
    );
    final current = _progress?.state.current;
    if (current != null &&
        current.fingerprint != _snapshot().fingerprint &&
        !_progress!.state.isLoading) {
      _restoring = true;
      _deliveryReference.text =
          current.inputs['delivery_reference'] as String? ?? '';
      _driver.text = current.inputs['driver_name'] as String? ?? '';
      _vehicle.text = current.inputs['vehicle_reference'] as String? ?? '';
      _dispatchDate =
          DateTime.tryParse(current.inputs['dispatch_date'] as String? ?? '') ??
          _dispatchDate;
      final quantities = {
        for (final line in current.inputs['lines'] as List)
          (line as Map)['request_line_id'] as String:
              line['dispatch_qty'] as String? ?? '',
      };
      for (final entry in _quantities.entries) {
        entry.value.text = quantities[entry.key] ?? '';
      }
      _restoring = false;
    }
    setState(() {});
  }

  void _bindProgress(YorksV1ProcurementProgressController controller) {
    if (identical(_progress, controller)) return;
    _progress?.removeListener(_progressChanged);
    _progress = controller;
    controller.addListener(_progressChanged);
    Future<void>.microtask(() async {
      if (mounted) await controller.initialize(_snapshot());
    });
  }

  Future<bool> _canLeave() async {
    if (_saving) return false;
    final progress = _progress;
    if (progress == null) return true;
    progress.update(_snapshot());
    return confirmYorksV1ProcurementLeave(
      context,
      controller: progress,
      language: ref.read(languageProvider),
      isOnline: ref.read(connectivityProvider).isOnline,
    );
  }

  bool _keyboard(KeyEvent event) {
    if (event is! KeyDownEvent || !_editable) return false;
    if ((HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyS) {
      unawaited(_saveProgress());
      return true;
    }
    return false;
  }

  Future<void> _saveProgress() async {
    _progress?.update(_snapshot());
    await _progress?.saveProgress();
  }

  Future<void> _reloadProgress() async {
    final progress = _progress;
    if (progress == null || progress.state.isPending) return;
    _baseRequestVersion = widget.workspace.requestRecordVersion;
    _restoring = true;
    _deliveryReference.clear();
    _driver.clear();
    _vehicle.clear();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _quantities.clear();
    _syncControllers();
    _restoring = false;
    await progress.reload(_snapshot());
    _committed = false;
    if (mounted) setState(() {});
  }

  Widget _progressPanel() => YorksV1ProcurementProgressPanel(
    controller: _progress!,
    language: ref.watch(languageProvider),
    onRetryPending: _retryPending,
    onReload: () => unawaited(_reloadProgress()),
    onConfirmed: () => unawaited(_confirmedRecovery()),
    onCommandAbandoned: (command) => ref
        .read(yorksV1MaterialWorkflowCommandControllerProvider)
        .releaseRejectedPreparedCommand(
          operation: 'dispatch_materials',
          entityId: widget.workspace.requestId,
          idempotencyKey: command.commandKey,
        ),
  );

  Future<void> _confirmedRecovery() async {
    if (_committed) return;
    _committed = true;
    final reference =
        _progress?.state.outcome?.effectReference ??
        _progress?.state.outcome?.effectId;
    try {
      await _progress?.retireAfterCommit();
      if (!mounted) return;
      widget.onChanged();
      YorksAppToast.show(
        context,
        title: reference == null
            ? t(YorksV1ProcurementProgressStrings.confirmedResult)
            : t(YorksV1ProcurementProgressStrings.confirmedDispatch(reference)),
        tone: YorksAppToastTone.success,
      );
    } catch (_) {
      _progress?.markViewRefreshDegraded();
    }
  }

  Future<void> _retryPending() async {
    final progress = _progress;
    if (progress == null || _saving) return;
    final payload = progress.pendingCommandPayload;
    final pending = progress.state.pendingCommand;
    if (payload == null ||
        pending == null ||
        payload['request_id'] != widget.workspace.requestId) {
      return;
    }
    final input = YorksV1DispatchInput(
      requestId: payload['request_id'] as String,
      expectedRequestVersion: payload['expected_version'] as int,
      dispatchDate: DateTime.parse(payload['dispatch_date'] as String),
      deliveryReference: payload['delivery_reference'] as String? ?? '',
      driverName: payload['driver_name'] as String?,
      vehicleReference: payload['vehicle_reference'] as String?,
      lines: [
        for (final raw in payload['lines'] as List)
          YorksV1DispatchLineInput(
            requestLineId: (raw as Map)['request_line_id'] as String,
            dispatchQuantity: raw['dispatch_qty'] as String,
          ),
      ],
      idempotencyKey: pending.commandKey,
    );
    await _commit(input, retryKey: pending.commandKey);
  }

  @override
  Widget build(BuildContext context) {
    _bindProgress(
      ref.watch(yorksV1ProcurementProgressControllerProvider(_scope)),
    );
    final candidates = widget.workspace.dispatchCandidates
        .where(
          (candidate) =>
              YorksV1DecimalQuantity.tryParse(
                candidate.stillNeededQuantity,
              )?.isPositive ==
              true,
        )
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.mobileFlow || constraints.maxWidth < 600) {
          return PopScope(
            canPop:
                _allowPop ||
                (!_saving &&
                    _progress?.state.isDirty != true &&
                    _progress?.state.isPending != true),
            onPopInvokedWithResult: (didPop, result) async {
              if (!didPop && await _canLeave() && mounted) {
                setState(() => _allowPop = true);
                if (context.mounted) Navigator.of(context).pop(result);
              }
            },
            child: _MobileDispatchEditor(
              workspace: widget.workspace,
              deliveryReference: _deliveryReference,
              driver: _driver,
              vehicle: _vehicle,
              quantities: _quantities,
              dispatchDate: _dispatchDate,
              saving: _saving,
              enabled: _editable,
              progressPanel: _progressPanel(),
              onSaveProgress: _saveProgress,
              canSaveProgress: _editable,
              onDate: _pickDate,
              onChanged: () => setState(() {}),
              onDispatch: _reviewDispatch,
              errors: _quantityErrors,
              language: ref.watch(languageProvider),
            ),
          );
        }
        final selected = _selectedLines();
        return PopScope(
          canPop:
              _allowPop ||
              (!_saving &&
                  _progress?.state.isDirty != true &&
                  _progress?.state.isPending != true),
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && await _canLeave() && mounted) {
              setState(() => _allowPop = true);
              if (context.mounted) Navigator.of(context).pop(result);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _progressPanel(),
              Expanded(
                child: _DispatchCandidateList(
                  candidates: candidates,
                  controllers: _quantities,
                  enabled: _editable,
                  errors: _quantityErrors,
                  language: ref.watch(languageProvider),
                  onChanged: () => setState(() => _quantityErrors = {}),
                  header: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          children: [
                            SizedBox(
                              width: 260,
                              child: _TextInput(
                                controller: _deliveryReference,
                                label: t(
                                  YorksV1LogisticsStrings
                                      .optionalSupplierReference,
                                ),
                                enabled: _editable,
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: SecondaryButton(
                                label: _dateLabel(_dispatchDate),
                                isExpanded: false,
                                icon: Icons.calendar_today_outlined,
                                onPressed: !_editable ? null : _pickDate,
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: _TextInput(
                                controller: _driver,
                                label: t(YorksV1LogisticsStrings.driver),
                                enabled: _editable,
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: _TextInput(
                                controller: _vehicle,
                                label: t(YorksV1LogisticsStrings.vehicle),
                                enabled: _editable,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          t(YorksV1LogisticsStrings.dispatchExcluded),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t(
                            YorksV1LogisticsStrings.dispatchSelection(
                              selected.length,
                              candidates.length - selected.length,
                            ),
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _editable ? _saveProgress : null,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          t(YorksV1ProcurementProgressStrings.saveProgress),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      PrimaryButton(
                        label: t(YorksV1LogisticsStrings.reviewDispatch),
                        icon: Icons.fact_check_outlined,
                        isExpanded: false,
                        isLoading: _saving,
                        onPressed: candidates.isEmpty || !_editable
                            ? null
                            : _reviewDispatch,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<YorksV1DispatchLineInput> _selectedLines() => [
    for (final candidate in widget.workspace.dispatchCandidates)
      if (YorksV1DecimalQuantity.tryParse(
            _quantities[candidate.requestLineId]?.text ?? '',
          )?.isPositive ==
          true)
        YorksV1DispatchLineInput(
          requestLineId: candidate.requestLineId,
          dispatchQuantity: _quantities[candidate.requestLineId]!.text.trim(),
        ),
  ];

  Future<void> _reviewDispatch() async {
    if (!_editable || _reviewOpen) return;
    final errors = YorksV1DispatchPreparation.validate(
      widget.workspace.dispatchCandidates,
      {for (final entry in _quantities.entries) entry.key: entry.value.text},
    );
    setState(() {
      _quantityErrors = errors;
    });
    if (errors.isNotEmpty) return;
    final lines = _selectedLines();
    if (lines.isEmpty) {
      _showError(t(YorksV1LogisticsStrings.invalidDispatch));
      return;
    }
    _reviewOpen = true;
    var answered = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(YorksV1LogisticsStrings.reviewDispatch)),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.workspace.requestNumber ?? ''} · ${widget.workspace.projectName}',
                ),
                Text(widget.workspace.scopeName),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  [
                    if (_deliveryReference.text.trim().isNotEmpty)
                      _deliveryReference.text.trim(),
                    _dateLabel(_dispatchDate),
                  ].join(' · '),
                ),
                if (_driver.text.trim().isNotEmpty ||
                    _vehicle.text.trim().isNotEmpty)
                  Text('${_driver.text.trim()} · ${_vehicle.text.trim()}'),
                const SizedBox(height: AppSpacing.md),
                Text(
                  t(YorksV1LogisticsStrings.dispatchReviewHelp),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final line in lines) ...[
                  Builder(
                    builder: (context) {
                      final candidate = widget.workspace.dispatchCandidates
                          .firstWhere(
                            (c) => c.requestLineId == line.requestLineId,
                          );
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _CandidateName(candidate: candidate),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              '${_displayQuantity(line.dispatchQuantity)} ${candidate.unit}',
                              style: AppTypography.labelLarge,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  t(
                    YorksV1LogisticsStrings.dispatchSelection(
                      lines.length,
                      widget.workspace.dispatchCandidates
                              .where(
                                (c) =>
                                    YorksV1DecimalQuantity.tryParse(
                                      c.stillNeededQuantity,
                                    )?.isPositive ==
                                    true,
                              )
                              .length -
                          lines.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(YorksV1LogisticsStrings.editDispatch)),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-dispatch'),
            onPressed: () {
              if (answered) return;
              answered = true;
              Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(t(YorksV1LogisticsStrings.confirmDispatch)),
          ),
        ],
      ),
    );
    _reviewOpen = false;
    if (accepted == true && mounted) await _dispatch();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dispatchDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _dispatchDate = selected);
      _inputChanged();
    }
  }

  Future<void> _dispatch() async {
    if (!_editable) return;
    final errors = YorksV1DispatchPreparation.validate(
      widget.workspace.dispatchCandidates,
      {for (final entry in _quantities.entries) entry.key: entry.value.text},
    );
    if (errors.isNotEmpty) {
      setState(() {
        _quantityErrors = errors;
      });
      return;
    }
    final lines = _selectedLines();
    if (lines.isEmpty) return;
    await _commit(
      YorksV1DispatchInput(
        requestId: widget.workspace.requestId,
        expectedRequestVersion: _baseRequestVersion,
        dispatchDate: _dispatchDate,
        deliveryReference: _deliveryReference.text,
        driverName: _driver.text,
        vehicleReference: _vehicle.text,
        lines: lines,
        idempotencyKey: _commandIdempotencyKey,
      ),
    );
  }

  Future<void> _commit(YorksV1DispatchInput input, {String? retryKey}) async {
    setState(() => _saving = true);
    try {
      _progress?.update(_snapshot());
      final updated = await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .dispatch(
            input,
            recoveredIdempotencyKey: retryKey,
            beforeInvoke: (key) async {
              if (retryKey != null && retryKey != key) {
                throw const YorksV1DomainException(
                  YorksV1DomainErrorCode.conflict,
                );
              }
              await _progress!.prepareFinalIntent(
                commandName: 'v1_dispatch_materials',
                commandKey: key,
                commandPayload: input.toRpcPayload(),
              );
              _progress!.markFinalCommandSent();
            },
          );
      _committed = true;
      try {
        await _progress?.retireAfterCommit();
      } catch (_) {
        /* Commit remains confirmed if local cleanup fails. */
      }
      if (!mounted) return;
      _commandIdempotencyKey = const Uuid().v4();
      widget.onChanged();
      final confirmedDispatch = updated.dispatches.isEmpty
          ? null
          : updated.dispatches.first;
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.dispatchConfirmed.primary,
        message: confirmedDispatch == null
            ? YorksV1LogisticsStrings.receiptReview.primary
            : YorksV1LogisticsStrings.dispatchConfirmedSummary(
                number: confirmedDispatch.number,
                lines: confirmedDispatch.lines.isEmpty
                    ? input.lines.length
                    : confirmedDispatch.lines.length,
              ).primary,
        tone: YorksAppToastTone.success,
      );
      _restoring = true;
      for (final controller in _quantities.values) {
        controller.clear();
      }
      _restoring = false;
    } on YorksV1DomainException catch (error) {
      if (_committed) {
        _progress?.markViewRefreshDegraded();
        return;
      }
      final rejected = _progress?.state.pendingCommand;
      await _progress?.rejectFinalIntent(error);
      if (_progress?.state.outcome?.isConfirmed == true) {
        await _confirmedRecovery();
        return;
      }
      // An uncertain write has its own live status panel; a failure toast
      // would contradict that state and invite an unsafe second dispatch.
      if (_progress?.state.isPending == true) return;
      if (rejected != null && _progress?.state.pendingCommand == null) {
        await ref
            .read(yorksV1MaterialWorkflowCommandControllerProvider)
            .releaseRejectedPreparedCommand(
              operation: 'dispatch_materials',
              entityId: widget.workspace.requestId,
              idempotencyKey: rejected.commandKey,
            );
      }
      if (mounted) {
        _showError(
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } catch (error) {
      if (_committed) {
        _progress?.markViewRefreshDegraded();
        return;
      }
      final rejected = _progress?.state.pendingCommand;
      await _progress?.rejectFinalIntent(error);
      if (_progress?.state.outcome?.isConfirmed == true) {
        await _confirmedRecovery();
        return;
      }
      // An uncertain write has its own live status panel; a failure toast
      // would contradict that state and invite an unsafe second dispatch.
      if (_progress?.state.isPending == true) return;
      if (rejected != null && _progress?.state.pendingCommand == null) {
        await ref
            .read(yorksV1MaterialWorkflowCommandControllerProvider)
            .releaseRejectedPreparedCommand(
              operation: 'dispatch_materials',
              entityId: widget.workspace.requestId,
              idempotencyKey: rejected.commandKey,
            );
      }
      if (mounted) _showError(YorksV1LogisticsStrings.savingFailed.primary);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String text) =>
      YorksAppToast.show(context, title: text, tone: YorksAppToastTone.error);
}

class _MobileDispatchEditor extends StatelessWidget {
  const _MobileDispatchEditor({
    required this.workspace,
    required this.deliveryReference,
    required this.driver,
    required this.vehicle,
    required this.quantities,
    required this.dispatchDate,
    required this.saving,
    required this.enabled,
    required this.onDate,
    required this.onChanged,
    required this.onDispatch,
    required this.errors,
    required this.progressPanel,
    required this.onSaveProgress,
    required this.canSaveProgress,
    required this.language,
  });

  final YorksV1LogisticsWorkspace workspace;
  final TextEditingController deliveryReference;
  final TextEditingController driver;
  final TextEditingController vehicle;
  final Map<String, TextEditingController> quantities;
  final DateTime dispatchDate;
  final bool saving;
  final bool enabled;
  final VoidCallback onDate;
  final VoidCallback onChanged;
  final VoidCallback onDispatch;
  final Map<String, YorksV1DispatchQuantityIssue> errors;
  final Widget progressPanel;
  final VoidCallback onSaveProgress;
  final bool canSaveProgress;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final candidates = workspace.dispatchCandidates
        .where((candidate) => _number(candidate.stillNeededQuantity) > 0)
        .toList(growable: false);
    final included = candidates
        .where(
          (item) =>
              YorksV1DecimalQuantity.tryParse(
                quantities[item.requestLineId]?.text ?? '',
              )?.isPositive ==
              true,
        )
        .length;
    return Column(
      key: const ValueKey('mobile-dispatch-create'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
            children: [
              YorksMobilePageTitle(
                eyebrow: workspace.requestNumber ?? '',
                title: YorksV1LogisticsStrings.createDispatch.active(language),
                description: YorksV1LogisticsStrings.dispatchOutstandingOnly
                    .active(language),
              ),
              const SizedBox(height: 16),
              progressPanel,
              YorksMobileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TextInput(
                      controller: deliveryReference,
                      label: YorksV1LogisticsStrings.optionalSupplierReference
                          .active(language),
                      enabled: enabled && !saving,
                      onChanged: (_) => onChanged(),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: !enabled || saving ? null : onDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: YorksV1LogisticsStrings.dispatchDate
                              .active(language),
                          suffixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 19,
                          ),
                        ),
                        child: Text(_dateLabel(dispatchDate)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TextInput(
                            controller: driver,
                            label: YorksV1LogisticsStrings.driver.active(
                              language,
                            ),
                            enabled: enabled && !saving,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TextInput(
                            controller: vehicle,
                            label: YorksV1LogisticsStrings.vehicle.active(
                              language,
                            ),
                            enabled: enabled && !saving,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              YorksMobileSectionHeader(
                title: YorksV1LogisticsStrings.dispatchApprovedItems.active(
                  language,
                ),
                subtitle: workspace.scopeName,
              ),
              const SizedBox(height: 10),
              if (candidates.isEmpty)
                YorksMobileCard(
                  child: Text(
                    YorksV1LogisticsStrings.noDispatch.active(language),
                  ),
                )
              else
                for (var index = 0; index < candidates.length; index++) ...[
                  _MobileDispatchCandidate(
                    index: index + 1,
                    candidate: candidates[index],
                    controller: quantities[candidates[index].requestLineId]!,
                    enabled: enabled && !saving,
                    onChanged: onChanged,
                    error: errors[candidates[index].requestLineId],
                    language: language,
                  ),
                  const SizedBox(height: 10),
                ],
              YorksMobileCallout(
                icon: Icons.shield_outlined,
                title: YorksV1LogisticsStrings.stockProtected.active(language),
                message: YorksV1LogisticsStrings.stockRecheckedOnDispatch
                    .active(language),
              ),
            ],
          ),
        ),
        YorksMobileStickyActions(
          summary: YorksV1LogisticsStrings.dispatchSelection(
            included,
            candidates.length - included,
          ).active(language),
          children: [
            OutlinedButton.icon(
              onPressed: canSaveProgress ? onSaveProgress : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(
                YorksV1ProcurementProgressStrings.saveProgress.active(language),
              ),
            ),
            FilledButton.icon(
              onPressed: candidates.isEmpty || saving || !enabled
                  ? null
                  : onDispatch,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_shipping_outlined, size: 19),
              label: Text(
                YorksV1LogisticsStrings.reviewDispatch.active(language),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MobileDispatchCandidate extends StatelessWidget {
  const _MobileDispatchCandidate({
    required this.index,
    required this.candidate,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.error,
    required this.language,
  });

  final int index;
  final YorksV1DispatchCandidate candidate;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final YorksV1DispatchQuantityIssue? error;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.blueContainer,
                shape: BoxShape.circle,
              ),
              child: Text('$index', style: AppTypography.labelLarge),
            ),
            const SizedBox(width: 10),
            Expanded(child: _CandidateName(candidate: candidate)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MobileDispatchFact(
                label: YorksV1LogisticsStrings.approved.active(language),
                value:
                    '${_displayQuantity(candidate.approvedQuantity)} ${candidate.unit}',
              ),
            ),
            Expanded(
              child: _MobileDispatchFact(
                label: YorksV1LogisticsStrings.stillNeeded.active(language),
                value:
                    '${_displayQuantity(candidate.stillNeededQuantity)} ${candidate.unit}',
              ),
            ),
          ],
        ),
        if (candidate.source == YorksV1LogisticsSource.warehouse) ...[
          const SizedBox(height: 8),
          _MobileDispatchFact(
            label: YorksV1LogisticsStrings.available.active(language),
            value:
                '${_displayQuantity(candidate.warehouseAvailableQuantity ?? '0')} ${candidate.unit}',
          ),
        ],
        const SizedBox(height: 12),
        _QuantityInput(
          controller: controller,
          errorText: _dispatchError(error, language),
          label: YorksV1LogisticsStrings.dispatchQuantity.active(language),
          enabled: enabled,
          onChanged: (_) => onChanged(),
        ),
      ],
    ),
  );
}

class _MobileDispatchFact extends StatelessWidget {
  const _MobileDispatchFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.muted,
          fontSize: 9,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 2),
      Text(value, style: AppTypography.labelLarge),
    ],
  );
}

class _DispatchCandidateList extends StatelessWidget {
  const _DispatchCandidateList({
    required this.candidates,
    required this.controllers,
    required this.enabled,
    required this.errors,
    required this.language,
    required this.onChanged,
    required this.header,
  });
  final List<YorksV1DispatchCandidate> candidates;
  final Map<String, TextEditingController> controllers;
  final bool enabled;
  final Map<String, YorksV1DispatchQuantityIssue> errors;
  final AppLanguage language;
  final VoidCallback onChanged;
  final Widget header;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          if (!compact)
            SliverPersistentHeader(
              pinned: true,
              delegate: _DispatchPinnedHeader(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  color: AppColors.surfaceContainerLow,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          YorksV1LogisticsStrings.itemDescription.active(
                            language,
                          ),
                          style: AppTypography.labelMedium,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          YorksV1LogisticsStrings.stillNeeded.active(language),
                          style: AppTypography.labelMedium,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          YorksV1LogisticsStrings.available.active(language),
                          style: AppTypography.labelMedium,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          YorksV1LogisticsStrings.sendNow.active(language),
                          style: AppTypography.labelMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (candidates.isEmpty)
            SliverToBoxAdapter(
              child: Text(YorksV1LogisticsStrings.noDispatch.active(language)),
            ),
          SliverList.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return Container(
                key: ValueKey('dispatch-row-${candidate.requestLineId}'),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                  horizontal: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.line)),
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CandidateName(candidate: candidate),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '${YorksV1LogisticsStrings.stillNeeded.active(language)}: ${_displayQuantity(candidate.stillNeededQuantity)} ${candidate.unit}',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _QuantityInput(
                            controller: controllers[candidate.requestLineId]!,
                            label: YorksV1LogisticsStrings.sendNow.active(
                              language,
                            ),
                            enabled: enabled,
                            errorText: _dispatchError(
                              errors[candidate.requestLineId],
                              language,
                            ),
                            onChanged: (_) => onChanged(),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _CandidateName(candidate: candidate),
                          ),
                          Expanded(
                            flex: 2,
                            child: _Quantity(
                              value: _displayQuantity(
                                candidate.stillNeededQuantity,
                              ),
                              unit: candidate.unit,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              candidate.source ==
                                      YorksV1LogisticsSource.warehouse
                                  ? '${candidate.warehouseAvailableQuantity == null ? '—' : _displayQuantity(candidate.warehouseAvailableQuantity!)} ${candidate.unit}'
                                  : '—',
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: _QuantityInput(
                              controller: controllers[candidate.requestLineId]!,
                              label: YorksV1LogisticsStrings.sendNow.active(
                                language,
                              ),
                              enabled: enabled,
                              errorText: _dispatchError(
                                errors[candidate.requestLineId],
                                language,
                              ),
                              onChanged: (_) => onChanged(),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
      );
    },
  );
}

class _DispatchPinnedHeader extends SliverPersistentHeaderDelegate {
  _DispatchPinnedHeader({required this.child});
  final Widget child;
  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_DispatchPinnedHeader oldDelegate) =>
      oldDelegate.child != child;
}

String? _dispatchError(
  YorksV1DispatchQuantityIssue? issue,
  AppLanguage language,
) => switch (issue) {
  null => null,
  YorksV1DispatchQuantityIssue.invalid =>
    YorksV1LogisticsStrings.dispatchQuantityInvalid.active(language),
  YorksV1DispatchQuantityIssue.negative =>
    YorksV1LogisticsStrings.dispatchQuantityNegative.active(language),
  YorksV1DispatchQuantityIssue.exceedsRemaining =>
    YorksV1LogisticsStrings.dispatchQuantityRemaining.active(language),
  YorksV1DispatchQuantityIssue.unavailable =>
    YorksV1LogisticsStrings.dispatchStockUnknown.active(language),
  YorksV1DispatchQuantityIssue.exceedsStock =>
    YorksV1LogisticsStrings.dispatchQuantityStock.active(language),
};

class _DispatchCard extends ConsumerStatefulWidget {
  const _DispatchCard({
    required this.dispatch,
    required this.workspace,
    required this.onChanged,
    required this.showReceiptReview,
    required this.canConfirmReceipt,
  });

  final YorksV1MaterialDispatch dispatch;
  final YorksV1LogisticsWorkspace workspace;
  final VoidCallback onChanged;
  final bool showReceiptReview;
  final bool canConfirmReceipt;

  @override
  ConsumerState<_DispatchCard> createState() => _DispatchCardState();
}

class _DispatchCardState extends ConsumerState<_DispatchCard> {
  bool _uploadingPhoto = false;
  String _photoIdempotencyKey = const Uuid().v4();
  final _documents = const YorksV1LogisticsDocumentService();

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final documentsWorkspace = ref
        .watch(
          yorksV1ReturnsDocumentsWorkspaceProvider(widget.workspace.requestId),
        )
        .valueOrNull;
    final documentDispatch = _documentDispatch(documentsWorkspace);
    final revision = documentDispatch?.deliveryOrder?.currentRevision;
    final deliveryOrderAccess = yorksV1FeatureActionAccess(
      ref.watch(yorksV1CurrentPermissionSnapshotProvider),
      YorksV1CapabilityKeys.deliveryOrdersGenerate,
      legacyAllowed: documentDispatch?.canGenerate == true,
      projectId: widget.workspace.projectId,
    );
    final mobile = YorksMobileUi.isActive(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.dispatch.number,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StateChip(state: widget.dispatch.state),
                    Text(
                      _dateLabel(widget.dispatch.dispatchDate),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _DispatchFactsGrid(
                  dispatch: widget.dispatch,
                  language: language,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          if (mobile)
            _DispatchLineCards(lines: widget.dispatch.lines, language: language)
          else
            _DispatchLineTable(
              lines: widget.dispatch.lines,
              language: language,
            ),
          const Divider(height: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (widget.dispatch.receiptReview != null)
                  SecondaryButton(
                    label: YorksV1LogisticsStrings.addSitePhoto.active(
                      language,
                    ),
                    isExpanded: false,
                    icon: _uploadingPhoto
                        ? Icons.hourglass_top_rounded
                        : Icons.add_a_photo_outlined,
                    onPressed: _uploadingPhoto ? null : _addSitePhoto,
                  ),
                if (revision != null && documentDispatch != null)
                  SecondaryButton(
                    label:
                        (revision.snapshotKind ==
                                    YorksV1DeliveryOrderSnapshotKind
                                        .receiptReview
                                ? YorksV1LogisticsStrings.printDeliveryReport
                                : YorksV1LogisticsStrings.printDocument)
                            .active(language),
                    isExpanded: false,
                    icon: Icons.print_outlined,
                    onPressed: () => _printDeliveryReport(
                      documentsWorkspace!,
                      documentDispatch,
                      revision,
                    ),
                  )
                else if (deliveryOrderAccess.isVisible)
                  SecondaryButton(
                    label: YorksV1LogisticsStrings.generateDeliveryOrder.active(
                      language,
                    ),
                    isExpanded: false,
                    icon: Icons.receipt_long_outlined,
                    onPressed: deliveryOrderAccess.canWrite
                        ? _openDeliveryOrder
                        : null,
                  ),
                if (widget.dispatch.canConfirmReceipt &&
                    widget.showReceiptReview)
                  SecondaryButton(
                    label: YorksV1LogisticsStrings.receiptReview.active(
                      language,
                    ),
                    isExpanded: false,
                    icon: Icons.fact_check_outlined,
                    onPressed: widget.canConfirmReceipt
                        ? () => _openReceiptReview(context)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  YorksV1DeliveryOrderDispatch? _documentDispatch(
    YorksV1ReturnsDocumentsWorkspace? workspace,
  ) {
    if (workspace == null) return null;
    for (final dispatch in workspace.deliveryOrderDispatches) {
      if (dispatch.dispatchId == widget.dispatch.id) return dispatch;
    }
    return null;
  }

  Future<void> _printDeliveryReport(
    YorksV1ReturnsDocumentsWorkspace workspace,
    YorksV1DeliveryOrderDispatch dispatch,
    YorksV1DeliveryOrderRevision revision,
  ) async {
    try {
      await _documents.printDeliveryOrder(
        workspace: workspace,
        dispatch: dispatch,
        revision: revision,
      );
    } catch (_) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.savingFailed.primary,
        tone: YorksAppToastTone.error,
      );
    }
  }

  void _openDeliveryOrder() => context.push(
    RoutePaths.yorksV1MaterialRequestReturnsDocumentsPath(
      widget.workspace.requestId,
      focusDeliveryOrder: true,
      dispatchId: widget.dispatch.id,
    ),
  );

  Future<void> _openReceiptReview(BuildContext context) async {
    if (!widget.canConfirmReceipt) return;
    await showYorksV1ReceiptReviewDialog(
      context,
      workspace: widget.workspace,
      dispatch: widget.dispatch,
      onChanged: widget.onChanged,
    );
  }

  Future<void> _addSitePhoto() async {
    final review = widget.dispatch.receiptReview;
    if (review == null || _uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);
    final uploaded = await _selectAndUploadReceiptPhoto(
      context: context,
      ref: ref,
      workspace: widget.workspace,
      receiptReviewId: review.id,
      idempotencyKey: _photoIdempotencyKey,
    );
    if (!mounted) return;
    if (uploaded) {
      _photoIdempotencyKey = const Uuid().v4();
      widget.onChanged();
    }
    setState(() => _uploadingPhoto = false);
  }
}

class _DispatchFactsGrid extends StatelessWidget {
  const _DispatchFactsGrid({required this.dispatch, required this.language});

  final YorksV1MaterialDispatch dispatch;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final values = <({String label, String value})>[
      (
        label: YorksV1LogisticsStrings.dispatchedBy.active(language),
        value: dispatch.dispatchedByDisplayName,
      ),
      (
        label: YorksV1LogisticsStrings.deliveryReference.active(language),
        value:
            dispatch.deliveryReference ??
            YorksV1MaterialRequestStrings.notProvided.active(language),
      ),
      (
        label: YorksV1LogisticsStrings.driver.active(language),
        value:
            dispatch.driverName ??
            YorksV1MaterialRequestStrings.notProvided.active(language),
      ),
      (
        label: YorksV1LogisticsStrings.vehicle.active(language),
        value:
            dispatch.vehicleReference ??
            YorksV1MaterialRequestStrings.notProvided.active(language),
      ),
      if (dispatch.receiptReview != null)
        (
          label: YorksV1LogisticsStrings.receiptReview.active(language),
          value:
              '${dispatch.receiptReview!.reviewedByDisplayName} · ${_dateLabel(dispatch.receiptReview!.reviewedAt)}',
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - AppSpacing.md * 3) / 4
            : constraints.maxWidth >= 520
            ? (constraints.maxWidth - AppSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: _DispatchFact(label: value.label, value: value.value),
              ),
          ],
        );
      },
    );
  }
}

class _DispatchFact extends StatelessWidget {
  const _DispatchFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.muted,
          letterSpacing: .7,
          fontSize: 10,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge,
      ),
    ],
  );
}

class _DispatchLineTable extends StatelessWidget {
  const _DispatchLineTable({required this.lines, required this.language});

  final List<YorksV1DispatchLine> lines;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: 1220,
      child: Table(
        key: const ValueKey('dispatch-lines-table'),
        border: TableBorder.all(color: AppColors.line, width: 1),
        columnWidths: const {
          0: FixedColumnWidth(58),
          1: FlexColumnWidth(2.4),
          2: FlexColumnWidth(1.3),
          3: FixedColumnWidth(130),
          4: FixedColumnWidth(118),
          5: FixedColumnWidth(76),
          6: FixedColumnWidth(128),
          7: FixedColumnWidth(92),
          8: FixedColumnWidth(92),
          9: FixedColumnWidth(92),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
            ),
            children: [
              _DispatchGridCell(
                YorksV1LogisticsStrings.serialNumber.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.itemDescription.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.brandOrigin.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.source.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.deliveryQuantity.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.unit.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.outcome.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.goodQuantity.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.missingQuantity.active(language),
                header: true,
              ),
              _DispatchGridCell(
                YorksV1LogisticsStrings.damagedQuantity.active(language),
                header: true,
              ),
            ],
          ),
          for (var index = 0; index < lines.length; index++)
            TableRow(
              children: [
                _DispatchGridCell('${index + 1}'),
                _DispatchGridCell(lines[index].description, emphasis: true),
                _DispatchGridCell(
                  lines[index].brandOrigin ??
                      YorksV1MaterialRequestStrings.notProvided.active(
                        language,
                      ),
                ),
                _DispatchGridCell(
                  yorksV1LogisticsSourceCopy(
                    lines[index].source,
                  ).active(language),
                ),
                _DispatchGridCell(
                  yorksV1DisplayQuantity(lines[index].dispatchedQuantity),
                ),
                _DispatchGridCell(lines[index].unit),
                _DispatchGridCell(
                  lines[index].receiptOutcome == null
                      ? YorksV1LogisticsStrings.pending.active(language)
                      : yorksV1ReceiptOutcomeCopy(
                          lines[index].receiptOutcome!,
                        ).active(language),
                ),
                _DispatchGridCell(
                  yorksV1DisplayQuantity(lines[index].goodQuantity ?? '0'),
                ),
                _DispatchGridCell(
                  yorksV1DisplayQuantity(lines[index].missingQuantity ?? '0'),
                ),
                _DispatchGridCell(
                  yorksV1DisplayQuantity(lines[index].damagedQuantity ?? '0'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _DispatchGridCell extends StatelessWidget {
  const _DispatchGridCell(
    this.value, {
    this.header = false,
    this.emphasis = false,
  });

  final String value;
  final bool header;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: header ? 46 : 54),
    alignment: AlignmentDirectional.centerStart,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Text(
      value,
      maxLines: header ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: (header ? AppTypography.labelSmall : AppTypography.bodySmall)
          .copyWith(
            color: header ? AppColors.muted : AppColors.ink,
            fontWeight: header || emphasis ? FontWeight.w800 : FontWeight.w500,
          ),
    ),
  );
}

class _DispatchLineCards extends StatelessWidget {
  const _DispatchLineCards({required this.lines, required this.language});

  final List<YorksV1DispatchLine> lines;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      children: [
        for (var index = 0; index < lines.length; index++) ...[
          _DispatchLineCard(
            index: index + 1,
            line: lines[index],
            language: language,
          ),
          if (index != lines.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _DispatchLineCard extends StatelessWidget {
  const _DispatchLineCard({
    required this.index,
    required this.line,
    required this.language,
  });

  final int index;
  final YorksV1DispatchLine line;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.blueContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$index',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.description,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      line.brandOrigin,
                      yorksV1LogisticsSourceCopy(line.source).active(language),
                    ].whereType<String>().join(' · '),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            _DispatchFact(
              label: YorksV1LogisticsStrings.deliveryQuantity.active(language),
              value:
                  '${yorksV1DisplayQuantity(line.dispatchedQuantity)} ${line.unit}',
            ),
            _DispatchFact(
              label: YorksV1LogisticsStrings.outcome.active(language),
              value: line.receiptOutcome == null
                  ? YorksV1LogisticsStrings.pending.active(language)
                  : yorksV1ReceiptOutcomeCopy(
                      line.receiptOutcome!,
                    ).active(language),
            ),
            if (line.receiptOutcome != null)
              _DispatchFact(
                label: YorksV1LogisticsStrings.goodQuantity.active(language),
                value: yorksV1DisplayQuantity(line.goodQuantity ?? '0'),
              ),
          ],
        ),
      ],
    ),
  );
}

Future<bool> _selectAndUploadReceiptPhoto({
  required BuildContext context,
  required WidgetRef ref,
  required YorksV1LogisticsWorkspace workspace,
  required String receiptReviewId,
  required String idempotencyKey,
}) async {
  try {
    final selected = await ref
        .read(yorksV1DocumentFileServiceProvider)
        .selectImage();
    if (selected == null) return false;
    await ref
        .read(yorksV1DocumentsRepositoryProvider)
        .upload(
          YorksV1DocumentUploadInput(
            projectId: workspace.projectId,
            entityType: YorksV1DocumentEntityType.receiptReview,
            entityId: receiptReviewId,
            classification: YorksV1DocumentClassification.operational,
            fileName: selected.fileName,
            mimeType: selected.mimeType,
            bytes: selected.bytes,
            idempotencyKey: idempotencyKey,
          ),
        );
    if (context.mounted) {
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.sitePhotoUploaded.primary,
        tone: YorksAppToastTone.success,
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.sitePhotoFailed.primary,
        tone: YorksAppToastTone.error,
      );
    }
    return false;
  }
}

/// Opens the same protected receipt-review command from either the focused
/// logistics route or the Material Request record. Keeping one dialog avoids
/// route changes and guarantees both entry points validate identical inputs.
Future<bool?> showYorksV1ReceiptReviewDialog(
  BuildContext context, {
  required YorksV1LogisticsWorkspace workspace,
  required YorksV1MaterialDispatch dispatch,
  required VoidCallback onChanged,
}) => showDialog<bool>(
  context: context,
  animationStyle: AnimationStyle.noAnimation,
  barrierDismissible: false,
  builder: (_) => _ReceiptReviewSheet(
    workspace: workspace,
    dispatch: dispatch,
    onChanged: onChanged,
  ),
);

class _ReceiptReviewSheet extends ConsumerStatefulWidget {
  const _ReceiptReviewSheet({
    required this.workspace,
    required this.dispatch,
    required this.onChanged,
  });

  final YorksV1LogisticsWorkspace workspace;
  final YorksV1MaterialDispatch dispatch;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ReceiptReviewSheet> createState() =>
      _ReceiptReviewSheetState();
}

class _ReceiptReviewSheetState extends ConsumerState<_ReceiptReviewSheet> {
  final Map<String, YorksV1ReceiptOutcome> _outcomes = {};
  final Map<String, TextEditingController> _goodQuantities = {};
  final Map<String, TextEditingController> _missingQuantities = {};
  final Map<String, TextEditingController> _damagedQuantities = {};
  final Map<String, TextEditingController> _notes = {};
  final Set<String> _reviewed = {};
  late String _receiptIdempotencyKey;
  late String _photoIdempotencyKey;
  bool _allReviewed = false;
  bool _saving = false;
  bool get _pendingReceipt => ref
      .read(yorksV1MaterialWorkflowCommandControllerProvider)
      .hasPendingReceipt(widget.dispatch.id);
  bool get _locked => _saving || _pendingReceipt;

  @override
  void initState() {
    super.initState();
    _receiptIdempotencyKey = const Uuid().v4();
    _photoIdempotencyKey = const Uuid().v4();
    for (final line in widget.dispatch.lines) {
      _outcomes[line.id] = YorksV1ReceiptOutcome.received;
      _goodQuantities[line.id] = TextEditingController(
        text: _displayQuantity(line.dispatchedQuantity),
      );
      _missingQuantities[line.id] = TextEditingController(text: '0');
      _damagedQuantities[line.id] = TextEditingController(text: '0');
      _notes[line.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _goodQuantities.values) {
      controller.dispose();
    }
    for (final controller in _missingQuantities.values) {
      controller.dispose();
    }
    for (final controller in _damagedQuantities.values) {
      controller.dispose();
    }
    for (final controller in _notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    if (YorksMobileUi.isActive(context)) {
      return PopScope(
        canPop: !_saving,
        child: Dialog.fullscreen(
          child: _MobileReceiptReview(
            dispatch: widget.dispatch,
            outcomes: _outcomes,
            reviewed: _reviewed,
            saving: _saving,
            outcomeUnknown: _pendingReceipt,
            onClose: () => Navigator.of(context).pop(),
            onReceiveAll: _receiveAll,
            onOutcome: _selectMobileOutcome,
            onConfirm:
                _pendingReceipt ||
                    _reviewed.length == widget.dispatch.lines.length
                ? _confirm
                : null,
          ),
        ),
      );
    }
    final isCompact = screen.width < AppSpacing.yorksV1DesktopBreakpoint;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.all(
          isCompact ? AppSpacing.sm : AppSpacing.xxl,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1320,
            maxHeight: screen.height * .92,
            minWidth: isCompact ? 0 : 760,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReceiptReviewHeader(
                dispatchNumber: widget.dispatch.number,
                onClose: _saving ? null : () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReceiptDispatchBanner(dispatch: widget.dispatch),
                      const SizedBox(height: AppSpacing.lg),
                      for (
                        var index = 0;
                        index < widget.dispatch.lines.length;
                        index++
                      )
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _ReceiptLineEditor(
                            lineNumber: index + 1,
                            line: widget.dispatch.lines[index],
                            outcome:
                                _outcomes[widget.dispatch.lines[index].id]!,
                            goodQuantity:
                                _goodQuantities[widget
                                    .dispatch
                                    .lines[index]
                                    .id]!,
                            missingQuantity:
                                _missingQuantities[widget
                                    .dispatch
                                    .lines[index]
                                    .id]!,
                            damagedQuantity:
                                _damagedQuantities[widget
                                    .dispatch
                                    .lines[index]
                                    .id]!,
                            note: _notes[widget.dispatch.lines[index].id]!,
                            isDisabled: _saving,
                            onOutcomeChanged: (outcome) => setState(() {
                              final line = widget.dispatch.lines[index];
                              _reviewed.add(line.id);
                              _outcomes[line.id] = outcome;
                              if (outcome == YorksV1ReceiptOutcome.received) {
                                _goodQuantities[line.id]!.text =
                                    _displayQuantity(line.dispatchedQuantity);
                                _missingQuantities[line.id]!.text = '0';
                                _damagedQuantities[line.id]!.text = '0';
                                _notes[line.id]!.clear();
                              } else if (_goodQuantities[line.id]!.text ==
                                  _displayQuantity(line.dispatchedQuantity)) {
                                _goodQuantities[line.id]!.text = '0';
                                _missingQuantities[line.id]!.text = '0';
                                _damagedQuantities[line.id]!.text = '0';
                              }
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SizedBox(
                        width: isCompact
                            ? screen.width -
                                  (AppSpacing.sm * 2) -
                                  (AppSpacing.lg * 2)
                            : 360,
                        child: CheckboxListTile(
                          value: _allReviewed,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _allReviewed = value ?? false,
                                ),
                          title: Text(
                            YorksV1LogisticsStrings.allLinesReviewed.primary,
                          ),
                        ),
                      ),
                      SecondaryButton(
                        label: MaterialLocalizations.of(
                          context,
                        ).cancelButtonLabel,
                        isExpanded: false,
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      PrimaryButton(
                        label: _pendingReceipt
                            ? YorksV1MaterialRequestStrings
                                  .checkSubmissionStatus
                                  .primary
                            : YorksV1LogisticsStrings.saveReceiptReview.primary,
                        icon: Icons.verified_outlined,
                        isExpanded: false,
                        isLoading: _saving,
                        onPressed: (_pendingReceipt || _allReviewed) && !_saving
                            ? _confirm
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    if (_pendingReceipt) {
      setState(() => _saving = true);
      try {
        final result = await ref
            .read(yorksV1MaterialWorkflowCommandControllerProvider)
            .checkReceiptStatus(widget.workspace.requestId, widget.dispatch.id);
        if (result != null && mounted) {
          widget.onChanged();
          Navigator.of(context).pop(true);
        }
      } on YorksV1CommittedViewUnavailable {
        if (mounted) {
          widget.onChanged();
          YorksAppToast.show(
            context,
            title: YorksV1MaterialRequestStrings
                .commandCommittedViewUnavailable
                .primary,
            tone: YorksAppToastTone.success,
          );
          Navigator.of(context).pop(true);
        }
      } catch (_) {
        if (mounted) {
          YorksAppToast.show(
            context,
            title: YorksV1MaterialRequestStrings.commandUnknown.primary,
            tone: YorksAppToastTone.information,
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    if (YorksMobileUi.isActive(context) &&
        _reviewed.length != widget.dispatch.lines.length) {
      _showFailure(YorksV1LogisticsStrings.allLinesReviewed.primary);
      return;
    }
    final lines = <YorksV1ReceiptLineInput>[];
    for (final line in widget.dispatch.lines) {
      final outcome = _outcomes[line.id]!;
      final good = _goodQuantities[line.id]!.text.trim();
      final note = _notes[line.id]!.text.trim();
      final dispatched = YorksV1DecimalQuantity.tryParse(
        line.dispatchedQuantity,
      );
      final goodQuantity = YorksV1DecimalQuantity.tryParse(good);
      final missingQuantity = outcome == YorksV1ReceiptOutcome.missing
          ? dispatched == null || goodQuantity == null
                ? null
                : dispatched - goodQuantity
          : outcome == YorksV1ReceiptOutcome.mixed
          ? YorksV1DecimalQuantity.tryParse(
              _missingQuantities[line.id]!.text.trim(),
            )
          : YorksV1DecimalQuantity.zero;
      final damagedQuantity = outcome == YorksV1ReceiptOutcome.damaged
          ? dispatched == null || goodQuantity == null
                ? null
                : dispatched - goodQuantity
          : outcome == YorksV1ReceiptOutcome.mixed
          ? YorksV1DecimalQuantity.tryParse(
              _damagedQuantities[line.id]!.text.trim(),
            )
          : YorksV1DecimalQuantity.zero;
      if (goodQuantity == null ||
          dispatched == null ||
          missingQuantity == null ||
          damagedQuantity == null ||
          goodQuantity.isNegative ||
          missingQuantity.isNegative ||
          damagedQuantity.isNegative ||
          goodQuantity + missingQuantity + damagedQuantity != dispatched ||
          (outcome == YorksV1ReceiptOutcome.received &&
              (goodQuantity != dispatched || note.isNotEmpty)) ||
          (outcome == YorksV1ReceiptOutcome.missing &&
              (!missingQuantity.isPositive ||
                  !damagedQuantity.isZero ||
                  note.isEmpty)) ||
          (outcome == YorksV1ReceiptOutcome.damaged &&
              (!missingQuantity.isZero ||
                  !damagedQuantity.isPositive ||
                  note.isEmpty)) ||
          (outcome == YorksV1ReceiptOutcome.mixed &&
              (!missingQuantity.isPositive ||
                  !damagedQuantity.isPositive ||
                  note.isEmpty))) {
        _showFailure(YorksV1LogisticsStrings.invalidReceipt.primary);
        return;
      }
      lines.add(
        YorksV1ReceiptLineInput(
          dispatchLineId: line.id,
          outcome: outcome,
          goodQuantity: good,
          missingQuantity: missingQuantity.canonicalText,
          damagedQuantity: damagedQuantity.canonicalText,
          note: note,
        ),
      );
    }
    setState(() => _saving = true);
    var acknowledged = false;
    try {
      final confirmedWorkspace = await ref
          .read(yorksV1MaterialWorkflowCommandControllerProvider)
          .confirmReceipt(
            YorksV1ReceiptConfirmationInput(
              requestId: widget.workspace.requestId,
              dispatchId: widget.dispatch.id,
              expectedRequestVersion: widget.workspace.requestRecordVersion,
              expectedDispatchVersion: widget.dispatch.recordVersion,
              lines: lines,
              idempotencyKey: _receiptIdempotencyKey,
            ),
          );
      acknowledged = true;
      if (!mounted) return;
      _receiptIdempotencyKey = const Uuid().v4();
      widget.onChanged();
      YorksV1MaterialDispatch? confirmedDispatch;
      for (final dispatch in confirmedWorkspace.dispatches) {
        if (dispatch.id == widget.dispatch.id) {
          confirmedDispatch = dispatch;
          break;
        }
      }
      final confirmedReview = confirmedDispatch?.receiptReview;
      if (confirmedReview != null) {
        final confirmedLines = confirmedDispatch!.lines;
        final exceptionLines = confirmedLines
            .where(
              (line) => line.receiptOutcome != YorksV1ReceiptOutcome.received,
            )
            .length;
        final attachNow = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(YorksV1LogisticsStrings.receiptConfirmed.primary),
            content: Text(
              '${YorksV1LogisticsStrings.receiptConfirmedSummary(lines: confirmedLines.length, exceptionLines: exceptionLines).primary}\n\n${YorksV1LogisticsStrings.attachPhotoPrompt.primary}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(YorksV1LogisticsStrings.attachLater.primary),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(YorksV1LogisticsStrings.addSitePhoto.primary),
              ),
            ],
          ),
        );
        if (attachNow == true && mounted) {
          final uploaded = await _selectAndUploadReceiptPhoto(
            context: context,
            ref: ref,
            workspace: confirmedWorkspace,
            receiptReviewId: confirmedReview.id,
            idempotencyKey: _photoIdempotencyKey,
          );
          if (uploaded) _photoIdempotencyKey = const Uuid().v4();
        }
      } else {
        YorksAppToast.show(
          context,
          title: YorksV1LogisticsStrings.receiptConfirmed.primary,
          message: YorksV1LogisticsStrings.receiptConfirmedSummary(
            lines: lines.length,
            exceptionLines: lines
                .where((line) => line.outcome != YorksV1ReceiptOutcome.received)
                .length,
          ).primary,
          tone: YorksAppToastTone.success,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on YorksV1CommittedViewUnavailable {
      if (mounted) {
        widget.onChanged();
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings
              .commandCommittedViewUnavailable
              .primary,
          tone: YorksAppToastTone.success,
        );
        Navigator.of(context).pop(true);
      }
    } on YorksV1CommandOutcomeUnknown {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialRequestStrings.commandUnknown.primary,
          tone: YorksAppToastTone.information,
        );
      }
    } on YorksV1DomainException catch (error) {
      if (acknowledged) {
        if (mounted) {
          YorksAppToast.show(
            context,
            title: YorksV1MaterialRequestStrings
                .commandCommittedViewUnavailable
                .primary,
            tone: YorksAppToastTone.success,
          );
          Navigator.of(context).pop(true);
        }
        return;
      }
      if (mounted) {
        _showFailure(
          YorksV1MaterialRequestStrings.commandFailure(error.code).primary,
        );
      }
    } catch (_) {
      if (mounted) {
        if (acknowledged) {
          YorksAppToast.show(
            context,
            title: YorksV1MaterialRequestStrings
                .commandCommittedViewUnavailable
                .primary,
            tone: YorksAppToastTone.success,
          );
          Navigator.of(context).pop(true);
        } else {
          _showFailure(YorksV1LogisticsStrings.savingFailed.primary);
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showFailure(String message) => YorksAppToast.show(
    context,
    title: message,
    tone: YorksAppToastTone.error,
  );

  void _receiveAll() {
    if (_locked) return;
    setState(() {
      for (final line in widget.dispatch.lines) {
        _outcomes[line.id] = YorksV1ReceiptOutcome.received;
        _goodQuantities[line.id]!.text = _displayQuantity(
          line.dispatchedQuantity,
        );
        _missingQuantities[line.id]!.text = '0';
        _damagedQuantities[line.id]!.text = '0';
        _notes[line.id]!.clear();
        _reviewed.add(line.id);
      }
    });
  }

  Future<void> _selectMobileOutcome(
    YorksV1DispatchLine line,
    YorksV1ReceiptOutcome outcome,
  ) async {
    if (_locked) return;
    if (outcome == YorksV1ReceiptOutcome.received) {
      setState(() {
        _outcomes[line.id] = outcome;
        _goodQuantities[line.id]!.text = _displayQuantity(
          line.dispatchedQuantity,
        );
        _missingQuantities[line.id]!.text = '0';
        _damagedQuantities[line.id]!.text = '0';
        _notes[line.id]!.clear();
        _reviewed.add(line.id);
      });
      return;
    }
    final result = await showDialog<_ReceiptExceptionDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MobileReceiptExceptionDialog(
        line: line,
        initialOutcome: outcome,
        initialGoodQuantity: _reviewed.contains(line.id)
            ? _goodQuantities[line.id]!.text
            : '0',
        initialMissingQuantity: _reviewed.contains(line.id)
            ? _missingQuantities[line.id]!.text
            : '0',
        initialDamagedQuantity: _reviewed.contains(line.id)
            ? _damagedQuantities[line.id]!.text
            : '0',
        initialNote: _notes[line.id]!.text,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _outcomes[line.id] = result.outcome;
      _goodQuantities[line.id]!.text = result.goodQuantity;
      _missingQuantities[line.id]!.text = result.missingQuantity;
      _damagedQuantities[line.id]!.text = result.damagedQuantity;
      _notes[line.id]!.text = result.note;
      _reviewed.add(line.id);
    });
  }
}

class _MobileReceiptReview extends StatelessWidget {
  const _MobileReceiptReview({
    required this.dispatch,
    required this.outcomes,
    required this.reviewed,
    required this.saving,
    this.outcomeUnknown = false,
    required this.onClose,
    required this.onReceiveAll,
    required this.onOutcome,
    required this.onConfirm,
  });

  final YorksV1MaterialDispatch dispatch;
  final Map<String, YorksV1ReceiptOutcome> outcomes;
  final Set<String> reviewed;
  final bool saving;
  final bool outcomeUnknown;
  final VoidCallback onClose;
  final VoidCallback onReceiveAll;
  final void Function(YorksV1DispatchLine, YorksV1ReceiptOutcome) onOutcome;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.mobileSurface,
    body: Column(
      key: const ValueKey('mobile-receipt-review'),
      children: [
        YorksMobileAppBar(
          title: YorksV1LogisticsStrings.reviewDelivery.primary,
          leading: YorksMobileIconButton(
            icon: Icons.close_rounded,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: saving ? () {} : onClose,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            children: [
              YorksMobilePageTitle(
                eyebrow: dispatch.number,
                title: YorksV1LogisticsStrings.reviewDeliveredMaterials.primary,
                description:
                    YorksV1LogisticsStrings.reviewDeliveryLineByLine.primary,
              ),
              const SizedBox(height: 14),
              _ReceiptDispatchBanner(dispatch: dispatch),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving || outcomeUnknown ? null : onReceiveAll,
                icon: const Icon(Icons.done_all_rounded, size: 19),
                label: Text(
                  YorksV1LogisticsStrings.receiveAllAsDispatched.primary,
                ),
              ),
              const SizedBox(height: 14),
              for (var index = 0; index < dispatch.lines.length; index++) ...[
                _MobileReceiptLineCard(
                  index: index + 1,
                  line: dispatch.lines[index],
                  reviewed: reviewed.contains(dispatch.lines[index].id),
                  outcome: outcomes[dispatch.lines[index].id],
                  enabled: !saving && !outcomeUnknown,
                  onOutcome: (value) => onOutcome(dispatch.lines[index], value),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        YorksMobileStickyActions(
          summary: YorksV1LogisticsStrings.linesReviewed(
            reviewed.length,
            dispatch.lines.length,
          ).primary,
          children: [
            FilledButton.icon(
              onPressed: saving ? null : onConfirm,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined, size: 19),
              label: Text(
                outcomeUnknown
                    ? YorksV1MaterialRequestStrings
                          .checkSubmissionStatus
                          .primary
                    : YorksV1LogisticsStrings.confirmReceipt.primary,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MobileReceiptLineCard extends StatelessWidget {
  const _MobileReceiptLineCard({
    required this.index,
    required this.line,
    required this.reviewed,
    required this.outcome,
    required this.enabled,
    required this.onOutcome,
  });

  final int index;
  final YorksV1DispatchLine line;
  final bool reviewed;
  final YorksV1ReceiptOutcome? outcome;
  final bool enabled;
  final ValueChanged<YorksV1ReceiptOutcome> onOutcome;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ReceiptLineIdentity(lineNumber: index, line: line),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: reviewed
                    ? AppColors.successContainer
                    : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                (reviewed
                        ? YorksV1LogisticsStrings.reviewed
                        : YorksV1LogisticsStrings.pending)
                    .primary,
                style: AppTypography.labelSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        YorksMobileSegmentedControl<YorksV1ReceiptOutcome>(
          options: [
            for (final value in YorksV1ReceiptOutcome.values)
              YorksMobileSegmentOption(
                value: value,
                label: yorksV1ReceiptOutcomeCopy(value).primary,
              ),
          ],
          selected: reviewed ? outcome : null,
          enabled: enabled,
          onSelected: onOutcome,
        ),
      ],
    ),
  );
}

class _ReceiptExceptionDraft {
  const _ReceiptExceptionDraft({
    required this.outcome,
    required this.goodQuantity,
    required this.missingQuantity,
    required this.damagedQuantity,
    required this.note,
  });

  final YorksV1ReceiptOutcome outcome;
  final String goodQuantity;
  final String missingQuantity;
  final String damagedQuantity;
  final String note;
}

class _MobileReceiptExceptionDialog extends StatefulWidget {
  const _MobileReceiptExceptionDialog({
    required this.line,
    required this.initialOutcome,
    required this.initialGoodQuantity,
    required this.initialMissingQuantity,
    required this.initialDamagedQuantity,
    required this.initialNote,
  });

  final YorksV1DispatchLine line;
  final YorksV1ReceiptOutcome initialOutcome;
  final String initialGoodQuantity;
  final String initialMissingQuantity;
  final String initialDamagedQuantity;
  final String initialNote;

  @override
  State<_MobileReceiptExceptionDialog> createState() =>
      _MobileReceiptExceptionDialogState();
}

class _MobileReceiptExceptionDialogState
    extends State<_MobileReceiptExceptionDialog> {
  late YorksV1ReceiptOutcome _outcome;
  late final TextEditingController _goodQuantity;
  late final TextEditingController _missingQuantity;
  late final TextEditingController _damagedQuantity;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _outcome = widget.initialOutcome;
    _goodQuantity = TextEditingController(text: widget.initialGoodQuantity);
    _missingQuantity = TextEditingController(
      text: widget.initialMissingQuantity,
    );
    _damagedQuantity = TextEditingController(
      text: widget.initialDamagedQuantity,
    );
    _note = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _goodQuantity.dispose();
    _missingQuantity.dispose();
    _damagedQuantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exception =
        (_number(widget.line.dispatchedQuantity) - _number(_goodQuantity.text))
            .clamp(0, double.infinity)
            .toDouble();
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: AppColors.mobileSurface,
        body: Column(
          key: const ValueKey('mobile-receipt-exception'),
          children: [
            YorksMobileAppBar(
              title: YorksV1LogisticsStrings.deliveryException.primary,
              leading: YorksMobileIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                children: [
                  YorksMobilePageTitle(
                    eyebrow: widget.line.unit,
                    title: widget.line.description,
                    description:
                        '${_displayQuantity(widget.line.dispatchedQuantity)} ${widget.line.unit} ${YorksV1LogisticsStrings.dispatched.primary}',
                  ),
                  const SizedBox(height: 16),
                  YorksMobileCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          YorksV1LogisticsStrings.result.primary,
                          style: AppTypography.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        YorksMobileSegmentedControl<YorksV1ReceiptOutcome>(
                          options: [
                            for (final value in const [
                              YorksV1ReceiptOutcome.missing,
                              YorksV1ReceiptOutcome.damaged,
                              YorksV1ReceiptOutcome.mixed,
                            ])
                              YorksMobileSegmentOption(
                                value: value,
                                label: yorksV1ReceiptOutcomeCopy(value).primary,
                              ),
                          ],
                          selected: _outcome,
                          onSelected: (value) =>
                              setState(() => _outcome = value),
                        ),
                        const SizedBox(height: 14),
                        _QuantityInput(
                          controller: _goodQuantity,
                          label: YorksV1LogisticsStrings.goodQuantity.primary,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_outcome == YorksV1ReceiptOutcome.mixed) ...[
                          const SizedBox(height: 12),
                          _QuantityInput(
                            controller: _missingQuantity,
                            label:
                                YorksV1LogisticsStrings.missingQuantity.primary,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _QuantityInput(
                            controller: _damagedQuantity,
                            label:
                                YorksV1LogisticsStrings.damagedQuantity.primary,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _note,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText:
                                YorksV1LogisticsStrings.explanation.primary,
                            helperText: YorksV1LogisticsStrings
                                .exceptionExplanationRequired
                                .primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  YorksMobileCallout(
                    icon: Icons.replay_rounded,
                    title: YorksV1LogisticsStrings.replacementEligible.primary,
                    message: YorksV1LogisticsStrings.replacementQuantity(
                      _quantityText(exception),
                      widget.line.unit,
                    ).primary,
                    warning: true,
                  ),
                ],
              ),
            ),
            YorksMobileStickyActions(
              children: [
                FilledButton(
                  onPressed: _save,
                  child: Text(YorksV1LogisticsStrings.saveReview.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final dispatched = _number(widget.line.dispatchedQuantity);
    final good = _decimalNumber(_goodQuantity.text);
    final missing = _outcome == YorksV1ReceiptOutcome.missing
        ? dispatched - (good ?? 0)
        : _outcome == YorksV1ReceiptOutcome.mixed
        ? _decimalNumber(_missingQuantity.text)
        : 0.0;
    final damaged = _outcome == YorksV1ReceiptOutcome.damaged
        ? dispatched - (good ?? 0)
        : _outcome == YorksV1ReceiptOutcome.mixed
        ? _decimalNumber(_damagedQuantity.text)
        : 0.0;
    if (good == null ||
        missing == null ||
        damaged == null ||
        good < 0 ||
        missing < 0 ||
        damaged < 0 ||
        (good + missing + damaged - dispatched).abs() > .0001 ||
        (_outcome == YorksV1ReceiptOutcome.missing && missing <= 0) ||
        (_outcome == YorksV1ReceiptOutcome.damaged && damaged <= 0) ||
        (_outcome == YorksV1ReceiptOutcome.mixed &&
            (missing <= 0 || damaged <= 0)) ||
        _note.text.trim().isEmpty) {
      YorksAppToast.show(
        context,
        title: YorksV1LogisticsStrings.invalidReceipt.primary,
        tone: YorksAppToastTone.error,
      );
      return;
    }
    Navigator.of(context).pop(
      _ReceiptExceptionDraft(
        outcome: _outcome,
        goodQuantity: _goodQuantity.text.trim(),
        missingQuantity: _quantityText(missing),
        damagedQuantity: _quantityText(damaged),
        note: _note.text.trim(),
      ),
    );
  }
}

class _ReceiptLineEditor extends StatelessWidget {
  const _ReceiptLineEditor({
    required this.lineNumber,
    required this.line,
    required this.outcome,
    required this.goodQuantity,
    required this.missingQuantity,
    required this.damagedQuantity,
    required this.note,
    required this.isDisabled,
    required this.onOutcomeChanged,
  });

  final int lineNumber;
  final YorksV1DispatchLine line;
  final YorksV1ReceiptOutcome outcome;
  final TextEditingController goodQuantity;
  final TextEditingController missingQuantity;
  final TextEditingController damagedQuantity;
  final TextEditingController note;
  final bool isDisabled;
  final ValueChanged<YorksV1ReceiptOutcome> onOutcomeChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1180;
        final identity = _ReceiptLineIdentity(
          lineNumber: lineNumber,
          line: line,
        );
        final decisions = _ReceiptOutcomeChoices(
          selected: outcome,
          disabled: isDisabled,
          onChanged: onOutcomeChanged,
        );
        final inputs = _ReceiptLineInputs(
          outcome: outcome,
          goodQuantity: goodQuantity,
          missingQuantity: missingQuantity,
          damagedQuantity: damagedQuantity,
          note: note,
          disabled: isDisabled,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: AppSpacing.md),
              SizedBox(width: 360, child: decisions),
              const SizedBox(width: AppSpacing.md),
              SizedBox(width: 360, child: inputs),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            const SizedBox(height: AppSpacing.md),
            decisions,
            const SizedBox(height: AppSpacing.md),
            inputs,
          ],
        );
      },
    ),
  );
}

class _ReceiptReviewHeader extends StatelessWidget {
  const _ReceiptReviewHeader({
    required this.dispatchNumber,
    required this.onClose,
  });

  final String dispatchNumber;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1LogisticsStrings.reviewDeliveredMaterials.primary,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$dispatchNumber · ${YorksV1LogisticsStrings.reviewDeliveryLineByLine.primary}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _ReceiptDispatchBanner extends StatelessWidget {
  const _ReceiptDispatchBanner({required this.dispatch});

  final YorksV1MaterialDispatch dispatch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      border: Border.all(color: AppColors.primary.withValues(alpha: .24)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xxs),
          child: Icon(Icons.local_shipping_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dispatch.deliveryReference ?? dispatch.number,
                style: AppTypography.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${_dateLabel(dispatch.dispatchDate)} · ${dispatch.dispatchedByDisplayName}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReceiptLineIdentity extends StatelessWidget {
  const _ReceiptLineIdentity({required this.lineNumber, required this.line});

  final int lineNumber;
  final YorksV1DispatchLine line;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$lineNumber. ${line.description}', style: AppTypography.titleSmall),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '${_displayQuantity(line.dispatchedQuantity)} ${line.unit} ${YorksV1LogisticsStrings.dispatched.primary}',
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _ReceiptOutcomeChoices extends StatelessWidget {
  const _ReceiptOutcomeChoices({
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  final YorksV1ReceiptOutcome selected;
  final bool disabled;
  final ValueChanged<YorksV1ReceiptOutcome> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final option in YorksV1ReceiptOutcome.values)
        _ReceiptOutcomeButton(
          outcome: option,
          selected: selected == option,
          onPressed: disabled ? null : () => onChanged(option),
        ),
    ],
  );
}

class _ReceiptOutcomeButton extends StatelessWidget {
  const _ReceiptOutcomeButton({
    required this.outcome,
    required this.selected,
    required this.onPressed,
  });

  final YorksV1ReceiptOutcome outcome;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(
      outcome == YorksV1ReceiptOutcome.received
          ? Icons.check_rounded
          : outcome == YorksV1ReceiptOutcome.missing
          ? Icons.remove_circle_outline_rounded
          : Icons.warning_amber_rounded,
      size: 18,
    ),
    label: Text(yorksV1ReceiptOutcomeCopy(outcome).primary),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTapTarget),
      foregroundColor: selected ? AppColors.primary : AppColors.onSurface,
      backgroundColor: selected ? AppColors.blueContainer : null,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.line,
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
    ),
  );
}

class _ReceiptLineInputs extends StatelessWidget {
  const _ReceiptLineInputs({
    required this.outcome,
    required this.goodQuantity,
    required this.missingQuantity,
    required this.damagedQuantity,
    required this.note,
    required this.disabled,
  });

  final YorksV1ReceiptOutcome outcome;
  final TextEditingController goodQuantity;
  final TextEditingController missingQuantity;
  final TextEditingController damagedQuantity;
  final TextEditingController note;
  final bool disabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = [
        SizedBox(
          width: constraints.maxWidth >= 330 ? 150 : double.infinity,
          child: _QuantityInput(
            controller: goodQuantity,
            label: YorksV1LogisticsStrings.goodQuantity.primary,
            enabled: !disabled && outcome != YorksV1ReceiptOutcome.received,
          ),
        ),
        if (outcome == YorksV1ReceiptOutcome.mixed)
          SizedBox(
            width: constraints.maxWidth >= 330 ? 150 : double.infinity,
            child: _QuantityInput(
              controller: missingQuantity,
              label: YorksV1LogisticsStrings.missingQuantity.primary,
              enabled: !disabled,
            ),
          ),
        if (outcome == YorksV1ReceiptOutcome.mixed)
          SizedBox(
            width: constraints.maxWidth >= 330 ? 150 : double.infinity,
            child: _QuantityInput(
              controller: damagedQuantity,
              label: YorksV1LogisticsStrings.damagedQuantity.primary,
              enabled: !disabled,
            ),
          ),
        SizedBox(
          width: constraints.maxWidth >= 330 ? 196 : double.infinity,
          child: _TextInput(
            controller: note,
            label: YorksV1LogisticsStrings.exceptionNote.primary,
            enabled: !disabled,
          ),
        ),
      ];
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: fields,
      );
    },
  );
}

class _CandidateName extends StatelessWidget {
  const _CandidateName({required this.candidate});
  final YorksV1DispatchCandidate candidate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(candidate.description, style: AppTypography.bodyMedium),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        [
          candidate.brandOrigin,
          yorksV1LogisticsSourceCopy(candidate.source).primary,
          candidate.externalSupplier,
        ].whereType<String>().join(' · '),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final YorksV1DispatchState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: state == YorksV1DispatchState.received
          ? AppColors.successContainer
          : AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      yorksV1DispatchStateCopy(state).primary,
      style: AppTypography.labelSmall,
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(value, style: AppTypography.bodyMedium),
    ],
  );
}

class _Quantity extends StatelessWidget {
  const _Quantity({required this.value, required this.unit});
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Text('$value $unit');
}

class _QuantityInput extends StatelessWidget {
  const _QuantityInput({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
    this.errorText,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    onChanged: onChanged,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      errorText: errorText,
      errorMaxLines: 3,
      border: const OutlineInputBorder(),
    ),
  );
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _LogisticsError extends StatelessWidget {
  const _LogisticsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SecondaryButton(
      label: YorksV1LogisticsStrings.savingFailed.primary,
      icon: Icons.refresh_rounded,
      onPressed: onRetry,
    ),
  );
}

class _ActiveText extends StatelessWidget {
  const _ActiveText({
    required this.copy,
    required this.language,
    required this.style,
    this.center = false,
  });

  final TranslatableString copy;
  final AppLanguage language;
  final TextStyle style;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
    copy.active(language),
    textAlign: center ? TextAlign.center : TextAlign.start,
    textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
    style: style,
  );
}

double _number(String text) => double.tryParse(text) ?? 0;

double? _decimalNumber(String text) {
  final normalized = text.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,4})?$').hasMatch(normalized)) return null;
  final value = double.tryParse(normalized);
  return value != null && value.isFinite ? value : null;
}

String _quantityText(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();

String _displayQuantity(String raw) => yorksV1DisplayQuantity(raw);

String _dateLabel(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

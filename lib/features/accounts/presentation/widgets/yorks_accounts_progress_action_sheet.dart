import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_providers.dart';
import '../../domain/accounts_evidence_models.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_inputs.dart';
import '../../domain/accounts_models.dart';

Future<bool> showYorksAccountsProgressActionSheet(
  BuildContext context, {
  required String projectId,
  required YorksAccountsProgressEntry entry,
  required YorksAccountsProgressProjection projection,
  required AppLanguage language,
  String? projectReference,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ProgressActionSheet(
      projectId: projectId,
      entry: entry,
      projection: projection,
      language: language,
      projectReference: projectReference,
    ),
  );
  return result ?? false;
}

enum _ProgressAction { suggest, confirm, approveReview, returnReview }

class _ProgressActionSheet extends ConsumerStatefulWidget {
  const _ProgressActionSheet({
    required this.projectId,
    required this.entry,
    required this.projection,
    required this.language,
    this.projectReference,
  });

  final String projectId;
  final YorksAccountsProgressEntry entry;
  final YorksAccountsProgressProjection projection;
  final AppLanguage language;
  final String? projectReference;

  @override
  ConsumerState<_ProgressActionSheet> createState() =>
      _ProgressActionSheetState();
}

class _ProgressActionSheetState extends ConsumerState<_ProgressActionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _percentController;
  late final TextEditingController _evidenceController;
  late final TextEditingController _searchController;
  late final TextEditingController _reasonController;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  late final List<String> _selectedIds;
  List<YorksAccountsEvidenceDocument> _selectedEvidence = const [];
  List<YorksAccountsEvidenceDocument> _searchResults = const [];
  bool _evidenceLoading = false;
  bool _evidenceLoaded = false;
  bool _hasMoreEvidence = false;
  bool _committedWaitingRefresh = false;
  bool _submitting = false;
  int? _retryVersion;
  YorksAccountsDecimal? _currentConfirmedPercent;
  late _ProgressAction _action;
  String? _localError;
  bool _authorityLost = false;

  List<_ProgressAction> get _availableActions {
    final actions = <_ProgressAction>[];
    final rowActions = widget.entry.nextActions
        .where((action) => action.isAvailable)
        .map((action) => action.code)
        .toSet();
    if (widget.projection.commands.allows('suggest_progress') &&
        rowActions.contains('suggest_progress')) {
      actions.add(_ProgressAction.suggest);
    }
    if (widget.projection.commands.allows('confirm_progress') &&
        rowActions.contains('confirm_progress')) {
      actions.add(_ProgressAction.confirm);
    }
    if (widget.projection.commands.allows('review_progress') &&
        rowActions.contains('review_progress')) {
      actions
        ..add(_ProgressAction.approveReview)
        ..add(_ProgressAction.returnReview);
    }
    return actions;
  }

  @override
  void initState() {
    super.initState();
    final actions = _availableActions;
    _action = actions.isEmpty ? _ProgressAction.suggest : actions.first;
    _percentController = TextEditingController(
      text:
          (_action == _ProgressAction.suggest
                  ? widget.entry.suggestedPercent
                  : widget.entry.confirmedPercent)
              .canonicalText,
    );
    _evidenceController = TextEditingController(
      text: widget.entry.evidenceSummary ?? '',
    );
    _selectedIds = [...widget.entry.evidenceDocumentIds];
    _searchController = TextEditingController();
    _reasonController = TextEditingController();
    _percentController.addListener(_rebuildSummary);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEvidence());
  }

  void _rebuildSummary() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _percentController.dispose();
    _evidenceController.dispose();
    _searchTimer?.cancel();
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _isReview =>
      _action == _ProgressAction.approveReview ||
      _action == _ProgressAction.returnReview;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  String _actionLabel(_ProgressAction action) => switch (action) {
    _ProgressAction.suggest => _text('suggest_progress'),
    _ProgressAction.confirm => _text('confirm_progress'),
    _ProgressAction.approveReview => _text('approve_review'),
    _ProgressAction.returnReview => _text('return_for_changes'),
  };

  Future<void> _loadEvidence() async {
    if (!mounted) return;
    final generation = ++_searchGeneration;
    setState(() {
      _evidenceLoading = true;
      _localError = null;
    });
    try {
      final result = await ref
          .read(yorksAccountsEvidenceRepositoryProvider)
          .search(
            projectId: widget.projectId,
            query: _searchController.text.trim(),
            selectedDocumentIds: _selectedIds,
          );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        final previous = {for (final item in _selectedEvidence) item.id: item};
        _selectedEvidence = [
          for (final item in result.selected)
            if (previous[item.id] case final prior?) prior else item,
        ];
        if (result.selected.any(
          (item) =>
              previous[item.id] != null &&
              previous[item.id]!.currentVersionId != item.currentVersionId,
        )) {
          _localError = _text('evidence_changed');
        }
        _searchResults = result.documents;
        _hasMoreEvidence = result.hasMore;
        _evidenceLoaded = true;
      });
    } on YorksV1DomainException catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      if (error.code == YorksV1DomainErrorCode.unauthorized ||
          error.code == YorksV1DomainErrorCode.unauthenticated ||
          error.code == YorksV1DomainErrorCode.featureDisabled) {
        _clearEvidence();
        setState(() => _authorityLost = true);
      } else {
        setState(() => _localError = _text('evidence_load_failed'));
      }
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _localError = _text('evidence_load_failed'));
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _evidenceLoading = false);
      }
    }
  }

  void _clearEvidence() {
    _searchGeneration++;
    _selectedIds.clear();
    _selectedEvidence = const [];
    _searchResults = const [];
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), _loadEvidence);
  }

  void _toggleEvidence(YorksAccountsEvidenceDocument document) {
    setState(() {
      if (_selectedIds.contains(document.id)) {
        _selectedIds.remove(document.id);
        _selectedEvidence = _selectedEvidence
            .where((item) => item.id != document.id)
            .toList(growable: false);
      } else if (_selectedIds.length < 256) {
        _selectedIds.add(document.id);
        _selectedEvidence = [..._selectedEvidence, document];
      }
      _localError = null;
    });
  }

  Future<void> _preview(YorksAccountsEvidenceDocument document) async {
    try {
      final Uint8List bytes = await ref
          .read(yorksAccountsEvidenceRepositoryProvider)
          .preview(projectId: widget.projectId, document: document);
      if (!mounted) return;
      if (document.mimeType != 'application/pdf' &&
          document.mimeType != 'image/jpeg' &&
          document.mimeType != 'image/png') {
        setState(() => _localError = _text('evidence_preview_unavailable'));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 800,
            height: MediaQuery.sizeOf(context).height * .8,
            child: Column(
              children: [
                ListTile(
                  title: Text(document.fileName),
                  trailing: IconButton(
                    tooltip: _text('close'),
                    icon: const Icon(Icons.close),
                    onPressed: Navigator.of(context).pop,
                  ),
                ),
                Expanded(
                  child: document.mimeType == 'application/pdf'
                      ? PdfPreview(
                          build: (_) async => bytes,
                          allowPrinting: false,
                          allowSharing: false,
                          canChangePageFormat: false,
                          canDebug: false,
                        )
                      : InteractiveViewer(child: Image.memory(bytes)),
                ),
              ],
            ),
          ),
        ),
      );
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      if (error.code == YorksV1DomainErrorCode.unauthorized ||
          error.code == YorksV1DomainErrorCode.unauthenticated) {
        _clearEvidence();
        setState(() => _authorityLost = true);
      } else if (error.code == YorksV1DomainErrorCode.conflict) {
        await _loadEvidence();
        if (mounted) setState(() => _localError = _text('evidence_changed'));
      } else {
        setState(() => _localError = _text('progress_evidence_invalid'));
      }
    }
  }

  Future<bool> _validateEvidenceBeforeSubmit() async {
    try {
      final refreshed = await ref
          .read(yorksAccountsEvidenceRepositoryProvider)
          .search(
            projectId: widget.projectId,
            selectedDocumentIds: _selectedIds,
          );
      if (!mounted) return false;
      for (final id in _selectedIds) {
        final current = refreshed.selected
            .where((item) => item.id == id)
            .firstOrNull;
        final displayed = _selectedEvidence
            .where((item) => item.id == id)
            .firstOrNull;
        if (current == null ||
            displayed == null ||
            current.currentVersionId != displayed.currentVersionId) {
          setState(() {
            if (current == null) {
              _selectedEvidence = _selectedEvidence
                  .where((item) => item.id != id)
                  .toList(growable: false);
            }
            _localError = _text('evidence_changed');
          });
          return false;
        }
      }
      return true;
    } on YorksV1DomainException catch (error) {
      if (!mounted) return false;
      if (error.code == YorksV1DomainErrorCode.unauthorized ||
          error.code == YorksV1DomainErrorCode.unauthenticated) {
        _clearEvidence();
        setState(() => _authorityLost = true);
      } else {
        setState(() => _localError = _text('evidence_load_failed'));
      }
      return false;
    } catch (_) {
      if (mounted) setState(() => _localError = _text('evidence_load_failed'));
      return false;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _performSubmit();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _performSubmit() async {
    if (_committedWaitingRefresh) {
      final refreshed = await ref
          .read(
            yorksAccountsProjectControllerProvider(widget.projectId).notifier,
          )
          .refresh();
      if (!mounted) return;
      if (refreshed) Navigator.of(context).pop(true);
      return;
    }
    final currentState = ref.read(
      yorksAccountsProjectControllerProvider(widget.projectId),
    );
    if (currentState.isMutating) return;
    if (currentState.hasPendingCommand) {
      final result = await ref
          .read(
            yorksAccountsProjectControllerProvider(widget.projectId).notifier,
          )
          .reconcilePendingCommand();
      if (!mounted) return;
      if (result != null) Navigator.of(context).pop(true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _localError = null);
    if (!_isReview) {
      // A summary-only suggestion (or non-increasing confirmation) does not
      // require a document lookup. Do not turn optional evidence search into
      // a new global financial workflow precondition.
      if (_selectedIds.isNotEmpty &&
          (!_evidenceLoaded || !await _validateEvidenceBeforeSubmit())) {
        return;
      }
      final percent = YorksAccountsDecimal.tryParse(_percentController.text);
      if (_action == _ProgressAction.confirm &&
          percent != null &&
          percent.compareTo(
                _currentConfirmedPercent ?? widget.entry.confirmedPercent,
              ) >
              0 &&
          _selectedIds.isEmpty) {
        setState(() => _localError = _text('confirmation_needs_document'));
        return;
      }
      if (_action == _ProgressAction.suggest &&
          _selectedIds.isEmpty &&
          _evidenceController.text.trim().isEmpty) {
        setState(
          () => _localError = _text('evidence_summary_or_document_required'),
        );
        return;
      }
    }
    final controller = ref.read(
      yorksAccountsProjectControllerProvider(widget.projectId).notifier,
    );
    final reason = _reasonController.text.trim();
    YorksAccountsCommandResult? result;
    if (_isReview) {
      result = await controller.reviewProgress(
        YorksAccountsReviewInput(
          projectId: widget.projectId,
          progressEntryId: widget.entry.progressEntryId,
          expectedVersion: _retryVersion ?? widget.entry.recordVersion,
          decision: _action == _ProgressAction.approveReview
              ? YorksAccountsReviewDecision.approved
              : YorksAccountsReviewDecision.returned,
          reason: reason,
        ),
      );
    } else {
      final percent = YorksAccountsDecimal.tryParse(_percentController.text);
      if (percent == null) {
        setState(() => _localError = _text('invalid_percentage'));
        return;
      }
      final input = YorksAccountsProgressInput(
        projectId: widget.projectId,
        progressEntryId: widget.entry.progressEntryId,
        expectedVersion: _retryVersion ?? widget.entry.recordVersion,
        percent: percent,
        evidenceSummary: _evidenceController.text.trim(),
        evidenceDocumentIds: List.unmodifiable(_selectedIds),
        reason: reason,
      );
      result = _action == _ProgressAction.suggest
          ? await controller.suggestProgress(input)
          : await controller.confirmProgress(input);
    }
    if (!mounted) return;
    if (result != null) {
      final refreshed = ref.read(
        yorksAccountsProjectControllerProvider(widget.projectId),
      );
      if (refreshed.status != YorksAccountsViewStatus.success) {
        setState(() {
          _committedWaitingRefresh = true;
          _localError = _text('saved_refresh_failed');
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _action == _ProgressAction.suggest
                ? _text('suggestion_saved')
                : _text('progress_action_saved'),
          ),
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }
    final state = ref.read(
      yorksAccountsProjectControllerProvider(widget.projectId),
    );
    if (state.status == YorksAccountsViewStatus.conflict) {
      final controller = ref.read(
        yorksAccountsProjectControllerProvider(widget.projectId).notifier,
      );
      if (await controller.refresh() && mounted) {
        final current = ref
            .read(yorksAccountsProjectControllerProvider(widget.projectId))
            .progress
            ?.progress
            .where(
              (item) => item.progressEntryId == widget.entry.progressEntryId,
            )
            .firstOrNull;
        if (current != null) {
          setState(() {
            _retryVersion = current.recordVersion;
            _currentConfirmedPercent = current.confirmedPercent;
          });
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _localError = state.error?.serverMessage?.contains('EVIDENCE') == true
          ? _text('progress_evidence_invalid')
          : state.status == YorksAccountsViewStatus.conflict &&
                _retryVersion != null
          ? '${_text('stale_conflict')} '
                '${_text('current_version')} $_retryVersion'
          : _stateError(state.status);
    });
  }

  String _stateError(YorksAccountsViewStatus status) => switch (status) {
    YorksAccountsViewStatus.conflict => _text('stale_conflict'),
    YorksAccountsViewStatus.uncertain => _text('uncertain_commit'),
    YorksAccountsViewStatus.offline => _text('offline'),
    YorksAccountsViewStatus.forbidden => _text('forbidden'),
    YorksAccountsViewStatus.sessionExpired => _text('session_expired'),
    _ => _text('action_failed'),
  };

  @override
  Widget build(BuildContext context) {
    final actions = _availableActions;
    final state = ref.watch(
      yorksAccountsProjectControllerProvider(widget.projectId),
    );
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final denied =
        _authorityLost ||
        state.status == YorksAccountsViewStatus.forbidden ||
        state.status == YorksAccountsViewStatus.sessionExpired ||
        state.status == YorksAccountsViewStatus.unavailable;
    // A sheet must not continue rendering its opening snapshot after access
    // has been revoked. The provider purges the protected projection too.
    ref.listen<YorksAccountsProjectState>(
      yorksAccountsProjectControllerProvider(widget.projectId),
      (previous, next) {
        if ((previous != null &&
                previous.status != YorksAccountsViewStatus.idle &&
                next.status == YorksAccountsViewStatus.idle) ||
            next.error?.code == YorksV1DomainErrorCode.unauthorized ||
            next.error?.code == YorksV1DomainErrorCode.unauthenticated ||
            next.error?.code == YorksV1DomainErrorCode.featureDisabled) {
          _percentController.clear();
          _evidenceController.clear();
          _clearEvidence();
          _reasonController.clear();
          setState(() => _authorityLost = true);
        }
      },
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: (MediaQuery.sizeOf(context).height - keyboard) * .92,
        ),
        margin: EdgeInsets.only(bottom: keyboard),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
        child: denied
            ? _UnavailableBody(
                title: _authorityLost
                    ? _text('forbidden')
                    : _stateError(state.status),
                closeLabel: _text('close'),
              )
            : state.hasPendingCommand
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetHeader(
                    title: _text('uncertain_commit'),
                    subtitle: _text('progress_pending_help'),
                    closeLabel: _text('close'),
                  ),
                  _SheetFooter(
                    cancelLabel: _text('close'),
                    submitLabel: _text('reconcile_progress'),
                    isBusy: state.isMutating || _submitting,
                    onSubmit: _submit,
                  ),
                ],
              )
            : actions.isEmpty
            ? _UnavailableBody(
                title: _text('no_available_action'),
                closeLabel: _text('close'),
              )
            : Form(
                key: _formKey,
                child: Column(
                  children: [
                    _SheetHeader(
                      title: _text('progress_action'),
                      subtitle:
                          '${widget.entry.buildingName ?? '—'} · '
                          '${widget.entry.stageLabel ?? widget.entry.stageKey}',
                      closeLabel: _text('close'),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ProgressReviewContext(
                              project:
                                  widget.projectReference ?? widget.projectId,
                              building: widget.entry.buildingName ?? '—',
                              stage:
                                  widget.entry.stageLabel ??
                                  widget.entry.stageKey,
                              confirmedPercent:
                                  (_currentConfirmedPercent ??
                                          widget.entry.confirmedPercent)
                                      .canonicalText,
                              action: _actionLabel(_action),
                              proposedPercent: _isReview
                                  ? null
                                  : _percentController.text,
                              evidenceCount: _selectedIds.length,
                              evidenceLabels: [
                                for (final id in _selectedIds)
                                  _selectedEvidence
                                          .where((item) => item.id == id)
                                          .firstOrNull
                                          ?.fileName ??
                                      _text('evidence_unavailable'),
                              ],
                              reason: _reasonController.text,
                              text: _text,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            if (_action == _ProgressAction.suggest) ...[
                              Text(_text('suggestion_not_confirmation')),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            DropdownButtonFormField<_ProgressAction>(
                              initialValue: _action,
                              decoration: InputDecoration(
                                labelText: _text('action'),
                              ),
                              items: [
                                for (final action in actions)
                                  DropdownMenuItem(
                                    value: action,
                                    child: Text(_actionLabel(action)),
                                  ),
                              ],
                              onChanged: state.isMutating
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _action = value;
                                        _localError = null;
                                        if (!_isReview) {
                                          _percentController.text =
                                              (_action ==
                                                          _ProgressAction
                                                              .suggest
                                                      ? widget
                                                            .entry
                                                            .suggestedPercent
                                                      : widget
                                                            .entry
                                                            .confirmedPercent)
                                                  .canonicalText;
                                        }
                                      });
                                    },
                            ),
                            if (!_isReview) ...[
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _percentController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: _text('percentage'),
                                  suffixText: '%',
                                ),
                                validator: (value) {
                                  final percent = YorksAccountsDecimal.tryParse(
                                    value ?? '',
                                  );
                                  if (percent == null ||
                                      percent.isNegative ||
                                      percent.compareTo(
                                            YorksAccountsDecimal.hundred,
                                          ) >
                                          0) {
                                    return _text('invalid_percentage');
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _evidenceController,
                                minLines: 2,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  labelText: _text('evidence_summary'),
                                  helperText: _text('evidence_helper'),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                _text('select_evidence'),
                                style: AppTypography.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextField(
                                controller: _searchController,
                                onChanged: _searchChanged,
                                decoration: InputDecoration(
                                  labelText: _text('search_project_evidence'),
                                  prefixIcon: const Icon(Icons.search),
                                ),
                              ),
                              if (_evidenceLoading)
                                const LinearProgressIndicator(),
                              for (final id in _selectedIds)
                                Builder(
                                  builder: (context) {
                                    final document = _selectedEvidence
                                        .where((item) => item.id == id)
                                        .firstOrNull;
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.description_outlined,
                                      ),
                                      title: Text(
                                        document?.fileName ??
                                            _text('evidence_unavailable'),
                                      ),
                                      subtitle: document == null
                                          ? null
                                          : Text(
                                              '${document.reference ?? ''} · '
                                              '${_text('current_revision')} '
                                              '${document.revisionNumber}',
                                            ),
                                      trailing: Wrap(
                                        children: [
                                          if (document != null &&
                                              (document.mimeType ==
                                                      'application/pdf' ||
                                                  document.mimeType ==
                                                      'image/jpeg' ||
                                                  document.mimeType ==
                                                      'image/png'))
                                            IconButton(
                                              tooltip: _text(
                                                'preview_evidence',
                                              ),
                                              onPressed: () =>
                                                  _preview(document),
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                              ),
                                            ),
                                          IconButton(
                                            tooltip: _text('remove_evidence'),
                                            onPressed: () => setState(() {
                                              _selectedIds.remove(id);
                                              _selectedEvidence =
                                                  _selectedEvidence
                                                      .where(
                                                        (item) => item.id != id,
                                                      )
                                                      .toList(growable: false);
                                            }),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              for (final document in _searchResults.where(
                                (item) => !_selectedIds.contains(item.id),
                              ))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.insert_drive_file_outlined,
                                  ),
                                  title: Text(document.fileName),
                                  subtitle: Text(
                                    '${document.reference ?? ''} · '
                                    '${_text('current_revision')} '
                                    '${document.revisionNumber}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: _text('select_evidence'),
                                    onPressed: _selectedIds.length >= 256
                                        ? null
                                        : () => _toggleEvidence(document),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ),
                              if (!_evidenceLoading &&
                                  _searchResults.isEmpty &&
                                  _evidenceLoaded)
                                Text(_text('no_project_evidence')),
                              if (_hasMoreEvidence)
                                Text(_text('refine_evidence_search')),
                              Text(
                                _text('evidence_current_only'),
                                style: AppTypography.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _reasonController,
                              onChanged: (_) => setState(() {}),
                              minLines: 2,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: _text('reason'),
                              ),
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? _text('reason_required')
                                  : null,
                            ),
                            if (_localError != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _InlineError(message: _localError!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _SheetFooter(
                      cancelLabel: _text('cancel'),
                      submitLabel: _committedWaitingRefresh
                          ? _text('retry_refresh')
                          : _actionLabel(_action),
                      isBusy: state.isMutating || _submitting,
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.closeLabel,
  });

  final String title;
  final String subtitle;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.lg,
    ),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: AppTypography.bodyMedium),
            ],
          ),
        ),
        IconButton(
          tooltip: closeLabel,
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _ProgressReviewContext extends StatelessWidget {
  const _ProgressReviewContext({
    required this.project,
    required this.building,
    required this.stage,
    required this.confirmedPercent,
    required this.action,
    required this.proposedPercent,
    required this.evidenceCount,
    required this.evidenceLabels,
    required this.reason,
    required this.text,
  });

  final String project;
  final String building;
  final String stage;
  final String confirmedPercent;
  final String action;
  final String? proposedPercent;
  final int evidenceCount;
  final List<String> evidenceLabels;
  final String reason;
  final String Function(String) text;

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
        Text(text('review_before_submit'), style: AppTypography.titleMedium),
        Text('${text('project')}: $project'),
        Text('${text('building')}: $building'),
        Text('${text('stage')}: $stage'),
        Text('${text('confirmed_progress')}: $confirmedPercent%'),
        Text('${text('action')}: $action'),
        if (proposedPercent != null)
          Text('${text('proposed_progress')}: $proposedPercent%'),
        Text('${text('selected_evidence_count')}: $evidenceCount'),
        for (final label in evidenceLabels.take(3)) Text('• $label'),
        if (evidenceLabels.length > 3) Text('+${evidenceLabels.length - 3}'),
        Text('${text('reason')}: ${reason.isEmpty ? '—' : reason}'),
      ],
    ),
  );
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.cancelLabel,
    required this.submitLabel,
    required this.isBusy,
    required this.onSubmit,
  });

  final String cancelLabel;
  final String submitLabel;
  final bool isBusy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isBusy ? null : Navigator.of(context).pop,
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: isBusy ? null : onSubmit,
            child: isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(submitLabel),
          ),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.errorContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody({required this.title, required this.closeLabel});
  final String title;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 36),
        const SizedBox(height: AppSpacing.md),
        Text(title, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          onPressed: Navigator.of(context).pop,
          child: Text(closeLabel),
        ),
      ],
    ),
  );
}

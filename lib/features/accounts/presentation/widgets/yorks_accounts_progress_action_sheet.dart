import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_inputs.dart';
import '../../domain/accounts_models.dart';

Future<bool> showYorksAccountsProgressActionSheet(
  BuildContext context, {
  required String projectId,
  required YorksAccountsProgressEntry entry,
  required YorksAccountsProgressProjection projection,
  required AppLanguage language,
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
  });

  final String projectId;
  final YorksAccountsProgressEntry entry;
  final YorksAccountsProgressProjection projection;
  final AppLanguage language;

  @override
  ConsumerState<_ProgressActionSheet> createState() =>
      _ProgressActionSheetState();
}

class _ProgressActionSheetState extends ConsumerState<_ProgressActionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _percentController;
  late final TextEditingController _evidenceController;
  late final Set<String> _evidenceDocumentIds;
  late final TextEditingController _reasonController;
  late _ProgressAction _action;
  String? _localError;

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
    _evidenceDocumentIds = {...widget.entry.evidenceDocumentIds};
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _percentController.dispose();
    _evidenceController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _localError = null);
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
          expectedVersion: widget.entry.recordVersion,
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
        expectedVersion: widget.entry.recordVersion,
        percent: percent,
        evidenceSummary: _evidenceController.text.trim(),
        evidenceDocumentIds: _evidenceDocumentIds.toList(growable: false),
        reason: reason,
      );
      result = _action == _ProgressAction.suggest
          ? await controller.suggestProgress(input)
          : await controller.confirmProgress(input);
    }
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
      return;
    }
    final state = ref.read(
      yorksAccountsProjectControllerProvider(widget.projectId),
    );
    setState(() => _localError = _stateError(state.status));
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
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        margin: EdgeInsets.only(bottom: keyboard),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
        child: actions.isEmpty
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
                              _EvidenceFiles(
                                projectId: widget.projectId,
                                language: widget.language,
                                selected: _evidenceDocumentIds,
                                onToggle: (id, on) => setState(() {
                                  on
                                      ? _evidenceDocumentIds.add(id)
                                      : _evidenceDocumentIds.remove(id);
                                }),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _reasonController,
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
                      submitLabel: _actionLabel(_action),
                      isBusy: state.isMutating,
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Files on the project this progress can rest on, chosen by name. Evidence the
/// server accepts is operational, so that is what is offered.
class _EvidenceFiles extends ConsumerWidget {
  const _EvidenceFiles({
    required this.projectId,
    required this.language,
    required this.selected,
    required this.onToggle,
  });

  final String projectId;
  final AppLanguage language;
  final Set<String> selected;
  final void Function(String id, bool on) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents =
        (ref
                    .watch(yorksV1DocumentWorkspaceProvider(projectId))
                    .valueOrNull
                    ?.documents ??
                const <YorksV1Document>[])
            .where(
              (document) =>
                  !document.isArchived &&
                  document.classification ==
                      YorksV1DocumentClassification.operational,
            )
            .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1AccountsStrings.text(language, 'v2_progress_evidence'),
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (documents.isEmpty)
          Text(
            YorksV1AccountsStrings.text(language, 'v2_files_empty'),
            style: AppTypography.bodySmall,
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final document in documents)
                FilterChip(
                  label: Text(document.currentVersion.fileName),
                  selected: selected.contains(document.id),
                  onSelected: (on) => onToggle(document.id, on),
                ),
            ],
          ),
      ],
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

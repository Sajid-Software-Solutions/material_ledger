import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_receivables_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_models.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';

Future<bool> showYorksAccountsClaimDraftSheet(
  BuildContext context, {
  required String projectId,
  required YorksAccountsProgressProjection progress,
  required AppLanguage language,
  YorksAccountsClaimDetailProjection? existing,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClaimDraftSheet(
        projectId: projectId,
        progress: progress,
        language: language,
        existing: existing,
      ),
    ) ??
    false;

Future<bool> showYorksAccountsClaimActionsSheet(
  BuildContext context, {
  required String projectId,
  required String claimId,
  required YorksAccountsProgressProjection progress,
  required AppLanguage language,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClaimActionsSheet(
        projectId: projectId,
        claimId: claimId,
        progress: progress,
        language: language,
      ),
    ) ??
    false;

enum YorksInvoiceActionIntent {
  recordPayment,
  createPdc,
  transitionPdc,
  replacePdc,
}

Future<bool> showYorksAccountsInvoiceActionsSheet(
  BuildContext context, {
  required String projectId,
  required String invoiceId,
  required AppLanguage language,
  YorksInvoiceActionIntent? initialIntent,
  String? initialPdcId,
  YorksAccountsPdcStatus? initialPdcTarget,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvoiceActionsSheet(
        projectId: projectId,
        invoiceId: invoiceId,
        language: language,
        initialIntent: initialIntent,
        initialPdcId: initialPdcId,
        initialPdcTarget: initialPdcTarget,
      ),
    ) ??
    false;

class _ClaimDraftSheet extends ConsumerStatefulWidget {
  const _ClaimDraftSheet({
    required this.projectId,
    required this.progress,
    required this.language,
    required this.existing,
  });

  final String projectId;
  final YorksAccountsProgressProjection progress;
  final AppLanguage language;
  final YorksAccountsClaimDetailProjection? existing;

  @override
  ConsumerState<_ClaimDraftSheet> createState() => _ClaimDraftSheetState();
}

class _ClaimDraftSheetState extends ConsumerState<_ClaimDraftSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reference;
  late final TextEditingController _periodStart;
  late final TextEditingController _periodEnd;
  late final TextEditingController _notes;
  late final Map<String, TextEditingController> _amounts;
  late final Map<String, TextEditingController> _evidence;
  late final Set<String> _selected;
  String? _error;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  List<YorksAccountsProgressEntry> get _candidates {
    final existingIds =
        widget.existing?.claim.lines
            .map((line) => line.progressEntryId)
            .toSet() ??
        const <String>{};
    return widget.progress.progress
        .where(
          (entry) =>
              existingIds.contains(entry.progressEntryId) ||
              (entry.availableToClaim?.isPositive == true &&
                  (entry.reviewStatus ==
                          YorksAccountsReviewStatus.notRequired ||
                      entry.reviewStatus ==
                          YorksAccountsReviewStatus.approved)),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing?.claim;
    final today = DateTime.now().toUtc();
    final date =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    _reference = TextEditingController(text: existing?.claimReference ?? '');
    _periodStart = TextEditingController(
      text: existing?.periodStart.postgresText ?? date,
    );
    _periodEnd = TextEditingController(
      text: existing?.periodEnd.postgresText ?? date,
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    final lines = {
      for (final line
          in existing?.lines ?? const <YorksAccountsClientClaimLine>[])
        line.progressEntryId: line,
    };
    _selected = lines.keys.toSet();
    _amounts = {
      for (final entry in _candidates)
        entry.progressEntryId: TextEditingController(
          text:
              lines[entry.progressEntryId]?.claimedAmount?.canonicalText ??
              entry.availableToClaim?.canonicalText ??
              '',
        ),
    };
    _evidence = {
      for (final entry in _candidates)
        entry.progressEntryId: TextEditingController(
          text: lines[entry.progressEntryId]?.evidenceReference ?? '',
        ),
    };
  }

  @override
  void dispose() {
    _reference.dispose();
    _periodStart.dispose();
    _periodEnd.dispose();
    _notes.dispose();
    for (final controller in [..._amounts.values, ..._evidence.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = _text('claim_line_required'));
      return;
    }
    final lines = <YorksAccountsClaimLineInput>[];
    for (final id in _selected) {
      final amount = YorksAccountsDecimal.tryParse(_amounts[id]!.text);
      if (amount == null || !amount.isPositive) {
        setState(() => _error = _text('invalid_amount'));
        return;
      }
      final entry = _candidates.firstWhere(
        (candidate) => candidate.progressEntryId == id,
      );
      final cap = entry.availableToClaim;
      final existingAmount = widget.existing?.claim.lines
          .where((line) => line.progressEntryId == id)
          .firstOrNull
          ?.claimedAmount;
      final effectiveCap = cap == null
          ? existingAmount
          : cap + (existingAmount ?? YorksAccountsDecimal.zero);
      if (effectiveCap != null && amount.compareTo(effectiveCap) > 0) {
        setState(() => _error = _text('claim_amount_exceeds_available'));
        return;
      }
      lines.add(
        YorksAccountsClaimLineInput(
          progressEntryId: id,
          claimedAmount: amount,
          evidenceReference: _nullable(_evidence[id]!.text),
        ),
      );
    }
    final input = YorksAccountsClaimDraftInput(
      projectId: widget.projectId,
      claimReference: _reference.text,
      periodStart: YorksAccountsDate.parse(_periodStart.text),
      periodEnd: YorksAccountsDate.parse(_periodEnd.text),
      lines: lines,
      notes: _notes.text,
      claimId: widget.existing?.claim.claimId,
      expectedVersion: widget.existing?.claim.recordVersion,
    );
    final controller = ref.read(
      yorksAccountsReceivablesControllerProvider(widget.projectId).notifier,
    );
    final result = widget.existing == null
        ? await controller.createClaimDraft(input)
        : await controller.updateClaimDraft(input);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      final status = ref
          .read(yorksAccountsReceivablesControllerProvider(widget.projectId))
          .status;
      setState(() => _error = _commandError(widget.language, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsReceivablesControllerProvider(widget.projectId),
    );
    return _SheetFrame(
      title: widget.existing == null
          ? _text('prepare_claim')
          : _text('edit_claim'),
      subtitle: _text('claim_cap_guidance'),
      closeLabel: _text('close'),
      footer: _SheetFooter(
        cancelLabel: _text('cancel'),
        submitLabel: _text('save_draft'),
        busy: state.isMutating,
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(_text('claim_identity')),
            TextFormField(
              controller: _reference,
              decoration: InputDecoration(labelText: _text('claim_reference')),
              validator: _required(widget.language),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _periodStart,
                    decoration: InputDecoration(
                      labelText: _text('period_start'),
                      helperText: _text('date_format'),
                    ),
                    validator: _dateValidator(widget.language),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _periodEnd,
                    decoration: InputDecoration(
                      labelText: _text('period_end'),
                      helperText: _text('date_format'),
                    ),
                    validator: _dateValidator(widget.language),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel(_text('claim_lines')),
            if (_candidates.isEmpty)
              _InfoBox(_text('no_claimable_lines'))
            else
              for (final entry in _candidates)
                _ClaimLineEditor(
                  language: widget.language,
                  entry: entry,
                  selected: _selected.contains(entry.progressEntryId),
                  amount: _amounts[entry.progressEntryId]!,
                  evidence: _evidence[entry.progressEntryId]!,
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selected.add(entry.progressEntryId);
                    } else {
                      _selected.remove(entry.progressEntryId);
                    }
                    _error = null;
                  }),
                ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: _text('notes')),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorBox(_error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClaimActionsSheet extends ConsumerStatefulWidget {
  const _ClaimActionsSheet({
    required this.projectId,
    required this.claimId,
    required this.progress,
    required this.language,
  });

  final String projectId;
  final String claimId;
  final YorksAccountsProgressProjection progress;
  final AppLanguage language;

  @override
  ConsumerState<_ClaimActionsSheet> createState() => _ClaimActionsSheetState();
}

class _ClaimActionsSheetState extends ConsumerState<_ClaimActionsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref
          .read(
            yorksAccountsReceivablesControllerProvider(
              widget.projectId,
            ).notifier,
          )
          .loadClaim(widget.claimId),
    );
  }

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  Future<void> _entityAction(
    Future<YorksAccountsReceivablesCommandResult?> Function(
      YorksAccountsEntityActionInput input,
    )
    command,
  ) async {
    final detail = ref
        .read(yorksAccountsReceivablesControllerProvider(widget.projectId))
        .selectedClaim;
    if (detail == null) return;
    final reason = await _askForReason(context, widget.language);
    if (reason == null || !mounted) return;
    final result = await command(
      YorksAccountsEntityActionInput(
        projectId: widget.projectId,
        entityId: detail.claim.claimId,
        expectedVersion: detail.claim.recordVersion,
        reason: reason,
      ),
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsReceivablesControllerProvider(widget.projectId),
    );
    final detail = state.selectedClaim;
    if (detail == null || detail.claim.claimId != widget.claimId) {
      return _LoadingSheet(
        title: _text('claim_detail'),
        closeLabel: _text('close'),
        failed:
            state.status != YorksAccountsViewStatus.loading &&
            state.status != YorksAccountsViewStatus.idle,
        retryLabel: _text('retry'),
        onRetry: () => ref
            .read(
              yorksAccountsReceivablesControllerProvider(
                widget.projectId,
              ).notifier,
            )
            .loadClaim(widget.claimId),
      );
    }
    final claim = detail.claim;
    final commands = detail.commands;
    final controller = ref.read(
      yorksAccountsReceivablesControllerProvider(widget.projectId).notifier,
    );
    return _SheetFrame(
      title: claim.claimReference,
      subtitle:
          '${claim.periodStart.postgresText} – ${claim.periodEnd.postgresText}',
      closeLabel: _text('close'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusStrip(
            label: _text('status'),
            value: _statusLabel(claim.status.wireValue),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(_text('claim_lines')),
          for (final line in claim.lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${line.buildingName ?? '—'} · '
                '${line.stageLabel ?? line.stageKey}',
              ),
              subtitle: Text(line.evidenceReference ?? _text('no_evidence')),
              trailing: Text(
                line.claimedAmount?.canonicalText ?? '—',
                style: AppTypography.titleSmall,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (claim.status == YorksAccountsClaimStatus.draft &&
                  commands.editClaimDraft)
                OutlinedButton.icon(
                  onPressed: state.isMutating
                      ? null
                      : () async {
                          final changed =
                              await showYorksAccountsClaimDraftSheet(
                                context,
                                projectId: widget.projectId,
                                progress: widget.progress,
                                language: widget.language,
                                existing: detail,
                              );
                          if (changed && mounted) {
                            await controller.loadClaim(widget.claimId);
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(_text('edit_claim')),
                ),
              if (claim.status == YorksAccountsClaimStatus.draft &&
                  commands.submitClaimToAccounts)
                FilledButton.icon(
                  onPressed: state.isMutating
                      ? null
                      : () => _entityAction(controller.submitClaimToAccounts),
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_text('send_to_accounts')),
                ),
              if (claim.status == YorksAccountsClaimStatus.draft &&
                  commands.editClaimDraft)
                OutlinedButton.icon(
                  onPressed: state.isMutating
                      ? null
                      : () => _entityAction(controller.deleteClaimDraft),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(_text('delete_draft')),
                ),
              if (claim.status == YorksAccountsClaimStatus.readyForAccounts &&
                  commands.createInvoiceDraft)
                FilledButton.icon(
                  onPressed: state.isMutating
                      ? null
                      : () async {
                          final changed = await _showInvoiceDraftSheet(
                            context,
                            projectId: widget.projectId,
                            claim: claim,
                            language: widget.language,
                          );
                          if (!mounted) return;
                          if (changed) Navigator.of(this.context).pop(true);
                        },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(_text('create_invoice')),
                ),
              if (claim.status != YorksAccountsClaimStatus.cancelled &&
                  claim.status != YorksAccountsClaimStatus.invoiced &&
                  commands.cancelClaim)
                TextButton.icon(
                  onPressed: state.isMutating
                      ? null
                      : () => _entityAction(controller.cancelClaim),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(_text('cancel_claim')),
                ),
            ],
          ),
          if (state.isMutating) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

Future<bool> _showInvoiceDraftSheet(
  BuildContext context, {
  required String projectId,
  required YorksAccountsClientClaim claim,
  required AppLanguage language,
  YorksAccountsClientInvoice? existing,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InvoiceDraftSheet(
        projectId: projectId,
        claim: claim,
        language: language,
        existing: existing,
      ),
    ) ??
    false;

class _InvoiceDraftSheet extends ConsumerStatefulWidget {
  const _InvoiceDraftSheet({
    required this.projectId,
    required this.claim,
    required this.language,
    required this.existing,
  });

  final String projectId;
  final YorksAccountsClientClaim claim;
  final AppLanguage language;
  final YorksAccountsClientInvoice? existing;

  @override
  ConsumerState<_InvoiceDraftSheet> createState() => _InvoiceDraftSheetState();
}

class _InvoiceDraftSheetState extends ConsumerState<_InvoiceDraftSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reference;
  late final TextEditingController _notes;
  String? _error;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _reference = TextEditingController(
      text: widget.existing?.invoiceReference ?? '',
    );
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final input = YorksAccountsInvoiceDraftInput(
      projectId: widget.projectId,
      claimId: widget.existing == null ? widget.claim.claimId : null,
      invoiceId: widget.existing?.invoiceId,
      expectedVersion: widget.existing?.recordVersion,
      invoiceReference: _reference.text,
      notes: _notes.text,
    );
    final controller = ref.read(
      yorksAccountsReceivablesControllerProvider(widget.projectId).notifier,
    );
    final result = widget.existing == null
        ? await controller.createInvoiceDraft(input)
        : await controller.updateInvoiceDraft(input);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      final status = ref
          .read(yorksAccountsReceivablesControllerProvider(widget.projectId))
          .status;
      setState(() => _error = _commandError(widget.language, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsReceivablesControllerProvider(widget.projectId),
    );
    return _SheetFrame(
      title: widget.existing == null
          ? _text('create_invoice')
          : _text('edit_invoice'),
      subtitle: widget.claim.claimReference,
      closeLabel: _text('close'),
      footer: _SheetFooter(
        cancelLabel: _text('cancel'),
        submitLabel: _text('save_draft'),
        busy: state.isMutating,
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(_text('claim_identity')),
            _InfoBox(
              '${widget.claim.claimReference} · '
              '${widget.claim.claimedExVat?.canonicalText ?? '—'}',
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _reference,
              decoration: InputDecoration(
                labelText: _text('invoice_reference'),
              ),
              validator: _required(widget.language),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: _text('notes')),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorBox(_error!),
            ],
          ],
        ),
      ),
    );
  }
}

enum _InvoiceAction {
  edit,
  submit,
  underCertification,
  certify,
  recordPayment,
  reversePayment,
  createPdc,
  transitionPdc,
  replacePdc,
  returnInvoice,
  cancelInvoice,
}

class _InvoiceActionsSheet extends ConsumerStatefulWidget {
  const _InvoiceActionsSheet({
    required this.projectId,
    required this.invoiceId,
    required this.language,
    required this.initialIntent,
    required this.initialPdcId,
    required this.initialPdcTarget,
  });

  final String projectId;
  final String invoiceId;
  final AppLanguage language;
  final YorksInvoiceActionIntent? initialIntent;
  final String? initialPdcId;
  final YorksAccountsPdcStatus? initialPdcTarget;

  @override
  ConsumerState<_InvoiceActionsSheet> createState() =>
      _InvoiceActionsSheetState();
}

class _InvoiceActionsSheetState extends ConsumerState<_InvoiceActionsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _secondary = TextEditingController();
  final _reason = TextEditingController();
  _InvoiceAction? _action;
  YorksAccountsPdcStatus _pdcTarget = YorksAccountsPdcStatus.received;
  String? _selectedPaymentId;
  String? _selectedPdcId;
  String? _error;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _action = switch (widget.initialIntent) {
      YorksInvoiceActionIntent.recordPayment => _InvoiceAction.recordPayment,
      YorksInvoiceActionIntent.createPdc => _InvoiceAction.createPdc,
      YorksInvoiceActionIntent.transitionPdc => _InvoiceAction.transitionPdc,
      YorksInvoiceActionIntent.replacePdc => _InvoiceAction.replacePdc,
      null => null,
    };
    _selectedPdcId = widget.initialPdcId;
    _pdcTarget = widget.initialPdcTarget ?? YorksAccountsPdcStatus.received;
    final now = DateTime.now().toUtc();
    _date.text =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref
          .read(
            yorksAccountsReceivablesControllerProvider(
              widget.projectId,
            ).notifier,
          )
          .loadInvoice(widget.invoiceId),
    );
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reference.dispose();
    _secondary.dispose();
    _reason.dispose();
    super.dispose();
  }

  List<_InvoiceAction> _actions(YorksAccountsInvoiceDetailProjection detail) {
    final invoice = detail.invoice;
    final commands = detail.commands;
    return [
      if (invoice.status == YorksAccountsInvoiceStatus.draft &&
          commands.createInvoiceDraft)
        _InvoiceAction.edit,
      if ((invoice.status == YorksAccountsInvoiceStatus.draft ||
              invoice.status == YorksAccountsInvoiceStatus.returned) &&
          commands.submitInvoice)
        _InvoiceAction.submit,
      if (invoice.status == YorksAccountsInvoiceStatus.submitted &&
          commands.submitInvoice)
        _InvoiceAction.underCertification,
      if (commands.recordCertification &&
          invoice.status != YorksAccountsInvoiceStatus.cancelled &&
          invoice.status != YorksAccountsInvoiceStatus.paid)
        _InvoiceAction.certify,
      if (commands.recordPayment &&
          (invoice.certifiedInclVat?.isPositive == true) &&
          (invoice.stillDue?.isPositive == true))
        _InvoiceAction.recordPayment,
      if (commands.reversePayment &&
          detail.payments.any(
            (payment) =>
                payment.entryKind == YorksAccountsPaymentEntryKind.receipt,
          ))
        _InvoiceAction.reversePayment,
      if (commands.createPdc &&
          invoice.status != YorksAccountsInvoiceStatus.cancelled)
        _InvoiceAction.createPdc,
      if (commands.transitionPdc && detail.pdcs.isNotEmpty)
        _InvoiceAction.transitionPdc,
      if (commands.replacePdc && detail.pdcs.isNotEmpty)
        _InvoiceAction.replacePdc,
      if (commands.returnInvoice &&
          invoice.status != YorksAccountsInvoiceStatus.cancelled &&
          invoice.status != YorksAccountsInvoiceStatus.paid)
        _InvoiceAction.returnInvoice,
      if (commands.cancelInvoice &&
          invoice.status != YorksAccountsInvoiceStatus.cancelled &&
          invoice.status != YorksAccountsInvoiceStatus.paid)
        _InvoiceAction.cancelInvoice,
    ];
  }

  String _label(_InvoiceAction action) => switch (action) {
    _InvoiceAction.edit => _text('edit_invoice'),
    _InvoiceAction.submit => _text('submit_invoice'),
    _InvoiceAction.underCertification => _text('start_certification'),
    _InvoiceAction.certify => _text('record_certification'),
    _InvoiceAction.recordPayment => _text('record_payment'),
    _InvoiceAction.reversePayment => _text('reverse_payment'),
    _InvoiceAction.createPdc => _text('record_pdc'),
    _InvoiceAction.transitionPdc => _text('update_pdc'),
    _InvoiceAction.replacePdc => _text('replace_pdc'),
    _InvoiceAction.returnInvoice => _text('return_invoice'),
    _InvoiceAction.cancelInvoice => _text('cancel_invoice'),
  };

  bool get _needsAmount =>
      _action == _InvoiceAction.certify ||
      _action == _InvoiceAction.recordPayment ||
      _action == _InvoiceAction.createPdc ||
      _action == _InvoiceAction.replacePdc;

  bool get _needsDate =>
      _action != null &&
      _action != _InvoiceAction.edit &&
      _action != _InvoiceAction.underCertification &&
      _action != _InvoiceAction.returnInvoice &&
      _action != _InvoiceAction.cancelInvoice;

  bool get _needsReference =>
      _action == _InvoiceAction.certify ||
      _action == _InvoiceAction.recordPayment ||
      _action == _InvoiceAction.reversePayment ||
      _action == _InvoiceAction.createPdc ||
      _action == _InvoiceAction.replacePdc;

  Future<void> _submit(YorksAccountsInvoiceDetailProjection detail) async {
    final action = _action;
    if (action == null) return;
    if (action == _InvoiceAction.edit) {
      final changed = await _showInvoiceDraftSheet(
        context,
        projectId: widget.projectId,
        claim: detail.claim,
        language: widget.language,
        existing: detail.invoice,
      );
      if (changed && mounted) {
        await ref
            .read(
              yorksAccountsReceivablesControllerProvider(
                widget.projectId,
              ).notifier,
            )
            .loadInvoice(widget.invoiceId);
      }
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final invoice = detail.invoice;
    final controller = ref.read(
      yorksAccountsReceivablesControllerProvider(widget.projectId).notifier,
    );
    final date = YorksAccountsDate.tryParse(_date.text);
    final amount = YorksAccountsDecimal.tryParse(_amount.text);
    final reason = _nullable(_reason.text);
    YorksAccountsReceivablesCommandResult? result;
    switch (action) {
      case _InvoiceAction.submit:
        result = await controller.submitInvoice(
          YorksAccountsInvoiceSubmitInput(
            projectId: widget.projectId,
            invoiceId: invoice.invoiceId,
            expectedVersion: invoice.recordVersion,
            submissionDate: date!,
            adminExceptionReason: null,
          ),
        );
      case _InvoiceAction.underCertification:
      case _InvoiceAction.returnInvoice:
      case _InvoiceAction.cancelInvoice:
        final input = YorksAccountsEntityActionInput(
          projectId: widget.projectId,
          entityId: invoice.invoiceId,
          expectedVersion: invoice.recordVersion,
          reason: _reason.text,
        );
        result = switch (action) {
          _InvoiceAction.underCertification =>
            await controller.markUnderCertification(input),
          _InvoiceAction.returnInvoice => await controller.returnInvoice(input),
          _ => await controller.cancelInvoice(input),
        };
      case _InvoiceAction.certify:
        result = await controller.recordCertification(
          YorksAccountsCertificationInput(
            projectId: widget.projectId,
            invoiceId: invoice.invoiceId,
            expectedVersion: invoice.recordVersion,
            certifiedExVat: amount!,
            certificationDate: date!,
            certificationReference: _reference.text,
            differenceReason: amount == invoice.claimedExVat ? null : reason,
          ),
        );
      case _InvoiceAction.recordPayment:
        result = await controller.recordPayment(
          YorksAccountsPaymentInput(
            projectId: widget.projectId,
            invoiceId: invoice.invoiceId,
            expectedVersion: invoice.recordVersion,
            paymentDate: date!,
            amount: amount!,
            paymentMethod: _secondary.text,
            paymentReference: _reference.text,
            reason: reason,
          ),
        );
      case _InvoiceAction.reversePayment:
        result = await controller.reversePayment(
          YorksAccountsPaymentReversalInput(
            projectId: widget.projectId,
            invoiceId: invoice.invoiceId,
            expectedVersion: invoice.recordVersion,
            originalPaymentId: _selectedPaymentId!,
            reversalDate: date!,
            reversalReference: _reference.text,
            reason: _reason.text,
          ),
        );
      case _InvoiceAction.createPdc:
        result = await controller.createPdc(
          YorksAccountsPdcCreateInput(
            projectId: widget.projectId,
            invoiceId: invoice.invoiceId,
            expectedVersion: invoice.recordVersion,
            chequeNumber: _reference.text,
            chequeDate: date!,
            amount: amount!,
            bankName: _nullable(_secondary.text),
          ),
        );
      case _InvoiceAction.transitionPdc:
        result = await controller.transitionPdc(
          YorksAccountsPdcTransitionInput(
            projectId: widget.projectId,
            pdcId: _selectedPdcId!,
            expectedVersion: detail.pdcs
                .firstWhere((pdc) => pdc.pdcId == _selectedPdcId)
                .recordVersion,
            targetStatus: _pdcTarget,
            actionDate: date!,
            clearanceReference: _pdcTarget == YorksAccountsPdcStatus.cleared
                ? _nullable(_reference.text)
                : null,
            reason: reason,
          ),
        );
      case _InvoiceAction.replacePdc:
        result = await controller.replacePdc(
          YorksAccountsPdcReplacementInput(
            projectId: widget.projectId,
            originalPdcId: _selectedPdcId!,
            expectedVersion: detail.pdcs
                .firstWhere((pdc) => pdc.pdcId == _selectedPdcId)
                .recordVersion,
            chequeNumber: _reference.text,
            chequeDate: date!,
            amount: amount!,
            bankName: _nullable(_secondary.text),
            reason: _reason.text,
          ),
        );
      case _InvoiceAction.edit:
        return;
    }
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      final status = ref
          .read(yorksAccountsReceivablesControllerProvider(widget.projectId))
          .status;
      setState(() => _error = _commandError(widget.language, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsReceivablesControllerProvider(widget.projectId),
    );
    final detail = state.selectedInvoice;
    if (detail == null || detail.invoice.invoiceId != widget.invoiceId) {
      return _LoadingSheet(
        title: _text('invoice_detail'),
        closeLabel: _text('close'),
        failed:
            state.status != YorksAccountsViewStatus.loading &&
            state.status != YorksAccountsViewStatus.idle,
        retryLabel: _text('retry'),
        onRetry: () => ref
            .read(
              yorksAccountsReceivablesControllerProvider(
                widget.projectId,
              ).notifier,
            )
            .loadInvoice(widget.invoiceId),
      );
    }
    final actions = _actions(detail);
    _action ??= actions.firstOrNull;
    _selectedPaymentId ??= detail.payments
        .where(
          (payment) =>
              payment.entryKind == YorksAccountsPaymentEntryKind.receipt,
        )
        .firstOrNull
        ?.paymentId;
    _selectedPdcId ??= detail.pdcs.firstOrNull?.pdcId;
    final invoice = detail.invoice;
    return _SheetFrame(
      title: invoice.invoiceReference,
      subtitle:
          '${_statusLabel(invoice.status.wireValue)} · '
          '${invoice.dueDate?.postgresText ?? _text('not_submitted')}',
      closeLabel: _text('close'),
      footer: actions.isEmpty
          ? null
          : _SheetFooter(
              cancelLabel: _text('close'),
              submitLabel: _label(_action!),
              busy: state.isMutating,
              onSubmit: () => _submit(detail),
            ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InvoicePosition(detail: detail, language: widget.language),
            const SizedBox(height: AppSpacing.lg),
            if (actions.isEmpty)
              _InfoBox(_text('no_available_action'))
            else ...[
              DropdownButtonFormField<_InvoiceAction>(
                initialValue: _action,
                decoration: InputDecoration(labelText: _text('action')),
                items: [
                  for (final action in actions)
                    DropdownMenuItem(
                      value: action,
                      child: Text(_label(action)),
                    ),
                ],
                onChanged: state.isMutating
                    ? null
                    : (value) => setState(() {
                        _action = value;
                        _error = null;
                      }),
              ),
              if (_action == _InvoiceAction.reversePayment) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentId,
                  decoration: InputDecoration(
                    labelText: _text('payment_to_reverse'),
                  ),
                  items: [
                    for (final payment in detail.payments.where(
                      (entry) =>
                          entry.entryKind ==
                          YorksAccountsPaymentEntryKind.receipt,
                    ))
                      DropdownMenuItem(
                        value: payment.paymentId,
                        child: Text(
                          '${payment.paymentReference} · '
                          '${payment.amount?.canonicalText ?? '—'}',
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedPaymentId = value),
                ),
              ],
              if (_action == _InvoiceAction.transitionPdc ||
                  _action == _InvoiceAction.replacePdc) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPdcId,
                  decoration: InputDecoration(labelText: _text('pdc')),
                  items: [
                    for (final pdc in detail.pdcs)
                      DropdownMenuItem(
                        value: pdc.pdcId,
                        child: Text(
                          '${pdc.chequeNumber} · '
                          '${_statusLabel(pdc.status.wireValue)}',
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectedPdcId = value),
                ),
              ],
              if (_action == _InvoiceAction.transitionPdc) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<YorksAccountsPdcStatus>(
                  initialValue: _pdcTarget,
                  decoration: InputDecoration(labelText: _text('new_status')),
                  items: [
                    for (final status in YorksAccountsPdcStatus.values.where(
                      (status) =>
                          status != YorksAccountsPdcStatus.expected &&
                          status != YorksAccountsPdcStatus.replaced,
                    ))
                      DropdownMenuItem(
                        value: status,
                        child: Text(_statusLabel(status.wireValue)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _pdcTarget = value);
                  },
                ),
              ],
              if (_needsDate || _action == _InvoiceAction.submit) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _date,
                  decoration: InputDecoration(
                    labelText: _text('date'),
                    helperText: _text('date_format'),
                  ),
                  validator: _dateValidator(widget.language),
                ),
              ],
              if (_needsAmount) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: _text('amount')),
                  validator: _positiveAmount(widget.language),
                ),
              ],
              if (_needsReference) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _reference,
                  decoration: InputDecoration(labelText: _referenceLabel()),
                  validator: _required(widget.language),
                ),
              ],
              if (_action == _InvoiceAction.recordPayment ||
                  _action == _InvoiceAction.createPdc ||
                  _action == _InvoiceAction.replacePdc) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _secondary,
                  decoration: InputDecoration(
                    labelText: _action == _InvoiceAction.recordPayment
                        ? _text('payment_method')
                        : _text('bank_name'),
                  ),
                  validator: _action == _InvoiceAction.recordPayment
                      ? _required(widget.language)
                      : null,
                ),
              ],
              if (_action != _InvoiceAction.edit &&
                  _action != _InvoiceAction.submit &&
                  _action != _InvoiceAction.createPdc) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: _text('reason')),
                  validator: _reasonRequired
                      ? _required(widget.language)
                      : null,
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorBox(_error!),
            ],
          ],
        ),
      ),
    );
  }

  bool get _reasonRequired =>
      _action == _InvoiceAction.underCertification ||
      _action == _InvoiceAction.returnInvoice ||
      _action == _InvoiceAction.cancelInvoice ||
      _action == _InvoiceAction.reversePayment ||
      _action == _InvoiceAction.replacePdc ||
      (_action == _InvoiceAction.transitionPdc &&
          (_pdcTarget == YorksAccountsPdcStatus.returned ||
              _pdcTarget == YorksAccountsPdcStatus.bounced ||
              _pdcTarget == YorksAccountsPdcStatus.cancelled));

  String _referenceLabel() => switch (_action) {
    _InvoiceAction.certify => _text('certification_reference'),
    _InvoiceAction.recordPayment ||
    _InvoiceAction.reversePayment => _text('payment_reference'),
    _InvoiceAction.createPdc ||
    _InvoiceAction.replacePdc => _text('cheque_number'),
    _ => _text('reference'),
  };
}

class _InvoicePosition extends StatelessWidget {
  const _InvoicePosition({required this.detail, required this.language});
  final YorksAccountsInvoiceDetailProjection detail;
  final AppLanguage language;

  String _text(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionLabel(_text('current_position')),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _MetricChip(
            label: _text('claimed'),
            value: detail.invoice.claimedExVat?.canonicalText ?? '—',
          ),
          _MetricChip(
            label: _text('certified'),
            value: detail.invoice.certifiedInclVat?.canonicalText ?? '—',
          ),
          _MetricChip(
            label: _text('paid'),
            value: detail.invoice.paidAmount?.canonicalText ?? '—',
          ),
          _MetricChip(
            label: _text('still_due'),
            value: detail.invoice.stillDue?.canonicalText ?? '—',
          ),
          _MetricChip(
            label: _text('pdc'),
            value: detail.invoice.pdcExposure?.canonicalText ?? '—',
          ),
        ],
      ),
      if (detail.pdcs.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(_text('pdc')),
        for (final pdc in detail.pdcs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_note_outlined),
            title: Text(pdc.chequeNumber),
            subtitle: Text(
              '${pdc.chequeDate.postgresText} · '
              '${_statusLabel(pdc.status.wireValue)}',
            ),
            trailing: Text(pdc.amount?.canonicalText ?? '—'),
          ),
      ],
    ],
  );
}

class _ClaimLineEditor extends StatelessWidget {
  const _ClaimLineEditor({
    required this.language,
    required this.entry,
    required this.selected,
    required this.amount,
    required this.evidence,
    required this.onSelected,
  });

  final AppLanguage language;
  final YorksAccountsProgressEntry entry;
  final bool selected;
  final TextEditingController amount;
  final TextEditingController evidence;
  final ValueChanged<bool> onSelected;

  String _text(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: selected ? AppColors.blueContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected,
          onChanged: (value) => onSelected(value ?? false),
          title: Text(
            '${entry.buildingName ?? '—'} · '
            '${entry.stageLabel ?? entry.stageKey}',
          ),
          subtitle: Text(
            '${_text('available')}: '
            '${entry.availableToClaim?.canonicalText ?? '—'} · '
            '${_text('previously_claimed')}: '
            '${entry.previouslyClaimedAmount?.canonicalText ?? '—'}',
          ),
        ),
        if (selected) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: _text('claim_amount')),
            validator: _positiveAmount(language),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: evidence,
            decoration: InputDecoration(labelText: _text('evidence_reference')),
          ),
        ],
      ],
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.closeLabel,
    required this.child,
    this.footer,
  });

  final String title;
  final String subtitle;
  final String closeLabel;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: 760,
        maxHeight: MediaQuery.sizeOf(context).height * .94,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.lg,
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
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: child,
            ),
          ),
          footer ?? const SizedBox.shrink(),
        ],
      ),
    ),
  );
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.cancelLabel,
    required this.submitLabel,
    required this.busy,
    required this.onSubmit,
  });

  final String cancelLabel;
  final String submitLabel;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : Navigator.of(context).pop,
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: busy ? null : onSubmit,
            child: busy
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

class _LoadingSheet extends StatelessWidget {
  const _LoadingSheet({
    required this.title,
    required this.closeLabel,
    required this.failed,
    required this.retryLabel,
    required this.onRetry,
  });
  final String title;
  final String closeLabel;
  final bool failed;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: title,
    subtitle: failed ? retryLabel : '',
    closeLabel: closeLabel,
    child: Center(
      child: failed
          ? OutlinedButton(onPressed: onRetry, child: Text(retryLabel))
          : const CircularProgressIndicator(),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(label, style: AppTypography.titleSmall),
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Text(message),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);
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

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.successContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: AppTypography.titleSmall),
      ],
    ),
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall),
        Text(value, style: AppTypography.titleSmall),
      ],
    ),
  );
}

Future<String?> _askForReason(
  BuildContext context,
  AppLanguage language,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(YorksV1AccountsStrings.text(language, 'reason')),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          validator: _required(language),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(YorksV1AccountsStrings.text(language, 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: Text(YorksV1AccountsStrings.text(language, 'confirm')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

FormFieldValidator<String> _required(AppLanguage language) =>
    (value) => (value ?? '').trim().isEmpty
    ? YorksV1AccountsStrings.text(language, 'field_required')
    : null;

FormFieldValidator<String> _dateValidator(AppLanguage language) =>
    (value) => YorksAccountsDate.tryParse(value ?? '') == null
    ? YorksV1AccountsStrings.text(language, 'invalid_date')
    : null;

FormFieldValidator<String> _positiveAmount(AppLanguage language) => (value) {
  final amount = YorksAccountsDecimal.tryParse(value ?? '');
  return amount == null || !amount.isPositive || amount.fractionDigits > 2
      ? YorksV1AccountsStrings.text(language, 'invalid_amount')
      : null;
};

String _commandError(AppLanguage language, YorksAccountsViewStatus status) =>
    YorksV1AccountsStrings.text(language, switch (status) {
      YorksAccountsViewStatus.conflict => 'stale_conflict',
      YorksAccountsViewStatus.uncertain => 'uncertain_commit',
      YorksAccountsViewStatus.offline => 'offline',
      YorksAccountsViewStatus.forbidden => 'forbidden',
      YorksAccountsViewStatus.sessionExpired => 'session_expired',
      _ => 'action_failed',
    });

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _statusLabel(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

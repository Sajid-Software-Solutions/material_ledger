import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_records_providers.dart';
import '../../application/accounts_supplier_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_supplier_inputs.dart';
import '../../domain/accounts_supplier_models.dart';
import '../v2/accounts_v2_common.dart';
import 'yorks_accounts_records_views.dart';

Future<bool> showYorksAccountsSupplierBillDraftSheet(
  BuildContext context, {
  required String projectId,
  required AppLanguage language,
  YorksAccountsSupplierBill? existing,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierBillDraftSheet(
        projectId: projectId,
        language: language,
        existing: existing,
      ),
    ) ??
    false;

Future<bool> showYorksAccountsSupplierBillActionsSheet(
  BuildContext context, {
  required String projectId,
  required String supplierBillId,
  required AppLanguage language,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierBillActionsSheet(
        projectId: projectId,
        supplierBillId: supplierBillId,
        language: language,
      ),
    ) ??
    false;

class _SupplierBillDraftSheet extends ConsumerStatefulWidget {
  const _SupplierBillDraftSheet({
    required this.projectId,
    required this.language,
    required this.existing,
  });

  final String projectId;
  final AppLanguage language;
  final YorksAccountsSupplierBill? existing;

  @override
  ConsumerState<_SupplierBillDraftSheet> createState() =>
      _SupplierBillDraftSheetState();
}

class _SupplierBillDraftSheetState
    extends ConsumerState<_SupplierBillDraftSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _supplier;
  late final TextEditingController _invoiceReference;
  late final TextEditingController _invoiceDate;
  late final TextEditingController _dueDate;
  late final TextEditingController _exVat;
  late final TextEditingController _vatRate;
  late final TextEditingController _poReference;
  String? _poDocumentId;
  String? _receiptReviewId;
  String? _invoiceDocumentId;
  late final TextEditingController _mismatchReason;
  late final TextEditingController _notes;
  String? _error;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final bill = widget.existing;
    final date = accountsV2TodayIso();
    _supplier = TextEditingController(text: bill?.supplierName ?? '');
    _invoiceReference = TextEditingController(
      text: bill?.supplierInvoiceReference ?? '',
    );
    _invoiceDate = TextEditingController(
      text: bill?.invoiceDate.postgresText ?? date,
    );
    _dueDate = TextEditingController(text: bill?.dueDate.postgresText ?? date);
    _exVat = TextEditingController(text: bill?.exVatAmount.canonicalText ?? '');
    _vatRate = TextEditingController(
      text: bill?.vatRatePercent.canonicalText ?? '5',
    );
    _poReference = TextEditingController(text: bill?.poLpoReference ?? '');
    _poDocumentId = bill?.poLpoDocumentId;
    _receiptReviewId = bill?.acceptedReceiptReviewId;
    _invoiceDocumentId = bill?.supplierInvoiceDocumentId;
    _mismatchReason = TextEditingController(
      text: bill?.explicitMismatchReason ?? '',
    );
    _notes = TextEditingController(text: bill?.notes ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final documents = yorksAccountsDocumentsControllerProvider(
        widget.projectId,
      );
      if (ref.read(documents).status == YorksAccountsViewStatus.idle) {
        ref.read(documents.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _supplier,
      _invoiceReference,
      _invoiceDate,
      _dueDate,
      _exVat,
      _vatRate,
      _poReference,
      _mismatchReason,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final exVat = YorksAccountsDecimal.tryParse(_exVat.text);
    final vat = YorksAccountsDecimal.tryParse(_vatRate.text);
    final invoiceDate = YorksAccountsDate.tryParse(_invoiceDate.text);
    final dueDate = YorksAccountsDate.tryParse(_dueDate.text);
    if (exVat == null ||
        vat == null ||
        invoiceDate == null ||
        dueDate == null) {
      setState(() => _error = _text('review_invalid_fields'));
      return;
    }
    if (dueDate.postgresText.compareTo(invoiceDate.postgresText) < 0) {
      setState(
        () => _error = YorksV1AccountsStrings.text(
          widget.language,
          'v2_sup_due_before',
        ),
      );
      return;
    }
    final input = YorksAccountsSupplierBillDraftInput(
      projectId: widget.projectId,
      supplierName: _supplier.text,
      supplierInvoiceReference: _invoiceReference.text,
      invoiceDate: invoiceDate,
      dueDate: dueDate,
      exVatAmount: exVat,
      vatRatePercent: vat,
      poLpoReference: _nullable(_poReference.text),
      poLpoDocumentId: _poDocumentId,
      acceptedReceiptReviewId: _receiptReviewId,
      supplierInvoiceDocumentId: _invoiceDocumentId,
      explicitMismatchReason: _nullable(_mismatchReason.text),
      notes: _nullable(_notes.text),
      supplierBillId: widget.existing?.supplierBillId,
      expectedVersion: widget.existing?.recordVersion,
    );
    final controller = ref.read(
      yorksAccountsSupplierControllerProvider(widget.projectId).notifier,
    );
    final result = widget.existing == null
        ? await controller.createBillDraft(input)
        : await controller.updateBillDraft(input);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      final status = ref
          .read(yorksAccountsSupplierControllerProvider(widget.projectId))
          .status;
      setState(() => _error = _commandError(widget.language, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsSupplierControllerProvider(widget.projectId),
    );
    return _SheetFrame(
      title: widget.existing == null
          ? _text('new_supplier_bill')
          : _text('edit_supplier_bill'),
      subtitle: _text('three_way_match_guidance'),
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
            _SectionLabel(_text('supplier_invoice')),
            _ResponsiveFields(
              children: [
                TextFormField(
                  controller: _supplier,
                  decoration: InputDecoration(
                    labelText: _text('supplier_name'),
                  ),
                  validator: _required(widget.language),
                ),
                TextFormField(
                  controller: _invoiceReference,
                  decoration: InputDecoration(
                    labelText: _text('supplier_invoice_reference'),
                  ),
                  validator: _required(widget.language),
                ),
                AccountsV2DateField(
                  label: _text('invoice_date'),
                  controller: _invoiceDate,
                  language: widget.language,
                ),
                AccountsV2DateField(
                  label: _text('due_date'),
                  controller: _dueDate,
                  language: widget.language,
                ),
                TextFormField(
                  controller: _exVat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: _text('ex_vat')),
                  validator: _positiveAmount(widget.language),
                ),
                TextFormField(
                  controller: _vatRate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _text('vat_rate'),
                    suffixText: '%',
                  ),
                  validator: _percentage(widget.language),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel(_text('three_way_match')),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _EvidenceCard(
                    title: _text('po_lpo'),
                    icon: Icons.request_quote_outlined,
                    children: [
                      TextFormField(
                        controller: _poReference,
                        decoration: InputDecoration(
                          labelText: _text('po_lpo_reference'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DocumentPicker(
                        projectId: widget.projectId,
                        language: widget.language,
                        uploadType: YorksV1AccountsDocumentType.poLpo,
                        billId: widget.existing?.supplierBillId,
                        value: _poDocumentId,
                        onChanged: (id) => setState(() => _poDocumentId = id),
                      ),
                    ],
                  ),
                  _EvidenceCard(
                    title: _text('accepted_delivery'),
                    icon: Icons.local_shipping_outlined,
                    children: [
                      _DeliveryPicker(
                        projectId: widget.projectId,
                        language: widget.language,
                        value: _receiptReviewId,
                        current: widget.existing?.acceptedDelivery,
                        onChanged: (id) =>
                            setState(() => _receiptReviewId = id),
                      ),
                    ],
                  ),
                  _EvidenceCard(
                    title: _text('supplier_invoice'),
                    icon: Icons.receipt_long_outlined,
                    children: [
                      _DocumentPicker(
                        projectId: widget.projectId,
                        language: widget.language,
                        uploadType: YorksV1AccountsDocumentType.supplierInvoice,
                        billId: widget.existing?.supplierBillId,
                        value: _invoiceDocumentId,
                        onChanged: (id) =>
                            setState(() => _invoiceDocumentId = id),
                      ),
                    ],
                  ),
                ];
                if (constraints.maxWidth < 680) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      Expanded(child: cards[index]),
                      if (index != cards.length - 1)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _mismatchReason,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(labelText: _text('mismatch_reason')),
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

/// Chooses a commercial file on this project, the only kind the server accepts
/// as evidence, or adds a new one, instead of asking for a database ID.
class _DocumentPicker extends ConsumerWidget {
  const _DocumentPicker({
    required this.projectId,
    required this.language,
    required this.uploadType,
    required this.value,
    required this.onChanged,
    this.billId,
  });

  final String projectId;
  final AppLanguage language;
  final YorksV1AccountsDocumentType uploadType;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// The bill being edited, which a new file links to. A new bill has no record
  /// to link to until its draft is saved.
  final String? billId;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  static String _label(YorksV1Document document) {
    final version = document.currentVersion;
    final reference = version.businessReference;
    return reference == null || reference.isEmpty
        ? version.fileName
        : '${version.fileName} · $reference';
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    YorksV1AccountsDocumentWorkspace workspace,
  ) async {
    final known = {for (final document in workspace.documents) document.id};
    final saved = await showYorksAccountsDocumentUploadDialog(
      context,
      projectId: projectId,
      language: language,
      workspace: workspace,
      initialType: uploadType,
      initialTargetEntityId: billId,
    );
    if (saved != true) return;
    final updated = ref
        .read(yorksAccountsDocumentsControllerProvider(projectId))
        .workspace;
    for (final document in updated?.documents ?? const <YorksV1Document>[]) {
      if (!known.contains(document.id)) {
        onChanged(document.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref
        .watch(yorksAccountsDocumentsControllerProvider(projectId))
        .workspace;
    final documents = (workspace?.documents ?? const <YorksV1Document>[])
        .where(
          (document) =>
              !document.isArchived &&
              document.classification ==
                  YorksV1DocumentClassification.commercial,
        )
        .toList(growable: false);
    final selected = value;
    final isListed = documents.any((document) => document.id == selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey<String>('${selected}_${documents.length}'),
          isExpanded: true,
          initialValue: selected,
          decoration: InputDecoration(labelText: _t('v2_sup_pick_document')),
          items: [
            DropdownMenuItem<String?>(child: Text(_t('v2_sup_pick_none'))),
            // A linked file this list can't show must stay linked, not vanish.
            if (selected != null && !isListed)
              DropdownMenuItem<String?>(
                value: selected,
                child: Text(_t('v2_sup_linked')),
              ),
            for (final document in documents)
              DropdownMenuItem<String?>(
                value: document.id,
                child: Text(_label(document), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
        if (billId == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _t('v2_sup_save_first'),
              style: AppTypography.bodySmall,
            ),
          )
        else if (workspace != null &&
            workspace.uploadTargets.any((t) => t.entityId == billId))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _add(context, ref, workspace),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(_t('v2_sup_add_document')),
            ),
          ),
      ],
    );
  }
}

/// Chooses a confirmed delivery on this project by its reference.
class _DeliveryPicker extends ConsumerWidget {
  const _DeliveryPicker({
    required this.projectId,
    required this.language,
    required this.value,
    required this.current,
    required this.onChanged,
  });

  final String projectId;
  final AppLanguage language;
  final String? value;
  final YorksAccountsAcceptedDelivery? current;
  final ValueChanged<String?> onChanged;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  String _label(YorksAccountsAcceptedDelivery delivery) {
    final reviewed = delivery.reviewedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${delivery.deliveryReference} · '
        '${reviewed.year}-${two(reviewed.month)}-${two(reviewed.day)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(
      yorksAccountsSupplierDeliveryOptionsProvider(projectId),
    );
    final deliveries = [
      ...?options.valueOrNull,
      // Keep a delivery already on the bill visible if the list can't show it.
      if (current != null &&
          !(options.valueOrNull ?? const []).any(
            (delivery) => delivery.receiptReviewId == current!.receiptReviewId,
          ))
        current!,
    ];
    final selected = value;
    final isListed = deliveries.any(
      (delivery) => delivery.receiptReviewId == selected,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey<String>('${selected}_${deliveries.length}'),
          isExpanded: true,
          initialValue: selected,
          decoration: InputDecoration(labelText: _t('v2_sup_pick_delivery')),
          items: [
            DropdownMenuItem<String?>(child: Text(_t('v2_sup_pick_none'))),
            if (selected != null && !isListed)
              DropdownMenuItem<String?>(
                value: selected,
                child: Text(_t('v2_sup_linked')),
              ),
            for (final delivery in deliveries)
              DropdownMenuItem<String?>(
                value: delivery.receiptReviewId,
                child: Text(_label(delivery), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
        if (options.hasValue && deliveries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _t('v2_sup_no_deliveries'),
              style: AppTypography.bodySmall,
            ),
          ),
      ],
    );
  }
}

enum _SupplierAction { edit, approve, payment, reversePayment, cancel }

class _SupplierBillActionsSheet extends ConsumerStatefulWidget {
  const _SupplierBillActionsSheet({
    required this.projectId,
    required this.supplierBillId,
    required this.language,
  });

  final String projectId;
  final String supplierBillId;
  final AppLanguage language;

  @override
  ConsumerState<_SupplierBillActionsSheet> createState() =>
      _SupplierBillActionsSheetState();
}

class _SupplierBillActionsSheetState
    extends ConsumerState<_SupplierBillActionsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _date = TextEditingController();
  final _amount = TextEditingController();
  final _method = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  final _adminException = TextEditingController();
  _SupplierAction? _action;
  String? _selectedPaymentId;
  String? _error;

  String _text(String key) => YorksV1AccountsStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _date.text = accountsV2TodayIso();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref
          .read(
            yorksAccountsSupplierControllerProvider(widget.projectId).notifier,
          )
          .loadBill(widget.supplierBillId),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _date,
      _amount,
      _method,
      _reference,
      _reason,
      _adminException,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<_SupplierAction> _actions(
    YorksAccountsSupplierBillDetailProjection detail,
  ) {
    final bill = detail.supplierBill;
    final commands = detail.commands;
    return [
      if (commands.editBill &&
          bill.status == YorksAccountsSupplierBillStatus.draft)
        _SupplierAction.edit,
      if (commands.approveBill &&
          bill.status == YorksAccountsSupplierBillStatus.draft)
        _SupplierAction.approve,
      if (commands.recordPayment &&
          bill.status == YorksAccountsSupplierBillStatus.approved &&
          bill.outstandingAmount.isPositive)
        _SupplierAction.payment,
      if (commands.reversePayment &&
          detail.payments.any(
            (payment) =>
                payment.entryKind ==
                YorksAccountsSupplierPaymentEntryKind.payment,
          ))
        _SupplierAction.reversePayment,
      if (commands.cancelBill &&
          bill.status != YorksAccountsSupplierBillStatus.cancelled)
        _SupplierAction.cancel,
    ];
  }

  String _label(_SupplierAction action) => switch (action) {
    _SupplierAction.edit => _text('edit_supplier_bill'),
    _SupplierAction.approve => _text('approve_supplier_bill'),
    _SupplierAction.payment => _text('record_supplier_payment'),
    _SupplierAction.reversePayment => _text('reverse_payment'),
    _SupplierAction.cancel => _text('cancel_supplier_bill'),
  };

  Future<void> _submit(YorksAccountsSupplierBillDetailProjection detail) async {
    final action = _action;
    if (action == null) return;
    if (action == _SupplierAction.edit) {
      final changed = await showYorksAccountsSupplierBillDraftSheet(
        context,
        projectId: widget.projectId,
        language: widget.language,
        existing: detail.supplierBill,
      );
      if (!mounted) return;
      if (changed) {
        await ref
            .read(
              yorksAccountsSupplierControllerProvider(
                widget.projectId,
              ).notifier,
            )
            .loadBill(widget.supplierBillId);
      }
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final bill = detail.supplierBill;
    final controller = ref.read(
      yorksAccountsSupplierControllerProvider(widget.projectId).notifier,
    );
    final date = YorksAccountsDate.tryParse(_date.text);
    final amount = YorksAccountsDecimal.tryParse(_amount.text);
    YorksAccountsSupplierCommandResult? result;
    switch (action) {
      case _SupplierAction.approve:
        result = await controller.approveBill(
          YorksAccountsSupplierBillApprovalInput(
            projectId: widget.projectId,
            supplierBillId: bill.supplierBillId,
            expectedVersion: bill.recordVersion,
            adminExceptionReason: _nullable(_adminException.text),
          ),
        );
      case _SupplierAction.payment:
        result = await controller.recordPayment(
          YorksAccountsSupplierPaymentInput(
            projectId: widget.projectId,
            supplierBillId: bill.supplierBillId,
            expectedVersion: bill.recordVersion,
            paymentDate: date!,
            paymentMethod: _method.text,
            paymentReference: _reference.text,
            amount: amount!,
            reason: _nullable(_reason.text),
            adminExceptionReason: _nullable(_adminException.text),
          ),
        );
      case _SupplierAction.reversePayment:
        result = await controller.reversePayment(
          YorksAccountsSupplierPaymentReversalInput(
            projectId: widget.projectId,
            supplierBillId: bill.supplierBillId,
            expectedVersion: bill.recordVersion,
            originalPaymentId: _selectedPaymentId!,
            reversalDate: date!,
            reversalReference: _reference.text,
            reason: _reason.text,
          ),
        );
      case _SupplierAction.cancel:
        result = await controller.cancelBill(
          YorksAccountsSupplierBillCancelInput(
            projectId: widget.projectId,
            supplierBillId: bill.supplierBillId,
            expectedVersion: bill.recordVersion,
            reason: _reason.text,
          ),
        );
      case _SupplierAction.edit:
        return;
    }
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      final status = ref
          .read(yorksAccountsSupplierControllerProvider(widget.projectId))
          .status;
      setState(() => _error = _commandError(widget.language, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsSupplierControllerProvider(widget.projectId),
    );
    final detail = state.selectedBill;
    if (detail == null ||
        detail.supplierBill.supplierBillId != widget.supplierBillId) {
      return _LoadingSheet(
        title: _text('supplier_bill_detail'),
        closeLabel: _text('close'),
        failed:
            state.status != YorksAccountsViewStatus.loading &&
            state.status != YorksAccountsViewStatus.idle,
        retryLabel: _text('retry'),
        onRetry: () => ref
            .read(
              yorksAccountsSupplierControllerProvider(
                widget.projectId,
              ).notifier,
            )
            .loadBill(widget.supplierBillId),
      );
    }
    final bill = detail.supplierBill;
    final actions = _actions(detail);
    _action ??= actions.firstOrNull;
    _selectedPaymentId ??= detail.payments
        .where(
          (payment) =>
              payment.entryKind ==
              YorksAccountsSupplierPaymentEntryKind.payment,
        )
        .firstOrNull
        ?.paymentId;
    return _SheetFrame(
      title: bill.supplierInvoiceReference,
      subtitle:
          '${bill.supplierName} · ${_statusLabel(bill.matchStatus.wireValue)}',
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
            _MatchPosition(bill: bill, language: widget.language),
            const SizedBox(height: AppSpacing.lg),
            if (actions.isEmpty)
              _InfoBox(_text('no_available_action'))
            else ...[
              DropdownButtonFormField<_SupplierAction>(
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
              if (_action == _SupplierAction.reversePayment) ...[
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
                          YorksAccountsSupplierPaymentEntryKind.payment,
                    ))
                      DropdownMenuItem(
                        value: payment.paymentId,
                        child: Text(
                          '${payment.paymentReference} · '
                          '${payment.amount.canonicalText}',
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedPaymentId = value),
                ),
              ],
              if (_action == _SupplierAction.payment ||
                  _action == _SupplierAction.reversePayment) ...[
                const SizedBox(height: AppSpacing.md),
                AccountsV2DateField(
                  label: _text('date'),
                  controller: _date,
                  language: widget.language,
                ),
              ],
              if (_action == _SupplierAction.payment) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: _text('amount')),
                  validator: _positiveAmount(widget.language),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _method,
                  decoration: InputDecoration(
                    labelText: _text('payment_method'),
                  ),
                  validator: _required(widget.language),
                ),
              ],
              if (_action == _SupplierAction.payment ||
                  _action == _SupplierAction.reversePayment) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _reference,
                  decoration: InputDecoration(
                    labelText: _text('payment_reference'),
                  ),
                  validator: _required(widget.language),
                ),
              ],
              if (_action == _SupplierAction.cancel ||
                  _action == _SupplierAction.reversePayment ||
                  _action == _SupplierAction.payment) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: _text('reason')),
                  validator:
                      _action == _SupplierAction.cancel ||
                          _action == _SupplierAction.reversePayment
                      ? _required(widget.language)
                      : null,
                ),
              ],
              if (_action == _SupplierAction.approve ||
                  _action == _SupplierAction.payment) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _adminException,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _text('admin_exception_reason'),
                    helperText: _text('admin_exception_helper'),
                  ),
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
}

class _MatchPosition extends StatelessWidget {
  const _MatchPosition({required this.bill, required this.language});
  final YorksAccountsSupplierBill bill;
  final AppLanguage language;

  String _text(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionLabel(_text('three_way_match')),
      LayoutBuilder(
        builder: (context, constraints) {
          final cards = [
            // The server counts a PO only with both its reference and its file.
            _MatchFact(
              title: _text('po_lpo'),
              present:
                  bill.poLpoDocumentId != null && bill.poLpoReference != null,
              detail: switch ((bill.poLpoReference, bill.poLpoDocumentId)) {
                (null, null) => _text('missing_evidence'),
                (null, _) => _text('v2_sup_po_needs_reference'),
                (final reference?, null) =>
                  '$reference · ${_text('v2_sup_po_needs_file')}',
                (final reference?, _) => reference,
              },
            ),
            _MatchFact(
              title: _text('accepted_delivery'),
              present: bill.acceptedDelivery != null,
              detail:
                  bill.acceptedDeliveryReference ?? _text('missing_evidence'),
            ),
            _MatchFact(
              title: _text('supplier_invoice'),
              present: bill.supplierInvoiceDocumentId != null,
              detail: _text(
                bill.supplierInvoiceDocumentId == null
                    ? 'missing_evidence'
                    : 'v2_sup_linked',
              ),
            ),
          ];
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in cards) ...[
                  card,
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                Expanded(child: cards[index]),
                if (index != cards.length - 1)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.md),
      _InfoBox(
        '${_text('match_status')}: '
        '${_statusLabel(bill.matchStatus.wireValue)} · '
        '${_text('payment_status')}: '
        '${_statusLabel(bill.paymentStatus.wireValue)} · '
        '${_text('still_due')}: ${bill.outstandingAmount.canonicalText}',
      ),
      if (bill.explicitMismatchReason != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _ErrorBox(bill.explicitMismatchReason!),
      ],
    ],
  );
}

class _MatchFact extends StatelessWidget {
  const _MatchFact({
    required this.title,
    required this.present,
    required this.detail,
  });
  final String title;
  final bool present;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: present ? AppColors.successContainer : AppColors.warningContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          present ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          color: present ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: AppTypography.titleSmall),
        Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: AppTypography.titleSmall)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    ),
  );
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Column(
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      }
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - AppSpacing.md) / 2,
              child: child,
            ),
        ],
      );
    },
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
        maxWidth: 820,
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

FormFieldValidator<String> _required(AppLanguage language) =>
    (value) => (value ?? '').trim().isEmpty
    ? YorksV1AccountsStrings.text(language, 'field_required')
    : null;

FormFieldValidator<String> _positiveAmount(AppLanguage language) => (value) {
  final amount = YorksAccountsDecimal.tryParse(value ?? '');
  return amount == null || !amount.isPositive || amount.fractionDigits > 2
      ? YorksV1AccountsStrings.text(language, 'invalid_amount')
      : null;
};

FormFieldValidator<String> _percentage(AppLanguage language) => (value) {
  final amount = YorksAccountsDecimal.tryParse(value ?? '');
  return amount == null ||
          amount.isNegative ||
          amount.compareTo(YorksAccountsDecimal.hundred) > 0
      ? YorksV1AccountsStrings.text(language, 'invalid_percentage')
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

/// R39 Accounts Workspace V2 — contract variations (VO) register card.
///
/// Lists variation orders (VO no., description, amount, status) on the Contract
/// tab and, for configuring actors, adds/edits them. Register only: approved
/// variations do not change the contract value.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/v2/variations_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

/// Creates (variationId null) or edits a variation; null on success or an error.
typedef YorksSaveVariationAction =
    Future<String?> Function({
      String? variationId,
      required String voNumber,
      String? description,
      String? amount,
      required String status,
      int? expectedVersion,
    });

class AccountsV2VariationsCard extends StatelessWidget {
  const AccountsV2VariationsCard({
    super.key,
    required this.variations,
    required this.canConfigure,
    required this.language,
    required this.format,
    this.onSave,
  });

  final List<YorksAccountsVariation> variations;
  final bool canConfigure;
  final AppLanguage language;
  final AccountsV2Format format;
  final YorksSaveVariationAction? onSave;

  String _t(String key) => accountsV2Text(language, key);

  bool get _canEdit => canConfigure && onSave != null;

  Future<void> _edit(BuildContext context, YorksAccountsVariation? v) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _VariationDialog(variation: v, language: language, onSave: onSave!),
    );
    if (saved == true) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final add = _canEdit
        ? AccountsV2Button(
            label: _t('v2_add_variation'),
            icon: 'plus',
            kind: AccountsV2ButtonKind.primary,
            size: AccountsV2ButtonSize.small,
            onPressed: () => _edit(context, null),
          )
        : null;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'edit',
            tone: AccountsV2Tone.org,
            title: _t('v2_variations_title'),
            subtitle: _t('v2c_variations_sub'),
            actions: [?add],
          ),
          if (variations.isEmpty)
            AccountsV2Empty(
              icon: 'edit',
              title: _t('v2c_no_records'),
              body: _t('v2_variations_empty'),
              action: _canEdit
                  ? AccountsV2Button(
                      label: _t('v2_add_variation'),
                      icon: 'plus',
                      onPressed: () => _edit(context, null),
                    )
                  : null,
            )
          else
            AccountsV2Table(
              columns: [
                AccountsV2Column(_t('v2c_vo_no'), width: 130),
                AccountsV2Column(_t('v2c_description')),
                AccountsV2Column(
                  _t('v2c_amount_aed'),
                  width: 180,
                  numeric: true,
                ),
                AccountsV2Column(_t('v2c_status'), width: 150),
                const AccountsV2Column('', width: 56, numeric: true),
              ],
              rows: [
                for (final v in variations)
                  AccountsV2Row([
                    Text(
                      v.voNumber,
                      style: v2Style(12.5, weight: FontWeight.w700),
                    ),
                    Text(v.description ?? '—'),
                    Text(
                      format.money(v.amount, withCurrency: false),
                      style: v2Style(12.5, tabular: true),
                    ),
                    _VariationStatusChip(status: v.status, language: language),
                    _canEdit
                        ? AccountsV2Button(
                            label: '',
                            icon: 'pen',
                            kind: AccountsV2ButtonKind.ghost,
                            size: AccountsV2ButtonSize.small,
                            tooltip: _t('v2_edit'),
                            onPressed: () => _edit(context, v),
                          )
                        : const SizedBox.shrink(),
                  ], onTap: _canEdit ? () => _edit(context, v) : null),
              ],
            ),
        ],
      ),
    );
  }
}

class _VariationStatusChip extends StatelessWidget {
  const _VariationStatusChip({required this.status, required this.language});

  final String status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final label = accountsV2Text(language, 'v2_vo_status_$status');
    return switch (status) {
      'approved' => StatusChip.success(label),
      'rejected' => StatusChip.error(label),
      _ => StatusChip.warning(label),
    };
  }
}

class _VariationDialog extends StatefulWidget {
  const _VariationDialog({
    required this.variation,
    required this.language,
    required this.onSave,
  });

  final YorksAccountsVariation? variation;
  final AppLanguage language;
  final YorksSaveVariationAction onSave;

  @override
  State<_VariationDialog> createState() => _VariationDialogState();
}

class _VariationDialogState extends State<_VariationDialog> {
  late final TextEditingController _voNumber;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late String _status;
  bool _saving = false;

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final v = widget.variation;
    _voNumber = TextEditingController(text: v?.voNumber ?? '');
    _description = TextEditingController(text: v?.description ?? '');
    _amount = TextEditingController(text: v?.amount?.canonicalText ?? '');
    _status = v?.status ?? 'pending';
  }

  @override
  void dispose() {
    for (final c in [_voNumber, _description, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (_voNumber.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final error = await widget.onSave(
      variationId: widget.variation?.variationId,
      voNumber: _voNumber.text.trim(),
      description: _trim(_description),
      amount: _trim(_amount),
      status: _status,
      expectedVersion: widget.variation?.recordVersion,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(accountsV2ErrorText(widget.language, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('v2_variations_title')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogField(label: _t('v2_vo_number'), controller: _voNumber),
            _DialogField(
              label: _t('v2_vo_description'),
              controller: _description,
            ),
            _DialogField(
              label: _t('v2_vo_amount'),
              controller: _amount,
              numeric: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('v2_vo_status'),
                    style: AppTypography.bodyMedium,
                  ),
                ),
                DropdownButton<String>(
                  value: _status,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _status = v ?? 'pending'),
                  items: [
                    for (final s in const ['pending', 'approved', 'rejected'])
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          accountsV2Text(widget.language, 'v2_vo_status_$s'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? _t('v2_saving') : _t('v2_save')),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.controller,
    this.numeric = false,
  });

  final String label;
  final TextEditingController controller;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: TextField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

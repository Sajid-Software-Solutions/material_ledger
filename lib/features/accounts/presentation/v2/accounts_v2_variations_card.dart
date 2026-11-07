/// R39 Accounts Workspace V2 — contract variations (VO) register card.
///
/// Lists variation orders (VO no., description, amount, status) on the Contract
/// tab and, for configuring actors, adds/edits them. Register only: approved
/// variations do not change the contract value.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/v2/variations_models.dart';
import 'accounts_v2_common.dart';

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
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_variations_title'),
            number: 5,
            trailing: _canEdit
                ? TextButton.icon(
                    onPressed: () => _edit(context, null),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(_t('v2_add_variation')),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (variations.isEmpty)
            Text(
              _t('v2_variations_empty'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            )
          else
            for (final v in variations)
              _VariationRow(
                variation: v,
                format: format,
                language: language,
                onTap: _canEdit ? () => _edit(context, v) : null,
              ),
        ],
      ),
    );
  }
}

class _VariationRow extends StatelessWidget {
  const _VariationRow({
    required this.variation,
    required this.format,
    required this.language,
    required this.onTap,
  });

  final YorksAccountsVariation variation;
  final AccountsV2Format format;
  final AppLanguage language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        variation.voNumber,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _VariationStatusChip(
                        status: variation.status,
                        language: language,
                      ),
                    ],
                  ),
                  if (variation.description != null &&
                      variation.description!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      variation.description!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              format.money(variation.amount),
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
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

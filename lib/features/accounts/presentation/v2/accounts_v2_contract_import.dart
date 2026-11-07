part of 'accounts_v2_contract_tab.dart';

/// Reviews a parsed Project Master File and saves it as a contract revision.
///
/// The contract value is shown as an editable, explicit choice because a workbook
/// and the project can legitimately disagree. Anything the parser could not read
/// is listed as a blocker and prevents saving. The server re-validates the save.
class _MasterFileImportDialog extends StatefulWidget {
  const _MasterFileImportDialog({
    required this.file,
    required this.setup,
    required this.buildings,
    required this.language,
    required this.onApply,
  });

  final YorksAccountsMasterImportFile file;
  final YorksAccountsCommercialSetupRead setup;
  final List<YorksContractBuildingOption> buildings;
  final AppLanguage language;
  final YorksApplyMasterImportAction? onApply;

  @override
  State<_MasterFileImportDialog> createState() =>
      _MasterFileImportDialogState();
}

class _MasterFileImportDialogState extends State<_MasterFileImportDialog> {
  late final TextEditingController _contract;
  late final TextEditingController _vat;
  late final TextEditingController _unit;
  bool _saving = false;
  String? _error;

  YorksAccountsMasterFileDraft get _draft => widget.file.draft;
  AccountsV2Format get _format =>
      AccountsV2Format(currencyCode: _draft.currencyCode);
  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _contract = TextEditingController(text: _draft.contractValue.canonicalText);
    _vat = TextEditingController(
      text: widget.setup.vatRatePercent?.canonicalText ?? '5',
    );
    _unit = TextEditingController(text: 'Nos');
  }

  @override
  void dispose() {
    _contract.dispose();
    _vat.dispose();
    _unit.dispose();
    super.dispose();
  }

  /// Workbook building code → project scope, matched on the code in the name.
  Map<String, String> get _scopeIds {
    final out = <String, String>{};
    for (final b in _draft.buildings) {
      final code = b.code?.toLowerCase();
      if (code == null) continue;
      for (final option in widget.buildings) {
        if ((option.code?.toLowerCase() == code) ||
            option.name.toLowerCase().contains(code)) {
          out[b.code!] = option.scopeId;
          break;
        }
      }
    }
    return out;
  }

  List<YorksAccountsMasterBuilding> get _unmatched {
    final ids = _scopeIds;
    return _draft.buildings
        .where((b) => b.code != null && !ids.containsKey(b.code))
        .toList(growable: false);
  }

  bool get _needsUnit => _draft.items.any((i) => i.unit == null);

  YorksAccountsCommercialSetup? _build() {
    final contract = YorksAccountsDecimal.tryParse(_contract.text.trim());
    final vat = YorksAccountsDecimal.tryParse(_vat.text.trim());
    final unit = _unit.text.trim();
    if (contract == null || !contract.isPositive || vat == null) return null;
    if (_needsUnit && unit.isEmpty) return null;
    if (_draft.hasBlockers || _unmatched.isNotEmpty) return null;
    final setup = _draft.toCommercialSetup(
      contractValue: contract,
      vatRatePercent: vat,
      scopeIdByCode: _scopeIds,
      defaultUnit: unit,
      paymentTermsDays: widget.setup.paymentTermsDays,
      reminderLeadDays: widget.setup.reminderLeadDays,
    );
    return setup.isValid ? setup : null;
  }

  Future<void> _save() async {
    final setup = _build();
    if (setup == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onApply!(
      setup,
      'Master file import: ${widget.file.fileName} sha256:${widget.file.sha256}',
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = accountsV2ErrorText(widget.language, error);
      });
    }
  }

  String _issueText(YorksAccountsMasterFileIssue issue) {
    var text = _t('v2_import_issue_${issue.code}');
    issue.args.forEach((key, value) {
      final amount = {'file', 'current', 'stated', 'total'}.contains(key)
          ? _format.money(YorksAccountsDecimal.tryParse(value))
          : value;
      text = text.replaceAll('{$key}', amount);
    });
    return text;
  }

  String _pct(YorksAccountsDecimal fraction) =>
      '${yorksAccountsFractionToPercent(fraction).displayText(maximumFractionDigits: 4)}%';

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final fileValue = draft.fileContractValue;
    final blocked = draft.hasBlockers || _unmatched.isNotEmpty;
    final ready = _build() != null;
    return AlertDialog(
      title: Text(_t('v2_import_preview_title')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.file.fileName,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final issue in draft.issues)
                _IssueRow(severity: issue.severity, text: _issueText(issue)),
              for (final b in _unmatched)
                _IssueRow(
                  severity: YorksAccountsMasterIssueSeverity.blocking,
                  text: _t(
                    'v2_import_issue_building_unmatched',
                  ).replaceAll('{building}', b.code ?? b.name),
                ),
              if (blocked) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _t('v2_import_blocked'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('import-contract-value'),
                controller: _contract,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText:
                      '${_t('v2_contract_value')} (${draft.currencyCode})',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (fileValue != null &&
                  fileValue.compareTo(
                        YorksAccountsDecimal.tryParse(_contract.text.trim()) ??
                            YorksAccountsDecimal.zero,
                      ) !=
                      0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(
                      () => _contract.text = fileValue.canonicalText,
                    ),
                    child: Text(
                      '${_t('v2_import_use_workbook')}: '
                      '${_format.money(fileValue)}',
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _t('v2_vat_label'),
                        suffixText: '%',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_needsUnit) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _unit,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: _t('v2_import_default_unit'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AccountsV2SectionTitle(_t('v2_buildings_title')),
              const SizedBox(height: AppSpacing.xs),
              for (final b in draft.buildings) _kv(b.name, _pct(b.fraction)),
              const SizedBox(height: AppSpacing.md),
              AccountsV2SectionTitle(_t('v2_stages_title')),
              const SizedBox(height: AppSpacing.xs),
              for (final s in draft.stages)
                _kv(
                  s.mode == 'items'
                      ? '${s.label} · ${draft.itemsForStage(s.key).length} '
                            '${_t('v2_import_items')}'
                      : s.label,
                  _pct(s.fraction),
                ),
              for (final s in draft.stages.where((s) => s.mode == 'items'))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${_t('v2_items_title')} · ${s.label}',
                    style: AppTypography.labelLarge,
                  ),
                  children: [
                    for (final item in draft.itemsForStage(s.key))
                      _kv(
                        '${item.name} · '
                        '${item.quantity.displayText(maximumFractionDigits: 2)} '
                        '${item.unit ?? _unit.text.trim()}',
                        _pct(item.weightFraction),
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _t('v2_import_review_note'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: (_saving || !ready || widget.onApply == null)
              ? null
              : _save,
          child: Text(_saving ? _t('v2_saving') : _t('v2_import_confirm')),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySmall)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.severity, required this.text});

  final YorksAccountsMasterIssueSeverity severity;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (severity) {
      YorksAccountsMasterIssueSeverity.blocking => (
        Icons.error_outline,
        AppColors.error,
      ),
      YorksAccountsMasterIssueSeverity.warning => (
        Icons.warning_amber_rounded,
        AppColors.warning,
      ),
      YorksAccountsMasterIssueSeverity.info => (
        Icons.info_outline,
        AppColors.muted,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.bodySmall)),
        ],
      ),
    );
  }
}

/// Edits invoice numbering: the prefix drives the next generated number.
class _InvoiceSettingsDialog extends StatefulWidget {
  const _InvoiceSettingsDialog({
    required this.settings,
    required this.language,
    required this.onSave,
  });

  final YorksAccountsSetupReadInvoiceSettings? settings;
  final AppLanguage language;
  final YorksSaveInvoiceSettingsAction onSave;

  @override
  State<_InvoiceSettingsDialog> createState() => _InvoiceSettingsDialogState();
}

class _InvoiceSettingsDialogState extends State<_InvoiceSettingsDialog> {
  late final TextEditingController _prefix;
  late final TextEditingController _scope;
  late final TextEditingController _attention;
  bool _saving = false;
  String? _error;

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _prefix = TextEditingController(text: s?.invoicePrefix ?? '');
    _scope = TextEditingController(text: s?.scopeLine ?? '');
    _attention = TextEditingController(text: s?.attentionName ?? '');
  }

  @override
  void dispose() {
    _prefix.dispose();
    _scope.dispose();
    _attention.dispose();
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      invoicePrefix: _prefix.text.trim(),
      scopeLine: _opt(_scope),
      attentionName: _opt(_attention),
      billToPartyId: widget.settings?.billToPartyId,
      expectedVersion: widget.settings?.recordVersion,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = accountsV2ErrorText(widget.language, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
    return AlertDialog(
      title: Text(_t('v2_invoice_numbering_title')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _prefix,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: deco(_t('v2_invoice_prefix_label')),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _scope,
              decoration: deco(_t('v2_scope_line_label')),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _attention,
              decoration: deco(_t('v2_attention_name_label')),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: (_saving || _prefix.text.trim().isEmpty) ? null : _save,
          child: Text(_saving ? _t('v2_saving') : _t('v2_save')),
        ),
      ],
    );
  }
}

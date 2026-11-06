/// R39 Accounts Workspace V2 — Contract tab.
///
/// Shows the commercial setup (`v1_get_project_commercial_setup`) with the live
/// setup check, and is where a contract is created and changed: a first-contract
/// start for a new project, the editor for percent and item stages, the Project
/// Master File import, invoice numbering and variations. Every save goes through
/// a server command that re-validates it; nothing is shown as saved until the
/// server confirms. Commercial content needs commercial-value access.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/accounts_master_file_parser.dart';
import '../../domain/v2/commercial_setup_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/variations_models.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_variations_card.dart';

part 'accounts_v2_contract_editor.dart';
part 'accounts_v2_contract_import.dart';

/// Saves the editable contract references; null on success or an error message.
typedef YorksSaveReferencesAction =
    Future<String?> Function({
      String? clientTrn,
      String? workOrderNumber,
      String? workOrderDate,
      String? contractNumber,
      String? retentionPercent,
      int? expectedProfileVersion,
    });

/// A picked and parsed workbook, ready for review.
typedef YorksAccountsMasterImportFile = ({
  YorksAccountsMasterFileDraft draft,
  String fileName,
  String sha256,
});

/// Picks and parses a Project Master File. Null means the pick was cancelled; a
/// thrown error means the file could not be read as a workbook.
typedef YorksImportMasterFileAction =
    Future<YorksAccountsMasterImportFile?> Function();

/// Saves an imported setup with an audit note; null on success or a failure code.
typedef YorksApplyMasterImportAction =
    Future<String?> Function(YorksAccountsCommercialSetup setup, String note);

/// Saves invoice numbering; null on success or a failure code.
typedef YorksSaveInvoiceSettingsAction =
    Future<String?> Function({
      required String invoicePrefix,
      String? scopeLine,
      String? attentionName,
      String? billToPartyId,
      int? expectedVersion,
    });

/// A project building a contract can be split across.
typedef YorksContractBuildingOption = ({
  String scopeId,
  String name,
  String? code,
});

/// A stage from the protected default template.
typedef YorksContractStageOption = ({
  String key,
  String label,
  YorksAccountsDecimal percent,
});

class AccountsV2ContractTab extends StatefulWidget {
  const AccountsV2ContractTab({
    super.key,
    required this.setup,
    required this.language,
    this.canEdit = false,
    this.onSave,
    this.onSaveReferences,
    this.variations = const [],
    this.onSaveVariation,
    this.onImportMasterFile,
    this.onApplyImport,
    this.onSaveInvoiceSettings,
    this.canManageInvoices = false,
    this.buildingOptions = const [],
    this.stageOptions = const [],
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;

  /// Whether the actor may configure commercials (configure_project_commercials).
  final bool canEdit;

  /// Saves the edited setup; returns null on success or an error message.
  final Future<String?> Function(YorksAccountsCommercialSetup setup)? onSave;

  /// Saves the editable contract references; null on success or an error.
  final YorksSaveReferencesAction? onSaveReferences;

  /// The contract variations (VO register).
  final List<YorksAccountsVariation> variations;

  /// Creates/edits a variation; null when the register is read-only.
  final YorksSaveVariationAction? onSaveVariation;

  /// Picks and parses a Project Master File for review.
  final YorksImportMasterFileAction? onImportMasterFile;

  /// Saves a reviewed import.
  final YorksApplyMasterImportAction? onApplyImport;

  /// Saves invoice numbering (needs manage_client_invoices).
  final YorksSaveInvoiceSettingsAction? onSaveInvoiceSettings;
  final bool canManageInvoices;

  /// The project's physical buildings (needed before a first contract exists).
  final List<YorksContractBuildingOption> buildingOptions;

  /// The default stage template.
  final List<YorksContractStageOption> stageOptions;

  @override
  State<AccountsV2ContractTab> createState() => _AccountsV2ContractTabState();
}

class _AccountsV2ContractTabState extends State<AccountsV2ContractTab> {
  bool _editing = false;

  /// The server stores one item list per building but saves one list for all of
  /// them, so a contract whose buildings differ can't be edited here safely.
  bool get _itemsVaryByBuilding {
    for (final stage in widget.setup.stages.where((s) => s.isItemsMode)) {
      final byBuilding = <String, List<String>>{};
      for (final it in widget.setup.itemsForStage(stage.stageKey)) {
        byBuilding
            .putIfAbsent(it.projectScopeId, () => [])
            .add(
              '${it.itemKey}|${it.itemLabel}|${it.quantity.canonicalText}|'
              '${it.unitCode}|${it.weightPercentOfContract.canonicalText}',
            );
      }
      if (byBuilding.values.map((v) => v.join(';')).toSet().length > 1) {
        return true;
      }
    }
    return false;
  }

  bool get _canEdit =>
      widget.canEdit && widget.onSave != null && !_itemsVaryByBuilding;
  bool get _itemsBlocked => widget.canEdit && _itemsVaryByBuilding;

  /// Every building a contract could use: the current split plus any others.
  List<YorksContractBuildingOption> get _buildingChoices => [
    for (final b in widget.setup.buildings)
      (scopeId: b.projectScopeId, name: b.name, code: null),
    for (final o in widget.buildingOptions)
      if (!widget.setup.buildings.any((b) => b.projectScopeId == o.scopeId)) o,
  ];

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final String failed = accountsV2Text(widget.language, 'v2_import_failed');
    final YorksAccountsMasterImportFile? file;
    try {
      file = await widget.onImportMasterFile!();
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    if (!context.mounted || file == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MasterFileImportDialog(
        file: file!,
        setup: widget.setup,
        buildings: [
          ...widget.buildingOptions,
          for (final b in widget.setup.buildings)
            if (!widget.buildingOptions.any(
              (o) => o.scopeId == b.projectScopeId,
            ))
              (scopeId: b.projectScopeId, name: b.name, code: null),
        ],
        language: widget.language,
        onApply: widget.onApplyImport,
      ),
    );
    if (saved == true) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(accountsV2Text(widget.language, 'v2_import_saved')),
        ),
      );
    }
  }

  Future<void> _editInvoiceSettings(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _InvoiceSettingsDialog(
        settings: widget.setup.invoiceSettings,
        language: widget.language,
        onSave: widget.onSaveInvoiceSettings!,
      ),
    );
    if (saved == true) {
      messenger?.showSnackBar(
        SnackBar(content: Text(accountsV2Text(widget.language, 'v2_saved'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    final language = widget.language;
    final format = AccountsV2Format(currencyCode: setup.currencyCode ?? 'AED');

    // Only a missing capability is "hidden"; a project with no contract yet is
    // not, and must not look locked to the person who has to set it up.
    if (!setup.capabilities.viewProjectCommercialValues) {
      return _CommercialHidden(
        language: language,
        hasBaseline: setup.hasBaseline,
      );
    }

    if (_editing) {
      return _ContractEditor(
        setup: setup,
        buildingChoices: _buildingChoices,
        stageOptions: widget.stageOptions,
        language: language,
        onCancel: () => setState(() => _editing = false),
        onSave: (form) async {
          final error = await widget.onSave!(form);
          if (mounted && error == null) setState(() => _editing = false);
          return error;
        },
      );
    }

    if (!setup.hasBaseline) {
      return _FirstContractStart(
        language: language,
        canEdit: widget.canEdit && widget.onSave != null,
        hasBuildings: _buildingChoices.isNotEmpty,
        onStart: () => setState(() => _editing = true),
        onImport:
            widget.onImportMasterFile == null || widget.onApplyImport == null
            ? null
            : () => _import(context),
      );
    }

    final main = <Widget>[
      if (widget.canEdit) ...[
        _EditNote(language: language),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (_canEdit || _itemsBlocked) ...[
        _EditBar(
          language: language,
          canEdit: _canEdit,
          itemsBlocked: _itemsBlocked,
          onEdit: () => setState(() => _editing = true),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (widget.canEdit &&
          widget.onImportMasterFile != null &&
          widget.onApplyImport != null) ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _import(context),
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: Text(accountsV2Text(language, 'v2_import_master')),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      _ContractHeaderCard(
        setup: setup,
        language: language,
        format: format,
        canEdit: widget.canEdit,
        onSaveReferences: widget.onSaveReferences,
      ),
      const SizedBox(height: AppSpacing.lg),
      _BuildingsCard(setup: setup, language: language, format: format),
      const SizedBox(height: AppSpacing.lg),
      _StagesCard(setup: setup, language: language, format: format),
    ];
    for (final stage in setup.stages.where((s) => s.isItemsMode)) {
      final items = setup.itemsForStage(stage.stageKey);
      if (items.isEmpty) continue;
      main
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(
          _ItemsCard(
            stage: stage,
            items: items,
            language: language,
            format: format,
          ),
        );
    }
    final canEditNumbering =
        widget.canManageInvoices && widget.onSaveInvoiceSettings != null;
    if (setup.invoiceSettings != null || canEditNumbering) {
      main
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(
          _InvoiceNumberingCard(
            settings: setup.invoiceSettings,
            language: language,
            onEdit: canEditNumbering
                ? () => _editInvoiceSettings(context)
                : null,
          ),
        );
    }
    if (widget.variations.isNotEmpty ||
        (widget.canEdit && widget.onSaveVariation != null)) {
      main
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(
          AccountsV2VariationsCard(
            variations: widget.variations,
            canConfigure: widget.canEdit,
            language: language,
            format: format,
            onSave: widget.onSaveVariation,
          ),
        );
    }

    final aside = <Widget>[
      _SetupCheckCard(setup: setup, language: language, format: format),
      const SizedBox(height: AppSpacing.lg),
      _HowAmountsCard(language: language),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSpacing.stackedBreakpoint;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ...main,
              const SizedBox(height: AppSpacing.lg),
              ...aside,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: main,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: AppSpacing.inspectorWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: aside,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Contract header ─────────────────────────────────────────────────────────

class _ContractHeaderCard extends StatelessWidget {
  const _ContractHeaderCard({
    required this.setup,
    required this.language,
    required this.format,
    this.canEdit = false,
    this.onSaveReferences,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;
  final bool canEdit;
  final YorksSaveReferencesAction? onSaveReferences;

  String _t(String key) => accountsV2Text(language, key);

  bool get _hasReferences => [
    setup.clientTrn,
    setup.workOrderNumber,
    setup.workOrderDate,
    setup.contractNumber,
    setup.retentionPercent,
  ].any((v) => v != null && v.isNotEmpty);

  Future<void> _editReferences(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReferencesDialog(
        setup: setup,
        language: language,
        onSave: onSaveReferences!,
      ),
    );
    if (saved == true) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = setup.paymentTermsDays == null
        ? '—'
        : '${setup.paymentTermsDays} ${_t('v2_days_suffix')}';
    final nextInvoice = setup.invoiceSettings?.nextInvoiceNumber ?? '—';
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_contract_summary_title'),
            number: 1,
            subtitle: _t('v2_contract_subtitle'),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Field(
                label: _t('v2_contract_value'),
                value: format.money(setup.contractValue),
                emphasize: true,
              ),
              _Field(
                label: '${_t('v2_contract_value')} · ${_t('v2_incl_vat')}',
                value: format.money(setup.contractInclVat),
              ),
              _Field(
                label: _t('v2_vat_label'),
                value: format.percent(setup.vatRatePercent),
              ),
              if (setup.retentionPercent?.isNotEmpty ?? false)
                _Field(
                  label: _t('v2_retention_label'),
                  value: format.percent(
                    YorksAccountsDecimal.tryParse(setup.retentionPercent!),
                  ),
                ),
              _Field(label: _t('v2_payment_terms_label'), value: terms),
              _Field(label: _t('v2_next_invoice_label'), value: nextInvoice),
            ],
          ),
          if (setup.clientParty?.name != null ||
              setup.mainContractorParty?.name != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                if (setup.clientParty?.name != null)
                  _PartyField(
                    label: _t('v2_party_client'),
                    party: setup.clientParty!,
                  ),
                if (setup.mainContractorParty?.name != null)
                  _PartyField(
                    label: _t('v2_party_main_contractor'),
                    party: setup.mainContractorParty!,
                  ),
              ],
            ),
          ],
          if (_hasReferences || (canEdit && onSaveReferences != null)) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('v2_references_title'),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
                if (canEdit && onSaveReferences != null)
                  TextButton.icon(
                    onPressed: () => _editReferences(context),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text(_t('v2_edit')),
                  ),
              ],
            ),
            if (_hasReferences) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  if (setup.workOrderNumber?.isNotEmpty ?? false)
                    _Field(
                      label: _t('v2_work_order_no'),
                      value: setup.workOrderNumber!,
                    ),
                  if (setup.workOrderDate?.isNotEmpty ?? false)
                    _Field(
                      label: _t('v2_work_order_date'),
                      value: setup.workOrderDate!,
                    ),
                  if (setup.contractNumber?.isNotEmpty ?? false)
                    _Field(
                      label: _t('v2_contract_no'),
                      value: setup.contractNumber!,
                    ),
                  if (setup.clientTrn?.isNotEmpty ?? false)
                    _Field(label: _t('v2_client_trn'), value: setup.clientTrn!),
                ],
              ),
            ] else
              Text(
                _t('v2_references_empty'),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
          ],
        ],
      ),
    );
  }
}

/// Edits the four contract references (TRN, work order no/date, contract no).
class _ReferencesDialog extends StatefulWidget {
  const _ReferencesDialog({
    required this.setup,
    required this.language,
    required this.onSave,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final YorksSaveReferencesAction onSave;

  @override
  State<_ReferencesDialog> createState() => _ReferencesDialogState();
}

class _ReferencesDialogState extends State<_ReferencesDialog> {
  late final TextEditingController _trn;
  late final TextEditingController _woNo;
  late final TextEditingController _woDate;
  late final TextEditingController _contractNo;
  late final TextEditingController _retention;
  bool _saving = false;

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void initState() {
    super.initState();
    final s = widget.setup;
    _trn = TextEditingController(text: s.clientTrn ?? '');
    _woNo = TextEditingController(text: s.workOrderNumber ?? '');
    _woDate = TextEditingController(text: s.workOrderDate ?? '');
    _contractNo = TextEditingController(text: s.contractNumber ?? '');
    _retention = TextEditingController(text: s.retentionPercent ?? '');
  }

  @override
  void dispose() {
    for (final c in [_trn, _woNo, _woDate, _contractNo, _retention]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await widget.onSave(
      clientTrn: _trim(_trn),
      workOrderNumber: _trim(_woNo),
      workOrderDate: _trim(_woDate),
      contractNumber: _trim(_contractNo),
      retentionPercent: _trim(_retention),
      expectedProfileVersion: widget.setup.profileVersion,
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
      title: Text(_t('v2_references_title')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _EditField(label: _t('v2_work_order_no'), controller: _woNo),
            _EditField(label: _t('v2_work_order_date'), controller: _woDate),
            _EditField(label: _t('v2_contract_no'), controller: _contractNo),
            _EditField(label: _t('v2_client_trn'), controller: _trn),
            _EditField(
              label: _t('v2_retention_label'),
              controller: _retention,
              numeric: true,
              suffix: '%',
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style:
              (emphasize ? AppTypography.titleMedium : AppTypography.titleSmall)
                  .copyWith(
                    color: AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
        ),
      ],
    );
  }
}

/// A contract party column: label, name, then muted address and contact lines.
class _PartyField extends StatelessWidget {
  const _PartyField({required this.label, required this.party});

  final String label;
  final YorksAccountsSetupReadParty party;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.bodySmall.copyWith(color: AppColors.muted);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            party.name ?? '—',
            style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
          ),
          if (party.address != null && party.address!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(party.address!, style: muted),
          ],
          if (party.contactLine != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(party.contactLine!, style: muted),
          ],
        ],
      ),
    );
  }
}

// ─── Buildings ───────────────────────────────────────────────────────────────

class _BuildingsCard extends StatelessWidget {
  const _BuildingsCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_buildings_title'),
            number: 2,
            trailing: _PercentBadge(
              percent: setup.buildingTotalPercent,
              ok: setup.buildingsHundred,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SplitHeader(
            left: _t('v2_buildings_title'),
            middle: _t('v2_share_label'),
            right: _t('v2_value_label'),
          ),
          for (final b in setup.buildings)
            _SplitRow(
              left: b.name,
              middle: format.percent(b.allocationPercent),
              right: format.money(b.value),
            ),
        ],
      ),
    );
  }
}

// ─── Stages ────────────────────────────────────────────────────────────────

class _StagesCard extends StatelessWidget {
  const _StagesCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_stages_title'),
            number: 3,
            trailing: _PercentBadge(
              percent: setup.stageTotalPercent,
              ok: setup.stagesHundred,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final s in setup.stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.stageName,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _ModeChip(
                              isItems: s.isItemsMode,
                              language: language,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      format.percent(s.allocationPercent),
                      textAlign: TextAlign.end,
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      format.money(s.value),
                      textAlign: TextAlign.end,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.isItems, required this.language});

  final bool isItems;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final label = accountsV2Text(
      language,
      isItems ? 'v2_mode_items' : 'v2_mode_percent',
    );
    return isItems
        ? StatusChip.info(label)
        : StatusChip(label: label, tone: NexusStatusTone.neutral);
  }
}

// ─── Items ─────────────────────────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.stage,
    required this.items,
    required this.language,
    required this.format,
  });

  final YorksAccountsSetupReadStage stage;
  final List<YorksAccountsSetupReadItem> items;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    // Group by building name in the server-provided order.
    final byBuilding = <String, List<YorksAccountsSetupReadItem>>{};
    for (final it in items) {
      byBuilding.putIfAbsent(it.buildingName, () => []).add(it);
    }
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            '${_t('v2_items_title')} · ${stage.stageName}',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in byBuilding.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xxs,
              ),
              child: Text(
                entry.key,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: AppSpacing.xl,
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 44,
                columns: [
                  DataColumn(label: Text(_t('v2_item_label'))),
                  DataColumn(label: Text(_t('v2_qty_label')), numeric: true),
                  DataColumn(label: Text(_t('v2_unit_label'))),
                  DataColumn(label: Text(_t('v2_weight_label')), numeric: true),
                  DataColumn(label: Text(_t('v2_value_label')), numeric: true),
                ],
                rows: [
                  for (final it in entry.value)
                    DataRow(
                      cells: [
                        DataCell(Text(it.itemLabel)),
                        DataCell(
                          Text(
                            it.quantity.displayText(maximumFractionDigits: 2),
                          ),
                        ),
                        DataCell(Text(it.unitCode)),
                        DataCell(
                          Text(
                            format.percent(
                              it.weightPercentOfContract,
                              maximumFractionDigits: 4,
                            ),
                          ),
                        ),
                        DataCell(Text(format.money(it.value))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Invoice numbering ───────────────────────────────────────────────────────

class _InvoiceNumberingCard extends StatelessWidget {
  const _InvoiceNumberingCard({
    required this.settings,
    required this.language,
    this.onEdit,
  });

  final YorksAccountsSetupReadInvoiceSettings? settings;
  final AppLanguage language;
  final VoidCallback? onEdit;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final current = settings;
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_invoice_numbering_title'),
            number: 4,
            trailing: onEdit == null
                ? null
                : TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text(_t('v2_edit')),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (current == null)
            Text(
              _t('v2_invoice_numbering_empty'),
              style: AppTypography.bodyMedium,
            )
          else
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _Field(
                  label: _t('v2_next_invoice_label'),
                  value: current.nextInvoiceNumber,
                ),
                if (current.scopeLine?.isNotEmpty ?? false)
                  _Field(
                    label: _t('v2_scope_line_label'),
                    value: current.scopeLine!,
                  ),
                if (current.attentionName?.isNotEmpty ?? false)
                  _Field(
                    label: _t('v2_attention_name_label'),
                    value: current.attentionName!,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Setup check ─────────────────────────────────────────────────────────────

class _SetupCheckCard extends StatelessWidget {
  const _SetupCheckCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final contractOk = (setup.contractValue?.isPositive) ?? false;
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_setup_check_title')),
          const SizedBox(height: AppSpacing.sm),
          _CheckRow(
            label: _t('v2_check_contract'),
            ok: contractOk,
            detail: format.money(setup.contractValue),
          ),
          _CheckRow(
            label: _t('v2_check_buildings'),
            ok: setup.buildingsHundred,
            detail: format.percent(setup.buildingTotalPercent),
          ),
          _CheckRow(
            label: _t('v2_check_stages'),
            ok: setup.stagesHundred,
            detail: format.percent(setup.stageTotalPercent),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.ok,
    required this.detail,
  });

  final String label;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel_outlined,
            size: 18,
            color: ok ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.bodyMedium)),
          Text(
            detail,
            style: AppTypography.labelLarge.copyWith(
              color: ok ? AppColors.success : AppColors.error,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── How amounts are worked out ──────────────────────────────────────────────

class _HowAmountsCard extends StatelessWidget {
  const _HowAmountsCard({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            accountsV2Text(language, 'v2_how_amounts_title'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            accountsV2Text(language, 'v2_how_amounts_body'),
            style: AppTypography.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ─── Shared bits ─────────────────────────────────────────────────────────────

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent, required this.ok});

  final YorksAccountsDecimal percent;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final text = '${percent.displayText(maximumFractionDigits: 2)}%';
    return ok ? StatusChip.success(text) : StatusChip.warning(text);
  }
}

class _SplitHeader extends StatelessWidget {
  const _SplitHeader({
    required this.left,
    required this.middle,
    required this.right,
  });

  final String left;
  final String middle;
  final String right;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelMedium.copyWith(color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          SizedBox(
            width: 72,
            child: Text(middle, style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 140,
            child: Text(right, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.left,
    required this.middle,
    required this.right,
  });

  final String left;
  final String middle;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              middle,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              right,
              textAlign: TextAlign.end,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommercialHidden extends StatelessWidget {
  const _CommercialHidden({required this.language, required this.hasBaseline});

  final AppLanguage language;
  final bool hasBaseline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 32, color: AppColors.muted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              accountsV2Text(language, 'v2_commercial_hidden'),
              style: AppTypography.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit note ───────────────────────────────────────────────────────────────

/// The prototype's blue note strip above the form: edits apply from the next
/// claim and issued invoices keep their amounts.
class _EditNote extends StatelessWidget {
  const _EditNote({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.blueContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              accountsV2Text(language, 'v2_contract_edit_note'),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit bar ────────────────────────────────────────────────────────────────

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.language,
    required this.canEdit,
    required this.itemsBlocked,
    required this.onEdit,
  });

  final AppLanguage language;
  final bool canEdit;
  final bool itemsBlocked;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (itemsBlocked) {
      return AccountsV2Card(
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                accountsV2Text(language, 'v2_edit_items_blocked'),
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: Text(accountsV2Text(language, 'v2_edit')),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final bool numeric;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodyMedium)),
          SizedBox(
            width: 160,
            child: TextField(
              controller: controller,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                isDense: true,
                suffixText: suffix,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

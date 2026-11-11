/// R39 Accounts Workspace V2 — Contract tab, laid out as the approved prototype.
///
/// The commercial setup (`v1_get_project_commercial_setup`) edited in place:
/// contract details, buildings, billing stages, item breakdowns and variations
/// beside a live setup check. A change is held on screen until Save, which runs
/// the server commands that re-validate it; nothing shows as saved until the
/// server confirms. The Project Master File import starts from the tab bar.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../application/v2/accounts_unsaved_drafts.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/accounts_master_file_parser.dart';
import '../../domain/v2/commercial_setup_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/material_sources_models.dart';
import '../../domain/v2/variations_models.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_safety.dart';
import 'accounts_v2_summary_tab.dart'
    show accountsV2SetupCheckDetail, accountsV2SetupCheckTitle;
import 'accounts_v2_variations_card.dart';
import 'kit/accounts_v2_kit.dart';
import 'kit/accounts_v2_setup_checks.dart';

part 'accounts_v2_contract_editor.dart';
part 'accounts_v2_contract_import.dart';
part 'accounts_v2_contract_material_links.dart';

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

/// Replaces every item-to-BOQ-folder link; null on success or a failure code.
typedef YorksSaveMaterialLinksAction =
    Future<String?> Function(
      List<YorksAccountsMaterialLink> links,
      String reason,
    );

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
    this.materialSources,
    this.onSaveMaterialLinks,
    this.drafts,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;

  /// Whether the actor may configure commercials (configure_project_commercials).
  final bool canEdit;

  /// Saves the edited setup against the profile version the edits started
  /// from; returns null on success or an error message.
  final Future<String?> Function(
    YorksAccountsCommercialSetup setup,
    int? expectedProfileVersion,
  )?
  onSave;

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

  /// BOQ folders, their links to items and deliveries; null while loading or
  /// when the read failed, which hides the BOQ link cards.
  final YorksAccountsMaterialSources? materialSources;

  /// Saves the links; null when the actor may not change them.
  final YorksSaveMaterialLinksAction? onSaveMaterialLinks;

  /// Keeps unsaved edits while the person is on another tab; null keeps none.
  final YorksAccountsUnsavedDrafts? drafts;

  @override
  State<AccountsV2ContractTab> createState() => AccountsV2ContractTabState();
}

/// Public so the tab bar's Import Master File button can start the import.
class AccountsV2ContractTabState extends State<AccountsV2ContractTab> {
  /// Opens the master-file import, as the tab's own button does.
  void startImport() {
    if (widget.onImportMasterFile == null || widget.onApplyImport == null) {
      return;
    }
    _import(context);
  }

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

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup;
    // A contract is all commercial values: without them there is nothing to
    // show or set up here.
    if (!setup.capabilities.viewProjectCommercialValues) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'shield',
          title: accountsV2Text(widget.language, 'v2_commercial_hidden'),
        ),
      );
    }
    if (!setup.hasBaseline && !widget.canEdit) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'doc',
          title: accountsV2Text(widget.language, 'v2_no_baseline_title'),
          body: accountsV2Text(widget.language, 'v2_first_no_access'),
        ),
      );
    }
    return _ContractWorkspace(
      tab: widget,
      buildingChoices: _buildingChoices,
      canEditSetup: _canEdit,
      itemsBlocked: _itemsBlocked,
    );
  }
}

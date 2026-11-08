/// R39 Accounts Workspace V2 — Progress & Claims tab, laid out as the approved
/// prototype: a Claim picker with the claim's actions, five KPIs, filters, the
/// building and stage workbench, and the Claim details panel.
///
/// The server keeps progress as a running total per building and stage (and per
/// item). The tab shows it as the prototype does, split into what was done
/// before the claim and what is in it, from the split the workbench read
/// returns. Typing "this claim" progress is a local edit; Save progress sends
/// the new running totals (`v1_save_claim_workbench`), which rebuilds the one
/// open draft claim on the server. Nothing is shown as saved before the server
/// confirms it. Money appears only with view_project_commercial_values.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/claim_workbench_models.dart';
import '../../domain/v2/claims_list_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/material_sources_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

/// Reopens a checked claim to draft; returns null on success or an error.
typedef YorksReopenClaimAction =
    Future<String?> Function({
      required String claimId,
      required int expectedVersion,
      required String reason,
    });

/// Issues the invoice for a checked claim; returns null on success or an error.
typedef YorksIssueInvoiceAction =
    Future<String?> Function({
      required String claimId,
      required int expectedClaimVersion,
      required String invoiceDate,
      required String submissionDate,
      String? invoiceReference,
    });

/// A selectable evidence document (id + display name) for the progress editor.
typedef YorksAccountsEvidenceDoc = ({String id, String name});

/// Confirms edited progress and rebuilds the draft claim; returns null on
/// success or an error message.
typedef YorksSaveWorkbenchAction =
    Future<String?> Function({
      String? claimReference,
      required String periodStart,
      required String periodEnd,
      required List<Map<String, Object?>> entries,
      required List<String> evidenceDocumentIds,
      String? reason,
    });

/// Opens an issued invoice on the Invoices & Payments tab.
typedef YorksOpenInvoiceAction = void Function(String invoiceId, {bool revise});

const double _eps = 0.005;

class AccountsV2ClaimsTab extends StatefulWidget {
  const AccountsV2ClaimsTab({
    super.key,
    required this.workbench,
    required this.language,
    this.onReopen,
    this.onIssue,
    this.onMarkChecked,
    this.onCancelClaim,
    this.onPreviewInvoice,
    this.onUpdateCell,
    this.onUploadEvidence,
    this.onSaveWorkbench,
    this.canRecordProgress = false,
    this.evidenceDocuments = const [],
    this.claims = const [],
    this.claimsLoaded = true,
    this.onSelectClaim,
    this.setup,
    this.materialSources,
    this.onOpenContract,
    this.onOpenInvoice,
    this.focusBuildingId,
    this.focusStageKey,
  });

  final YorksAccountsWorkbench workbench;
  final AppLanguage language;
  final YorksReopenClaimAction? onReopen;
  final YorksIssueInvoiceAction? onIssue;
  final YorksReopenClaimAction? onMarkChecked;

  /// Deletes (cancels) a draft claim; it stays in History.
  final YorksReopenClaimAction? onCancelClaim;

  /// Renders the invoice this claim would produce; null on success or an error.
  final Future<String?> Function(String claimId)? onPreviewInvoice;
  final YorksSaveWorkbenchAction? onSaveWorkbench;

  /// Suggests or confirms one cell, for people who can't prepare a claim.
  final ValueChanged<YorksAccountsWorkbenchCell>? onUpdateCell;

  /// Picks and uploads a project document; returns its id, or null if cancelled.
  /// Throws when the upload fails.
  final Future<String?> Function()? onUploadEvidence;
  final bool canRecordProgress;
  final List<YorksAccountsEvidenceDoc> evidenceDocuments;

  /// All claims for the project (newest first), for the Claim picker.
  final List<YorksAccountsClaimSummary> claims;

  /// False while the claims list is still loading.
  final bool claimsLoaded;

  /// Switches the workbench to a claim; null returns to the open claim.
  final ValueChanged<String?>? onSelectClaim;

  /// The contract, for building shares, stage percents, VAT and the next
  /// invoice number. Optional: the tab works from the workbench alone.
  final YorksAccountsCommercialSetupRead? setup;

  /// What has reached site for items linked to the BOQ; null hides it.
  final YorksAccountsMaterialSources? materialSources;
  final VoidCallback? onOpenContract;
  final YorksOpenInvoiceAction? onOpenInvoice;

  /// A building and stage to open first (from the Overview).
  final String? focusBuildingId;
  final String? focusStageKey;

  @override
  State<AccountsV2ClaimsTab> createState() => _AccountsV2ClaimsTabState();
}

// ─── View model ──────────────────────────────────────────────────────────────

/// What one building × stage shows: progress before the claim and in it.
final class _CellView {
  _CellView({
    required this.cell,
    required this.stageValue,
    required this.beforePct,
    required this.thisPct,
    required this.beforeAmount,
    required this.thisAmount,
    required this.thisExact,
    required this.items,
  });

  final YorksAccountsWorkbenchCell cell;
  final double stageValue;

  /// Exact percent done before the claim (sent back as the base of a running
  /// total) and the percent in it, as first shown.
  final YorksAccountsDecimal beforePct;
  final YorksAccountsDecimal thisPct;
  final double beforeAmount;
  final double thisAmount;

  /// [thisAmount] unrounded, for the claim's Excel-rule gross.
  final double thisExact;
  final List<_ItemView> items;

  String get key => '${cell.buildingScopeId}|${cell.stageKey}';
}

final class _ItemView {
  _ItemView({required this.item, required this.before, required this.initial});

  final YorksAccountsWorkbenchItem item;
  final YorksAccountsDecimal before;
  final YorksAccountsDecimal initial;
}

final class _Building {
  _Building(this.id, this.name);

  final String id;
  final String name;
  final List<_CellView> cells = [];
}

final class _Stage {
  _Stage(this.key, this.name, this.position, this.byItems);

  final String key;
  final String name;
  final int position;
  final bool byItems;
}

YorksAccountsDecimal _dec(double value, [int digits = 4]) {
  final fixed = (value < 0 ? 0.0 : value).toStringAsFixed(digits);
  return YorksAccountsDecimal.tryParse(fixed) ?? YorksAccountsDecimal.zero;
}

double _d(YorksAccountsDecimal? value) =>
    value == null ? 0 : v2Number(value.canonicalText);

/// A number as typed into an input: no grouping, trailing zeros dropped.
String _plain(YorksAccountsDecimal value) {
  if (value.isZero) return '';
  return value.displayText(maximumFractionDigits: 4).replaceAll(',', '');
}

YorksAccountsDecimal? _parseInput(String text) {
  final t = text.trim().replaceAll(',', '');
  if (t.isEmpty) return YorksAccountsDecimal.zero;
  return YorksAccountsDecimal.tryParse(t);
}

class _AccountsV2ClaimsTabState extends State<AccountsV2ClaimsTab> {
  final Set<String> _openBuildings = {};
  final Set<String> _openStages = {};
  String _fBuilding = 'all';
  String _fStage = 'all';
  String _fShow = 'all';

  /// Starting a new claim when none is open (nothing on the server yet).
  bool _newClaim = false;
  bool _autoSelected = false;

  final Map<String, TextEditingController> _pct = {};
  final Map<String, TextEditingController> _qty = {};
  final Map<String, String> _initial = {};

  late String _periodStart;
  late String _periodEnd;
  final _note = TextEditingController();
  final Set<String> _evidence = {};
  bool _saving = false;
  bool _uploading = false;
  bool _busy = false;
  String? _error;

  late List<_Stage> _stages;
  late List<_Building> _buildings;
  late Map<String, _CellView> _views;

  bool get _values => widget.workbench.canViewValues;
  String _t(String key) => accountsV2Text(widget.language, key);

  Map<String, dynamic>? get _claim => widget.workbench.claim;
  String get _status =>
      _newClaim ? 'new' : (_claim?['status'] as String? ?? 'none');

  /// Whether this claim's progress may be typed here.
  bool get _canEdit =>
      widget.canRecordProgress &&
      widget.onSaveWorkbench != null &&
      (_status == 'draft' || _status == 'new');

  @override
  void initState() {
    super.initState();
    _rebuild(resetEdits: true);
    final b = widget.focusBuildingId;
    final s = widget.focusStageKey;
    if (b != null) {
      _openBuildings.add(b);
      if (s != null) _openStages.add('$b|$s');
    } else if (_buildings.isNotEmpty) {
      // As the prototype: the first building open, and in it the stages this
      // claim has progress in,
      final first = _buildings.first;
      _openBuildings.add(first.id);
      // and those with more delivered to site than claimed.
      for (final v in first.cells) {
        if (_fractions(v).$2 > 0.00001 ||
            v.items.any((i) => _deliveryWaiting(v, i))) {
          _openStages.add(v.key);
        }
      }
    }
  }

  @override
  void didUpdateWidget(AccountsV2ClaimsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workbench, widget.workbench) ||
        !identical(oldWidget.setup, widget.setup)) {
      final sameClaim =
          oldWidget.workbench.openClaimId == widget.workbench.openClaimId;
      // Unsaved typing survives a background refresh of the same claim.
      _rebuild(resetEdits: !(_dirty && sameClaim));
    }
  }

  @override
  void dispose() {
    for (final c in [..._pct.values, ..._qty.values, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Building the view ────────────────────────────────────────────────────

  void _rebuild({required bool resetEdits}) {
    final wb = widget.workbench;
    final setup = widget.setup;
    final status = _status;
    final stages = <String, _Stage>{};
    for (final c in wb.cells) {
      stages.putIfAbsent(
        c.stageKey,
        () => _Stage(
          c.stageKey,
          c.stageLabel ?? c.stageKey,
          c.stagePosition,
          c.isItemsMode,
        ),
      );
    }
    _stages = stages.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final buildings = <String, _Building>{};
    final order = <String>[
      for (final b
          in setup?.buildings ?? const <YorksAccountsSetupReadBuilding>[])
        b.projectScopeId,
    ];
    final sorted = [...wb.cells]
      ..sort((a, b) {
        final ia = order.indexOf(a.buildingScopeId);
        final ib = order.indexOf(b.buildingScopeId);
        if (ia != ib) {
          return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
        }
        final byName = a.buildingName.compareTo(b.buildingName);
        return byName != 0
            ? byName
            : a.stagePosition.compareTo(b.stagePosition);
      });
    _views = {};
    for (final c in sorted) {
      final view = _viewFor(c, status);
      _views[view.key] = view;
      buildings
          .putIfAbsent(
            c.buildingScopeId,
            () => _Building(c.buildingScopeId, c.buildingName),
          )
          .cells
          .add(view);
    }
    for (final b in buildings.values) {
      b.cells.sort(
        (x, y) => x.cell.stagePosition.compareTo(y.cell.stagePosition),
      );
    }
    _buildings = buildings.values.toList();

    if (resetEdits) _resetEdits();
  }

  _CellView _viewFor(YorksAccountsWorkbenchCell c, String status) {
    final stageValue = _d(c.stageValue);
    final newMode = status == 'new';
    final hasContextClaim = _claim != null;
    // Before and in the claim, as the server split them for the claim in view.
    // A new claim follows everything claimed so far.
    var beforePct = c.percentBeforeClaim ?? c.confirmedPercent;
    var thisPct = c.percentThisClaim ?? YorksAccountsDecimal.zero;
    if (newMode && hasContextClaim) {
      beforePct = beforePct + thisPct;
      final rest = c.confirmedPercent - beforePct;
      thisPct = rest.isNegative ? YorksAccountsDecimal.zero : rest;
    }
    var beforeAmount = _d(c.claimedBeforeClaim);
    var thisAmount = _d(c.thisClaimAmount);
    var thisExact = _d(c.thisClaimAmountExact ?? c.thisClaimAmount);
    if (newMode && _values) {
      beforeAmount = _d(c.claimed);
      thisAmount = _d(c.available);
      thisExact = _d(c.availableExact ?? c.available);
    }
    // With money, a lump-sum split follows the claimed amounts exactly, so the
    // percent and the amount always agree.
    if (_values && stageValue > 0 && !c.isItemsMode) {
      beforePct = _dec(beforeAmount / stageValue * 100);
      final rest = newMode
          ? _d(c.confirmedPercent) - beforeAmount / stageValue * 100
          : thisAmount / stageValue * 100;
      thisPct = _dec(rest < 0 ? 0 : rest);
    }
    final items = <_ItemView>[
      for (final item in [
        ...c.items,
      ]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)))
        () {
          var before = item.qtyBeforeClaim ?? item.confirmedQty;
          var initial = item.qtyThisClaim ?? YorksAccountsDecimal.zero;
          if (newMode && hasContextClaim) {
            before = before + initial;
            final rest = item.confirmedQty - before;
            initial = rest.isNegative ? YorksAccountsDecimal.zero : rest;
          }
          return _ItemView(item: item, before: before, initial: initial);
        }(),
    ];
    return _CellView(
      cell: c,
      stageValue: stageValue,
      beforePct: beforePct,
      thisPct: thisPct,
      beforeAmount: beforeAmount,
      thisAmount: thisAmount,
      thisExact: thisExact,
      items: items,
    );
  }

  void _resetEdits() {
    for (final c in [..._pct.values, ..._qty.values]) {
      c.dispose();
    }
    _pct.clear();
    _qty.clear();
    _initial.clear();
    for (final v in _views.values) {
      if (v.cell.isItemsMode) {
        for (final i in v.items) {
          final text = _plain(i.initial);
          _initial['q:${i.item.stageItemId}'] = text;
          _qty[i.item.stageItemId] = TextEditingController(text: text)
            ..addListener(_changed);
        }
      } else {
        final text = _plain(v.thisPct);
        _initial['p:${v.cell.progressEntryId}'] = text;
        _pct[v.cell.progressEntryId] = TextEditingController(text: text)
          ..addListener(_changed);
      }
    }
    final claim = _claim;
    final today = accountsV2TodayIso();
    if (_status == 'draft' && claim != null) {
      _periodStart = claim['claim_period_start'] as String? ?? today;
      _periodEnd = claim['claim_period_end'] as String? ?? today;
    } else {
      _periodStart = '${today.substring(0, 8)}01';
      _periodEnd = today;
    }
    _note.clear();
    _evidence.clear();
    _error = null;
  }

  void _changed() {
    if (mounted) setState(() => _error = null);
  }

  // ─── Edits ────────────────────────────────────────────────────────────────

  bool _isEdited(String key, TextEditingController controller) {
    final now = _parseInput(controller.text);
    final was = _parseInput(_initial[key] ?? '');
    if (now == null) return true;
    return was == null || now.compareTo(was) != 0;
  }

  bool get _dirty {
    for (final e in _pct.entries) {
      if (_isEdited('p:${e.key}', e.value)) return true;
    }
    for (final e in _qty.entries) {
      if (_isEdited('q:${e.key}', e.value)) return true;
    }
    return false;
  }

  /// The typed percent in a lump-sum cell (the shown value when untouched).
  YorksAccountsDecimal _typedPct(_CellView v) =>
      _parseInput(_pct[v.cell.progressEntryId]?.text ?? '') ??
      YorksAccountsDecimal.zero;

  YorksAccountsDecimal _typedQty(_ItemView i) =>
      _parseInput(_qty[i.item.stageItemId]?.text ?? '') ??
      YorksAccountsDecimal.zero;

  bool _cellEdited(_CellView v) {
    if (v.cell.isItemsMode) {
      return v.items.any(
        (i) => _isEdited('q:${i.item.stageItemId}', _qty[i.item.stageItemId]!),
      );
    }
    final c = _pct[v.cell.progressEntryId];
    return c != null && _isEdited('p:${v.cell.progressEntryId}', c);
  }

  double _itemValue(_ItemView i) => _d(i.item.itemValue);

  double _itemAmount(_ItemView i, double qty) {
    final total = _d(i.item.quantity);
    return total <= 0 ? 0 : _itemValue(i) * qty / total;
  }

  /// This claim's money for a cell: the server's figure until it is edited.
  double _liveAmount(_CellView v) {
    if (!_cellEdited(v)) return v.thisAmount;
    if (v.cell.isItemsMode) {
      return v.items.fold<double>(
        0,
        (a, i) => a + _itemAmount(i, _d(_typedQty(i))),
      );
    }
    return v.stageValue * _d(_typedPct(v)) / 100;
  }

  /// Fraction of the stage done before the claim and in it, for the bars.
  (double, double) _fractions(_CellView v) {
    if (_values && v.stageValue > 0) {
      return (v.beforeAmount / v.stageValue, _liveAmount(v) / v.stageValue);
    }
    if (v.cell.isItemsMode) {
      if (v.items.isEmpty) return (0, 0);
      var before = 0.0;
      var now = 0.0;
      for (final i in v.items) {
        final q = _d(i.item.quantity);
        if (q <= 0) continue;
        before += _d(i.before) / q;
        now += _d(_typedQty(i)) / q;
      }
      return (before / v.items.length, now / v.items.length);
    }
    return (_d(v.beforePct) / 100, _d(_typedPct(v)) / 100);
  }

  bool _cellOver(_CellView v) {
    if (v.cell.isItemsMode) {
      return v.items.any(
        (i) => (i.before + _typedQty(i)).compareTo(i.item.quantity) > 0,
      );
    }
    return (v.beforePct + _typedPct(v)).compareTo(
          YorksAccountsDecimal.hundred,
        ) >
        0;
  }

  List<Map<String, Object?>> _entries() {
    final out = <Map<String, Object?>>[];
    for (final v in _views.values) {
      if (v.cell.isItemsMode) {
        for (final i in v.items) {
          final c = _qty[i.item.stageItemId]!;
          if (!_isEdited('q:${i.item.stageItemId}', c)) continue;
          out.add({
            'stage_item_id': i.item.stageItemId,
            'confirmed_qty_to_date': (i.before + _typedQty(i)).canonicalText,
          });
        }
      } else {
        final c = _pct[v.cell.progressEntryId]!;
        if (!_isEdited('p:${v.cell.progressEntryId}', c)) continue;
        out.add({
          'progress_entry_id': v.cell.progressEntryId,
          'confirmed_percent_to_date':
              (v.beforePct + _typedPct(v)).canonicalText,
        });
      }
    }
    return out;
  }

  bool get _invalidInput {
    for (final c in [..._pct.values, ..._qty.values]) {
      final v = _parseInput(c.text);
      if (v == null || v.isNegative) return true;
    }
    return _views.values.any((v) => _cellEdited(v) && _cellOver(v));
  }

  bool get _hasIncrease {
    for (final v in _views.values) {
      if (v.cell.isItemsMode) {
        for (final i in v.items) {
          if (!_isEdited(
            'q:${i.item.stageItemId}',
            _qty[i.item.stageItemId]!,
          )) {
            continue;
          }
          if ((i.before + _typedQty(i)).compareTo(i.item.confirmedQty) > 0) {
            return true;
          }
        }
      } else if (_cellEdited(v) &&
          (v.beforePct + _typedPct(v)).compareTo(v.cell.confirmedPercent) > 0) {
        return true;
      }
    }
    return false;
  }

  void _set(TextEditingController c, String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _maxLump(_CellView v) {
    final rest = YorksAccountsDecimal.hundred - v.beforePct;
    _set(
      _pct[v.cell.progressEntryId]!,
      _plain(rest.isNegative ? YorksAccountsDecimal.zero : rest),
    );
  }

  void _maxItem(_ItemView i) {
    final rest = i.item.quantity - i.before;
    _set(
      _qty[i.item.stageItemId]!,
      _plain(rest.isNegative ? YorksAccountsDecimal.zero : rest),
    );
  }

  void _copyLumpToAll(_CellView from) {
    final text = _pct[from.cell.progressEntryId]!.text;
    for (final v in _views.values) {
      if (v.cell.stageKey == from.cell.stageKey &&
          v != from &&
          !v.cell.isItemsMode) {
        _set(_pct[v.cell.progressEntryId]!, text);
      }
    }
  }

  void _copyItemsToAll(_CellView from) {
    final byKey = {
      for (final i in from.items)
        i.item.itemKey: _qty[i.item.stageItemId]!.text,
    };
    for (final v in _views.values) {
      if (v.cell.stageKey != from.cell.stageKey || v == from) continue;
      for (final i in v.items) {
        final text = byKey[i.item.itemKey];
        if (text != null) _set(_qty[i.item.stageItemId]!, text);
      }
    }
  }

  void _clearItems(_CellView v) {
    for (final i in v.items) {
      _set(_qty[i.item.stageItemId]!, '');
    }
  }

  void _useSuggestion(_CellView v) {
    final suggested = v.cell.suggestedPercent;
    if (suggested == null) return;
    final rest = suggested - v.beforePct;
    _set(
      _pct[v.cell.progressEntryId]!,
      _plain(rest.isNegative ? YorksAccountsDecimal.zero : rest),
    );
    setState(() => _evidence.addAll(v.cell.suggestedEvidenceDocumentIds));
  }

  void _discard() => setState(() {
    _resetEdits();
    if (_newClaim && !_dirty) _newClaim = false;
  });

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final claim = _claim;
    final reference = _status == 'draft'
        ? (claim?['claim_reference'] as String?)
        : null;
    final error = await widget.onSaveWorkbench!(
      claimReference: reference,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
      entries: _entries(),
      evidenceDocumentIds: _evidence.toList(growable: false),
      reason: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) {
        _newClaim = false;
        _rebuild(resetEdits: true);
      } else {
        _error = accountsV2ErrorText(widget.language, error);
      }
    });
    if (error == null) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_progress_saved'))));
    }
  }

  Future<void> _uploadEvidence() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _uploading = true);
    try {
      final id = await widget.onUploadEvidence!();
      if (mounted && id != null) setState(() => _evidence.add(id));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(_t('v2_evidence_upload_failed'))),
      );
    }
    if (mounted) setState(() => _uploading = false);
  }

  // ─── Claim commands ───────────────────────────────────────────────────────

  Future<void> _run(Future<String?> Function() command, String okKey) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    final error = await command();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? _t(okKey)
              : accountsV2ErrorText(widget.language, error),
        ),
      ),
    );
  }

  String? get _claimId => _claim?['claim_id'] as String?;
  int get _claimVersion => (_claim?['record_version'] as num?)?.toInt() ?? 1;

  Future<String?> _askReason(String title, String label) => showDialog<String>(
    context: context,
    builder: (_) =>
        _ReasonDialog(title: title, label: label, language: widget.language),
  );

  Future<void> _markChecked() async {
    final reason = await _askReason(
      _t('v2_claim_mark_checked'),
      _t('v2_claim_mark_reason'),
    );
    if (reason == null || _claimId == null) return;
    await _run(
      () => widget.onMarkChecked!(
        claimId: _claimId!,
        expectedVersion: _claimVersion,
        reason: reason,
      ),
      'v2_claim_checked_done',
    );
  }

  Future<void> _reopen() async {
    final reason = await _askReason(
      _t('v2_claim_back_to_draft'),
      _t('v2_claim_reopen_reason'),
    );
    if (reason == null || _claimId == null) return;
    await _run(
      () => widget.onReopen!(
        claimId: _claimId!,
        expectedVersion: _claimVersion,
        reason: reason,
      ),
      'v2_claim_reopened',
    );
  }

  Future<void> _deleteDraft() async {
    final reason = await _askReason(
      _t('v2p_delete_draft'),
      _t('v2p_delete_reason'),
    );
    if (reason == null || _claimId == null) return;
    await _run(
      () => widget.onCancelClaim!(
        claimId: _claimId!,
        expectedVersion: _claimVersion,
        reason: reason,
      ),
      'v2p_deleted',
    );
  }

  Future<void> _issue() async {
    final result = await showDialog<_IssueResult>(
      context: context,
      builder: (_) => _IssueDialog(language: widget.language),
    );
    if (result == null || _claimId == null) return;
    await _run(
      () => widget.onIssue!(
        claimId: _claimId!,
        expectedClaimVersion: _claimVersion,
        invoiceDate: result.invoiceDate,
        submissionDate: result.submissionDate,
        invoiceReference: result.reference,
      ),
      'v2_claim_issued',
    );
  }

  Future<void> _preview() async {
    final id = _claimId;
    if (id == null || widget.onPreviewInvoice == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final error = await widget.onPreviewInvoice!(id);
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_inv_pdf_failed'))));
    }
  }

  // ─── Claim numbers and labels ─────────────────────────────────────────────

  /// Live claims oldest first; their place is the claim number.
  List<YorksAccountsClaimSummary> get _liveClaims => [
    for (final c in widget.claims.reversed)
      if (c.status != 'cancelled') c,
  ];

  int _numberOf(String? claimId) {
    for (final c in widget.claims) {
      if (c.claimId == claimId && c.claimNumber != null) return c.claimNumber!;
    }
    final live = _liveClaims;
    final i = live.indexWhere((c) => c.claimId == claimId);
    return i < 0 ? live.length + 1 : i + 1;
  }

  String _no(int n) => '#${n.toString().padLeft(2, '0')}';

  String _statusLabel(String status) => switch (status) {
    'invoiced' => _t('v2p_status_invoiced'),
    'ready_for_accounts' => _t('v2p_status_checked'),
    'cancelled' => _t('v2p_status_cancelled'),
    'new' => _t('v2p_status_new'),
    _ => _t('v2p_status_draft'),
  };

  Map<String, dynamic>? get _invoice => _claim?['invoice'] is Map
      ? Map<String, dynamic>.from(_claim!['invoice'] as Map)
      : null;

  String? get _draftInvoiceNo {
    final s = widget.setup?.invoiceSettings;
    if (s == null || s.invoicePrefix.isEmpty) return null;
    return '${s.invoicePrefix}${s.nextSequence.toString().padLeft(2, '0')}';
  }

  String? get _invoiceNo => _status == 'invoiced'
      ? (_invoice?['invoice_reference'] as String?)
      : _draftInvoiceNo;

  double get _vatPercent {
    final rate = widget.setup?.vatRatePercent;
    if (rate != null) return _d(rate);
    final gross = v2Number(_claim?['claimed_ex_vat']);
    final vat = v2Number(_claim?['vat_amount']);
    return gross > 0 ? vat / gross * 100 : 0;
  }

  double get _contractValue {
    final value = widget.setup?.contractValue;
    if (value != null) return _d(value);
    return v2Number(_claim?['contract_value']);
  }

  /// This claim's exact (unrounded) gross: the server's exact figure plus
  /// anything typed since.
  double get _exactGross {
    var exact = _newClaim
        ? 0.0
        : v2Number(
            _claim?['claimed_ex_vat_exact'] ?? _claim?['claimed_ex_vat'],
          );
    for (final v in _views.values) {
      final live = _cellEdited(v) ? _liveAmount(v) : v.thisExact;
      if (_newClaim) {
        exact += live;
      } else if (_cellEdited(v)) {
        exact += live - v.thisExact;
      }
    }
    return exact;
  }

  /// Gross, VAT and net payable as the Yorks workbook works them out: each
  /// rounded once from the exact gross. The server's figures stand until
  /// something is typed (an invoiced claim shows its invoice).
  ({double gross, double vat, double net}) get _amounts {
    if (!_newClaim && !_dirty && _claim?['net_payable'] != null) {
      return (
        gross: v2Number(_claim?['claimed_ex_vat']),
        vat: v2Number(_claim?['vat_amount']),
        net: v2Number(_claim?['net_payable']),
      );
    }
    return accountsV2ExcelAmounts(_exactGross, _vatPercent);
  }

  double get _gross => _amounts.gross;

  double _stageAmount(String stageKey) => _views.values
      .where((v) => v.cell.stageKey == stageKey)
      .fold<double>(0, (a, v) => a + _liveAmount(v));

  int get _siteRecords =>
      _views.values.fold<int>(0, (a, v) => a + _siteCount(v));

  /// Site records waiting in a cell: a Site Engineer's suggestion, or items
  /// with more delivered to site than is claimed so far.
  int _siteCount(_CellView v) {
    final suggested = v.cell.suggestedPercent != null ? 1 : 0;
    if (!v.cell.isItemsMode) return suggested;
    return suggested + v.items.where((i) => _deliveryWaiting(v, i)).length;
  }

  // ─── Deliveries to site ───────────────────────────────────────────────────

  YorksAccountsItemDelivered? _delivered(_CellView v, _ItemView i) => widget
      .materialSources
      ?.deliveredFor(v.cell.buildingScopeId, v.cell.stageKey, i.item.itemKey);

  /// Delivered, never more than the item's quantity.
  YorksAccountsDecimal? _deliveredTarget(_CellView v, _ItemView i) {
    final d = _delivered(v, i);
    if (d == null) return null;
    return d.deliveredQty.compareTo(i.item.quantity) > 0
        ? i.item.quantity
        : d.deliveredQty;
  }

  /// More has reached site than the claim has to date.
  bool _deliveryWaiting(_CellView v, _ItemView i) {
    if (_status == 'invoiced') return false;
    final target = _deliveredTarget(v, i);
    return target != null && target.compareTo(i.before + _typedQty(i)) > 0;
  }

  /// Fills this claim so the item's total to date is what was delivered.
  void _useDelivered(_CellView v, _ItemView i) {
    final target = _deliveredTarget(v, i);
    if (target == null) return;
    final rest = target - i.before;
    if (rest.isNegative || rest.isZero) return;
    _set(_qty[i.item.stageItemId]!, _plain(rest));
  }

  void _useAllDelivered(_CellView v) {
    for (final i in v.items) {
      if (_deliveryWaiting(v, i)) _useDelivered(v, i);
    }
  }

  // ─── Filters ──────────────────────────────────────────────────────────────

  bool get _filtering =>
      _fBuilding != 'all' || _fStage != 'all' || _fShow != 'all';

  bool _matches(_CellView v) {
    if (_fStage != 'all' && v.cell.stageKey != _fStage) return false;
    switch (_fShow) {
      case 'claimed':
        final (_, now) = _fractions(v);
        return now > 0.00001;
      case 'sug':
        return _siteCount(v) > 0;
      case 'open':
        final (before, now) = _fractions(v);
        return before + now < 1 - 0.00001;
    }
    return true;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    if (wb.baselineRevisionId == null || wb.cells.isEmpty) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'hier',
          title: _t('v2p_nothing_title'),
          body: _t('v2p_nothing_body'),
          action: widget.onOpenContract == null
              ? null
              : AccountsV2Button(
                  label: _t('v2p_open_contract'),
                  onPressed: widget.onOpenContract,
                ),
        ),
      );
    }

    // Show the latest claim when none is open, as the prototype does.
    if (_claim == null &&
        !_newClaim &&
        !_autoSelected &&
        _liveClaims.isNotEmpty &&
        widget.onSelectClaim != null) {
      _autoSelected = true;
      final latest = _liveClaims.last.claimId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelectClaim!(latest);
      });
    }

    if (_claim == null && !_newClaim) {
      if (!widget.claimsLoaded || _liveClaims.isNotEmpty) {
        return const _Waiting();
      }
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'chart',
          title: _t('v2p_no_claims_title'),
          body: _t('v2p_no_claims_body'),
          action: _canStart
              ? AccountsV2Button(
                  label: '${_t('v2p_start_claim')} ${_no(1)}',
                  icon: 'plus',
                  onPressed: _startNewClaim,
                )
              : null,
        ),
      );
    }

    final dirty = _dirty;
    return AccountsV2Stack(
      children: [
        if (_status == 'invoiced') _invoicedNote(),
        _toolRow(context),
        _kpis(),
        _filters(context),
        if (dirty || _newClaim) _saveCard(context, dirty),
        AccountsV2Split(main: _workbenchCard(context), side: _sidePanel()),
      ],
    );
  }

  bool get _canStart =>
      widget.canRecordProgress && widget.onSaveWorkbench != null;

  bool get _hasDraft =>
      _liveClaims.any((c) => c.status == 'draft') ||
      widget.workbench.openClaimStatus == 'draft';

  void _startNewClaim() {
    setState(() {
      _newClaim = true;
      _rebuild(resetEdits: true);
    });
  }

  void _selectClaim(String value) {
    if (value == '__new') return;
    if (value == _claimId && !_newClaim) return;
    setState(() {
      _newClaim = false;
      _resetEdits();
    });
    widget.onSelectClaim?.call(value);
  }

  // ─── Top: note, tool row, KPIs, filters ───────────────────────────────────

  Widget _invoicedNote() {
    final inv = _invoice;
    final no = inv?['invoice_reference'] as String? ?? '';
    return AccountsV2Note(
      tone: AccountsV2NoteTone.ok,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  '${_t('v2p_claim')} ${_no(_numberOf(_claimId))} '
                  '${_t('v2p_invoiced_note_a')} ',
            ),
            TextSpan(
              text: no,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text:
                  ' ${_t('v2p_invoiced_note_on')} '
                  '${v2Date(inv?['submission_date'])}. '
                  '${_t('v2p_invoiced_note_b')}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolRow(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final options = <(String, String)>[
      if (_newClaim)
        (
          '__new',
          '${_t('v2p_claim')} ${_no(_liveClaims.length + 1)} · '
              '${v2Month(_periodEnd)} · ${_t('v2p_status_new')}',
        ),
      for (final c in _liveClaims.reversed)
        (
          c.claimId,
          '${_t('v2p_claim')} ${_no(_numberOf(c.claimId))} · '
              '${v2Month(c.periodEnd ?? c.periodStart)} · '
              '${c.claimId == _claimId && c.status == 'invoiced' && _invoice != null ? _invoice!['invoice_reference'] : _statusLabel(c.status)}',
        ),
    ];
    // The claim in view may not be in the list (it loads separately).
    final current = _newClaim ? '__new' : (_claimId ?? '');
    if (!options.any((o) => o.$1 == current) && _claim != null) {
      options.insert(0, (
        current,
        '${_t('v2p_claim')} ${_no(_numberOf(_claimId))} · '
            '${v2Month(_claim!['claim_period_end'] ?? _claim!['claim_period_start'])} · '
            '${_statusLabel(_status)}',
      ));
    }
    final picker = AccountsV2Select<String>(
      label: _t('v2p_claim'),
      value: current,
      options: options,
      width: narrow ? null : 340,
      onChanged: widget.onSelectClaim == null || _saving ? null : _selectClaim,
    );
    final actions = _claimActions();
    final newButton = !_hasDraft && !_newClaim && _canStart
        ? AccountsV2Button(
            label: _t('v2p_new_claim'),
            icon: 'plus',
            onPressed: _startNewClaim,
          )
        : null;
    final actionRow = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: actions,
    );
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            picker,
            if (newButton != null || actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [?newButton, ...actions],
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          picker,
          if (newButton != null) ...[const SizedBox(width: 10), newButton],
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: actionRow,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _claimActions() {
    if (!_values) return const [];
    if (_status == 'invoiced') {
      final inv = _invoice;
      final id = inv?['invoice_id'] as String?;
      if (id == null || widget.onOpenInvoice == null) return const [];
      return [
        AccountsV2Button(
          label: '${_t('v2p_view_invoice')} ${inv?['invoice_reference'] ?? ''}',
          icon: 'receipt',
          onPressed: () => widget.onOpenInvoice!(id),
        ),
        AccountsV2Button(
          label: _t('v2p_revise'),
          icon: 'edit',
          onPressed: () => widget.onOpenInvoice!(id, revise: true),
        ),
      ];
    }
    if (_newClaim) return const [];
    final hasAmount = _gross > _eps && !_dirty;
    final checked = _status == 'ready_for_accounts';
    final no = _invoiceNo;
    return [
      if (widget.onPreviewInvoice != null)
        AccountsV2Button(
          label: _t('v2p_preview_invoice'),
          icon: 'doc',
          onPressed: hasAmount && !_busy ? _preview : null,
        ),
      if (widget.onIssue != null)
        AccountsV2Button(
          label: no == null
              ? _t('v2p_issue_invoice')
              : '${_t('v2p_issue_invoice')} $no',
          icon: 'receipt',
          kind: AccountsV2ButtonKind.primary,
          tooltip: checked ? null : _t('v2p_issue_needs_check'),
          onPressed: hasAmount && checked && !_busy ? _issue : null,
        ),
    ];
  }

  Widget _kpis() {
    final ro = _status == 'invoiced';
    final amounts = _amounts;
    final gross = amounts.gross;
    final vatPct = _vatPercent;
    final contract = _contractValue;
    final before = _newClaim
        ? _views.values.fold<double>(0, (a, v) => a + _d(v.cell.claimed))
        : _views.values.fold<double>(0, (a, v) => a + v.beforeAmount);
    final sug = ro ? 0 : _siteRecords;
    final (statusLabel, statusTone, statusIcon) = switch (_status) {
      'invoiced' => (_t('v2p_status_invoiced'), AccountsV2Tone.green, 'check'),
      'ready_for_accounts' => (
        _t('v2p_status_checked'),
        AccountsV2Tone.blue,
        'shield',
      ),
      'new' => (_t('v2p_status_new'), AccountsV2Tone.org, 'edit'),
      _ => (_t('v2p_status_draft'), AccountsV2Tone.org, 'edit'),
    };
    final checkedBy = _claim?['checked_by'] as String?;
    final preparedBy = _claim?['prepared_by'] as String?;
    return AccountsV2KpiRow(
      children: [
        if (_values) ...[
          AccountsV2KpiCard(
            icon: 'chart',
            label: _t('v2p_kpi_this_claim'),
            value: v2Money(gross),
            caption: _t('v2p_excl_vat'),
          ),
          AccountsV2KpiCard(
            icon: 'receipt',
            tone: AccountsV2Tone.green,
            label: _t('v2p_kpi_net'),
            value: v2Money(amounts.net),
            caption:
                '${_t('v2p_incl_vat')} ${v2Fmt(vatPct, vatPct % 1 == 0 ? 0 : 2)}%',
          ),
          AccountsV2KpiCard(
            icon: 'spark',
            label: _t('v2p_kpi_contract_invoiced'),
            value: contract > 0
                ? '${v2Pct(before / contract * 100)} → '
                      '${v2Pct((before + gross) / contract * 100)}'
                : '—',
            caption: _t('v2p_before_after'),
          ),
        ],
        AccountsV2KpiCard(
          icon: 'truck',
          tone: AccountsV2Tone.vio,
          label: _t('v2p_kpi_site'),
          value: ro ? '—' : '$sug',
          caption: ro
              ? _t('v2p_claim_is_invoiced')
              : sug > 0
              ? _t('v2p_site_waiting')
              : _t('v2p_nothing_waiting'),
          valueTone: sug > 0
              ? AccountsV2ValueTone.vio
              : AccountsV2ValueTone.plain,
        ),
        AccountsV2KpiCard(
          icon: statusIcon,
          tone: statusTone,
          label: _t('v2p_kpi_status'),
          value: statusLabel,
          caption: checkedBy != null && _status != 'draft'
              ? '${_t('v2p_checked_by')} $checkedBy'
              : '${_t('v2p_prepared_by')} ${preparedBy ?? '—'}',
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final width = narrow ? null : 228.0;
    Widget field(Widget child) => narrow
        ? ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: child,
          )
        : child;
    final selects = [
      AccountsV2Select<String>(
        label: _t('v2p_building'),
        value: _fBuilding,
        width: width,
        options: [
          ('all', _t('v2p_all')),
          for (final b in _buildings) (b.id, b.name),
        ],
        onChanged: (v) => setState(() => _fBuilding = v),
      ),
      AccountsV2Select<String>(
        label: _t('v2p_stage'),
        value: _fStage,
        width: width,
        options: [
          ('all', _t('v2p_all')),
          for (final s in _stages) (s.key, s.name),
        ],
        onChanged: (v) => setState(() => _fStage = v),
      ),
      AccountsV2Select<String>(
        label: _t('v2p_show'),
        value: _fShow,
        width: width,
        options: [
          ('all', _t('v2p_show_all')),
          ('claimed', _t('v2p_show_claimed')),
          ('sug', _t('v2p_show_sug')),
          ('open', _t('v2p_show_open')),
        ],
        onChanged: (v) => setState(() => _fShow = v),
      ),
    ];
    final toggles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccountsV2Button(
          label: _t('v2p_expand_all'),
          size: AccountsV2ButtonSize.small,
          onPressed: () => setState(() {
            _openBuildings.addAll(_buildings.map((b) => b.id));
            _openStages.addAll(_views.keys);
          }),
        ),
        const SizedBox(width: 8),
        AccountsV2Button(
          label: _t('v2p_collapse_all'),
          size: AccountsV2ButtonSize.small,
          onPressed: () => setState(() {
            _openBuildings.clear();
            _openStages.clear();
          }),
        ),
      ],
    );
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in selects) ...[field(s), const SizedBox(height: 10)],
            Align(alignment: AlignmentDirectional.centerEnd, child: toggles),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          for (final (i, s) in selects.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            s,
          ],
          const Spacer(),
          toggles,
        ],
      ),
    );
  }

  // ─── Save card ────────────────────────────────────────────────────────────

  Widget _saveCard(BuildContext context, bool dirty) {
    final needsEvidence = _hasIncrease && _evidence.isEmpty;
    final invalid = _invalidInput;
    final canSave =
        dirty &&
        !_saving &&
        !invalid &&
        !needsEvidence &&
        _periodStart.compareTo(_periodEnd) <= 0;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final docs = {for (final d in widget.evidenceDocuments) d.id: d.name};
    return AccountsV2Panel(
      padding: phone
          ? const EdgeInsets.all(14)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2Note(
            tone: _error != null || invalid
                ? AccountsV2NoteTone.bad
                : AccountsV2NoteTone.warn,
            trailing: phone ? null : _saveButtons(canSave),
            child: Text(
              _error ??
                  (invalid
                      ? '${_t('v2p_col_total_done')}: ${_t('v2p_over_total')}'
                      : _t('v2p_unsaved')),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DateBox(
                label: _t('v2p_period_from'),
                iso: _periodStart,
                width: phone ? double.infinity : 200,
                onPicked: (v) => setState(() => _periodStart = v),
              ),
              _DateBox(
                label: _t('v2p_period_to'),
                iso: _periodEnd,
                width: phone ? double.infinity : 200,
                onPicked: (v) => setState(() => _periodEnd = v),
              ),
              SizedBox(
                width: phone ? double.infinity : 300,
                child: AccountsV2TextField(
                  label: _t('v2p_note_opt'),
                  controller: _note,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _t('v2p_evidence'),
                style: v2Style(12.5, weight: FontWeight.w700),
              ),
              for (final id in _evidence)
                _EvidenceChip(
                  label: docs[id] ?? (id.length > 8 ? id.substring(0, 8) : id),
                  onRemove: () => setState(() => _evidence.remove(id)),
                ),
              _AddEvidenceButton(
                label: _t('v2p_add_file'),
                chooseLabel: _t('v2p_choose_file'),
                uploadLabel: _t('v2_evidence_upload'),
                documents: [
                  for (final d in widget.evidenceDocuments)
                    if (!_evidence.contains(d.id)) d,
                ],
                busy: _uploading,
                onChoose: (id) => setState(() => _evidence.add(id)),
                onUpload: widget.onUploadEvidence == null
                    ? null
                    : _uploadEvidence,
              ),
              if (needsEvidence)
                Text(
                  _t('v2p_evidence_needed'),
                  style: v2Style(12, color: AccountsV2Colors.bad),
                ),
            ],
          ),
          if (phone) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _saveButtons(canSave),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveButtons(bool canSave) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AccountsV2Button(
        label: _t('v2c_discard'),
        size: AccountsV2ButtonSize.small,
        onPressed: _saving ? null : _discard,
      ),
      AccountsV2Button(
        label: _saving ? _t('v2c_saving') : _t('v2p_save_progress'),
        icon: 'check',
        kind: AccountsV2ButtonKind.primary,
        size: AccountsV2ButtonSize.small,
        onPressed: canSave ? _save : null,
      ),
    ],
  );

  // ─── Workbench ────────────────────────────────────────────────────────────

  Widget _workbenchCard(BuildContext context) {
    final rows = <Widget>[];
    for (final b in _buildings) {
      if (_fBuilding != 'all' && b.id != _fBuilding) continue;
      final cells = b.cells.where(_matches).toList();
      if (_filtering && cells.isEmpty) continue;
      final open = _filtering || _openBuildings.contains(b.id);
      rows.add(
        _BuildingBlock(
          first: rows.isEmpty,
          open: open,
          header: _buildingRow(context, b, open),
          children: [
            for (final (i, v) in cells.indexed)
              _stageBlock(context, b, v, first: i == 0),
          ],
        ),
      );
    }
    final stageCount = _stages.length;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'hier',
            title: _t('v2p_wb_title'),
            subtitle: _t('v2p_wb_sub'),
            divider: false,
            actions: [
              AccountsV2Chip(
                '${_buildings.length} ${_t('v2p_physical_buildings')} · '
                '${_buildings.length * stageCount} ${_t('v2p_billing_stages')}',
                tone: AccountsV2ChipTone.pri,
              ),
            ],
          ),
          if (rows.isEmpty)
            AccountsV2Empty(
              icon: 'hier',
              title: _t('v2p_no_match'),
              action: AccountsV2Button(
                label: _t('v2p_clear_filters'),
                onPressed: () => setState(() {
                  _fBuilding = 'all';
                  _fStage = 'all';
                  _fShow = 'all';
                }),
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }

  double _buildingShare(_Building b) {
    final setup = widget.setup;
    if (setup != null) {
      for (final sb in setup.buildings) {
        if (sb.projectScopeId == b.id) return _d(sb.allocationPercent);
      }
    }
    final contract = _contractValue;
    if (contract <= 0) return 0;
    return b.cells.fold<double>(0, (a, v) => a + v.stageValue) / contract * 100;
  }

  double _stageShare(String stageKey) {
    final setup = widget.setup;
    if (setup != null) {
      for (final s in setup.stages) {
        if (s.stageKey == stageKey) return _d(s.allocationPercent);
      }
    }
    return 0;
  }

  Widget _buildingRow(BuildContext context, _Building b, bool open) {
    final buildingValue = b.cells.fold<double>(0, (a, v) => a + v.stageValue);
    double before;
    double now;
    if (_values && buildingValue > 0) {
      before =
          b.cells.fold<double>(0, (a, v) => a + v.beforeAmount) / buildingValue;
      now =
          b.cells.fold<double>(0, (a, v) => a + _liveAmount(v)) / buildingValue;
    } else {
      var weight = 0.0;
      before = 0;
      now = 0;
      for (final v in b.cells) {
        final w = _stageShare(v.cell.stageKey);
        final (fb, fn) = _fractions(v);
        before += fb * (w > 0 ? w : 1);
        now += fn * (w > 0 ? w : 1);
        weight += w > 0 ? w : 1;
      }
      if (weight > 0) {
        before /= weight;
        now /= weight;
      }
    }
    final amount = b.cells.fold<double>(0, (a, v) => a + _liveAmount(v));
    return _WorkbenchRow(
      stage: false,
      open: open,
      onTap: () => setState(() {
        if (!_openBuildings.remove(b.id)) _openBuildings.add(b.id);
      }),
      leading: const _BuildingTile(),
      title: Text(
        b.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: v2Style(14.5, weight: FontWeight.w700, height: 1.35),
      ),
      subtitle:
          '${v2Pct(_buildingShare(b), 0)} ${_t('v2p_of_contract')} · '
          '${_stages.length} ${_t('v2p_billing_stages')}',
      before: before,
      now: now,
      amount: _amountText(
        amount,
        b.cells.fold<double>(0, (a, v) => a + _fractions(v).$2),
        digits: 2,
      ),
      amountLabel: _t('v2p_this_claim'),
    );
  }

  String _amountText(double amount, double fraction, {int digits = 0}) {
    if (_values) return amount > _eps ? v2Money(amount, digits: digits) : '—';
    return fraction > 0.00001 ? v2Pct(fraction * 100) : '—';
  }

  Widget _stageBlock(
    BuildContext context,
    _Building b,
    _CellView v, {
    required bool first,
  }) {
    final key = v.key;
    final open = _openStages.contains(key);
    final stageIndex = _stages.indexWhere((s) => s.key == v.cell.stageKey);
    final sug = _status == 'invoiced' ? 0 : _siteCount(v);
    final (before, now) = _fractions(v);
    final over = _cellOver(v);
    final measure = v.cell.isItemsMode
        ? '${v.items.length} ${_t('v2p_items')}'
        : _t('v2p_pct_complete');
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkbenchRow(
            stage: true,
            open: open,
            onTap: () => setState(() {
              if (!_openStages.remove(key)) _openStages.add(key);
            }),
            leading: _StageNumber(number: stageIndex + 1, open: open),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    v.cell.stageLabel ?? v.cell.stageKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: v2Style(13, weight: FontWeight.w700, height: 1.35),
                  ),
                ),
                if (sug > 0) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _t('v2p_site_chip_tip'),
                    child: AccountsV2Chip(
                      '$sug',
                      tone: AccountsV2ChipTone.vio,
                      icon: 'truck',
                    ),
                  ),
                ],
              ],
            ),
            subtitle: [
              if (_stageShare(v.cell.stageKey) > 0)
                '${v2Pct(_stageShare(v.cell.stageKey), 0)} ${_t('v2p_of_contract')}',
              measure,
              if (_values) v2Money(v.stageValue, digits: 0),
            ].join(' · '),
            before: before,
            now: now,
            over: over,
            amount: _amountText(_liveAmount(v), now),
            amountLabel: _t('v2p_this_claim'),
          ),
          if (open)
            _EditorPad(
              child: v.cell.isItemsMode
                  ? _itemsEditor(context, b, v)
                  : _lumpEditor(context, b, v),
            ),
        ],
      ),
    );
  }

  Widget _toolbar(List<Widget> leading, List<Widget> actions) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: leading,
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }

  Widget _suggestionLine(_CellView v) {
    final s = v.cell.suggestedPercent;
    if (s == null || _status == 'invoiced') return const SizedBox.shrink();
    final by = v.cell.suggestedBy;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const AccountsV2Icon('truck', size: 15, color: AccountsV2Colors.vio),
        Text(
          '${by == null || by.isEmpty ? '' : '$by '}${_t('v2p_suggested')} '
          '${v2Pct(_d(s))}',
          style: v2Style(
            12.5,
            weight: FontWeight.w600,
            color: AccountsV2Colors.vio,
          ),
        ),
      ],
    );
  }

  Widget _deliveriesLine(int waiting) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const AccountsV2Icon('truck', size: 15, color: AccountsV2Colors.vio),
        Text(
          '$waiting ${_t(waiting == 1 ? 'v2m_item_waiting' : 'v2m_items_waiting')}',
          style: v2Style(
            12.5,
            weight: FontWeight.w600,
            color: AccountsV2Colors.vio,
          ),
        ),
      ],
    );
  }

  Widget _lumpEditor(BuildContext context, _Building b, _CellView v) {
    final ro = !_canEdit;
    final controller = _pct[v.cell.progressEntryId]!;
    final typed = _typedPct(v);
    final total = v.beforePct + typed;
    final over = total.compareTo(YorksAccountsDecimal.hundred) > 0;
    final amount = _liveAmount(v);
    final phone = AccountsV2Breakpoints.isPhone(context);
    final input = _QtyCell(
      controller: controller,
      enabled: !ro,
      showMax: !ro && _d(v.beforePct) < 100 - _eps,
      maxTooltip: _t('v2p_max_tip_lump'),
      maxLabel: _t('v2p_max'),
      error: over,
      onMax: () => _maxLump(v),
    );
    final columns = <AccountsV2Column>[
      if (_values) AccountsV2Column(_t('v2p_col_stage_value'), numeric: true),
      AccountsV2Column(_t('v2p_col_done_before'), width: 120, numeric: true),
      AccountsV2Column(_t('v2p_col_this_pct'), width: 170, numeric: true),
      AccountsV2Column(
        _t('v2p_col_total_done'),
        width: _values ? 120 : null,
        numeric: true,
      ),
      if (_values)
        AccountsV2Column(_t('v2p_col_this_aed'), width: 150, numeric: true),
    ];
    final sugAction = v.cell.suggestedPercent != null && !ro
        ? AccountsV2Button(
            label: _t('v2p_use'),
            size: AccountsV2ButtonSize.small,
            icon: 'truck',
            onPressed: () => _useSuggestion(v),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ro ||
            widget.onUpdateCell != null ||
            v.cell.suggestedPercent != null) ...[
          _toolbar(
            [
              if (v.cell.suggestedPercent != null && _status != 'invoiced')
                _suggestionLine(v)
              else
                Text(
                  '${b.name} · ${_t('v2p_lump_hint')}',
                  style: v2Style(12, color: AccountsV2Colors.mut),
                ),
            ],
            [
              ?sugAction,
              if (!ro && _buildings.length > 1)
                AccountsV2Button(
                  label: _t('v2p_copy_all'),
                  icon: 'copy',
                  size: AccountsV2ButtonSize.small,
                  onPressed: () => _copyLumpToAll(v),
                ),
              if (ro && widget.onUpdateCell != null)
                AccountsV2Button(
                  label: _t('v2_cell_update_progress'),
                  icon: 'edit',
                  size: AccountsV2ButtonSize.small,
                  onPressed: () => widget.onUpdateCell!(v.cell),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        AccountsV2Table(
          boxed: true,
          minWidth: phone ? 640 : 0,
          columns: columns,
          rows: [
            AccountsV2Row([
              if (_values) Text(v2Fmt(v.stageValue)),
              Text(v2Pct(_d(v.beforePct))),
              input,
              over
                  ? Text(
                      '${v2Pct(_d(total))} ⚠',
                      style: v2Style(
                        12.5,
                        weight: FontWeight.w700,
                        color: AccountsV2Colors.bad,
                      ),
                    )
                  : Text(v2Pct(_d(total))),
              if (_values)
                amount > _eps
                    ? Text(
                        v2Fmt(amount),
                        style: v2Style(
                          12.5,
                          weight: FontWeight.w700,
                          tabular: true,
                        ),
                      )
                    : Text(
                        '—',
                        style: v2Style(12.5, color: AccountsV2Colors.mut),
                      ),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        AccountsV2How(
          spans: [
            ('${_t('v2p_amount_eq')} ', false),
            (_t('v2p_lump_code'), true),
            ('. ${_t('v2p_lump_how')}', false),
          ],
        ),
      ],
    );
  }

  Widget _itemsEditor(BuildContext context, _Building b, _CellView v) {
    final ro = !_canEdit;
    if (v.items.isEmpty) {
      return AccountsV2Empty(
        icon: 'list',
        title: _t('v2p_no_items_title'),
        body: _t('v2p_no_items_body'),
        action: widget.onOpenContract == null
            ? null
            : AccountsV2Button(
                label: _t('v2p_open_contract'),
                size: AccountsV2ButtonSize.small,
                onPressed: widget.onOpenContract,
              ),
      );
    }
    final phone = AccountsV2Breakpoints.isPhone(context);
    final waiting = v.items.where((i) => _deliveryWaiting(v, i)).length;
    final anyDelivered = v.items.any((i) => _delivered(v, i) != null);
    final columns = <AccountsV2Column>[
      AccountsV2Column(_t('v2p_col_item')),
      AccountsV2Column(_t('v2p_col_before'), width: 84, numeric: true),
      AccountsV2Column(_t('v2p_col_this'), width: 156, numeric: true),
      AccountsV2Column(_t('v2p_col_to_date'), width: 112, numeric: true),
      if (_values)
        AccountsV2Column(_t('v2p_col_amount'), width: 130, numeric: true),
    ];
    String qty(YorksAccountsDecimal q) {
      final d = _d(q);
      return v2Fmt(d, d % 1 == 0 ? 0 : 2);
    }

    final rows = <AccountsV2Row>[];
    for (final (index, i) in v.items.indexed) {
      final typed = _typedQty(i);
      final toDate = i.before + typed;
      final total = _d(i.item.quantity);
      final pct = total > 0 ? _d(toDate) / total * 100 : 0.0;
      final over = toDate.compareTo(i.item.quantity) > 0;
      final amount = _itemAmount(i, _d(typed));
      rows.add(
        AccountsV2Row([
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                i.item.itemLabel,
                style: v2Style(12.5, weight: FontWeight.w700),
              ),
              Text(
                [
                  '${qty(i.item.quantity)} ${i.item.unitCode}',
                  if (_values) v2Fmt(_itemValue(i)),
                ].join(' · '),
                style: v2Style(12, color: AccountsV2Colors.mut, tabular: true),
              ),
              if (_delivered(v, i) case final d?)
                _DeliveredLine(
                  key: ValueKey('v2m_delivered_${i.item.stageItemId}'),
                  text:
                      '${d.isShare ? '≈ ' : ''}'
                      '${qty(_deliveredTarget(v, i)!)} ${_t('v2m_delivered')}'
                      '${d.lastDeliveryReference == null ? '' : ' · ${d.lastDeliveryReference}'}',
                  tooltip: d.isShare ? _t('v2m_share_hint') : null,
                  useLabel: _t('v2p_use'),
                  onUse: !ro && _deliveryWaiting(v, i)
                      ? () => _useDelivered(v, i)
                      : null,
                ),
            ],
          ),
          i.before.isZero
              ? Text('0', style: v2Style(12.5, color: AccountsV2Colors.mut))
              : Text(qty(i.before)),
          _QtyCell(
            controller: _qty[i.item.stageItemId]!,
            enabled: !ro,
            showMax: !ro && i.before.compareTo(i.item.quantity) < 0,
            maxTooltip: _t('v2p_max_tip_item'),
            maxLabel: _t('v2p_max'),
            error: over,
            last: index == v.items.length - 1,
            onMax: () => _maxItem(i),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${qty(toDate)} · ${v2Pct(pct, 0)}${over ? ' ⚠' : ''}',
                style: over
                    ? v2Style(
                        12.5,
                        weight: FontWeight.w700,
                        color: AccountsV2Colors.bad,
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 84,
                child: AccountsV2Bar(
                  segments: [
                    (
                      (pct / 100).clamp(0.0, 1.0),
                      over
                          ? AccountsV2Colors.bad
                          : pct >= 99.99
                          ? AccountsV2Colors.ok
                          : AccountsV2Colors.pri,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_values)
            amount > _eps
                ? Text(
                    v2Fmt(amount),
                    style: v2Style(
                      12.5,
                      weight: FontWeight.w700,
                      tabular: true,
                    ),
                  )
                : Text('—', style: v2Style(12.5, color: AccountsV2Colors.mut)),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(
          [
            if (v.cell.suggestedPercent != null && _status != 'invoiced')
              _suggestionLine(v)
            else if (waiting > 0)
              _deliveriesLine(waiting)
            else
              Text(
                '${b.name} · ${v.items.length} ${_t('v2p_items')}',
                style: v2Style(12, color: AccountsV2Colors.mut),
              ),
          ],
          [
            if (!ro && waiting > 0)
              AccountsV2Button(
                key: ValueKey('v2m_use_all_${v.key}'),
                label: _t('v2m_use_all'),
                icon: 'truck',
                size: AccountsV2ButtonSize.small,
                onPressed: () => _useAllDelivered(v),
              ),
            if (!ro && _buildings.length > 1)
              AccountsV2Button(
                label: _t('v2p_copy_all'),
                icon: 'copy',
                size: AccountsV2ButtonSize.small,
                onPressed: () => _copyItemsToAll(v),
              ),
            if (!ro)
              AccountsV2Button(
                label: _t('v2p_clear'),
                size: AccountsV2ButtonSize.small,
                onPressed: () => _clearItems(v),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AccountsV2Table(
          boxed: true,
          minWidth: phone ? 640 : 0,
          columns: columns,
          rows: rows,
          footer: _values
              ? [
                  Text(
                    '${b.name} · ${v.cell.stageLabel ?? v.cell.stageKey} — '
                    '${_t('v2p_items_this_claim')}',
                  ),
                  Text(v2Fmt(_liveAmount(v))),
                ]
              : null,
          footerSpans: const [4, 1],
        ),
        const SizedBox(height: 10),
        AccountsV2How(
          spans: [
            ('${_t('v2p_amount_eq')} ', false),
            (_t('v2p_items_code'), true),
            ('. ${_t('v2p_items_how')}', false),
            if (anyDelivered) (' ${_t('v2m_used_hint')}', false),
          ],
        ),
      ],
    );
  }

  // ─── Claim details panel ──────────────────────────────────────────────────

  Widget _sidePanel() {
    final status = _status;
    final ro = status == 'invoiced';
    final amounts = _amounts;
    final gross = amounts.gross;
    final vatPct = _vatPercent;
    final vat = amounts.vat;
    final net = amounts.net;
    final retentionPct = v2Number(_claim?['retention_percent']);
    final retention = ro ? 0.0 : gross * retentionPct / 100;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final (chipLabel, chipTone) = switch (status) {
      'invoiced' => (_t('v2p_status_invoiced'), AccountsV2ChipTone.ok),
      'ready_for_accounts' => (
        _t('v2p_status_checked'),
        AccountsV2ChipTone.pri,
      ),
      'new' => (_t('v2p_status_new'), AccountsV2ChipTone.warn),
      _ => (_t('v2p_status_draft'), AccountsV2ChipTone.warn),
    };
    final number = _newClaim ? _liveClaims.length + 1 : _numberOf(_claimId);
    final month = _newClaim
        ? v2Month(_periodEnd)
        : v2Month(_claim?['claim_period_end'] ?? _claim?['claim_period_start']);
    final preparedBy = _claim?['prepared_by'] as String?;
    final checkedBy = _claim?['checked_by'] as String?;
    final no = _invoiceNo;
    final hasAmount = gross > _eps && !_dirty;
    final checked = status == 'ready_for_accounts';
    final steps = <(String, int)>[
      (_t('v2p_status_draft'), status == 'draft' || status == 'new' ? 1 : 2),
      (_t('v2p_checked_by_pm'), checked ? 1 : (ro ? 2 : 0)),
      (_t('v2p_status_invoiced'), ro ? 2 : 0),
    ];
    final canMark =
        status == 'draft' && widget.onMarkChecked != null && _claimId != null;
    final canReopen = checked && widget.onReopen != null && _claimId != null;
    final canDelete =
        status == 'draft' &&
        widget.onCancelClaim != null &&
        widget.workbench.canCancelClaim &&
        _claimId != null;
    final actions = <Widget>[
      if (ro) ...[
        if (_invoice?['invoice_id'] != null && widget.onOpenInvoice != null)
          AccountsV2Button(
            label: '${_t('v2p_view_invoice')} ${no ?? ''}',
            icon: 'receipt',
            block: true,
            onPressed: () =>
                widget.onOpenInvoice!(_invoice!['invoice_id'] as String),
          ),
      ] else if (!_newClaim) ...[
        Row(
          children: [
            if (canMark || canReopen)
              Expanded(
                child: canMark
                    ? AccountsV2Button(
                        label: _t('v2p_mark_checked'),
                        icon: 'check',
                        size: AccountsV2ButtonSize.small,
                        block: true,
                        onPressed: hasAmount && !_busy ? _markChecked : null,
                      )
                    : AccountsV2Button(
                        label: _t('v2p_back_to_draft'),
                        icon: 'undo',
                        size: AccountsV2ButtonSize.small,
                        block: true,
                        onPressed: _busy ? null : _reopen,
                      ),
              ),
            if ((canMark || canReopen) &&
                widget.onPreviewInvoice != null &&
                _values)
              const SizedBox(width: 8),
            if (widget.onPreviewInvoice != null && _values)
              Expanded(
                child: AccountsV2Button(
                  label: _t('v2p_preview'),
                  icon: 'doc',
                  size: AccountsV2ButtonSize.small,
                  block: true,
                  onPressed: hasAmount && !_busy ? _preview : null,
                ),
              ),
          ],
        ),
        if (widget.onIssue != null && _values)
          AccountsV2Button(
            label: no == null
                ? _t('v2p_issue_invoice')
                : '${_t('v2p_issue_invoice')} $no',
            icon: 'receipt',
            kind: AccountsV2ButtonKind.primary,
            block: true,
            tooltip: checked ? null : _t('v2p_issue_needs_check'),
            onPressed: hasAmount && checked && !_busy ? _issue : null,
          ),
        if (gross <= _eps)
          Text(
            _t('v2p_enter_progress'),
            textAlign: TextAlign.center,
            style: v2Style(12, color: AccountsV2Colors.mut),
          )
        // Why Issue is not available yet, said where it shows, not only on
        // hover: a claim is checked before Accounts invoices it.
        else if (widget.onIssue != null && _values && !checked)
          Text(
            _t('v2p_issue_needs_check'),
            textAlign: TextAlign.center,
            style: v2Style(12, color: AccountsV2Colors.mut),
          ),
        if (canDelete)
          AccountsV2Button(
            label: _t('v2p_delete_draft'),
            kind: AccountsV2ButtonKind.ghostDanger,
            size: AccountsV2ButtonSize.small,
            block: true,
            onPressed: _busy ? null : _deleteDraft,
          ),
      ],
    ];
    return AccountsV2Panel(
      padding: phone
          ? const EdgeInsets.all(14)
          : const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('v2p_claim_details'),
                  style: v2Style(17, weight: FontWeight.w700, height: 1.3),
                ),
              ),
              AccountsV2Chip(chipLabel, tone: chipTone),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${_t('v2p_claim')} ${_no(number)}',
            style: v2Style(22, weight: FontWeight.w700, height: 1.2),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 8),
            child: Text(
              [
                month,
                if (preparedBy != null)
                  '${_t('v2p_prepared_by_lower')} $preparedBy',
                if (checkedBy != null && status != 'draft')
                  '${_t('v2p_checked_by_lower')} $checkedBy',
              ].join(' · '),
              style: v2Style(12.5, color: AccountsV2Colors.ink2),
            ),
          ),
          _Pipeline(steps: steps),
          if (_values) ...[
            for (final s in _stages)
              AccountsV2LedgerRow(
                label: s.name,
                value: _stageAmount(s.key) > _eps
                    ? v2Money(_stageAmount(s.key))
                    : '—',
              ),
            AccountsV2LedgerRow(label: _t('v2p_gross'), value: v2Money(gross)),
            AccountsV2LedgerRow(
              label:
                  '${_t('v2p_vat')} ${v2Fmt(vatPct, vatPct % 1 == 0 ? 0 : 2)}%',
              value: v2Money(vat),
            ),
            if (retention > _eps) ...[
              AccountsV2LedgerRow(
                label:
                    '${_t('v2p_retention_held')} ${v2Fmt(retentionPct, retentionPct % 1 == 0 ? 0 : 2)}%',
                value: '− ${v2Money(retention)}',
              ),
              AccountsV2LedgerRow(
                label: _t('v2p_after_retention'),
                value: v2Money(net - retention),
              ),
            ],
            AccountsV2LedgerRow(
              label: ro ? _t('v2p_invoice') : _t('v2p_invoice_no'),
              value: no ?? '—',
            ),
            _NetBox(
              label: _t('v2p_kpi_net'),
              amount: v2Money(net),
              words: v2AmountInWords(net),
            ),
          ] else
            for (final s in _stages)
              AccountsV2LedgerRow(
                label: s.name,
                value: () {
                  final views = _views.values.where(
                    (v) => v.cell.stageKey == s.key,
                  );
                  if (views.isEmpty) return '—';
                  final f =
                      views.fold<double>(0, (a, v) => a + _fractions(v).$2) /
                      views.length;
                  return f > 0.00001 ? v2Pct(f * 100) : '—';
                }(),
              ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final (i, a) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              a,
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Small pieces ────────────────────────────────────────────────────────────

/// Under an item: what has reached site from its BOQ folders, with Use when
/// more arrived than the claim has to date.
class _DeliveredLine extends StatelessWidget {
  const _DeliveredLine({
    super.key,
    required this.text,
    required this.tooltip,
    required this.useLabel,
    required this.onUse,
  });

  final String text;
  final String? tooltip;
  final String useLabel;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    // The figure wraps rather than hiding the delivery number, and Use keeps
    // a full-size tap target on a phone.
    final phone = AccountsV2Breakpoints.isPhone(context);
    final figure = Text.rich(
      TextSpan(
        children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: 5),
              child: AccountsV2Icon(
                'truck',
                size: 13,
                color: AccountsV2Colors.vio,
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: v2Style(
        12,
        weight: FontWeight.w600,
        color: AccountsV2Colors.vio,
        tabular: true,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          tooltip == null ? figure : Tooltip(message: tooltip!, child: figure),
          if (onUse != null)
            Semantics(
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onUse,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: phone ? 44 : 0,
                    minWidth: phone ? 44 : 0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        useLabel,
                        style: v2Style(
                          12,
                          weight: FontWeight.w700,
                          color: AccountsV2Colors.pri,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _BuildingBlock extends StatelessWidget {
  const _BuildingBlock({
    required this.first,
    required this.open,
    required this.header,
    required this.children,
  });

  final bool first;
  final bool open;
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (open && children.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                color: AccountsV2Colors.quietPanel,
                border: Border(top: BorderSide(color: AccountsV2Colors.line2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

/// One building or stage row of the workbench (`.wb-row`, `.wb-row.st`).
class _WorkbenchRow extends StatefulWidget {
  const _WorkbenchRow({
    required this.stage,
    required this.open,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.before,
    required this.now,
    required this.amount,
    required this.amountLabel,
    this.over = false,
  });

  final bool stage;
  final bool open;
  final VoidCallback onTap;
  final Widget leading;
  final Widget title;
  final String subtitle;
  final double before;
  final double now;
  final bool over;
  final String amount;
  final String amountLabel;

  @override
  State<_WorkbenchRow> createState() => _WorkbenchRowState();
}

class _WorkbenchRowState extends State<_WorkbenchRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    final medium = AccountsV2Breakpoints.isMedium(context);
    final stage = widget.stage;
    final gap = narrow ? 10.0 : 16.0;
    final lead = stage ? (narrow ? 28.0 : 30.0) : (narrow ? 40.0 : 44.0);
    final padding = narrow
        ? EdgeInsets.fromLTRB(stage ? 20 : 14, 12, 14, 12)
        : EdgeInsets.fromLTRB(stage ? 32 : 18, 12, 18, 12);
    final total = widget.before + widget.now;
    final over = widget.over || total > 1.0001;
    final bar = Row(
      children: [
        Expanded(
          child: Tooltip(
            message:
                '${v2Pct(widget.before * 100)} + ${v2Pct(widget.now * 100)}',
            child: AccountsV2Bar(
              segments: [
                (widget.before.clamp(0.0, 1.0), AccountsV2Colors.pri),
                (
                  widget.now.clamp(0.0, (1 - widget.before).clamp(0.0, 1.0)),
                  over ? AccountsV2Colors.bad : AccountsV2Colors.priLight,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: Text(
            v2Pct(total * 100),
            textAlign: TextAlign.right,
            style: v2Style(
              11,
              weight: FontWeight.w700,
              color: over ? AccountsV2Colors.bad : AccountsV2Colors.mut,
            ),
          ),
        ),
      ],
    );
    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.amount,
          maxLines: 1,
          style: v2Style(
            11.5,
            weight: FontWeight.w700,
            color: AccountsV2Colors.ink2,
            tabular: true,
          ),
        ),
        Text(
          widget.amountLabel,
          style: v2Style(12.5, color: AccountsV2Colors.ink2),
        ),
      ],
    );
    final row = Row(
      children: [
        SizedBox(width: lead, child: widget.leading),
        SizedBox(width: gap),
        Expanded(
          flex: medium ? 120 : 115,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.title,
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: v2Style(12.5, color: AccountsV2Colors.ink2),
              ),
            ],
          ),
        ),
        if (!narrow) ...[
          SizedBox(width: gap),
          Expanded(flex: medium ? 100 : 150, child: bar),
          SizedBox(width: gap),
          SizedBox(width: medium ? 140 : 160, child: amount),
        ] else ...[
          SizedBox(width: gap),
          amount,
        ],
        SizedBox(width: gap),
        SizedBox(
          width: narrow ? 18 : 22,
          child: AnimatedRotation(
            turns: widget.open ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: const AccountsV2Icon(
              'chevD',
              size: 20,
              color: AccountsV2Colors.ink,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      expanded: widget.open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            color: _hover ? AccountsV2Colors.rowHover : Colors.transparent,
            constraints: BoxConstraints(minHeight: stage ? 58 : 68),
            padding: padding,
            alignment: Alignment.centerLeft,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _BuildingTile extends StatelessWidget {
  const _BuildingTile();

  @override
  Widget build(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    return AccountsV2IconTile(
      icon: 'bldg',
      size: narrow ? 40 : 44,
      radius: 11,
      iconSize: 21,
    );
  }
}

class _StageNumber extends StatelessWidget {
  const _StageNumber({required this.number, required this.open});

  final int number;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final size = AccountsV2Breakpoints.isNarrow(context) ? 28.0 : 30.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: open ? AccountsV2Colors.pri : Colors.white,
        border: Border.all(
          color: open ? AccountsV2Colors.pri : AccountsV2Colors.line,
        ),
      ),
      child: Text(
        '$number',
        style: v2Style(
          12,
          weight: FontWeight.w700,
          color: open ? Colors.white : AccountsV2Colors.ink2,
          height: 1,
        ),
      ),
    );
  }
}

/// The editor area under an open stage (`.wb-ed`).
class _EditorPad extends StatelessWidget {
  const _EditorPad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final narrow = AccountsV2Breakpoints.isNarrow(context);
    return Padding(
      padding: narrow
          ? const EdgeInsets.fromLTRB(12, 2, 12, 14)
          : const EdgeInsets.fromLTRB(76, 2, 18, 16),
      child: child,
    );
  }
}

/// A quantity input with its Max button (`.qtycell`).
class _QtyCell extends StatelessWidget {
  const _QtyCell({
    required this.controller,
    required this.enabled,
    required this.showMax,
    required this.maxLabel,
    required this.maxTooltip,
    required this.onMax,
    this.error = false,
    this.last = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool showMax;
  final String maxLabel;
  final String maxTooltip;
  final VoidCallback onMax;
  final bool error;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AccountsV2CellInput(
            controller: controller,
            numeric: true,
            bold: true,
            hint: '0',
            enabled: enabled,
            error: error,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) {
              if (!last) FocusScope.of(context).nextFocus();
            },
          ),
        ),
        const SizedBox(width: 6),
        Visibility(
          visible: showMax,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Tooltip(
            message: maxTooltip,
            child: SizedBox(
              width: 46,
              height: 30,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AccountsV2Colors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: showMax ? onMax : null,
                  hoverColor: AccountsV2Colors.buttonHover,
                  child: Center(
                    child: Text(
                      maxLabel,
                      maxLines: 1,
                      style: v2Style(
                        12,
                        weight: FontWeight.w700,
                        color: AccountsV2Colors.ink2,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draft → Checked by PM → Invoiced, with dots and joining lines
/// (`.pipeline`). Each step is 0 = to do, 1 = current, 2 = done.
class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.steps});

  final List<(String, int)> steps;

  Color _color(int state) => switch (state) {
    2 => AccountsV2Colors.ok,
    1 => AccountsV2Colors.pri,
    _ => AccountsV2Colors.line,
  };

  Color _lineColor(int state) =>
      state == 2 ? AccountsV2Colors.ok : AccountsV2Colors.line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (label, state)) in steps.indexed)
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 22,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        if (i > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 10,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: .5,
                              child: Container(
                                height: 2,
                                color: _lineColor(state),
                              ),
                            ),
                          ),
                        if (i < steps.length - 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 10,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerRight,
                              widthFactor: .5,
                              child: Container(
                                height: 2,
                                color: _lineColor(steps[i + 1].$2),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 5,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _color(state),
                              boxShadow: state == 1
                                  ? const [
                                      BoxShadow(
                                        color: AccountsV2Colors.pri100,
                                        spreadRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: v2Style(
                      11,
                      weight: state == 1
                          ? FontWeight.w700
                          : state == 2
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: state == 1
                          ? AccountsV2Colors.pri
                          : state == 2
                          ? AccountsV2Colors.ok
                          : AccountsV2Colors.mut,
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

/// The pale blue Net payable box with the amount in words (`.netbox`).
class _NetBox extends StatelessWidget {
  const _NetBox({
    required this.label,
    required this.amount,
    required this.words,
  });

  final String label;
  final String amount;
  final String words;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AccountsV2Colors.pri50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: v2Style(12, color: AccountsV2Colors.ink2)),
          const SizedBox(height: 2),
          Text(
            amount,
            style: v2Style(
              19,
              weight: FontWeight.w700,
              color: AccountsV2Colors.navy,
              tabular: true,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            words,
            style: v2Style(11, color: AccountsV2Colors.ink2, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// A read-only date field that opens a calendar (`.of input[type=date]`).
class _DateBox extends StatefulWidget {
  const _DateBox({
    required this.label,
    required this.iso,
    required this.onPicked,
    this.width,
  });

  final String label;
  final String iso;
  final ValueChanged<String> onPicked;
  final double? width;

  @override
  State<_DateBox> createState() => _DateBoxState();
}

class _DateBoxState extends State<_DateBox> {
  late final _controller = TextEditingController(text: v2Date(widget.iso));

  @override
  void didUpdateWidget(_DateBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iso != widget.iso) _controller.text = v2Date(widget.iso);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(widget.iso) ?? now,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    String two(int v) => v.toString().padLeft(2, '0');
    widget.onPicked('${picked.year}-${two(picked.month)}-${two(picked.day)}');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: AccountsV2TextField(
        label: widget.label,
        controller: _controller,
        readOnly: true,
        onTap: _pick,
        suffix: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: AccountsV2Icon(
            'clock',
            size: 17,
            color: AccountsV2Colors.ink2,
          ),
        ),
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: AccountsV2Colors.pri50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AccountsV2Icon('clip', size: 13, color: AccountsV2Colors.pri),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v2Style(
                11.5,
                weight: FontWeight.w700,
                color: AccountsV2Colors.pri,
                height: 1.2,
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: AccountsV2Icon('x', size: 13, color: AccountsV2Colors.pri),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Add file": pick one of the project's files, or upload a new one.
class _AddEvidenceButton extends StatelessWidget {
  const _AddEvidenceButton({
    required this.label,
    required this.chooseLabel,
    required this.uploadLabel,
    required this.documents,
    required this.busy,
    required this.onChoose,
    this.onUpload,
  });

  final String label;
  final String chooseLabel;
  final String uploadLabel;
  final List<YorksAccountsEvidenceDoc> documents;
  final bool busy;
  final ValueChanged<String> onChoose;
  final VoidCallback? onUpload;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final value = await showMenu<String>(
      context: context,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      position: RelativeRect.fromRect(
        topLeft & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (onUpload != null)
          PopupMenuItem<String>(
            value: '__upload',
            child: Row(
              children: [
                const AccountsV2Icon(
                  'upload',
                  size: 16,
                  color: AccountsV2Colors.pri,
                ),
                const SizedBox(width: 8),
                Text(uploadLabel, style: v2Style(13, weight: FontWeight.w600)),
              ],
            ),
          ),
        for (final d in documents)
          PopupMenuItem<String>(
            value: d.id,
            child: Row(
              children: [
                const AccountsV2Icon(
                  'doc',
                  size: 16,
                  color: AccountsV2Colors.ink2,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: v2Style(13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (value == null) return;
    if (value == '__upload') {
      onUpload?.call();
    } else {
      onChoose(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => AccountsV2Button(
        label: busy ? '…' : label,
        icon: 'plus',
        size: AccountsV2ButtonSize.small,
        tooltip: chooseLabel,
        onPressed: busy || (documents.isEmpty && onUpload == null)
            ? null
            : () => _open(context),
      ),
    );
  }
}

// ─── Command dialogs ─────────────────────────────────────────────────────────

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.language,
  });

  final String title;
  final String label;
  final AppLanguage language;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

class _IssueResult {
  const _IssueResult({
    required this.invoiceDate,
    required this.submissionDate,
    this.reference,
  });

  final String invoiceDate;
  final String submissionDate;
  final String? reference;
}

class _IssueDialog extends StatefulWidget {
  const _IssueDialog({required this.language});

  final AppLanguage language;

  @override
  State<_IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<_IssueDialog> {
  late final TextEditingController _invoiceDate;
  late final TextEditingController _submissionDate;
  final _reference = TextEditingController();

  String _t(String key) => accountsV2Text(widget.language, key);

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  void initState() {
    super.initState();
    final today = accountsV2TodayIso();
    _invoiceDate = TextEditingController(text: today);
    _submissionDate = TextEditingController(text: today);
  }

  @override
  void dispose() {
    _invoiceDate.dispose();
    _submissionDate.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        _datePattern.hasMatch(_invoiceDate.text.trim()) &&
        _datePattern.hasMatch(_submissionDate.text.trim());
    return AlertDialog(
      title: Text(_t('v2_claim_issue')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AccountsV2DateField(
            label: _t('v2_claim_invoice_date'),
            controller: _invoiceDate,
            language: widget.language,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          AccountsV2DateField(
            label: _t('v2_claim_submission_date'),
            controller: _submissionDate,
            language: widget.language,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reference,
            decoration: InputDecoration(
              labelText: _t('v2_claim_reference_opt'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('v2_cancel')),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  final ref = _reference.text.trim();
                  Navigator.of(context).pop(
                    _IssueResult(
                      invoiceDate: _invoiceDate.text.trim(),
                      submissionDate: _submissionDate.text.trim(),
                      reference: ref.isEmpty ? null : ref,
                    ),
                  );
                }
              : null,
          child: Text(_t('v2_confirm')),
        ),
      ],
    );
  }
}

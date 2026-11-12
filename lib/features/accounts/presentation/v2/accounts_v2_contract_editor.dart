part of 'accounts_v2_contract_tab.dart';

/// One item row being edited: the single list every building shares.
final class _ItemRowDraft {
  _ItemRowDraft({
    required this.key,
    required String label,
    required String quantity,
    required String unit,
    required String weight,
    required VoidCallback onChanged,
  }) : label = TextEditingController(text: label),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       weight = TextEditingController(text: weight) {
    for (final c in controllers) {
      c.addListener(onChanged);
    }
  }

  final String key;
  final TextEditingController label;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController weight;

  List<TextEditingController> get controllers => [
    label,
    quantity,
    unit,
    weight,
  ];

  bool get isValid {
    final q = YorksAccountsDecimal.tryParse(quantity.text.trim());
    final w = YorksAccountsDecimal.tryParse(weight.text.trim());
    return label.text.trim().isNotEmpty &&
        unit.text.trim().isNotEmpty &&
        q != null &&
        q.isPositive &&
        w != null &&
        w.isPositive;
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

final class _StageDraft {
  _StageDraft({
    required this.key,
    required String label,
    required String percent,
    required this.byItems,
    required this.items,
    required VoidCallback onChanged,
  }) : label = TextEditingController(text: label),
       percent = TextEditingController(text: percent) {
    this.label.addListener(onChanged);
    this.percent.addListener(onChanged);
  }

  final String key;
  final TextEditingController label;
  final TextEditingController percent;
  bool byItems;
  final List<_ItemRowDraft> items;

  void dispose() {
    label.dispose();
    percent.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

/// A building in the split being edited.
final class _BuildingDraft {
  _BuildingDraft({
    required this.scopeId,
    required this.name,
    required String share,
    required VoidCallback onChanged,
  }) : share = TextEditingController(text: share) {
    this.share.addListener(onChanged);
  }

  final String scopeId;
  final String name;
  final TextEditingController share;

  void dispose() => share.dispose();
}

typedef _ItemForm = ({
  String key,
  String label,
  String quantity,
  String unit,
  String weight,
});

final class _StageForm {
  const _StageForm({
    required this.key,
    required this.label,
    required this.percent,
    required this.byItems,
    required this.items,
  });

  final String key;
  final String label;
  final String percent;
  final bool byItems;
  final List<_ItemForm> items;

  String get signature =>
      '$key=$label=$percent=$byItems=${items.map((i) => '${i.key}:${i.label}:'
          '${i.quantity}:${i.unit}:${i.weight}').join(',')}';
}

/// Everything typed in the Contract form, as plain values.
final class _ContractForm {
  const _ContractForm({
    required this.fields,
    required this.billTo,
    required this.buildings,
    required this.stages,
  });

  /// In the order of [_ContractWorkspaceState._fields].
  final List<String> fields;
  final String? billTo;
  final List<({String scopeId, String name, String share})> buildings;
  final List<_StageForm> stages;

  String get buildingsSignature =>
      buildings.map((b) => '${b.scopeId}=${b.share}').join(';');
  String get stagesSignature => stages.map((s) => s.signature).join('|');
}

/// An unsaved Contract form with what it was started from: kept while the
/// person is on another tab, and the state an Undo returns to.
final class _ContractDraft {
  const _ContractDraft({
    required this.form,
    required this.base,
    required this.initial,
    required this.baseProfileVersion,
    required this.baseInvoiceVersion,
    required this.prefilled,
    required this.skipPrefill,
    required this.nextKey,
  });

  final _ContractForm form;

  /// The saved values the edits started from (for keeping them on top of a
  /// newer version someone else saved).
  final _ContractForm? base;
  final String initial;
  final int? baseProfileVersion;
  final int? baseInvoiceVersion;
  final bool prefilled;
  final bool skipPrefill;
  final int nextKey;
}

/// The whole Contract tab as the prototype lays it out, edited in place: the
/// contract details form, buildings, billing stages, item breakdowns and
/// variations beside a live setup check. Nothing is saved until the person
/// presses Save; the server then re-validates every part.
class _ContractWorkspace extends StatefulWidget {
  const _ContractWorkspace({
    required this.tab,
    required this.buildingChoices,
    required this.canEditSetup,
    required this.itemsBlocked,
  });

  final AccountsV2ContractTab tab;
  final List<YorksContractBuildingOption> buildingChoices;
  final bool canEditSetup;
  final bool itemsBlocked;

  @override
  State<_ContractWorkspace> createState() => _ContractWorkspaceState();
}

class _ContractWorkspaceState extends State<_ContractWorkspace> {
  final _contract = TextEditingController();
  final _vat = TextEditingController();
  final _terms = TextEditingController();
  final _reminder = TextEditingController();
  final _retention = TextEditingController();
  final _trn = TextEditingController();
  final _contact = TextEditingController();
  final _woNumber = TextEditingController();
  final _woDate = TextEditingController();
  final _contractNumber = TextEditingController();
  final _prefix = TextEditingController();
  final _scope = TextEditingController();
  final List<_BuildingDraft> _buildings = [];
  final List<_StageDraft> _stages = [];
  int _nextKey = 1;
  bool _saving = false;
  String? _error;

  /// Set when Save is pressed while something still needs fixing: the fields
  /// involved are outlined until the form is saved or discarded.
  bool _showProblems = false;
  final _detailsKey = GlobalKey();
  final _buildingsKey = GlobalKey();
  final _stagesKey = GlobalKey();
  final _itemKeys = <String, GlobalKey>{};
  String _initial = '';

  /// Empty fields were started from the project; they are unsaved until Save.
  bool _prefilled = false;

  /// Discard keeps the fields empty rather than filling them again.
  bool _skipPrefill = false;

  /// The saved values and versions the current edits started from. Save sends
  /// these versions, so edits made before someone else's save are refused by
  /// the server instead of quietly replacing that save.
  _ContractForm? _base;
  int? _baseProfileVersion;
  int? _baseInvoiceVersion;

  /// A short explanation above the save buttons (kept edits, an update).
  String? _notice;

  AccountsV2ContractTab get tab => widget.tab;
  YorksAccountsCommercialSetupRead get setup => tab.setup;
  String _t(String key) => accountsV2Text(tab.language, key);

  List<TextEditingController> get _fields => [
    _contract,
    _vat,
    _terms,
    _reminder,
    _retention,
    _trn,
    _contact,
    _woNumber,
    _woDate,
    _contractNumber,
    _prefix,
    _scope,
  ];

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in _fields) {
      c.addListener(_changed);
    }
    _load();
    // Edits left on this tab earlier come back as they were.
    final kept = tab.drafts?.kept<_ContractDraft>(
      YorksAccountsDraftSection.contract,
    );
    if (kept != null) {
      _restoreDraft(kept);
      _notice = _t('v2u_restored');
      tab.drafts?.drop(YorksAccountsDraftSection.contract);
    }
  }

  @override
  void didUpdateWidget(_ContractWorkspace old) {
    super.didUpdateWidget(old);
    // A fresh read from the server replaces the form, unless the person is in
    // the middle of an edit they have not saved.
    if (!identical(old.tab.setup, setup) && !_dirty && !_saving) _load();
  }

  @override
  void dispose() {
    final drafts = tab.drafts;
    if (drafts != null) {
      if (_dirty) {
        drafts.keep(YorksAccountsDraftSection.contract, _captureDraft());
      } else {
        drafts.drop(YorksAccountsDraftSection.contract);
      }
      drafts.setEditing(YorksAccountsDraftSection.contract, false);
    }
    for (final c in _fields) {
      c.dispose();
    }
    for (final b in _buildings) {
      b.dispose();
    }
    for (final s in _stages) {
      s.dispose();
    }
    super.dispose();
  }

  /// Even shares that sum to exactly 100 (any remainder goes to the last one).
  List<String> _evenShares(int count) {
    if (count == 0) return const [];
    const unitsInHundred = 1000000; // four decimal places
    final each = unitsInHundred ~/ count;
    String text(int units) => YorksAccountsDecimal.parse(
      '${units ~/ 10000}.${(units % 10000).toString().padLeft(4, '0')}',
    ).canonicalText;
    return [
      for (var i = 0; i < count; i++)
        text(i == count - 1 ? unitsInHundred - each * (count - 1) : each),
    ];
  }

  void _load() {
    final s = setup;
    _contract.text = s.contractValue?.canonicalText ?? '';
    _vat.text = s.vatRatePercent?.canonicalText ?? '5';
    _terms.text = s.paymentTermsDays?.toString() ?? '';
    _reminder.text = s.reminderLeadDays?.toString() ?? '';
    _retention.text = s.retentionPercent ?? '';
    _trn.text = s.clientTrn ?? '';
    _contact.text = s.invoiceSettings?.attentionName ?? '';
    _woNumber.text = s.workOrderNumber ?? '';
    _woDate.text = _displayDate(s.workOrderDate);
    _contractNumber.text = s.contractNumber ?? '';
    _prefix.text = s.invoiceSettings?.invoicePrefix ?? '';
    _scope.text = s.invoiceSettings?.scopeLine ?? '';
    _billTo = _billToParty(s)?.partyId;

    for (final b in _buildings) {
      b.dispose();
    }
    _buildings.clear();
    if (s.hasBaseline) {
      for (final b in s.buildings) {
        _buildings.add(
          _BuildingDraft(
            scopeId: b.projectScopeId,
            name: b.name,
            share: b.allocationPercent.canonicalText,
            onChanged: _changed,
          ),
        );
      }
    } else {
      final evens = _evenShares(widget.buildingChoices.length);
      for (final (i, o) in widget.buildingChoices.indexed) {
        _buildings.add(
          _BuildingDraft(
            scopeId: o.scopeId,
            name: o.name,
            share: evens[i],
            onChanged: _changed,
          ),
        );
      }
    }

    for (final st in _stages) {
      st.dispose();
    }
    _stages.clear();
    if (s.stages.isNotEmpty) {
      for (final st in s.stages) {
        _stages.add(
          _StageDraft(
            key: st.stageKey,
            label: st.stageName,
            percent: st.allocationPercent.canonicalText,
            byItems: st.isItemsMode,
            items: _itemsFor(st.stageKey),
            onChanged: _changed,
          ),
        );
      }
    } else {
      _applyTemplate();
    }
    _initial = _snapshot();
    _base = _capture();
    _baseProfileVersion = s.profileVersion;
    _baseInvoiceVersion = s.invoiceSettings?.recordVersion;
    _error = null;
    _notice = null;
    _showProblems = false;
    _prefilled = !_skipPrefill && _prefillFromProject();
  }

  // ─── Drafts, undo and newer versions ───────────────────────────────────────

  _ContractForm _capture() => _ContractForm(
    fields: [for (final c in _fields) c.text],
    billTo: _billTo,
    buildings: [
      for (final b in _buildings)
        (scopeId: b.scopeId, name: b.name, share: b.share.text),
    ],
    stages: [
      for (final st in _stages)
        _StageForm(
          key: st.key,
          label: st.label.text,
          percent: st.percent.text,
          byItems: st.byItems,
          items: [
            for (final it in st.items)
              (
                key: it.key,
                label: it.label.text,
                quantity: it.quantity.text,
                unit: it.unit.text,
                weight: it.weight.text,
              ),
          ],
        ),
    ],
  );

  /// Puts [form] in the fields, rebuilding the building and stage rows.
  void _apply(_ContractForm form) {
    for (final (i, c) in _fields.indexed) {
      if (i < form.fields.length && c.text != form.fields[i]) {
        c.text = form.fields[i];
      }
    }
    _billTo = form.billTo;
    for (final b in _buildings) {
      b.dispose();
    }
    _buildings
      ..clear()
      ..addAll([
        for (final b in form.buildings)
          _BuildingDraft(
            scopeId: b.scopeId,
            name: b.name,
            share: b.share,
            onChanged: _changed,
          ),
      ]);
    for (final st in _stages) {
      st.dispose();
    }
    _stages
      ..clear()
      ..addAll([
        for (final st in form.stages)
          _StageDraft(
            key: st.key,
            label: st.label,
            percent: st.percent,
            byItems: st.byItems,
            items: [
              for (final it in st.items)
                _ItemRowDraft(
                  key: it.key,
                  label: it.label,
                  quantity: it.quantity,
                  unit: it.unit,
                  weight: it.weight,
                  onChanged: _changed,
                ),
            ],
            onChanged: _changed,
          ),
      ]);
  }

  _ContractDraft _captureDraft() => _ContractDraft(
    form: _capture(),
    base: _base,
    initial: _initial,
    baseProfileVersion: _baseProfileVersion,
    baseInvoiceVersion: _baseInvoiceVersion,
    prefilled: _prefilled,
    skipPrefill: _skipPrefill,
    nextKey: _nextKey,
  );

  void _restoreDraft(_ContractDraft d) {
    _apply(d.form);
    _base = d.base;
    _initial = d.initial;
    _baseProfileVersion = d.baseProfileVersion;
    _baseInvoiceVersion = d.baseInvoiceVersion;
    _prefilled = d.prefilled;
    _skipPrefill = d.skipPrefill;
    _nextKey = d.nextKey;
    _error = null;
    _notice = null;
  }

  /// Makes a one-click change and offers to take it back.
  void _undoable(String messageKey, VoidCallback change) {
    final before = _captureDraft();
    setState(change);
    _offerUndo(_t(messageKey), before);
  }

  void _offerUndo(String message, _ContractDraft before) {
    showAccountsV2Undo(
      context,
      language: tab.language,
      message: message,
      onUndo: () {
        if (mounted) setState(() => _restoreDraft(before));
      },
    );
  }

  /// Someone else saved after these edits began: Save would be refused, so the
  /// bar offers to move the edits onto the newer version or take that version.
  bool get _stale {
    if (_saving || !_dirty) return false;
    final profileMoved = setup.profileVersion != _baseProfileVersion;
    final invoiceMoved =
        setup.invoiceSettings?.recordVersion != _baseInvoiceVersion;
    return ((_setupDirty || _referencesDirty) && profileMoved) ||
        (_invoiceDirty && invoiceMoved);
  }

  static const _setupFields = {0, 1, 2, 3};
  static const _referenceFields = {4, 5, 7, 8, 9};

  String _partOfField(int index) => _setupFields.contains(index)
      ? 'v2c_part_details'
      : _referenceFields.contains(index)
      ? 'v2c_part_references'
      : 'v2c_part_invoice';

  /// Loads the newer saved version and puts back every field this person
  /// changed. Fields both people changed keep this person's value and are
  /// named, so they can be checked before saving.
  void _keepMineOnLatest() {
    final before = _captureDraft();
    final mine = before.form;
    final base = before.base ?? mine;
    setState(() {
      _skipPrefill = true;
      _load();
      final theirs = _capture();
      final overlaps = <String>{};
      bool changed(String m, String b) => m != b;
      final fields = [...theirs.fields];
      for (var i = 0; i < fields.length && i < mine.fields.length; i++) {
        if (!changed(mine.fields[i], base.fields[i])) continue;
        if (theirs.fields[i] != base.fields[i] &&
            theirs.fields[i] != mine.fields[i]) {
          overlaps.add(_partOfField(i));
        }
        fields[i] = mine.fields[i];
      }
      var billTo = theirs.billTo;
      if (mine.billTo != base.billTo) {
        if (theirs.billTo != base.billTo && theirs.billTo != mine.billTo) {
          overlaps.add('v2c_part_invoice');
        }
        billTo = mine.billTo;
      }
      var buildings = theirs.buildings;
      if (mine.buildingsSignature != base.buildingsSignature) {
        if (theirs.buildingsSignature != base.buildingsSignature &&
            theirs.buildingsSignature != mine.buildingsSignature) {
          overlaps.add('v2c_part_buildings');
        }
        buildings = mine.buildings;
      }
      var stages = theirs.stages;
      if (mine.stagesSignature != base.stagesSignature) {
        if (theirs.stagesSignature != base.stagesSignature &&
            theirs.stagesSignature != mine.stagesSignature) {
          overlaps.add('v2c_part_stages');
        }
        stages = mine.stages;
      }
      _apply(
        _ContractForm(
          fields: fields,
          billTo: billTo,
          buildings: buildings,
          stages: stages,
        ),
      );
      _notice = overlaps.isEmpty
          ? _t('v2c_merged')
          : _t(
              'v2c_merged_overlap',
            ).replaceAll('{parts}', overlaps.map(_t).join(', '));
    });
    _offerUndo(_t('v2c_merged'), before);
  }

  /// Replaces these edits with the newer saved version (Undo brings them back).
  void _takeTheirs() {
    final before = _captureDraft();
    setState(() {
      _skipPrefill = true;
      _load();
    });
    _offerUndo(_t('v2c_theirs_loaded'), before);
  }

  /// Starts empty fields from what was entered when the project was created:
  /// contract no. from its job/contract reference, the invoice contact from the
  /// client, the invoice prefix from the project code and the scope line from
  /// the project name. Only fields this person may edit, and only as unsaved
  /// changes: nothing is kept until Save. Returns whether anything was filled.
  bool _prefillFromProject() {
    final s = setup;
    var filled = false;
    void fill(TextEditingController c, String? value) {
      final v = value?.trim() ?? '';
      if (c.text.trim().isNotEmpty || v.isEmpty) return;
      c.text = v;
      filled = true;
    }

    if (_canEditReferences) fill(_contractNumber, s.jobContractReference);
    if (_canEditInvoice) {
      final party = s.clientParty ?? s.mainContractorParty;
      fill(_contact, party?.contactName);
      fill(
        _prefix,
        s.projectReference?.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), ''),
      );
      fill(_scope, s.projectName);
    }
    return filled;
  }

  /// One building's list stands for all (the server stores one per building).
  List<_ItemRowDraft> _itemsFor(String stageKey) {
    final all = setup.itemsForStage(stageKey);
    if (all.isEmpty) return [];
    final scope = all.first.projectScopeId;
    return [
      for (final it in all.where((i) => i.projectScopeId == scope))
        _ItemRowDraft(
          key: it.itemKey,
          label: it.itemLabel,
          quantity: it.quantity.canonicalText,
          unit: it.unitCode,
          weight: it.weightPercentOfContract.canonicalText,
          onChanged: _changed,
        ),
    ];
  }

  void _applyTemplate() {
    final previous = {for (final s in _stages) s.key: s};
    _stages.clear();
    for (final option in tab.stageOptions) {
      final old = previous.remove(option.key);
      if (old != null) {
        old.percent.text = option.percent.canonicalText;
        _stages.add(old);
      } else {
        _stages.add(
          _StageDraft(
            key: option.key,
            label: option.label,
            percent: option.percent.canonicalText,
            byItems: false,
            items: [],
            onChanged: _changed,
          ),
        );
      }
    }
    for (final dropped in previous.values) {
      dropped.dispose();
    }
  }

  // ─── Dates ─────────────────────────────────────────────────────────────────

  /// `2025-08-13` → `13 Aug 2025`, as every Accounts screen shows a date.
  static String _displayDate(String? iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso ?? '');
    if (m == null) return iso ?? '';
    return v2Date(iso);
  }

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// `13 Aug 2025`, `13/08/2025` or `2025-08-13` → `2025-08-13`; null when
  /// not a date.
  static String? _isoDate(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(t);
    if (iso != null) return t;
    final named = RegExp(r'^(\d{1,2}) ([A-Za-z]{3}) (\d{4})$').firstMatch(t);
    if (named != null) {
      final month = _months.indexOf(named.group(2)!.toLowerCase()) + 1;
      if (month == 0) return null;
      return '${named.group(3)}-${month.toString().padLeft(2, '0')}-'
          '${named.group(1)!.padLeft(2, '0')}';
    }
    final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
    if (dmy == null) return null;
    return '${dmy.group(3)}-${dmy.group(2)!.padLeft(2, '0')}-'
        '${dmy.group(1)!.padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_isoDate(_woDate.text) ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _woDate.text = v2Date(picked);
  }

  // ─── Model and changes ─────────────────────────────────────────────────────

  YorksAccountsDecimal _dec(TextEditingController c) =>
      YorksAccountsDecimal.tryParse(c.text.trim()) ?? YorksAccountsDecimal.zero;

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  YorksAccountsCommercialSetup _model() => YorksAccountsCommercialSetup(
    contractValue: _dec(_contract),
    currencyCode: setup.currencyCode ?? 'AED',
    vatRatePercent: _dec(_vat),
    paymentTermsDays: int.tryParse(_terms.text.trim()),
    reminderLeadDays: int.tryParse(_reminder.text.trim()),
    buildings: [
      for (final b in _buildings)
        if (_dec(b.share).isPositive)
          YorksAccountsSetupBuilding(
            buildingScopeId: b.scopeId,
            allocationPercent: _dec(b.share),
          ),
    ],
    stages: [
      for (final (i, st) in _stages.indexed)
        YorksAccountsSetupStage(
          stageKey: st.key,
          stageLabel: st.label.text.trim(),
          allocationPercent: _dec(st.percent),
          position: i + 1,
          measurementMode: st.byItems ? 'items' : 'percent',
          items: [
            if (st.byItems)
              for (final (order, it) in st.items.indexed)
                YorksAccountsSetupItem(
                  itemKey: it.key,
                  itemLabel: it.label.text.trim(),
                  displayOrder: order + 1,
                  quantity: _dec(it.quantity),
                  unitCode: it.unit.text.trim(),
                  weightPercentOfContract: _dec(it.weight),
                ),
          ],
        ),
    ],
  );

  String get _setupSnapshot => '${_model().toSetupJson()}';
  String get _referencesSnapshot =>
      '${_retention.text.trim()}|${_trn.text.trim()}|${_woNumber.text.trim()}|'
      '${_isoDate(_woDate.text) ?? _woDate.text.trim()}|'
      '${_contractNumber.text.trim()}';
  String get _invoiceSnapshot =>
      '${_prefix.text.trim()}|${_scope.text.trim()}|${_contact.text.trim()}|'
      '${_billTo ?? ''}';

  /// The party being billed: the one chosen in the invoice settings, else the
  /// main contractor (a subcontractor bills the main contractor), else the
  /// client.
  YorksAccountsSetupReadParty? _billToParty(
    YorksAccountsCommercialSetupRead s,
  ) {
    final chosen = s.invoiceSettings?.billToPartyId;
    for (final p in [s.mainContractorParty, s.clientParty]) {
      if (p != null && chosen != null && p.partyId == chosen) return p;
    }
    return s.mainContractorParty ?? s.clientParty;
  }

  String? _billTo;

  String _snapshot() =>
      '$_setupSnapshot§$_referencesSnapshot§$_invoiceSnapshot';

  bool get _dirty => _snapshot() != _initial;

  List<String> get _initialParts => _initial.split('§');

  bool get _setupDirty =>
      _initialParts.isEmpty || _setupSnapshot != _initialParts[0];
  bool get _referencesDirty =>
      _initialParts.length < 2 || _referencesSnapshot != _initialParts[1];
  bool get _invoiceDirty =>
      _initialParts.length < 3 || _invoiceSnapshot != _initialParts[2];

  bool get _canEditReferences => tab.canEdit && tab.onSaveReferences != null;
  bool get _canEditInvoice =>
      tab.canManageInvoices && tab.onSaveInvoiceSettings != null;

  List<AccountsV2SetupCheck> get _checks => accountsV2SetupChecksFrom(
    contract: _num(_contract),
    buildings: [
      for (final b in _buildings) (id: b.scopeId, share: _num(b.share)),
    ],
    stages: [
      for (final st in _stages)
        (
          key: st.key,
          name: st.label.text.trim(),
          percent: _num(st.percent),
          byItems: st.byItems,
          weights: {
            null: [for (final it in st.items) _num(it.weight)],
          },
        ),
    ],
  );

  /// Every reason the current changes cannot be saved yet, in the order
  /// they appear on the page. Save stays pressable; pressing it with any of
  /// these left outlines the fields and moves to the first one, instead of a
  /// greyed-out button that never says why.
  List<_SaveBlocker> get _blockers {
    final out = <_SaveBlocker>[];
    if (_setupDirty) {
      if (!widget.canEditSetup) {
        out.add(_SaveBlocker(_t('v2c_block_no_setup_access')));
      } else {
        final vat = YorksAccountsDecimal.tryParse(_vat.text.trim());
        if (vat == null || vat.isNegative) {
          out.add(
            _SaveBlocker(_t('v2c_block_vat'), _detailsKey, _ProblemField.vat),
          );
        }
        final noBuildings = _buildings.isEmpty;
        if (noBuildings) {
          out.add(
            _SaveBlocker(
              widget.buildingChoices.isEmpty
                  ? _t('v2c_block_project_has_no_buildings')
                  : _t('v2c_block_add_building'),
              _buildingsKey,
            ),
          );
        }
        for (final c in _checks.where((c) => !c.ok)) {
          if (noBuildings && c.kind == AccountsV2SetupCheckKind.buildings) {
            continue;
          }
          out.add(
            _SaveBlocker(
              '${accountsV2SetupCheckTitle(tab.language, c)} — '
              '${accountsV2SetupCheckDetail(tab.language, c)}',
              switch (c.kind) {
                AccountsV2SetupCheckKind.contractValue => _detailsKey,
                AccountsV2SetupCheckKind.buildings => _buildingsKey,
                AccountsV2SetupCheckKind.stages => _stagesKey,
                AccountsV2SetupCheckKind.items =>
                  _itemKeys[c.stageKey] ?? _stagesKey,
              },
              c.kind == AccountsV2SetupCheckKind.contractValue
                  ? _ProblemField.contract
                  : null,
            ),
          );
        }
        if (_stages.any((s) => s.label.text.trim().isEmpty)) {
          out.add(_SaveBlocker(_t('v2c_block_stage_name'), _stagesKey));
        }
        for (final st in _stages.where((s) => s.byItems)) {
          if (st.items.isNotEmpty && !st.items.every((i) => i.isValid)) {
            out.add(
              _SaveBlocker(
                '${st.label.text.trim()}: ${_t('v2c_block_item_rows')}',
                _itemKeys[st.key] ?? _stagesKey,
              ),
            );
          }
        }
        if (out.isEmpty && !_model().isValid) {
          out.add(_SaveBlocker(_t('v2c_block_setup_invalid'), _detailsKey));
        }
      }
    }
    if (_referencesDirty && !_canEditReferences) {
      out.add(_SaveBlocker(_t('v2c_block_no_reference_access')));
    }
    if (_invoiceDirty) {
      if (!_canEditInvoice) {
        out.add(_SaveBlocker(_t('v2c_block_no_invoice_access')));
      } else if (_prefix.text.trim().isEmpty) {
        out.add(
          _SaveBlocker(
            _t('v2c_block_prefix'),
            _detailsKey,
            _ProblemField.prefix,
          ),
        );
      }
    }
    if (_woDate.text.trim().isNotEmpty && _isoDate(_woDate.text) == null) {
      out.add(
        _SaveBlocker(
          _t('v2c_block_wo_date'),
          _detailsKey,
          _ProblemField.woDate,
        ),
      );
    }
    return out;
  }

  bool get _canSave => !_saving && _dirty;

  bool _flag(_ProblemField field) =>
      _showProblems && _blockers.any((b) => b.field == field);

  void _reveal(_SaveBlocker blocker) {
    final target = blocker.target?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.05,
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
  }

  /// Lets the screen rebuild with the server's fresh read before the next
  /// command, so each one carries the version the server now holds.
  Future<void> _settle() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _save() async {
    final blockers = _blockers;
    if (blockers.isNotEmpty) {
      setState(() => _showProblems = true);
      _reveal(blockers.first);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final setupDirty = _setupDirty;
    final referencesDirty = _referencesDirty;
    final invoiceDirty = _invoiceDirty;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Up to three server commands, one per part. Each that succeeds is kept as
    // saved, so a later refusal names exactly what was and wasn't saved.
    final saved = <String>[];
    String? error;
    String? failedPart;
    if (setupDirty) {
      error = await tab.onSave!(_model(), _baseProfileVersion);
      if (error == null) {
        await _settle();
        saved.add('v2c_part_setup');
        _markSaved(0);
        _baseProfileVersion = widget.tab.setup.profileVersion;
      } else {
        failedPart = 'v2c_part_setup';
      }
    }
    if (error == null && referencesDirty && mounted) {
      error = await tab.onSaveReferences!(
        clientTrn: _trn.text.trim(),
        workOrderNumber: _woNumber.text.trim(),
        workOrderDate: _isoDate(_woDate.text),
        contractNumber: _contractNumber.text.trim(),
        retentionPercent: _retention.text.trim(),
        expectedProfileVersion: _baseProfileVersion,
      );
      if (error == null) {
        await _settle();
        saved.add('v2c_part_references');
        _markSaved(1);
        _baseProfileVersion = widget.tab.setup.profileVersion;
      } else {
        failedPart = 'v2c_part_references';
      }
    }
    if (error == null && invoiceDirty && mounted) {
      final settings = widget.tab.setup.invoiceSettings;
      final scope = _scope.text.trim();
      final contact = _contact.text.trim();
      error = await tab.onSaveInvoiceSettings!(
        invoicePrefix: _prefix.text.trim(),
        scopeLine: scope.isEmpty ? null : scope,
        attentionName: contact.isEmpty ? null : contact,
        billToPartyId: _billTo ?? settings?.billToPartyId,
        expectedVersion: _baseInvoiceVersion,
      );
      if (error == null) {
        await _settle();
        saved.add('v2c_part_invoice');
        _markSaved(2);
        _baseInvoiceVersion = widget.tab.setup.invoiceSettings?.recordVersion;
      } else {
        failedPart = 'v2c_part_invoice';
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) {
        _load();
      } else if (_stale) {
        // Someone else saved meanwhile: the bar explains and offers the way on.
        _error = null;
      } else {
        final reason = accountsV2ErrorText(tab.language, error);
        _error = saved.isEmpty || failedPart == null
            ? reason
            : _t('v2c_partial_saved')
                  .replaceAll('{saved}', saved.map(_t).join(', '))
                  .replaceAll('{failed}', _t(failedPart))
                  .replaceAll('{reason}', reason);
      }
    });
    if (error == null) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_saved'))));
    }
  }

  /// Counts one part (0 setup, 1 references, 2 invoice) as saved: it no
  /// longer makes the form unsaved, and newer saved values start from it.
  void _markSaved(int part) {
    final parts = _initialParts;
    if (parts.length != 3) return;
    final now = [_setupSnapshot, _referencesSnapshot, _invoiceSnapshot];
    parts[part] = now[part];
    _initial = parts.join('§');
    final base = _base;
    if (base == null) return;
    final current = _capture();
    final fields = [...base.fields];
    for (var i = 0; i < fields.length && i < current.fields.length; i++) {
      final inPart = switch (part) {
        0 => _setupFields.contains(i),
        1 => _referenceFields.contains(i),
        _ => !_setupFields.contains(i) && !_referenceFields.contains(i),
      };
      if (inPart) fields[i] = current.fields[i];
    }
    _base = _ContractForm(
      fields: fields,
      billTo: part == 2 ? current.billTo : base.billTo,
      buildings: part == 0 ? current.buildings : base.buildings,
      stages: part == 0 ? current.stages : base.stages,
    );
  }

  void _discard() {
    final before = _captureDraft();
    setState(() {
      _skipPrefill = true;
      _load();
    });
    _offerUndo(_t('v2u_discarded'), before);
  }

  // ─── Building, stage and item edits ────────────────────────────────────────

  void _splitEqually() => _undoable('v2u_split_equal', () {
    final shares = _evenShares(_buildings.length);
    for (final (i, b) in _buildings.indexed) {
      b.share.text = shares[i];
    }
  });

  List<YorksContractBuildingOption> get _unusedBuildings => [
    for (final o in widget.buildingChoices)
      if (!_buildings.any((b) => b.scopeId == o.scopeId)) o,
  ];

  void _addBuilding(YorksContractBuildingOption option) {
    setState(() {
      _buildings.add(
        _BuildingDraft(
          scopeId: option.scopeId,
          name: option.name,
          share: '0',
          onChanged: _changed,
        ),
      );
    });
  }

  void _removeBuilding(_BuildingDraft b) =>
      _undoable('v2u_removed_building', () {
        _buildings.remove(b);
        b.dispose();
      });

  void _addStage() {
    var n = _nextKey++;
    while (_stages.any((s) => s.key == 'custom_$n')) {
      n = _nextKey++;
    }
    setState(() {
      _stages.add(
        _StageDraft(
          key: 'custom_$n',
          label: '',
          percent: '0',
          byItems: false,
          items: [],
          onChanged: _changed,
        ),
      );
    });
  }

  void _removeStage(_StageDraft st) => _undoable('v2u_removed_stage', () {
    _stages.remove(st);
    st.dispose();
  });

  void _addItem(_StageDraft st) {
    var n = st.items.length + 1;
    while (st.items.any((i) => i.key == 'item-$n')) {
      n++;
    }
    setState(() {
      st.items.add(
        _ItemRowDraft(
          key: 'item-$n',
          label: '',
          quantity: '1',
          unit: 'Nos',
          weight: '0',
          onChanged: _changed,
        ),
      );
    });
  }

  void _removeItem(_StageDraft st, _ItemRowDraft it) =>
      _undoable('v2u_removed_item', () {
        st.items.remove(it);
        it.dispose();
      });

  /// Copies another item stage's list into [target], keeping the item names,
  /// quantities and units; weights stay as they are on rows already present.
  void _copyItems(_StageDraft from, _StageDraft target) {
    _undoable('v2u_items_copied', () {
      for (final it in target.items) {
        it.dispose();
      }
      target.items
        ..clear()
        ..addAll([
          for (final (i, it) in from.items.indexed)
            _ItemRowDraft(
              key: 'item-${i + 1}',
              label: it.label.text,
              quantity: it.quantity.text,
              unit: it.unit.text,
              weight: it.weight.text,
              onChanged: _changed,
            ),
        ]);
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The tab bar marks Contract while it has unsaved edits (reported after the
    // frame, so no other widget rebuilds mid-build).
    tab.drafts?.setEditing(YorksAccountsDraftSection.contract, _dirty);
    final editable = widget.canEditSetup;
    final main = AccountsV2Stack(
      children: [
        KeyedSubtree(key: _detailsKey, child: _detailsCard()),
        KeyedSubtree(key: _buildingsKey, child: _buildingsCard(editable)),
        KeyedSubtree(key: _stagesKey, child: _stagesCard(editable)),
        for (final st in _stages) ...[
          if (st.byItems)
            KeyedSubtree(
              key: _itemKeys.putIfAbsent(st.key, GlobalKey.new),
              child: _itemsCard(st, editable && !widget.itemsBlocked),
            ),
          ?_linksCardFor(st.key),
        ],
        AccountsV2VariationsCard(
          variations: tab.variations,
          canConfigure: tab.canEdit,
          language: tab.language,
          format: const AccountsV2Format(),
          onSave: tab.onSaveVariation,
        ),
      ],
    );
    final side = AccountsV2Stack(children: [_setupPanel(), _howCard()]);
    return AccountsV2Stack(
      children: [
        if (tab.canEdit)
          AccountsV2Note(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${_t('v2c_edit_note_a')} '),
                  TextSpan(
                    text: _t('v2c_edit_note_b'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' ${_t('v2c_edit_note_c')}'),
                ],
              ),
            ),
          ),
        if (widget.itemsBlocked)
          AccountsV2Note(
            tone: AccountsV2NoteTone.warn,
            child: Text(_t('v2_items_vary_note')),
          ),
        if (_stale)
          _staleBar()
        else if ((_dirty || _error != null) && _needsExplaining)
          _saveBar(),
        _kpis(),
        AccountsV2Split(main: main, side: side),
        // Discard and Save stay in reach at the bottom of the screen while
        // anything is unsaved, however far down the form the person is.
        if (!_stale && (_dirty || _error != null))
          AccountsV2BottomBar(child: _actionBar()),
      ],
    );
  }

  /// Whether the note above the form has something to say beyond "unsaved"
  /// (the bottom bar already says that).
  bool get _needsExplaining =>
      _error != null ||
      _notice != null ||
      _prefilled ||
      (_dirty && _blockers.isNotEmpty);

  /// The bar at the bottom: what state the form is in, Discard and Save.
  Widget _actionBar() {
    final blockers = _dirty ? _blockers : const <_SaveBlocker>[];
    final phone = AccountsV2Breakpoints.isPhone(context);
    final status = Text(
      _error != null
          ? _t('v2c_bar_failed')
          : blockers.isEmpty
          ? _t('v2c_bar_unsaved')
          : _t('v2c_bar_to_fix').replaceAll('{n}', '${blockers.length}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: v2Style(
        13,
        weight: FontWeight.w600,
        color: _error != null || (_showProblems && blockers.isNotEmpty)
            ? AccountsV2Colors.bad
            : AccountsV2Colors.ink2,
      ),
    );
    final discard = AccountsV2Button(
      label: _t('v2c_discard'),
      size: AccountsV2ButtonSize.small,
      block: phone,
      onPressed: _saving ? null : _discard,
    );
    final save = AccountsV2Button(
      label: _saving ? _t('v2c_saving') : _t('v2c_save_changes'),
      icon: 'check',
      kind: AccountsV2ButtonKind.primary,
      size: AccountsV2ButtonSize.small,
      block: phone,
      onPressed: _canSave ? _save : null,
    );
    return KeyedSubtree(
      key: const ValueKey('accounts-v2-contract-save-bar'),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                status,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: discard),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: save),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 12),
                discard,
                const SizedBox(width: 8),
                save,
              ],
            ),
    );
  }

  Widget _staleBar() => AccountsV2Note(
    key: const ValueKey('accounts-v2-contract-stale-bar'),
    tone: AccountsV2NoteTone.bad,
    trailing: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        AccountsV2Button(
          label: _t('v2c_stale_theirs'),
          size: AccountsV2ButtonSize.small,
          onPressed: _takeTheirs,
        ),
        AccountsV2Button(
          key: const ValueKey('accounts-v2-contract-keep-mine'),
          label: _t('v2c_stale_merge'),
          kind: AccountsV2ButtonKind.primary,
          size: AccountsV2ButtonSize.small,
          onPressed: _keepMineOnLatest,
        ),
      ],
    ),
    child: Text(_t('v2c_stale')),
  );

  Widget _saveBar() {
    final blockers = _blockers;
    final failing = _error != null || (_showProblems && blockers.isNotEmpty);
    final intro =
        _error ??
        (_notice != null ? '$_notice ' : '') +
            (_prefilled ? '${_t('v2c_prefilled')} ' : '') +
            _t('v2c_unsaved');
    return AccountsV2Note(
      key: const ValueKey('accounts-v2-contract-note'),
      tone: failing ? AccountsV2NoteTone.bad : AccountsV2NoteTone.warn,
      child: blockers.isEmpty
          ? Text(intro)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intro),
                const SizedBox(height: 6),
                Text(
                  _t('v2c_block_intro').replaceAll('{n}', '${blockers.length}'),
                  key: const ValueKey('accounts-v2-contract-blockers'),
                  style: v2Style(13, weight: FontWeight.w700),
                ),
                for (final b in blockers)
                  _BlockerLine(
                    text: b.text,
                    onTap: b.target == null ? null : () => _reveal(b),
                  ),
              ],
            ),
    );
  }

  Widget _kpis() {
    final checks = _checks;
    final bad = checks.where((c) => !c.ok).length;
    final contract = _num(_contract);
    final vat = _num(_vat);
    final shares = _buildings.fold<double>(0, (a, b) => a + _num(b.share));
    final stageTotal = _stages.fold<double>(0, (a, s) => a + _num(s.percent));
    final itemStages = _stages.where((s) => s.byItems).toList();
    final itemCount = itemStages.fold<int>(0, (n, s) => n + s.items.length);
    return AccountsV2KpiRow(
      children: [
        AccountsV2KpiCard(
          icon: 'doc',
          label: _t('v2_kpi_contract'),
          value: v2Money(contract),
          caption:
              '${_t('v2o_excl_vat')} · '
              '${v2Money(contract * (1 + vat / 100))} '
              '${_t('v2o_with_vat')}',
        ),
        AccountsV2KpiCard(
          icon: 'bldg',
          label: _t('v2o_physical_buildings'),
          value: '${_buildings.length}',
          caption: '${_t('v2c_shares_total')} ${v2Pct(shares, 2)}',
          valueTone: (shares - 100).abs() < 0.005
              ? AccountsV2ValueTone.plain
              : AccountsV2ValueTone.bad,
        ),
        AccountsV2KpiCard(
          icon: 'chart',
          tone: AccountsV2Tone.vio,
          label: _t('v2_stages_title'),
          value: '${_stages.length}',
          caption: _stages.isEmpty
              ? '—'
              : _stages.map((s) => v2Pct(_num(s.percent), 0)).join(' / '),
          valueTone: (stageTotal - 100).abs() < 0.005
              ? AccountsV2ValueTone.plain
              : AccountsV2ValueTone.bad,
        ),
        AccountsV2KpiCard(
          icon: 'list',
          label: _t('v2c_item_breakdown'),
          value: '$itemCount ${_t('v2c_items_lower')}',
          caption: itemStages.isEmpty
              ? _t('v2c_no_item_stages')
              : itemStages.map((s) => s.label.text.trim()).join(' · '),
        ),
        AccountsV2KpiCard(
          icon: bad > 0 ? 'alert' : 'check',
          tone: bad > 0 ? AccountsV2Tone.red : AccountsV2Tone.green,
          label: _t('v2c_setup_check'),
          value: bad > 0 ? '$bad ${_t('v2c_to_fix')}' : _t('v2c_ready'),
          caption: bad > 0
              ? _t('v2c_fix_before_claim')
              : '${_t('v2c_all')} ${checks.length} ${_t('v2c_checks_passed')}',
          valueTone: bad > 0 ? AccountsV2ValueTone.bad : AccountsV2ValueTone.ok,
        ),
      ],
    );
  }

  // ─── Contract details ──────────────────────────────────────────────────────

  Widget _detailsCard() {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final compact = AccountsV2Breakpoints.isCompact(context);
    final columns = phone ? 1 : (compact ? 2 : 3);
    final setupOn = widget.canEditSetup;
    final refsOn = _canEditReferences;
    final invoiceOn = _canEditInvoice;
    Widget field(
      String label,
      TextEditingController c, {
      bool numeric = false,
      bool enabled = true,
      Widget? suffix,
      _ProblemField? problem,
    }) => AccountsV2TextField(
      label: label,
      controller: c,
      numeric: numeric,
      size: AccountsV2FieldSize.large,
      enabled: enabled,
      suffix: suffix,
      error: problem != null && _flag(problem),
    );
    // Who the invoices are addressed to: chosen from the project's client and
    // main contractor by someone who manages invoices; read-only otherwise.
    final parties = [
      if (setup.mainContractorParty?.partyId != null)
        (setup.mainContractorParty!, _t('v2c_party_main_contractor')),
      if (setup.clientParty?.partyId != null)
        (setup.clientParty!, _t('v2c_party_client')),
    ];
    final client =
        parties
            .where((p) => p.$1.partyId == _billTo)
            .map((p) => p.$1)
            .firstOrNull ??
        _billToParty(setup);
    final fields = <Widget>[
      field(
        _t('v2c_contract_value'),
        _contract,
        numeric: true,
        enabled: setupOn,
        problem: _ProblemField.contract,
      ),
      field(
        _t('v2c_vat_pct'),
        _vat,
        numeric: true,
        enabled: setupOn,
        problem: _ProblemField.vat,
      ),
      field(_t('v2c_terms_days'), _terms, numeric: true, enabled: setupOn),
      field(
        _t('v2c_retention_pct'),
        _retention,
        numeric: true,
        enabled: refsOn,
      ),
      if (invoiceOn && parties.length > 1)
        AccountsV2Select<String>(
          label: _t('v2c_client'),
          value: _billTo ?? parties.first.$1.partyId!,
          options: [
            for (final (party, kind) in parties)
              (party.partyId!, '${party.name ?? ''} ($kind)'),
          ],
          onChanged: (v) => setState(() => _billTo = v),
        )
      else
        _ReadOnlyField(label: _t('v2c_client'), value: client?.name ?? ''),
      _ReadOnlyField(
        label: _t('v2c_client_address'),
        value: client?.address ?? '',
      ),
      field(_t('v2c_client_trn'), _trn, enabled: refsOn),
      field(_t('v2c_client_contact'), _contact, enabled: invoiceOn),
      field(_t('v2c_wo_number'), _woNumber, enabled: refsOn),
      // Chosen from a calendar and shown like every other date; never typed.
      AccountsV2TextField(
        label: _t('v2c_wo_date'),
        controller: _woDate,
        size: AccountsV2FieldSize.large,
        enabled: refsOn,
        readOnly: true,
        onTap: refsOn ? _pickDate : null,
        error: _flag(_ProblemField.woDate),
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refsOn && _woDate.text.trim().isNotEmpty)
              IconButton(
                tooltip: _t('v2b_clear_date'),
                onPressed: () => _woDate.clear(),
                icon: const Icon(Icons.close, size: 18),
                color: AccountsV2Colors.mut,
              ),
            IconButton(
              tooltip: _t('v2_pick_date'),
              onPressed: refsOn ? _pickDate : null,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              color: AccountsV2Colors.ink,
            ),
          ],
        ),
      ),
      field(_t('v2c_contract_no'), _contractNumber, enabled: refsOn),
      field(
        _t('v2c_invoice_prefix'),
        _prefix,
        enabled: invoiceOn,
        problem: _ProblemField.prefix,
      ),
    ];
    final rows = <Widget>[
      for (var i = 0; i < fields.length; i += columns)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: 14),
              Expanded(
                child: i + c < fields.length
                    ? fields[i + c]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      field(_t('v2c_scope_line'), _scope, enabled: invoiceOn),
    ];
    final next =
        setup.invoiceSettings?.nextInvoiceNumber ?? '${_prefix.text.trim()}01';
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'doc',
            title: _t('v2c_details_title'),
            subtitle: _t('v2c_details_sub'),
          ),
          AccountsV2CardBody(
            top: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const SizedBox(height: 18),
                  row,
                ],
                const SizedBox(height: 16),
                _HowLine(
                  children: [
                    ('${_t('v2c_contract_incl_vat')} ', false),
                    (v2Money(_num(_contract) * (1 + _num(_vat) / 100)), true),
                    ('  ·  ${_t('v2c_due_date_rule')} ', false),
                    ('${_terms.text.trim()} ${_t('v2o_days')}', true),
                    ('  ·  ${_t('v2o_next_invoice')} ', false),
                    (next, true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Buildings ─────────────────────────────────────────────────────────────

  Widget _buildingsCard(bool editable) {
    final contract = _num(_contract);
    final total = _buildings.fold<double>(0, (a, b) => a + _num(b.share));
    final unused = _unusedBuildings;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'bldg',
            title: _t('v2_buildings_title'),
            subtitle: _t('v2c_buildings_sub'),
            actions: editable
                ? [
                    AccountsV2Button(
                      label: _t('v2c_split_equally'),
                      size: AccountsV2ButtonSize.small,
                      onPressed: _buildings.isEmpty ? null : _splitEqually,
                    ),
                    _AddMenu<YorksContractBuildingOption>(
                      label: _t('v2c_add_building'),
                      options: [for (final o in unused) (o, o.name)],
                      onSelected: _addBuilding,
                    ),
                  ]
                : const [],
          ),
          if (_buildings.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: AccountsV2Note(
                key: const ValueKey('accounts-v2-contract-no-buildings'),
                tone: AccountsV2NoteTone.warn,
                child: Text(
                  widget.buildingChoices.isEmpty
                      ? _t('v2c_block_project_has_no_buildings')
                      : _t('v2c_block_add_building'),
                ),
              ),
            ),
          AccountsV2Table(
            phoneCards: true,
            columns: [
              AccountsV2Column(_t('v2c_building')),
              AccountsV2Column(_t('v2c_share_pct'), width: 120, numeric: true),
              AccountsV2Column(_t('v2c_value_excl'), width: 170, numeric: true),
              const AccountsV2Column('', width: 52, numeric: true),
            ],
            rows: [
              for (final b in _buildings)
                AccountsV2Row([
                  _NameCell(b.name),
                  AccountsV2CellInput(
                    controller: b.share,
                    numeric: true,
                    enabled: editable,
                  ),
                  Text(
                    v2Money(contract * _num(b.share) / 100),
                    style: v2Style(12.5, tabular: true),
                  ),
                  editable
                      ? _RemoveButton(
                          tooltip: _t('v2_remove'),
                          onPressed: () => _removeBuilding(b),
                        )
                      : const SizedBox.shrink(),
                ]),
            ],
            footer: [
              Text(_t('v2c_total')),
              _TotalPercent(total),
              Text(
                v2Money(contract * total / 100),
                style: v2Style(12.5, weight: FontWeight.w700, tabular: true),
              ),
              const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Billing stages ────────────────────────────────────────────────────────

  Widget _stagesCard(bool editable) {
    final contract = _num(_contract);
    final total = _stages.fold<double>(0, (a, s) => a + _num(s.percent));
    final standard = tab.stageOptions
        .map((o) => v2Fmt(v2Number(o.percent.canonicalText), 0))
        .join('/');
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'chart',
            tone: AccountsV2Tone.vio,
            title: _t('v2_stages_title'),
            subtitle: _t('v2c_stages_sub'),
            actions: editable
                ? [
                    if (tab.stageOptions.isNotEmpty)
                      AccountsV2Button(
                        label: '${_t('v2c_yorks_standard')} $standard',
                        size: AccountsV2ButtonSize.small,
                        onPressed: () => setState(_applyTemplate),
                      ),
                    AccountsV2Button(
                      label: _t('v2c_add_stage'),
                      icon: 'plus',
                      kind: AccountsV2ButtonKind.primary,
                      size: AccountsV2ButtonSize.small,
                      onPressed: _addStage,
                    ),
                  ]
                : const [],
          ),
          AccountsV2Table(
            phoneCards: true,
            columns: [
              AccountsV2Column(_t('v2c_stage')),
              AccountsV2Column(
                _t('v2c_pct_contract'),
                width: 120,
                numeric: true,
              ),
              AccountsV2Column(_t('v2c_measured_by'), width: 210),
              AccountsV2Column(_t('v2c_value'), width: 170, numeric: true),
              const AccountsV2Column('', width: 52, numeric: true),
            ],
            rows: [
              for (final st in _stages)
                AccountsV2Row([
                  AccountsV2CellInput(controller: st.label, enabled: editable),
                  AccountsV2CellInput(
                    controller: st.percent,
                    numeric: true,
                    enabled: editable,
                  ),
                  _ModeSelect(
                    byItems: st.byItems,
                    enabled: editable,
                    language: tab.language,
                    onChanged: (v) => setState(() => st.byItems = v),
                  ),
                  Text(
                    v2Money(contract * _num(st.percent) / 100),
                    style: v2Style(12.5, tabular: true),
                  ),
                  editable && _stages.length > 1
                      ? _RemoveButton(
                          tooltip: _t('v2_remove'),
                          onPressed: () => _removeStage(st),
                        )
                      : const SizedBox.shrink(),
                ]),
            ],
            footer: [
              Text(_t('v2c_total')),
              _TotalPercent(total),
              const SizedBox.shrink(),
              Text(
                v2Money(contract * total / 100),
                style: v2Style(12.5, weight: FontWeight.w700, tabular: true),
              ),
              const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Item breakdown ────────────────────────────────────────────────────────

  Widget _itemsCard(_StageDraft st, bool editable) {
    final contract = _num(_contract);
    final others = [
      for (final s in _stages)
        if (s.byItems && s != st && s.items.isNotEmpty) s,
    ];
    final weight = st.items.fold<double>(0, (a, i) => a + _num(i.weight));
    final value = st.items.fold<double>(
      0,
      (a, i) => a + contract * _num(i.weight) / 100,
    );
    final check = _checks.where((c) => c.stageKey == st.key).firstOrNull;
    final firstShare = _buildings.isEmpty ? 0.0 : _num(_buildings.first.share);
    final stageValue = contract * firstShare / 100 * _num(st.percent) / 100;
    final name = st.label.text.trim();
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: 'list',
            title: '$name — ${_t('v2c_item_breakdown_lower')}',
            subtitle: _t('v2c_items_sub'),
            actions: editable
                ? [
                    _AddMenu<_StageDraft>(
                      label: _t('v2c_copy_list'),
                      icon: 'copy',
                      primary: false,
                      options: [
                        for (final o in others) (o, o.label.text.trim()),
                      ],
                      onSelected: (from) => _copyItems(from, st),
                    ),
                    AccountsV2Button(
                      label: _t('v2_item_add'),
                      icon: 'plus',
                      kind: AccountsV2ButtonKind.primary,
                      size: AccountsV2ButtonSize.small,
                      onPressed: () => _addItem(st),
                    ),
                  ]
                : const [],
          ),
          AccountsV2Table(
            phoneCards: true,
            columns: [
              const AccountsV2Column('#', width: 44, center: true),
              AccountsV2Column(_t('v2c_item')),
              AccountsV2Column(_t('v2_qty_label'), width: 84, numeric: true),
              AccountsV2Column(_t('v2_unit_label'), width: 80),
              AccountsV2Column(_t('v2c_weight_pct'), width: 100, numeric: true),
              AccountsV2Column(
                _t('v2c_value_per_building'),
                width: 150,
                numeric: true,
              ),
              const AccountsV2Column('', width: 52, numeric: true),
            ],
            rows: [
              for (final (i, it) in st.items.indexed)
                AccountsV2Row([
                  Text(
                    '${i + 1}',
                    style: v2Style(12.5, color: AccountsV2Colors.mut),
                  ),
                  AccountsV2CellInput(controller: it.label, enabled: editable),
                  AccountsV2CellInput(
                    controller: it.quantity,
                    numeric: true,
                    enabled: editable,
                  ),
                  AccountsV2CellInput(controller: it.unit, enabled: editable),
                  AccountsV2CellInput(
                    controller: it.weight,
                    numeric: true,
                    enabled: editable,
                  ),
                  _ItemValue(
                    value: contract * _num(it.weight) / 100,
                    quantity: _num(it.quantity),
                    unit: it.unit.text.trim(),
                  ),
                  editable
                      ? _RemoveButton(
                          tooltip: _t('v2_remove'),
                          onPressed: () => _removeItem(st, it),
                        )
                      : const SizedBox.shrink(),
                ]),
            ],
            emptyRow: AccountsV2Empty(
              icon: 'list',
              title: _t('v2c_no_items'),
              body: _t('v2c_no_items_body'),
            ),
            footer: [
              const SizedBox.shrink(),
              Text(_t('v2c_total_one_building')),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              Text('${v2Fmt(weight, 3)}%'),
              Text(v2Fmt(value), style: v2Style(12.5, weight: FontWeight.w700)),
              const SizedBox.shrink(),
            ],
          ),
          if (check != null)
            AccountsV2CardBody(
              top: 14,
              child: AccountsV2Note(
                tone: check.ok
                    ? AccountsV2NoteTone.ok
                    : AccountsV2NoteTone.warn,
                child: Text(
                  check.ok
                      ? '${_t('v2c_items_exact_a')} $name '
                            '${_t('v2c_items_exact_b')} (${v2Money(stageValue)}).'
                      : accountsV2SetupCheckDetail(tab.language, check),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── BOQ links ─────────────────────────────────────────────────────────────

  /// The BOQ link card under Material Supply when the saved contract measures
  /// it by items; links name saved items, so unsaved edits do not change it.
  Widget? _linksCardFor(String stageKey) {
    final sources = tab.materialSources;
    if (sources == null ||
        !setup.hasBaseline ||
        stageKey != _materialSupplyStage) {
      return null;
    }
    final stage = setup.stages.where((s) => s.stageKey == stageKey).firstOrNull;
    if (stage == null ||
        !stage.isItemsMode ||
        setup.itemsForStage(stageKey).isEmpty) {
      return null;
    }
    final canLink = sources.canLink && tab.onSaveMaterialLinks != null;
    return _MaterialLinksCard(
      setup: setup,
      stage: stage,
      sources: sources,
      language: tab.language,
      onEdit: canLink ? () => _editLinks(sources) : null,
    );
  }

  Future<void> _editLinks(YorksAccountsMaterialSources sources) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final saved = await showAccountsV2Drawer<bool>(
      context,
      closeLabel: _t('v2i_close'),
      title: Text(_t('v2m_drawer_title')),
      builder: (_) => _MaterialLinksDrawer(
        setup: setup,
        sources: sources,
        language: tab.language,
        onSave: tab.onSaveMaterialLinks!,
      ),
    );
    if (saved == true) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2m_saved'))));
    }
  }

  // ─── Side panel ────────────────────────────────────────────────────────────

  Widget _setupPanel() {
    final checks = _checks;
    final bad = checks.where((c) => !c.ok).length;
    return AccountsV2Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('v2c_setup_check'),
                  style: v2Style(17, weight: FontWeight.w700),
                ),
              ),
              AccountsV2Chip(
                bad > 0 ? '$bad ${_t('v2c_to_fix')}' : _t('v2c_ready'),
                tone: bad > 0 ? AccountsV2ChipTone.bad : AccountsV2ChipTone.ok,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t('v2c_contract_setup'),
            style: v2Style(22, weight: FontWeight.w700, height: 1.2),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 8),
            child: Text(
              '${setup.projectReference ?? ''} · ${_t('v2c_updates_as_you_type')}',
              style: v2Style(12.5, color: AccountsV2Colors.ink2),
            ),
          ),
          for (final (i, c) in checks.indexed)
            _CheckRow(
              ok: c.ok,
              title: accountsV2SetupCheckTitle(tab.language, c),
              detail: accountsV2SetupCheckDetail(tab.language, c),
              last: i == checks.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _howCard() {
    final example = () {
      for (final st in _stages) {
        if (!st.byItems || st.items.isEmpty) continue;
        final it = st.items.firstWhere(
          (i) => _num(i.quantity) > 1,
          orElse: () => st.items.first,
        );
        final qty = _num(it.quantity);
        final q = (qty / 3).round().clamp(1, qty.isFinite ? qty.toInt() : 1);
        final value = _num(_contract) * _num(it.weight) / 100;
        return (it, q, qty, value);
      }
      return null;
    }();
    Widget formula(String title, String code) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: v2Style(12.5, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          _CodeChip(code),
        ],
      ),
    );
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(icon: 'info', title: _t('v2c_how_title')),
          AccountsV2CardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                formula(_t('v2c_how_stage'), _t('v2c_how_stage_code')),
                formula(_t('v2c_how_item'), _t('v2c_how_item_code')),
                formula(_t('v2c_how_claimed'), _t('v2c_how_claimed_code')),
                if (example != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text.rich(
                      TextSpan(
                        style: v2Style(
                          12.5,
                          color: AccountsV2Colors.ink2,
                          height: 1.6,
                        ),
                        children: [
                          TextSpan(
                            text: '${_t('v2c_example')} ',
                            style: v2Style(12.5, weight: FontWeight.w700),
                          ),
                          TextSpan(
                            text:
                                '${example.$2} ${_t('v2o_of')} '
                                '${v2Fmt(example.$3, 0)} '
                                '${example.$1.label.text.trim()}\n'
                                '${v2Fmt(example.$4)} × ${example.$2} ÷ '
                                '${v2Fmt(example.$3, 0)} = ',
                          ),
                          TextSpan(
                            text: v2Money(example.$4 * example.$2 / example.$3),
                            style: v2Style(12.5, weight: FontWeight.w700),
                          ),
                        ],
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

// ─── Small pieces ────────────────────────────────────────────────────────────

/// A filled-in but locked field, styled like the editable ones.
class _ReadOnlyField extends StatefulWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  State<_ReadOnlyField> createState() => _ReadOnlyFieldState();
}

class _ReadOnlyFieldState extends State<_ReadOnlyField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_ReadOnlyField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountsV2TextField(
    label: widget.label,
    controller: _c,
    size: AccountsV2FieldSize.large,
    readOnly: true,
  );
}

/// The building name in the first column, in the same box as the inputs.
class _NameCell extends StatelessWidget {
  const _NameCell(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AccountsV2Colors.line),
    ),
    child: Text(name, maxLines: 1, style: v2Style(13)),
  );
}

class _TotalPercent extends StatelessWidget {
  const _TotalPercent(this.total);

  final double total;

  @override
  Widget build(BuildContext context) => Text(
    v2Pct(total, 2),
    style: v2Style(
      12.5,
      weight: FontWeight.w700,
      tabular: true,
      color: (total - 100).abs() < 0.005
          ? AccountsV2Colors.ok
          : AccountsV2Colors.bad,
    ),
  );
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AccountsV2Breakpoints.isPhone(context) ? 44 : 30,
    child: AccountsV2Button(
      label: '',
      icon: 'trash',
      kind: AccountsV2ButtonKind.ghostDanger,
      size: AccountsV2ButtonSize.small,
      tooltip: tooltip,
      onPressed: onPressed,
    ),
  );
}

class _ItemValue extends StatelessWidget {
  const _ItemValue({
    required this.value,
    required this.quantity,
    required this.unit,
  });

  final double value;
  final double quantity;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(v2Fmt(value), style: v2Style(12.5, tabular: true)),
      if (quantity > 1)
        Text(
          '${v2Fmt(value / quantity)} / $unit',
          style: v2Style(12, color: AccountsV2Colors.mut),
        ),
    ],
  );
}

/// The "% complete (lump sum)" / "Item quantities" choice in a stage row.
class _ModeSelect extends StatelessWidget {
  const _ModeSelect({
    required this.byItems,
    required this.enabled,
    required this.language,
    required this.onChanged,
  });

  final bool byItems;
  final bool enabled;
  final AppLanguage language;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountsV2Text(language, key);
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : AccountsV2Colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? AccountsV2Colors.line : Colors.transparent,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool>(
          value: byItems,
          isExpanded: true,
          isDense: true,
          style: v2Style(13),
          icon: const AccountsV2Icon('caret', size: 20),
          borderRadius: BorderRadius.circular(10),
          onChanged: enabled
              ? (v) {
                  if (v != null) onChanged(v);
                }
              : null,
          items: [
            DropdownMenuItem(value: false, child: Text(t('v2c_mode_lump'))),
            DropdownMenuItem(value: true, child: Text(t('v2c_mode_items'))),
          ],
        ),
      ),
    );
  }
}

/// A small button that opens a menu of choices (Add building, Copy list from…).
class _AddMenu<T> extends StatelessWidget {
  const _AddMenu({
    required this.label,
    required this.options,
    required this.onSelected,
    this.icon = 'plus',
    this.primary = true,
  });

  final String label;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;
  final String icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      enabled: options.isNotEmpty,
      tooltip: label,
      onSelected: (i) => onSelected(options[i].$1),
      itemBuilder: (_) => [
        for (final (i, o) in options.indexed)
          PopupMenuItem<int>(value: i, child: Text(o.$2)),
      ],
      child: IgnorePointer(
        child: AccountsV2Button(
          label: label,
          icon: icon,
          kind: primary
              ? AccountsV2ButtonKind.primary
              : AccountsV2ButtonKind.normal,
          size: AccountsV2ButtonSize.small,
          onPressed: options.isEmpty ? null : () {},
        ),
      ),
    );
  }
}

/// One setup check line in the side panel (`.check`).
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.ok,
    required this.title,
    required this.detail,
    required this.last,
  });

  final bool ok;
  final String title;
  final String detail;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AccountsV2Colors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ok ? AccountsV2Colors.ok50 : AccountsV2Colors.bad50,
            shape: BoxShape.circle,
          ),
          child: ok
              ? const AccountsV2Icon(
                  'check',
                  size: 13,
                  color: AccountsV2Colors.ok,
                )
              : Text(
                  '!',
                  style: v2Style(
                    12,
                    weight: FontWeight.w800,
                    color: AccountsV2Colors.bad,
                    height: 1,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: v2Style(12.5, weight: FontWeight.w700)),
              Text(detail, style: v2Style(12, color: AccountsV2Colors.mut)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A formula in a light box (`.fx code`).
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AccountsV2Colors.bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AccountsV2Colors.line),
    ),
    child: Text(code, style: v2Style(12)),
  );
}

/// The grey summary line under the details form, with bold figures (`.how`).
class _HowLine extends StatelessWidget {
  const _HowLine({required this.children});

  final List<(String text, bool bold)> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AccountsV2Colors.bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text.rich(
      TextSpan(
        style: v2Style(12.5, color: AccountsV2Colors.ink2),
        children: [
          for (final (text, bold) in children)
            TextSpan(
              text: text,
              style: bold
                  ? v2Style(
                      12.5,
                      weight: FontWeight.w700,
                      color: AccountsV2Colors.ink,
                    )
                  : null,
            ),
        ],
      ),
    ),
  );
}

enum _ProblemField { contract, vat, prefix, woDate }

/// One reason the changes cannot be saved yet, and where on the page it is.
final class _SaveBlocker {
  const _SaveBlocker(this.text, [this.target, this.field]);

  final String text;
  final GlobalKey? target;
  final _ProblemField? field;
}

class _BlockerLine extends StatelessWidget {
  const _BlockerLine({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 6),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: AccountsV2Colors.bad,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: v2Style(13).copyWith(
                decoration: onTap == null ? null : TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return line;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: line),
    );
  }
}

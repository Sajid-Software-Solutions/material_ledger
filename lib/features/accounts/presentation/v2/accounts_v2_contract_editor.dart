part of 'accounts_v2_contract_tab.dart';

/// The start screen for a project with no contract yet.
class _FirstContractStart extends StatelessWidget {
  const _FirstContractStart({
    required this.language,
    required this.canEdit,
    required this.hasBuildings,
    required this.onStart,
    this.onImport,
  });

  final AppLanguage language;
  final bool canEdit;
  final bool hasBuildings;
  final VoidCallback onStart;
  final VoidCallback? onImport;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final body = !canEdit
        ? _t('v2_first_no_access')
        : hasBuildings
        ? _t('v2_first_body')
        : _t('v2_first_no_buildings');
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(_t('v2_first_title')),
              const SizedBox(height: AppSpacing.sm),
              Text(body, style: AppTypography.bodyMedium),
              if (canEdit && hasBuildings) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(_t('v2_first_start')),
                    ),
                    if (onImport != null)
                      OutlinedButton.icon(
                        onPressed: onImport,
                        icon: const Icon(Icons.upload_file_outlined, size: 16),
                        label: Text(_t('v2_import_master')),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

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

/// Creates or edits the contract: value, building split, stages and, for
/// item-billed stages, the single item list every building shares.
class _ContractEditor extends StatefulWidget {
  const _ContractEditor({
    required this.setup,
    required this.buildingChoices,
    required this.stageOptions,
    required this.language,
    required this.onCancel,
    required this.onSave,
  });

  final YorksAccountsCommercialSetupRead setup;
  final List<YorksContractBuildingOption> buildingChoices;
  final List<YorksContractStageOption> stageOptions;
  final AppLanguage language;
  final VoidCallback onCancel;
  final Future<String?> Function(YorksAccountsCommercialSetup setup) onSave;

  @override
  State<_ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends State<_ContractEditor> {
  late final TextEditingController _contract;
  late final TextEditingController _vat;
  late final TextEditingController _terms;
  late final TextEditingController _reminder;
  final Map<String, TextEditingController> _building = {};
  final List<_StageDraft> _stages = [];
  int _nextKey = 1;
  bool _saving = false;
  String? _error;

  String _t(String key) => accountsV2Text(widget.language, key);

  void _onChanged() {
    if (mounted) setState(() {});
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

  @override
  void initState() {
    super.initState();
    final s = widget.setup;
    _contract = TextEditingController(
      text: s.contractValue?.canonicalText ?? '',
    )..addListener(_onChanged);
    _vat = TextEditingController(text: s.vatRatePercent?.canonicalText ?? '5')
      ..addListener(_onChanged);
    _terms = TextEditingController(text: s.paymentTermsDays?.toString() ?? '');
    _reminder = TextEditingController(
      text: s.reminderLeadDays?.toString() ?? '',
    );

    final evens = _evenShares(widget.buildingChoices.length);
    for (final (i, option) in widget.buildingChoices.indexed) {
      final existing = s.buildings.where(
        (b) => b.projectScopeId == option.scopeId,
      );
      _building[option.scopeId] = TextEditingController(
        text: s.hasBaseline
            ? (existing.isEmpty
                  ? '0'
                  : existing.first.allocationPercent.canonicalText)
            : evens[i],
      )..addListener(_onChanged);
    }

    if (s.stages.isNotEmpty) {
      for (final st in s.stages) {
        _stages.add(
          _StageDraft(
            key: st.stageKey,
            label: st.stageName,
            percent: st.allocationPercent.canonicalText,
            byItems: st.isItemsMode,
            items: _itemsFor(st.stageKey),
            onChanged: _onChanged,
          ),
        );
      }
    } else {
      _applyTemplate();
    }
  }

  /// One building's list stands for all (the tab blocks lists that differ).
  List<_ItemRowDraft> _itemsFor(String stageKey) {
    final all = widget.setup.itemsForStage(stageKey);
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
          onChanged: _onChanged,
        ),
    ];
  }

  void _applyTemplate() {
    final previous = {for (final s in _stages) s.key: s};
    _stages.clear();
    for (final option in widget.stageOptions) {
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
            onChanged: _onChanged,
          ),
        );
      }
    }
    for (final dropped in previous.values) {
      dropped.dispose();
    }
  }

  @override
  void dispose() {
    for (final c in [_contract, _vat, _terms, _reminder, ..._building.values]) {
      c.dispose();
    }
    for (final s in _stages) {
      s.dispose();
    }
    super.dispose();
  }

  YorksAccountsDecimal _dec(TextEditingController c) =>
      YorksAccountsDecimal.tryParse(c.text.trim()) ?? YorksAccountsDecimal.zero;

  YorksAccountsCommercialSetup _model() {
    final s = widget.setup;
    return YorksAccountsCommercialSetup(
      contractValue: _dec(_contract),
      currencyCode: s.currencyCode ?? 'AED',
      vatRatePercent: _dec(_vat),
      paymentTermsDays: int.tryParse(_terms.text.trim()),
      reminderLeadDays: int.tryParse(_reminder.text.trim()),
      buildings: [
        for (final o in widget.buildingChoices)
          if (_dec(_building[o.scopeId]!).isPositive)
            YorksAccountsSetupBuilding(
              buildingScopeId: o.scopeId,
              allocationPercent: _dec(_building[o.scopeId]!),
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
  }

  double _num(String text) => double.tryParse(text.trim()) ?? 0;

  /// What a stage's items must total per building, or null when the buildings
  /// have unequal shares (the server applies one list to all of them). Display
  /// check only; the server enforces the exact rule.
  double? _neededWeight(_StageDraft st) {
    final shares = _building.values
        .map((c) => _num(c.text))
        .where((v) => v > 0)
        .toSet();
    if (shares.length != 1) return null;
    return shares.first * _num(st.percent.text) / 100;
  }

  bool _itemsOk(_StageDraft st) {
    if (st.items.isEmpty || !st.items.every((i) => i.isValid)) return false;
    final needed = _neededWeight(st);
    if (needed == null) return false;
    final have = st.items.fold(0.0, (a, i) => a + _num(i.weight.text));
    return (have - needed).abs() <= 0.000005;
  }

  bool get _vatOk {
    final v = YorksAccountsDecimal.tryParse(_vat.text.trim());
    return v != null && !v.isNegative;
  }

  bool get _canSave =>
      !_saving &&
      _vatOk &&
      _model().isValid &&
      _stages.every((s) => s.label.text.trim().isNotEmpty) &&
      _stages.where((s) => s.byItems).every(_itemsOk);

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(_model());
    if (error == null) {
      messenger?.showSnackBar(SnackBar(content: Text(_t('v2_saved'))));
    }
    if (mounted) {
      setState(() {
        _saving = false;
        _error = error == null
            ? null
            : accountsV2ErrorText(widget.language, error);
      });
    }
  }

  void _splitEvenly() {
    final shares = _evenShares(widget.buildingChoices.length);
    for (final (i, o) in widget.buildingChoices.indexed) {
      _building[o.scopeId]!.text = shares[i];
    }
  }

  void _addStage() {
    final key = 'custom_${_nextKey++}';
    setState(() {
      _stages.add(
        _StageDraft(
          key: key,
          label: '',
          percent: '0',
          byItems: false,
          items: [],
          onChanged: _onChanged,
        ),
      );
    });
  }

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
          onChanged: _onChanged,
        ),
      );
    });
  }

  Widget _labelled(
    String label,
    TextEditingController controller, {
    bool numeric = true,
    String? suffix,
    double? width,
  }) {
    final field = TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  Widget _itemRow(_StageDraft st, _ItemRowDraft it) {
    final remove = IconButton(
      tooltip: _t('v2_remove'),
      icon: const Icon(Icons.delete_outline, size: 18),
      onPressed: () => setState(() {
        st.items.remove(it);
        it.dispose();
      }),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final name = _labelled(_t('v2_item_label'), it.label, numeric: false);
          final qty = _labelled(_t('v2_qty_label'), it.quantity);
          final unit = _labelled(_t('v2_unit_label'), it.unit, numeric: false);
          final weight = _labelled(
            _t('v2_weight_label'),
            it.weight,
            suffix: '%',
          );
          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: 90, child: qty),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: 90, child: unit),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: 110, child: weight),
                remove,
              ],
            );
          }
          return Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: name),
                    remove,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: qty),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: unit),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: weight),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stageCard(_StageDraft st) {
    final needed = _neededWeight(st);
    final have = st.items.fold(0.0, (a, i) => a + _num(i.weight.text));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _labelled(_t('v2_stage_name'), st.label, numeric: false),
              ),
              const SizedBox(width: AppSpacing.sm),
              _labelled(
                _t('v2_share_label'),
                st.percent,
                suffix: '%',
                width: 110,
              ),
              if (_stages.length > 1)
                IconButton(
                  tooltip: _t('v2_remove'),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => setState(() {
                    _stages.remove(st);
                    st.dispose();
                  }),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('v2_stage_by_items'),
                  style: AppTypography.bodyMedium,
                ),
              ),
              Switch(
                value: st.byItems,
                onChanged: (on) => setState(() => st.byItems = on),
              ),
            ],
          ),
          if (st.byItems) ...[
            Text(
              _t('v2_items_same_note'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            for (final it in st.items) _itemRow(st, it),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _addItem(st),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(_t('v2_item_add')),
                ),
                const Spacer(),
                if (needed != null)
                  Text(
                    '${_fmt(have)}% / ${_fmt(needed)}%',
                    style: AppTypography.labelLarge.copyWith(
                      color: _itemsOk(st) ? AppColors.success : AppColors.error,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.lg, color: AppColors.line),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final text = v.toStringAsFixed(6);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final model = _model();
    final hundred = YorksAccountsDecimal.hundred;
    final isFirst = !widget.setup.hasBaseline;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (!isFirst) ...[
          _EditNote(language: widget.language),
          const SizedBox(height: AppSpacing.lg),
        ],
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(
                isFirst
                    ? _t('v2_first_title')
                    : _t('v2_contract_summary_title'),
                number: 1,
              ),
              const SizedBox(height: AppSpacing.md),
              _labelled(_t('v2_contract_value'), _contract),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _labelled(_t('v2_vat_label'), _vat, suffix: '%'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _labelled(
                      _t('v2_payment_terms_label'),
                      _terms,
                      suffix: _t('v2_days_suffix'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _labelled(
                _t('v2_reminder_label'),
                _reminder,
                suffix: _t('v2_days_suffix'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(
                _t('v2_buildings_title'),
                number: 2,
                trailing: _PercentBadge(
                  percent: model.buildingTotal,
                  ok: model.buildingTotal == hundred,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _splitEvenly,
                  child: Text(_t('v2_split_evenly')),
                ),
              ),
              for (final o in widget.buildingChoices)
                _EditField(
                  label: o.name,
                  controller: _building[o.scopeId]!,
                  numeric: true,
                  suffix: '%',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(
                _t('v2_stages_title'),
                number: 3,
                trailing: _PercentBadge(
                  percent: model.stageTotal,
                  ok: model.stageTotal == hundred,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  if (widget.stageOptions.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_applyTemplate),
                      child: Text(_t('v2_stages_standard')),
                    ),
                  TextButton.icon(
                    onPressed: _addStage,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(_t('v2_stage_add')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final st in _stages) _stageCard(st),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AccountsV2Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountsV2SectionTitle(_t('v2_setup_check_title')),
              const SizedBox(height: AppSpacing.sm),
              for (final check in model.validate())
                _CheckRow(
                  label: _t(_checkLabelKey(check.key)),
                  ok: check.ok,
                  detail: _checkDetail(check.key, model),
                ),
              _CheckRow(
                label: _t('v2_check_vat'),
                ok: _vatOk,
                detail: '${_vat.text.trim()}%',
              ),
              for (final st in _stages.where((s) => s.byItems))
                _CheckRow(
                  label: _neededWeight(st) == null
                      ? _t('v2_check_items_equal_buildings')
                      : '${st.label.text.trim()} · ${_t('v2_check_item_weights')}',
                  ok: _itemsOk(st),
                  detail: '${st.items.length}',
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(_saving ? _t('v2_saving') : _t('v2_save')),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              onPressed: _saving ? null : widget.onCancel,
              child: Text(_t('v2_cancel')),
            ),
          ],
        ),
      ],
    );
  }

  String _checkDetail(String key, YorksAccountsCommercialSetup model) =>
      switch (key) {
        'buildings_total' =>
          '${model.buildingTotal.displayText(maximumFractionDigits: 2)}%',
        'stages_total' =>
          '${model.stageTotal.displayText(maximumFractionDigits: 2)}%',
        _ => model.contractValue.displayText(maximumFractionDigits: 2),
      };

  static String _checkLabelKey(String key) => switch (key) {
    'contract_value' => 'v2_check_contract',
    'buildings_total' => 'v2_check_buildings',
    'stages_total' => 'v2_check_stages',
    _ => key,
  };
}

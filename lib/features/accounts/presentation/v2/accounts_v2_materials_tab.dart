/// Accounts › Materials (PRODUCT_DECISIONS.md section 61).
///
/// Each building's contract lines as the signed invoices print them (the
/// material and installation sheets), but live: the line's quantity and unit,
/// what is confirmed delivered or installed, what reached site through
/// Material Requests and, for someone who may see commercial values, the
/// line's rate, amount and what has been invoiced. Read-only: quantities are
/// confirmed on Progress & claims; the BOQ's Contract Materials sheet raises
/// the requests. Each building's sheet links to both.
///
/// Everything shown comes from the server projection. Money is shown only when
/// the server sent it; the screen never decides that from a role.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/material_register_models.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

/// Opens Progress & claims on one building (null: all of them) and stage.
typedef AccountsV2OpenClaims =
    void Function(String? buildingScopeId, String stageKey);

class AccountsV2MaterialsTab extends StatefulWidget {
  const AccountsV2MaterialsTab({
    super.key,
    required this.register,
    required this.language,
    this.initialBuildingScopeId,
    this.onOpenClaims,
    this.onOpenBoqSheet,
  });

  final YorksAccountsMaterialRegister register;
  final AppLanguage language;

  /// The building to open on (a BOQ sheet's "Open in Accounts").
  final String? initialBuildingScopeId;

  /// Opens Progress & claims, where quantities are confirmed.
  final AccountsV2OpenClaims? onOpenClaims;

  /// Opens a BOQ folder by id; null when the viewer cannot read the BOQ.
  final ValueChanged<String>? onOpenBoqSheet;

  @override
  State<AccountsV2MaterialsTab> createState() => _AccountsV2MaterialsTabState();
}

class _AccountsV2MaterialsTabState extends State<AccountsV2MaterialsTab> {
  /// The building shown, by position in the register; -1 shows all of them.
  int _building = 0;
  String? _stageKey;

  @override
  void initState() {
    super.initState();
    final focus = widget.initialBuildingScopeId;
    if (focus != null) {
      final index = widget.register.buildings.indexWhere(
        (b) => b.projectScopeId == focus,
      );
      if (index >= 0) _building = index;
    }
  }

  String _t(String key) => accountsV2Text(widget.language, key);

  YorksAccountsMaterialRegister get _register => widget.register;

  String get _stage {
    final stages = _register.stages;
    final chosen = _stageKey;
    if (chosen != null && stages.any((s) => s.stageKey == chosen)) {
      return chosen;
    }
    return stages.isEmpty ? '' : stages.first.stageKey;
  }

  List<(int, YorksAccountsRegisterBuilding)> get _shownBuildings {
    final all = _register.buildings.indexed.toList();
    if (_building < 0 || _building >= all.length) return all;
    return [all[_building]];
  }

  @override
  Widget build(BuildContext context) {
    final register = _register;
    if (register.stages.isEmpty || register.isEmpty) {
      return AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'box',
          title: _t('v2mat_empty_title'),
          body: _t('v2mat_empty_body'),
        ),
      );
    }
    final format = AccountsV2Format(
      currencyCode: register.currencyCode ?? 'AED',
    );
    final stage = _stage;
    final stageLabel = register.stages
        .firstWhere(
          (s) => s.stageKey == stage,
          orElse: () => register.stages.first,
        )
        .stageLabel;
    final shown = _shownBuildings;
    return AccountsV2Stack(
      children: [
        _Filters(
          language: widget.language,
          buildings: [for (final b in register.buildings) b.shortName],
          building: _building,
          onBuilding: (i) => setState(() => _building = i),
          stages: [for (final s in register.stages) (s.stageKey, s.stageLabel)],
          stage: stage,
          onStage: (k) => setState(() => _stageKey = k),
        ),
        _Kpis(
          language: widget.language,
          format: format,
          stageKey: stage,
          buildings: [for (final (_, b) in shown) b],
          values: register.canViewValues,
        ),
        for (final (index, building) in shown)
          _Sheet(
            key: ValueKey('v2mat_sheet_${building.projectScopeId}_$stage'),
            language: widget.language,
            format: format,
            letter: yorksAccountsBuildingLetter(index),
            building: building,
            stageKey: stage,
            stageLabel: stageLabel,
            values: register.canViewValues,
            onOpenClaims: widget.onOpenClaims == null
                ? null
                : () => widget.onOpenClaims!(building.projectScopeId, stage),
            onOpenBoqSheet: switch ((
              widget.onOpenBoqSheet,
              _sheetGroupId(building),
            )) {
              (final open?, final groupId?) => () => open(groupId),
              _ => null,
            },
          ),
        AccountsV2Note(
          child: Text(
            register.canViewValues
                ? '${_t('v2mat_note_how')} ${_t('v2mat_rates_note')}'
                : '${_t('v2mat_note_how')} ${_t('v2mat_no_prices')}',
          ),
        ),
      ],
    );
  }
}

/// The BOQ folder holding most of a building's tied lines (its Contract
/// Materials sheet), or null when none is tied.
String? _sheetGroupId(YorksAccountsRegisterBuilding building) {
  final counts = <String, int>{};
  for (final line in building.lines) {
    final groupId = line.boqGroupId;
    if (groupId == null || groupId.isEmpty) continue;
    counts[groupId] = (counts[groupId] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

// ─── Filters ─────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({
    required this.language,
    required this.buildings,
    required this.building,
    required this.onBuilding,
    required this.stages,
    required this.stage,
    required this.onStage,
  });

  final AppLanguage language;
  final List<String> buildings;
  final int building;
  final ValueChanged<int> onBuilding;
  final List<(String, String)> stages;
  final String stage;
  final ValueChanged<String> onStage;

  @override
  Widget build(BuildContext context) {
    final buildingChoices = [
      for (final (i, name) in buildings.indexed)
        _Choice(
          key: ValueKey('v2mat_building_$i'),
          label: name,
          selected: building == i,
          onTap: () => onBuilding(i),
        ),
      if (buildings.length > 1)
        _Choice(
          key: const ValueKey('v2mat_building_all'),
          label: accountsV2Text(language, 'v2mat_all'),
          selected: building < 0,
          onTap: () => onBuilding(-1),
        ),
    ];
    final stageChoices = [
      for (final (key, label) in stages)
        _Choice(
          key: ValueKey('v2mat_stage_$key'),
          label: label,
          selected: stage == key,
          onTap: () => onStage(key),
        ),
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ChoiceGroup(
          label: accountsV2Text(language, 'v2mat_building'),
          children: buildingChoices,
        ),
        if (stageChoices.length > 1)
          _ChoiceGroup(
            label: accountsV2Text(language, 'v2mat_stage'),
            children: stageChoices,
          ),
      ],
    );
  }
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Phones keep the choices on one line and scroll it sideways.
    final phone = AccountsV2Breakpoints.isPhone(context);
    final box = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AccountsV2Colors.cardBorder),
      ),
      child: phone
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  child,
                ],
              ],
            )
          : Wrap(spacing: 2, runSpacing: 2, children: children),
    );
    return Semantics(
      container: true,
      label: label,
      child: phone
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: box)
          : box,
    );
  }
}

/// One segment: 44px tall on phones, 34px on larger screens.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AccountsV2Colors.pri50 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(
              minHeight: phone ? 44 : 34,
              minWidth: phone ? 44 : 0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Sized to its label, not stretched across the row.
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: v2Style(
                  12.5,
                  weight: FontWeight.w700,
                  color: selected
                      ? AccountsV2Colors.pri
                      : AccountsV2Colors.ink2,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── KPIs ────────────────────────────────────────────────────────────────────

class _Kpis extends StatelessWidget {
  const _Kpis({
    required this.language,
    required this.format,
    required this.stageKey,
    required this.buildings,
    required this.values,
  });

  final AppLanguage language;
  final AccountsV2Format format;
  final String stageKey;
  final List<YorksAccountsRegisterBuilding> buildings;
  final bool values;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final b in buildings)
        for (final l in b.lines)
          if (l.stage(stageKey) != null) (l, l.stage(stageKey)!),
    ];
    final done = lines
        .where((e) => e.$2.progress == YorksAccountsLineProgress.done)
        .length;
    final part = lines
        .where((e) => e.$2.progress == YorksAccountsLineProgress.part)
        .length;
    final supply = stageKey == 'material_supply';
    YorksAccountsDecimal sum(
      YorksAccountsDecimal? Function(YorksAccountsRegisterCell) pick,
    ) {
      var total = YorksAccountsDecimal.zero;
      for (final b in buildings) {
        final value = b.cell(stageKey);
        if (value == null) continue;
        total = total + (pick(value) ?? YorksAccountsDecimal.zero);
      }
      return total;
    }

    final cards = <Widget>[];
    if (values) {
      final stageValue = sum((c) => c.stageValue);
      final doneAmount = sum((c) => c.doneAmount);
      final invoiced = sum((c) => c.invoicedAmount);
      final notInvoiced = sum((c) => c.notInvoicedAmount);
      final ready = lines.any(
        (e) => e.$2.billing == YorksAccountsLineBilling.ready,
      );
      final references = <String>{
        for (final e in lines)
          if (e.$2.lastInvoice != null) e.$2.lastInvoice!.reference,
      }.toList()..sort();
      final latest = references.isEmpty
          ? null
          : lines
                .map((e) => e.$2.lastInvoice)
                .whereType<YorksAccountsRegisterInvoice>()
                .firstWhere((i) => i.reference == references.last);
      cards.addAll([
        AccountsV2KpiCard(
          key: const ValueKey('v2mat_kpi_done'),
          icon: supply ? 'truck' : 'check',
          label: _t(supply ? 'v2mat_kpi_delivered' : 'v2mat_kpi_installed'),
          value: format.percentOfRatio(format.ratio(doneAmount, stageValue)),
          caption: _t('v2mat_of')
              .replaceAll('{done}', format.money(doneAmount))
              .replaceAll(
                '{total}',
                format.money(stageValue, withCurrency: false),
              ),
          tone: AccountsV2Tone.green,
        ),
        AccountsV2KpiCard(
          key: const ValueKey('v2mat_kpi_invoiced'),
          icon: 'receipt',
          label: _t('v2mat_kpi_invoiced'),
          value: format.money(invoiced),
          caption: latest == null
              ? _t('v2mat_kpi_invoiced_none')
              : '${latest.reference} · ${accountsV2Text(language, 'status_${latest.status}')}',
        ),
        AccountsV2KpiCard(
          key: const ValueKey('v2mat_kpi_not_invoiced'),
          icon: 'coins',
          label: _t('v2mat_kpi_not_invoiced'),
          value: format.money(notInvoiced),
          caption: !doneAmount.isPositive
              ? _t(
                  supply
                      ? 'v2mat_kpi_none_delivered'
                      : 'v2mat_kpi_none_installed',
                )
              : !notInvoiced.isPositive
              ? _t('v2mat_kpi_all_invoiced')
              : ready
              ? _t('v2mat_kpi_next_claim')
              : _t('v2mat_kpi_correction'),
          tone: AccountsV2Tone.vio,
          valueTone: notInvoiced.isPositive
              ? AccountsV2ValueTone.vio
              : AccountsV2ValueTone.plain,
        ),
      ]);
    }
    cards.add(
      AccountsV2KpiCard(
        key: const ValueKey('v2mat_kpi_lines'),
        icon: 'list',
        label: _t('v2mat_kpi_lines'),
        value: _t('v2mat_of')
            .replaceAll('{done}', '$done')
            .replaceAll('{total}', '${lines.length}'),
        caption:
            _t(supply ? 'v2mat_kpi_lines_supply' : 'v2mat_kpi_lines_install')
                .replaceAll('{part}', '$part')
                .replaceAll('{none}', '${lines.length - done - part}'),
        tone: AccountsV2Tone.blue,
      ),
    );
    if (!values && supply) {
      final onSite = lines
          .where((e) => e.$1.site?.deliveredQty.isPositive ?? false)
          .length;
      cards.add(
        AccountsV2KpiCard(
          key: const ValueKey('v2mat_kpi_on_site'),
          icon: 'truck',
          label: _t('v2mat_on_site'),
          value: _linesText(language, onSite),
          caption: _t('v2mat_from_requests'),
          tone: AccountsV2Tone.org,
        ),
      );
    }
    return AccountsV2KpiRow(children: cards);
  }
}

// ─── One building's sheet ────────────────────────────────────────────────────

/// "15 lines", or "1 line".
String _linesText(AppLanguage language, int n) => n == 1
    ? accountsV2Text(language, 'v2mat_line_one')
    : accountsV2Text(language, 'v2mat_lines').replaceAll('{n}', '$n');

String _qty(YorksAccountsDecimal value) =>
    value.displayText(maximumFractionDigits: 4);

/// A quantity of the line: "20", or "50%" of a lump-sum line.
String _part(YorksAccountsDecimal done, YorksAccountsRegisterLineStage stage) {
  if (!stage.isLot) return _qty(done);
  const format = AccountsV2Format();
  return format.percentOfRatio(
    format.ratio(done, stage.quantity),
    fractionDigits: 0,
  );
}

/// "20 of 55", or "50%" for a lump-sum line.
String _progressText(
  AppLanguage language,
  YorksAccountsDecimal done,
  YorksAccountsRegisterLineStage stage,
) {
  if (stage.isLot) return _part(done, stage);
  return accountsV2Text(language, 'v2mat_of')
      .replaceAll('{done}', _qty(done))
      .replaceAll('{total}', _qty(stage.quantity));
}

Widget _stateChip(
  AppLanguage language,
  String stageKey,
  YorksAccountsRegisterLineStage stage,
) {
  final supply = stageKey == 'material_supply';
  final (key, tone) = switch (stage.progress) {
    YorksAccountsLineProgress.none => (
      supply ? 'v2mat_not_delivered' : 'v2mat_not_started',
      AccountsV2ChipTone.neutral,
    ),
    YorksAccountsLineProgress.part => (
      supply ? 'v2mat_part_delivered' : 'v2mat_installing',
      supply ? AccountsV2ChipTone.warn : AccountsV2ChipTone.pri,
    ),
    YorksAccountsLineProgress.done => (
      supply ? 'v2mat_delivered_state' : 'v2mat_installed_state',
      AccountsV2ChipTone.ok,
    ),
  };
  return AccountsV2Chip(accountsV2Text(language, key), tone: tone);
}

/// The billing chip, or null when there is nothing to say (or no right to).
Widget? _billingChip(
  AppLanguage language,
  YorksAccountsRegisterLineStage stage,
) {
  return switch (stage.billing) {
    YorksAccountsLineBilling.ready => AccountsV2Chip(
      accountsV2Text(language, 'v2mat_ready_to_invoice'),
      tone: AccountsV2ChipTone.vio,
    ),
    YorksAccountsLineBilling.overInvoiced => AccountsV2Chip(
      accountsV2Text(language, 'v2mat_over_invoiced'),
      tone: AccountsV2ChipTone.bad,
    ),
    _ => null,
  };
}

/// "20 · YRA32202R.1" and the invoice's status beneath, or "—".
Widget _invoicedCell(
  AppLanguage language,
  YorksAccountsRegisterLineStage stage,
) {
  final invoiced = stage.invoicedQty;
  final invoice = stage.lastInvoice;
  if (invoiced == null || !invoiced.isPositive || invoice == null) {
    return Text('—', style: v2Style(12.5, color: AccountsV2Colors.mut));
  }
  return AccountsV2CellStack(
    primary: '${_part(invoiced, stage)} · ${invoice.reference}',
    secondary: accountsV2Text(language, 'status_${invoice.status}'),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    super.key,
    required this.language,
    required this.format,
    required this.letter,
    required this.building,
    required this.stageKey,
    required this.stageLabel,
    required this.values,
    this.onOpenClaims,
    this.onOpenBoqSheet,
  });

  final AppLanguage language;
  final AccountsV2Format format;
  final String letter;
  final YorksAccountsRegisterBuilding building;
  final String stageKey;
  final String stageLabel;
  final bool values;
  final VoidCallback? onOpenClaims;
  final VoidCallback? onOpenBoqSheet;

  String _t(String key) => accountsV2Text(language, key);

  bool get _supply => stageKey == 'material_supply';

  @override
  Widget build(BuildContext context) {
    final rows = yorksAccountsSheetRows(letter, [
      for (final l in building.lines)
        if (l.stage(stageKey) != null) l,
    ]);
    final cell = building.cell(stageKey);
    final lineCount = rows.where((r) => !r.isHeading).length;
    final subtitle = [
      _linesText(language, lineCount),
      if (values && cell?.stageValue != null) format.money(cell!.stageValue),
    ].join(' · ');
    final phone = AccountsV2Breakpoints.isPhone(context);
    final scope = building.projectScopeId;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2TileHead(
            icon: _supply ? 'box' : 'cog',
            tone: _supply ? AccountsV2Tone.blue : AccountsV2Tone.green,
            title: '$letter · ${building.shortName} — $stageLabel',
            subtitle: subtitle,
            actions: [
              if (onOpenClaims != null)
                AccountsV2Button(
                  key: ValueKey('v2mat_open_claims_$scope'),
                  label: _t('v2mat_open_claims'),
                  icon: 'chart',
                  size: AccountsV2ButtonSize.small,
                  onPressed: onOpenClaims,
                ),
              if (onOpenBoqSheet != null)
                AccountsV2Button(
                  key: ValueKey('v2mat_open_boq_$scope'),
                  label: _t('v2mat_open_boq'),
                  icon: 'box',
                  size: AccountsV2ButtonSize.small,
                  onPressed: onOpenBoqSheet,
                ),
            ],
          ),
          if (phone)
            _PhoneLines(
              language: language,
              format: format,
              rows: rows,
              stageKey: stageKey,
              values: values,
            )
          else
            _table(rows, cell),
        ],
      ),
    );
  }

  Widget _table(
    List<YorksAccountsSheetRow> rows,
    YorksAccountsRegisterCell? cell,
  ) {
    final onSite = _supply;
    final columns = <AccountsV2Column>[
      AccountsV2Column(_t('v2mat_ref'), width: 72),
      AccountsV2Column(_t('v2mat_description'), flex: 3),
      AccountsV2Column(_t('v2mat_qty'), width: 64, numeric: true),
      AccountsV2Column(_t('v2mat_unit'), width: 60),
      if (values) AccountsV2Column(_t('v2mat_rate'), width: 112, numeric: true),
      if (values)
        AccountsV2Column(_t('v2mat_amount'), width: 120, numeric: true),
      AccountsV2Column(
        _t(_supply ? 'v2mat_delivered' : 'v2mat_installed'),
        width: 120,
      ),
      if (onSite)
        AccountsV2Column(_t('v2mat_on_site'), width: 84, numeric: true),
      if (values) AccountsV2Column(_t('v2mat_invoiced'), width: 132),
      AccountsV2Column(_t('v2mat_state'), width: 150),
    ];
    final tableRows = <AccountsV2Row>[];
    for (final row in rows) {
      final line = row.line;
      if (line == null) {
        tableRows.add(
          AccountsV2Row([
            Text(row.code, style: v2Style(12.5, weight: FontWeight.w700)),
            Text(row.label, style: v2Style(12.5, weight: FontWeight.w700)),
            for (var i = 2; i < columns.length; i++) const SizedBox(),
          ]),
        );
        continue;
      }
      final stage = line.stage(stageKey)!;
      final billing = _billingChip(language, stage);
      tableRows.add(
        AccountsV2Row(
          key: ValueKey(
            'v2mat_line_${building.projectScopeId}_${line.itemKey}',
          ),
          [
            Text(row.code, style: v2Style(12.5, color: AccountsV2Colors.ink2)),
            Text(
              row.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: v2Style(12.5, weight: FontWeight.w600),
            ),
            Text(_qty(stage.quantity), style: v2Style(12.5, tabular: true)),
            Text(stage.unitCode),
            if (values)
              Text(
                format.money(stage.rate, withCurrency: false),
                style: v2Style(12.5, tabular: true),
              ),
            if (values)
              Text(
                format.money(stage.amount, withCurrency: false),
                style: v2Style(12.5, weight: FontWeight.w600, tabular: true),
              ),
            stage.confirmedQty.isPositive
                ? (values && stage.doneAmount != null
                      ? AccountsV2CellStack(
                          primary: _progressText(
                            language,
                            stage.confirmedQty,
                            stage,
                          ),
                          secondary: format.money(stage.doneAmount),
                        )
                      : Text(
                          _progressText(language, stage.confirmedQty, stage),
                        ))
                : Text(
                    _progressText(language, stage.confirmedQty, stage),
                    style: v2Style(12.5, color: AccountsV2Colors.mut),
                  ),
            if (onSite)
              Tooltip(
                message: line.site?.lastDeliveryReference ?? '',
                child: Text(
                  line.site == null
                      ? '—'
                      : _part(line.site!.deliveredQty, stage),
                  style: v2Style(
                    12.5,
                    tabular: true,
                    color: line.site == null
                        ? AccountsV2Colors.mut
                        : AccountsV2Colors.ink,
                  ),
                ),
              ),
            if (values) _invoicedCell(language, stage),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _stateChip(language, stageKey, stage),
                ?billing,
                if (stage.needsReview)
                  AccountsV2Chip(
                    accountsV2Text(language, 'v2mat_check_qty'),
                    tone: AccountsV2ChipTone.bad,
                  ),
              ],
            ),
          ],
        ),
      );
    }
    List<Widget>? footer;
    List<int>? spans;
    if (values && cell != null) {
      footer = [
        Text(_t('v2mat_total')),
        Text(format.money(cell.stageValue, withCurrency: false)),
        Text(format.money(cell.doneAmount, withCurrency: false)),
        if (onSite) const SizedBox(),
        Text(format.money(cell.invoicedAmount, withCurrency: false)),
        const SizedBox(),
      ];
      spans = [5, 1, 1, if (onSite) 1, 1, 1];
    }
    return AccountsV2Table(
      columns: columns,
      rows: tableRows,
      footer: footer,
      footerSpans: spans,
    );
  }
}

/// Phones: one card per line, each 44px or taller, with the state and the
/// price where the server sent one.
class _PhoneLines extends StatelessWidget {
  const _PhoneLines({
    required this.language,
    required this.format,
    required this.rows,
    required this.stageKey,
    required this.values,
  });

  final AppLanguage language;
  final AccountsV2Format format;
  final List<YorksAccountsSheetRow> rows;
  final String stageKey;
  final bool values;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final row in rows) {
      final line = row.line;
      if (line == null) {
        cards.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${row.code}  ${row.label}',
              style: v2Style(
                12.5,
                weight: FontWeight.w700,
                color: AccountsV2Colors.ink2,
              ),
            ),
          ),
        );
        continue;
      }
      final stage = line.stage(stageKey)!;
      final billing = _billingChip(language, stage);
      final invoiced = stage.invoicedQty;
      final invoice = stage.lastInvoice;
      cards.add(
        Container(
          key: ValueKey('v2mat_card_${line.itemKey}'),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AccountsV2Colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${row.code}  ${row.label}',
                      style: v2Style(13.5, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_qty(stage.quantity)} ${stage.unitCode}',
                    style: v2Style(
                      12.5,
                      color: AccountsV2Colors.ink2,
                      tabular: true,
                    ),
                  ),
                ],
              ),
              if (values && stage.amount != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${accountsV2Text(language, 'v2mat_rate')} ${format.money(stage.rate, withCurrency: false)}',
                        style: v2Style(
                          12,
                          color: AccountsV2Colors.mut,
                          tabular: true,
                        ),
                      ),
                    ),
                    Text(
                      format.money(stage.amount),
                      style: v2Style(
                        12.5,
                        weight: FontWeight.w700,
                        tabular: true,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _stateChip(language, stageKey, stage),
                  if (stage.confirmedQty.isPositive)
                    AccountsV2Chip(
                      _progressText(language, stage.confirmedQty, stage),
                    ),
                  if (values &&
                      invoiced != null &&
                      invoiced.isPositive &&
                      invoice != null)
                    AccountsV2Chip(
                      '${accountsV2Text(language, 'v2mat_invoiced')} '
                      '${_part(invoiced, stage)} · ${invoice.reference} · '
                      '${accountsV2Text(language, 'status_${invoice.status}')}',
                      tone: AccountsV2ChipTone.pri,
                    ),
                  ?billing,
                  if (stageKey == 'material_supply' &&
                      (line.site?.deliveredQty.isPositive ?? false))
                    AccountsV2Chip(
                      '${accountsV2Text(language, 'v2mat_on_site')} ${_part(line.site!.deliveredQty, stage)}',
                      tone: AccountsV2ChipTone.warn,
                    ),
                  if (stage.needsReview)
                    AccountsV2Chip(
                      accountsV2Text(language, 'v2mat_check_qty'),
                      tone: AccountsV2ChipTone.bad,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            card,
          ],
        ],
      ),
    );
  }
}

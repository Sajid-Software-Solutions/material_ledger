import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_arrangement.dart';
import '../../../../shared/models/yorks_v1_arrangement_strings.dart';
import '../../../../shared/models/yorks_v1_company_material_request.dart';
import '../../../../shared/models/yorks_v1_company_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import 'yorks_v1_company_material_request_operations.dart'
    show CompanySupplyPlanChoice;

String _stockLabel(YorksV1InventoryItem item) =>
    '${item.description} · ${item.availableQuantity} ${item.unit}';

enum _MobileStage { lines, line, review }

/// The company lane uses the same single-workspace editing pattern as the
/// project arrangement editor. Only its final command and follow-up rule differ.
class YorksV1CompanyArrangementWorkbench extends StatefulWidget {
  const YorksV1CompanyArrangementWorkbench({
    required this.request,
    required this.inventory,
    required this.language,
    required this.onSave,
    super.key,
  });

  final YorksV1CompanyMaterialRequest request;
  final List<YorksV1InventoryItem> inventory;
  final AppLanguage language;
  final Future<void> Function(List<CompanySupplyPlanChoice> choices) onSave;

  @override
  State<YorksV1CompanyArrangementWorkbench> createState() =>
      _YorksV1CompanyArrangementWorkbenchState();
}

class _YorksV1CompanyArrangementWorkbenchState
    extends State<YorksV1CompanyArrangementWorkbench> {
  late final List<YorksV1CompanyMaterialRequestLine> _outstanding;
  late final Map<String, _PlanLine> _drafts;
  final _scroll = ScrollController();
  bool _busy = false;
  bool _dirty = false;
  bool _allowPop = false;
  bool _closing = false;
  bool _review = false;
  _MobileStage _mobileStage = _MobileStage.lines;
  int _mobileLineIndex = 0;
  String? _saveError;
  Set<String> _issues = {};

  @override
  void initState() {
    super.initState();
    _outstanding = widget.request.lines
        .where((line) {
          final qty = YorksV1DecimalQuantity.tryParse(
            line.withdrawableQuantity,
          );
          return qty != null && qty.isPositive;
        })
        .toList(growable: false);
    final saved = widget.request.currentSupplyPlan?['lines'];
    final savedByLine = <String, Map<String, dynamic>>{
      if (saved is List)
        for (final value in saved)
          if (value is Map && value['request_line_id'] != null)
            value['request_line_id'].toString(): Map<String, dynamic>.from(
              value,
            ),
    };
    _drafts = {
      for (final line in _outstanding)
        line.id: _PlanLine(
          line: line,
          saved: savedByLine[line.id],
          inventory: widget.inventory,
        ),
    };
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _issues = {};
    _saveError = null;
  });

  Future<void> _close() async {
    if (_busy || _closing) return;
    _closing = true;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            YorksV1ArrangementStrings.arrangement.active(widget.language),
          ),
          content: Text(
            YorksV1CompanyMaterialRequestStrings.unsavedArrangement.active(
              widget.language,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                YorksV1CompanyMaterialRequestStrings.keepEditing.active(
                  widget.language,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                YorksV1CompanyMaterialRequestStrings.discardChanges.active(
                  widget.language,
                ),
              ),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) {
        _closing = false;
        return;
      }
    }
    _dismiss();
  }

  void _dismiss() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_busy || _outstanding.isEmpty) return;
    final issues = <String>{};
    final choices = <CompanySupplyPlanChoice>[];
    for (final line in _outstanding) {
      final draft = _drafts[line.id]!;
      final choice = draft.choice;
      if (choice == null) {
        issues.add(line.id);
      } else {
        choices.add(choice);
      }
    }
    if (issues.isNotEmpty) {
      setState(() {
        _review = false;
        _issues = issues;
        _mobileStage = _MobileStage.lines;
      });
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!_review) {
      setState(() {
        _review = true;
        _mobileStage = _MobileStage.review;
      });
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() {
      _busy = true;
      _saveError = null;
    });
    try {
      await widget.onSave(choices);
      if (mounted) _dismiss();
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = YorksV1CompanyMaterialRequestStrings.actionFailed
              .active(widget.language),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;
    final phone = width <= 720;
    final counts = [
      _drafts.values.where((d) => d.decision == 'full').length,
      _drafts.values.where((d) => d.decision == 'partial').length,
      _drafts.values.where((d) => d.decision == 'unavailable').length,
      _drafts.values
          .where(
            (d) =>
                d.source == 'external_supplier' && d.decision != 'unavailable',
          )
          .length,
    ];
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && !_closing) _close();
      },
      child: Dialog(
        insetPadding: EdgeInsets.all(compact ? 0 : AppSpacing.xl),
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            compact ? 0 : AppSpacing.radiusLg,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1420,
            maxHeight: MediaQuery.sizeOf(context).height - (compact ? 0 : 40),
          ),
          child: Column(
            children: [
              _header(compact, phone),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.all(
                    compact ? AppSpacing.md : AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (phone && _mobileStage == _MobileStage.lines) ...[
                        _mobileList(counts),
                      ] else if (phone &&
                          _mobileStage == _MobileStage.line) ...[
                        _lineCard(_outstanding[_mobileLineIndex]),
                      ] else ...[
                        if (_review) ...[
                          _reviewPanel(counts),
                          const SizedBox(height: AppSpacing.lg),
                        ] else ...[
                          _overview(counts),
                          const SizedBox(height: AppSpacing.md),
                          _guidance(),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (_issues.isNotEmpty) ...[
                          _validationSummary(),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (_saveError != null) ...[
                          Text(
                            _saveError!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (compact)
                          for (final line in _outstanding) ...[
                            _lineCard(line),
                            const SizedBox(height: AppSpacing.md),
                          ]
                        else
                          _table(),
                      ],
                    ],
                  ),
                ),
              ),
              _footer(phone),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool compact, bool phone) => Container(
    padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(Icons.inventory_2_outlined, color: AppColors.blue),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phone
                    ? widget.request.requestNumber ??
                          YorksV1CompanyMaterialRequestStrings.arrangeItems
                              .active(widget.language)
                    : YorksV1ArrangementStrings.arrangeMaterialRequest.active(
                        widget.language,
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                phone
                    ? widget.request.responsibleUnitName
                    : '${widget.request.requestNumber ?? ''} · ${widget.request.responsibleUnitName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _busy ? null : _close,
          tooltip: YorksV1MaterialRequestStrings.cancel.active(widget.language),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _overview(List<int> counts) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      _count(
        YorksV1CompanyMaterialRequestStrings.full.active(widget.language),
        counts[0],
        AppColors.success,
      ),
      _count(
        YorksV1CompanyMaterialRequestStrings.partial.active(widget.language),
        counts[1],
        AppColors.warning,
      ),
      _count(
        YorksV1CompanyMaterialRequestStrings.cannotProvideNow.active(
          widget.language,
        ),
        counts[2],
        AppColors.error,
      ),
      _count(
        YorksV1ArrangementStrings.externalSupplier.active(widget.language),
        counts[3],
        AppColors.tertiary,
      ),
    ],
  );

  Widget _count(String label, int value, Color color) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTypography.labelSmall),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$value',
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _guidance() => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .42),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        const Icon(Icons.verified_user_outlined, color: AppColors.blue),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            YorksV1ArrangementStrings.approvalReleasesArranged.active(
              widget.language,
            ),
            style: AppTypography.bodySmall,
          ),
        ),
      ],
    ),
  );

  Widget _validationSummary() => Container(
    key: const ValueKey('company-arrangement-validation'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.errorContainer.withValues(alpha: .42),
      border: Border.all(color: AppColors.error.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            YorksV1ArrangementStrings.rowsNeedAttention(
              _issues.length,
            ).active(widget.language),
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mobileList(List<int> counts) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        YorksV1ArrangementStrings.arrangeRequestedItems.active(widget.language),
        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        YorksV1ArrangementStrings.decideEveryLine.active(widget.language),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.md),
      _overview(counts),
      if (_issues.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _validationSummary(),
      ],
      const SizedBox(height: AppSpacing.md),
      for (var index = 0; index < _outstanding.length; index++) ...[
        Builder(
          builder: (context) {
            final line = _outstanding[index];
            final draft = _drafts[line.id]!;
            final valid = draft.choice != null;
            return Card(
              color: _issues.contains(line.id)
                  ? AppColors.errorContainer
                  : AppColors.surfaceContainerLowest,
              child: InkWell(
                key: ValueKey('company-arrangement-mobile-line-${line.id}'),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                onTap: () => setState(() {
                  _mobileLineIndex = index;
                  _mobileStage = _MobileStage.line;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: valid
                            ? AppColors.successContainer
                            : AppColors.blueContainer,
                        child: Icon(
                          valid ? Icons.check_rounded : Icons.edit_outlined,
                          size: 19,
                          color: valid ? AppColors.success : AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.description,
                              style: AppTypography.labelLarge.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${line.withdrawableQuantity} ${line.unit} · ${_decisionLabel(draft.decision)}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            if (!valid)
                              Text(
                                YorksV1CompanyMaterialRequestStrings.notReviewed
                                    .active(widget.language),
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );

  String _decisionLabel(String decision) => switch (decision) {
    'partial' => YorksV1CompanyMaterialRequestStrings.partial.active(
      widget.language,
    ),
    'unavailable' =>
      YorksV1CompanyMaterialRequestStrings.cannotProvideNow.active(
        widget.language,
      ),
    _ => YorksV1CompanyMaterialRequestStrings.full.active(widget.language),
  };

  Widget _table() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: constraints.maxWidth < 1060 ? 1060 : constraints.maxWidth,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            children: [
              Container(
                color: AppColors.surfaceContainerLow,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    _heading(
                      YorksV1ArrangementStrings.requestedItem.active(
                        widget.language,
                      ),
                      30,
                    ),
                    _heading(
                      YorksV1ArrangementStrings.decision.active(
                        widget.language,
                      ),
                      17,
                    ),
                    _heading(
                      YorksV1ArrangementStrings.supplierSource.active(
                        widget.language,
                      ),
                      28,
                    ),
                    _heading(
                      YorksV1ArrangementStrings.requested.active(
                        widget.language,
                      ),
                      12,
                    ),
                    _heading(
                      YorksV1ArrangementStrings.arranged.active(
                        widget.language,
                      ),
                      13,
                    ),
                  ],
                ),
              ),
              for (final line in _outstanding) _lineRow(line),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _heading(String label, int flex) => Expanded(
    flex: flex,
    child: Text(
      label.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
      ),
    ),
  );

  Widget _lineRow(YorksV1CompanyMaterialRequestLine line) {
    final draft = _drafts[line.id]!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _rowColor(draft),
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 30, child: _item(line)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 17, child: _decision(draft)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 28, child: _source(draft)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 12,
                child: Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    '${line.withdrawableQuantity} ${line.unit}',
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 13, child: _quantity(draft)),
            ],
          ),
          if (draft.decision != 'full') ...[
            const SizedBox(height: AppSpacing.sm),
            _reasonAndFollowUp(draft),
          ],
          if (_issues.contains(line.id)) ...[
            const SizedBox(height: AppSpacing.sm),
            _lineIssue(),
          ],
        ],
      ),
    );
  }

  Widget _lineCard(YorksV1CompanyMaterialRequestLine line) {
    final draft = _drafts[line.id]!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _rowColor(draft),
        border: Border.all(
          color: _issues.contains(line.id) ? AppColors.error : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _item(line),
          const SizedBox(height: AppSpacing.md),
          _decision(draft),
          const SizedBox(height: AppSpacing.md),
          if (draft.decision != 'unavailable') ...[
            _source(draft),
            const SizedBox(height: AppSpacing.md),
            _quantity(draft),
            const SizedBox(height: AppSpacing.md),
          ],
          if (draft.decision != 'full') _reasonAndFollowUp(draft),
          if (_issues.contains(line.id)) ...[
            const SizedBox(height: AppSpacing.sm),
            _lineIssue(),
          ],
        ],
      ),
    );
  }

  Color _rowColor(_PlanLine draft) => switch (draft.decision) {
    'partial' => AppColors.warningContainer.withValues(alpha: .32),
    'unavailable' => AppColors.errorContainer.withValues(alpha: .28),
    _ => AppColors.surfaceContainerLowest,
  };

  Widget _item(YorksV1CompanyMaterialRequestLine line) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        line.description,
        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
      ),
      if (line.brandOrigin?.isNotEmpty == true ||
          line.size?.isNotEmpty == true ||
          line.model?.isNotEmpty == true)
        Text(
          [
            line.size,
            line.model,
            line.brandOrigin,
          ].where((part) => part?.isNotEmpty == true).join(' · '),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
    ],
  );

  Widget _decision(_PlanLine draft) => DropdownButtonFormField<String>(
    key: ValueKey('company-arrangement-decision-${draft.line.id}'),
    initialValue: draft.decision,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: YorksV1ArrangementStrings.decision.active(widget.language),
    ),
    items: [
      DropdownMenuItem(
        value: 'full',
        child: Text(
          YorksV1CompanyMaterialRequestStrings.full.active(widget.language),
        ),
      ),
      DropdownMenuItem(
        value: 'partial',
        child: Text(
          YorksV1CompanyMaterialRequestStrings.partial.active(widget.language),
        ),
      ),
      DropdownMenuItem(
        value: 'unavailable',
        child: Text(
          YorksV1CompanyMaterialRequestStrings.cannotProvideNow.active(
            widget.language,
          ),
        ),
      ),
    ],
    onChanged: _busy
        ? null
        : (value) {
            if (value == null) return;
            draft.decision = value;
            draft.quantity.text = value == 'unavailable'
                ? '0'
                : draft.line.withdrawableQuantity;
            _changed();
          },
  );

  Widget _source(_PlanLine draft) {
    if (draft.decision == 'unavailable') {
      return Text(
        YorksV1ArrangementStrings.noSourceRequired.active(widget.language),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    final matches = widget.inventory
        .where(
          (item) => item.unit.toLowerCase() == draft.line.unit.toLowerCase(),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('company-arrangement-source-${draft.line.id}'),
          initialValue: draft.source,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: YorksV1ArrangementStrings.supplierSource.active(
              widget.language,
            ),
          ),
          items: [
            DropdownMenuItem(
              value: 'warehouse',
              child: Text(
                YorksV1CompanyMaterialRequestStrings.warehouseSource.active(
                  widget.language,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'external_supplier',
              child: Text(
                YorksV1CompanyMaterialRequestStrings.externalSource.active(
                  widget.language,
                ),
              ),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  draft.source = value;
                  _changed();
                },
        ),
        const SizedBox(height: AppSpacing.xs),
        if (draft.source == 'warehouse')
          DropdownMenu<String>(
            key: ValueKey('company-arrangement-stock-${draft.line.id}'),
            controller: draft.stockSearch,
            initialSelection: draft.inventoryItemId,
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            menuHeight: 260,
            label: Text(
              YorksV1CompanyMaterialRequestStrings.chooseInventory.active(
                widget.language,
              ),
            ),
            dropdownMenuEntries: [
              for (final item in matches)
                DropdownMenuEntry(
                  value: item.id,
                  label: _stockLabel(item),
                  labelWidget: Text(
                    _stockLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onSelected: _busy
                ? null
                : (value) {
                    draft.inventoryItemId = value;
                    _changed();
                  },
          )
        else
          TextField(
            key: ValueKey('company-arrangement-supplier-${draft.line.id}'),
            controller: draft.supplier,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: YorksV1CompanyMaterialRequestStrings.externalSource
                  .active(widget.language),
            ),
            onChanged: (_) => _changed(),
          ),
      ],
    );
  }

  Widget _quantity(_PlanLine draft) => draft.decision == 'unavailable'
      ? const SizedBox.shrink()
      : TextField(
          key: ValueKey('company-arrangement-quantity-${draft.line.id}'),
          controller: draft.quantity,
          enabled: !_busy && draft.decision == 'partial',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: YorksV1ArrangementStrings.arranged.active(
              widget.language,
            ),
            suffixText: draft.line.unit,
          ),
          onChanged: (_) => _changed(),
        );

  Widget _reasonAndFollowUp(_PlanLine draft) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      SizedBox(
        width: 300,
        child: TextField(
          key: ValueKey('company-arrangement-reason-${draft.line.id}'),
          controller: draft.reason,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: YorksV1CompanyMaterialRequestStrings.reasonRequired
                .active(widget.language),
          ),
          onChanged: (_) => _changed(),
        ),
      ),
      if (draft.decision == 'unavailable')
        OutlinedButton.icon(
          key: ValueKey('company-arrangement-follow-up-${draft.line.id}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTapTarget),
          ),
          onPressed: _busy
              ? null
              : () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate:
                        draft.followUp != null &&
                            !draft.followUp!.isBefore(today)
                        ? draft.followUp!
                        : today,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 3650)),
                  );
                  if (chosen != null) {
                    draft.followUp = chosen;
                    _changed();
                  }
                },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            draft.followUp == null
                ? YorksV1CompanyMaterialRequestStrings.followUpDate.active(
                    widget.language,
                  )
                : MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(draft.followUp!),
          ),
        ),
    ],
  );

  Widget _lineIssue() => Text(
    YorksV1CompanyMaterialRequestStrings.checkLine.active(widget.language),
    style: AppTypography.bodySmall.copyWith(
      color: AppColors.error,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _reviewPanel(List<int> counts) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .35),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1ArrangementStrings.arrangementReview.active(widget.language),
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          YorksV1ArrangementStrings.approvalReleasesArranged.active(
            widget.language,
          ),
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        _overview(counts),
      ],
    ),
  );

  Widget _footer(bool phone) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: AppSpacing.sm,
      overflowSpacing: AppSpacing.sm,
      children: [
        if (_busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTapTarget),
          ),
          onPressed: _busy
              ? null
              : phone && _mobileStage == _MobileStage.line
              ? () => setState(() => _mobileStage = _MobileStage.lines)
              : _review
              ? () => setState(() {
                  _review = false;
                  _mobileStage = _MobileStage.lines;
                })
              : _close,
          child: Text(
            _review || phone && _mobileStage == _MobileStage.line
                ? YorksV1ArrangementStrings.previous.active(widget.language)
                : YorksV1MaterialRequestStrings.cancel.active(widget.language),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('company-arrangement-save'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTapTarget),
          ),
          onPressed: _busy || _outstanding.isEmpty
              ? null
              : phone && _mobileStage == _MobileStage.line
              ? _nextMobileLine
              : _save,
          icon: Icon(
            _review
                ? Icons.check_rounded
                : phone && _mobileStage == _MobileStage.line
                ? Icons.arrow_forward_rounded
                : Icons.rate_review_outlined,
          ),
          label: Text(
            _review
                ? YorksV1CompanyMaterialRequestStrings.saveSupplyPlan.active(
                    widget.language,
                  )
                : phone && _mobileStage == _MobileStage.line
                ? YorksV1ArrangementStrings.saveAndNext.active(widget.language)
                : YorksV1CompanyMaterialRequestStrings.reviewItems.active(
                    widget.language,
                  ),
          ),
        ),
      ],
    ),
  );

  void _nextMobileLine() => setState(() {
    if (_mobileLineIndex + 1 < _outstanding.length) {
      _mobileLineIndex++;
    } else {
      _mobileStage = _MobileStage.lines;
    }
  });
}

class _PlanLine {
  _PlanLine({
    required this.line,
    required Map<String, dynamic>? saved,
    required List<YorksV1InventoryItem> inventory,
  }) : decision = saved?['decision']?.toString() ?? 'full',
       source = saved?['source_kind']?.toString() == 'external_supplier'
           ? 'external_supplier'
           : 'warehouse',
       inventoryItemId = saved?['inventory_item_id']?.toString(),
       followUp = DateTime.tryParse(saved?['follow_up_date']?.toString() ?? ''),
       quantity = TextEditingController(
         text: saved?['arranged_qty']?.toString() ?? line.withdrawableQuantity,
       ),
       supplier = TextEditingController(
         text: saved?['external_supplier']?.toString() ?? '',
       ),
       reason = TextEditingController(
         text: saved?['reason']?.toString() ?? '',
       ) {
    final selected = inventory
        .where((item) => item.id == inventoryItemId)
        .firstOrNull;
    stockSearch = TextEditingController(
      text: selected == null ? '' : _stockLabel(selected),
    );
    stockSearch.addListener(() {
      final current = inventory
          .where((item) => item.id == inventoryItemId)
          .firstOrNull;
      if (current != null && stockSearch.text != _stockLabel(current)) {
        inventoryItemId = null;
      }
    });
  }

  final YorksV1CompanyMaterialRequestLine line;
  String decision;
  String source;
  String? inventoryItemId;
  DateTime? followUp;
  final TextEditingController quantity;
  late final TextEditingController stockSearch;
  final TextEditingController supplier;
  final TextEditingController reason;

  CompanySupplyPlanChoice? get choice {
    final maximum = YorksV1DecimalQuantity.tryParse(line.withdrawableQuantity);
    final amount = YorksV1DecimalQuantity.tryParse(quantity.text.trim());
    if (maximum == null ||
        amount == null ||
        amount.isNegative ||
        amount.compareTo(maximum) > 0) {
      return null;
    }
    final explanation = reason.text.trim();
    if (decision == 'full' && amount != maximum) return null;
    if (decision == 'partial' &&
        (!amount.isPositive ||
            amount.compareTo(maximum) >= 0 ||
            explanation.isEmpty)) {
      return null;
    }
    if (decision == 'unavailable' &&
        (!amount.isZero ||
            explanation.isEmpty ||
            followUp == null ||
            followUp!.isBefore(DateUtils.dateOnly(DateTime.now())))) {
      return null;
    }
    if (decision != 'full' &&
        decision != 'partial' &&
        decision != 'unavailable') {
      return null;
    }
    if (decision != 'unavailable' &&
        ((source == 'warehouse' && inventoryItemId == null) ||
            (source == 'external_supplier' && supplier.text.trim().isEmpty))) {
      return null;
    }
    return CompanySupplyPlanChoice(
      decision: decision,
      quantity: decision == 'unavailable' ? '0' : amount.canonicalText,
      inventoryItemId: decision != 'unavailable' && source == 'warehouse'
          ? inventoryItemId
          : null,
      externalSupplier:
          decision != 'unavailable' && source == 'external_supplier'
          ? supplier.text.trim()
          : null,
      reason: decision == 'full' ? null : explanation,
      followUpDate: decision == 'unavailable'
          ? '${followUp!.year.toString().padLeft(4, '0')}-${followUp!.month.toString().padLeft(2, '0')}-${followUp!.day.toString().padLeft(2, '0')}'
          : null,
    );
  }

  void dispose() {
    quantity.dispose();
    stockSearch.dispose();
    supplier.dispose();
    reason.dispose();
  }
}

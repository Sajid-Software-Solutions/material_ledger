import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/controllers/yorks_v1_material_line_editor.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_return_candidates.dart';
import '../../../../shared/models/yorks_v1_material_return_composer_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_workflow.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../screens/yorks_v1_material_request_screens.dart'
    show YorksV1MaterialDescriptionField, YorksV1MaterialItemsEditor;

typedef _Strings = YorksV1MaterialReturnComposerStrings;

/// One delivered material chosen for return. The quantity is allocated across
/// the material's deliveries newest first when the draft is saved.
class YorksV1ReturnSelection {
  YorksV1ReturnSelection({
    required this.key,
    required this.description,
    required this.unit,
    this.size,
    this.scopeId,
    YorksV1MaterialReturnItem? item,
    String quantity = '',
    String note = '',
  }) : _item = item,
       quantity = TextEditingController(text: quantity),
       note = TextEditingController(text: note);

  final String key;
  final String description;
  final String? size;
  final String unit;

  /// Building limit chosen in the picker; null means every building.
  final String? scopeId;
  final TextEditingController quantity;
  final TextEditingController note;
  YorksV1MaterialReturnItem? _item;

  /// Current availability, or null when the material is no longer returnable.
  YorksV1MaterialReturnItem? get item => _item;

  void dispose() {
    quantity.dispose();
    note.dispose();
  }
}

enum YorksV1ReturnSelectionIssue {
  quantityRequired,
  exceedsAvailable,
  unavailable,
}

/// Result of turning the composer into save-draft lines.
class YorksV1ReturnComposerLines {
  const YorksV1ReturnComposerLines({
    required this.lines,
    required this.hasIssues,
    required this.customIncomplete,
  });

  final List<YorksV1MaterialReturnDraftLineInput> lines;
  final bool hasIssues;
  final bool customIncomplete;
}

/// State of the Material Return composer: delivered selections plus custom
/// lines edited with the Material Request line editor.
class YorksV1ReturnComposerController extends ChangeNotifier
    implements YorksV1MaterialLineEditor {
  final _selections = <YorksV1ReturnSelection>[];
  var _customLines = <YorksV1MaterialRequestLine>[];
  YorksV1MaterialReturnItemCandidates? _resolvedFrom;
  bool _showIssues = false;

  List<YorksV1ReturnSelection> get selections => List.unmodifiable(_selections);
  List<YorksV1MaterialRequestLine> get customLines =>
      List.unmodifiable(_customLines);
  bool get isEmpty => _selections.isEmpty && _customLines.isEmpty;
  bool get isResolved => _resolvedFrom != null;

  /// Candidates the selections were last resolved against.
  YorksV1MaterialReturnItemCandidates? get resolvedFrom => _resolvedFrom;

  /// Highlight problems only after the user tried to save.
  bool get showIssues => _showIssues;

  bool contains(String key) => _selections.any((item) => item.key == key);

  void addItem(YorksV1MaterialReturnItem item, {String? scopeId}) {
    if (contains(item.key)) return;
    _selections.add(
      YorksV1ReturnSelection(
        key: item.key,
        description: item.description,
        size: item.size,
        unit: item.unit,
        scopeId: scopeId,
        item: yorksV1MaterialReturnItemForScope(item, scopeId),
      ),
    );
    notifyListeners();
  }

  void removeSelection(String key) {
    final index = _selections.indexWhere((item) => item.key == key);
    if (index < 0) return;
    _selections.removeAt(index).dispose();
    notifyListeners();
  }

  void clear() {
    for (final selection in _selections) {
      selection.dispose();
    }
    _selections.clear();
    _customLines = [];
    _resolvedFrom = null;
    _showIssues = false;
    notifyListeners();
  }

  /// Rebuilds the composer from saved draft lines. Delivered lines of the same
  /// material are merged back into one selection.
  void hydrate(List<YorksV1MaterialReturnLineRecord> lines) {
    final resolvedFrom = _resolvedFrom;
    for (final selection in _selections) {
      selection.dispose();
    }
    _selections.clear();
    _showIssues = false;
    final totals = <String, List<YorksV1MaterialReturnLineRecord>>{};
    final custom = <YorksV1MaterialRequestLine>[];
    for (final line in lines) {
      if (line.origin == YorksV1ReturnLineOrigin.delivered) {
        totals
            .putIfAbsent(
              yorksV1MaterialReturnItemKey(
                description: line.description,
                size: line.size,
                unit: line.unit,
              ),
              () => [],
            )
            .add(line);
      } else {
        custom.add(
          YorksV1MaterialRequestLine(
            id: const Uuid().v4(),
            displayOrder: custom.length + 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: line.description,
            quantity: yorksV1DisplayQuantity(line.returnQuantity),
            unit: line.unit,
            brandOrigin: line.brandOrigin,
            size: line.size,
            model: line.model,
            equipmentTag: line.equipmentTag,
          ),
        );
      }
    }
    for (final entry in totals.entries) {
      final first = entry.value.first;
      _selections.add(
        YorksV1ReturnSelection(
          key: entry.key,
          description: first.description,
          size: first.size,
          unit: first.unit,
          quantity: yorksV1SumQuantities(
            entry.value.map((line) => line.returnQuantity),
          ),
          note:
              entry.value
                  .map((line) => line.lineNote)
                  .whereType<String>()
                  .firstOrNull ??
              '',
        ),
      );
    }
    _customLines = custom;
    _resolvedFrom = null;
    if (resolvedFrom != null) {
      _apply(resolvedFrom);
    } else {
      notifyListeners();
    }
  }

  /// Attaches current availability to every selection.
  void resolve(YorksV1MaterialReturnItemCandidates candidates) {
    if (identical(_resolvedFrom, candidates)) return;
    _apply(candidates);
  }

  void _apply(YorksV1MaterialReturnItemCandidates candidates) {
    _resolvedFrom = candidates;
    for (final selection in _selections) {
      final item = candidates.itemForKey(selection.key);
      selection._item = item == null
          ? null
          : yorksV1MaterialReturnItemForScope(item, selection.scopeId);
    }
    notifyListeners();
  }

  YorksV1ReturnSelectionIssue? issueFor(YorksV1ReturnSelection selection) {
    final quantity = YorksV1DecimalQuantity.tryParse(selection.quantity.text);
    if (isResolved && selection.item == null) {
      return YorksV1ReturnSelectionIssue.unavailable;
    }
    if (quantity == null || !quantity.isPositive) {
      return YorksV1ReturnSelectionIssue.quantityRequired;
    }
    final available = YorksV1DecimalQuantity.tryParse(
      selection.item?.returnableQuantity ?? '',
    );
    if (available != null && quantity.compareTo(available) > 0) {
      return YorksV1ReturnSelectionIssue.exceedsAvailable;
    }
    return null;
  }

  List<YorksV1ReturnAllocation>? allocationFor(
    YorksV1ReturnSelection selection,
  ) {
    final item = selection.item;
    if (item == null) return null;
    return yorksV1AllocateReturnQuantity(item.sources, selection.quantity.text);
  }

  YorksV1ReturnComposerLines buildLines() {
    final lines = <YorksV1MaterialReturnDraftLineInput>[];
    var hasIssues = false;
    for (final selection in _selections) {
      final allocation = issueFor(selection) == null
          ? allocationFor(selection)
          : null;
      if (allocation == null) {
        hasIssues = true;
        continue;
      }
      final note = selection.note.text.trim();
      for (final slice in allocation) {
        lines.add(
          YorksV1MaterialReturnDraftLineInput(
            origin: YorksV1ReturnLineOrigin.delivered,
            dispatchLineId: slice.source.dispatchLineId,
            receiptReviewLineId: slice.source.receiptReviewLineId,
            quantity: slice.quantity,
            note: note.isEmpty ? null : note,
          ),
        );
      }
    }
    var customIncomplete = false;
    for (final line in _customLines) {
      final quantity = YorksV1DecimalQuantity.tryParse(line.quantity);
      final blank =
          line.description.trim().isEmpty && line.quantity.trim().isEmpty;
      if (blank) continue;
      if (line.description.trim().isEmpty ||
          line.unit.trim().isEmpty ||
          quantity == null ||
          !quantity.isPositive) {
        customIncomplete = true;
        continue;
      }
      lines.add(
        YorksV1MaterialReturnDraftLineInput(
          origin: YorksV1ReturnLineOrigin.custom,
          description: line.description,
          brandOrigin: line.brandOrigin,
          unit: line.unit,
          size: line.size,
          model: line.model,
          equipmentTag: line.equipmentTag,
          quantity: quantity.canonicalText,
        ),
      );
    }
    if (hasIssues || customIncomplete) {
      _showIssues = true;
      notifyListeners();
    }
    return YorksV1ReturnComposerLines(
      lines: lines,
      hasIssues: hasIssues,
      customIncomplete: customIncomplete,
    );
  }

  // Material Request line editor commands for custom lines.

  @override
  Future<void> updateLine(
    String lineId,
    YorksV1MaterialRequestLine Function(YorksV1MaterialRequestLine) transform,
  ) async {
    _customLines = [
      for (final line in _customLines)
        if (line.id == lineId) transform(line) else line,
    ];
    notifyListeners();
  }

  @override
  Future<void> addCustomLine({String? afterLineId}) async =>
      _insertAfter(afterLineId, null);

  @override
  Future<void> addSimilarLine({String? afterLineId}) async {
    final source = _customLines
        .where((line) => line.id == afterLineId)
        .firstOrNull;
    if (source != null) _insertAfter(afterLineId, source);
  }

  @override
  Future<void> removeLine(String lineId) async {
    _customLines = _renumber(
      _customLines.where((line) => line.id != lineId).toList(),
    );
    notifyListeners();
  }

  void _insertAfter(String? afterLineId, YorksV1MaterialRequestLine? copy) {
    final index = afterLineId == null
        ? _customLines.length - 1
        : _customLines.indexWhere((line) => line.id == afterLineId);
    final next = [..._customLines]
      ..insert(
        index + 1,
        YorksV1MaterialRequestLine(
          id: const Uuid().v4(),
          displayOrder: 0,
          source: YorksV1MaterialRequestLineSource.custom,
          description: copy?.description ?? '',
          quantity: '',
          unit: copy?.unit ?? '',
          brandOrigin: copy?.brandOrigin,
          size: copy?.size,
          model: copy?.model,
          equipmentTag: copy?.equipmentTag,
        ),
      );
    _customLines = _renumber(next);
    notifyListeners();
  }

  static List<YorksV1MaterialRequestLine> _renumber(
    List<YorksV1MaterialRequestLine> lines,
  ) => [
    for (var i = 0; i < lines.length; i++)
      YorksV1MaterialRequestLine(
        id: lines[i].id,
        displayOrder: i + 1,
        source: lines[i].source,
        description: lines[i].description,
        quantity: lines[i].quantity,
        unit: lines[i].unit,
        brandOrigin: lines[i].brandOrigin,
        size: lines[i].size,
        model: lines[i].model,
        equipmentTag: lines[i].equipmentTag,
      ),
  ];

  @override
  void dispose() {
    for (final selection in _selections) {
      selection.dispose();
    }
    super.dispose();
  }
}

/// Search-first composer for a project-wide Material Return.
class YorksV1MaterialReturnComposer extends ConsumerStatefulWidget {
  const YorksV1MaterialReturnComposer({
    super.key,
    required this.projectId,
    required this.scopes,
    required this.controller,
    required this.language,
    required this.enabled,
    this.returnId,
    this.scopeId,
  });

  final String projectId;
  final String? returnId;

  /// Building the return is raised from; used for the custom-line autocomplete
  /// and the optional "only this building" filter.
  final String? scopeId;
  final List<YorksV1MaterialReturnScope> scopes;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;

  @override
  ConsumerState<YorksV1MaterialReturnComposer> createState() =>
      _YorksV1MaterialReturnComposerState();
}

class _YorksV1MaterialReturnComposerState
    extends ConsumerState<YorksV1MaterialReturnComposer> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _serverSearch;
  bool _onlyBuilding = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final normalized = value.trim();
      setState(
        () => _serverSearch = normalized.length >= 3 ? normalized : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final baseQuery = YorksV1MaterialReturnCandidatesQuery(
      projectId: widget.projectId,
      returnId: widget.returnId,
    );
    final base = ref.watch(
      yorksV1MaterialReturnItemCandidatesProvider(baseQuery),
    );
    final serverSearch = _serverSearch;
    final searched = serverSearch == null
        ? null
        : ref.watch(
            yorksV1MaterialReturnItemCandidatesProvider(
              YorksV1MaterialReturnCandidatesQuery(
                projectId: widget.projectId,
                returnId: widget.returnId,
                search: serverSearch,
              ),
            ),
          );
    if (base case AsyncData(
      :final value,
    ) when !identical(value, widget.controller.resolvedFrom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.resolve(value);
      });
    }
    final scopeFilter = _onlyBuilding ? widget.scopeId : null;
    final scopeName = widget.scopes
        .where((scope) => scope.id == widget.scopeId)
        .firstOrNull
        ?.name;
    return Container(
      key: const ValueKey('material-return-composer'),
      decoration: _panel,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _Strings.materialToReturn.active(language),
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _Strings.materialToReturnHint.active(language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('material-return-search'),
            controller: _search,
            enabled: widget.enabled,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: _Strings.searchDelivered.active(language),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _Strings.remove.active(language),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
          ),
          if (scopeName != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  key: const ValueKey('material-return-all-buildings'),
                  label: Text(_Strings.allBuildings.active(language)),
                  selected: !_onlyBuilding,
                  onSelected: (_) => setState(() => _onlyBuilding = false),
                ),
                ChoiceChip(
                  key: const ValueKey('material-return-only-building'),
                  label: Text(
                    _Strings.onlyBuilding(scopeName).active(language),
                  ),
                  selected: _onlyBuilding,
                  onSelected: (_) => setState(() => _onlyBuilding = true),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          base.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, _) => _Notice(
              icon: Icons.cloud_off_rounded,
              text: _Strings.loadFailed.active(language),
              action: TextButton(
                key: const ValueKey('material-return-candidates-retry'),
                onPressed: () => ref.invalidate(
                  yorksV1MaterialReturnItemCandidatesProvider(baseQuery),
                ),
                child: Text(_Strings.retry.active(language)),
              ),
            ),
            data: (all) => _results(
              all,
              searched?.valueOrNull,
              searching: searched?.isLoading == true,
              scopeId: scopeFilter,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _SelectedMaterials(
              controller: widget.controller,
              language: language,
              enabled: widget.enabled,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _CustomItems(
              controller: widget.controller,
              language: language,
              enabled: widget.enabled,
              projectId: widget.projectId,
              scopeId: widget.scopeId,
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(
    YorksV1MaterialReturnItemCandidates all,
    YorksV1MaterialReturnItemCandidates? searched, {
    required bool searching,
    required String? scopeId,
  }) {
    final language = widget.language;
    if (all.items.isEmpty) {
      return _Notice(
        icon: Icons.inventory_2_outlined,
        text: _Strings.noDelivered.active(language),
      );
    }
    final text = _search.text;
    final seen = <String>{};
    final items = <YorksV1MaterialReturnItem>[];
    void addItem(YorksV1MaterialReturnItem item) {
      final scoped = yorksV1MaterialReturnItemForScope(item, scopeId);
      if (scoped.sources.isEmpty || !seen.add(scoped.key)) return;
      items.add(scoped);
    }

    for (final item in all.items) {
      if (yorksV1MaterialReturnItemMatches(item, text)) addItem(item);
    }
    // Close spellings found by the server's trigram search follow the exact
    // matches, so "coper pipe" still reaches "Copper Pipe".
    if (searched != null && text.trim().isNotEmpty) {
      for (final item in searched.items) {
        addItem(all.itemForKey(item.key) ?? item);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (searching) const LinearProgressIndicator(minHeight: 2),
        if (items.isEmpty)
          _Notice(
            icon: Icons.search_off_rounded,
            text: searching
                ? _Strings.searching.active(language)
                : _Strings.noMatches.active(language),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => ListView.separated(
                  key: const ValueKey('material-return-results'),
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _CandidateTile(
                      item: item,
                      language: language,
                      added: widget.controller.contains(item.key),
                      onAdd: widget.enabled
                          ? () => widget.controller.addItem(
                              item,
                              scopeId: scopeId,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.item,
    required this.language,
    required this.added,
    required this.onAdd,
  });

  final YorksV1MaterialReturnItem item;
  final AppLanguage language;
  final bool added;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final requests = {
      for (final source in item.sources) source.requestNumber,
    }.toList(growable: false);
    return InkWell(
      key: ValueKey('material-return-candidate-${item.key}'),
      onTap: added ? null : onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    style: AppTypography.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      if (item.size != null)
                        _Tag('${_Strings.size.active(language)} ${item.size}'),
                      for (final model in item.models.take(2))
                        _Tag('${_Strings.model.active(language)} $model'),
                      for (final code in item.itemCodes.take(2)) _Tag(code),
                      for (final brand in item.brandOrigins.take(2))
                        _Tag(brand),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    requests.length > 2
                        ? '${requests.take(2).join(' · ')} +${requests.length - 2}'
                        : requests.join(' · '),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _Strings.returnable(
                    yorksV1DisplayQuantity(item.returnableQuantity),
                    item.unit,
                  ).active(language),
                  style: AppTypography.labelLarge,
                ),
                if (item.hasUnconfirmed)
                  Text(
                    _Strings.unconfirmedPart(
                      yorksV1DisplayQuantity(
                        item.unconfirmedReturnableQuantity,
                      ),
                    ).active(language),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onWarningContainer,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                added
                    ? Chip(
                        avatar: const Icon(Icons.check_rounded, size: 16),
                        label: Text(_Strings.added.active(language)),
                        visualDensity: VisualDensity.compact,
                      )
                    : FilledButton.tonalIcon(
                        key: ValueKey('material-return-add-${item.key}'),
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(_Strings.add.active(language)),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedMaterials extends StatelessWidget {
  const _SelectedMaterials({
    required this.controller,
    required this.language,
    required this.enabled,
  });

  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selections = controller.selections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selections.isEmpty
              ? _Strings.nothingSelected.active(language)
              : _Strings.selectedCount(selections.length).active(language),
          style: selections.isEmpty
              ? AppTypography.bodyMedium.copyWith(color: AppColors.muted)
              : AppTypography.titleMedium,
        ),
        for (final selection in selections) ...[
          const SizedBox(height: AppSpacing.sm),
          _SelectedMaterialRow(
            key: ValueKey('material-return-selected-${selection.key}'),
            selection: selection,
            controller: controller,
            language: language,
            enabled: enabled,
          ),
        ],
      ],
    );
  }
}

class _SelectedMaterialRow extends StatelessWidget {
  const _SelectedMaterialRow({
    super.key,
    required this.selection,
    required this.controller,
    required this.language,
    required this.enabled,
  });

  final YorksV1ReturnSelection selection;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: selection.quantity,
        builder: (context, _, _) {
          final item = selection.item;
          final issue = controller.issueFor(selection);
          final visibleIssue =
              issue == YorksV1ReturnSelectionIssue.unavailable ||
                  issue == YorksV1ReturnSelectionIssue.exceedsAvailable ||
                  (controller.showIssues && issue != null)
              ? issue
              : null;
          final allocation = issue == null
              ? controller.allocationFor(selection)
              : null;
          final errorText = switch (visibleIssue) {
            YorksV1ReturnSelectionIssue.quantityRequired =>
              _Strings.quantityRequired.active(language),
            YorksV1ReturnSelectionIssue.exceedsAvailable =>
              _Strings.exceedsAvailable(
                yorksV1DisplayQuantity(item?.returnableQuantity ?? '0'),
              ).active(language),
            YorksV1ReturnSelectionIssue.unavailable =>
              _Strings.noLongerAvailable.active(language),
            null => null,
          };
          final quantityField = TextField(
            key: ValueKey('material-return-qty-${selection.key}'),
            controller: selection.quantity,
            enabled: enabled && item != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            decoration: InputDecoration(
              labelText: _Strings.returnQuantity.active(language),
              suffixText: selection.unit,
              errorText: errorText,
              errorMaxLines: 2,
              helperText: item == null
                  ? null
                  : _Strings.available(
                      yorksV1DisplayQuantity(item.returnableQuantity),
                      item.unit,
                    ).active(language),
            ),
          );
          final noteField = TextField(
            controller: selection.note,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: _Strings.lineNote.active(language),
            ),
          );
          final remove = IconButton(
            key: ValueKey('material-return-remove-${selection.key}'),
            tooltip: _Strings.remove.active(language),
            onPressed: enabled
                ? () => controller.removeSelection(selection.key)
                : null,
            icon: const Icon(Icons.close_rounded, color: AppColors.error),
          );
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selection.description, style: AppTypography.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (selection.size != null)
                    _Tag('${_Strings.size.active(language)} ${selection.size}'),
                  for (final model in item?.models ?? const <String>[])
                    _Tag('${_Strings.model.active(language)} $model'),
                  for (final tag in item?.equipmentTags ?? const <String>[])
                    _Tag('${_Strings.equipmentTag.active(language)} $tag'),
                  for (final code in item?.itemCodes ?? const <String>[])
                    _Tag(code),
                ],
              ),
            ],
          );
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: visibleIssue == null ? AppColors.line : AppColors.error,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: heading),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 190, child: quantityField),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(flex: 3, child: noteField),
                          remove,
                        ],
                      )
                    else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: heading),
                          remove,
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      quantityField,
                      const SizedBox(height: AppSpacing.sm),
                      noteField,
                    ],
                    if (allocation != null && allocation.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _AllocationPreview(
                        allocation: allocation,
                        language: language,
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      );
}

class _AllocationPreview extends StatelessWidget {
  const _AllocationPreview({required this.allocation, required this.language});

  final List<YorksV1ReturnAllocation> allocation;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _Strings.deliveries.active(language),
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final slice in allocation)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  slice.source.isUnconfirmed
                      ? Icons.local_shipping_outlined
                      : Icons.verified_outlined,
                  size: 16,
                  color: slice.source.isUnconfirmed
                      ? AppColors.onWarningContainer
                      : AppColors.success,
                ),
                Text(
                  [
                    slice.source.requestNumber,
                    slice.source.dispatchNumber,
                    if (slice.source.deliveredAt != null)
                      dateFormat.format(slice.source.deliveredAt!.toLocal()),
                  ].join(' · '),
                  style: AppTypography.bodySmall,
                ),
                Text(
                  _Strings.takes(
                    yorksV1DisplayQuantity(slice.quantity),
                    yorksV1DisplayQuantity(slice.source.returnableQuantity),
                  ).active(language),
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (slice.source.isUnconfirmed)
                  Text(
                    _Strings.unconfirmedDelivery.active(language),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onWarningContainer,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CustomItems extends StatelessWidget {
  const _CustomItems({
    required this.controller,
    required this.language,
    required this.enabled,
    required this.projectId,
    required this.scopeId,
  });

  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;
  final String projectId;
  final String? scopeId;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _Strings.itemsNotDelivered.active(language),
                  style: AppTypography.titleMedium,
                ),
                Text(
                  _Strings.itemsNotDeliveredHint.active(language),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('material-return-add-custom'),
            onPressed: enabled ? () => controller.addCustomLine() : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(_Strings.addItem.active(language)),
          ),
        ],
      ),
      if (controller.customLines.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        YorksV1MaterialItemsEditor(
          lines: controller.customLines,
          controller: controller,
          enabled: enabled,
          descriptionBuilder: (line, compact) =>
              YorksV1MaterialDescriptionField(
                key: ValueKey('material-return-custom-description-${line.id}'),
                line: line,
                controller: controller,
                enabled: enabled,
                compact: compact,
                projectId: projectId,
                scopeId: scopeId,
              ),
        ),
      ],
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Text(text, style: AppTypography.labelSmall),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ),
        ?action,
      ],
    ),
  );
}

const _panel = BoxDecoration(
  color: AppColors.surfaceContainerLowest,
  borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusLg)),
  border: Border.fromBorderSide(BorderSide(color: AppColors.line)),
  boxShadow: [
    BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 5)),
  ],
);

/// Message for a failed return save, preferring specific server reasons.
TranslatableString? yorksV1MaterialReturnComposerFailure(Object error) {
  final message = error is YorksV1DomainException
      ? (error.serverMessage ?? '').toUpperCase()
      : '';
  if (message.contains('V1_MATERIAL_RETURN_ELIGIBLE_QTY_EXCEEDED')) {
    return _Strings.quantityTaken;
  }
  return null;
}

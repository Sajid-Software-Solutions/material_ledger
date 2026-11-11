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
    show
        YorksV1MaterialDescriptionField,
        YorksV1MaterialItemsEditor,
        YorksV1MaterialLinePolicy,
        YorksV1MaterialRowsAttentionBanner;

typedef _Strings = YorksV1MaterialReturnComposerStrings;

/// Where a delivered return line comes from. The quantity typed on the line
/// is allocated across [item]'s deliveries newest first when saving.
class YorksV1ReturnDeliveredRef {
  YorksV1ReturnDeliveredRef({
    required this.key,
    this.scopeId,
    YorksV1MaterialReturnItem? item,
    this.note,
  }) : _item = item;

  final String key;

  /// Building limit chosen when adding; null means every building.
  final String? scopeId;
  final String? note;
  YorksV1MaterialReturnItem? _item;

  /// Current availability, or null when the material is no longer returnable.
  YorksV1MaterialReturnItem? get item => _item;
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

/// One list of Material Request-shaped lines: delivered lines (details locked,
/// quantity editable) and custom lines (fully editable), in the order added.
class YorksV1ReturnComposerController extends ChangeNotifier
    implements YorksV1MaterialLineEditor {
  var _lines = <YorksV1MaterialRequestLine>[];
  final _delivered = <String, YorksV1ReturnDeliveredRef>{};
  YorksV1MaterialReturnItemCandidates? _resolvedFrom;

  List<YorksV1MaterialRequestLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  bool get isResolved => _resolvedFrom != null;
  bool get hasDelivered => _delivered.isNotEmpty;

  /// Candidates the delivered lines were last resolved against.
  YorksV1MaterialReturnItemCandidates? get resolvedFrom => _resolvedFrom;

  YorksV1ReturnDeliveredRef? deliveredRef(String lineId) => _delivered[lineId];
  bool isDelivered(String lineId) => _delivered.containsKey(lineId);
  bool containsKey(String key) =>
      _delivered.values.any((ref) => ref.key == key);

  /// Adds a delivered material once; returns false when it is already listed.
  bool addItem(YorksV1MaterialReturnItem item, {String? scopeId}) {
    if (containsKey(item.key)) return false;
    final scoped = yorksV1MaterialReturnItemForScope(item, scopeId);
    final line = YorksV1MaterialRequestLine(
      id: const Uuid().v4(),
      displayOrder: _lines.length + 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: item.description,
      quantity: '',
      unit: item.unit,
      size: item.size,
      model: _joined([...item.models, ...item.equipmentTags]),
      brandOrigin: _joined(item.brandOrigins),
    );
    _lines = [..._lines, line];
    _delivered[line.id] = YorksV1ReturnDeliveredRef(
      key: item.key,
      scopeId: scopeId,
      item: scoped,
    );
    notifyListeners();
    return true;
  }

  void clear() {
    _lines = [];
    _delivered.clear();
    _resolvedFrom = null;
    notifyListeners();
  }

  /// Rebuilds the composer from saved draft lines. Delivered lines of the same
  /// material are merged back into one line.
  void hydrate(List<YorksV1MaterialReturnLineRecord> records) {
    final resolvedFrom = _resolvedFrom;
    _lines = [];
    _delivered.clear();
    final byKey = <String, List<YorksV1MaterialReturnLineRecord>>{};
    final order = <Object>[];
    for (final record in records) {
      if (record.origin == YorksV1ReturnLineOrigin.delivered) {
        final key = yorksV1MaterialReturnItemKey(
          description: record.description,
          size: record.size,
          unit: record.unit,
        );
        if (!byKey.containsKey(key)) order.add(key);
        byKey.putIfAbsent(key, () => []).add(record);
      } else {
        order.add(record);
      }
    }
    final next = <YorksV1MaterialRequestLine>[];
    for (final entry in order) {
      final id = const Uuid().v4();
      if (entry is String) {
        final group = byKey[entry]!;
        final first = group.first;
        next.add(
          YorksV1MaterialRequestLine(
            id: id,
            displayOrder: next.length + 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: first.description,
            quantity: yorksV1SumQuantities(
              group.map((line) => line.returnQuantity),
            ),
            unit: first.unit,
            size: first.size,
            model: _joined([?first.model, ?first.equipmentTag]),
            brandOrigin: first.brandOrigin,
          ),
        );
        _delivered[id] = YorksV1ReturnDeliveredRef(
          key: entry,
          note: group
              .map((line) => line.lineNote)
              .whereType<String>()
              .firstOrNull,
        );
      } else if (entry is YorksV1MaterialReturnLineRecord) {
        next.add(
          YorksV1MaterialRequestLine(
            id: id,
            displayOrder: next.length + 1,
            source: YorksV1MaterialRequestLineSource.custom,
            description: entry.description,
            quantity: yorksV1DisplayQuantity(entry.returnQuantity),
            unit: entry.unit,
            brandOrigin: entry.brandOrigin,
            size: entry.size,
            model: entry.model,
            equipmentTag: entry.equipmentTag,
          ),
        );
      }
    }
    _lines = next;
    _resolvedFrom = null;
    if (resolvedFrom != null) {
      _apply(resolvedFrom);
    } else {
      notifyListeners();
    }
  }

  /// Attaches current availability to every delivered line.
  void resolve(YorksV1MaterialReturnItemCandidates candidates) {
    if (identical(_resolvedFrom, candidates)) return;
    _apply(candidates);
  }

  void _apply(YorksV1MaterialReturnItemCandidates candidates) {
    _resolvedFrom = candidates;
    for (final ref in _delivered.values) {
      final item = candidates.itemForKey(ref.key);
      ref._item = item == null
          ? null
          : yorksV1MaterialReturnItemForScope(item, ref.scopeId);
    }
    notifyListeners();
  }

  YorksV1MaterialRequestLine? _line(String lineId) =>
      _lines.where((line) => line.id == lineId).firstOrNull;

  YorksV1ReturnSelectionIssue? issueFor(String lineId) {
    final ref = _delivered[lineId];
    final line = _line(lineId);
    if (ref == null || line == null) return null;
    if (isResolved && ref.item == null) {
      return YorksV1ReturnSelectionIssue.unavailable;
    }
    final quantity = YorksV1DecimalQuantity.tryParse(line.quantity);
    if (quantity == null || !quantity.isPositive) {
      return YorksV1ReturnSelectionIssue.quantityRequired;
    }
    final available = YorksV1DecimalQuantity.tryParse(
      ref.item?.returnableQuantity ?? '',
    );
    if (available != null && quantity.compareTo(available) > 0) {
      return YorksV1ReturnSelectionIssue.exceedsAvailable;
    }
    return null;
  }

  List<YorksV1ReturnAllocation>? allocationFor(String lineId) {
    final item = _delivered[lineId]?.item;
    final line = _line(lineId);
    if (item == null || line == null) return null;
    return yorksV1AllocateReturnQuantity(item.sources, line.quantity);
  }

  /// Grid rules for one line: delivered details are locked and the quantity
  /// carries the returnable hint and over-quantity error.
  YorksV1MaterialLinePolicy policyFor(
    YorksV1MaterialRequestLine line,
    AppLanguage language,
  ) {
    final ref = _delivered[line.id];
    if (ref == null) return YorksV1MaterialLinePolicy.standard;
    final item = ref.item;
    final issue = issueFor(line.id);
    return YorksV1MaterialLinePolicy(
      lockDetails: true,
      allowSimilar: false,
      quantityHint: item == null
          ? null
          : _Strings.ofAvailable(
              yorksV1DisplayQuantity(item.returnableQuantity),
            ).active(language),
      quantityError: switch (issue) {
        YorksV1ReturnSelectionIssue.exceedsAvailable =>
          _Strings.exceedsAvailable(
            yorksV1DisplayQuantity(item?.returnableQuantity ?? '0'),
          ).active(language),
        YorksV1ReturnSelectionIssue.unavailable =>
          _Strings.noLongerAvailable.active(language),
        _ => null,
      },
    );
  }

  /// Lines that block saving, in grid order.
  List<String> invalidLineIds() => [
    for (final line in _lines)
      if (!line.hasValidOperationalValues ||
          (isDelivered(line.id) && issueFor(line.id) != null))
        line.id,
  ];

  YorksV1ReturnComposerLines buildLines() {
    final lines = <YorksV1MaterialReturnDraftLineInput>[];
    var hasIssues = false;
    var customIncomplete = false;
    for (final line in _lines) {
      final ref = _delivered[line.id];
      if (ref != null) {
        final allocation = issueFor(line.id) == null
            ? allocationFor(line.id)
            : null;
        if (allocation == null) {
          hasIssues = true;
          continue;
        }
        for (final slice in allocation) {
          lines.add(
            YorksV1MaterialReturnDraftLineInput(
              origin: YorksV1ReturnLineOrigin.delivered,
              dispatchLineId: slice.source.dispatchLineId,
              receiptReviewLineId: slice.source.receiptReviewLineId,
              quantity: slice.quantity,
              note: ref.note,
            ),
          );
        }
        continue;
      }
      final blank =
          line.description.trim().isEmpty && line.quantity.trim().isEmpty;
      if (blank) continue;
      final quantity = YorksV1DecimalQuantity.tryParse(line.quantity);
      if (!line.hasDescription ||
          !line.hasControlledUnit ||
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
    return YorksV1ReturnComposerLines(
      lines: lines,
      hasIssues: hasIssues,
      customIncomplete: customIncomplete,
    );
  }

  // Material Request line editor commands.

  @override
  Future<void> updateLine(
    String lineId,
    YorksV1MaterialRequestLine Function(YorksV1MaterialRequestLine) transform,
  ) async {
    _lines = [
      for (final line in _lines)
        if (line.id != lineId)
          line
        else if (isDelivered(lineId))
          // Delivered details are facts of the delivery; only quantity moves.
          line.copyWith(quantity: transform(line).quantity)
        else
          transform(line),
    ];
    notifyListeners();
  }

  @override
  Future<void> addCustomLine({String? afterLineId}) async =>
      _insertAfter(afterLineId, null);

  @override
  Future<void> addSimilarLine({String? afterLineId}) async {
    final source = _line(afterLineId ?? '');
    if (source != null && !isDelivered(source.id)) {
      _insertAfter(afterLineId, source);
    }
  }

  @override
  Future<void> removeLine(String lineId) async {
    _delivered.remove(lineId);
    _lines = _renumber(_lines.where((line) => line.id != lineId).toList());
    notifyListeners();
  }

  void _insertAfter(String? afterLineId, YorksV1MaterialRequestLine? copy) {
    final index = afterLineId == null
        ? _lines.length - 1
        : _lines.indexWhere((line) => line.id == afterLineId);
    final next = [..._lines]
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
    _lines = _renumber(next);
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

  static String? _joined(Iterable<String> values) {
    final unique = {for (final value in values) value.trim()}
      ..removeWhere((value) => value.isEmpty);
    return unique.isEmpty ? null : unique.join(', ');
  }
}

/// Body of the numbered "Material Items" card: instant delivered-material
/// search, the Material Request attention banner and the Material Request
/// line grid.
class YorksV1MaterialReturnItems extends ConsumerStatefulWidget {
  const YorksV1MaterialReturnItems({
    super.key,
    required this.projectId,
    required this.controller,
    required this.language,
    required this.enabled,
    this.returnId,
    this.scopeId,
  });

  final String projectId;
  final String? returnId;
  final String? scopeId;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;

  @override
  ConsumerState<YorksV1MaterialReturnItems> createState() =>
      _YorksV1MaterialReturnItemsState();
}

class _YorksV1MaterialReturnItemsState
    extends ConsumerState<YorksV1MaterialReturnItems> {
  YorksV1MaterialReturnCandidatesQuery get _baseQuery =>
      YorksV1MaterialReturnCandidatesQuery(
        projectId: widget.projectId,
        returnId: widget.returnId,
      );

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final base = ref.watch(
      yorksV1MaterialReturnItemCandidatesProvider(_baseQuery),
    );
    if (base case AsyncData(
      :final value,
    ) when !identical(value, widget.controller.resolvedFrom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.resolve(value);
      });
    }
    return Column(
      key: const ValueKey('material-return-items'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                yorksV1MaterialReturnItemCandidatesProvider(_baseQuery),
              ),
              child: Text(_Strings.retry.active(language)),
            ),
          ),
          data: (all) => _DeliveredSearchField(
            all: all,
            projectId: widget.projectId,
            returnId: widget.returnId,
            controller: widget.controller,
            language: language,
            enabled: widget.enabled,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => _grid(language),
        ),
      ],
    );
  }

  Widget _grid(AppLanguage language) {
    final controller = widget.controller;
    final lines = controller.lines;
    if (lines.isEmpty) {
      return Text(
        _Strings.noItemsYet.active(language),
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      );
    }
    final invalid = controller.invalidLineIds();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (invalid.isNotEmpty) ...[
          YorksV1MaterialRowsAttentionBanner(
            key: const ValueKey('material-return-attention'),
            message: _Strings.rowsNeedAttention(
              invalid.length,
            ).active(language),
            firstLineId: invalid.first,
            reviewLabel: _Strings.review.active(language),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        YorksV1MaterialItemsEditor(
          key: const ValueKey('material-return-grid'),
          lines: lines,
          controller: controller,
          enabled: widget.enabled,
          linePolicy: (line) => controller.policyFor(line, language),
          descriptionBuilder: (line, compact) => controller.isDelivered(line.id)
              ? _DeliveredDescription(
                  key: ValueKey('material-return-delivered-${line.id}'),
                  line: line,
                  controller: controller,
                  language: language,
                )
              : YorksV1MaterialDescriptionField(
                  key: ValueKey(
                    'material-return-custom-description-${line.id}',
                  ),
                  line: line,
                  controller: controller,
                  enabled: widget.enabled,
                  compact: compact,
                  projectId: widget.projectId,
                  scopeId: widget.scopeId,
                ),
        ),
      ],
    );
  }
}

/// Type-ahead over delivered material: instant local matches first, then the
/// server's trigram matches for close spellings.
class _DeliveredSearchField extends ConsumerStatefulWidget {
  const _DeliveredSearchField({
    required this.all,
    required this.projectId,
    required this.returnId,
    required this.controller,
    required this.language,
    required this.enabled,
  });

  final YorksV1MaterialReturnItemCandidates all;
  final String projectId;
  final String? returnId;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;
  final bool enabled;

  @override
  ConsumerState<_DeliveredSearchField> createState() =>
      _DeliveredSearchFieldState();
}

class _DeliveredSearchFieldState extends ConsumerState<_DeliveredSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  int _epoch = 0;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<YorksV1MaterialReturnItem>> _options(
    TextEditingValue value,
  ) async {
    final text = value.text.trim();
    if (text.isEmpty) return const [];
    final epoch = ++_epoch;
    final local = [
      for (final item in widget.all.items)
        if (yorksV1MaterialReturnItemMatches(item, text)) item,
    ];
    if (text.length < 3 || local.length >= 8) return local.take(30);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || epoch != _epoch) return local;
    try {
      final searched = await ref.read(
        yorksV1MaterialReturnItemCandidatesProvider(
          YorksV1MaterialReturnCandidatesQuery(
            projectId: widget.projectId,
            returnId: widget.returnId,
            search: text,
          ),
        ).future,
      );
      final seen = {for (final item in local) item.key};
      return [
        ...local,
        for (final item in searched.items)
          if (seen.add(item.key)) widget.all.itemForKey(item.key) ?? item,
      ].take(30);
    } catch (_) {
      return local;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    if (widget.all.items.isEmpty) {
      return _Notice(
        icon: Icons.inventory_2_outlined,
        text: _Strings.noDelivered.active(language),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          RawAutocomplete<YorksV1MaterialReturnItem>(
            textEditingController: _text,
            focusNode: _focus,
            displayStringForOption: (item) => item.description,
            optionsBuilder: _options,
            onSelected: (item) {
              widget.controller.addItem(item);
              _text.clear();
              _focus.requestFocus();
            },
            fieldViewBuilder: (context, text, focus, onSubmitted) => TextField(
              key: const ValueKey('material-return-search'),
              controller: text,
              focusNode: focus,
              enabled: widget.enabled,
              onSubmitted: (_) => onSubmitted(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: _Strings.searchDelivered.active(language),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: AlignmentDirectional.topStart,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: 380,
                  ),
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => ListView.separated(
                      key: const ValueKey('material-return-search-results'),
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = options.elementAt(index);
                        final added = widget.controller.containsKey(item.key);
                        return _CandidateTile(
                          item: item,
                          language: language,
                          trailing: added
                              ? _AddedChip(language: language)
                              : null,
                          onTap: added ? null : () => onSelected(item),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }
}

/// Read-only description of a delivered line: the material, where it came
/// from and which deliveries the typed quantity will be taken from.
class _DeliveredDescription extends StatelessWidget {
  const _DeliveredDescription({
    super.key,
    required this.line,
    required this.controller,
    required this.language,
  });

  final YorksV1MaterialRequestLine line;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final item = controller.deliveredRef(line.id)?.item;
    final requests = {
      for (final source
          in item?.sources ?? const <YorksV1MaterialReturnSource>[])
        source.requestNumber,
    }.toList(growable: false);
    final allocation = controller.allocationFor(line.id);
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Tag(
                    _Strings.fromDelivery.active(language),
                    color: AppColors.blueContainer,
                    textColor: AppColors.blue,
                  ),
                  for (final code
                      in item?.itemCodes.take(1) ?? const <String>[])
                    _Tag(code),
                  if (requests.isNotEmpty)
                    Text(
                      requests.length > 2
                          ? '${requests.take(2).join(', ')} +${requests.length - 2}'
                          : requests.join(', '),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  if (item?.hasUnconfirmed == true)
                    _Tag(
                      _Strings.unconfirmedDelivery.active(language),
                      color: AppColors.warningContainer,
                      textColor: AppColors.onWarningContainer,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (allocation != null && allocation.isNotEmpty)
          IconButton(
            key: ValueKey('material-return-deliveries-${line.id}'),
            tooltip: _Strings.deliveries.active(language),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(line.description),
                content: SizedBox(
                  width: 460,
                  child: _AllocationPreview(
                    allocation: allocation,
                    language: language,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Add from Deliveries": browse every returnable material with search and a
/// building filter, select several, add them in one step. Mirrors the
/// Material Request "Add from BOQ" picker.
Future<void> showYorksV1DeliveredMaterialPicker(
  BuildContext context, {
  required String projectId,
  required String? returnId,
  required String? scopeId,
  required String? scopeName,
  required String? projectReference,
  required YorksV1ReturnComposerController controller,
  required AppLanguage language,
}) async {
  final picked = await showDialog<List<YorksV1MaterialReturnItem>>(
    context: context,
    builder: (context) => _DeliveredPickerDialog(
      projectId: projectId,
      returnId: returnId,
      scopeId: scopeId,
      scopeName: scopeName,
      projectReference: projectReference,
      controller: controller,
      language: language,
    ),
  );
  if (picked == null) return;
  for (final item in picked) {
    controller.addItem(item);
  }
}

class _DeliveredPickerDialog extends ConsumerStatefulWidget {
  const _DeliveredPickerDialog({
    required this.projectId,
    required this.returnId,
    required this.scopeId,
    required this.scopeName,
    required this.projectReference,
    required this.controller,
    required this.language,
  });

  final String projectId;
  final String? returnId;
  final String? scopeId;
  final String? scopeName;
  final String? projectReference;
  final YorksV1ReturnComposerController controller;
  final AppLanguage language;

  @override
  ConsumerState<_DeliveredPickerDialog> createState() =>
      _DeliveredPickerDialogState();
}

class _DeliveredPickerDialogState
    extends ConsumerState<_DeliveredPickerDialog> {
  final _search = TextEditingController();
  final _selected = <String>{};
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
    final viewport = MediaQuery.sizeOf(context);
    final base = ref.watch(
      yorksV1MaterialReturnItemCandidatesProvider(
        YorksV1MaterialReturnCandidatesQuery(
          projectId: widget.projectId,
          returnId: widget.returnId,
        ),
      ),
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
    final items = <YorksV1MaterialReturnItem>[];
    final all = base.valueOrNull;
    if (all != null) {
      final scopeId = _onlyBuilding ? widget.scopeId : null;
      final seen = <String>{};
      void add(YorksV1MaterialReturnItem item) {
        final scoped = yorksV1MaterialReturnItemForScope(item, scopeId);
        if (scoped.sources.isNotEmpty && seen.add(scoped.key)) {
          items.add(scoped);
        }
      }

      for (final item in all.items) {
        if (yorksV1MaterialReturnItemMatches(item, _search.text)) add(item);
      }
      final found = searched?.valueOrNull;
      if (found != null && _search.text.trim().isNotEmpty) {
        for (final item in found.items) {
          add(all.itemForKey(item.key) ?? item);
        }
      }
    }
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: viewport.height - (AppSpacing.lg * 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _Strings.addDeliveredTitle.active(language),
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          [
                            ?widget.projectReference,
                            _Strings.materialToReturnHint.active(language),
                          ].join(' · '),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      minimumSize: const Size.square(AppSpacing.minTapTarget),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('material-return-picker-search'),
                    controller: _search,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: _Strings.searchDelivered.active(language),
                    ),
                  ),
                  if (widget.scopeName != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('material-return-all-buildings'),
                          label: Text(_Strings.allBuildings.active(language)),
                          selected: !_onlyBuilding,
                          onSelected: (_) =>
                              setState(() => _onlyBuilding = false),
                        ),
                        ChoiceChip(
                          key: const ValueKey('material-return-only-building'),
                          label: Text(
                            _Strings.onlyBuilding(
                              widget.scopeName!,
                            ).active(language),
                          ),
                          selected: _onlyBuilding,
                          onSelected: (_) =>
                              setState(() => _onlyBuilding = true),
                        ),
                      ],
                    ),
                  ],
                  if (searched?.isLoading == true) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            Flexible(
              child: base.isLoading && all == null
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : base.hasError && all == null
                  ? _Notice(
                      icon: Icons.cloud_off_rounded,
                      text: _Strings.loadFailed.active(language),
                    )
                  : items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: _Notice(
                        icon: Icons.search_off_rounded,
                        text: (all?.items.isEmpty ?? true)
                            ? _Strings.noDelivered.active(language)
                            : _Strings.noMatches.active(language),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('material-return-picker-results'),
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final added = widget.controller.containsKey(item.key);
                        final selected = _selected.contains(item.key);
                        return _CandidateTile(
                          key: ValueKey('material-return-pick-${item.key}'),
                          item: item,
                          language: language,
                          leading: Checkbox(
                            value: added || selected,
                            onChanged: added
                                ? null
                                : (value) => setState(() {
                                    if (value == true) {
                                      _selected.add(item.key);
                                    } else {
                                      _selected.remove(item.key);
                                    }
                                  }),
                          ),
                          trailing: added
                              ? _AddedChip(language: language)
                              : null,
                          onTap: added
                              ? null
                              : () => setState(() {
                                  if (!_selected.remove(item.key)) {
                                    _selected.add(item.key);
                                  }
                                }),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _Strings.selectedItems(_selected.length).active(language),
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_Strings.cancel.active(language)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    key: const ValueKey('material-return-add-selected'),
                    onPressed: _selected.isEmpty || all == null
                        ? null
                        : () => Navigator.of(context).pop([
                            for (final key in _selected) ?all.itemForKey(key),
                          ]),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      minimumSize: const Size(0, AppSpacing.minTapTarget),
                    ),
                    child: Text(_Strings.addSelected.active(language)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    super.key,
    required this.item,
    required this.language,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final YorksV1MaterialReturnItem item;
  final AppLanguage language;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final requests = {
      for (final source in item.sources) source.requestNumber,
    }.toList(growable: false);
    final quantities = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _Strings.returnable(
            yorksV1DisplayQuantity(item.returnableQuantity),
            item.unit,
          ).active(language),
          textAlign: TextAlign.end,
          style: AppTypography.labelLarge,
        ),
        if (item.hasUnconfirmed)
          Text(
            _Strings.unconfirmedPart(
              yorksV1DisplayQuantity(item.unconfirmedReturnableQuantity),
            ).active(language),
            textAlign: TextAlign.end,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onWarningContainer,
            ),
          ),
        if (trailing != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          trailing!,
        ],
      ],
    );
    final details = Column(
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
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.size != null)
              _Tag('${_Strings.size.active(language)} ${item.size}'),
            for (final model in item.models.take(2))
              _Tag('${_Strings.model.active(language)} $model'),
            for (final code in item.itemCodes.take(2)) _Tag(code),
            for (final brand in item.brandOrigins.take(2)) _Tag(brand),
            Text(
              requests.length > 2
                  ? '${requests.take(2).join(' · ')} +${requests.length - 2}'
                  : requests.join(' · '),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
    return InkWell(
      key: key == null
          ? ValueKey('material-return-candidate-${item.key}')
          : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Phones stack the quantities under the material so neither is
            // squeezed; wider surfaces keep them right-aligned like a table.
            final narrow = constraints.maxWidth < 520;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?leading,
                Expanded(
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: quantities,
                            ),
                          ],
                        )
                      : details,
                ),
                if (!narrow) ...[
                  const SizedBox(width: AppSpacing.md),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .4,
                    ),
                    child: quantities,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AddedChip extends StatelessWidget {
  const _AddedChip({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
      const SizedBox(width: AppSpacing.xxs),
      Text(
        _Strings.alreadyAdded.active(language),
        style: AppTypography.labelSmall.copyWith(color: AppColors.success),
      ),
    ],
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _Strings.deliveries.active(language),
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        for (final slice in allocation)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  slice.source.isUnconfirmed
                      ? Icons.local_shipping_outlined
                      : Icons.verified_outlined,
                  size: 18,
                  color: slice.source.isUnconfirmed
                      ? AppColors.onWarningContainer
                      : AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          slice.source.requestNumber,
                          slice.source.dispatchNumber,
                          if (slice.source.deliveredAt != null)
                            dateFormat.format(
                              slice.source.deliveredAt!.toLocal(),
                            ),
                        ].join(' · '),
                        style: AppTypography.bodySmall,
                      ),
                      Text(
                        slice.source.isUnconfirmed
                            ? _Strings.unconfirmedDelivery.active(language)
                            : _Strings.confirmedDelivery.active(language),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _Strings.takes(
                    yorksV1DisplayQuantity(slice.quantity),
                    yorksV1DisplayQuantity(slice.source.returnableQuantity),
                  ).active(language),
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color, this.textColor});

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
    decoration: BoxDecoration(
      color: color ?? AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Text(
      text,
      style: AppTypography.labelSmall.copyWith(color: textColor),
    ),
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

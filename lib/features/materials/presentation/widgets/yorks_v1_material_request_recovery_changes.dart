import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';

/// Compare the actual non-commercial Save payload, including missing values.
/// Match lines by stable ID so additions, removals and reordering stay visible.
class YorksV1MaterialRequestRecoveryChanges extends StatelessWidget {
  const YorksV1MaterialRequestRecoveryChanges({
    super.key,
    required this.draft,
    required this.saved,
    required this.language,
  });
  final YorksV1MaterialRequestDraft draft;
  final YorksV1MaterialRequest saved;
  final AppLanguage language;

  static const _labels = <String, TranslatableString>{
    'project_id': YorksV1MaterialRequestStrings.project,
    'scope_id': YorksV1MaterialRequestStrings.scope,
    'title': YorksV1MaterialRequestStrings.requestTitle,
    'timing': YorksV1MaterialRequestStrings.timing,
    'scheduled_date': YorksV1MaterialRequestStrings.scheduledDate,
    'delivery_note': YorksV1MaterialRequestStrings.deliveryNoteLabel,
    'display_order': YorksV1MaterialRequestStrings.lineOrder,
    'source_kind': YorksV1MaterialRequestStrings.lineSource,
    'source_boq_group_id': YorksV1MaterialRequestStrings.sourceGroup,
    'source_boq_row_id': YorksV1MaterialRequestStrings.sourceRow,
    'item_description': YorksV1MaterialRequestStrings.itemDescription,
    'brand_origin': YorksV1MaterialRequestStrings.brandOrigin,
    'size': YorksV1MaterialRequestStrings.size,
    'model': YorksV1BoqStrings.model,
    'equipment_tag': YorksV1BoqStrings.equipmentTag,
    'planning_model_tag': YorksV1MaterialRequestStrings.planningModelTag,
    'quantity_suggested': YorksV1MaterialRequestStrings.suggestedQuantity,
    'requested_qty': YorksV1MaterialRequestStrings.quantity,
    'unit': YorksV1MaterialRequestStrings.unit,
  };

  Map<String, dynamic> _line(YorksV1MaterialRequestLine line) {
    final fields = line.toRpcJson()..remove('id');
    final technical = fields.remove('technical_attributes') as Map;
    return {...fields, ...Map<String, dynamic>.from(technical)};
  }

  String _value(String key, Object? value) {
    if (value == null || value.toString().isEmpty) {
      return YorksV1MaterialRequestStrings.recoveryCleared.active(language);
    }
    if (key == 'project_id' && value == saved.projectId) {
      return '${saved.projectReference} · ${saved.projectName}';
    }
    if (key == 'scope_id' && value == saved.scopeId) return saved.scopeName;
    if (value is bool) {
      return (value
              ? YorksV1MaterialRequestStrings.recoveryYes
              : YorksV1MaterialRequestStrings.recoveryNo)
          .active(language);
    }
    if (key == 'source_kind') {
      return switch (value) {
        'custom' => YorksV1MaterialRequestStrings.recoveryCustomSource.active(
          language,
        ),
        'boq' => YorksV1BoqStrings.boq.active(language),
        _ => value.toString(),
      };
    }
    if (key == 'timing') {
      return yorksV1MaterialRequestTimingCopy(
        YorksV1MaterialRequestTiming.fromWireValue(value.toString())!,
      ).active(language);
    }
    return value.toString();
  }

  List<Widget> _changes(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) => [
    for (final key in {...before.keys, ...after.keys})
      if (before[key] != after[key])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labels[key]!.active(language),
                style: AppTypography.labelLarge,
              ),
              Text(
                '${YorksV1MaterialRequestStrings.savedValue.active(language)}: ${_value(key, before[key])}',
              ),
              Text(
                '${YorksV1MaterialRequestStrings.recoveredInput.active(language)}: ${_value(key, after[key])}',
              ),
            ],
          ),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final savedDraft = YorksV1MaterialRequestDraft(
      id: draft.id,
      ownerAuthUserId: draft.ownerAuthUserId,
      submissionIdempotencyKey: draft.submissionIdempotencyKey,
      projectId: saved.projectId,
      scopeId: saved.scopeId,
      title: saved.title,
      timing: saved.timing,
      scheduledDate: saved.scheduledDate,
      deliveryNote: saved.deliveryNote,
      lines: saved.lines,
      updatedAt: saved.updatedAt,
    );
    Map<String, dynamic> header(YorksV1MaterialRequestDraft value) =>
        value.toSaveInput().toRpcPayload()
          ..remove('request_id')
          ..remove('expected_version')
          ..remove('lines');
    final before = {for (final line in saved.lines) line.id: line};
    final after = {for (final line in draft.lines) line.id: line};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          YorksV1MaterialRequestStrings.recoveryChanges.active(language),
          style: AppTypography.titleMedium,
        ),
        ..._changes(header(savedDraft), header(draft)),
        for (final id in {...before.keys, ...after.keys})
          if (_changes(
            before[id] == null ? {} : _line(before[id]!),
            after[id] == null ? {} : _line(after[id]!),
          ).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (before[id] == null || after[id] == null)
                      Text(
                        (before[id] == null
                                ? YorksV1MaterialRequestStrings
                                      .recoveryAddedLine
                                : YorksV1MaterialRequestStrings
                                      .recoveryRemovedLine)
                            .active(language),
                        style: AppTypography.labelLarge,
                      ),
                    Text(
                      (after[id] ?? before[id])!.description,
                      style: AppTypography.titleSmall,
                    ),
                    ..._changes(
                      before[id] == null ? {} : _line(before[id]!),
                      after[id] == null ? {} : _line(after[id]!),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

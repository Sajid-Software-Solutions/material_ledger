import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_worker_record.dart';
import '../../../../shared/models/yorks_v1_worker_record_strings.dart';
import '../../../../shared/providers/yorks_v1_worker_record_provider.dart';
import 'yorks_v1_worker_records_tab.dart';

typedef _S = YorksV1WorkerRecordStrings;

/// Add a worker, or edit one worker's employment record.
///
/// Nothing is shown as saved until the server confirms it. The dialog pops
/// `true` after a confirmed save so the register can reload.
class YorksV1WorkerRecordFormDialog extends ConsumerStatefulWidget {
  const YorksV1WorkerRecordFormDialog({
    super.key,
    required this.language,
    this.record,
  });

  final AppLanguage language;

  /// Null to add a new worker.
  final YorksV1WorkerRecord? record;

  static Future<bool?> show(
    BuildContext context, {
    required AppLanguage language,
    YorksV1WorkerRecord? record,
  }) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        YorksV1WorkerRecordFormDialog(language: language, record: record),
  );

  @override
  ConsumerState<YorksV1WorkerRecordFormDialog> createState() =>
      _YorksV1WorkerRecordFormDialogState();
}

class _YorksV1WorkerRecordFormDialogState
    extends ConsumerState<YorksV1WorkerRecordFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.record?.fullName);
  late final _designation = TextEditingController(
    text: widget.record?.designation,
  );
  late final _company = TextEditingController(
    text: widget.record?.employerCompany,
  );
  final _joiningDate = TextEditingController();
  late final _license = TextEditingController(
    text: widget.record?.tradeLicenseNo,
  );
  late final _passport = TextEditingController(text: widget.record?.passportNo);
  late final _basic = TextEditingController(text: widget.record?.basicSalary);
  late final _housing = TextEditingController(
    text: widget.record?.housingAllowance,
  );
  late final _other = TextEditingController(
    text: widget.record?.otherAllowance,
  );

  /// The record as last confirmed by the server. After a save that stored the
  /// record but not the photo, a retry continues from here.
  late YorksV1WorkerRecord? _confirmed = widget.record;
  Uint8List? _photo;
  bool _saving = false;
  bool _savedSomething = false;
  TranslatableString? _error;

  // One idempotency key per distinct input: a retry of the same input reuses
  // it, so a lost response can never create a second worker.
  String? _saveSignature;
  String _saveKey = const Uuid().v4();
  String _photoKey = const Uuid().v4();

  @override
  void dispose() {
    for (final controller in [
      _name,
      _designation,
      _company,
      _joiningDate,
      _license,
      _passport,
      _basic,
      _housing,
      _other,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isNewWorker => _confirmed == null;

  Future<void> _pickPhoto() async {
    final picked = await ref.read(yorksV1WorkerPhotoPickerProvider)();
    if (!mounted || !picked.picked) return;
    setState(() {
      if (picked.bytes == null) {
        _error = _S.photoUnreadable;
      } else {
        _photo = picked.bytes;
        _photoKey = const Uuid().v4();
        _error = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_joiningDate.text) ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    _joiningDate.text =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final repository = ref.read(yorksV1WorkerRecordRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final confirmed = _confirmed;
      var input = YorksV1SaveWorkerRecordInput(
        workerId: confirmed?.workerId,
        expectedVersion: confirmed?.recordVersion,
        fullName: _name.text,
        designation: _designation.text,
        employerCompany: _company.text,
        joiningDate: _isNewWorker ? _joiningDate.text.trim() : null,
        tradeLicenseNo: _license.text,
        passportNo: _passport.text,
        basicSalary: _basic.text,
        housingAllowance: _housing.text,
        otherAllowance: _other.text,
        idempotencyKey: _saveKey,
      );
      if (_saveSignature != null && _saveSignature != input.signature) {
        _saveKey = const Uuid().v4();
        input = YorksV1SaveWorkerRecordInput(
          workerId: input.workerId,
          expectedVersion: input.expectedVersion,
          fullName: input.fullName,
          designation: input.designation,
          employerCompany: input.employerCompany,
          joiningDate: input.joiningDate,
          tradeLicenseNo: input.tradeLicenseNo,
          passportNo: input.passportNo,
          basicSalary: input.basicSalary,
          housingAllowance: input.housingAllowance,
          otherAllowance: input.otherAllowance,
          idempotencyKey: _saveKey,
        );
      }
      _saveSignature = input.signature;

      var saved = await repository.saveRecord(input);
      _confirmed = saved;
      _savedSomething = true;
      // The next save starts from the confirmed version with a fresh key.
      _saveSignature = null;
      _saveKey = const Uuid().v4();

      final photo = _photo;
      if (photo != null) {
        try {
          saved = await repository.setPhoto(
            workerId: saved.workerId,
            jpegBytes: photo,
            expectedVersion: saved.recordVersion,
            idempotencyKey: _photoKey,
          );
          _confirmed = saved;
          _photo = null;
        } on YorksV1DomainException {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _error = _S.photoNotSaved;
          });
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (error.code) {
          YorksV1DomainErrorCode.conflict => _S.saveConflict,
          YorksV1DomainErrorCode.offline => _S.saveOffline,
          YorksV1DomainErrorCode.unauthorized ||
          YorksV1DomainErrorCode.unauthenticated => _S.saveNotAllowed,
          YorksV1DomainErrorCode.invalidInput
              when (error.serverMessage ?? '').contains('PASSPORT_DUPLICATE') =>
            _S.passportDuplicate,
          _ => _S.saveFailed,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    String t(TranslatableString copy) => copy.active(language);
    String? required(String? value) =>
        (value ?? '').trim().isEmpty ? t(_S.fieldRequired) : null;
    String? amount(String? value) =>
        yorksV1IsValidWorkerAmount(value ?? '') ? null : t(_S.invalidAmount);

    Widget text(
      TextEditingController controller,
      TranslatableString label, {
      String? Function(String?)? validator,
      int maxLength = 180,
      TextCapitalization capitalization = TextCapitalization.none,
      Key? key,
    }) => TextFormField(
      key: key,
      controller: controller,
      enabled: !_saving,
      validator: validator,
      textCapitalization: capitalization,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      decoration: InputDecoration(labelText: t(label), isDense: true),
    );
    Widget money(
      TextEditingController controller,
      TranslatableString label,
      Key key,
    ) => TextFormField(
      key: key,
      controller: controller,
      enabled: !_saving,
      validator: amount,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(13),
      ],
      textAlign: TextAlign.end,
      decoration: InputDecoration(labelText: t(label), isDense: true),
    );
    Widget pair(Widget left, Widget right) => compact
        ? Column(
            children: [
              left,
              const SizedBox(height: AppSpacing.md),
              right,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: right),
            ],
          );
    Widget heading(TranslatableString copy) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(
        t(copy),
        style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
      ),
    );

    final total = yorksV1SumWorkerAmounts([
      _basic.text,
      _housing.text,
      _other.text,
    ]);
    final confirmed = _confirmed;
    final photo = _photo;

    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        key: const ValueKey('worker-record-form'),
        insetPadding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
        title: Text(
          t(widget.record == null ? _S.newWorkerRecord : _S.editRecord),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (photo != null)
                        ClipOval(
                          child: Image.memory(
                            photo,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        )
                      else if (confirmed != null)
                        YorksV1WorkerPhoto(
                          record: confirmed,
                          language: language,
                          size: 72,
                        )
                      else
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.blueContainer,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.blue,
                            size: 32,
                          ),
                        ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: AppSpacing.minTapTarget,
                              child: OutlinedButton.icon(
                                key: const ValueKey('worker-record-photo'),
                                onPressed: _saving ? null : _pickPhoto,
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                  t(
                                    photo != null ||
                                            confirmed?.photoObjectPath != null
                                        ? _S.changePhoto
                                        : _S.choosePhoto,
                                  ),
                                ),
                              ),
                            ),
                            if (photo != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Text(
                                  t(_S.photoReady),
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  heading(_S.identity),
                  text(
                    _name,
                    _S.name,
                    validator: required,
                    capitalization: TextCapitalization.characters,
                    key: const ValueKey('worker-record-name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  pair(
                    text(
                      _designation,
                      _S.designation,
                      validator: required,
                      maxLength: 120,
                      capitalization: TextCapitalization.words,
                      key: const ValueKey('worker-record-designation'),
                    ),
                    _isNewWorker
                        ? TextFormField(
                            key: const ValueKey('worker-record-joining-date'),
                            controller: _joiningDate,
                            enabled: !_saving,
                            validator: (value) {
                              final text = (value ?? '').trim();
                              if (text.isEmpty) return t(_S.fieldRequired);
                              final valid =
                                  RegExp(
                                    r'^\d{4}-\d{2}-\d{2}$',
                                  ).hasMatch(text) &&
                                  DateTime.tryParse(text) != null;
                              return valid ? null : t(_S.invalidDate);
                            },
                            decoration: InputDecoration(
                              labelText: t(_S.joiningDate),
                              hintText: t(_S.joiningDateHint),
                              isDense: true,
                              suffixIcon: IconButton(
                                onPressed: _saving ? null : _pickDate,
                                icon: const Icon(Icons.event_outlined),
                              ),
                            ),
                          )
                        : InputDecorator(
                            decoration: InputDecoration(
                              labelText: t(_S.workerNumber),
                              isDense: true,
                              enabled: false,
                            ),
                            child: Text(confirmed?.workerNumber ?? ''),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  text(
                    _company,
                    _S.company,
                    validator: required,
                    key: const ValueKey('worker-record-company'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  pair(
                    text(
                      _license,
                      _S.tradeLicense,
                      maxLength: 60,
                      key: const ValueKey('worker-record-license'),
                    ),
                    text(
                      _passport,
                      _S.passport,
                      maxLength: 40,
                      capitalization: TextCapitalization.characters,
                      key: const ValueKey('worker-record-passport'),
                    ),
                  ),
                  heading(_S.salary),
                  pair(
                    money(
                      _basic,
                      _S.basicSalary,
                      const ValueKey('worker-record-basic'),
                    ),
                    money(
                      _housing,
                      _S.housing,
                      const ValueKey('worker-record-housing'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  pair(
                    money(
                      _other,
                      _S.others,
                      const ValueKey('worker-record-other'),
                    ),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: t(_S.totalSalary),
                        isDense: true,
                        enabled: false,
                      ),
                      child: Text(
                        total == null
                            ? '—'
                            : 'AED ${yorksV1FormatWorkerMoney(total)}',
                        key: const ValueKey('worker-record-total'),
                        textAlign: TextAlign.end,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      key: const ValueKey('worker-record-form-error'),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Text(
                        t(_error!),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                // A record saved before a failed photo still counts.
                : () => Navigator.of(context).pop(_savedSomething),
            child: Text(t(_savedSomething ? _S.close : _S.cancel)),
          ),
          FilledButton(
            key: const ValueKey('worker-record-save'),
            onPressed: _saving ? null : _save,
            child: Text(t(_saving ? _S.saving : _S.save)),
          ),
        ],
      ),
    );
  }
}

/// Company documents — New record and Edit record, laid out like the
/// Material Request composer: a header with the commands, then numbered
/// cards. Documents are added on the record once it exists. Nothing is
/// shown as saved until the server confirms; a refusal is shown in place
/// with everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../core/widgets/yorks_mobile_ui.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_company_documents.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_company_documents_provider.dart';
import '../../materials/presentation/screens/yorks_v1_material_request_screens.dart'
    show
        YorksV1MaterialFormAction,
        YorksV1MaterialFormCard,
        YorksV1MaterialFormField,
        YorksV1MaterialFormMeta;
import 'company_kit.dart';

class CompanyFormScreen extends ConsumerWidget {
  const CompanyFormScreen({super.key, this.recordId, this.initialKind});

  /// The record to edit; null for a new record.
  final String? recordId;

  /// A [CompanyRecordKind] wire value for a new record.
  final String? initialKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final overview = ref.watch(yorksV1CompanyOverviewProvider);
    final record = recordId == null
        ? null
        : ref.watch(yorksV1CompanyRecordProvider(recordId!));
    final error = overview.error ?? record?.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: PeopleMessage(
            icon: Icons.cloud_off_outlined,
            title: companyErrorText(error, language),
            action: PS.t(PS.retry, language),
            onPressed: () {
              ref.invalidate(yorksV1CompanyOverviewProvider);
              if (recordId != null) {
                ref.invalidate(yorksV1CompanyRecordProvider(recordId!));
              }
            },
          ),
        ),
      );
    }
    final loadedOverview = overview.valueOrNull;
    final loadedRecord = record?.valueOrNull;
    if (loadedOverview == null || (recordId != null && loadedRecord == null)) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final canManage = loadedRecord?.canManage ?? loadedOverview.canManage;
    if (!canManage) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: PeopleMessage(
            icon: Icons.lock_outline_rounded,
            title: CS.t(CS.errDenied, language),
            action: CS.t(CS.title, language),
            onPressed: () => context.go(companyPath),
          ),
        ),
      );
    }
    return _RecordForm(
      key: ValueKey('company-form-${recordId ?? 'new'}'),
      record: loadedRecord,
      initialKind: initialKind == null
          ? CompanyRecordKind.entity
          : CompanyRecordKind.from(initialKind),
      owners: [for (final owner in loadedOverview.owners) owner.name],
      language: language,
    );
  }
}

class _RecordForm extends ConsumerStatefulWidget {
  const _RecordForm({
    super.key,
    required this.record,
    required this.initialKind,
    required this.owners,
    required this.language,
  });

  final CompanyRecord? record;
  final CompanyRecordKind initialKind;
  final List<String> owners;
  final AppLanguage language;

  @override
  ConsumerState<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<_RecordForm> {
  late CompanyRecordKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _reference;
  late final TextEditingController _owner;
  late final TextEditingController _notes;
  late final TextEditingController _job;
  late final TextEditingController _people;
  late final TextEditingController _vehicles;
  late final TextEditingController _appliedPeople;
  late final TextEditingController _appliedVehicles;
  final _ownerFocus = FocusNode();
  bool _busy = false;
  bool _tried = false;
  String? _error;
  String? _idempotencyKey;

  AppLanguage get _language => widget.language;
  CompanyRecord? get _record => widget.record;

  @override
  void initState() {
    super.initState();
    final record = _record;
    _kind = record?.kind ?? widget.initialKind;
    String count(int? value) => value?.toString() ?? '';
    _name = TextEditingController(text: record?.name ?? '');
    _reference = TextEditingController(text: record?.reference ?? '');
    _owner = TextEditingController(text: record?.owner ?? '');
    _notes = TextEditingController(text: record?.notes ?? '');
    _job = TextEditingController(text: record?.details.job ?? '');
    _people = TextEditingController(text: count(record?.details.people));
    _vehicles = TextEditingController(text: count(record?.details.vehicles));
    _appliedPeople = TextEditingController(
      text: count(record?.details.appliedPeople),
    );
    _appliedVehicles = TextEditingController(
      text: count(record?.details.appliedVehicles),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _reference,
      _owner,
      _notes,
      _job,
      _people,
      _vehicles,
      _appliedPeople,
      _appliedVehicles,
    ]) {
      controller.dispose();
    }
    _ownerFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _error = null;
    _idempotencyKey = null;
  });

  String? get _nameError =>
      _tried && _name.text.trim().isEmpty ? CS.t(CS.errName, _language) : null;

  void _close() {
    final record = _record;
    context.go(record == null ? companyPath : companyRecordPath(record.id));
  }

  int? _count(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_name.text.trim().isEmpty) return;
    _idempotencyKey ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(yorksV1CompanyDocumentsRepositoryProvider)
          .saveRecord(
            CompanySaveRecordInput(
              recordId: _record?.id,
              kind: _kind,
              name: _name.text,
              reference: _reference.text,
              owner: _owner.text,
              notes: _notes.text,
              details: CompanyContractDetails(
                job: _job.text.trim().isEmpty ? null : _job.text.trim(),
                people: _count(_people),
                vehicles: _count(_vehicles),
                appliedPeople: _count(_appliedPeople),
                appliedVehicles: _count(_appliedVehicles),
              ),
              expectedVersion: _record?.recordVersion ?? 0,
              idempotencyKey: _idempotencyKey!,
            ),
          );
      if (!mounted) return;
      yorksV1RefreshCompanyDocuments(ref, recordId: saved.id);
      peopleToast(
        context,
        PS.t(PS.savedToast, _language, {'name': saved.name}),
      );
      context.go(companyRecordPath(saved.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = companyErrorText(error, _language);
      });
    }
  }

  // ─── Fields ────────────────────────────────────────────────────────────────

  Widget _text(
    String key,
    TextEditingController controller, {
    String? label,
    String? error,
    bool number = false,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    keyboardType: number ? TextInputType.number : null,
    inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
    minLines: 1,
    maxLines: maxLines,
    textCapitalization: capitalization,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(labelText: label, errorText: error),
  );

  Widget _kindField({bool labelled = true}) =>
      DropdownButtonFormField<CompanyRecordKind>(
        key: const ValueKey('company-form-kind'),
        initialValue: _kind,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: labelled ? CS.t(CS.whatIsIt, _language) : null,
          prefixIcon: Icon(companyKindIcon(_kind), size: 20),
        ),
        items: [
          for (final kind in CompanyRecordKind.values)
            DropdownMenuItem(
              value: kind,
              child: Text(companyKindLabel(kind, _language)),
            ),
        ],
        onChanged: _busy || _record != null
            ? null
            : (value) {
                if (value == null) return;
                _kind = value;
                _changed();
              },
      );

  Widget _nameField({bool labelled = true}) => _text(
    'company-form-name',
    _name,
    label: labelled ? CS.t(CS.name, _language) : null,
    error: _nameError,
    capitalization: TextCapitalization.characters,
  );

  Widget _referenceField({bool labelled = true}) => _text(
    'company-form-reference',
    _reference,
    label: labelled
        ? CS.t(CS.optional, _language, {
            'field': companyReferenceLabel(_kind, _language),
          })
        : null,
  );

  /// Company, suggesting the companies already recorded.
  Widget _ownerField({bool labelled = true}) => RawAutocomplete<String>(
    textEditingController: _owner,
    focusNode: _ownerFocus,
    optionsBuilder: (value) {
      final query = value.text.trim().toLowerCase();
      return [
        for (final owner in widget.owners)
          if (query.isEmpty || owner.toLowerCase().contains(query)) owner,
      ].take(8);
    },
    onSelected: (_) => _changed(),
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextField(
          key: const ValueKey('company-form-owner'),
          controller: controller,
          focusNode: focusNode,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _changed(),
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: labelled
                ? CS.t(CS.optional, _language, {
                    'field': companyOwnerLabel(_kind, _language),
                  })
                : null,
            prefixIcon: const Icon(Icons.apartment_outlined, size: 20),
          ),
        ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: AlignmentDirectional.topStart,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.apartment_outlined, size: 18),
                  title: Text(option),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _notesField({bool labelled = true}) => _text(
    'company-form-notes',
    _notes,
    label: labelled ? PS.t(PS.notes, _language) : null,
    maxLines: 4,
  );

  List<(String, Widget)> get _contractFields => [
    (
      CS.t(CS.job, _language),
      _text(
        'company-form-job',
        _job,
        capitalization: TextCapitalization.characters,
      ),
    ),
    (
      CS.t(CS.people, _language),
      _text('company-form-people', _people, number: true),
    ),
    (
      CS.t(CS.vehicles, _language),
      _text('company-form-vehicles', _vehicles, number: true),
    ),
    (
      CS.t(CS.appliedPeople, _language),
      _text('company-form-applied-people', _appliedPeople, number: true),
    ),
    (
      CS.t(CS.appliedVehicles, _language),
      _text('company-form-applied-vehicles', _appliedVehicles, number: true),
    ),
  ];

  Widget? _errorBanner() => _error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: YorksMobileCallout(
              key: const ValueKey('company-form-error'),
              icon: Icons.error_outline_rounded,
              title: _error!,
              message: '',
              warning: true,
            ),
          ),
        );

  String get _saveLabel =>
      _busy ? PS.t(PS.saving, _language) : PS.t(PS.save, _language);

  String get _title => _record == null
      ? CS.t(CS.newRecord, _language)
      : CS.t(CS.editRecord, _language, {'name': _record!.name});

  // ─── Layouts ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppSpacing.stackedBreakpoint
      ? _phoneLayout()
      : _desktop();

  Widget _desktop() => Scaffold(
    backgroundColor: AppColors.surface,
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint
              ? AppSpacing.xxxl + AppSpacing.xs
              : AppSpacing.lg;
          return SingleChildScrollView(
            key: const ValueKey('company-form-desktop'),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.xxxl,
              horizontal,
              72,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(),
                    const SizedBox(height: AppSpacing.lg),
                    _detailsCard(),
                    if (_kind == CompanyRecordKind.contract) ...[
                      const SizedBox(height: AppSpacing.xxxl),
                      _contractCard(),
                    ],
                    ?_errorBanner(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _hero() {
    final record = _record;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 920;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CS.t(CS.title, _language).toUpperCase(),
              style: AppTypography.eyebrow,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _title,
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              CS.t(CS.formDescription, _language),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                YorksV1MaterialFormMeta(
                  icon: companyKindIcon(_kind),
                  value: companyKindLabel(_kind, _language),
                ),
                if (record?.reference != null)
                  YorksV1MaterialFormMeta(
                    icon: Icons.tag_rounded,
                    value: record!.reference!,
                  ),
                if (_owner.text.trim().isNotEmpty)
                  YorksV1MaterialFormMeta(
                    icon: Icons.apartment_outlined,
                    value: _owner.text.trim(),
                  ),
              ],
            ),
          ],
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            YorksV1MaterialFormAction(
              key: const ValueKey('company-form-cancel'),
              label: PS.t(PS.cancel, _language),
              onPressed: _busy ? null : _close,
            ),
            YorksV1MaterialFormAction(
              key: const ValueKey('company-form-save'),
              label: _saveLabel,
              icon: Icons.check_rounded,
              primary: true,
              onPressed: _busy ? null : _save,
            ),
          ],
        );
        return Container(
          key: const ValueKey('company-form-hero'),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: AppSpacing.lg),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: AppSpacing.xl),
                    actions,
                  ],
                ),
        );
      },
    );
  }

  Widget _grid(List<(String, Widget)> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 3
          : constraints.maxWidth >= 640
          ? 2
          : 1;
      const gap = AppSpacing.lg;
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (label, child) in fields)
            SizedBox(
              width: width,
              child: YorksV1MaterialFormField(label: label, child: child),
            ),
        ],
      );
    },
  );

  Widget _detailsCard() => YorksV1MaterialFormCard(
    key: const ValueKey('company-form-details-card'),
    sectionNumber: 1,
    title: CS.t(CS.recordInformation, _language),
    description: CS.t(CS.recordInformationDescription, _language),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grid([
          (CS.t(CS.whatIsIt, _language), _kindField(labelled: false)),
          (CS.t(CS.name, _language), _nameField(labelled: false)),
          (
            CS.t(CS.optional, _language, {
              'field': companyReferenceLabel(_kind, _language),
            }),
            _referenceField(labelled: false),
          ),
          (
            CS.t(CS.optional, _language, {
              'field': companyOwnerLabel(_kind, _language),
            }),
            _ownerField(labelled: false),
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        YorksV1MaterialFormField(
          label: PS.t(PS.notes, _language),
          child: _notesField(labelled: false),
        ),
      ],
    ),
  );

  Widget _contractCard() => YorksV1MaterialFormCard(
    key: const ValueKey('company-form-contract-card'),
    sectionNumber: 2,
    title: CS.t(CS.contract, _language),
    description: CS.t(CS.contractDescription, _language),
    child: _grid(_contractFields),
  );

  // ─── Phone: one column, the save bar at the bottom ─────────────────────────

  Widget _phoneLayout() {
    const gap = SizedBox(height: AppSpacing.md);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        key: const ValueKey('company-form-mobile'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxxl,
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('company-form-back'),
              onPressed: _busy ? null : _close,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(PS.t(PS.cancel, _language)),
            ),
          ),
          Text(
            _title,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CS.t(CS.formDescription, _language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          section(CS.t(CS.recordInformation, _language)),
          _kindField(),
          gap,
          _nameField(),
          gap,
          _referenceField(),
          gap,
          _ownerField(),
          gap,
          _notesField(),
          if (_kind == CompanyRecordKind.contract) ...[
            section(CS.t(CS.contract, _language)),
            for (final (label, field) in _contractFields) ...[
              Text(label, style: AppTypography.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              field,
              gap,
            ],
          ],
          ?_errorBanner(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey('company-form-save'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_saveLabel),
            ),
          ),
        ),
      ),
    );
  }
}

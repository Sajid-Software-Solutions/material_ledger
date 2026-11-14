/// People — New person and Edit person, laid out like the Material Request
/// composer: a header with the commands, then numbered cards.
///
/// A saved person is also a Workforce worker, so crews, attendance and
/// timesheets use the same record. Documents are added on the record once
/// the person exists. Nothing is shown as saved until the server confirms;
/// a refusal is shown in place with everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../core/widgets/yorks_mobile_ui.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/app_strings.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../materials/presentation/screens/yorks_v1_material_request_screens.dart'
    show
        YorksV1MaterialFormAction,
        YorksV1MaterialFormCard,
        YorksV1MaterialFormField,
        YorksV1MaterialFormMeta;
import 'people_kit.dart';

class PeoplePersonFormScreen extends ConsumerWidget {
  const PeoplePersonFormScreen({super.key, this.workerId});

  /// The person to edit; null for a new person.
  final String? workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final overview = ref.watch(yorksV1PeopleOverviewProvider);
    final person = workerId == null
        ? null
        : ref.watch(yorksV1PeoplePersonProvider(workerId!));
    final error = overview.error ?? person?.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: PeopleMessage(
            icon: Icons.cloud_off_outlined,
            title: peopleErrorText(error, language),
            action: PS.t(PS.retry, language),
            onPressed: () {
              ref.invalidate(yorksV1PeopleOverviewProvider);
              if (workerId != null) {
                ref.invalidate(yorksV1PeoplePersonProvider(workerId!));
              }
            },
          ),
        ),
      );
    }
    final loadedOverview = overview.valueOrNull;
    final loadedPerson = person?.valueOrNull;
    if (loadedOverview == null || (workerId != null && loadedPerson == null)) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final canManage = loadedPerson?.canManage ?? loadedOverview.canManage;
    if (!canManage) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: PeopleMessage(
            icon: Icons.lock_outline_rounded,
            title: PS.t(PS.errDenied, language),
            action: PS.t(PS.title, language),
            onPressed: () => context.go(peoplePath),
          ),
        ),
      );
    }
    return _PersonForm(
      key: ValueKey('people-form-${workerId ?? 'new'}'),
      person: loadedPerson,
      companies: [for (final company in loadedOverview.companies) company.name],
      language: language,
    );
  }
}

class _PersonForm extends ConsumerStatefulWidget {
  const _PersonForm({
    super.key,
    required this.person,
    required this.companies,
    required this.language,
  });

  final PeoplePerson? person;
  final List<String> companies;
  final AppLanguage language;

  @override
  ConsumerState<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends ConsumerState<_PersonForm> {
  late final TextEditingController _name;
  late final TextEditingController _arabic;
  late final TextEditingController _company;
  late final TextEditingController _profession;
  late final TextEditingController _idProfession;
  late final TextEditingController _unified;
  late final TextEditingController _phone;
  final _companyFocus = FocusNode();
  late PeopleCategory _category;
  String? _dob;
  bool _busy = false;
  bool _tried = false;
  String? _error;
  String? _idempotencyKey;

  AppLanguage get _language => widget.language;
  PeoplePerson? get _person => widget.person;

  @override
  void initState() {
    super.initState();
    final person = _person;
    _name = TextEditingController(text: person?.name ?? '');
    _arabic = TextEditingController(text: person?.arabicName ?? '');
    _company = TextEditingController(text: person?.company ?? '');
    _profession = TextEditingController(
      text: person == null || person.position == 'Not recorded'
          ? ''
          : person.position,
    );
    _idProfession = TextEditingController(text: person?.idProfession ?? '');
    _unified = TextEditingController(text: person?.unifiedNumber ?? '');
    _phone = TextEditingController(text: person?.mobile ?? '');
    _category = person?.category ?? PeopleCategory.labour;
    _dob = person?.dateOfBirth;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _arabic,
      _company,
      _profession,
      _idProfession,
      _unified,
      _phone,
    ]) {
      controller.dispose();
    }
    _companyFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _error = null;
    _idempotencyKey = null;
  });

  String? get _nameError =>
      _tried && _name.text.trim().isEmpty ? PS.t(PS.errName, _language) : null;
  String? get _companyError => _tried && _company.text.trim().isEmpty
      ? PS.t(PS.errCompany, _language)
      : null;

  void _close() {
    final person = _person;
    context.go(person == null ? peoplePath : peoplePersonPath(person.id));
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_name.text.trim().isEmpty || _company.text.trim().isEmpty) return;
    _idempotencyKey ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(yorksV1PeopleRepositoryProvider)
          .savePerson(
            PeopleSavePersonInput(
              workerId: _person?.id,
              fullName: _name.text,
              company: _company.text,
              category: _category,
              position: _profession.text,
              idProfession: _idProfession.text,
              arabicName: _arabic.text,
              dateOfBirth: _dob,
              unifiedNumber: _unified.text,
              mobile: _phone.text,
              expectedVersion: _person?.recordVersion ?? 0,
              idempotencyKey: _idempotencyKey!,
            ),
          );
      if (!mounted) return;
      yorksV1RefreshPeople(ref, workerId: saved.id);
      peopleToast(
        context,
        PS.t(PS.savedToast, _language, {'name': saved.name}),
      );
      context.go(peoplePersonPath(saved.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = peopleErrorText(error, _language);
      });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dob ?? '') ?? DateTime(now.year - 30),
      firstDate: DateTime(1930),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _dob =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      _error = null;
      _idempotencyKey = null;
    });
  }

  // ─── Fields ────────────────────────────────────────────────────────────────

  Widget _text(
    String key,
    TextEditingController controller, {
    String? label,
    String? error,
    TextInputType? keyboard,
    TextDirection? direction,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    keyboardType: keyboard,
    textDirection: direction,
    textCapitalization: capitalization,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(labelText: label, errorText: error),
  );

  Widget _nameField({bool labelled = true}) => _text(
    'people-form-name',
    _name,
    label: labelled ? PS.t(PS.fullName, _language) : null,
    error: _nameError,
    capitalization: TextCapitalization.characters,
  );

  Widget _arabicField({bool labelled = true}) => _text(
    'people-form-arabic',
    _arabic,
    label: labelled ? PS.t(PS.arabicName, _language) : null,
    direction: TextDirection.rtl,
  );

  Widget _professionField({bool labelled = true}) => _text(
    'people-form-profession',
    _profession,
    label: labelled ? PS.t(PS.profession, _language) : null,
    capitalization: TextCapitalization.words,
  );

  Widget _idProfessionField({bool labelled = true}) => _text(
    'people-form-id-profession',
    _idProfession,
    label: labelled ? PS.t(PS.idProfession, _language) : null,
    capitalization: TextCapitalization.words,
  );

  Widget _unifiedField({bool labelled = true}) => _text(
    'people-form-unified',
    _unified,
    label: labelled ? PS.t(PS.unified, _language) : null,
    keyboard: TextInputType.number,
  );

  Widget _mobileField({bool labelled = true}) => _text(
    'people-form-mobile',
    _phone,
    label: labelled ? PS.t(PS.mobile, _language) : null,
    keyboard: TextInputType.phone,
  );

  /// Company, suggesting the companies already recorded.
  Widget _companyField({bool labelled = true}) => RawAutocomplete<String>(
    textEditingController: _company,
    focusNode: _companyFocus,
    optionsBuilder: (value) {
      final query = value.text.trim().toLowerCase();
      return [
        for (final company in widget.companies)
          if (query.isEmpty || company.toLowerCase().contains(query)) company,
      ].take(8);
    },
    onSelected: (_) => _changed(),
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextField(
          key: const ValueKey('people-form-company'),
          controller: controller,
          focusNode: focusNode,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _changed(),
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: labelled ? PS.t(PS.company, _language) : null,
            errorText: _companyError,
            prefixIcon: const Icon(Icons.business_outlined, size: 20),
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
                  leading: const Icon(Icons.business_outlined, size: 18),
                  title: Text(option),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _categoryField() => YorksMobileSegmentedControl<String>(
    key: const ValueKey('people-form-category'),
    selected: _category.wire,
    enabled: !_busy,
    options: [
      YorksMobileSegmentOption(
        value: PeopleCategory.staff.wire,
        label: PS.t(PS.staff, _language),
      ),
      YorksMobileSegmentOption(
        value: PeopleCategory.labour.wire,
        label: PS.t(PS.labour, _language),
      ),
    ],
    onSelected: (value) {
      _category = PeopleCategory.from(value);
      _changed();
    },
  );

  Widget _dobField({bool labelled = true}) => InkWell(
    key: const ValueKey('people-form-dob'),
    onTap: _busy ? null : _pickDob,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: labelled ? PS.t(PS.dob, _language) : null,
        suffixIcon: _dob != null && !_busy
            ? IconButton(
                tooltip: PS.t(PS.clear, _language),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _dob = null;
                  _idempotencyKey = null;
                }),
              )
            : const Icon(Icons.event_outlined),
      ),
      child: Text(
        peopleDate(_dob),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
      ),
    ),
  );

  Widget? _errorBanner() => _error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: YorksMobileCallout(
              key: const ValueKey('people-form-error'),
              icon: Icons.error_outline_rounded,
              title: _error!,
              message: '',
              warning: true,
            ),
          ),
        );

  String get _saveLabel =>
      _busy ? PS.t(PS.saving, _language) : PS.t(PS.save, _language);

  String get _title => _person == null
      ? PS.t(PS.newPerson, _language)
      : PS.t(PS.editPerson, _language, {'name': _person!.name});

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
            key: const ValueKey('people-form-desktop'),
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
                    const SizedBox(height: AppSpacing.xxxl),
                    _personalCard(),
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
    final person = _person;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 920;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              PS.t(PS.title, _language).toUpperCase(),
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
              PS.t(PS.formDescription, _language),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                if (person != null)
                  YorksV1MaterialFormMeta(
                    icon: Icons.tag_rounded,
                    value: person.number,
                  ),
                YorksV1MaterialFormMeta(
                  icon: _category == PeopleCategory.staff
                      ? Icons.badge_outlined
                      : Icons.engineering_outlined,
                  value: peopleCategoryLabel(_category, _language),
                ),
                if (_company.text.trim().isNotEmpty)
                  YorksV1MaterialFormMeta(
                    icon: Icons.business_outlined,
                    value: _company.text.trim(),
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
              key: const ValueKey('people-form-cancel'),
              label: PS.t(PS.cancel, _language),
              onPressed: _busy ? null : _close,
            ),
            YorksV1MaterialFormAction(
              key: const ValueKey('people-form-save'),
              label: _saveLabel,
              icon: Icons.check_rounded,
              primary: true,
              onPressed: _busy ? null : _save,
            ),
          ],
        );
        return Container(
          key: const ValueKey('people-form-hero'),
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

  Widget _grid(List<(TranslatableString, Widget)> fields) => LayoutBuilder(
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
              child: YorksV1MaterialFormField(
                label: PS.t(label, _language),
                child: child,
              ),
            ),
        ],
      );
    },
  );

  Widget _detailsCard() => YorksV1MaterialFormCard(
    key: const ValueKey('people-form-details-card'),
    sectionNumber: 1,
    title: PS.t(PS.personInformation, _language),
    description: PS.t(PS.personInformationDescription, _language),
    child: _grid([
      (PS.fullName, _nameField(labelled: false)),
      (PS.arabicName, _arabicField(labelled: false)),
      (PS.company, _companyField(labelled: false)),
      (PS.profession, _professionField(labelled: false)),
      (PS.idProfession, _idProfessionField(labelled: false)),
      (PS.factCategory, _categoryField()),
    ]),
  );

  Widget _personalCard() => YorksV1MaterialFormCard(
    key: const ValueKey('people-form-personal-card'),
    sectionNumber: 2,
    title: PS.t(PS.personal, _language),
    child: _grid([
      (PS.dob, _dobField(labelled: false)),
      (PS.unified, _unifiedField(labelled: false)),
      (PS.mobile, _mobileField(labelled: false)),
    ]),
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
        key: const ValueKey('people-form-mobile'),
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
              key: const ValueKey('people-form-back'),
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
            PS.t(PS.formDescription, _language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          section(PS.t(PS.personInformation, _language)),
          _nameField(),
          gap,
          _arabicField(),
          gap,
          _companyField(),
          gap,
          _professionField(),
          gap,
          _idProfessionField(),
          gap,
          _categoryField(),
          section(PS.t(PS.personal, _language)),
          _dobField(),
          gap,
          _unifiedField(),
          gap,
          _mobileField(),
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
              key: const ValueKey('people-form-save'),
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

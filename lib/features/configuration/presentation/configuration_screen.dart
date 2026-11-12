/// Configuration — set up the company and every module
/// (docs/yorks-v1/CONFIGURATION_REDESIGN_PLAN.md, PRODUCT_DECISIONS 39).
///
/// Every control here changes something real. A section is edited in place
/// and saved with a reason after reviewing exactly what changes; the server
/// checks the version, role and every value, and keeps the history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_language.dart';
import '../../../shared/models/app_strings.dart';
import '../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../shared/models/yorks_v1_configuration_v2_strings.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../workforce/presentation/attendance/attendance_crews_screen.dart'
    show AttendanceHolidaysCard;
import '../../workforce/presentation/attendance/attendance_common.dart'
    show
        AS,
        AttendancePage,
        AttendanceLoadState,
        attendanceErrorText,
        attendanceStamp,
        attendanceToast;
import '../application/configuration_workspace_providers.dart';
import '../data/configuration_workspace_repository.dart';
import '../domain/configuration_workspace_models.dart';

typedef CS = ConfigStrings;

const _configPath = '/yorks/configuration';

({TranslatableString title, TranslatableString sub, String icon}) _sectionCopy(
  ConfigSection section,
) => switch (section) {
  ConfigSection.checklist => (
    title: CS.secChecklist,
    sub: CS.secChecklistSub,
    icon: 'check',
  ),
  ConfigSection.company => (
    title: CS.secCompany,
    sub: CS.secCompanySub,
    icon: 'company',
  ),
  ConfigSection.projects => (
    title: CS.secProjects,
    sub: CS.secProjectsSub,
    icon: 'folder',
  ),
  ConfigSection.requests => (
    title: CS.secRequests,
    sub: CS.secRequestsSub,
    icon: 'list',
  ),
  ConfigSection.inventory => (
    title: CS.secInventory,
    sub: CS.secInventorySub,
    icon: 'box',
  ),
  ConfigSection.accounts => (
    title: CS.secAccounts,
    sub: CS.secAccountsSub,
    icon: 'coins',
  ),
  ConfigSection.workforce => (
    title: CS.secWorkforce,
    sub: CS.secWorkforceSub,
    icon: 'users',
  ),
  ConfigSection.rentals => (
    title: CS.secRentals,
    sub: CS.secRentalsSub,
    icon: 'bldg',
  ),
  ConfigSection.notifications => (
    title: CS.secNotifications,
    sub: CS.secNotificationsSub,
    icon: 'bell',
  ),
  ConfigSection.access => (
    title: CS.secAccess,
    sub: CS.secAccessSub,
    icon: 'shield',
  ),
  ConfigSection.numbering => (
    title: CS.secNumbering,
    sub: CS.secNumberingSub,
    icon: 'hier',
  ),
  ConfigSection.history => (
    title: CS.secHistory,
    sub: CS.secHistorySub,
    icon: 'history',
  ),
};

/// Sections in their groups, in reading order.
const _groups = <(TranslatableString, List<ConfigSection>)>[
  (CS.navStart, [ConfigSection.checklist]),
  (CS.navCompany, [ConfigSection.company, ConfigSection.numbering]),
  (
    CS.navOperations,
    [
      ConfigSection.projects,
      ConfigSection.requests,
      ConfigSection.inventory,
      ConfigSection.workforce,
      ConfigSection.rentals,
    ],
  ),
  (CS.navFinance, [ConfigSection.accounts]),
  (
    CS.navSystem,
    [ConfigSection.notifications, ConfigSection.access, ConfigSection.history],
  ),
];

List<ConfigSection> _visibleSections(ConfigWorkspace workspace) => [
  for (final (_, sections) in _groups)
    for (final section in sections)
      if (workspace.isAdmin ||
          section == ConfigSection.workforce ||
          section == ConfigSection.rentals)
        section,
];

/// How many checklist items need attention.
int _attentionCount(ConfigWorkspace workspace) {
  final checks = workspace.checks;
  return [
    checks.bankMissing,
    checks.trnMissing,
    checks.pushOff,
    checks.holidaysThisYear == 0,
    checks.activePrUsers == 0,
  ].where((item) => item).length;
}

String configErrorText(Object? error, AppLanguage language) {
  if (error is YorksV1DomainException) {
    final message = '${error.serverMessage ?? ''} ${error.serverCode ?? ''}'
        .toUpperCase();
    if (error.code == YorksV1DomainErrorCode.conflict) {
      return CS.t(CS.errConflict, language);
    }
    if (message.contains('IBAN')) return CS.t(CS.errIban, language);
    if (message.contains('TRN')) return CS.t(CS.errTrn, language);
    if (message.contains('EMAIL')) return CS.t(CS.errEmail, language);
    if (message.contains('TEXT_REQUIRED')) {
      return CS.t(CS.errRequired, language);
    }
    if (message.contains('SUPPORT_CONTACT')) {
      return CS.t(CS.errWhatsapp, language);
    }
    if (message.contains('STAGE')) return CS.t(CS.errStageTotal, language);
    if (message.contains('DEFAULT_FOLDER')) {
      return CS.t(CS.errFolderRequired, language);
    }
    if (message.contains('NAME_TAKEN')) return CS.t(CS.errNameTaken, language);
    if (message.contains('ACCOUNTS_POLICY')) {
      return CS.t(CS.errPolicy, language);
    }
  }
  return attendanceErrorText(error, language);
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class ConfigurationScreen extends ConsumerStatefulWidget {
  const ConfigurationScreen({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<ConfigurationScreen> createState() =>
      _ConfigurationScreenState();
}

class _ConfigurationScreenState extends ConsumerState<ConfigurationScreen> {
  late ConfigSection? _section = ConfigSection.from(widget.initialSection);
  bool _dirty = false;

  Future<void> _select(ConfigSection? section) async {
    if (section == _section) return;
    if (_dirty) {
      final language = ref.read(languageProvider);
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(CS.t(CS.leaveTitle, language)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(CS.t(CS.keepEditing, language)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(CS.t(CS.discard, language)),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() {
      _section = section;
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final workspace = ref.watch(configWorkspaceProvider);
    return workspace.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => _ErrorState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(configWorkspaceProvider),
      ),
      data: (data) {
        final visible = _visibleSections(data);
        final phone = MediaQuery.sizeOf(context).width < 900;
        final selected = _section != null && visible.contains(_section)
            ? _section!
            : (phone ? null : visible.first);
        final nav = _SectionNav(
          workspace: data,
          sections: visible,
          selected: selected,
          language: language,
          onSelect: _select,
        );
        if (phone && selected == null) {
          return AttendancePage(
            language: language,
            title: CS.t(CS.title, language),
            subtitle: CS.t(CS.intro, language),
            onRefresh: () async => refreshConfiguration(ref),
            children: [nav],
          );
        }
        final body = _SectionBody(
          key: ValueKey('config-section-${selected!.wire}-${data.version}'),
          section: selected,
          workspace: data,
          language: language,
          onDirty: (dirty) => _dirty = dirty,
          onOpenSection: _select,
          onBack: phone ? () => _select(null) : null,
        );
        if (phone) return body;
        return ColoredBox(
          color: AccountsV2Colors.bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 0, 22),
                  children: [
                    Text(
                      CS.t(CS.title, language),
                      style: v2Style(22, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CS.t(CS.intro, language),
                      style: v2Style(12.5, color: AccountsV2Colors.mut),
                    ),
                    const SizedBox(height: 14),
                    nav,
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.language,
    required this.error,
    required this.onRetry,
  });

  final AppLanguage language;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AccountsV2Colors.bg,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AccountsV2Panel(
            child: AccountsV2Empty(
              icon: 'alert',
              title: configErrorText(error, language),
              action: AccountsV2Button(
                label: AS.t(AS.retry, language),
                icon: 'undo',
                onPressed: onRetry,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({
    required this.workspace,
    required this.sections,
    required this.selected,
    required this.language,
    required this.onSelect,
  });

  final ConfigWorkspace workspace;
  final List<ConfigSection> sections;
  final ConfigSection? selected;
  final AppLanguage language;
  final ValueChanged<ConfigSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final attention = _attentionCount(workspace);
    return AccountsV2Panel(
      key: const ValueKey('config-nav'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (group, members) in _groups)
            if (members.any(sections.contains)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Text(
                  CS.t(group, language).toUpperCase(),
                  style: v2Style(
                    10.5,
                    weight: FontWeight.w700,
                    color: AccountsV2Colors.mut2,
                  ),
                ),
              ),
              for (final section in members.where(sections.contains))
                Builder(
                  builder: (context) {
                    final copy = _sectionCopy(section);
                    final active = section == selected;
                    return Semantics(
                      selected: active,
                      button: true,
                      child: InkWell(
                        key: ValueKey('config-nav-${section.wire}'),
                        onTap: () => onSelect(section),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: active ? AccountsV2Colors.pri50 : null,
                            border: const Border(
                              top: BorderSide(color: AccountsV2Colors.line2),
                            ),
                          ),
                          child: Row(
                            children: [
                              AccountsV2Icon(
                                copy.icon,
                                size: 18,
                                color: active
                                    ? AccountsV2Colors.pri
                                    : AccountsV2Colors.ink2,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      CS.t(copy.title, language),
                                      style: v2Style(
                                        13.5,
                                        weight: FontWeight.w600,
                                        color: active
                                            ? AccountsV2Colors.pri
                                            : AccountsV2Colors.ink,
                                      ),
                                    ),
                                    Text(
                                      CS.t(copy.sub, language),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: v2Style(
                                        11.5,
                                        color: AccountsV2Colors.mut,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (section == ConfigSection.checklist &&
                                  attention > 0)
                                AccountsV2TabBadge('$attention', bad: true),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
        ],
      ),
    );
  }
}

// ─── Section body and the save flow ──────────────────────────────────────────

class _SectionBody extends ConsumerStatefulWidget {
  const _SectionBody({
    super.key,
    required this.section,
    required this.workspace,
    required this.language,
    required this.onDirty,
    required this.onOpenSection,
    this.onBack,
  });

  final ConfigSection section;
  final ConfigWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<bool> onDirty;
  final ValueChanged<ConfigSection> onOpenSection;
  final VoidCallback? onBack;

  @override
  ConsumerState<_SectionBody> createState() => _SectionBodyState();
}

class _SectionBodyState extends ConsumerState<_SectionBody> {
  /// Pending changes by a stable key, so editing a value twice keeps one.
  final Map<String, ConfigChange> _pending = {};

  AppLanguage get _language => widget.language;
  ConfigWorkspace get _workspace => widget.workspace;
  bool get _editable => _workspace.canEdit(widget.section);

  void stage(String key, ConfigChange? change) {
    setState(() {
      if (change == null) {
        _pending.remove(key);
      } else {
        _pending[key] = change;
      }
    });
    widget.onDirty(_pending.isNotEmpty);
  }

  void _discard() {
    setState(_pending.clear);
    widget.onDirty(false);
  }

  Future<void> _review() async {
    final repository = ref.read(configWorkspaceRepositoryProvider);
    final key = ConfigWorkspaceRepository.newKey();
    final changes = _pending.values.toList();
    final version = await showDialog<int>(
      context: context,
      builder: (_) => _ReviewDialog(
        language: _language,
        changes: changes,
        onSave: (reason) => repository.apply(
          section: widget.section,
          changes: changes,
          reason: reason,
          expectedVersion: _workspace.version,
          idempotencyKey: key,
        ),
      ),
    );
    if (version == null || !mounted) return;
    widget.onDirty(false);
    attendanceToast(context, CS.t(CS.saved, _language, {'v': version}));
    refreshConfiguration(ref);
  }

  Object? pendingValue(String key) => _pending[key]?.json['value'];
  bool isPending(String key) => _pending.containsKey(key);
  Map<String, ConfigChange> get pending => _pending;

  @override
  Widget build(BuildContext context) {
    final copy = _sectionCopy(widget.section);
    final language = _language;
    final content = switch (widget.section) {
      ConfigSection.checklist => _checklist(context),
      ConfigSection.company => _CompanySection(this),
      ConfigSection.projects => _FoldersSection(this),
      ConfigSection.requests => _RequestsSection(this),
      ConfigSection.inventory => _InventorySection(this),
      ConfigSection.accounts => _AccountsSection(this),
      ConfigSection.workforce => _workforce(context),
      ConfigSection.rentals => _RentalsSection(this),
      ConfigSection.notifications => _NotificationsSection(this),
      ConfigSection.access => _access(context),
      ConfigSection.numbering => _numbering(),
      ConfigSection.history => const _HistorySection(),
    };
    final readOnlySection =
        !_editable &&
        const [
          ConfigSection.company,
          ConfigSection.projects,
          ConfigSection.requests,
          ConfigSection.inventory,
          ConfigSection.accounts,
          ConfigSection.rentals,
          ConfigSection.notifications,
        ].contains(widget.section);
    return AttendancePage(
      language: language,
      eyebrow: widget.onBack == null ? null : CS.t(CS.title, language),
      title: CS.t(copy.title, language),
      subtitle: CS.t(copy.sub, language),
      readOnly: readOnlySection,
      onRefresh: () async => refreshConfiguration(ref),
      actions: [
        if (widget.onBack != null)
          AccountsV2Button(
            key: const ValueKey('config-back'),
            label: CS.t(CS.sections, language),
            icon: 'undo',
            kind: AccountsV2ButtonKind.ghost,
            onPressed: widget.onBack,
          ),
      ],
      children: [
        ...(content is List<Widget> ? content : [content as Widget]),
        if (_pending.isNotEmpty)
          AccountsV2BottomBar(
            key: const ValueKey('config-save-bar'),
            child: _SaveBar(
              count: _pending.length,
              language: language,
              onDiscard: _discard,
              onSave: _review,
            ),
          ),
      ],
    );
  }

  // ─── Read-only sections ────────────────────────────────────────────────────

  List<Widget> _checklist(BuildContext context) {
    final checks = _workspace.checks;
    final language = _language;
    final year = _workspace.today.length >= 4
        ? _workspace.today.substring(0, 4)
        : '';
    final items =
        <
          ({
            String key,
            String title,
            String detail,
            bool ok,
            ConfigSection? section,
            String? path,
          })
        >[
          (
            key: 'bank',
            title: CS.t(CS.chkBank, language),
            detail: checks.bankMissing
                ? CS.t(CS.chkBankMissing, language)
                : '${_workspace.text('company.bank_name')} · ${_workspace.text('company.bank_iban')}',
            ok: !checks.bankMissing,
            section: ConfigSection.company,
            path: null,
          ),
          (
            key: 'trn',
            title: CS.t(CS.chkTrn, language),
            detail: checks.trnMissing
                ? CS.t(CS.empty, language)
                : _workspace.text('company.trn'),
            ok: !checks.trnMissing,
            section: ConfigSection.company,
            path: null,
          ),
          (
            key: 'holidays',
            title: CS.t(CS.chkHolidays, language, {'year': year}),
            detail: checks.holidaysThisYear == 0
                ? CS.t(CS.chkHolidaysNone, language)
                : CS.t(CS.chkHolidaysCount, language, {
                    'n': checks.holidaysThisYear,
                  }),
            ok: checks.holidaysThisYear > 0,
            section: ConfigSection.workforce,
            path: null,
          ),
          (
            key: 'pr',
            title: CS.t(CS.chkPr, language),
            detail: checks.activePrUsers == 0
                ? CS.t(CS.chkPrNone, language)
                : '${checks.activePrUsers}',
            ok: checks.activePrUsers > 0,
            section: ConfigSection.access,
            path: null,
          ),
          (
            key: 'push',
            title: CS.t(CS.chkPush, language),
            detail: CS.t(checks.pushOff ? CS.off : CS.on, language),
            ok: !checks.pushOff,
            section: ConfigSection.notifications,
            path: null,
          ),
          (
            key: 'folders',
            title: CS.t(CS.chkFolders, language),
            detail: '${checks.defaultFolders}',
            ok: true,
            section: ConfigSection.projects,
            path: null,
          ),
          (
            key: 'rentals',
            title: CS.t(CS.chkRentals, language),
            detail: CS.t(checks.rentalsOff ? CS.off : CS.on, language),
            ok: true,
            section: ConfigSection.rentals,
            path: null,
          ),
        ];
    final attention = items.where((item) => !item.ok).length;
    return [
      if (attention == 0)
        AccountsV2Note(
          tone: AccountsV2NoteTone.ok,
          child: Text(CS.t(CS.allGood, language), style: v2Style(13)),
        ),
      AccountsV2Panel(
        key: const ValueKey('config-checklist'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              _Row(
                key: ValueKey('config-check-${item.key}'),
                leading: Icon(
                  item.ok
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: item.ok ? AccountsV2Colors.ok : AccountsV2Colors.bad,
                ),
                title: item.title,
                detail: item.detail,
                trailing: item.section == null
                    ? null
                    : AccountsV2Button(
                        label: CS.t(item.ok ? CS.open : CS.fix, language),
                        size: AccountsV2ButtonSize.small,
                        kind: item.ok
                            ? AccountsV2ButtonKind.normal
                            : AccountsV2ButtonKind.primary,
                        onPressed: () => widget.onOpenSection(item.section!),
                      ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _workforce(BuildContext context) {
    final language = _language;
    return [
      _OffDays(host: this),
      AttendanceHolidaysCard(
        key: const ValueKey('config-workforce-holidays'),
        language: language,
        onChanged: () => refreshConfiguration(ref),
      ),
      AccountsV2Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              key: const ValueKey('config-workforce-admin'),
              title: CS.t(CS.shiftsLocations, language),
              detail: CS.t(CS.shiftsLocationsHint, language),
              trailing: _LinkButton(
                label: CS.t(CS.open, language),
                path: '/yorks/workforce/administration',
              ),
            ),
            _Row(
              key: const ValueKey('config-workforce-crews'),
              title: CS.t(CS.crewsLink, language),
              detail: '',
              trailing: _LinkButton(
                label: CS.t(CS.open, language),
                path: '/yorks/workforce/crews',
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _access(BuildContext context) {
    final language = _language;
    return [
      AccountsV2Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Row(
              key: const ValueKey('config-access-users'),
              title: CS.t(CS.usersLink, language),
              detail: CS.t(CS.usersLinkHint, language),
              trailing: _LinkButton(
                label: CS.t(CS.open, language),
                path: '/users',
              ),
            ),
          ],
        ),
      ),
      AccountsV2Panel(
        key: const ValueKey('config-roles'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountsV2CardHead(
              title: CS.t(CS.rolesTitle, language),
              icon: 'usercog',
              subtitle: CS.t(CS.rolesSub, language),
            ),
            for (final (role, line) in [
              ('admin', CS.roleAdmin),
              ('senior_mechanical_engineer', CS.roleSme),
              ('project_manager', CS.roleGlobalEngineer),
              ('project_engineer', CS.rolePe),
              ('site_engineer', CS.roleSe),
              ('procurement', CS.roleProcurement),
              ('accountant', CS.roleAccountant),
              ('pr', CS.rolePr),
            ])
              _Row(
                title: role == 'project_manager'
                    ? CS.t(CS.roleGlobalEngineer, language).split(':').first
                    : YorksV1AuditStrings.roleLabel(role, language),
                detail: role == 'project_manager'
                    ? _capitalize(
                        CS
                            .t(line, language)
                            .split(':')
                            .skip(1)
                            .join(':')
                            .trim(),
                      )
                    : CS.t(line, language),
              ),
          ],
        ),
      ),
      AccountsV2Note(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CS.t(CS.signInRules, language),
              style: v2Style(13, weight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(CS.t(CS.signInRulesBody, language), style: v2Style(12.5)),
          ],
        ),
      ),
    ];
  }

  List<Widget> _numbering() {
    final language = _language;
    String example(String pattern) => pattern
        .replaceAll('{PROJECT_REF}', 'YRA-321')
        .replaceAll('{PROJECT}', 'YRA-321')
        .replaceAll('{NNN}', '001')
        .replaceAll('{###}', '001');
    final rows = [
      (CS.numMr, _workspace.text('numbering.material_request_pattern')),
      (CS.numDispatch, _workspace.text('numbering.dispatch_pattern')),
      (CS.numReturn, _workspace.text('numbering.return_pattern')),
      (CS.numInvoice, _workspace.text('numbering.invoice_pattern')),
      (CS.numCrewRequest, 'CRQ-{YYYY}-{NNNN}'),
    ];
    return [
      AccountsV2Note(
        child: Text(CS.t(CS.numberingHow, language), style: v2Style(12.5)),
      ),
      AccountsV2Panel(
        key: const ValueKey('config-numbering'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, pattern) in rows)
              _Row(
                title: CS.t(label, language),
                detail: pattern.isEmpty
                    ? CS.t(CS.empty, language)
                    : '$pattern  ·  ${CS.t(CS.example, language, {'x': pattern == 'CRQ-{YYYY}-{NNNN}' ? 'CRQ-2026-0001' : example(pattern)})}',
              ),
            _Row(
              title: CS.t(CS.numProject, language),
              detail: CS.t(CS.numProjectValue, language),
            ),
          ],
        ),
      ),
    ];
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => AccountsV2Button(
    label: label,
    size: AccountsV2ButtonSize.small,
    onPressed: () => context.go(path),
  );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.count,
    required this.language,
    required this.onDiscard,
    required this.onSave,
  });

  final int count;
  final AppLanguage language;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          CS.t(CS.changesPending, language, {'n': count}),
          style: v2Style(13, weight: FontWeight.w600),
        ),
        AccountsV2Button(
          key: const ValueKey('config-discard'),
          label: CS.t(CS.discard, language),
          onPressed: onDiscard,
        ),
        AccountsV2Button(
          key: const ValueKey('config-review'),
          label: CS.t(CS.reviewSave, language),
          icon: 'check',
          kind: AccountsV2ButtonKind.primary,
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.language,
    required this.changes,
    required this.onSave,
  });

  final AppLanguage language;
  final List<ConfigChange> changes;
  final Future<int> Function(String reason) onSave;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().length < 8) {
      setState(() => _error = CS.t(CS.reason, widget.language));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final version = await widget.onSave(_reason.text);
      if (mounted) Navigator.of(context).pop(version);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = configErrorText(error, widget.language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('config-review-dialog'),
        title: Text(
          CS.t(CS.reviewTitle, language, {'n': widget.changes.length}),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  CS.t(CS.reviewBody, language),
                  style: v2Style(12.5, color: AccountsV2Colors.mut),
                ),
                const SizedBox(height: 10),
                for (final change in widget.changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change.label,
                          style: v2Style(13, weight: FontWeight.w600),
                        ),
                        if (change.before != null || change.after != null)
                          Text(
                            '${(change.before ?? '').isEmpty ? CS.t(CS.empty, language) : change.before}  →  ${(change.after ?? '').isEmpty ? CS.t(CS.empty, language) : change.after}',
                            style: v2Style(12.5, color: AccountsV2Colors.ink2),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('config-reason'),
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: CS.t(CS.reason, language),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: AccountsV2Note(
                      key: const ValueKey('config-review-error'),
                      tone: AccountsV2NoteTone.bad,
                      child: Text(_error!, style: v2Style(13)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(CS.t(CS.keepEditing, language)),
          ),
          FilledButton(
            key: const ValueKey('config-save'),
            onPressed: _busy ? null : _save,
            child: Text(CS.t(CS.save, language)),
          ),
        ],
      ),
    );
  }
}

// ─── Building blocks ─────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    this.detail = '',
    this.leading,
    this.trailing,
  });

  final String title;
  final String detail;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AccountsV2Colors.line2)),
    ),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: v2Style(13.5, weight: FontWeight.w600)),
              if (detail.isNotEmpty)
                Text(detail, style: v2Style(12.5, color: AccountsV2Colors.mut)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    ),
  );
}

/// A switch with its meaning underneath.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.changed = false,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool changed;

  @override
  Widget build(BuildContext context) => _Row(
    title: changed ? '$title  •' : title,
    detail: hint,
    trailing: Switch(
      value: value,
      activeTrackColor: AccountsV2Colors.pri,
      onChanged: onChanged,
    ),
  );
}

/// A text setting staged on every keystroke.
class _TextSetting extends StatefulWidget {
  const _TextSetting({
    required this.host,
    required this.settingKey,
    required this.label,
    this.width,
    this.normalize,
  });

  final _SectionBodyState host;
  final String settingKey;
  final TranslatableString label;
  final double? width;
  final String Function(String)? normalize;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.host._workspace.text(widget.settingKey),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final language = host._language;
    final published = host._workspace.text(widget.settingKey);
    return AccountsV2TextField(
      key: ValueKey('config-field-${widget.settingKey}'),
      label: CS.t(widget.label, language),
      controller: _controller,
      enabled: host._editable,
      width: widget.width,
      onChanged: (text) {
        final value = (widget.normalize ?? (t) => t.trim())(text);
        host.stage(
          widget.settingKey,
          value == published
              ? null
              : ConfigChange.setting(
                  widget.settingKey,
                  value,
                  label: CS.t(widget.label, language),
                  before: published,
                ),
        );
      },
    );
  }
}

Widget _group(String title, List<Widget> children) => AccountsV2Panel(
  child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: v2Style(14, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: children),
      ],
    ),
  ),
);

// ─── Company ─────────────────────────────────────────────────────────────────

class _CompanySection extends StatelessWidget {
  const _CompanySection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final ws = host._workspace;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final wide = phone ? null : 420.0;
    final narrow = phone ? null : 200.0;
    String value(String key) {
      final pending = host.pendingValue(key);
      return pending is String ? pending : ws.text(key);
    }

    TextSpan line(String text) => TextSpan(text: '$text\n');
    final formats = ws.setting('documents.allowed_formats')?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(CS.t(CS.grpNames, language), [
          _TextSetting(
            host: host,
            settingKey: 'company.legal_name',
            label: CS.fLegalName,
            width: wide,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.short_name',
            label: CS.fShortName,
            width: narrow,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.arabic_name',
            label: CS.fArabicName,
            width: wide,
          ),
        ]),
        const SizedBox(height: accountsV2Gap),
        _group(CS.t(CS.grpContact, language), [
          _TextSetting(
            host: host,
            settingKey: 'company.address',
            label: CS.fAddress,
            width: wide,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.phone',
            label: CS.fPhone,
            width: narrow,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.fax',
            label: CS.fFax,
            width: narrow,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.email',
            label: CS.fEmail,
            width: narrow,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.trn',
            label: CS.fTrn,
            width: narrow,
            normalize: (t) => t.replaceAll(RegExp(r'\s'), ''),
          ),
        ]),
        const SizedBox(height: accountsV2Gap),
        _group(CS.t(CS.grpBank, language), [
          _TextSetting(
            host: host,
            settingKey: 'company.bank_name',
            label: CS.fBankName,
            width: narrow,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.bank_account_name',
            label: CS.fAccountName,
            width: wide,
          ),
          _TextSetting(
            host: host,
            settingKey: 'company.bank_iban',
            label: CS.fIban,
            width: wide,
            normalize: (t) => t.replaceAll(' ', '').toUpperCase(),
          ),
        ]),
        const SizedBox(height: accountsV2Gap),
        _group(CS.t(CS.grpSupport, language), [
          _TextSetting(
            host: host,
            settingKey: 'support.developer_whatsapp',
            label: CS.fWhatsapp,
            width: narrow,
            normalize: (t) => t.replaceAll(RegExp(r'[\s-]'), ''),
          ),
        ]),
        const SizedBox(height: accountsV2Gap),
        AccountsV2Panel(
          key: const ValueKey('config-letterhead'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.grpPreview, language),
                icon: 'doc',
                subtitle: CS.t(CS.previewSub, language),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AccountsV2Colors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        value('company.legal_name'),
                        style: v2Style(15, weight: FontWeight.w700),
                      ),
                      if (value('company.arabic_name').isNotEmpty)
                        Text(
                          value('company.arabic_name'),
                          textDirection: TextDirection.rtl,
                          style: v2Style(13.5, weight: FontWeight.w600),
                        ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          style: v2Style(12, color: AccountsV2Colors.ink2),
                          children: [
                            if (value('company.address').isNotEmpty)
                              line(value('company.address')),
                            line(
                              [
                                if (value('company.phone').isNotEmpty)
                                  '${CS.t(CS.fPhone, language)} ${value('company.phone')}',
                                if (value('company.fax').isNotEmpty)
                                  '${CS.t(CS.fFax, language)} ${value('company.fax')}',
                                if (value('company.email').isNotEmpty)
                                  value('company.email'),
                              ].join('  ·  '),
                            ),
                            if (value('company.trn').isNotEmpty)
                              line(
                                '${CS.t(CS.fTrn, language)} ${value('company.trn')}',
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 18),
                      if (value('company.bank_iban').isEmpty)
                        Text(
                          CS.t(CS.chkBankMissing, language),
                          style: v2Style(12, color: AccountsV2Colors.bad),
                        )
                      else
                        Text(
                          '${value('company.bank_name')}  ·  ${value('company.bank_account_name')}\n${CS.t(CS.fIban, language)} ${value('company.bank_iban')}',
                          style: v2Style(12, color: AccountsV2Colors.ink2),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: accountsV2Gap),
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.grpFacts, language),
                icon: 'shield',
              ),
              _Row(
                title: CS.t(CS.fCurrency, language),
                detail: ws.text('regional.currency'),
              ),
              _Row(
                title: CS.t(CS.fTimezone, language),
                detail: ws.text('regional.timezone'),
              ),
              _Row(
                title: CS.t(CS.fWorkspace, language),
                detail: ws.text('company.workspace_name'),
              ),
              _Row(
                title: CS.t(CS.fFileTypes, language),
                detail: formats is List ? formats.join(', ') : '',
              ),
              _Row(
                title: CS.t(CS.fFileSize, language),
                detail: '${ws.text('documents.maximum_file_size_mb')} MB',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Lists ───────────────────────────────────────────────────────────────────

/// Add, rename, archive and restore one list. Changes are staged on the
/// section and saved together.
class _ListEditor extends StatefulWidget {
  const _ListEditor({
    required this.host,
    required this.kind,
    required this.title,
    required this.items,
    this.archiveSystem = false,
    this.allowAlias = false,
    this.unitFields = false,
  });

  final _SectionBodyState host;
  final String kind;
  final String title;
  final List<ConfigListItem> items;
  final bool archiveSystem;
  final bool allowAlias;
  final bool unitFields;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String _type = 'count';
  int _decimals = 0;
  bool _showArchived = false;
  int _newCount = 0;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  _SectionBodyState get host => widget.host;
  AppLanguage get language => host._language;

  String _key(String id, String action) => '${widget.kind}.$id.$action';

  bool _active(ConfigListItem item) {
    final archive = host.pending[_key(item.id, 'archive')];
    final restore = host.pending[_key(item.id, 'restore')];
    if (archive != null) return false;
    if (restore != null) return true;
    return item.active;
  }

  String _nameOf(ConfigListItem item) {
    final rename = host.pending[_key(item.id, 'rename')];
    return rename == null ? item.name : '${rename.json['name']}';
  }

  Future<String?> _ask(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('config-list-dialog-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: CS.t(CS.newName, language),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(CS.t(CS.keepEditing, language)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(CS.t(CS.save, language)),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _add() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (widget.unitFields && _code.text.trim().isEmpty) return;
    _newCount++;
    host.stage(
      '${widget.kind}.new$_newCount.create',
      ConfigChange(
        {
          'kind': widget.kind,
          'action': 'create',
          'name': name,
          if (widget.unitFields) ...{
            'code': _code.text.trim(),
            'type': _type,
            'decimals': _decimals,
          },
        },
        label: '${CS.t(CS.add, language)} · ${widget.title}',
        after: widget.unitFields ? '$name (${_code.text.trim()})' : name,
      ),
    );
    _name.clear();
    _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final editable = host._editable;
    final archivedCount = widget.items.where((i) => !_active(i)).length;
    final shown = [
      for (final item in widget.items)
        if (_showArchived || _active(item) || !item.active) ...[
          if (_showArchived || _active(item)) item,
        ],
    ];
    final created = [
      for (final entry in host.pending.entries)
        if (entry.key.startsWith('${widget.kind}.new')) entry,
    ];
    final phone = AccountsV2Breakpoints.isPhone(context);
    return AccountsV2Panel(
      key: ValueKey('config-list-${widget.kind}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(title: widget.title, icon: 'list'),
          if (archivedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  label: Text(
                    CS.t(CS.showArchived, language, {'n': archivedCount}),
                  ),
                  selected: _showArchived,
                  onSelected: (value) => setState(() => _showArchived = value),
                ),
              ),
            ),
          for (final item in shown)
            _Row(
              key: ValueKey('config-item-${widget.kind}-${item.id}'),
              title: _nameOf(item),
              detail: [
                if (item.code.isNotEmpty && widget.unitFields) item.code,
                if (widget.unitFields) '${item.extra['type']}',
                if (item.system) CS.t(CS.system, language),
                if (!_active(item)) CS.t(CS.archived, language),
                if (item.aliases.isNotEmpty)
                  '${CS.t(CS.aliases, language)}: ${item.aliases.join(', ')}',
                for (final entry in host.pending.entries)
                  if (entry.key == _key(item.id, 'add_alias'))
                    '+ ${entry.value.json['name']}',
              ].join(' · '),
              trailing: !editable
                  ? null
                  : Wrap(
                      spacing: 6,
                      children: [
                        if (!widget.unitFields)
                          AccountsV2Button(
                            label: CS.t(CS.rename, language),
                            size: AccountsV2ButtonSize.small,
                            kind: AccountsV2ButtonKind.ghost,
                            onPressed: () async {
                              final name = await _ask(
                                CS.t(CS.rename, language),
                                _nameOf(item),
                              );
                              if (name == null || name.isEmpty) return;
                              host.stage(
                                _key(item.id, 'rename'),
                                name == item.name
                                    ? null
                                    : ConfigChange(
                                        {
                                          'kind': widget.kind,
                                          'action': 'rename',
                                          'id': item.id,
                                          'name': name,
                                        },
                                        label:
                                            '${CS.t(CS.rename, language)} · ${widget.title}',
                                        before: item.name,
                                        after: name,
                                      ),
                              );
                            },
                          ),
                        if (widget.allowAlias)
                          AccountsV2Button(
                            label: CS.t(CS.addAlias, language),
                            size: AccountsV2ButtonSize.small,
                            kind: AccountsV2ButtonKind.ghost,
                            onPressed: () async {
                              final name = await _ask(
                                CS.t(CS.addAlias, language),
                                '',
                              );
                              if (name == null || name.isEmpty) return;
                              host.stage(
                                _key(item.id, 'add_alias'),
                                ConfigChange(
                                  {
                                    'kind': widget.kind,
                                    'action': 'add_alias',
                                    'id': item.id,
                                    'name': name,
                                  },
                                  label:
                                      '${CS.t(CS.addAlias, language)} · ${item.name}',
                                  after: name,
                                ),
                              );
                            },
                          ),
                        if (!item.system || widget.archiveSystem)
                          AccountsV2Button(
                            key: ValueKey(
                              'config-toggle-${widget.kind}-${item.id}',
                            ),
                            label: CS.t(
                              _active(item) ? CS.archive : CS.restore,
                              language,
                            ),
                            size: AccountsV2ButtonSize.small,
                            kind: AccountsV2ButtonKind.ghost,
                            onPressed: () {
                              final action = _active(item)
                                  ? 'archive'
                                  : 'restore';
                              final other = action == 'archive'
                                  ? 'restore'
                                  : 'archive';
                              if (host.pending.containsKey(
                                _key(item.id, other),
                              )) {
                                host.stage(_key(item.id, other), null);
                                return;
                              }
                              host.stage(
                                _key(item.id, action),
                                ConfigChange(
                                  {
                                    'kind': widget.kind,
                                    'action': action,
                                    'id': item.id,
                                  },
                                  label:
                                      '${CS.t(action == 'archive' ? CS.archive : CS.restore, language)} · ${item.name}',
                                ),
                              );
                            },
                          ),
                      ],
                    ),
            ),
          for (final entry in created)
            _Row(
              title: entry.value.after ?? '',
              detail: CS.t(CS.newItem, language),
              trailing: AccountsV2Button(
                label: CS.t(CS.discard, language),
                size: AccountsV2ButtonSize.small,
                kind: AccountsV2ButtonKind.ghost,
                onPressed: () => host.stage(entry.key, null),
              ),
            ),
          if (editable)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  AccountsV2TextField(
                    key: ValueKey('config-add-${widget.kind}'),
                    label: CS.t(CS.newName, language),
                    controller: _name,
                    width: phone ? null : 260,
                  ),
                  if (widget.unitFields) ...[
                    AccountsV2TextField(
                      label: CS.t(CS.unitCode, language),
                      controller: _code,
                      width: 120,
                    ),
                    AccountsV2Select<String>(
                      label: CS.t(CS.unitType, language),
                      value: _type,
                      width: 150,
                      options: const [
                        ('count', 'count'),
                        ('length', 'length'),
                        ('area', 'area'),
                        ('volume', 'volume'),
                        ('weight', 'weight'),
                        ('other', 'other'),
                      ],
                      onChanged: (value) => setState(() => _type = value),
                    ),
                    AccountsV2Select<int>(
                      label: CS.t(CS.unitDecimals, language),
                      value: _decimals,
                      width: 110,
                      options: const [
                        (0, '0'),
                        (1, '1'),
                        (2, '2'),
                        (3, '3'),
                        (4, '4'),
                      ],
                      onChanged: (value) => setState(() => _decimals = value),
                    ),
                  ],
                  AccountsV2Button(
                    key: ValueKey('config-add-${widget.kind}-button'),
                    label: CS.t(CS.add, language),
                    icon: 'plus',
                    onPressed: _add,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Projects: default folders ───────────────────────────────────────────────

class _FoldersSection extends StatelessWidget {
  const _FoldersSection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final templates = [...host._workspace.boqTemplates]
      ..sort((a, b) {
        final ao = _order(a);
        final bo = _order(b);
        return ao != bo ? ao.compareTo(bo) : a.name.compareTo(b.name);
      });
    final on = templates.where(_active).toList();
    final offList = templates.where((t) => !_active(t)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountsV2Note(
          child: Text(CS.t(CS.foldersHow, language), style: v2Style(12.5)),
        ),
        const SizedBox(height: accountsV2Gap),
        AccountsV2Panel(
          key: const ValueKey('config-folders'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.foldersTitle, language),
                icon: 'folder',
              ),
              for (final (index, template) in on.indexed)
                _folderRow(context, template, index, on),
              for (final template in offList)
                _folderRow(context, template, -1, on),
              if (host._editable) _NewFolder(host: host),
            ],
          ),
        ),
      ],
    );
  }

  bool _active(ConfigListItem item) {
    final change =
        host.pending['boq.${item.id}.activate'] ??
        host.pending['boq.${item.id}.deactivate'];
    if (change != null) return change.json['action'] == 'activate';
    return item.active;
  }

  int _order(ConfigListItem item) {
    final move = host.pending['boq.${item.id}.move'];
    return move == null ? item.order : (move.json['order'] as int);
  }

  String _name(ConfigListItem item) =>
      '${host.pending['boq.${item.id}.rename']?.json['name'] ?? item.name}';

  Widget _folderRow(
    BuildContext context,
    ConfigListItem item,
    int index,
    List<ConfigListItem> on,
  ) {
    final language = host._language;
    final active = _active(item);
    final editable = host._editable;
    void move(int delta) {
      final target = on[index + delta];
      final a = _order(item);
      final b = _order(target);
      final aNew = a == b ? b + delta : b;
      final bNew = a == b ? a : a;
      for (final (moved, order, original) in [
        (item, aNew, item.order),
        (target, bNew, target.order),
      ]) {
        host.stage(
          'boq.${moved.id}.move',
          order == original
              ? null
              : ConfigChange(
                  {
                    'kind': 'boq_template',
                    'action': 'move',
                    'id': moved.id,
                    'order': order,
                  },
                  label: '${CS.foldersTitle.active(language)} · ${moved.name}',
                  before: '${moved.order}',
                  after: '$order',
                ),
        );
      }
    }

    return _Row(
      key: ValueKey('config-folder-${item.code}'),
      title: _name(item),
      detail: [
        if (item.usage > 0) CS.t(CS.usedBy, language, {'n': item.usage}),
      ].join(),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (editable && active && index > 0)
            IconButton(
              tooltip: CS.t(CS.moveUp, language),
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: () => move(-1),
            ),
          if (editable && active && index >= 0 && index < on.length - 1)
            IconButton(
              tooltip: CS.t(CS.moveDown, language),
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: () => move(1),
            ),
          if (editable)
            AccountsV2Button(
              label: CS.t(CS.rename, language),
              size: AccountsV2ButtonSize.small,
              kind: AccountsV2ButtonKind.ghost,
              onPressed: () async {
                final controller = TextEditingController(text: _name(item));
                final name = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(CS.t(CS.rename, language)),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: CS.t(CS.newName, language),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(CS.t(CS.keepEditing, language)),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text.trim()),
                        child: Text(CS.t(CS.save, language)),
                      ),
                    ],
                  ),
                ).whenComplete(controller.dispose);
                if (name == null || name.isEmpty) return;
                host.stage(
                  'boq.${item.id}.rename',
                  name == item.name
                      ? null
                      : ConfigChange(
                          {
                            'kind': 'boq_template',
                            'action': 'rename',
                            'id': item.id,
                            'name': name,
                          },
                          label: CS.t(CS.rename, language),
                          before: item.name,
                          after: name,
                        ),
                );
              },
            ),
          Switch(
            key: ValueKey('config-folder-switch-${item.code}'),
            value: active,
            activeTrackColor: AccountsV2Colors.pri,
            onChanged: !editable
                ? null
                : (value) {
                    host.stage('boq.${item.id}.activate', null);
                    host.stage('boq.${item.id}.deactivate', null);
                    if (value == item.active) return;
                    final action = value ? 'activate' : 'deactivate';
                    host.stage(
                      'boq.${item.id}.$action',
                      ConfigChange(
                        {
                          'kind': 'boq_template',
                          'action': action,
                          'id': item.id,
                        },
                        label: item.name,
                        before: CS.t(item.active ? CS.on : CS.off, language),
                        after: CS.t(value ? CS.on : CS.off, language),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

class _NewFolder extends StatefulWidget {
  const _NewFolder({required this.host});

  final _SectionBodyState host;

  @override
  State<_NewFolder> createState() => _NewFolderState();
}

class _NewFolderState extends State<_NewFolder> {
  final _name = TextEditingController();
  int _count = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final language = host._language;
    final created = [
      for (final entry in host.pending.entries)
        if (entry.key.startsWith('boq.new')) entry,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in created)
          _Row(
            title: '${entry.value.after}',
            detail: CS.t(CS.newItem, language),
            trailing: AccountsV2Button(
              label: CS.t(CS.discard, language),
              size: AccountsV2ButtonSize.small,
              kind: AccountsV2ButtonKind.ghost,
              onPressed: () => host.stage(entry.key, null),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              AccountsV2TextField(
                key: const ValueKey('config-new-folder'),
                label: CS.t(CS.newFolder, language),
                controller: _name,
                width: AccountsV2Breakpoints.isPhone(context) ? null : 300,
              ),
              AccountsV2Button(
                key: const ValueKey('config-new-folder-add'),
                label: CS.t(CS.add, language),
                icon: 'plus',
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  _count++;
                  host.stage(
                    'boq.new$_count.create',
                    ConfigChange(
                      {
                        'kind': 'boq_template',
                        'action': 'create',
                        'name': name,
                      },
                      label: CS.t(CS.foldersTitle, language),
                      after: name,
                    ),
                  );
                  _name.clear();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Requests ────────────────────────────────────────────────────────────────

class _RequestsSection extends StatelessWidget {
  const _RequestsSection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final ws = host._workspace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.rulesTitle, language),
                icon: 'list',
              ),
              _Row(
                title: CS.t(CS.defaultTiming, language),
                trailing: SizedBox(
                  width: 170,
                  child: AccountsV2Select<String>(
                    key: const ValueKey('config-default-timing'),
                    label: CS.t(CS.defaultTiming, language),
                    value:
                        (host.pendingValue('requests.default_timing') ??
                                ws.text('requests.default_timing'))
                            .toString(),
                    options: [
                      ('normal', CS.t(CS.timingNormal, language)),
                      ('urgent', CS.t(CS.timingUrgent, language)),
                    ],
                    onChanged: host._editable
                        ? (value) => _flagOrValue(
                            host,
                            'requests.default_timing',
                            value,
                            CS.t(CS.defaultTiming, language),
                          )
                        : null,
                  ),
                ),
              ),
              _settingSwitch(
                host,
                'requests.urgent_enabled',
                CS.urgentAllowed,
                CS.urgentAllowedHint,
                fallback: true,
              ),
              _settingSwitch(
                host,
                'requests.allow_authorized_creator_self_approval',
                CS.selfApproval,
                CS.selfApprovalHint,
                fallback: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: accountsV2Gap),
        _ListEditor(
          host: host,
          kind: 'mr_category',
          title: CS.t(CS.mrCategories, language),
          items: ws.mrCategories,
          archiveSystem: true,
        ),
        const SizedBox(height: accountsV2Gap),
        _ListEditor(
          host: host,
          kind: 'mr_department',
          title: CS.t(CS.mrDepartments, language),
          items: ws.mrDepartments,
          archiveSystem: true,
        ),
      ],
    );
  }
}

void _flagOrValue(
  _SectionBodyState host,
  String key,
  Object value,
  String label,
) {
  final published = host._workspace.setting(key)?.value;
  host.stage(
    key,
    value == published
        ? null
        : ConfigChange.setting(
            key,
            value,
            label: label,
            before: published?.toString(),
          ),
  );
}

Widget _settingSwitch(
  _SectionBodyState host,
  String key,
  TranslatableString title,
  TranslatableString hint, {
  bool fallback = false,
}) {
  final language = host._language;
  final pending = host.pendingValue(key);
  final value = pending is bool
      ? pending
      : host._workspace.flag(key, fallback: fallback);
  return _SwitchRow(
    key: ValueKey('config-switch-$key'),
    title: CS.t(title, language),
    hint: CS.t(hint, language),
    value: value,
    changed: host.isPending(key),
    onChanged: host._editable
        ? (next) => _flagOrValue(host, key, next, CS.t(title, language))
        : null,
  );
}

// ─── Inventory ───────────────────────────────────────────────────────────────

class _InventorySection extends StatelessWidget {
  const _InventorySection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final ws = host._workspace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.sourcingTitle, language),
                icon: 'truck',
              ),
              _settingSwitch(
                host,
                'procurement.require_external_source_readiness',
                CS.externalReadiness,
                CS.externalReadinessHint,
              ),
              _Row(
                title: CS.t(CS.warehouseFirst, language),
                leading: const Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: accountsV2Gap),
        _ListEditor(
          host: host,
          kind: 'inventory_category',
          title: CS.t(CS.categoriesTitle, language),
          items: ws.inventoryCategories,
          allowAlias: true,
        ),
        const SizedBox(height: accountsV2Gap),
        _ListEditor(
          host: host,
          kind: 'unit',
          title: CS.t(CS.unitsTitle, language),
          items: ws.units,
          unitFields: true,
        ),
      ],
    );
  }
}

// ─── Accounts ────────────────────────────────────────────────────────────────

class _AccountsSection extends StatefulWidget {
  const _AccountsSection(this.host);

  final _SectionBodyState host;

  @override
  State<_AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends State<_AccountsSection> {
  late final ConfigWorkspace _ws = widget.host._workspace;
  late final _terms = TextEditingController(
    text: '${_ws.paymentTermsDays ?? ''}',
  );
  late final _lead = TextEditingController(
    text: '${_ws.reminderLeadDays ?? ''}',
  );
  late final List<
    ({String? key, TextEditingController name, TextEditingController percent})
  >
  _stages = [
    for (final stage in _ws.stages)
      if (stage.active)
        (
          key: stage.key,
          name: TextEditingController(text: stage.name),
          percent: TextEditingController(text: stage.percent),
        ),
  ];

  @override
  void dispose() {
    _terms.dispose();
    _lead.dispose();
    for (final stage in _stages) {
      stage.name.dispose();
      stage.percent.dispose();
    }
    super.dispose();
  }

  _SectionBodyState get host => widget.host;
  AppLanguage get language => host._language;

  double get _total => _stages.fold(
    0,
    (sum, stage) => sum + (double.tryParse(stage.percent.text.trim()) ?? 0),
  );

  void _stagePolicy() {
    final terms = int.tryParse(_terms.text.trim());
    final lead = int.tryParse(_lead.text.trim());
    final same = terms == _ws.paymentTermsDays && lead == _ws.reminderLeadDays;
    host.stage(
      'accounts.policy',
      same || terms == null || lead == null
          ? null
          : ConfigChange(
              {
                'kind': 'accounts_policy',
                'payment_terms_days': terms,
                'reminder_lead_days': lead,
              },
              label: CS.t(CS.policyTitle, language),
              before: '${_ws.paymentTermsDays} / ${_ws.reminderLeadDays}',
              after: '$terms / $lead',
            ),
    );
  }

  void _stageStages() {
    String describe(Iterable<(String, String)> rows) =>
        rows.map((r) => '${r.$1} ${r.$2}%').join(', ');
    final before = describe([
      for (final stage in _ws.stages)
        if (stage.active) (stage.name, stage.percent),
    ]);
    final after = describe([
      for (final stage in _stages)
        (stage.name.text.trim(), stage.percent.text.trim()),
    ]);
    host.stage(
      'accounts.stages',
      before == after
          ? null
          : ConfigChange(
              {
                'kind': 'accounts_stages',
                'stages': [
                  for (final stage in _stages)
                    {
                      'key': ?stage.key,
                      'name': stage.name.text.trim(),
                      'percent': stage.percent.text.trim(),
                    },
                ],
              },
              label: CS.t(CS.stagesTitle, language),
              before: before,
              after: after,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = host._editable;
    final total = _total;
    final totalOk = (total - 100).abs() < 0.00005;
    final phone = AccountsV2Breakpoints.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(CS.t(CS.policyTitle, language), [
          AccountsV2TextField(
            key: const ValueKey('config-payment-terms'),
            label: CS.t(CS.paymentTerms, language),
            controller: _terms,
            numeric: true,
            enabled: editable,
            width: phone ? null : 200,
            onChanged: (_) => _stagePolicy(),
          ),
          AccountsV2TextField(
            key: const ValueKey('config-reminder-lead'),
            label: CS.t(CS.reminderLead, language),
            controller: _lead,
            numeric: true,
            enabled: editable,
            width: phone ? null : 220,
            onChanged: (_) => _stagePolicy(),
          ),
        ]),
        const SizedBox(height: accountsV2Gap),
        AccountsV2Panel(
          key: const ValueKey('config-stages'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.stagesTitle, language),
                icon: 'chart',
                subtitle: CS.t(CS.stagesHow, language),
              ),
              for (final (index, stage) in _stages.indexed)
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AccountsV2Colors.line2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AccountsV2TextField(
                          key: ValueKey('config-stage-name-$index'),
                          label: CS.t(CS.stageName, language),
                          controller: stage.name,
                          enabled: editable,
                          onChanged: (_) {
                            setState(() {});
                            _stageStages();
                          },
                        ),
                      ),
                      SizedBox(width: phone ? 6 : 10),
                      AccountsV2TextField(
                        key: ValueKey('config-stage-percent-$index'),
                        label: CS.t(CS.stagePercent, language),
                        controller: stage.percent,
                        numeric: true,
                        enabled: editable,
                        width: phone ? 76 : 100,
                        onChanged: (_) {
                          setState(() {});
                          _stageStages();
                        },
                      ),
                      if (editable && _stages.length > 1)
                        IconButton(
                          tooltip: CS.t(CS.archive, language),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            setState(() => _stages.removeAt(index));
                            _stageStages();
                          },
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      CS.t(CS.total, language, {
                        'p': total.toStringAsFixed(
                          total == total.roundToDouble() ? 0 : 2,
                        ),
                      }),
                      key: const ValueKey('config-stage-total'),
                      style: v2Style(
                        13.5,
                        weight: FontWeight.w700,
                        color: totalOk
                            ? AccountsV2Colors.ok
                            : AccountsV2Colors.bad,
                      ),
                    ),
                    if (editable && _stages.length < 12)
                      AccountsV2Button(
                        key: const ValueKey('config-add-stage'),
                        label: CS.t(CS.addStage, language),
                        icon: 'plus',
                        onPressed: () {
                          setState(
                            () => _stages.add((
                              key: null,
                              name: TextEditingController(),
                              percent: TextEditingController(text: '0'),
                            )),
                          );
                          _stageStages();
                        },
                      ),
                  ],
                ),
              ),
              if (!totalOk)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: AccountsV2Note(
                    tone: AccountsV2NoteTone.bad,
                    child: Text(
                      CS.t(CS.errStageTotal, language),
                      style: v2Style(12.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Workforce: weekly off days ─────────────────────────────────────────────

class _OffDays extends StatelessWidget {
  const _OffDays({required this.host});

  final _SectionBodyState host;

  static const _order = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final published = host._workspace.weeklyOffDays;
    final pending = host.pendingValue('workforce.weekly_off_days');
    final current = pending is List
        ? [for (final day in pending) day.toString()]
        : published;
    String describe(List<String> days) => days.isEmpty
        ? CS.t(CS.empty, language)
        : [
            for (final day in _order)
              if (days.contains(day)) CS.t(CS.weekdays[day]!, language),
          ].join(', ');
    return AccountsV2Panel(
      key: const ValueKey('config-off-days'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              CS.t(CS.offDaysTitle, language),
              style: v2Style(14, weight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              CS.t(CS.offDaysHint, language),
              style: v2Style(12.5, color: AccountsV2Colors.mut),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in _order)
                  AccountsV2Button(
                    key: ValueKey('config-off-day-$day'),
                    label: CS.t(CS.weekdays[day]!, language),
                    icon: current.contains(day) ? 'check' : null,
                    kind: current.contains(day)
                        ? AccountsV2ButtonKind.primary
                        : AccountsV2ButtonKind.normal,
                    onPressed: !host._editable
                        ? null
                        : () {
                            final selected = !current.contains(day);
                            final next = [
                              for (final d in _order)
                                if (d == day ? selected : current.contains(d))
                                  d,
                            ];
                            if (next.length > 6) return;
                            final same =
                                next.length == published.length &&
                                next.every(published.contains);
                            host.stage(
                              'workforce.weekly_off_days',
                              same
                                  ? null
                                  : ConfigChange(
                                      {
                                        'kind': 'setting',
                                        'key': 'workforce.weekly_off_days',
                                        'value': next,
                                      },
                                      label: CS.t(CS.offDaysTitle, language),
                                      before: describe(published),
                                      after: describe(next),
                                    ),
                            );
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rentals and notifications ───────────────────────────────────────────────

class _RentalsSection extends StatelessWidget {
  const _RentalsSection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    final ws = host._workspace;
    final pending = host.pending['rentals']?.json;
    final enabled = pending == null
        ? ws.rentalsEnabled
        : pending['enabled'] == true;
    final push = pending == null ? ws.rentalsPush : pending['push'] == true;
    void set({required bool enabled, required bool push}) {
      final effectivePush = enabled && push;
      host.stage(
        'rentals',
        enabled == ws.rentalsEnabled && effectivePush == ws.rentalsPush
            ? null
            : ConfigChange(
                {'kind': 'rentals', 'enabled': enabled, 'push': effectivePush},
                label: CS.t(CS.secRentals, language),
                before:
                    '${CS.t(ws.rentalsEnabled ? CS.on : CS.off, language)} / ${CS.t(ws.rentalsPush ? CS.on : CS.off, language)}',
                after:
                    '${CS.t(enabled ? CS.on : CS.off, language)} / ${CS.t(effectivePush ? CS.on : CS.off, language)}',
              ),
      );
    }

    return AccountsV2Panel(
      key: const ValueKey('config-rentals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitchRow(
            key: const ValueKey('config-rentals-enabled'),
            title: CS.t(CS.rentalsEnabled, language),
            hint: CS.t(CS.rentalsEnabledHint, language),
            value: enabled,
            changed: pending != null,
            onChanged: host._editable
                ? (value) => set(enabled: value, push: push)
                : null,
          ),
          _SwitchRow(
            key: const ValueKey('config-rentals-push'),
            title: CS.t(CS.rentalsPush, language),
            hint: CS.t(CS.rentalsPushHint, language),
            value: enabled && push,
            onChanged: host._editable && enabled
                ? (value) => set(enabled: enabled, push: value)
                : null,
          ),
          if (ws.rentalsLastRun != null)
            _Row(
              title: CS.t(CS.lastRun, language, {
                'at': attendanceStamp(ws.rentalsLastRun),
              }),
            ),
        ],
      ),
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection(this.host);

  final _SectionBodyState host;

  @override
  Widget build(BuildContext context) {
    final language = host._language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _settingSwitch(
                host,
                'notifications.push_enabled',
                CS.pushEnabled,
                CS.pushEnabledHint,
                fallback: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: accountsV2Gap),
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CS.t(CS.dailyReminders, language),
                icon: 'clock',
              ),
              _Row(title: CS.t(CS.remMonthEnd, language)),
              _Row(title: CS.t(CS.remCrewRequests, language)),
              _Row(title: CS.t(CS.remRentals, language)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── History ─────────────────────────────────────────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final centre = ref.watch(yorksV1ConfigurationCentreProvider);
    return centre.when(
      loading: () => const AccountsV2Panel(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => AccountsV2Panel(
        child: AccountsV2Empty(
          icon: 'alert',
          title: configErrorText(error, language),
        ),
      ),
      data: (data) {
        if (data.history.isEmpty) {
          return AccountsV2Panel(
            child: AccountsV2Empty(
              icon: 'history',
              title: CS.t(CS.historyEmpty, language),
            ),
          );
        }
        return AccountsV2Panel(
          key: const ValueKey('config-history'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final publication in data.history)
                _Row(
                  title:
                      '${publication.versionLabel} · “${publication.reason}”',
                  detail: CS.t(CS.historyLine, language, {
                    'who': publication.publishedBy,
                    'when': attendanceStamp(publication.publishedAt),
                    'n': publication.changeCount,
                  }),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens a section from elsewhere in the app.
String configurationPath(ConfigSection section) =>
    '$_configPath?section=${section.wire}';

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// People — the home screen, laid out like the Material Request Centre:
/// header with its commands, the view switcher, metric tiles that filter,
/// and one panel with search, filters and the list.
///
/// Needs attention lists every current document that has expired or ends
/// within 60 days, expired first. Staff and Labour are the registers, a
/// table on desktop and cards on a phone, paged on the server.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../shared/services/yorks_v1_people_workbook.dart';
import 'people_import_dialog.dart';
import 'people_kit.dart';
import 'person_attachments.dart';

enum PeopleView { attention, staff, labour }

/// What a metric tile shows.
enum _Tile { total, staff, labour, expired, expiring, passes }

class PeopleCentreScreen extends ConsumerStatefulWidget {
  const PeopleCentreScreen({super.key, this.initialView});

  /// `attention`, `staff` or `labour`.
  final String? initialView;

  @override
  ConsumerState<PeopleCentreScreen> createState() => _PeopleCentreScreenState();
}

class _PeopleCentreScreenState extends ConsumerState<PeopleCentreScreen> {
  static const _pageSize = 25;

  late PeopleView _view = switch (widget.initialView) {
    'staff' => PeopleView.staff,
    'labour' => PeopleView.labour,
    _ => PeopleView.attention,
  };
  _Tile? _tile;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _company;
  String _sort = 'name';
  int _offset = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  PeopleListQuery get _listQuery => PeopleListQuery(
    category: _view == PeopleView.labour
        ? PeopleCategory.labour
        : PeopleCategory.staff,
    company: _company,
    search: _query,
    sort: _sort,
    limit: _pageSize,
    offset: _offset,
  );

  void _setView(PeopleView view, {_Tile? tile}) => setState(() {
    _view = view;
    _tile = tile;
    _offset = 0;
  });

  void _onTile(_Tile tile) => switch (tile) {
    _Tile.total || _Tile.staff => _setView(PeopleView.staff, tile: tile),
    _Tile.labour => _setView(PeopleView.labour, tile: tile),
    _Tile.expired ||
    _Tile.expiring ||
    _Tile.passes => _setView(PeopleView.attention, tile: tile),
  };

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _offset = 0;
      });
    });
  }

  void _refresh() => yorksV1RefreshPeople(ref);

  Future<void> _export(AppLanguage language) async {
    setState(() => _exporting = true);
    try {
      final repository = ref.read(yorksV1PeopleRepositoryProvider);
      final staffPage = await repository.list(
        const PeopleListQuery(category: PeopleCategory.staff, limit: 1000),
      );
      final labourPage = await repository.list(
        const PeopleListQuery(category: PeopleCategory.labour, limit: 1000),
      );
      final people = [...staffPage.rows, ...labourPage.rows];
      final bytes = peopleEncodeWorkbook(
        peopleExportSheets(people, today: staffPage.today),
      );
      final saved = await ref
          .read(yorksV1BoqWorkbookFileServiceProvider)
          .saveWorkbook(
            bytes: bytes,
            suggestedName: 'People_${staffPage.today}.xlsx',
          );
      if (!mounted || !saved) return;
      peopleToast(context, PS.t(PS.exportDone, language, {'n': people.length}));
    } catch (error) {
      if (mounted) peopleToast(context, peopleErrorText(error, language));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    final imported = await showPeopleImportDialog(context);
    if (imported == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final overview = ref.watch(yorksV1PeopleOverviewProvider);
    final flags = ref.watch(yorksV1FeatureFlagsProvider);
    final canManage = overview.valueOrNull?.canManage ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppSpacing.compactBreakpoint;
    final horizontal = width >= AppSpacing.yorksV1DesktopBreakpoint
        ? AppSpacing.xl
        : AppSpacing.md;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          key: const ValueKey('people-centre'),
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.lg,
            horizontal,
            AppSpacing.xxxl,
          ),
          children: [
            _Header(
              language: language,
              compact: compact,
              canManage: canManage,
              exporting: _exporting,
              onRefresh: _refresh,
              onImport: _import,
              onExport: () => _export(language),
              onAdd: () => context.go(peopleNewPath),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ViewBar(
              language: language,
              view: _view,
              onView: (view) => _setView(view),
              showWorkforce: flags.workforceAttendanceV2,
              showCompany: flags.companyDocuments,
            ),
            const SizedBox(height: AppSpacing.md),
            overview.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => PeopleSurface(
                child: PeopleMessage(
                  icon: Icons.cloud_off_outlined,
                  title: peopleErrorText(error, language),
                  action: PS.t(PS.retry, language),
                  onPressed: _refresh,
                ),
              ),
              data: (data) => _Metrics(
                overview: data,
                language: language,
                selected: _tile,
                onTile: _onTile,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PeopleSurface(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _Toolbar(
                      language: language,
                      search: _search,
                      onSearch: _onSearch,
                      companies: [
                        for (final company
                            in overview.valueOrNull?.companies ?? const [])
                          company.name,
                      ],
                      company: _company,
                      onCompany: (value) => setState(() {
                        _company = value;
                        _offset = 0;
                      }),
                      sort: _view == PeopleView.attention ? null : _sort,
                      onSort: (value) => setState(() {
                        _sort = value;
                        _offset = 0;
                      }),
                    ),
                  ),
                  const Divider(height: 1),
                  if (_view == PeopleView.attention)
                    _AttentionList(
                      overview: overview.valueOrNull,
                      language: language,
                      search: _query,
                      company: _company,
                      tile: _tile,
                      failed: overview.hasError,
                    )
                  else
                    _Register(
                      query: _listQuery,
                      language: language,
                      onPage: (offset) => setState(() => _offset = offset),
                      canManage: canManage,
                      onImport: _import,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.language,
    required this.compact,
    required this.canManage,
    required this.exporting,
    required this.onRefresh,
    required this.onImport,
    required this.onExport,
    required this.onAdd,
  });

  final AppLanguage language;
  final bool compact;
  final bool canManage;
  final bool exporting;
  final VoidCallback onRefresh;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 40 : 46,
          height: compact ? 40 : 46,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(
            Icons.badge_outlined,
            color: AppColors.blue,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PS.t(PS.title, language),
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.displaySmall)
                        .copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                PS.t(PS.centreDescription, language),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: [
        Tooltip(
          message: PS.t(PS.refresh, language),
          child: SizedBox.square(
            dimension: AppSpacing.minTapTarget,
            child: IconButton(
              key: const ValueKey('people-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        if (canManage)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: OutlinedButton.icon(
              key: const ValueKey('people-import'),
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(PS.t(PS.importExcel, language)),
            ),
          ),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: OutlinedButton.icon(
            key: const ValueKey('people-export'),
            onPressed: exporting ? null : onExport,
            icon: exporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(PS.t(PS.exportExcel, language)),
          ),
        ),
        if (canManage)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: FilledButton.icon(
              key: const ValueKey('people-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(PS.t(PS.addPerson, language)),
            ),
          ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: AppSpacing.md),
          actions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: AppSpacing.lg),
        Flexible(child: actions),
      ],
    );
  }
}

/// The Material Request register switcher: one outlined bar of views, and
/// the Workforce and Timesheets destinations beside it.
class _ViewBar extends StatelessWidget {
  const _ViewBar({
    required this.language,
    required this.view,
    required this.onView,
    required this.showWorkforce,
    this.showCompany = false,
  });

  final AppLanguage language;
  final PeopleView view;
  final ValueChanged<PeopleView> onView;
  final bool showWorkforce;
  final bool showCompany;

  @override
  Widget build(BuildContext context) {
    Widget segment(PeopleView value, IconData icon, String label) {
      final selected = value == view;
      return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('people-view-${value.name}'),
          onTap: () => onView(value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            color: selected ? AppColors.blueContainer : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.blue : AppColors.inkSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: selected ? AppColors.blue : AppColors.ink,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bar = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            children: [
              segment(
                PeopleView.attention,
                Icons.warning_amber_rounded,
                PS.t(PS.viewAttention, language),
              ),
              const VerticalDivider(width: 1),
              segment(
                PeopleView.staff,
                Icons.badge_outlined,
                PS.t(PS.staff, language),
              ),
              const VerticalDivider(width: 1),
              segment(
                PeopleView.labour,
                Icons.engineering_outlined,
                PS.t(PS.labour, language),
              ),
            ],
          ),
        ),
      ),
    );
    if (!showWorkforce && !showCompany) {
      return Align(alignment: AlignmentDirectional.centerStart, child: bar);
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        bar,
        if (showCompany)
          OutlinedButton.icon(
            key: const ValueKey('people-link-company'),
            onPressed: () => context.go(RoutePaths.yorksV1CompanyDocuments),
            icon: const Icon(Icons.business_center_outlined, size: 18),
            label: Text(YorksV1ShellStrings.companyDocuments.active(language)),
          ),
        if (showWorkforce) ...[
          OutlinedButton.icon(
            key: const ValueKey('people-link-workforce'),
            onPressed: () => context.go(RoutePaths.yorksV1Workforce),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: Text(PS.t(PS.linkWorkforce, language)),
          ),
          OutlinedButton.icon(
            key: const ValueKey('people-link-timesheets'),
            onPressed: () => context.go(RoutePaths.yorksV1WorkforceSheets),
            icon: const Icon(Icons.calendar_view_month_outlined, size: 18),
            label: Text(PS.t(PS.linkTimesheets, language)),
          ),
        ],
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.overview,
    required this.language,
    required this.selected,
    required this.onTile,
  });

  final PeopleOverview overview;
  final AppLanguage language;
  final _Tile? selected;
  final ValueChanged<_Tile> onTile;

  @override
  Widget build(BuildContext context) {
    final passes = [PeopleDocumentKind.cicpaPass, PeopleDocumentKind.cmwPass]
        .fold<int>(0, (sum, kind) {
          final counts = overview.byKind[kind];
          return sum + (counts == null ? 0 : counts.expired + counts.expiring);
        });
    final tiles = [
      (
        _Tile.total,
        PS.kpiTotal,
        PS.kpiTotalHint,
        overview.total,
        Icons.groups_outlined,
        AppColors.blue,
        AppColors.blueContainer,
      ),
      (
        _Tile.staff,
        PS.staff,
        PS.kpiStaffHint,
        overview.staff,
        Icons.badge_outlined,
        AppColors.purple,
        AppColors.purpleContainer,
      ),
      (
        _Tile.labour,
        PS.labour,
        PS.kpiLabourHint,
        overview.labour,
        Icons.engineering_outlined,
        AppColors.success,
        AppColors.successContainer,
      ),
      (
        _Tile.expired,
        PS.kpiExpired,
        PS.kpiExpiredHint,
        overview.expired,
        Icons.error_outline_rounded,
        AppColors.error,
        AppColors.errorContainer,
      ),
      (
        _Tile.expiring,
        PS.kpiExpiring,
        PS.kpiExpiringHint,
        overview.expiring,
        Icons.schedule_rounded,
        AppColors.warning,
        AppColors.warningContainer,
      ),
      (
        _Tile.passes,
        PS.kpiPasses,
        PS.kpiPassesHint,
        passes,
        Icons.verified_user_outlined,
        AppColors.neutralText,
        AppColors.neutralContainer,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= AppSpacing.wideBreakpoint
            ? 6
            : width >= AppSpacing.compactBreakpoint
            ? 3
            : 2;
        const gap = AppSpacing.sm;
        final cardWidth = (width - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (tile, label, hint, value, icon, fg, bg) in tiles)
              SizedBox(
                width: cardWidth,
                child: PeopleMetricCard(
                  key: ValueKey('people-metric-${tile.name}'),
                  label: PS.t(label, language),
                  hint: PS.t(hint, language),
                  value: value,
                  icon: icon,
                  foreground: fg,
                  background: bg,
                  selected: selected == tile,
                  onTap: () => onTile(tile),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.language,
    required this.search,
    required this.onSearch,
    required this.companies,
    required this.company,
    required this.onCompany,
    required this.sort,
    required this.onSort,
  });

  final AppLanguage language;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final List<String> companies;
  final String? company;
  final ValueChanged<String?> onCompany;

  /// Null hides the sort control.
  final String? sort;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      key: const ValueKey('people-search'),
      controller: search,
      onChanged: onSearch,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: PS.t(PS.searchHint, language),
      ),
    );
    final companyField = DropdownButtonFormField<String?>(
      key: const ValueKey('people-company'),
      initialValue: companies.contains(company) ? company : null,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.apartment_outlined, size: 20),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(PS.t(PS.allCompanies, language)),
        ),
        for (final name in companies)
          DropdownMenuItem<String?>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onCompany,
    );
    final sortField = sort == null
        ? null
        : DropdownButtonFormField<String>(
            key: const ValueKey('people-sort'),
            initialValue: sort,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.sort_rounded, size: 20),
            ),
            items: [
              DropdownMenuItem(
                value: 'name',
                child: Text(PS.t(PS.sortName, language)),
              ),
              DropdownMenuItem(
                value: 'expiry',
                child: Text(PS.t(PS.sortExpiry, language)),
              ),
              DropdownMenuItem(
                value: 'company',
                child: Text(PS.t(PS.sortCompany, language)),
              ),
            ],
            onChanged: (value) {
              if (value != null) onSort(value);
            },
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: companyField),
                  if (sortField != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: sortField),
                  ],
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 5, child: searchField),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: companyField),
            if (sortField != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: sortField),
            ],
          ],
        );
      },
    );
  }
}

/// Every current document expired or ending within 60 days.
class _AttentionList extends StatelessWidget {
  const _AttentionList({
    required this.overview,
    required this.language,
    required this.search,
    required this.company,
    required this.tile,
    this.failed = false,
  });

  final PeopleOverview? overview;
  final AppLanguage language;
  final String search;
  final String? company;
  final _Tile? tile;

  /// The overview could not be read; the message above says why.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final data = overview;
    if (data == null) {
      if (failed) return const SizedBox(height: AppSpacing.xl);
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final needle = search.toLowerCase();
    final items = [
      for (final item in data.attention)
        if ((company == null || item.company == company) &&
            (needle.isEmpty ||
                item.personName.toLowerCase().contains(needle) ||
                item.personNumber.toLowerCase().contains(needle) ||
                item.company.toLowerCase().contains(needle) ||
                (item.document.number ?? '').toLowerCase().contains(needle)) &&
            switch (tile) {
              _Tile.expired =>
                item.document.status == PeopleDocumentStatus.expired,
              _Tile.expiring =>
                item.document.status == PeopleDocumentStatus.expiring,
              _Tile.passes => item.document.kind.isPass,
              _ => true,
            })
          item,
    ];
    if (items.isEmpty) {
      return PeopleMessage(
        icon: Icons.verified_outlined,
        title: PS.t(PS.attentionEmpty, language),
        body: PS.t(PS.attentionEmptyBody, language),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            PS.t(PS.attentionDescription, language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items) ...[
            _AttentionRow(item: item, language: language),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.language});

  final PeopleAttentionItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final document = item.document;
    final colors = peopleStatusColors(document.status);
    final kind = peopleKindLabel(
      document.kind,
      language,
      label: document.label,
    );
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('people-attention-${document.id}'),
        onTap: () => context.go(peoplePersonPath(item.personId)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      peopleKindIcon(document.kind),
                      color: colors.color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.personNumber,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.blue,
                          ),
                        ),
                        Text(
                          item.personName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            kind,
                            if (document.number != null) document.number!,
                            item.company,
                            peopleCategoryLabel(item.category, language),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final when = Column(
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    peopleDate(document.expiryDate),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    peopleDaysText(document, language),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: when),
                        PeopleStatusPill(
                          status: document.status,
                          language: language,
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: AppSpacing.md),
                  when,
                  const SizedBox(width: AppSpacing.md),
                  PeopleStatusPill(status: document.status, language: language),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Staff or Labour, a page at a time.
class _Register extends ConsumerWidget {
  const _Register({
    required this.query,
    required this.language,
    required this.onPage,
    required this.canManage,
    required this.onImport,
  });

  final PeopleListQuery query;
  final AppLanguage language;
  final ValueChanged<int> onPage;
  final bool canManage;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(yorksV1PeopleListProvider(query));
    // A paperclip beside each person with files (PRODUCT_DECISIONS 47).
    final attached =
        ref.watch(yorksV1PeopleAttachmentCountsProvider).valueOrNull ??
        const <String, int>{};
    return page.when(
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => PeopleMessage(
        icon: Icons.cloud_off_outlined,
        title: peopleErrorText(error, language),
        action: PS.t(PS.retry, language),
        onPressed: () => ref.invalidate(yorksV1PeopleListProvider(query)),
      ),
      data: (data) {
        if (data.total == 0) {
          final filtered = query.search.isNotEmpty || query.company != null;
          return PeopleMessage(
            icon: Icons.person_search_outlined,
            title: PS.t(filtered ? PS.emptyRegister : PS.emptyAll, language),
            body: filtered ? null : PS.t(PS.emptyAllBody, language),
            action: !filtered && canManage
                ? PS.t(PS.importExcel, language)
                : null,
            onPressed: !filtered && canManage ? onImport : null,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 1040
                  ? _RegisterTable(
                      rows: data.rows,
                      language: language,
                      attached: attached,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final person in data.rows) ...[
                            _PersonCard(
                              person: person,
                              language: language,
                              attached: attached[person.id] ?? 0,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      PS.t(PS.range, language, {
                        'a': data.offset + 1,
                        'b': data.offset + data.rows.length,
                        'n': data.total,
                      }),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('people-page-previous'),
                    onPressed: data.offset == 0
                        ? null
                        : () => onPage(
                            (data.offset - query.limit).clamp(0, data.total),
                          ),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('people-page-next'),
                    onPressed: data.offset + data.rows.length >= data.total
                        ? null
                        : () => onPage(data.offset + query.limit),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The register as a table: Person, Company, Profession, then one column
/// per document.
class _RegisterTable extends StatelessWidget {
  const _RegisterTable({
    required this.rows,
    required this.language,
    this.attached = const {},
  });

  final List<PeoplePerson> rows;
  final AppLanguage language;

  /// Attachments per person, by worker id.
  final Map<String, int> attached;

  static const _flex = [30, 18, 16, 11, 11, 11, 11, 11, 11];

  @override
  Widget build(BuildContext context) {
    final header = AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );
    final headings = [
      PS.t(PS.colPerson, language),
      PS.t(PS.colCompany, language),
      PS.t(PS.colProfession, language),
      PS.t(PS.kindVisa, language),
      PS.t(PS.kindPassport, language),
      PS.t(PS.kindLabourCard, language),
      PS.t(PS.kindIloe, language),
      PS.t(PS.kindEmiratesId, language),
      PS.t(PS.colPasses, language),
    ];
    Widget cell(int index, Widget child) => Expanded(
      flex: _flex[index],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: child,
      ),
    );
    return Column(
      key: const ValueKey('people-register-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              for (final (index, heading) in headings.indexed)
                cell(
                  index,
                  Text(
                    heading.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: header,
                  ),
                ),
              const SizedBox(width: 24),
            ],
          ),
        ),
        for (final person in rows)
          InkWell(
            key: ValueKey('people-row-${person.id}'),
            onTap: () => context.go(peoplePersonPath(person.id)),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  cell(
                    0,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                person.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelLarge.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            RecordAttachmentCount(
                              key: ValueKey('people-attached-${person.id}'),
                              count: attached[person.id] ?? 0,
                              language: language,
                            ),
                          ],
                        ),
                        Text(
                          [
                            person.number,
                            if (person.arabicName != null) person.arabicName!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  cell(
                    1,
                    Text(
                      person.company,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  cell(
                    2,
                    Text(
                      person.profession == 'Not recorded'
                          ? '—'
                          : person.profession,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  for (final (offset, kind) in [
                    PeopleDocumentKind.visa,
                    PeopleDocumentKind.passport,
                    PeopleDocumentKind.labourCard,
                    PeopleDocumentKind.iloe,
                    PeopleDocumentKind.emiratesId,
                  ].indexed)
                    cell(
                      3 + offset,
                      PeopleExpiryCell(
                        document: person.current(kind),
                        language: language,
                      ),
                    ),
                  cell(8, _PassesSummary(person: person, language: language)),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The soonest-ending pass, or a dash.
class _PassesSummary extends StatelessWidget {
  const _PassesSummary({required this.person, required this.language});

  final PeoplePerson person;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final passes = [
      for (final document in person.documents)
        if (document.kind.isPass) document,
    ];
    if (passes.isEmpty) {
      return Text(
        '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.mutedLight),
      );
    }
    passes.sort(
      (a, b) => (a.expiryDate ?? '9999').compareTo(b.expiryDate ?? '9999'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PeopleExpiryCell(document: passes.first, language: language),
        if (passes.length > 1)
          Text(
            PS.t(PS.passesCount, language, {'n': passes.length}),
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

/// The register as cards, for a phone or a narrow window.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.language,
    this.attached = 0,
  });

  final PeoplePerson person;
  final AppLanguage language;
  final int attached;

  @override
  Widget build(BuildContext context) {
    final attention = person.attention;
    final colors = peopleStatusColors(attention);
    final next = person.nextExpiry;
    final chips = [
      for (final kind in const [
        PeopleDocumentKind.visa,
        PeopleDocumentKind.labourCard,
        PeopleDocumentKind.iloe,
        PeopleDocumentKind.passport,
      ])
        if (person.current(kind) != null) person.current(kind)!,
      for (final document in person.documents)
        if (document.kind.isPass && document.expiryDate != null) document,
    ];
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('people-card-${person.id}'),
        onTap: () => context.go(peoplePersonPath(person.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      person.category == PeopleCategory.staff
                          ? Icons.badge_outlined
                          : Icons.engineering_outlined,
                      color: colors.color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              person.number,
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            RecordAttachmentCount(
                              key: ValueKey('people-attached-${person.id}'),
                              count: attached,
                              language: language,
                            ),
                          ],
                        ),
                        Text(
                          person.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            person.company,
                            if (person.profession != 'Not recorded')
                              person.profession,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PeopleStatusPill(status: attention, language: language),
                ],
              ),
              if (next != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  PS.t(PS.nextExpiry, language, {
                    'doc': peopleKindLabel(
                      next.kind,
                      language,
                      label: next.label,
                    ),
                    'date': peopleDate(next.expiryDate),
                  }),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (chips.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final document in chips)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${peopleKindLabel(document.kind, language)} ',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            Flexible(
                              child: PeopleExpiryCell(
                                document: document,
                                language: language,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Company documents — the home screen, laid out like People and the
/// Material Request Centre: header with its commands, the view switcher,
/// metric tiles that filter, and one panel with search, filters and the
/// list.
///
/// Needs attention lists every current document that has expired or ends
/// within 60 days, expired first. Licences & permits, Vehicles, Insurance
/// and CICPA passes are the registers, a table on desktop and cards on a
/// phone, paged on the server.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_company_documents.dart';
import '../../../shared/services/yorks_v1_bulk_attach.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../shared/providers/yorks_v1_company_documents_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/services/yorks_v1_company_workbook.dart';
import '../../../shared/services/yorks_v1_people_workbook.dart'
    show peopleEncodeWorkbook;
import 'company_import_dialog.dart';
import '../../people_records/presentation/bulk_attachments.dart';
import 'company_attachments.dart';
import 'company_kit.dart';

enum CompanyView {
  attention([]),
  licences([CompanyRecordKind.entity, CompanyRecordKind.item]),
  vehicles([CompanyRecordKind.vehicle]),
  insurance([CompanyRecordKind.policy]),
  contracts([CompanyRecordKind.contract]);

  const CompanyView(this.kinds);
  final List<CompanyRecordKind> kinds;

  static CompanyView from(String? value) => values.firstWhere(
    (view) => view.name == value,
    orElse: () => CompanyView.attention,
  );
}

/// What a metric tile shows.
enum _Tile { total, licences, vehicles, cover, expired, expiring }

class CompanyCentreScreen extends ConsumerStatefulWidget {
  const CompanyCentreScreen({super.key, this.initialView});

  /// A [CompanyView] name.
  final String? initialView;

  @override
  ConsumerState<CompanyCentreScreen> createState() =>
      _CompanyCentreScreenState();
}

class _CompanyCentreScreenState extends ConsumerState<CompanyCentreScreen> {
  static const _pageSize = 25;

  late CompanyView _view = CompanyView.from(widget.initialView);
  _Tile? _tile;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _owner;
  String _sort = 'name';
  bool _archived = false;
  int _offset = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  CompanyListQuery get _listQuery => CompanyListQuery(
    kinds: _view.kinds,
    owner: _owner,
    search: _query,
    sort: _sort,
    includeArchived: _archived,
    limit: _pageSize,
    offset: _offset,
  );

  void _setView(CompanyView view, {_Tile? tile}) => setState(() {
    _view = view;
    _tile = tile;
    _offset = 0;
  });

  void _onTile(_Tile tile) => switch (tile) {
    _Tile.total || _Tile.licences => _setView(CompanyView.licences, tile: tile),
    _Tile.vehicles => _setView(CompanyView.vehicles, tile: tile),
    _Tile.cover => _setView(CompanyView.contracts, tile: tile),
    _Tile.expired ||
    _Tile.expiring => _setView(CompanyView.attention, tile: tile),
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

  void _refresh() => yorksV1RefreshCompanyDocuments(ref);

  /// A folder of scans attached at once, each matched to a record and a
  /// document from its file name.
  Future<void> _bulk(AppLanguage language) async {
    final repository = ref.read(yorksV1CompanyDocumentsRepositoryProvider);
    final attached = await showBulkAttachDialog(
      context,
      keyPrefix: 'company',
      hint: CS.t(CS.bulkHint, language),
      chooseOwnerLabel: CS.t(CS.bulkChooseRecord, language),
      kinds: bulkAttachCompanyKinds,
      loadOwners: () async {
        final page = await repository.list(const CompanyListQuery(limit: 1000));
        return [
          for (final record in page.rows)
            BulkAttachOwner(
              id: record.id,
              name: record.name,
              subtitle: [
                companyKindLabel(record.kind, language),
                ?record.reference,
                ?record.owner,
              ].join(' · '),
              codes: [?record.reference],
              documents: [
                for (final document in record.documents)
                  BulkAttachDocument(
                    id: document.id,
                    kind: document.kind.wire,
                    number: document.number,
                    isCurrent: document.isCurrent,
                  ),
              ],
            ),
        ];
      },
      documentLabel: (document) => [
        companyDocumentLabel(CompanyDocumentKind.from(document.kind), language),
        ?document.number,
      ].join(' · '),
      upload: (upload) => repository.addAttachment(
        recordId: upload.ownerId,
        bytes: upload.bytes,
        fileName: upload.fileName,
        contentType: upload.contentType,
        documentId: upload.documentId,
        idempotencyKey: upload.idempotencyKey,
      ),
    );
    if (!mounted || (attached ?? 0) == 0) return;
    yorksV1RefreshCompanyDocuments(ref);
    peopleToast(context, PS.t(PS.bulkFinished, language, {'n': attached}));
  }

  Future<void> _export(AppLanguage language) async {
    setState(() => _exporting = true);
    try {
      final page = await ref
          .read(yorksV1CompanyDocumentsRepositoryProvider)
          .list(const CompanyListQuery(limit: 1000));
      final bytes = peopleEncodeWorkbook(
        companyExportSheets(page.rows, today: page.today),
      );
      final saved = await ref
          .read(yorksV1BoqWorkbookFileServiceProvider)
          .saveWorkbook(
            bytes: bytes,
            suggestedName: 'Company_Documents_${page.today}.xlsx',
          );
      if (!mounted || !saved) return;
      peopleToast(context, CS.t(CS.exportDone, language, {'n': page.total}));
    } catch (error) {
      if (mounted) peopleToast(context, companyErrorText(error, language));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    final imported = await showCompanyImportDialog(context);
    if (imported == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final overview = ref.watch(yorksV1CompanyOverviewProvider);
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
          key: const ValueKey('company-centre'),
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
              onBulk: () => _bulk(language),
              onAdd: () => context.go(
                _view.kinds.isEmpty
                    ? companyNewPath
                    : companyNewKindPath(_view.kinds.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ViewBar(
              language: language,
              view: _view,
              onView: (view) => _setView(view),
              showPeople: flags.peopleRecords,
            ),
            const SizedBox(height: AppSpacing.md),
            overview.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => PeopleSurface(
                child: PeopleMessage(
                  icon: Icons.cloud_off_outlined,
                  title: companyErrorText(error, language),
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
                      owners: [
                        for (final owner
                            in overview.valueOrNull?.owners ?? const [])
                          owner.name,
                      ],
                      owner: _owner,
                      onOwner: (value) => setState(() {
                        _owner = value;
                        _offset = 0;
                      }),
                      sort: _view == CompanyView.attention ? null : _sort,
                      onSort: (value) => setState(() {
                        _sort = value;
                        _offset = 0;
                      }),
                      archived: _view == CompanyView.attention
                          ? null
                          : _archived,
                      onArchived: (value) => setState(() {
                        _archived = value;
                        _offset = 0;
                      }),
                    ),
                  ),
                  const Divider(height: 1),
                  if (_view == CompanyView.attention)
                    _AttentionList(
                      overview: overview.valueOrNull,
                      language: language,
                      search: _query,
                      owner: _owner,
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
    required this.onBulk,
  });

  final AppLanguage language;
  final bool compact;
  final bool canManage;
  final bool exporting;
  final VoidCallback onRefresh;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onAdd;

  /// Bulk upload of a folder of scans (PRODUCT_DECISIONS section 49).
  final VoidCallback onBulk;

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
            Icons.business_center_outlined,
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
                CS.t(CS.title, language),
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.displaySmall)
                        .copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                CS.t(CS.centreDescription, language),
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
              key: const ValueKey('company-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        if (canManage)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: OutlinedButton.icon(
              key: const ValueKey('company-bulk-attach'),
              onPressed: onBulk,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: Text(PS.t(PS.bulkUpload, language)),
            ),
          ),
        if (canManage)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: OutlinedButton.icon(
              key: const ValueKey('company-import'),
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(PS.t(PS.importExcel, language)),
            ),
          ),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: OutlinedButton.icon(
            key: const ValueKey('company-export'),
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
              key: const ValueKey('company-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(CS.t(CS.addRecord, language)),
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

class _ViewBar extends StatelessWidget {
  const _ViewBar({
    required this.language,
    required this.view,
    required this.onView,
    required this.showPeople,
  });

  final AppLanguage language;
  final CompanyView view;
  final ValueChanged<CompanyView> onView;
  final bool showPeople;

  @override
  Widget build(BuildContext context) {
    Widget segment(CompanyView value, IconData icon, String label) {
      final selected = value == view;
      return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('company-view-${value.name}'),
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

    final segments = [
      (
        CompanyView.attention,
        Icons.warning_amber_rounded,
        PS.t(PS.viewAttention, language),
      ),
      (
        CompanyView.licences,
        Icons.storefront_outlined,
        CS.t(CS.viewLicences, language),
      ),
      (
        CompanyView.vehicles,
        Icons.directions_car_outlined,
        CS.t(CS.viewVehicles, language),
      ),
      (
        CompanyView.insurance,
        Icons.health_and_safety_outlined,
        CS.t(CS.viewInsurance, language),
      ),
      (
        CompanyView.contracts,
        Icons.handshake_outlined,
        CS.t(CS.viewContracts, language),
      ),
    ];
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
              for (final (index, (value, icon, label)) in segments.indexed) ...[
                if (index > 0) const VerticalDivider(width: 1),
                segment(value, icon, label),
              ],
            ],
          ),
        ),
      ),
    );
    if (!showPeople) {
      return Align(alignment: AlignmentDirectional.centerStart, child: bar);
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        bar,
        OutlinedButton.icon(
          key: const ValueKey('company-link-people'),
          onPressed: () => context.go(peoplePathForCompany),
          icon: const Icon(Icons.contact_page_outlined, size: 18),
          label: Text(CS.t(CS.linkPeople, language)),
        ),
      ],
    );
  }
}

/// The People home, linked from the view bar.
const peoplePathForCompany = '/yorks/people';

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.overview,
    required this.language,
    required this.selected,
    required this.onTile,
  });

  final CompanyOverview overview;
  final AppLanguage language;
  final _Tile? selected;
  final ValueChanged<_Tile> onTile;

  @override
  Widget build(BuildContext context) {
    final by = overview.byKind;
    final entities = by[CompanyRecordKind.entity] ?? 0;
    final items = by[CompanyRecordKind.item] ?? 0;
    final policies = by[CompanyRecordKind.policy] ?? 0;
    final contracts = by[CompanyRecordKind.contract] ?? 0;
    final tiles = [
      (
        _Tile.total,
        CS.t(CS.kpiRecords, language),
        CS.t(CS.kpiRecordsHint, language),
        overview.total,
        Icons.inventory_2_outlined,
        AppColors.blue,
        AppColors.blueContainer,
      ),
      (
        _Tile.licences,
        CS.t(CS.viewLicences, language),
        CS.t(CS.kpiLicencesHint, language, {'e': entities, 'i': items}),
        entities + items,
        Icons.storefront_outlined,
        AppColors.purple,
        AppColors.purpleContainer,
      ),
      (
        _Tile.vehicles,
        CS.t(CS.viewVehicles, language),
        CS.t(CS.kpiVehiclesHint, language),
        by[CompanyRecordKind.vehicle] ?? 0,
        Icons.directions_car_outlined,
        AppColors.success,
        AppColors.successContainer,
      ),
      (
        _Tile.cover,
        CS.t(CS.kpiCover, language),
        CS.t(CS.kpiCoverHint, language, {'p': policies, 'c': contracts}),
        policies + contracts,
        Icons.handshake_outlined,
        AppColors.neutralText,
        AppColors.neutralContainer,
      ),
      (
        _Tile.expired,
        PS.t(PS.kpiExpired, language),
        CS.t(CS.kpiExpiredHint, language),
        overview.expired,
        Icons.error_outline_rounded,
        AppColors.error,
        AppColors.errorContainer,
      ),
      (
        _Tile.expiring,
        PS.t(PS.kpiExpiring, language),
        PS.t(PS.kpiExpiringHint, language),
        overview.expiring,
        Icons.schedule_rounded,
        AppColors.warning,
        AppColors.warningContainer,
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
                  key: ValueKey('company-metric-${tile.name}'),
                  label: label,
                  hint: hint,
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
    required this.owners,
    required this.owner,
    required this.onOwner,
    required this.sort,
    required this.onSort,
    required this.archived,
    required this.onArchived,
  });

  final AppLanguage language;
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final List<String> owners;
  final String? owner;
  final ValueChanged<String?> onOwner;

  /// Null hides the sort control.
  final String? sort;
  final ValueChanged<String> onSort;

  /// Null hides the archived switch.
  final bool? archived;
  final ValueChanged<bool> onArchived;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      key: const ValueKey('company-search'),
      controller: search,
      onChanged: onSearch,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: CS.t(CS.searchHint, language),
      ),
    );
    final ownerField = DropdownButtonFormField<String?>(
      key: const ValueKey('company-owner'),
      initialValue: owners.contains(owner) ? owner : null,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.apartment_outlined, size: 20),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(PS.t(PS.allCompanies, language)),
        ),
        for (final name in owners)
          DropdownMenuItem<String?>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onOwner,
    );
    final sortField = sort == null
        ? null
        : DropdownButtonFormField<String>(
            key: const ValueKey('company-sort'),
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
                value: 'owner',
                child: Text(PS.t(PS.sortCompany, language)),
              ),
            ],
            onChanged: (value) {
              if (value != null) onSort(value);
            },
          );
    final archivedChip = archived == null
        ? null
        : FilterChip(
            key: const ValueKey('company-archived'),
            selected: archived!,
            onSelected: onArchived,
            avatar: const Icon(Icons.inventory_outlined, size: 18),
            label: Text(CS.t(CS.showArchived, language)),
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
                  Expanded(child: ownerField),
                  if (sortField != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: sortField),
                  ],
                ],
              ),
              if (archivedChip != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: archivedChip,
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 5, child: searchField),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: ownerField),
            if (sortField != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: sortField),
            ],
            if (archivedChip != null) ...[
              const SizedBox(width: AppSpacing.sm),
              archivedChip,
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
    required this.owner,
    required this.tile,
    this.failed = false,
  });

  final CompanyOverview? overview;
  final AppLanguage language;
  final String search;
  final String? owner;
  final _Tile? tile;
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
        if ((owner == null || item.owner == owner) &&
            (needle.isEmpty ||
                item.recordName.toLowerCase().contains(needle) ||
                (item.reference ?? '').toLowerCase().contains(needle) ||
                (item.owner ?? '').toLowerCase().contains(needle) ||
                (item.document.number ?? '').toLowerCase().contains(needle) ||
                (item.document.label ?? '').toLowerCase().contains(needle)) &&
            switch (tile) {
              _Tile.expired =>
                item.document.status == PeopleDocumentStatus.expired,
              _Tile.expiring =>
                item.document.status == PeopleDocumentStatus.expiring,
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

  final CompanyAttentionItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final document = item.document;
    final colors = peopleStatusColors(document.status);
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('company-attention-${document.id}'),
        onTap: () => context.go(companyRecordPath(item.recordId)),
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
                      companyDocumentIcon(document.kind),
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
                          companyKindLabel(item.recordKind, language),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.blue,
                          ),
                        ),
                        Text(
                          item.recordName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            companyDocumentLabel(
                              document.kind,
                              language,
                              label: document.label,
                            ),
                            if (document.number != null) document.number!,
                            if (item.owner != null) item.owner!,
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
                    companyDaysText(document.daysLeft, language),
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

/// One register, a page at a time.
class _Register extends ConsumerWidget {
  const _Register({
    required this.query,
    required this.language,
    required this.onPage,
    required this.canManage,
    required this.onImport,
  });

  final CompanyListQuery query;
  final AppLanguage language;
  final ValueChanged<int> onPage;
  final bool canManage;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(yorksV1CompanyListProvider(query));
    // A paperclip beside each record with files (PRODUCT_DECISIONS 48).
    final attached =
        ref.watch(yorksV1CompanyAttachmentCountsProvider).valueOrNull ??
        const <String, int>{};
    return page.when(
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => PeopleMessage(
        icon: Icons.cloud_off_outlined,
        title: companyErrorText(error, language),
        action: PS.t(PS.retry, language),
        onPressed: () => ref.invalidate(yorksV1CompanyListProvider(query)),
      ),
      data: (data) {
        if (data.total == 0) {
          final filtered = query.search.isNotEmpty || query.owner != null;
          return PeopleMessage(
            icon: Icons.search_off_rounded,
            title: CS.t(filtered ? CS.emptyRegister : CS.emptyAll, language),
            body: filtered ? null : CS.t(CS.emptyAllBody, language),
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
              builder: (context, constraints) => constraints.maxWidth >= 980
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
                          for (final record in data.rows) ...[
                            _RecordCard(
                              record: record,
                              language: language,
                              attached: attached[record.id] ?? 0,
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
                    key: const ValueKey('company-page-previous'),
                    onPressed: data.offset == 0
                        ? null
                        : () => onPage(
                            (data.offset - query.limit).clamp(0, data.total),
                          ),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('company-page-next'),
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

/// The register as a table: Record, Reference, Company, the documents held
/// and the next expiry.
class _RegisterTable extends StatelessWidget {
  const _RegisterTable({
    required this.rows,
    required this.language,
    this.attached = const {},
  });

  /// Attachments per record, by record id.
  final Map<String, int> attached;

  final List<CompanyRecord> rows;
  final AppLanguage language;

  static const _flex = [30, 13, 17, 30, 14];

  @override
  Widget build(BuildContext context) {
    final header = AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );
    final headings = [
      CS.t(CS.colRecord, language),
      CS.t(CS.colReference, language),
      CS.t(CS.colOwner, language),
      CS.t(CS.colDocuments, language),
      CS.t(CS.colNextExpiry, language),
    ];
    Widget cell(int index, Widget child) => Expanded(
      flex: _flex[index],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: child,
      ),
    );
    return Column(
      key: const ValueKey('company-register-table'),
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
        for (final record in rows)
          InkWell(
            key: ValueKey('company-row-${record.id}'),
            onTap: () => context.go(companyRecordPath(record.id)),
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
                    _RecordName(
                      record: record,
                      language: language,
                      attached: attached[record.id] ?? 0,
                    ),
                  ),
                  cell(
                    1,
                    Text(
                      record.reference ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  cell(
                    2,
                    Text(
                      record.owner ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  cell(3, _DocumentList(record: record, language: language)),
                  cell(
                    4,
                    record.documents.isEmpty
                        ? Text(
                            CS.t(CS.noDocumentsYet, language),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          )
                        : PeopleStatusPill(
                            status: record.attention,
                            language: language,
                          ),
                  ),
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

class _RecordName extends StatelessWidget {
  const _RecordName({
    required this.record,
    required this.language,
    this.attached = 0,
  });

  final CompanyRecord record;
  final AppLanguage language;

  /// How many files the record has (a paperclip beside the name).
  final int attached;

  @override
  Widget build(BuildContext context) {
    final colors = companyKindColors(record.kind);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(
            companyKindIcon(record.kind),
            size: 18,
            color: colors.color,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w800,
                        color: record.archived
                            ? AppColors.muted
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  RecordAttachmentCount(
                    key: ValueKey('company-attached-${record.id}'),
                    count: attached,
                    language: language,
                  ),
                ],
              ),
              Text(
                [
                  companyKindLabel(record.kind, language),
                  if (record.archived) CS.t(CS.archive, language),
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
      ],
    );
  }
}

/// Up to three documents, soonest first, with how many more.
class _DocumentList extends StatelessWidget {
  const _DocumentList({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final documents = [...record.documents]
      ..sort(
        (a, b) => (a.expiryDate ?? '9999').compareTo(b.expiryDate ?? '9999'),
      );
    if (documents.isEmpty) {
      return Text(
        '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.mutedLight),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final document in documents.take(3))
          Row(
            children: [
              Flexible(
                child: Text(
                  '${companyDocumentLabel(document.kind, language, label: document.label)}  ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
              CompanyExpiryCell(
                document: document,
                language: language,
                dense: true,
              ),
            ],
          ),
        if (documents.length > 3)
          Text(
            CS.t(CS.documentsCount, language, {'n': documents.length}),
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

/// The register as cards, for a phone or a narrow window.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.language,
    this.attached = 0,
  });

  final CompanyRecord record;
  final AppLanguage language;
  final int attached;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('company-card-${record.id}'),
      onTap: () => context.go(companyRecordPath(record.id)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _RecordName(
                    record: record,
                    language: language,
                    attached: attached,
                  ),
                ),
                if (record.documents.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  PeopleStatusPill(
                    status: record.attention,
                    language: language,
                  ),
                ],
              ],
            ),
            if (record.reference != null || record.owner != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  if (record.reference != null) record.reference!,
                  if (record.owner != null) record.owner!,
                ].join(' · '),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _DocumentList(record: record, language: language),
          ],
        ),
      ),
    ),
  );
}

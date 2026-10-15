import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_app_toast.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../../shared/models/yorks_v1_document_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_supplier.dart';
import '../../../../shared/models/yorks_v1_inventory_supplier_strings.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_supplier_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_workbook_provider.dart';
import '../../../../shared/services/yorks_v1_inventory_workbook_service.dart';

typedef YorksV1SupplierAction =
    void Function(YorksV1InventorySupplierDirectoryEntry supplier);

/// Procurement/Admin-only R38.9 supplier directory.
///
/// The route guard remains the first client boundary. This widget repeats the
/// exact-role check before it asks Riverpod for a supplier projection, so a
/// stale/deep route cannot briefly expose supplier controls or cached data.
class YorksV1InventorySupplierDirectoryScreen extends ConsumerStatefulWidget {
  const YorksV1InventorySupplierDirectoryScreen({
    super.key,
    this.onExportRegister,
    this.onImportReceipt,
    this.onAddSupplier,
    this.onOpenSupplier,
  });

  final VoidCallback? onExportRegister;
  final VoidCallback? onImportReceipt;
  final VoidCallback? onAddSupplier;
  final ValueChanged<String>? onOpenSupplier;

  @override
  ConsumerState<YorksV1InventorySupplierDirectoryScreen> createState() =>
      _YorksV1InventorySupplierDirectoryScreenState();
}

class _YorksV1InventorySupplierDirectoryScreenState
    extends ConsumerState<YorksV1InventorySupplierDirectoryScreen> {
  static const _pageSize = 30;
  static const _exportPageSize = 100;
  static const _maximumExportSuppliers = 10000;

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _search;
  YorksV1InventorySupplierStatus? _status;
  int _offset = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final canManage =
        ref.watch(yorksV1CurrentRoleProvider)?.canManageInventory ?? false;
    if (!canManage) {
      return _RestrictedSupplierSurface(language: language);
    }

    final query = YorksV1InventorySupplierDirectoryQuery(
      search: _search,
      status: _status,
      limit: _pageSize,
      offset: _offset,
    );
    final directory = ref.watch(
      yorksV1InventorySupplierDirectoryProvider(query),
    );
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: compact ? AppColors.mobileSurface : AppColors.surface,
      body: SafeArea(
        top: false,
        child: directory.when(
          loading: () => const _SupplierLoadingSurface(),
          error: (_, _) => _SupplierErrorSurface(
            language: language,
            onRetry: () => ref.invalidate(
              yorksV1InventorySupplierDirectoryProvider(query),
            ),
          ),
          data: (workspace) => _SupplierDirectoryBody(
            workspace: workspace,
            language: language,
            searchController: _searchController,
            selectedStatus: _status,
            onSearchChanged: _onSearchChanged,
            onStatusChanged: (value) {
              setState(() {
                _status = value;
                _offset = 0;
              });
            },
            onRefresh: () => ref.invalidate(
              yorksV1InventorySupplierDirectoryProvider(query),
            ),
            exportBusy: _exporting,
            onExport: _exporting
                ? null
                : widget.onExportRegister ?? _exportSupplierRegister,
            onImport: widget.onImportReceipt ?? _openImport,
            onAdd: widget.onAddSupplier ?? _openAddSupplier,
            onOpenSupplier: _openSupplier,
            onPrevious: workspace.offset > 0
                ? () => setState(
                    () => _offset = (_offset - _pageSize).clamp(0, 100000),
                  )
                : null,
            onNext: workspace.hasMore
                ? () => setState(() => _offset += _pageSize)
                : null,
          ),
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final next = value.trim();
      setState(() {
        _search = next.isEmpty ? null : next;
        _offset = 0;
      });
    });
  }

  void _openSupplier(String supplierId) {
    final callback = widget.onOpenSupplier;
    if (callback != null) {
      callback(supplierId);
      return;
    }
    GoRouter.maybeOf(
      context,
    )?.push('/yorks/inventory/suppliers/${Uri.encodeComponent(supplierId)}');
  }

  void _openImport() {
    GoRouter.maybeOf(context)?.push('/yorks/inventory/import');
  }

  Future<void> _openAddSupplier() async {
    final created = await showDialog<YorksV1InventorySupplierDirectoryEntry>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddSupplierDialog(),
    );
    if (!mounted || created == null) return;
    _openSupplier(created.id);
  }

  Future<void> _exportSupplierRegister() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    var succeeded = false;
    try {
      final fileService = ref.read(yorksV1InventoryWorkbookFileServiceProvider);
      if (fileService is! YorksV1InventorySupplierRegisterFileService) {
        throw StateError('supplier register export is unavailable');
      }
      final exportData = await _loadAllSuppliersForExport();
      final supplierFileService =
          fileService as YorksV1InventorySupplierRegisterFileService;
      succeeded = await supplierFileService.saveSupplierRegister(
        suppliers: exportData.suppliers,
        // These are the server-authoritative, per-unit directory totals. The
        // client never combines unlike units while building the workbook.
        unitTotals: exportData.unitTotals,
      );
    } catch (_) {
      succeeded = false;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    final language = ref.read(languageProvider);
    YorksAppToast.show(
      context,
      title:
          (succeeded
                  ? YorksV1BoqStrings.exported
                  : YorksV1BoqStrings.exportFailed)
              .active(language),
      tone: succeeded ? YorksAppToastTone.success : YorksAppToastTone.error,
    );
  }

  Future<
    ({
      List<YorksV1InventorySupplierDirectoryEntry> suppliers,
      List<YorksV1InventorySupplierUnitTotal> unitTotals,
    })
  >
  _loadAllSuppliersForExport() async {
    final repository = ref.read(yorksV1InventorySupplierRepositoryProvider);
    final entries = <String, YorksV1InventorySupplierDirectoryEntry>{};
    var unitTotals = const <YorksV1InventorySupplierUnitTotal>[];
    var offset = 0;
    while (offset < _maximumExportSuppliers) {
      final page = await repository.getDirectory(
        limit: _exportPageSize,
        offset: offset,
      );
      if (offset == 0) unitTotals = page.unitTotals;
      if (page.totalCount > _maximumExportSuppliers) {
        throw StateError('supplier register exceeds safe export limit');
      }
      for (final supplier in page.suppliers) {
        entries[supplier.id] = supplier;
      }
      if (!page.hasMore || page.suppliers.isEmpty) break;
      offset += page.limit > 0 ? page.limit : _exportPageSize;
    }
    if (offset >= _maximumExportSuppliers &&
        entries.length < _maximumExportSuppliers) {
      throw StateError('supplier register pagination did not complete');
    }
    final suppliers = entries.values.toList(growable: false)
      ..sort((left, right) {
        if (left.isSystemUnknown != right.isSystemUnknown) {
          return left.isSystemUnknown ? -1 : 1;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    return (suppliers: suppliers, unitTotals: unitTotals);
  }
}

class _SupplierDirectoryBody extends StatelessWidget {
  const _SupplierDirectoryBody({
    required this.workspace,
    required this.language,
    required this.searchController,
    required this.selectedStatus,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onRefresh,
    required this.exportBusy,
    required this.onExport,
    required this.onImport,
    required this.onAdd,
    required this.onOpenSupplier,
    required this.onPrevious,
    required this.onNext,
  });

  final YorksV1InventorySupplierDirectoryWorkspace workspace;
  final AppLanguage language;
  final TextEditingController searchController;
  final YorksV1InventorySupplierStatus? selectedStatus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<YorksV1InventorySupplierStatus?> onStatusChanged;
  final VoidCallback onRefresh;
  final bool exportBusy;
  final VoidCallback? onExport;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  final ValueChanged<String> onOpenSupplier;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final pagePadding = _pagePadding(context);
    final suppliers = [...workspace.suppliers]
      ..sort((left, right) {
        if (left.isSystemUnknown != right.isSystemUnknown) {
          return left.isSystemUnknown ? -1 : 1;
        }
        final statusCompare = left.status.index.compareTo(right.status.index);
        if (statusCompare != 0) return statusCompare;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    return CustomScrollView(
      key: const ValueKey('supplier-directory-scroll-view'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            _isCompact(context) ? AppSpacing.lg : AppSpacing.xxl,
            pagePadding,
            0,
          ),
          sliver: SliverList.list(
            children: [
              _SupplierDirectoryHeader(
                language: language,
                exportBusy: exportBusy,
                onExport: onExport,
                onImport: onImport,
                onAdd: onAdd,
                onRefresh: onRefresh,
              ),
              const SizedBox(height: AppSpacing.lg),
              _InventoryAreaTabs(language: language),
              const SizedBox(height: AppSpacing.lg),
              _DirectoryMetrics(summary: workspace.summary, language: language),
              const SizedBox(height: AppSpacing.md),
              _SupplierDirectoryFilters(
                language: language,
                controller: searchController,
                selectedStatus: selectedStatus,
                onSearchChanged: onSearchChanged,
                onStatusChanged: onStatusChanged,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
        if (suppliers.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pagePadding),
            sliver: SliverToBoxAdapter(
              child: _SupplierEmptySurface(language: language),
            ),
          )
        else
          _SupplierCardRows(
            suppliers: suppliers,
            language: language,
            horizontalPadding: pagePadding,
            onOpenSupplier: onOpenSupplier,
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            AppSpacing.md,
            pagePadding,
            _isCompact(context) ? 112 : AppSpacing.massive,
          ),
          sliver: SliverToBoxAdapter(
            child: _DirectoryPagination(
              workspace: workspace,
              language: language,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierDirectoryHeader extends StatelessWidget {
  const _SupplierDirectoryHeader({
    required this.language,
    required this.exportBusy,
    required this.onExport,
    required this.onImport,
    required this.onAdd,
    required this.onRefresh,
  });

  final AppLanguage language;
  final bool exportBusy;
  final VoidCallback? onExport;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact = _isCompact(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          YorksV1InventoryStrings.warehouseInventory
              .active(language)
              .toUpperCase(),
          style: AppTypography.eyebrow,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          YorksV1InventorySupplierStrings.suppliers.active(language),
          style:
              (compact
                      ? AppTypography.headlineMedium
                      : AppTypography.displaySmall)
                  .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            YorksV1InventorySupplierStrings.supplierSubtitle.active(language),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ),
      ],
    );
    final export = OutlinedButton.icon(
      key: const ValueKey('supplier-directory-export'),
      onPressed: onExport,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, AppSpacing.minTapTarget),
      ),
      icon: exportBusy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(YorksDataTransferIcons.exportData, size: 18),
      label: Text(
        YorksV1InventorySupplierStrings.exportRegister.active(language),
      ),
    );
    final import = OutlinedButton.icon(
      key: const ValueKey('supplier-directory-import'),
      onPressed: onImport,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, AppSpacing.minTapTarget),
      ),
      icon: const Icon(YorksDataTransferIcons.importData, size: 18),
      label: Text(
        YorksV1InventorySupplierStrings.importReceipt.active(language),
      ),
    );
    final add = FilledButton.icon(
      key: const ValueKey('supplier-directory-add'),
      onPressed: onAdd,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        minimumSize: const Size(44, AppSpacing.minTapTarget),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(YorksV1InventorySupplierStrings.addSupplier.active(language)),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: AppSpacing.lg),
          SizedBox(height: AppSpacing.massive, child: export),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SizedBox(height: AppSpacing.massive, child: import),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(height: AppSpacing.massive, child: add),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: heading),
        const SizedBox(width: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.end,
          children: [
            export,
            import,
            add,
            IconButton.outlined(
              tooltip: YorksV1LogisticsStrings.refresh.active(language),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _InventoryAreaTabs extends StatelessWidget {
  const _InventoryAreaTabs({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final entries =
        <({String label, IconData icon, String path, bool selected})>[
          (
            label: YorksV1InventoryStrings.overview.active(language),
            icon: Icons.home_outlined,
            path: '/yorks/inventory?tab=overview',
            selected: false,
          ),
          (
            label: YorksV1InventoryStrings.items.active(language),
            icon: Icons.inventory_2_outlined,
            path: '/yorks/inventory?tab=items',
            selected: false,
          ),
          (
            label: YorksV1InventoryStrings.movements.active(language),
            icon: Icons.history_rounded,
            path: '/yorks/inventory?tab=movements',
            selected: false,
          ),
          (
            label: YorksV1InventoryStrings.reservations.active(language),
            icon: Icons.verified_user_outlined,
            path: '/yorks/inventory?tab=reservations',
            selected: false,
          ),
          (
            label: YorksV1InventorySupplierStrings.suppliers.active(language),
            icon: Icons.group_outlined,
            path: '/yorks/inventory/suppliers',
            selected: true,
          ),
        ];
    return Semantics(
      container: true,
      child: SingleChildScrollView(
        key: const ValueKey('supplier-directory-area-tabs'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: _SupplierTabButton(
                  label: entry.label,
                  icon: entry.icon,
                  selected: entry.selected,
                  onPressed: router == null
                      ? null
                      : () => router.go(entry.path),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryMetrics extends StatelessWidget {
  const _DirectoryMetrics({required this.summary, required this.language});

  final YorksV1InventorySupplierDirectorySummary summary;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1120
          ? 5
          : constraints.maxWidth >= 680
          ? 3
          : 2;
      final values = <({String label, int value, Color tone, IconData icon})>[
        (
          label: YorksV1InventorySupplierStrings.activeSuppliers.active(
            language,
          ),
          value: summary.activeSuppliers,
          tone: AppColors.success,
          icon: Icons.storefront_outlined,
        ),
        (
          label: YorksV1InventorySupplierStrings.receiptBatches.active(
            language,
          ),
          value: summary.receiptBatches,
          tone: AppColors.blue,
          icon: Icons.receipt_long_outlined,
        ),
        (
          label: YorksV1InventorySupplierStrings.itemsSupplied.active(language),
          value: summary.distinctItems,
          tone: AppColors.blue,
          icon: Icons.inventory_2_outlined,
        ),
        (
          label: YorksV1InventorySupplierStrings.documentsMissing.active(
            language,
          ),
          value: summary.documentsMissing,
          tone: AppColors.warning,
          icon: Icons.description_outlined,
        ),
        (
          label: YorksV1InventorySupplierStrings.inactiveReview.active(
            language,
          ),
          value: summary.inactiveOrReview + summary.identityMissing,
          tone: AppColors.warning,
          icon: Icons.rule_folder_outlined,
        ),
      ];
      final width =
          (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (var index = 0; index < values.length; index++)
            SizedBox(
              width: columns == 2 && index == values.length - 1
                  ? constraints.maxWidth
                  : width,
              child: _CompactMetricCard(
                label: values[index].label,
                value: '${values[index].value}',
                tone: values[index].tone,
                icon: values[index].icon,
              ),
            ),
        ],
      );
    },
  );
}

class _SupplierDirectoryFilters extends StatelessWidget {
  const _SupplierDirectoryFilters({
    required this.language,
    required this.controller,
    required this.selectedStatus,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  final AppLanguage language;
  final TextEditingController controller;
  final YorksV1InventorySupplierStatus? selectedStatus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<YorksV1InventorySupplierStatus?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const ValueKey('supplier-directory-search'),
      controller: controller,
      onChanged: onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: YorksV1InventorySupplierStrings.searchHint.active(language),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
      ),
    );
    final filter = DropdownButtonFormField<YorksV1InventorySupplierStatus?>(
      key: const ValueKey('supplier-directory-status-filter'),
      initialValue: selectedStatus,
      isExpanded: true,
      items: [
        DropdownMenuItem<YorksV1InventorySupplierStatus?>(
          value: null,
          child: Text(
            YorksV1InventorySupplierStrings.allSuppliers.active(language),
          ),
        ),
        for (final status in YorksV1InventorySupplierStatus.values)
          DropdownMenuItem<YorksV1InventorySupplierStatus?>(
            value: status,
            child: Text(_supplierStatusLabel(status, language)),
          ),
      ],
      onChanged: onStatusChanged,
    );
    return _SupplierSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                filter,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 4, child: search),
              const SizedBox(width: AppSpacing.md),
              SizedBox(width: 230, child: filter),
            ],
          );
        },
      ),
    );
  }
}

class _SupplierCardRows extends StatelessWidget {
  const _SupplierCardRows({
    required this.suppliers,
    required this.language,
    required this.horizontalPadding,
    required this.onOpenSupplier,
  });

  final List<YorksV1InventorySupplierDirectoryEntry> suppliers;
  final AppLanguage language;
  final double horizontalPadding;
  final ValueChanged<String> onOpenSupplier;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.crossAxisExtent - horizontalPadding * 2;
      final columns = width >= 1120
          ? 3
          : width >= 680
          ? 2
          : 1;
      final rowCount = (suppliers.length / columns).ceil();
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        sliver: SliverList.builder(
          itemCount: rowCount,
          itemBuilder: (context, rowIndex) {
            final start = rowIndex * columns;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: start + column < suppliers.length
                          ? _SupplierDirectoryCard(
                              supplier: suppliers[start + column],
                              language: language,
                              onOpen: () =>
                                  onOpenSupplier(suppliers[start + column].id),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class _SupplierDirectoryCard extends StatelessWidget {
  const _SupplierDirectoryCard({
    required this.supplier,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierDirectoryEntry supplier;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final unknown = supplier.isSystemUnknown;
    final tone = unknown ? AppColors.warning : _statusTone(supplier.status);
    return Semantics(
      button: true,
      label: YorksV1InventorySupplierStrings.openFolder.active(language),
      child: Material(
        color: unknown
            ? AppColors.warningContainer.withValues(alpha: .64)
            : AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: unknown ? AppColors.warning : AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 190),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InitialsTile(
                        label: _initials(supplier.name),
                        background: unknown
                            ? AppColors.warningContainer
                            : AppColors.blueContainer,
                        foreground: unknown
                            ? AppColors.warning
                            : AppColors.blue,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              supplier.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleSmall,
                            ),
                            if (supplier.description != null) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                supplier.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _StatusPill(
                        label: _supplierStatusLabel(supplier.status, language),
                        tone: tone,
                      ),
                    ],
                  ),
                  if (unknown) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      YorksV1InventorySupplierStrings.unknownSupplierExplanation
                          .active(language),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onWarningContainer,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _SupplierMiniMetric(
                          label: YorksV1InventorySupplierStrings.receiptBatches
                              .active(language),
                          value: '${supplier.receiptBatchCount}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _SupplierMiniMetric(
                          label: YorksV1InventorySupplierStrings.itemsSupplied
                              .active(language),
                          value: '${supplier.distinctItemCount}',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _SupplierMiniMetric(
                          label: YorksV1InventoryStrings.lastUpdated.active(
                            language,
                          ),
                          value: supplier.lastReceiptAt == null
                              ? YorksV1InventoryStrings.notConfigured.active(
                                  language,
                                )
                              : _date(context, supplier.lastReceiptAt!),
                        ),
                      ),
                    ],
                  ),
                  if (unknown && supplier.reconciliationCount > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _StatusPill(
                      label:
                          '${supplier.reconciliationCount} ${YorksV1InventorySupplierStrings.review.active(language)}',
                      tone: AppColors.warning,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          YorksV1InventorySupplierStrings.openFolder.active(
                            language,
                          ),
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryPagination extends StatelessWidget {
  const _DirectoryPagination({
    required this.workspace,
    required this.language,
    required this.onPrevious,
    required this.onNext,
  });

  final YorksV1InventorySupplierDirectoryWorkspace workspace;
  final AppLanguage language;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (workspace.totalCount <= workspace.limit && workspace.offset == 0) {
      return const SizedBox.shrink();
    }
    final first = workspace.suppliers.isEmpty ? 0 : workspace.offset + 1;
    final last = workspace.offset + workspace.suppliers.length;
    final description =
        '${AppStrings.showing.active(language)} $first–$last ${AppStrings.of_.active(language)} ${workspace.totalCount}';
    return _SupplierSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(description, style: AppTypography.bodySmall)),
          IconButton.outlined(
            tooltip: AppStrings.previous.active(language),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.outlined(
            tooltip: AppStrings.next.active(language),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _AddSupplierDialog extends ConsumerStatefulWidget {
  const _AddSupplierDialog();

  @override
  ConsumerState<_AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends ConsumerState<_AddSupplierDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _aliases = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _aliases.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final command = ref.watch(yorksV1InventorySupplierCommandProvider);
    return AlertDialog(
      title: Text(YorksV1InventorySupplierStrings.addSupplier.active(language)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: YorksV1InventorySupplierStrings.canonicalSupplier
                      .active(language),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppStrings.description.active(language),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _aliases,
                decoration: InputDecoration(
                  labelText: YorksV1InventorySupplierStrings.aliases.active(
                    language,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: command.isLoading ? null : () => Navigator.pop(context),
          child: Text(AppStrings.cancel.active(language)),
        ),
        FilledButton(
          onPressed: command.isLoading || _name.text.trim().isEmpty
              ? null
              : _submit,
          child: command.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(AppStrings.saveChanges.active(language)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final created = await ref
        .read(yorksV1InventorySupplierCommandProvider.notifier)
        .createSupplier(
          name: _name.text,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text,
          aliases: _aliases.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
        );
    if (!mounted || created == null) return;
    Navigator.pop(context, created);
  }
}

class _DocumentUploadTarget {
  const _DocumentUploadTarget({
    required this.classification,
    required this.entityType,
    required this.entityId,
  });

  final YorksV1DocumentClassification classification;
  final YorksV1DocumentEntityType entityType;
  final String entityId;
}

class _DocumentUploadOptions {
  const _DocumentUploadOptions({
    required this.classification,
    required this.receiptBatchId,
    required this.supplierDocumentType,
    required this.businessReference,
    required this.supplierDocumentNotes,
  });

  final YorksV1DocumentClassification classification;
  final String? receiptBatchId;
  final YorksV1SupplierDocumentType supplierDocumentType;
  final String? businessReference;
  final String? supplierDocumentNotes;
}

class _DocumentUploadOptionsDialog extends StatefulWidget {
  const _DocumentUploadOptionsDialog({
    required this.language,
    required this.batches,
    required this.preselectedReceiptBatchId,
    required this.lockReceiptBatch,
    this.initialClassification = YorksV1DocumentClassification.operational,
    this.initialDocumentType = YorksV1SupplierDocumentType.deliveryNote,
    this.initialBusinessReference,
    this.initialNotes,
    this.lockClassification = false,
    this.lockDocumentType = false,
    this.isRevision = false,
  });

  final AppLanguage language;
  final List<YorksV1InventorySupplierReceiptBatch> batches;
  final String? preselectedReceiptBatchId;
  final bool lockReceiptBatch;
  final YorksV1DocumentClassification initialClassification;
  final YorksV1SupplierDocumentType initialDocumentType;
  final String? initialBusinessReference;
  final String? initialNotes;
  final bool lockClassification;
  final bool lockDocumentType;
  final bool isRevision;

  @override
  State<_DocumentUploadOptionsDialog> createState() =>
      _DocumentUploadOptionsDialogState();
}

class _DocumentUploadOptionsDialogState
    extends State<_DocumentUploadOptionsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessReference;
  late final TextEditingController _notes;
  late YorksV1DocumentClassification _classification;
  late YorksV1SupplierDocumentType _documentType;
  String? _receiptBatchId;

  @override
  void initState() {
    super.initState();
    _classification = widget.initialClassification;
    _documentType = widget.initialDocumentType;
    _receiptBatchId = widget.preselectedReceiptBatchId;
    _businessReference = TextEditingController(
      text: widget.initialBusinessReference,
    );
    _notes = TextEditingController(text: widget.initialNotes);
    if (_documentType == YorksV1SupplierDocumentType.invoice) {
      _classification = YorksV1DocumentClassification.commercial;
    }
  }

  @override
  void dispose() {
    _businessReference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      (widget.isRevision
              ? YorksV1DocumentStrings.uploadVersion
              : YorksV1DocumentStrings.uploadDocument)
          .active(widget.language),
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<YorksV1SupplierDocumentType>(
                key: const ValueKey('supplier-document-type'),
                initialValue: _documentType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1InventorySupplierStrings.documentType
                      .active(widget.language),
                  helperText: widget.lockDocumentType
                      ? YorksV1InventorySupplierStrings
                            .documentTypeLockedForRevision
                            .active(widget.language)
                      : null,
                ),
                items: [
                  for (final type in YorksV1SupplierDocumentType.values)
                    if (!widget.lockClassification ||
                        widget.initialClassification ==
                            YorksV1DocumentClassification.commercial ||
                        type != YorksV1SupplierDocumentType.invoice)
                      DropdownMenuItem(
                        value: type,
                        child: Text(
                          _supplierDocumentTypeLabel(type, widget.language),
                        ),
                      ),
                ],
                onChanged: widget.lockDocumentType
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _documentType = value;
                          if (value == YorksV1SupplierDocumentType.invoice) {
                            _classification =
                                YorksV1DocumentClassification.commercial;
                          }
                        });
                      },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<YorksV1DocumentClassification>(
                key: ValueKey(
                  'supplier-document-classification-${_classification.wireValue}',
                ),
                initialValue: _classification,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1DocumentStrings.classification.active(
                    widget.language,
                  ),
                ),
                items: [
                  for (final classification
                      in YorksV1DocumentClassification.values)
                    DropdownMenuItem(
                      value: classification,
                      child: Text(
                        _classificationLabel(classification, widget.language),
                      ),
                    ),
                ],
                onChanged:
                    widget.lockClassification ||
                        _documentType == YorksV1SupplierDocumentType.invoice
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _classification = value);
                        }
                      },
              ),
              if (_documentType == YorksV1SupplierDocumentType.invoice) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1InventorySupplierStrings.invoiceCommercial.active(
                    widget.language,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('supplier-document-business-reference'),
                controller: _businessReference,
                maxLength: 180,
                decoration: InputDecoration(
                  labelText: YorksV1InventorySupplierStrings.businessReference
                      .active(widget.language),
                  hintText: YorksV1InventorySupplierStrings
                      .businessReferenceHint
                      .active(widget.language),
                ),
                validator: (value) {
                  if (_documentType.requiresBusinessReference &&
                      (value == null || value.trim().isEmpty)) {
                    return YorksV1InventorySupplierStrings
                        .referenceRequiredForType
                        .active(widget.language);
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('supplier-document-notes'),
                controller: _notes,
                minLines: 2,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: AppStrings.notes.active(widget.language),
                  hintText: YorksV1InventorySupplierStrings.documentNotesHint
                      .active(widget.language),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                key: const ValueKey('supplier-document-receipt-batch'),
                initialValue: _receiptBatchId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1InventorySupplierStrings.receiptBatches
                      .active(widget.language),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      YorksV1InventorySupplierStrings.optional.active(
                        widget.language,
                      ),
                    ),
                  ),
                  for (final batch in widget.batches)
                    DropdownMenuItem<String?>(
                      value: batch.id,
                      child: Text(
                        [
                          batch.receiptNumber,
                          batch.supplierReference,
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.lockReceiptBatch
                    ? null
                    : (value) => setState(() => _receiptBatchId = value),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        key: const ValueKey('supplier-document-options-continue'),
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.pop(
            context,
            _DocumentUploadOptions(
              classification: _classification,
              receiptBatchId: _receiptBatchId,
              supplierDocumentType: _documentType,
              businessReference: _trimmedOrNull(_businessReference.text),
              supplierDocumentNotes: _trimmedOrNull(_notes.text),
            ),
          );
        },
        child: Text(AppStrings.saveAndContinue.active(widget.language)),
      ),
    ],
  );
}

String _classificationLabel(
  YorksV1DocumentClassification classification,
  AppLanguage language,
) => switch (classification) {
  YorksV1DocumentClassification.operational =>
    YorksV1DocumentStrings.operational.active(language),
  YorksV1DocumentClassification.commercial =>
    YorksV1DocumentStrings.commercial.active(language),
  YorksV1DocumentClassification.adminRestricted =>
    YorksV1DocumentStrings.adminRestricted.active(language),
};

String _supplierDocumentTypeLabel(
  YorksV1SupplierDocumentType type,
  AppLanguage language,
) => switch (type) {
  YorksV1SupplierDocumentType.deliveryNote =>
    YorksV1InventorySupplierStrings.deliveryNote.active(language),
  YorksV1SupplierDocumentType.invoice =>
    YorksV1InventorySupplierStrings.invoice.active(language),
  YorksV1SupplierDocumentType.packingList =>
    YorksV1InventorySupplierStrings.packingList.active(language),
  YorksV1SupplierDocumentType.productDataSheet =>
    YorksV1InventorySupplierStrings.productDataSheet.active(language),
  YorksV1SupplierDocumentType.other =>
    YorksV1InventorySupplierStrings.otherDocument.active(language),
};

String? _trimmedOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Procurement/Admin R38.9 supplier folder with six local sections.
class YorksV1InventorySupplierFolderScreen extends ConsumerStatefulWidget {
  const YorksV1InventorySupplierFolderScreen({
    super.key,
    required this.supplierId,
    this.initialSection = YorksV1InventorySupplierFolderSection.overview,
    this.onAddDocument,
    this.onImportReceipt,
    this.onOpenItemTrail,
    this.onOpenReceiptBatch,
    this.onOpenDocument,
    this.onReplaceDocument,
    this.onOpenDestination,
  });

  final String supplierId;
  final YorksV1InventorySupplierFolderSection initialSection;
  final VoidCallback? onAddDocument;
  final VoidCallback? onImportReceipt;
  final ValueChanged<String>? onOpenItemTrail;
  final ValueChanged<String>? onOpenReceiptBatch;
  final ValueChanged<String>? onOpenDocument;
  final ValueChanged<String>? onReplaceDocument;
  final ValueChanged<String>? onOpenDestination;

  @override
  ConsumerState<YorksV1InventorySupplierFolderScreen> createState() =>
      _YorksV1InventorySupplierFolderScreenState();
}

class _YorksV1InventorySupplierFolderScreenState
    extends ConsumerState<YorksV1InventorySupplierFolderScreen> {
  static const _pageSize = 50;
  static const _uuid = Uuid();

  late YorksV1InventorySupplierFolderSection _section;
  int _offset = 0;
  bool _documentBusy = false;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final canManage =
        ref.watch(yorksV1CurrentRoleProvider)?.canManageInventory ?? false;
    if (!canManage) {
      return _RestrictedSupplierSurface(language: language);
    }

    final query = YorksV1InventorySupplierFolderQuery(
      supplierId: widget.supplierId,
      section: _section,
      limit: _pageSize,
      offset: _offset,
    );
    final folder = ref.watch(yorksV1InventorySupplierFolderProvider(query));
    final compact = _isCompact(context);
    return Scaffold(
      backgroundColor: compact ? AppColors.mobileSurface : AppColors.surface,
      body: SafeArea(
        top: false,
        child: folder.when(
          loading: () => const _SupplierLoadingSurface(),
          error: (_, _) => _SupplierErrorSurface(
            language: language,
            onRetry: () =>
                ref.invalidate(yorksV1InventorySupplierFolderProvider(query)),
          ),
          data: (workspace) => _SupplierFolderBody(
            workspace: workspace,
            language: language,
            section: _section,
            onSection: (value) {
              if (value == _section) return;
              setState(() {
                _section = value;
                _offset = 0;
              });
            },
            onRefresh: () =>
                ref.invalidate(yorksV1InventorySupplierFolderProvider(query)),
            documentBusy: _documentBusy,
            onAddDocument:
                widget.onAddDocument ??
                (_documentBusy ? null : () => _uploadDocument()),
            onImportReceipt: widget.onImportReceipt ?? _openImport,
            onOpenItemTrail: _openItemTrail,
            onOpenReceiptBatch: _openReceiptBatch,
            onOpenDocument: _openDocument,
            onReplaceDocument: _replaceDocument,
            onOpenDestination: _openDestination,
            onPrevious: workspace.offset > 0
                ? () => setState(
                    () => _offset = (_offset - _pageSize).clamp(0, 100000),
                  )
                : null,
            onNext: workspace.offset + workspace.limit < workspace.totalCount
                ? () => setState(() => _offset += _pageSize)
                : null,
          ),
        ),
      ),
    );
  }

  void _openImport() {
    GoRouter.maybeOf(context)?.push(
      '/yorks/inventory/import?supplierId=${Uri.encodeComponent(widget.supplierId)}',
    );
  }

  void _openItemTrail(String inventoryItemId) {
    final callback = widget.onOpenItemTrail;
    if (callback != null) {
      callback(inventoryItemId);
      return;
    }
    _showSupplierDetail(
      _SupplierItemTrailDetail(
        supplierId: widget.supplierId,
        inventoryItemId: inventoryItemId,
      ),
    );
  }

  void _openReceiptBatch(String receiptBatchId) {
    final callback = widget.onOpenReceiptBatch;
    if (callback != null) {
      callback(receiptBatchId);
      return;
    }
    _showSupplierDetail(
      _SupplierReceiptBatchDetail(
        supplierId: widget.supplierId,
        receiptBatchId: receiptBatchId,
        onAddDocument: () => _uploadDocument(receiptBatchId: receiptBatchId),
        onDownloadDocument: _openDocument,
        onReplaceDocument: _replaceDocument,
      ),
    );
  }

  Future<void> _showSupplierDetail(Widget child) async {
    if (_isCompact(context)) {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceContainerLowest,
        builder: (_) => FractionallySizedBox(heightFactor: .92, child: child),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
          child: child,
        ),
      ),
    );
  }

  Future<void> _uploadDocument({
    String? documentId,
    String? receiptBatchId,
  }) async {
    if (_documentBusy) return;
    setState(() => _documentBusy = true);
    try {
      final repository = ref.read(yorksV1SupplierDocumentsRepositoryProvider);
      late final _DocumentUploadTarget target;
      late final _DocumentUploadOptions options;
      if (documentId != null) {
        final protectedWorkspace = await repository.getSupplierWorkspace(
          widget.supplierId,
        );
        final document = protectedWorkspace.documents
            .where((entry) => entry.id == documentId)
            .firstOrNull;
        if (document == null) throw StateError('missing protected projection');
        final link = document.links
            .where(
              (entry) =>
                  (entry.entityType == YorksV1DocumentEntityType.supplier &&
                      entry.entityId == widget.supplierId) ||
                  entry.entityType ==
                      YorksV1DocumentEntityType.supplierReceiptBatch,
            )
            .firstOrNull;
        if (link == null) throw StateError('missing protected supplier link');
        target = _DocumentUploadTarget(
          classification: document.classification,
          entityType: link.entityType,
          entityId: link.entityId,
        );
        final version = document.currentVersion;
        final batches = await _loadReceiptBatches();
        if (!mounted) return;
        final selectedOptions = await showDialog<_DocumentUploadOptions>(
          context: context,
          builder: (_) => _DocumentUploadOptionsDialog(
            language: ref.read(languageProvider),
            batches: batches,
            preselectedReceiptBatchId:
                link.entityType ==
                    YorksV1DocumentEntityType.supplierReceiptBatch
                ? link.entityId
                : null,
            lockReceiptBatch: true,
            initialClassification: document.classification,
            initialDocumentType:
                version.supplierDocumentType ??
                YorksV1SupplierDocumentType.deliveryNote,
            initialBusinessReference: version.businessReference,
            initialNotes: version.supplierDocumentNotes,
            lockClassification: true,
            lockDocumentType: version.supplierDocumentType != null,
            isRevision: true,
          ),
        );
        if (selectedOptions == null) return;
        options = selectedOptions;
      } else {
        final batches = await _loadReceiptBatches();
        if (!mounted) return;
        final selectedOptions = await showDialog<_DocumentUploadOptions>(
          context: context,
          builder: (_) => _DocumentUploadOptionsDialog(
            language: ref.read(languageProvider),
            batches: batches,
            preselectedReceiptBatchId: receiptBatchId,
            lockReceiptBatch: receiptBatchId != null,
          ),
        );
        if (selectedOptions == null) return;
        options = selectedOptions;
        target = _DocumentUploadTarget(
          classification: options.classification,
          entityType: options.receiptBatchId == null
              ? YorksV1DocumentEntityType.supplier
              : YorksV1DocumentEntityType.supplierReceiptBatch,
          entityId: options.receiptBatchId ?? widget.supplierId,
        );
      }
      final selected = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (selected == null) return;
      await repository.uploadSupplier(
        YorksV1DocumentUploadInput(
          projectId: widget.supplierId,
          entityType: target.entityType,
          entityId: target.entityId,
          classification: target.classification,
          fileName: selected.fileName,
          mimeType: selected.mimeType,
          bytes: selected.bytes,
          documentId: documentId,
          supplierDocumentType: options.supplierDocumentType,
          businessReference: options.businessReference,
          supplierDocumentNotes: options.supplierDocumentNotes,
          idempotencyKey: _uuid.v4(),
        ),
      );
      if (!mounted) return;
      ref.invalidate(
        yorksV1SupplierDocumentWorkspaceProvider(widget.supplierId),
      );
      ref.invalidate(yorksV1InventorySupplierFolderProvider);
      YorksAppToast.show(
        context,
        title: YorksV1DocumentStrings.uploadSucceeded.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.success,
      );
    } on YorksV1CommittedViewUnavailable {
      if (!mounted) return;
      ref.invalidate(
        yorksV1SupplierDocumentWorkspaceProvider(widget.supplierId),
      );
      ref.invalidate(yorksV1InventorySupplierFolderProvider);
      YorksAppToast.show(
        context,
        title: YorksV1DocumentStrings.uploadConfirmedRefreshPending.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1DocumentStrings.uploadFailed.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _documentBusy = false);
    }
  }

  Future<List<YorksV1InventorySupplierReceiptBatch>>
  _loadReceiptBatches() async {
    const pageSize = 100;
    const maximum = 1000;
    final repository = ref.read(yorksV1InventorySupplierRepositoryProvider);
    final batches = <YorksV1InventorySupplierReceiptBatch>[];
    var offset = 0;
    while (offset < maximum) {
      final page = await repository.getFolder(
        supplierId: widget.supplierId,
        section: YorksV1InventorySupplierFolderSection.receiptBatches,
        limit: pageSize,
        offset: offset,
      );
      batches.addAll(page.batches);
      offset += page.batches.length;
      if (offset >= page.totalCount || page.batches.isEmpty) break;
    }
    return List.unmodifiable(batches);
  }

  Future<void> _openDocument(String documentId) async {
    final callback = widget.onOpenDocument;
    if (callback != null) {
      callback(documentId);
      return;
    }
    if (_documentBusy) return;
    setState(() => _documentBusy = true);
    try {
      final workspace = await ref.read(
        yorksV1SupplierDocumentWorkspaceProvider(widget.supplierId).future,
      );
      final document = workspace.documents
          .where((entry) => entry.id == documentId)
          .firstOrNull;
      if (document == null) throw StateError('missing protected projection');
      final version = document.currentVersion;
      final bytes = await ref
          .read(yorksV1SupplierDocumentsRepositoryProvider)
          .downloadDocument(
            bucketId: version.bucketId,
            objectPath: version.objectPath,
          );
      final saved = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: bytes,
            fileName: version.fileName,
            mimeType: version.mimeType,
          );
      if (!saved) return;
    } catch (_) {
      if (!mounted) return;
      YorksAppToast.show(
        context,
        title: YorksV1DocumentStrings.downloadFailed.active(
          ref.read(languageProvider),
        ),
        tone: YorksAppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _documentBusy = false);
    }
  }

  Future<void> _replaceDocument(String documentId) async {
    final callback = widget.onReplaceDocument;
    if (callback != null) {
      callback(documentId);
      return;
    }
    await _uploadDocument(documentId: documentId);
  }

  void _openDestination(YorksV1InventorySupplierDestination destination) {
    final callback = widget.onOpenDestination;
    if (callback != null) {
      callback(destination.id);
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final requestId = destination.requestId.trim();
    if (requestId.isNotEmpty) {
      unawaited(
        router.push<void>(
          '/yorks/material-requests/${Uri.encodeComponent(requestId)}',
        ),
      );
      return;
    }
    final projectId = destination.projectId.trim();
    if (projectId.isNotEmpty) {
      unawaited(
        router.push<void>('/yorks/projects/${Uri.encodeComponent(projectId)}'),
      );
    }
  }
}

class _SupplierFolderBody extends StatelessWidget {
  const _SupplierFolderBody({
    required this.workspace,
    required this.language,
    required this.section,
    required this.onSection,
    required this.onRefresh,
    required this.documentBusy,
    required this.onAddDocument,
    required this.onImportReceipt,
    required this.onOpenItemTrail,
    required this.onOpenReceiptBatch,
    required this.onOpenDocument,
    required this.onReplaceDocument,
    required this.onOpenDestination,
    required this.onPrevious,
    required this.onNext,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final YorksV1InventorySupplierFolderSection section;
  final ValueChanged<YorksV1InventorySupplierFolderSection> onSection;
  final VoidCallback onRefresh;
  final bool documentBusy;
  final VoidCallback? onAddDocument;
  final VoidCallback onImportReceipt;
  final ValueChanged<String>? onOpenItemTrail;
  final ValueChanged<String>? onOpenReceiptBatch;
  final ValueChanged<String>? onOpenDocument;
  final ValueChanged<String>? onReplaceDocument;
  final ValueChanged<YorksV1InventorySupplierDestination>? onOpenDestination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final padding = _pagePadding(context);
    return CustomScrollView(
      key: const ValueKey('supplier-folder-scroll-view'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding,
            _isCompact(context) ? AppSpacing.sm : AppSpacing.xxl,
            padding,
            0,
          ),
          sliver: SliverList.list(
            children: [
              _SupplierHero(
                workspace: workspace,
                language: language,
                onAddDocument: onAddDocument,
                onImportReceipt: onImportReceipt,
                onRefresh: onRefresh,
              ),
              const SizedBox(height: AppSpacing.md),
              _SupplierFolderTabs(
                selected: section,
                language: language,
                onSelected: onSection,
              ),
              const SizedBox(height: AppSpacing.md),
              _SupplierSection(
                workspace: workspace,
                language: language,
                section: section,
                onSection: onSection,
                onAddDocument: onAddDocument,
                documentBusy: documentBusy,
                onOpenItemTrail: onOpenItemTrail,
                onOpenReceiptBatch: onOpenReceiptBatch,
                onOpenDocument: onOpenDocument,
                onReplaceDocument: onReplaceDocument,
                onOpenDestination: onOpenDestination,
              ),
              if (section != YorksV1InventorySupplierFolderSection.overview)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _FolderPagination(
                    workspace: workspace,
                    language: language,
                    onPrevious: onPrevious,
                    onNext: onNext,
                  ),
                ),
              SizedBox(height: _isCompact(context) ? 112 : AppSpacing.massive),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierHero extends StatelessWidget {
  const _SupplierHero({
    required this.workspace,
    required this.language,
    required this.onAddDocument,
    required this.onImportReceipt,
    required this.onRefresh,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final VoidCallback? onAddDocument;
  final VoidCallback onImportReceipt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final supplier = workspace.supplier;
    final compact = _isCompact(context);
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InitialsTile(
          label: _initials(supplier.name),
          background: Colors.white.withValues(alpha: .13),
          foreground: Colors.white,
          size: compact ? 52 : 56,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier.name,
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.displaySmall)
                        .copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                [
                  supplier.code,
                  ...supplier.aliases,
                ].where((value) => value.trim().isNotEmpty).join(' · '),
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white.withValues(alpha: .78),
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
      children: [
        OutlinedButton.icon(
          onPressed: onAddDocument,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .5)),
          ),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Text(
            YorksV1InventorySupplierStrings.addDocument.active(language),
          ),
        ),
        FilledButton.icon(
          onPressed: onImportReceipt,
          style: FilledButton.styleFrom(
            foregroundColor: AppColors.navy,
            backgroundColor: Colors.white,
          ),
          icon: const Icon(YorksDataTransferIcons.importData, size: 18),
          label: Text(
            YorksV1InventorySupplierStrings.importReceipt.active(language),
          ),
        ),
        if (!compact)
          IconButton.outlined(
            tooltip: YorksV1LogisticsStrings.refresh.active(language),
            onPressed: onRefresh,
            color: Colors.white,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
    final metrics = <({String label, String value})>[
      (
        label: YorksV1InventorySupplierStrings.receiptBatches.active(language),
        value: '${supplier.receiptBatchCount}',
      ),
      (
        label: YorksV1InventorySupplierStrings.itemsSupplied.active(language),
        value: '${supplier.distinctItemCount}',
      ),
      (
        label: YorksV1InventorySupplierStrings.documentsMissing.active(
          language,
        ),
        value: '${supplier.missingDocumentCount}',
      ),
      (
        label: YorksV1InventoryStrings.lastUpdated.active(language),
        value: supplier.lastReceiptAt == null
            ? YorksV1InventoryStrings.notConfigured.active(language)
            : _date(context, supplier.lastReceiptAt!),
      ),
      (
        label: YorksV1InventoryStrings.status.active(language),
        value: _supplierStatusLabel(supplier.status, language),
      ),
    ];

    final metricsPanel = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 5 : 2;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var index = 0; index < metrics.length; index++)
              SizedBox(
                width: columns == 2 && index == metrics.length - 1
                    ? constraints.maxWidth
                    : width,
                child: _HeroMetric(
                  label: metrics[index].label,
                  value: metrics[index].value,
                ),
              ),
          ],
        );
      },
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(
          compact ? AppSpacing.radiusLg : AppSpacing.radiusXl,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: AppSpacing.ambientBlur,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              identity,
              const SizedBox(height: AppSpacing.md),
              actions,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: AppSpacing.xl),
                  actions,
                ],
              ),
            if (supplier.isSystemUnknown) ...[
              const SizedBox(height: AppSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          YorksV1InventorySupplierStrings
                              .unknownSupplierExplanation
                              .active(language),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onWarningContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (compact)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    iconColor: Colors.white,
                    collapsedIconColor: Colors.white,
                    textColor: Colors.white,
                    collapsedTextColor: Colors.white,
                    title: Text(
                      YorksV1InventorySupplierStrings.overview.active(language),
                    ),
                    children: [metricsPanel],
                  ),
                ),
              )
            else
              metricsPanel,
          ],
        ),
      ),
    );
  }
}

class _SupplierFolderTabs extends StatelessWidget {
  const _SupplierFolderTabs({
    required this.selected,
    required this.language,
    required this.onSelected,
  });

  final YorksV1InventorySupplierFolderSection selected;
  final AppLanguage language;
  final ValueChanged<YorksV1InventorySupplierFolderSection> onSelected;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: const EdgeInsets.all(AppSpacing.xs),
    child: SingleChildScrollView(
      key: const ValueKey('supplier-folder-tabs'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in YorksV1InventorySupplierFolderSection.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
              child: _SupplierTabButton(
                label: _sectionLabel(section, language),
                selected: section == selected,
                onPressed: () => onSelected(section),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SupplierSection extends StatelessWidget {
  const _SupplierSection({
    required this.workspace,
    required this.language,
    required this.section,
    required this.onSection,
    required this.onAddDocument,
    required this.documentBusy,
    required this.onOpenItemTrail,
    required this.onOpenReceiptBatch,
    required this.onOpenDocument,
    required this.onReplaceDocument,
    required this.onOpenDestination,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final YorksV1InventorySupplierFolderSection section;
  final ValueChanged<YorksV1InventorySupplierFolderSection> onSection;
  final VoidCallback? onAddDocument;
  final bool documentBusy;
  final ValueChanged<String>? onOpenItemTrail;
  final ValueChanged<String>? onOpenReceiptBatch;
  final ValueChanged<String>? onOpenDocument;
  final ValueChanged<String>? onReplaceDocument;
  final ValueChanged<YorksV1InventorySupplierDestination>? onOpenDestination;

  @override
  Widget build(BuildContext context) => switch (section) {
    YorksV1InventorySupplierFolderSection.overview => _SupplierOverviewSection(
      workspace: workspace,
      language: language,
      onSection: onSection,
      onOpenReceiptBatch: onOpenReceiptBatch,
    ),
    YorksV1InventorySupplierFolderSection.itemsReceived =>
      _SupplierItemsSection(
        workspace: workspace,
        language: language,
        onOpen: onOpenItemTrail,
      ),
    YorksV1InventorySupplierFolderSection.receiptBatches =>
      _SupplierBatchesSection(
        workspace: workspace,
        language: language,
        onOpen: onOpenReceiptBatch,
      ),
    YorksV1InventorySupplierFolderSection.documents =>
      _SupplierDocumentsSection(
        workspace: workspace,
        language: language,
        onAdd: onAddDocument,
        busy: documentBusy,
        onOpen: onOpenDocument,
        onReplace: onReplaceDocument,
      ),
    YorksV1InventorySupplierFolderSection.destinations =>
      _SupplierDestinationsSection(
        workspace: workspace,
        language: language,
        onOpen: onOpenDestination,
      ),
    YorksV1InventorySupplierFolderSection.activityAudit =>
      _SupplierActivitySection(workspace: workspace, language: language),
  };
}

class _SupplierOverviewSection extends StatelessWidget {
  const _SupplierOverviewSection({
    required this.workspace,
    required this.language,
    required this.onSection,
    required this.onOpenReceiptBatch,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<YorksV1InventorySupplierFolderSection> onSection;
  final ValueChanged<String>? onOpenReceiptBatch;

  @override
  Widget build(BuildContext context) {
    final position = _SupplierPanel(
      title: YorksV1InventorySupplierStrings.supplierPosition.active(language),
      trailing: _StatusPill(
        label: YorksV1InventorySupplierStrings.controlled.active(language),
        tone: AppColors.success,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 620 ? 2 : 1;
          final width =
              (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
          final entries = <Widget>[
            _PositionCard(
              label: YorksV1InventorySupplierStrings.canonicalSupplier.active(
                language,
              ),
              value: workspace.supplier.name,
              detail: workspace.supplier.code,
            ),
            _PositionCard(
              label: YorksV1InventorySupplierStrings.aliases.active(language),
              value: workspace.supplier.aliases.isEmpty
                  ? YorksV1InventorySupplierStrings.noRecords.active(language)
                  : workspace.supplier.aliases.join(' · '),
            ),
            _PositionCard(
              label: YorksV1InventorySupplierStrings.quantityReceived.active(
                language,
              ),
              value: workspace.unitTotals.isEmpty
                  ? YorksV1InventorySupplierStrings.noRecords.active(language)
                  : workspace.unitTotals
                        .map(
                          (total) => '${total.acceptedQuantity} ${total.unit}',
                        )
                        .join(' · '),
            ),
            _PositionCard(
              label: YorksV1InventorySupplierStrings.documentControl.active(
                language,
              ),
              value:
                  '${workspace.supplier.missingDocumentCount} ${YorksV1InventorySupplierStrings.documentsMissing.active(language)}',
            ),
          ];
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final entry in entries) SizedBox(width: width, child: entry),
            ],
          );
        },
      ),
    );
    final batches = _SupplierPanel(
      title: YorksV1InventorySupplierStrings.recentReceiptBatches.active(
        language,
      ),
      trailing: TextButton(
        onPressed: () =>
            onSection(YorksV1InventorySupplierFolderSection.receiptBatches),
        child: Text(AppStrings.viewAll.active(language)),
      ),
      child: workspace.batches.isEmpty
          ? _InlineSupplierEmpty(language: language)
          : SizedBox(
              height: 176,
              child: ListView.builder(
                key: const ValueKey('supplier-overview-batches'),
                itemCount: workspace.batches.length,
                itemBuilder: (context, index) {
                  final batch = workspace.batches[index];
                  return _BatchListTile(
                    batch: batch,
                    language: language,
                    onTap: onOpenReceiptBatch == null
                        ? null
                        : () => onOpenReceiptBatch!(batch.id),
                  );
                },
              ),
            ),
    );
    final activity = _SupplierPanel(
      title: YorksV1InventorySupplierStrings.recentActivity.active(language),
      child: workspace.activity.isEmpty
          ? _InlineSupplierEmpty(language: language)
          : SizedBox(
              height: 300,
              child: ListView.builder(
                key: const ValueKey('supplier-overview-activity'),
                itemCount: workspace.activity.length,
                itemBuilder: (context, index) => _ActivityTile(
                  activity: workspace.activity[index],
                  language: language,
                ),
              ),
            ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            children: [
              position,
              const SizedBox(height: AppSpacing.md),
              batches,
              const SizedBox(height: AppSpacing.md),
              activity,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  position,
                  const SizedBox(height: AppSpacing.md),
                  batches,
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: activity),
          ],
        );
      },
    );
  }
}

class _SupplierItemsSection extends StatelessWidget {
  const _SupplierItemsSection({
    required this.workspace,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) => _SupplierPanel(
    title: YorksV1InventorySupplierStrings.itemsReceived.active(language),
    child: workspace.items.isEmpty
        ? _InlineSupplierEmpty(language: language)
        : _ResponsiveRecords<YorksV1InventorySupplierItemReceipt>(
            items: workspace.items,
            desktopHeaders: [
              YorksV1InventoryStrings.item.active(language),
              YorksV1InventoryStrings.size.active(language),
              YorksV1InventorySupplierStrings.quantityReceived.active(language),
              YorksV1InventoryStrings.onHand.active(language),
              YorksV1InventoryStrings.lastUpdated.active(language),
              YorksV1InventorySupplierStrings.receiptBatches.active(language),
              AppStrings.action.active(language),
            ],
            desktopCells: (context, item) => [
              _ItemIdentity(item: item),
              _TwoLineValue(primary: item.size, secondary: item.modelTag),
              Text('${item.acceptedQuantity} ${item.unit}'),
              Text('${item.currentOnHand} ${item.unit}'),
              Text(
                item.lastReceiptAt == null
                    ? YorksV1InventoryStrings.notConfigured.active(language)
                    : _date(context, item.lastReceiptAt!),
              ),
              Text('${item.receiptBatchCount}'),
              IconButton.outlined(
                key: ValueKey('supplier-item-trail-${item.inventoryItemId}'),
                tooltip: YorksV1InventoryStrings.view.active(language),
                onPressed: onOpen == null
                    ? null
                    : () => onOpen!(item.inventoryItemId),
                icon: const Icon(Icons.history_rounded),
              ),
            ],
            mobileBuilder: (context, item) => _ItemReceiptCard(
              item: item,
              language: language,
              onOpen: onOpen == null
                  ? null
                  : () => onOpen!(item.inventoryItemId),
            ),
          ),
  );
}

class _SupplierBatchesSection extends StatelessWidget {
  const _SupplierBatchesSection({
    required this.workspace,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) => _SupplierPanel(
    title: YorksV1InventorySupplierStrings.receiptsBatches.active(language),
    child: workspace.batches.isEmpty
        ? _InlineSupplierEmpty(language: language)
        : _ResponsiveRecords<YorksV1InventorySupplierReceiptBatch>(
            items: workspace.batches,
            desktopHeaders: [
              YorksV1LogisticsStrings.reference.active(language),
              YorksV1LogisticsStrings.date.active(language),
              YorksV1InventoryStrings.location.active(language),
              YorksV1InventoryStrings.status.active(language),
              YorksV1LogisticsStrings.deliveryQuantity.active(language),
              yorksV1ReceiptOutcomeCopy(
                YorksV1ReceiptOutcome.received,
              ).active(language),
              yorksV1ReceiptOutcomeCopy(
                YorksV1ReceiptOutcome.damaged,
              ).active(language),
              yorksV1MaterialReturnStateCopy(
                YorksV1MaterialReturnState.rejected,
              ).active(language),
              AppStrings.action.active(language),
            ],
            desktopCells: (context, batch) => [
              _TwoLineValue(
                primary: batch.receiptNumber,
                secondary: batch.supplierReference,
              ),
              Text(_date(context, batch.receivedDate)),
              Text(batch.location),
              _StatusPill(
                label: _humanizeData(batch.status),
                tone: batch.status == 'completed'
                    ? AppColors.success
                    : AppColors.blue,
              ),
              Text('${batch.deliveredQuantity} ${batch.unit}'),
              Text('${batch.acceptedQuantity} ${batch.unit}'),
              Text('${batch.damagedQuantity} ${batch.unit}'),
              Text('${batch.rejectedQuantity} ${batch.unit}'),
              IconButton.outlined(
                key: ValueKey('supplier-batch-detail-${batch.id}'),
                tooltip: YorksV1InventoryStrings.view.active(language),
                onPressed: onOpen == null ? null : () => onOpen!(batch.id),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
            mobileBuilder: (context, batch) => _ReceiptBatchCard(
              batch: batch,
              language: language,
              onOpen: onOpen == null ? null : () => onOpen!(batch.id),
            ),
          ),
  );
}

class _SupplierDocumentsSection extends ConsumerWidget {
  const _SupplierDocumentsSection({
    required this.workspace,
    required this.language,
    required this.onAdd,
    required this.busy,
    required this.onOpen,
    required this.onReplace,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final VoidCallback? onAdd;
  final bool busy;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protectedVersions = {
      for (final document
          in ref
                  .watch(
                    yorksV1SupplierDocumentWorkspaceProvider(
                      workspace.supplier.id,
                    ),
                  )
                  .valueOrNull
                  ?.documents ??
              const <YorksV1Document>[])
        document.id: document.currentVersion,
    };
    return _SupplierPanel(
      title: YorksV1InventorySupplierStrings.documents.active(language),
      trailing: FilledButton.icon(
        onPressed: busy ? null : onAdd,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          minimumSize: const Size(44, AppSpacing.minTapTarget),
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(
          YorksV1InventorySupplierStrings.addDocument.active(language),
        ),
      ),
      child: workspace.documents.isEmpty
          ? _InlineSupplierEmpty(language: language)
          : _ResponsiveRecords<YorksV1InventorySupplierDocument>(
              items: workspace.documents,
              desktopHeaders: [
                YorksV1InventorySupplierStrings.documents.active(language),
                YorksV1InventorySupplierStrings.documentType.active(language),
                YorksV1InventorySupplierStrings.businessReference.active(
                  language,
                ),
                AppStrings.notes.active(language),
                YorksV1DocumentStrings.classification.active(language),
                YorksV1DocumentStrings.revision.active(language),
                YorksV1DocumentStrings.actor.active(language),
                YorksV1LogisticsStrings.date.active(language),
                YorksV1DocumentStrings.entity.active(language),
                AppStrings.action.active(language),
              ],
              desktopCells: (context, document) {
                final version = protectedVersions[document.documentId];
                return [
                  _TwoLineValue(
                    primary: document.fileName,
                    secondary: document.mimeType,
                    icon: Icons.description_outlined,
                  ),
                  Text(_supplierDocumentTypeValue(version, language)),
                  Text(
                    version?.businessReference ??
                        YorksV1InventoryStrings.notConfigured.active(language),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      version?.supplierDocumentNotes ??
                          YorksV1InventoryStrings.notConfigured.active(
                            language,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_humanizeData(document.classification)),
                  Text('${document.revisionNumber}'),
                  Text(document.uploadedByDisplayName),
                  Text(_dateTime(context, document.uploadedAt)),
                  Text(
                    document.receiptBatchId ??
                        YorksV1InventoryStrings.notConfigured.active(language),
                  ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      IconButton.outlined(
                        key: ValueKey(
                          'supplier-document-download-${document.documentId}',
                        ),
                        tooltip: YorksV1DocumentStrings.download.active(
                          language,
                        ),
                        onPressed: busy || onOpen == null
                            ? null
                            : () => onOpen!(document.documentId),
                        icon: const Icon(YorksDataTransferIcons.exportData),
                      ),
                      IconButton.outlined(
                        key: ValueKey(
                          'supplier-document-replace-${document.documentId}',
                        ),
                        tooltip: YorksV1DocumentStrings.uploadVersion.active(
                          language,
                        ),
                        onPressed: busy || onReplace == null
                            ? null
                            : () => onReplace!(document.documentId),
                        icon: const Icon(YorksDataTransferIcons.importData),
                      ),
                    ],
                  ),
                ];
              },
              mobileBuilder: (context, document) => _DocumentCard(
                document: document,
                protectedVersion: protectedVersions[document.documentId],
                language: language,
                onOpen: onOpen == null
                    ? null
                    : () => onOpen!(document.documentId),
                onReplace: onReplace == null
                    ? null
                    : () => onReplace!(document.documentId),
              ),
            ),
    );
  }
}

class _SupplierDestinationsSection extends StatelessWidget {
  const _SupplierDestinationsSection({
    required this.workspace,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final ValueChanged<YorksV1InventorySupplierDestination>? onOpen;

  @override
  Widget build(BuildContext context) => _SupplierPanel(
    title: YorksV1InventorySupplierStrings.destinations.active(language),
    child: workspace.destinations.isEmpty
        ? _InlineSupplierEmpty(language: language)
        : _ResponsiveRecords<YorksV1InventorySupplierDestination>(
            items: workspace.destinations,
            desktopHeaders: [
              YorksV1InventoryStrings.item.active(language),
              YorksV1LogisticsStrings.project.active(language),
              YorksV1LogisticsStrings.scope.active(language),
              YorksV1InventoryStrings.request.active(language),
              YorksV1ShellStrings.dispatch.active(language),
              YorksV1LogisticsStrings.quantity.active(language),
              YorksV1InventoryStrings.status.active(language),
              YorksV1LogisticsStrings.date.active(language),
              AppStrings.action.active(language),
            ],
            desktopCells: (context, destination) => [
              Text(destination.itemDescription),
              _TwoLineValue(
                primary: destination.projectReference,
                secondary: destination.projectName,
              ),
              Text(destination.scopeName),
              Text(destination.requestNumber),
              Text(destination.dispatchNumber),
              Text('${destination.quantity} ${destination.unit}'),
              _StatusPill(
                label: _humanizeData(destination.state),
                tone: AppColors.blue,
              ),
              Text(_date(context, destination.dispatchedAt)),
              IconButton.outlined(
                key: ValueKey('supplier-destination-${destination.id}'),
                tooltip: YorksV1InventoryStrings.view.active(language),
                onPressed: onOpen == null ? null : () => onOpen!(destination),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ],
            mobileBuilder: (context, destination) => _DestinationCard(
              destination: destination,
              language: language,
              onOpen: onOpen == null ? null : () => onOpen!(destination),
            ),
          ),
  );
}

class _SupplierActivitySection extends StatelessWidget {
  const _SupplierActivitySection({
    required this.workspace,
    required this.language,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _SupplierPanel(
    title: YorksV1InventorySupplierStrings.activityAudit.active(language),
    child: workspace.activity.isEmpty
        ? _InlineSupplierEmpty(language: language)
        : ListView.builder(
            key: const ValueKey('supplier-activity-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: workspace.activity.length,
            itemBuilder: (context, index) => _ActivityTile(
              activity: workspace.activity[index],
              language: language,
            ),
          ),
  );
}

class _SupplierItemTrailDetail extends ConsumerWidget {
  const _SupplierItemTrailDetail({
    required this.supplierId,
    required this.inventoryItemId,
  });

  final String supplierId;
  final String inventoryItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final query = YorksV1InventorySupplierItemTrailQuery(
      supplierId: supplierId,
      inventoryItemId: inventoryItemId,
    );
    final trail = ref.watch(yorksV1InventorySupplierItemTrailProvider(query));
    return _SupplierDetailFrame(
      title: YorksV1InventorySupplierStrings.itemsReceived.active(language),
      child: trail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _SupplierDetailFailure(
          language: language,
          onRetry: () =>
              ref.invalidate(yorksV1InventorySupplierItemTrailProvider(query)),
        ),
        data: (workspace) =>
            _SupplierItemTrailContent(workspace: workspace, language: language),
      ),
    );
  }
}

class _SupplierItemTrailContent extends StatelessWidget {
  const _SupplierItemTrailContent({
    required this.workspace,
    required this.language,
  });

  final YorksV1InventorySupplierItemTrailWorkspace workspace;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final item = workspace.item;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _SupplierDetailIdentity(
          icon: Icons.inventory_2_outlined,
          title: item.description,
          subtitle: [
            item.itemCode,
            item.brandOrigin,
            item.size,
            item.modelTag,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
          metrics: [
            _DetailMetric(
              YorksV1InventoryStrings.onHand.active(language),
              '${item.currentOnHand} ${item.unit}',
            ),
            _DetailMetric(
              YorksV1InventoryStrings.reserved.active(language),
              '${item.reservedQuantity} ${item.unit}',
            ),
            _DetailMetric(
              YorksV1InventoryStrings.available.active(language),
              '${item.availableQuantity} ${item.unit}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierTrailReceiptLine>(
          title: YorksV1InventorySupplierStrings.receiptsBatches.active(
            language,
          ),
          items: workspace.receiptLines,
          itemBuilder: (context, line) => _SupplierDetailRecord(
            icon: Icons.receipt_long_outlined,
            title: line.receiptNumber,
            subtitle:
                '${line.acceptedQuantity} ${line.unit} · ${line.location}',
            trailing: _date(context, line.receivedDate),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierTrailMovement>(
          title: YorksV1InventoryStrings.movements.active(language),
          items: workspace.movements,
          itemBuilder: (context, movement) => _SupplierDetailRecord(
            icon: Icons.swap_vert_circle_outlined,
            title: _humanizeData(movement.movementType),
            subtitle:
                '${movement.quantityDelta} · ${YorksV1InventoryStrings.onHand.active(language)} ${movement.onHandAfterQuantity}',
            trailing: _dateTime(context, movement.createdAt),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierTrailReservation>(
          title: YorksV1InventoryStrings.reserved.active(language),
          items: workspace.reservations,
          itemBuilder: (context, reservation) => _SupplierDetailRecord(
            icon: Icons.bookmark_border_rounded,
            title: reservation.requestNumber,
            subtitle:
                '${reservation.projectReference} · ${reservation.remainingQuantity} ${reservation.unit}',
            trailing: _humanizeData(reservation.state),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierTrailDestination>(
          title: YorksV1InventorySupplierStrings.destinations.active(language),
          items: workspace.destinations,
          itemBuilder: (context, destination) => _SupplierDetailRecord(
            icon: Icons.alt_route_rounded,
            title: destination.dispatchNumber,
            subtitle:
                '${destination.projectReference} · ${destination.allocatedQuantity} ${destination.unit}',
            trailing: _date(context, destination.dispatchedAt),
          ),
        ),
        if (workspace.provenanceGaps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SupplierDetailList<YorksV1InventorySupplierTrailGap>(
            title: YorksV1InventorySupplierStrings.identityMissing.active(
              language,
            ),
            warning: true,
            items: workspace.provenanceGaps,
            itemBuilder: (context, gap) => _SupplierDetailRecord(
              icon: Icons.warning_amber_rounded,
              title: gap.dispatchNumber,
              subtitle:
                  '${gap.projectReference} · ${gap.unallocatedQuantity} ${gap.unit}',
              trailing: _humanizeData(gap.reasonCode),
              warning: true,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _SupplierReceiptBatchDetail extends ConsumerWidget {
  const _SupplierReceiptBatchDetail({
    required this.supplierId,
    required this.receiptBatchId,
    required this.onAddDocument,
    required this.onDownloadDocument,
    required this.onReplaceDocument,
  });

  final String supplierId;
  final String receiptBatchId;
  final VoidCallback onAddDocument;
  final ValueChanged<String> onDownloadDocument;
  final ValueChanged<String> onReplaceDocument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final query = YorksV1InventorySupplierReceiptBatchDetailQuery(
      supplierId: supplierId,
      receiptBatchId: receiptBatchId,
    );
    final detail = ref.watch(
      yorksV1InventorySupplierReceiptBatchDetailProvider(query),
    );
    final protectedVersions = {
      for (final document
          in ref
                  .watch(yorksV1SupplierDocumentWorkspaceProvider(supplierId))
                  .valueOrNull
                  ?.documents ??
              const <YorksV1Document>[])
        document.id: document.currentVersion,
    };
    return _SupplierDetailFrame(
      title: YorksV1InventorySupplierStrings.receiptsBatches.active(language),
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _SupplierDetailFailure(
          language: language,
          onRetry: () => ref.invalidate(
            yorksV1InventorySupplierReceiptBatchDetailProvider(query),
          ),
        ),
        data: (workspace) => _SupplierReceiptBatchContent(
          workspace: workspace,
          protectedVersions: protectedVersions,
          language: language,
          onAddDocument: onAddDocument,
          onDownloadDocument: onDownloadDocument,
          onReplaceDocument: onReplaceDocument,
        ),
      ),
    );
  }
}

class _SupplierReceiptBatchContent extends StatelessWidget {
  const _SupplierReceiptBatchContent({
    required this.workspace,
    required this.protectedVersions,
    required this.language,
    required this.onAddDocument,
    required this.onDownloadDocument,
    required this.onReplaceDocument,
  });

  final YorksV1InventorySupplierReceiptBatchDetailWorkspace workspace;
  final Map<String, YorksV1DocumentVersion> protectedVersions;
  final AppLanguage language;
  final VoidCallback onAddDocument;
  final ValueChanged<String> onDownloadDocument;
  final ValueChanged<String> onReplaceDocument;

  @override
  Widget build(BuildContext context) {
    final batch = workspace.batch;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _SupplierDetailIdentity(
          icon: Icons.receipt_long_outlined,
          title: batch.receiptNumber,
          subtitle: [
            batch.supplierReference,
            _humanizeData(batch.sourceType),
            batch.location,
          ].where((value) => value.isNotEmpty).join(' · '),
          status: _StatusPill(
            label: _humanizeData(batch.status),
            tone: AppColors.success,
          ),
          metrics: [
            for (final total in batch.unitTotals)
              _DetailMetric(
                YorksV1InventorySupplierStrings.quantityReceived.active(
                  language,
                ),
                '${total.acceptedQuantity} ${total.unit}',
              ),
            _DetailMetric(
              YorksV1InventoryStrings.itemsCount.active(language),
              '${batch.lineCount}',
            ),
            _DetailMetric(
              YorksV1InventorySupplierStrings.documents.active(language),
              '${batch.documentCount}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: const ValueKey('supplier-batch-add-document'),
            onPressed: onAddDocument,
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, AppSpacing.minTapTarget),
              backgroundColor: AppColors.navy,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              YorksV1InventorySupplierStrings.addDocument.active(language),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierReceiptBatchDetailLine>(
          title: YorksV1InventorySupplierStrings.itemsReceived.active(language),
          items: workspace.lines,
          itemBuilder: (context, line) => _SupplierDetailRecord(
            icon: Icons.inventory_2_outlined,
            title: line.description,
            subtitle:
                '${line.itemCode} · ${line.acceptedQuantity} ${line.unit} · ${line.location ?? batch.location}',
            trailing: line.serialNumber ?? line.batchLotNumber,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierDocument>(
          title: YorksV1InventorySupplierStrings.documents.active(language),
          items: workspace.documents,
          itemBuilder: (context, document) {
            final version = protectedVersions[document.documentId];
            return _SupplierDetailRecord(
              icon: Icons.description_outlined,
              title: document.fileName,
              subtitle: [
                _supplierDocumentTypeValue(version, language),
                version?.businessReference,
                '${YorksV1DocumentStrings.revision.active(language)} ${document.revisionNumber}',
                _humanizeData(document.classification),
                version?.supplierDocumentNotes,
              ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
              trailingWidget: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  IconButton.outlined(
                    tooltip: YorksV1DocumentStrings.download.active(language),
                    onPressed: () => onDownloadDocument(document.documentId),
                    icon: const Icon(YorksDataTransferIcons.exportData),
                  ),
                  IconButton.outlined(
                    tooltip: YorksV1DocumentStrings.uploadVersion.active(
                      language,
                    ),
                    onPressed: () => onReplaceDocument(document.documentId),
                    icon: const Icon(YorksDataTransferIcons.importData),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _SupplierDetailList<YorksV1InventorySupplierActivity>(
          title: YorksV1InventorySupplierStrings.activityAudit.active(language),
          items: workspace.activity,
          itemBuilder: (context, event) => _SupplierDetailRecord(
            icon: Icons.history_rounded,
            title: _humanizeData(event.eventType),
            subtitle:
                '${event.actorDisplayName} · ${_humanizeData(event.actorRole)}',
            trailing: _dateTime(context, event.occurredAt),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _SupplierDetailFrame extends StatelessWidget {
  const _SupplierDetailFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.headlineSmall)),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _SupplierDetailFailure extends StatelessWidget {
  const _SupplierDetailFailure({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: AppColors.muted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            YorksV1InventorySupplierStrings.loadFailed.active(language),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(
              YorksV1InventorySupplierStrings.tryAgain.active(language),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailMetric {
  const _DetailMetric(this.label, this.value);

  final String label;
  final String value;
}

class _SupplierDetailIdentity extends StatelessWidget {
  const _SupplierDetailIdentity({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_DetailMetric> metrics;
  final Widget? status;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, color: AppColors.blue, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.headlineSmall),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle, style: AppTypography.bodySmall),
                  ],
                ],
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: AppSpacing.sm),
              status!,
            ],
          ],
        ),
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 700 ? 3 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * AppSpacing.sm) /
                  columns;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: _PositionCard(
                        label: metric.label,
                        value: metric.value,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );
}

class _SupplierDetailList<T> extends StatelessWidget {
  const _SupplierDetailList({
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.warning = false,
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  final bool warning;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.titleLarge)),
            _StatusPill(
              label: '${items.length}',
              tone: warning ? AppColors.warning : AppColors.blue,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          const SizedBox.shrink()
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  itemBuilder(context, items[index]),
            ),
          ),
      ],
    ),
  );
}

class _SupplierDetailRecord extends StatelessWidget {
  const _SupplierDetailRecord({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        SizedBox.square(
          dimension: AppSpacing.minTapTarget,
          child: Icon(
            icon,
            color: warning ? AppColors.warning : AppColors.blue,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailingWidget!,
        ] else if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              trailing!,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ResponsiveRecords<T> extends StatelessWidget {
  const _ResponsiveRecords({
    required this.items,
    required this.desktopHeaders,
    required this.desktopCells,
    required this.mobileBuilder,
  });

  final List<T> items;
  final List<String> desktopHeaders;
  final List<Widget> Function(BuildContext context, T item) desktopCells;
  final Widget Function(BuildContext context, T item) mobileBuilder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 900) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(
            bottom: index == items.length - 1 ? 0 : AppSpacing.sm,
          ),
          child: mobileBuilder(context, items[index]),
        ),
      );
    }
    return _LocalTable<T>(
      headers: desktopHeaders,
      items: items,
      cells: desktopCells,
    );
  }
}

class _LocalTable<T> extends StatelessWidget {
  const _LocalTable({
    required this.headers,
    required this.items,
    required this.cells,
  });

  final List<String> headers;
  final List<T> items;
  final List<Widget> Function(BuildContext context, T item) cells;

  @override
  Widget build(BuildContext context) {
    final minWidth = headers.length * 138.0;
    return Scrollbar(
      thumbVisibility: false,
      child: SingleChildScrollView(
        key: const ValueKey('supplier-local-table-scroll'),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(
              AppColors.surfaceContainerLow,
            ),
            headingTextStyle: AppTypography.labelSmall.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .55,
            ),
            dataTextStyle: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
            columns: [
              for (final header in headers) DataColumn(label: Text(header)),
            ],
            rows: [
              for (final item in items)
                DataRow(
                  cells: [
                    for (final child in cells(context, item))
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: child,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemReceiptCard extends StatelessWidget {
  const _ItemReceiptCard({
    required this.item,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierItemReceipt item;
  final AppLanguage language;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => _RecordCard(
    icon: Icons.inventory_2_outlined,
    title: item.description,
    subtitle: item.itemCode,
    onTap: onOpen,
    children: [
      _LabelValue(
        label: YorksV1InventorySupplierStrings.quantityReceived.active(
          language,
        ),
        value: '${item.acceptedQuantity} ${item.unit}',
      ),
      _LabelValue(
        label: YorksV1InventoryStrings.onHand.active(language),
        value: '${item.currentOnHand} ${item.unit}',
      ),
      _LabelValue(
        label: YorksV1InventorySupplierStrings.receiptBatches.active(language),
        value: '${item.receiptBatchCount}',
      ),
      _LabelValue(
        label: YorksV1InventoryStrings.lastUpdated.active(language),
        value: item.lastReceiptAt == null
            ? YorksV1InventoryStrings.notConfigured.active(language)
            : _date(context, item.lastReceiptAt!),
      ),
    ],
  );
}

class _ReceiptBatchCard extends StatelessWidget {
  const _ReceiptBatchCard({
    required this.batch,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierReceiptBatch batch;
  final AppLanguage language;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => _RecordCard(
    icon: Icons.receipt_long_outlined,
    title: batch.receiptNumber,
    subtitle: batch.supplierReference,
    onTap: onOpen,
    status: _StatusPill(
      label: _humanizeData(batch.status),
      tone: batch.status == 'completed' ? AppColors.success : AppColors.blue,
    ),
    children: [
      _LabelValue(
        label: YorksV1LogisticsStrings.deliveryQuantity.active(language),
        value: '${batch.deliveredQuantity} ${batch.unit}',
      ),
      _LabelValue(
        label: yorksV1ReceiptOutcomeCopy(
          YorksV1ReceiptOutcome.received,
        ).active(language),
        value: '${batch.acceptedQuantity} ${batch.unit}',
      ),
      _LabelValue(
        label: YorksV1InventoryStrings.location.active(language),
        value: batch.location,
      ),
      _LabelValue(
        label: YorksV1LogisticsStrings.date.active(language),
        value: _date(context, batch.receivedDate),
      ),
    ],
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.protectedVersion,
    required this.language,
    required this.onOpen,
    required this.onReplace,
  });

  final YorksV1InventorySupplierDocument document;
  final YorksV1DocumentVersion? protectedVersion;
  final AppLanguage language;
  final VoidCallback? onOpen;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) => _RecordCard(
    icon: Icons.description_outlined,
    title: document.fileName,
    subtitle: [
      _supplierDocumentTypeValue(protectedVersion, language),
      protectedVersion?.businessReference,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
    onTap: onOpen,
    children: [
      _LabelValue(
        label: YorksV1InventorySupplierStrings.documentType.active(language),
        value: _supplierDocumentTypeValue(protectedVersion, language),
      ),
      if (protectedVersion?.businessReference case final reference?)
        _LabelValue(
          label: YorksV1InventorySupplierStrings.businessReference.active(
            language,
          ),
          value: reference,
        ),
      if (protectedVersion?.supplierDocumentNotes case final notes?)
        _LabelValue(label: AppStrings.notes.active(language), value: notes),
      _LabelValue(
        label: YorksV1DocumentStrings.revision.active(language),
        value: '${document.revisionNumber}',
      ),
      _LabelValue(
        label: YorksV1DocumentStrings.classification.active(language),
        value: _humanizeData(document.classification),
      ),
      _LabelValue(
        label: YorksV1DocumentStrings.actor.active(language),
        value: document.uploadedByDisplayName,
      ),
      _LabelValue(
        label: YorksV1LogisticsStrings.date.active(language),
        value: _dateTime(context, document.uploadedAt),
      ),
      OutlinedButton.icon(
        onPressed: onReplace,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, AppSpacing.minTapTarget),
        ),
        icon: const Icon(YorksDataTransferIcons.importData, size: 18),
        label: Text(YorksV1DocumentStrings.uploadVersion.active(language)),
      ),
    ],
  );
}

String _supplierDocumentTypeValue(
  YorksV1DocumentVersion? version,
  AppLanguage language,
) {
  final type = version?.supplierDocumentType;
  return type == null
      ? YorksV1InventoryStrings.notConfigured.active(language)
      : _supplierDocumentTypeLabel(type, language);
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.language,
    required this.onOpen,
  });

  final YorksV1InventorySupplierDestination destination;
  final AppLanguage language;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => _RecordCard(
    icon: Icons.alt_route_rounded,
    title: destination.itemDescription,
    subtitle: destination.dispatchNumber,
    onTap: onOpen,
    status: _StatusPill(
      label: _humanizeData(destination.state),
      tone: AppColors.blue,
    ),
    children: [
      _LabelValue(
        label: YorksV1LogisticsStrings.project.active(language),
        value: destination.projectReference,
      ),
      _LabelValue(
        label: YorksV1LogisticsStrings.scope.active(language),
        value: destination.scopeName,
      ),
      _LabelValue(
        label: YorksV1LogisticsStrings.quantity.active(language),
        value: '${destination.quantity} ${destination.unit}',
      ),
      _LabelValue(
        label: YorksV1LogisticsStrings.date.active(language),
        value: _date(context, destination.dispatchedAt),
      ),
    ],
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.language});

  final YorksV1InventorySupplierActivity activity;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(
            Icons.history_rounded,
            color: AppColors.blue,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _humanizeData(activity.eventType),
                style: AppTypography.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${activity.entityType} · ${activity.entityId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall,
              ),
              if (activity.reason != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(activity.reason!, style: AppTypography.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                activity.actorDisplayName,
                textAlign: TextAlign.end,
                style: AppTypography.labelLarge,
              ),
              Text(
                _humanizeData(activity.actorRole),
                textAlign: TextAlign.end,
                style: AppTypography.bodySmall,
              ),
              Text(
                _dateTime(context, activity.occurredAt),
                textAlign: TextAlign.end,
                style: AppTypography.labelSmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BatchListTile extends StatelessWidget {
  const _BatchListTile({
    required this.batch,
    required this.language,
    required this.onTap,
  });

  final YorksV1InventorySupplierReceiptBatch batch;
  final AppLanguage language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    minTileHeight: 64,
    leading: Container(
      width: AppSpacing.minTapTarget,
      height: AppSpacing.minTapTarget,
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: const Icon(
        Icons.receipt_long_outlined,
        color: AppColors.success,
        size: 20,
      ),
    ),
    title: Text(batch.receiptNumber, style: AppTypography.titleSmall),
    subtitle: Text(
      [
        batch.supplierReference,
        _date(context, batch.receivedDate),
        '${batch.lineCount} ${YorksV1InventoryStrings.itemsCount.active(language)}',
      ].whereType<String>().join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.bodySmall,
    ),
    trailing: Text(
      '${batch.acceptedQuantity} ${batch.unit}',
      style: AppTypography.labelLarge,
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
    this.onTap,
    this.status,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, color: AppColors.blue, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.titleSmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  status!,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - AppSpacing.sm) / 2;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final child in children)
                      SizedBox(width: width, child: child),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge,
      ),
    ],
  );
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 108),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(value, style: AppTypography.titleSmall),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(detail!, style: AppTypography.bodySmall),
        ],
      ],
    ),
  );
}

class _SupplierPanel extends StatelessWidget {
  const _SupplierPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(title, style: AppTypography.titleMedium)),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: child),
      ],
    ),
  );
}

class _SupplierSurface extends StatelessWidget {
  const _SupplierSurface({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _CompactMetricCard extends StatelessWidget {
  const _CompactMetricCard({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 74),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(icon, color: tone, size: 19),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  style: AppTypography.headlineSmall.copyWith(color: tone),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 58),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: Colors.white.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white.withValues(alpha: .72),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleSmall.copyWith(color: Colors.white),
        ),
      ],
    ),
  );
}

class _SupplierMiniMetric extends StatelessWidget {
  const _SupplierMiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge,
        ),
      ],
    ),
  );
}

class _InitialsTile extends StatelessWidget {
  const _InitialsTile({
    required this.label,
    required this.background,
    required this.foreground,
    this.size = AppSpacing.minTapTarget,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Text(
      label,
      style: AppTypography.labelLarge.copyWith(color: foreground),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(color: tone),
    ),
  );
}

class _SupplierTabButton extends StatelessWidget {
  const _SupplierTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.blueContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: selected ? AppColors.blueContainerStrong : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? AppColors.blue : AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: selected ? AppColors.blue : AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TwoLineValue extends StatelessWidget {
  const _TwoLineValue({this.primary, this.secondary, this.icon});

  final String? primary;
  final String? secondary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: AppColors.blue),
        const SizedBox(width: AppSpacing.sm),
      ],
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (primary != null)
              Text(
                primary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge,
              ),
            if (secondary != null)
              Text(
                secondary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall,
              ),
          ],
        ),
      ),
    ],
  );
}

class _ItemIdentity extends StatelessWidget {
  const _ItemIdentity({required this.item});

  final YorksV1InventorySupplierItemReceipt item;

  @override
  Widget build(BuildContext context) => _TwoLineValue(
    primary: '${item.itemCode} · ${item.description}',
    secondary: item.unit,
  );
}

class _FolderPagination extends StatelessWidget {
  const _FolderPagination({
    required this.workspace,
    required this.language,
    required this.onPrevious,
    required this.onNext,
  });

  final YorksV1InventorySupplierFolderWorkspace workspace;
  final AppLanguage language;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (workspace.totalCount <= workspace.limit && workspace.offset == 0) {
      return const SizedBox.shrink();
    }
    return _SupplierSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${AppStrings.showing.active(language)} ${workspace.offset + 1} ${AppStrings.of_.active(language)} ${workspace.totalCount}',
              style: AppTypography.bodySmall,
            ),
          ),
          IconButton.outlined(
            tooltip: AppStrings.previous.active(language),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.outlined(
            tooltip: AppStrings.next.active(language),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _InlineSupplierEmpty extends StatelessWidget {
  const _InlineSupplierEmpty({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 120),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.mutedLight),
          const SizedBox(height: AppSpacing.sm),
          Text(
            YorksV1InventorySupplierStrings.noRecords.active(language),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _SupplierEmptySurface extends StatelessWidget {
  const _SupplierEmptySurface({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _SupplierSurface(
    padding: const EdgeInsets.all(AppSpacing.xxxl),
    child: Column(
      children: [
        const Icon(
          Icons.folder_off_outlined,
          size: 40,
          color: AppColors.mutedLight,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          YorksV1InventorySupplierStrings.noSuppliers.active(language),
          textAlign: TextAlign.center,
          style: AppTypography.titleMedium,
        ),
      ],
    ),
  );
}

class _SupplierLoadingSurface extends StatelessWidget {
  const _SupplierLoadingSurface();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(
      dimension: 30,
      child: CircularProgressIndicator(strokeWidth: 3),
    ),
  );
}

class _SupplierErrorSurface extends StatelessWidget {
  const _SupplierErrorSurface({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              YorksV1InventorySupplierStrings.loadFailed.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                YorksV1InventorySupplierStrings.tryAgain.active(language),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RestrictedSupplierSurface extends StatelessWidget {
  const _RestrictedSupplierSurface({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, size: 44, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.restrictedLabel.active(language),
            style: AppTypography.titleMedium,
          ),
        ],
      ),
    ),
  );
}

String _supplierStatusLabel(
  YorksV1InventorySupplierStatus status,
  AppLanguage language,
) => switch (status) {
  YorksV1InventorySupplierStatus.active =>
    YorksV1InventorySupplierStrings.active.active(language),
  YorksV1InventorySupplierStatus.review =>
    YorksV1InventorySupplierStrings.review.active(language),
  YorksV1InventorySupplierStatus.inactive =>
    YorksV1InventorySupplierStrings.inactive.active(language),
  YorksV1InventorySupplierStatus.identityMissing =>
    YorksV1InventorySupplierStrings.identityMissing.active(language),
};

String _sectionLabel(
  YorksV1InventorySupplierFolderSection section,
  AppLanguage language,
) => switch (section) {
  YorksV1InventorySupplierFolderSection.overview =>
    YorksV1InventorySupplierStrings.overview.active(language),
  YorksV1InventorySupplierFolderSection.itemsReceived =>
    YorksV1InventorySupplierStrings.itemsReceived.active(language),
  YorksV1InventorySupplierFolderSection.receiptBatches =>
    YorksV1InventorySupplierStrings.receiptsBatches.active(language),
  YorksV1InventorySupplierFolderSection.documents =>
    YorksV1InventorySupplierStrings.documents.active(language),
  YorksV1InventorySupplierFolderSection.destinations =>
    YorksV1InventorySupplierStrings.destinations.active(language),
  YorksV1InventorySupplierFolderSection.activityAudit =>
    YorksV1InventorySupplierStrings.activityAudit.active(language),
};

Color _statusTone(YorksV1InventorySupplierStatus status) => switch (status) {
  YorksV1InventorySupplierStatus.active => AppColors.success,
  YorksV1InventorySupplierStatus.review => AppColors.warning,
  YorksV1InventorySupplierStatus.inactive => AppColors.muted,
  YorksV1InventorySupplierStatus.identityMissing => AppColors.warning,
};

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '—';
  if (words.length == 1) {
    return words.first
        .substring(0, words.first.length.clamp(1, 3))
        .toUpperCase();
  }
  return words.take(3).map((value) => value[0]).join().toUpperCase();
}

String _humanizeData(String value) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  return words
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _date(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

String _dateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatMediumDate(local);
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}

double _pagePadding(BuildContext context) => _isCompact(context)
    ? AppSpacing.mobileScreenHorizontal
    : AppSpacing.screenHorizontal;

bool _isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < AppSpacing.yorksV1ShellDesktopBreakpoint;

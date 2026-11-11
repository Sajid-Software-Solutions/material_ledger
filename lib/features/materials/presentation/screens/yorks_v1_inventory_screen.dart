import '../../../../shared/models/yorks_v1_inventory_register_query.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../../../shared/models/analytics_event.dart';
import '../../../../shared/providers/yorks_v1_inventory_import_recovery_provider.dart';
import 'yorks_v1_inventory_recovery_panel.dart';
import '../../../../shared/providers/yorks_v1_inventory_stock_command_provider.dart';
import '../../../../shared/models/yorks_v1_inventory_history.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_app_toast.dart';
import '../../../../shared/controllers/yorks_v1_inventory_import_controller.dart';
import '../../../../shared/controllers/yorks_v1_inventory_stock_command.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_supplier_strings.dart';
import '../../../../shared/models/yorks_v1_inventory_workbook.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_configuration_provider.dart';
import '../../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_repository_provider.dart';
import '../../../../shared/repositories/yorks_v1_logistics_repository.dart';
import '../../../../shared/services/yorks_v1_inventory_workbook_service.dart';

import 'yorks_v1_controlled_unit_field.dart';

enum _WarehouseTab { overview, items, movements, reservations }

enum _WarehouseItemStatus { all, active, reserved, low, out, inactive }

enum _WarehouseMovementType { all, stockIn, stockOut, dispatch, materialReturn }

enum _InventoryAction { createItem, adjustExisting }

const _overviewTopPanelBodyHeight = 264.0;
const _overviewListPanelBodyHeight = 360.0;

/// Inventory category IDs are server UUIDs. This local-only value represents
/// the explicit "create a parent category" decision in import preview state.
const _createImportedCategoryChoice = '__create_imported_category__';

/// R38.3 warehouse workspace. All content comes from the role-safe logistics
/// projection and every mutation remains repository/RPC backed.
class YorksV1InventoryScreen extends ConsumerStatefulWidget {
  const YorksV1InventoryScreen({super.key, this.initialTab});

  /// Allows the supplier workspace's local area tabs to return to the exact
  /// inventory surface selected by the user without keeping parallel tab
  /// state in the URL and widget tree.
  final String? initialTab;

  @override
  ConsumerState<YorksV1InventoryScreen> createState() =>
      _YorksV1InventoryScreenState();
}

class _YorksV1InventoryScreenState extends ConsumerState<YorksV1InventoryScreen>
    with WidgetsBindingObserver {
  late _WarehouseTab _tab;
  _WarehouseItemStatus _itemStatus = _WarehouseItemStatus.all;
  _WarehouseMovementType _movementType = _WarehouseMovementType.all;
  String _itemSearch = '';
  String _movementSearch = '';
  String? _itemUnit;
  String? _itemCategoryId;
  bool _fileActionBusy = false;
  int _stockOffset = 0;
  YorksV1InventoryWorkspace? _lastPage;
  String? _lastPageAuthority;
  Timer? _searchDebounce;
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Notification events are hints, not a complete stock-change stream.
    // Bound staleness while this workspace is visible, including adjustments
    // that do not generate a notification for the current user.
    _freshnessTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
    _tab = switch (widget.initialTab?.trim().toLowerCase()) {
      'items' => _WarehouseTab.items,
      'movements' => _WarehouseTab.movements,
      'reservations' => _WarehouseTab.reservations,
      'overview' => _WarehouseTab.overview,
      _ => _WarehouseTab.items,
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final canManage =
        ref.watch(yorksV1CurrentRoleProvider)?.canManageInventory ?? false;
    final suppliersEnabled = ref
        .watch(yorksV1FeatureFlagsProvider)
        .inventorySuppliers;
    final pendingImport = ref.watch(yorksV1InventoryImportRecoveryProvider);
    if (canManage && pendingImport?.exists == true) {
      return Scaffold(
        body: SafeArea(
          child: YorksV1InventoryImportRecoveryPanel(
            onResolved: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      );
    }
    final command = ref.watch(yorksV1InventoryStockCommandProvider);
    if (canManage && command.unresolved) {
      return Scaffold(
        body: SafeArea(
          child: _StateMessage(
            icon: Icons.pending_actions_outlined,
            message:
                (command.recoveryBlocked
                        ? YorksV1InventoryStrings.recoveryBlocked
                        : YorksV1InventoryStrings.uncertainSave)
                    .active(language),
            action: YorksV1InventoryStrings.retrySave.active(language),
            onAction: () async {
              if (command.busy) return;
              try {
                await command.save(
                  ref.read(yorksV1LogisticsRepositoryProvider),
                  () => command.pending!,
                );
              } catch (_) {
                if (mounted && !command.unresolved) {
                  _notice(
                    YorksV1InventoryStrings.saveRejected.active(language),
                    tone: YorksAppToastTone.error,
                  );
                }
              }
              if (mounted) {
                setState(() {});
                _refresh();
              }
            },
          ),
        ),
      );
    }
    final paged = _tab != _WarehouseTab.overview;
    final workspace = paged
        ? ref.watch(
            yorksV1InventoryRegisterProvider(
              YorksV1InventoryRegisterQuery(
                register: _tab == _WarehouseTab.reservations
                    ? 'reservations'
                    : 'stock',
                search: _tab == _WarehouseTab.items ? _itemSearch : '',
                status: _tab == _WarehouseTab.items ? _itemStatus.name : 'all',
                unit: _tab == _WarehouseTab.items ? _itemUnit : null,
                categoryId: _tab == _WarehouseTab.items
                    ? _itemCategoryId
                    : null,
                offset: _tab == _WarehouseTab.movements ? 0 : _stockOffset,
                limit: _tab == _WarehouseTab.movements ? 1 : 50,
              ),
            ),
          )
        : ref.watch(yorksV1InventoryWorkspaceProvider(null));
    final authority =
        '${ref.watch(yorksV1AuthUserIdProvider)}:${ref.watch(yorksV1CurrentRoleProvider)}:${_tab.name}';
    if (_lastPageAuthority != authority) {
      _lastPage = null;
      _lastPageAuthority = authority;
    }
    if (paged && !workspace.isLoading && !workspace.hasError) {
      _lastPage = workspace.asData?.value;
    }
    final visibleWorkspace =
        paged && workspace.isLoading && !workspace.hasValue && _lastPage != null
        ? AsyncValue<YorksV1InventoryWorkspace>.data(_lastPage!)
        : workspace;
    final compact =
        MediaQuery.sizeOf(context).width <
        AppSpacing.yorksV1ShellDesktopBreakpoint;
    return Scaffold(
      backgroundColor: compact ? AppColors.mobileSurface : AppColors.surface,
      body: SafeArea(
        top: false,
        child: visibleWorkspace.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _StateMessage(
            icon: Icons.cloud_off_rounded,
            message: YorksV1InventoryStrings.loadFailed.active(language),
            action: YorksV1LogisticsStrings.refresh.active(language),
            onAction: _refresh,
          ),
          data: (value) => _WarehouseBody(
            workspace: value,
            refreshing: workspace.isLoading,
            onPreviousPage: () =>
                setState(() => _stockOffset = math.max(0, _stockOffset - 50)),
            onNextPage: () => setState(() => _stockOffset += 50),
            language: language,
            canManage: canManage,
            tab: _tab,
            itemStatus: _itemStatus,
            movementType: _movementType,
            itemSearch: _itemSearch,
            movementSearch: _movementSearch,
            itemUnit: _itemUnit,
            itemCategoryId: _itemCategoryId,
            onTab: (value) => setState(() {
              _tab = value;
              _stockOffset = 0;
            }),
            onSuppliers: suppliersEnabled && canManage
                ? () => context.push('/yorks/inventory/suppliers')
                : null,
            onItemStatus: (value) => setState(() {
              _itemStatus = value;
              _stockOffset = 0;
            }),
            onMovementType: (value) => setState(() => _movementType = value),
            onItemSearch: (searchText) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                if (!mounted) return;
                final query = searchText.trim();
                final timing = Stopwatch()..start();
                final count = _matchingStock(
                  value.items,
                  search: query,
                  status: _itemStatus,
                  unit: _itemUnit,
                  categoryId: _itemCategoryId,
                ).length;
                timing.stop();
                setState(() {
                  _itemSearch = query;
                  _stockOffset = 0;
                });
                if (query.isNotEmpty && value.totalMatches == null) {
                  ref
                      .read(analyticsServiceProvider)
                      .recordMaterialSearch(
                        queryLength: query.length,
                        resultCount: count,
                        duration: timing.elapsed,
                        context: AnalyticsSearchContext.inventory,
                      );
                }
              });
            },
            onMovementSearch: (value) =>
                setState(() => _movementSearch = value.trim()),
            onItemUnit: (value) => setState(() {
              _itemUnit = value;
              _stockOffset = 0;
            }),
            onItemCategory: (value) => setState(() {
              _itemCategoryId = value;
              _stockOffset = 0;
            }),
            onRefresh: _refresh,
            onAdd: () => _openInventoryAction(value),
            onImport: suppliersEnabled && canManage
                ? () => context.push('/yorks/inventory/import')
                : () => _openImport(value),
            onDownload: () => _downloadTemplate(language),
            onExport: () => _export(value, language),
            onCategories: () => _openCategories(value),
            onItem: (item) => _openItem(item, canManage: canManage),
            onAdjust: (item) => _openExistingAdjustment(value, item),
          ),
        ),
      ),
    );
  }

  Future<void> _openExistingAdjustment(
    YorksV1InventoryWorkspace workspace,
    YorksV1LogisticsInventoryItem item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _InventoryAdjustmentDialog(
        workspace: workspace,
        inventoryItem: item,
        onCommitted: _refresh,
      ),
    );
  }

  void _refresh() {
    ref.invalidate(yorksV1InventoryRegisterProvider);
    ref.invalidate(yorksV1InventoryWorkspaceProvider);
    ref.invalidate(yorksV1InventoryItemDetailProvider);
    ref.invalidate(yorksV1InventoryHistoryProvider);
  }

  Future<void> _openInventoryAction(YorksV1InventoryWorkspace workspace) async {
    final action = await showDialog<_InventoryAction>(
      context: context,
      builder: (_) => const _InventoryActionChooser(),
    );
    if (!mounted || action == null) return;
    if (action == _InventoryAction.createItem) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CreateInventoryItemDialog(
          workspace: workspace,
          onCommitted: _refresh,
        ),
      );
      return;
    }
    if (workspace.totalMatches != null) {
      try {
        workspace = await ref
            .read(yorksV1LogisticsRepositoryProvider)
            .getInventory();
      } catch (_) {
        if (mounted) {
          _notice(
            YorksV1InventoryStrings.loadFailed.active(
              ref.read(languageProvider),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
    }
    final item = await showDialog<YorksV1LogisticsInventoryItem>(
      context: context,
      builder: (_) => _ExistingStockPicker(items: workspace.items),
    );
    if (!mounted || item == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InventoryAdjustmentDialog(
        workspace: workspace,
        inventoryItem: item,
        onCommitted: _refresh,
      ),
    );
  }

  Future<void> _openImport(YorksV1InventoryWorkspace workspace) async {
    if (workspace.totalMatches != null) {
      try {
        workspace = await ref
            .read(yorksV1LogisticsRepositoryProvider)
            .getInventory();
      } catch (_) {
        if (mounted) {
          _notice(
            YorksV1InventoryStrings.loadFailed.active(
              ref.read(languageProvider),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
    }
    ref.read(yorksV1InventoryImportControllerProvider.notifier).reset();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InventoryImportDialog(workspace: workspace, onCommitted: _refresh),
    );
  }

  Future<void> _downloadTemplate(AppLanguage language) async {
    if (_fileActionBusy) return;
    setState(() => _fileActionBusy = true);
    try {
      final saved = await ref
          .read(yorksV1InventoryWorkbookFileServiceProvider)
          .saveImportTemplate();
      if (mounted && saved) {
        _notice(
          YorksV1InventoryStrings.downloadFormatComplete.active(language),
          tone: YorksAppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        _notice(
          YorksV1InventoryStrings.downloadFormatFailed.active(language),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _fileActionBusy = false);
    }
  }

  Future<void> _export(
    YorksV1InventoryWorkspace workspace,
    AppLanguage language,
  ) async {
    if (_fileActionBusy) return;
    setState(() => _fileActionBusy = true);
    try {
      if (_tab == _WarehouseTab.items && workspace.totalMatches != null) {
        final repository =
            ref.read(yorksV1LogisticsRepositoryProvider)
                as YorksV1InventoryRegisterRepository;
        final exportUser = ref.read(yorksV1AuthUserIdProvider);
        final exportRole = ref.read(yorksV1CurrentRoleProvider);
        final search = _itemSearch;
        final status = _itemStatus.name;
        final unit = _itemUnit;
        final category = _itemCategoryId;
        final rows = <YorksV1LogisticsInventoryItem>[];
        final seen = <String>{};
        var offset = 0;
        while (true) {
          final page = await repository.getInventoryPage(
            YorksV1InventoryRegisterQuery(
              search: search,
              status: status,
              unit: unit,
              categoryId: category,
              offset: offset,
              limit: 500,
            ),
          );
          if (!mounted ||
              ref.read(yorksV1AuthUserIdProvider) != exportUser ||
              ref.read(yorksV1CurrentRoleProvider) != exportRole) {
            return;
          }
          for (final item in page.items) {
            if (!seen.add(item.id)) {
              throw StateError(
                'Stock changed during export; refresh and retry',
              );
            }
            rows.add(item);
          }
          if (!page.hasMore) break;
          if (page.items.isEmpty) {
            throw StateError('Stock page did not advance');
          }
          offset += page.items.length;
        }
        workspace = YorksV1InventoryWorkspace(
          items: rows,
          categories: workspace.categories,
          totalMatches: rows.length,
        );
      }
      final saved = await ref
          .read(yorksV1InventoryWorkbookFileServiceProvider)
          .saveStockRegister(
            workspace:
                _tab == _WarehouseTab.items && workspace.totalMatches == null
                ? YorksV1InventoryWorkspace(
                    items: _matchingStock(
                      workspace.items,
                      search: _itemSearch,
                      status: _itemStatus,
                      unit: _itemUnit,
                      categoryId: _itemCategoryId,
                    ),
                    categories: workspace.categories,
                    recentMovements: const [],
                    reservations: const [],
                  )
                : workspace,
            suggestedName:
                YorksV1PlatformInventoryWorkbookFileService.stockRegisterSuggestedName(
                  DateTime.now(),
                ),
          );
      if (mounted && saved) {
        _notice(
          YorksV1InventoryStrings.exportRegisterComplete.active(language),
          tone: YorksAppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        _notice(
          YorksV1InventoryStrings.exportRegisterFailed.active(language),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _fileActionBusy = false);
    }
  }

  Future<void> _openCategories(YorksV1InventoryWorkspace workspace) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoriesDialog(
        categories: workspace.categories,
        onCommitted: _refresh,
      ),
    );
  }

  Future<void> _openItem(
    YorksV1LogisticsInventoryItem item, {
    required bool canManage,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InventoryItemDetailDialog(
        inventoryItemId: item.id,
        canManage: canManage,
        onChanged: _refresh,
      ),
    );
  }

  void _notice(String message, {YorksAppToastTone? tone}) => YorksAppToast.show(
    context,
    title: message,
    tone: tone ?? YorksAppToastTone.information,
  );
}

class _WarehouseBody extends StatelessWidget {
  const _WarehouseBody({
    required this.workspace,
    this.refreshing = false,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.language,
    required this.canManage,
    required this.tab,
    required this.itemStatus,
    required this.movementType,
    required this.itemSearch,
    required this.movementSearch,
    required this.itemUnit,
    required this.itemCategoryId,
    required this.onTab,
    required this.onSuppliers,
    required this.onItemStatus,
    required this.onMovementType,
    required this.onItemSearch,
    required this.onMovementSearch,
    required this.onItemUnit,
    required this.onItemCategory,
    required this.onRefresh,
    required this.onAdd,
    required this.onImport,
    required this.onDownload,
    required this.onExport,
    required this.onCategories,
    required this.onItem,
    required this.onAdjust,
  });

  final YorksV1InventoryWorkspace workspace;
  final bool refreshing;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final AppLanguage language;
  final bool canManage;
  final _WarehouseTab tab;
  final _WarehouseItemStatus itemStatus;
  final _WarehouseMovementType movementType;
  final String itemSearch;
  final String movementSearch;
  final String? itemUnit;
  final String? itemCategoryId;
  final ValueChanged<_WarehouseTab> onTab;
  final VoidCallback? onSuppliers;
  final ValueChanged<_WarehouseItemStatus> onItemStatus;
  final ValueChanged<_WarehouseMovementType> onMovementType;
  final ValueChanged<String> onItemSearch;
  final ValueChanged<String> onMovementSearch;
  final ValueChanged<String?> onItemUnit;
  final ValueChanged<String?> onItemCategory;
  final VoidCallback onRefresh;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onExport;
  final VoidCallback onCategories;
  final ValueChanged<YorksV1LogisticsInventoryItem> onItem;
  final ValueChanged<YorksV1LogisticsInventoryItem> onAdjust;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <
        AppSpacing.yorksV1ShellDesktopBreakpoint;
    final pagePadding = compact
        ? AppSpacing.mobileScreenHorizontal
        : AppSpacing.screenHorizontal;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            compact ? AppSpacing.lg : AppSpacing.xxl,
            pagePadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.pageMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WarehouseHeader(
                    language: language,
                    compact: compact,
                    canManage: canManage,
                    onSuppliers: onSuppliers,
                    onRefresh: onRefresh,
                    onAdd: onAdd,
                    onImport: onImport,
                    onDownload: onDownload,
                  ),
                  if (workspace.fetchedAt != null || refreshing)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        refreshing
                            ? YorksV1InventoryStrings.refreshing.active(
                                language,
                              )
                            : '${YorksV1InventoryStrings.refreshedAt.active(language)} · ${DateFormat.yMd().add_jm().format(workspace.fetchedAt!.toLocal())}',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  _WarehouseTabs(
                    selected: tab,
                    language: language,
                    onSelected: onTab,
                    onSuppliers: onSuppliers,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  switch (tab) {
                    _WarehouseTab.overview => _OverviewTab(
                      workspace: workspace,
                      language: language,
                      canManage: canManage,
                      onAdd: onAdd,
                      onImport: onImport,
                      onDownload: onDownload,
                      onExport: onExport,
                      onCategories: onCategories,
                      onItem: onItem,
                    ),
                    _WarehouseTab.items => _ItemsTab(
                      workspace: workspace,
                      language: language,
                      canManage: canManage,
                      status: itemStatus,
                      search: itemSearch,
                      unit: itemUnit,
                      categoryId: itemCategoryId,
                      onStatus: onItemStatus,
                      onSearch: onItemSearch,
                      onUnit: onItemUnit,
                      onCategory: onItemCategory,
                      onAdd: onAdd,
                      onDownload: onDownload,
                      onExport: onExport,
                      onCategories: onCategories,
                      onItem: onItem,
                      onAdjust: onAdjust,
                    ),
                    _WarehouseTab.movements => _PagedInventoryHistory(
                      language: language,
                    ),
                    _WarehouseTab.reservations => _ReservationsTab(
                      reservations: workspace.reservations,
                      language: language,
                    ),
                  },
                  if (workspace.totalMatches != null &&
                      (tab == _WarehouseTab.items ||
                          tab == _WarehouseTab.reservations))
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: workspace.pageOffset == 0 || refreshing
                              ? null
                              : onPreviousPage,
                          child: Text(
                            YorksV1InventoryStrings.previousPage.active(
                              language,
                            ),
                          ),
                        ),
                        Text(
                          '${workspace.pageOffset + (workspace.totalMatches == 0 ? 0 : 1)}–${math.min(workspace.pageOffset + 50, workspace.totalMatches!)} / ${workspace.totalMatches}',
                        ),
                        TextButton(
                          onPressed: workspace.hasMore && !refreshing
                              ? onNextPage
                              : null,
                          child: Text(
                            YorksV1InventoryStrings.nextPage.active(language),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: compact ? 112 : AppSpacing.massive),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarehouseHeader extends StatelessWidget {
  const _WarehouseHeader({
    required this.language,
    required this.compact,
    required this.canManage,
    required this.onSuppliers,
    required this.onRefresh,
    required this.onAdd,
    required this.onImport,
    required this.onDownload,
  });

  final AppLanguage language;
  final bool compact;
  final bool canManage;
  final VoidCallback? onSuppliers;
  final VoidCallback onRefresh;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The office sidebar reduces the usable content width on tablets even
        // when the overall window is wider than the mobile breakpoint.
        final stacked = compact || constraints.maxWidth < 980;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              Text(
                YorksV1InventoryStrings.procurementWorkspace.active(language),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1InventoryStrings.warehouseInventory.active(language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  (stacked
                          ? AppTypography.headlineMedium
                          : AppTypography.displaySmall)
                      .copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (!compact)
              Text(
                YorksV1InventoryStrings.subtitle.active(language),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
          ],
        );
        final actions = Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          children: [
            if (canManage)
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  YorksV1InventoryStrings.addReceive.active(language),
                ),
              ),
            if (canManage)
              PopupMenuButton<String>(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) =>
                    value == 'import' ? onImport() : onDownload(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'import',
                    child: Text(
                      YorksV1InventoryStrings.importInventory.active(language),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'template',
                    child: Text(
                      YorksV1InventoryStrings.downloadImportFormat.active(
                        language,
                      ),
                    ),
                  ),
                ],
              ),
            IconButton(
              tooltip: YorksV1LogisticsStrings.refresh.active(language),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: AppSpacing.lg),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.xl),
            actions,
          ],
        );
      },
    );
  }
}

class _WarehouseTabs extends StatelessWidget {
  const _WarehouseTabs({
    required this.selected,
    required this.language,
    required this.onSelected,
    required this.onSuppliers,
  });

  final _WarehouseTab selected;
  final AppLanguage language;
  final ValueChanged<_WarehouseTab> onSelected;
  final VoidCallback? onSuppliers;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _WarehouseTab.overview: YorksV1InventoryStrings.overview,
      _WarehouseTab.items: YorksV1InventoryStrings.items,
      _WarehouseTab.movements: YorksV1InventoryStrings.movements,
      _WarehouseTab.reservations: YorksV1InventoryStrings.reservations,
    };
    const icons = {
      _WarehouseTab.overview: Icons.home_outlined,
      _WarehouseTab.items: Icons.inventory_2_outlined,
      _WarehouseTab.movements: Icons.history_rounded,
      _WarehouseTab.reservations: Icons.verified_user_outlined,
    };
    if (MediaQuery.sizeOf(context).width <= 720) {
      return InputDecorator(
        decoration: const InputDecoration(border: OutlineInputBorder()),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('inventory-section-selector'),
            value: selected.name,
            isExpanded: true,
            items: [
              for (final value in _WarehouseTab.values)
                DropdownMenuItem(
                  value: value.name,
                  child: Text(labels[value]!.active(language)),
                ),
              if (onSuppliers != null)
                DropdownMenuItem(
                  value: 'suppliers',
                  child: Text(
                    YorksV1InventorySupplierStrings.suppliers.active(language),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == 'suppliers') {
                onSuppliers?.call();
                return;
              }
              if (value != null) onSelected(_WarehouseTab.values.byName(value));
            },
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            for (final value in _WarehouseTab.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: _TabButton(
                  label: labels[value]!.active(language),
                  icon: icons[value]!,
                  selected: value == selected,
                  onPressed: () => onSelected(value),
                ),
              ),
            if (onSuppliers != null)
              _TabButton(
                label: YorksV1InventorySupplierStrings.suppliers.active(
                  language,
                ),
                icon: Icons.group_outlined,
                selected: false,
                onPressed: onSuppliers!,
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.surfaceContainerLowest : Colors.transparent,
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
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.navy : AppColors.muted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: selected ? AppColors.navy : AppColors.inkSecondary,
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.workspace,
    required this.language,
    required this.canManage,
    required this.onAdd,
    required this.onImport,
    required this.onDownload,
    required this.onExport,
    required this.onCategories,
    required this.onItem,
  });

  final YorksV1InventoryWorkspace workspace;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onExport;
  final VoidCallback onCategories;
  final ValueChanged<YorksV1LogisticsInventoryItem> onItem;

  @override
  Widget build(BuildContext context) {
    final attention = workspace.items
        .where(
          (item) => item.isActive && (item.isLowStock || item.isOutOfStock),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * AppSpacing.md) /
                columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _MetricCard(
                  width: width,
                  icon: Icons.inventory_2_outlined,
                  label: YorksV1InventoryStrings.activeStockItems.active(
                    language,
                  ),
                  value: '${workspace.summary.totalActiveItems}',
                  tone: AppColors.blue,
                  detail: YorksV1InventoryStrings.activeWarehouseCatalogue
                      .active(language),
                ),
                _MetricCard(
                  width: width,
                  icon: Icons.check_circle_outline_rounded,
                  label: YorksV1InventoryStrings.itemsWithReservations.active(
                    language,
                  ),
                  value: '${workspace.summary.reservedCount}',
                  tone: AppColors.purple,
                  detail: YorksV1InventoryStrings.committedToActiveWork.active(
                    language,
                  ),
                ),
                _MetricCard(
                  width: width,
                  icon: Icons.lock_clock_outlined,
                  label: YorksV1InventoryStrings.lowStock.active(language),
                  value: '${workspace.summary.lowStockCount}',
                  tone: AppColors.warning,
                  detail: YorksV1InventoryStrings.configuredThresholds.active(
                    language,
                  ),
                ),
                _MetricCard(
                  width: width,
                  icon: Icons.warning_amber_rounded,
                  label: YorksV1InventoryStrings.outOfStock.active(language),
                  value: '${workspace.summary.outOfStockCount}',
                  tone: AppColors.error,
                  detail: YorksV1InventoryStrings.noAvailableQuantity.active(
                    language,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _TrustCard(language: language),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final attentionCard = _WarehousePanel(
              key: const ValueKey('inventory-attention-panel'),
              title: YorksV1InventoryStrings.needsAttention.active(language),
              subtitle: YorksV1InventoryStrings.onlyAttentionItems.active(
                language,
              ),
              trailing: _CountPill(
                '${attention.length} ${YorksV1InventoryStrings.items.active(language)}',
                tone: AppColors.warning,
              ),
              bodyHeight: wide
                  ? _overviewTopPanelBodyHeight
                  : math.min(
                      _overviewTopPanelBodyHeight,
                      math.max(112, attention.length * 70).toDouble(),
                    ),
              child: attention.isEmpty
                  ? Center(
                      child: _InlineEmpty(
                        message: YorksV1InventoryStrings.healthy.active(
                          language,
                        ),
                      ),
                    )
                  : _BoundedOverviewList(
                      key: const ValueKey('inventory-attention-list'),
                      itemCount: attention.length,
                      itemBuilder: (context, index) {
                        final item = attention[index];
                        return _AttentionRow(
                          item: item,
                          language: language,
                          onTap: () => onItem(item),
                        );
                      },
                    ),
            );
            final tools = _WarehousePanel(
              key: const ValueKey('inventory-quick-tools-panel'),
              title: YorksV1InventoryStrings.quickTools.active(language),
              subtitle:
                  (canManage
                          ? YorksV1InventoryStrings.commonProcurementActions
                          : YorksV1InventoryStrings.readOnlyInventoryAccess)
                      .active(language),
              bodyHeight: wide ? _overviewTopPanelBodyHeight : null,
              child: _QuickTools(
                language: language,
                canManage: canManage,
                onAdd: onAdd,
                onImport: onImport,
                onDownload: onDownload,
                onExport: onExport,
                onCategories: onCategories,
              ),
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: attentionCard),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 3, child: tools),
                    ],
                  )
                : Column(
                    children: [
                      attentionCard,
                      const SizedBox(height: AppSpacing.lg),
                      tools,
                    ],
                  );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final categories = _CategoryCoverage(
              workspace: workspace,
              language: language,
              bodyHeight: _overviewListPanelBodyHeight,
            );
            final movements = _WarehousePanel(
              key: const ValueKey('inventory-recent-movements-panel'),
              title: YorksV1InventoryStrings.recentActivity.active(language),
              subtitle: YorksV1InventoryStrings.recentActivityHelp.active(
                language,
              ),
              bodyHeight: _overviewListPanelBodyHeight,
              child: workspace.recentMovements.isEmpty
                  ? Center(
                      child: _InlineEmpty(
                        message: YorksV1InventoryStrings.noMovements.active(
                          language,
                        ),
                      ),
                    )
                  : _BoundedOverviewList(
                      key: const ValueKey('inventory-recent-movement-list'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      itemCount: workspace.recentMovements.length,
                      itemBuilder: (context, index) => _MovementTile(
                        movement: workspace.recentMovements[index],
                      ),
                    ),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  categories,
                  const SizedBox(height: AppSpacing.lg),
                  movements,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: categories),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: movements),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.detail,
  });
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final compact = width < 220;
    return SizedBox(
      width: width,
      height: 116,
      child: _Surface(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(width: 4, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Icon(icon, color: tone, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.inkSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 10 : null,
                              height: compact ? 1.1 : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            value,
                            style: AppTypography.headlineMedium.copyWith(
                              fontSize: compact ? 24 : null,
                              height: compact ? 1.05 : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                              fontSize: compact ? 10 : null,
                              height: compact ? 1.15 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.blueContainerStrong),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final formula = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FormulaChip(YorksV1InventoryStrings.onHand.active(language)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text('-'),
              ),
              _FormulaChip(YorksV1InventoryStrings.reserved.active(language)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text('='),
              ),
              _FormulaChip(
                YorksV1InventoryStrings.available.active(language),
                filled: true,
              ),
            ],
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1InventoryStrings.stockFormula.active(language),
                style: AppTypography.titleSmall.copyWith(color: AppColors.navy),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                YorksV1InventoryStrings.formulaHelp.active(language),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_outlined, color: AppColors.blue),
                const SizedBox(height: AppSpacing.md),
                copy,
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: formula,
                ),
              ],
            );
          }
          return Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.blue),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: formula),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: copy),
            ],
          );
        },
      ),
    ),
  );
}

class _FormulaChip extends StatelessWidget {
  const _FormulaChip(this.label, {this.filled = false});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 32),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(
      color: filled ? AppColors.blue : AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      border: Border.all(
        color: filled ? AppColors.blue : AppColors.blueContainerStrong,
      ),
    ),
    child: Text(
      label,
      style: AppTypography.labelMedium.copyWith(
        color: filled ? Colors.white : AppColors.navy,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _WarehousePanel extends StatelessWidget {
  const _WarehousePanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.bodyHeight,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final double? bodyHeight;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.headlineSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(subtitle!, style: AppTypography.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        if (bodyHeight == null)
          child
        else
          SizedBox(height: bodyHeight, child: child),
      ],
    ),
  );
}

class _BoundedOverviewList extends StatefulWidget {
  const _BoundedOverviewList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;

  @override
  State<_BoundedOverviewList> createState() => _BoundedOverviewListState();
}

class _BoundedOverviewListState extends State<_BoundedOverviewList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    child: ListView.builder(
      controller: _controller,
      primary: false,
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.label, {required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .1),
      border: Border.all(color: tone.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(label, style: AppTypography.labelLarge.copyWith(color: tone)),
  );
}

class _QuickTools extends StatelessWidget {
  const _QuickTools({
    required this.language,
    required this.canManage,
    required this.onAdd,
    required this.onImport,
    required this.onDownload,
    required this.onExport,
    required this.onCategories,
  });
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onDownload;
  final VoidCallback onExport;
  final VoidCallback onCategories;

  @override
  Widget build(BuildContext context) {
    final tools = [
      if (canManage) ...[
        (
          YorksDataTransferIcons.downloadTemplate,
          YorksV1InventoryStrings.downloadFormat.active(language),
          onDownload,
        ),
        (
          YorksDataTransferIcons.importData,
          YorksV1InventoryStrings.importInventory.active(language),
          onImport,
        ),
        (
          Icons.add_box_outlined,
          YorksV1InventoryStrings.addReceive.active(language),
          onAdd,
        ),
      ],
      (
        YorksDataTransferIcons.exportData,
        YorksV1InventoryStrings.exportRegister.active(language),
        onExport,
      ),
      if (canManage)
        (
          Icons.category_outlined,
          YorksV1InventoryStrings.manageCategories.active(language),
          onCategories,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTwoColumns = constraints.maxWidth > 340;
          final tileWidth = hasTwoColumns
              ? (constraints.maxWidth - AppSpacing.sm) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var index = 0; index < tools.length; index++)
                SizedBox(
                  width:
                      hasTwoColumns &&
                          tools.length.isOdd &&
                          index == tools.length - 1
                      ? constraints.maxWidth
                      : tileWidth,
                  child: Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: tileWidth,
                      child: _QuickToolTile(
                        key: ValueKey('inventory-quick-tool-$index'),
                        icon: tools[index].$1,
                        label: tools[index].$2,
                        onTap: tools[index].$3,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, color: AppColors.blue, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: AppTypography.titleSmall)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CategoryCoverage extends StatelessWidget {
  const _CategoryCoverage({
    required this.workspace,
    required this.language,
    required this.bodyHeight,
  });
  final YorksV1InventoryWorkspace workspace;
  final AppLanguage language;
  final double bodyHeight;

  @override
  Widget build(BuildContext context) {
    final familyCounts = <String, int>{};
    for (final category in workspace.categories) {
      final family = category.parentName ?? category.name;
      familyCounts.update(
        family,
        (value) => value + category.itemCount,
        ifAbsent: () => category.itemCount,
      );
    }
    final families = familyCounts.entries.toList(growable: false)
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0 ? count : a.key.compareTo(b.key);
      });
    final maxItems = math.max(
      1,
      families.fold<int>(0, (best, category) => math.max(best, category.value)),
    );
    return _WarehousePanel(
      key: const ValueKey('inventory-category-panel'),
      title: YorksV1InventoryStrings.categoryCoverage.active(language),
      subtitle: YorksV1InventoryStrings.categoryCoverageHelp.active(language),
      bodyHeight: bodyHeight,
      child: _BoundedOverviewList(
        key: const ValueKey('inventory-category-list'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        itemCount: families.length,
        itemBuilder: (context, index) =>
            _CategoryCoverageRow(category: families[index], maxItems: maxItems),
      ),
    );
  }
}

class _CategoryCoverageRow extends StatelessWidget {
  const _CategoryCoverageRow({required this.category, required this.maxItems});

  final MapEntry<String, int> category;
  final int maxItems;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category.key,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text('${category.value}', style: AppTypography.labelLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(
          value: category.value / maxItems,
          minHeight: 7,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          backgroundColor: AppColors.surfaceContainerHighest,
        ),
      ],
    ),
  );
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.item,
    required this.language,
    required this.onTap,
  });
  final YorksV1LogisticsInventoryItem item;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.isOutOfStock
                  ? AppColors.errorContainer
                  : AppColors.warningContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              item.isOutOfStock
                  ? Icons.warning_amber_rounded
                  : Icons.inventory_2_outlined,
              color: item.isOutOfStock ? AppColors.error : AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.description, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${_quantity(item.availableQuantity)} ${item.unit} ${YorksV1InventoryStrings.available.active(language)}',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          _StockBadge(item: item, language: language),
        ],
      ),
    ),
  );
}

List<YorksV1LogisticsInventoryItem> _matchingStock(
  List<YorksV1LogisticsInventoryItem> source, {
  required String search,
  required _WarehouseItemStatus status,
  String? unit,
  String? categoryId,
}) {
  final key = search.toLowerCase();
  return source
      .where((item) {
        final statusMatch = switch (status) {
          _WarehouseItemStatus.all => true,
          _WarehouseItemStatus.active => item.isActive,
          _WarehouseItemStatus.reserved =>
            double.tryParse(item.reservedQuantity) != null &&
                double.parse(item.reservedQuantity) > 0,
          _WarehouseItemStatus.low => item.isLowStock,
          _WarehouseItemStatus.out => item.isOutOfStock,
          _WarehouseItemStatus.inactive => !item.isActive,
        };
        final haystack =
            '${item.itemCode ?? ''} ${item.description} ${item.brandOrigin ?? ''} ${item.unit} ${item.categoryPath ?? item.categoryName ?? ''} ${item.locationBin ?? ''}'
                .toLowerCase();
        return statusMatch &&
            (unit == null || item.unit == unit) &&
            (categoryId == null || item.categoryId == categoryId) &&
            (key.isEmpty || haystack.contains(key));
      })
      .toList(growable: false);
}

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({
    required this.workspace,
    required this.language,
    required this.canManage,
    required this.status,
    required this.search,
    required this.unit,
    required this.categoryId,
    required this.onStatus,
    required this.onSearch,
    required this.onUnit,
    required this.onCategory,
    required this.onAdd,
    required this.onDownload,
    required this.onExport,
    required this.onCategories,
    required this.onItem,
    required this.onAdjust,
  });
  final YorksV1InventoryWorkspace workspace;
  final AppLanguage language;
  final bool canManage;
  final _WarehouseItemStatus status;
  final String search;
  final String? unit;
  final String? categoryId;
  final ValueChanged<_WarehouseItemStatus> onStatus;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onUnit;
  final ValueChanged<String?> onCategory;
  final VoidCallback onAdd;
  final VoidCallback onDownload;
  final VoidCallback onExport;
  final VoidCallback onCategories;
  final ValueChanged<YorksV1LogisticsInventoryItem> onItem;
  final ValueChanged<YorksV1LogisticsInventoryItem> onAdjust;

  @override
  Widget build(BuildContext context) {
    final items = _matchingStock(
      workspace.items,
      search: search,
      status: status,
      unit: unit,
      categoryId: categoryId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WarehouseItemFilters(
          search: search,
          workspace: workspace,
          language: language,
          status: status,
          unit: unit,
          categoryId: categoryId,
          shownItems: items.length,
          canManage: canManage,
          onSearch: onSearch,
          onStatus: onStatus,
          onUnit: onUnit,
          onCategory: onCategory,
          onAdd: onAdd,
          onDownload: onDownload,
          onExport: onExport,
          onCategories: onCategories,
        ),
        const SizedBox(height: AppSpacing.lg),
        _WarehousePanel(
          title: YorksV1InventoryStrings.warehouseItemsTitle.active(language),
          subtitle: YorksV1InventoryStrings.warehouseItemsHelp.active(language),
          child: items.isEmpty
              ? _StateMessage(
                  icon: Icons.inventory_2_outlined,
                  message: YorksV1InventoryStrings.noItems.active(language),
                )
              : LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth >=
                          AppSpacing.yorksV1DesktopBreakpoint
                      ? _InventoryTable(
                          items: items,
                          language: language,
                          onItem: onItem,
                          onAdjust: canManage ? onAdjust : null,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: SizedBox(
                            height: math.min(
                              720,
                              math.max(128, items.length * 112).toDouble(),
                            ),
                            child: ListView.separated(
                              key: const ValueKey(
                                'inventory-items-mobile-list',
                              ),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return _InventoryCard(
                                  item: item,
                                  language: language,
                                  onTap: () => onItem(item),
                                );
                              },
                            ),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _WarehouseItemFilters extends StatelessWidget {
  const _WarehouseItemFilters({
    required this.workspace,
    this.search = '',
    required this.language,
    required this.status,
    required this.unit,
    required this.categoryId,
    required this.shownItems,
    required this.canManage,
    required this.onSearch,
    required this.onStatus,
    required this.onUnit,
    required this.onCategory,
    required this.onAdd,
    required this.onDownload,
    required this.onExport,
    required this.onCategories,
  });

  final YorksV1InventoryWorkspace workspace;
  final String search;
  final AppLanguage language;
  final _WarehouseItemStatus status;
  final String? unit;
  final String? categoryId;
  final int shownItems;
  final bool canManage;
  final ValueChanged<String> onSearch;
  final ValueChanged<_WarehouseItemStatus> onStatus;
  final ValueChanged<String?> onUnit;
  final ValueChanged<String?> onCategory;
  final VoidCallback onAdd;
  final VoidCallback onDownload;
  final VoidCallback onExport;
  final VoidCallback onCategories;

  @override
  Widget build(BuildContext context) {
    final units =
        (workspace.availableUnits.isNotEmpty
              ? workspace.availableUnits.toList()
              : workspace.items.map((item) => item.unit).toSet().toList())
          ..sort();
    final categories =
        workspace.categories.where((category) => category.isActive).toList()
          ..sort((a, b) => a.displayPath.compareTo(b.displayPath));
    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final controls = [
                  _WarehouseTextFilter(
                    value: search,
                    label: YorksV1InventoryStrings.searchWarehouse.active(
                      language,
                    ),
                    hint: YorksV1InventoryStrings.itemSearchHint.active(
                      language,
                    ),
                    onChanged: onSearch,
                  ),
                  _WarehouseDropdown<_WarehouseItemStatus>(
                    label: YorksV1InventoryStrings.status.active(language),
                    value: status,
                    onChanged: (value) {
                      if (value != null) onStatus(value);
                    },
                    items: [
                      (
                        _WarehouseItemStatus.all,
                        YorksV1InventoryStrings.allStatus.active(language),
                      ),
                      (
                        _WarehouseItemStatus.active,
                        YorksV1InventoryStrings.active.active(language),
                      ),
                      (
                        _WarehouseItemStatus.reserved,
                        YorksV1InventoryStrings.reserved.active(language),
                      ),
                      (
                        _WarehouseItemStatus.low,
                        YorksV1InventoryStrings.lowStock.active(language),
                      ),
                      (
                        _WarehouseItemStatus.out,
                        YorksV1InventoryStrings.outOfStock.active(language),
                      ),
                      (
                        _WarehouseItemStatus.inactive,
                        YorksV1InventoryStrings.inactive.active(language),
                      ),
                    ],
                  ),
                  _WarehouseDropdown<String?>(
                    label: YorksV1LogisticsStrings.unit.active(language),
                    value: unit,
                    onChanged: onUnit,
                    items: [
                      (null, YorksV1InventoryStrings.allUnits.active(language)),
                      for (final value in units) (value, value),
                    ],
                  ),
                  _WarehouseDropdown<String?>(
                    label: YorksV1InventoryStrings.category.active(language),
                    value: categoryId,
                    onChanged: onCategory,
                    items: [
                      (
                        null,
                        YorksV1InventoryStrings.allCategories.active(language),
                      ),
                      for (final category in categories)
                        (category.id, category.displayPath),
                    ],
                  ),
                ];
                if (!wide) {
                  return Column(
                    children: [
                      controls[0],
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          YorksV1InventoryStrings.filters.active(language),
                        ),
                        children: [
                          for (final control in controls.skip(1))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: control,
                            ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 3, child: controls[0]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: controls[1]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: controls[2]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: controls[3]),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final actions = [
                  if (canManage)
                    PopupMenuButton<String>(
                      tooltip: YorksV1InventoryStrings.manageCategories.active(
                        language,
                      ),
                      onSelected: (_) => onCategories(),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'categories',
                          child: Text(
                            YorksV1InventoryStrings.manageCategories.active(
                              language,
                            ),
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  OutlinedButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      YorksV1InventoryStrings.exportMatchingStock.active(
                        language,
                      ),
                    ),
                  ),
                ];
                if (constraints.maxWidth >= 1450) {
                  return Row(
                    children: [
                      Text(
                        '$shownItems ${YorksV1InventoryStrings.warehouseItems.active(language)}',
                        style: AppTypography.labelLarge,
                      ),
                      const Spacer(),
                      for (var index = 0; index < actions.length; index++) ...[
                        actions[index],
                        if (index < actions.length - 1)
                          const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$shownItems ${YorksV1InventoryStrings.warehouseItems.active(language)}',
                      style: AppTypography.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: actions,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseTextFilter extends StatefulWidget {
  const _WarehouseTextFilter({
    required this.label,
    required this.hint,
    required this.onChanged,
    this.value = '',
  });
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_WarehouseTextFilter> createState() => _WarehouseTextFilterState();
}

class _WarehouseTextFilterState extends State<_WarehouseTextFilter> {
  late final _controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _WarehouseTextFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label, style: AppTypography.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
        ),
      ),
    ],
  );
}

class _WarehouseDropdown<T> extends StatelessWidget {
  const _WarehouseDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final item in items)
            DropdownMenuItem(value: item.$1, child: Text(item.$2)),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

class _InventoryTable extends StatefulWidget {
  const _InventoryTable({
    required this.items,
    required this.language,
    required this.onItem,
    this.onAdjust,
  });
  final List<YorksV1LogisticsInventoryItem> items;
  final AppLanguage language;
  final ValueChanged<YorksV1LogisticsInventoryItem> onItem;
  final ValueChanged<YorksV1LogisticsInventoryItem>? onAdjust;

  @override
  State<_InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<_InventoryTable> {
  final _horizontal = ScrollController();
  List<YorksV1LogisticsInventoryItem> get items => widget.items;
  AppLanguage get language => widget.language;
  ValueChanged<YorksV1LogisticsInventoryItem> get onItem => widget.onItem;
  ValueChanged<YorksV1LogisticsInventoryItem>? get onAdjust => widget.onAdjust;
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: _horizontal,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        // Keep the controlled desktop grid readable instead of squeezing
        // headers and values into the viewport. Narrow desktops can scroll the
        // full table; compact layouts use the purpose-built item cards above.
        width: math.max(1600.0, constraints.maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InventoryTableRow(language: language, horizontal: _horizontal),
            const Divider(height: 1),
            SizedBox(
              height: math.min(640, math.max(82, items.length * 83).toDouble()),
              child: ListView.separated(
                key: const ValueKey('inventory-items-desktop-list'),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _InventoryTableRow(
                    language: language,
                    horizontal: _horizontal,
                    item: item,
                    onTap: () => onItem(item),
                    onAdjust: onAdjust == null ? null : () => onAdjust!(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InventoryTableRow extends StatelessWidget {
  const _InventoryTableRow({
    required this.language,
    required this.horizontal,
    this.item,
    this.onTap,
    this.onAdjust,
  });
  final AppLanguage language;
  final ScrollController horizontal;
  final YorksV1LogisticsInventoryItem? item;
  final VoidCallback? onTap;
  final VoidCallback? onAdjust;

  @override
  Widget build(BuildContext context) {
    final header = item == null;
    Widget cell({
      required Widget child,
      required int flex,
      bool last = false,
      Alignment alignment = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Container(
        constraints: BoxConstraints(minHeight: header ? 48 : 82),
        alignment: alignment,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(right: BorderSide(color: AppColors.line)),
        ),
        child: child,
      ),
    );
    Widget label(String text, {TextAlign? align}) => Text(
      text,
      maxLines: header ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: header
          ? AppTypography.labelMedium.copyWith(letterSpacing: .55)
          : AppTypography.bodyMedium,
    );
    final current = item;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: header
          ? [
              cell(
                flex: 24,
                child: label(YorksV1InventoryStrings.item.active(language)),
              ),
              cell(
                flex: 12,
                child: label(YorksV1InventoryStrings.category.active(language)),
              ),
              cell(
                flex: 6,
                child: label(
                  YorksV1InventoryStrings.locationColumn.active(language),
                ),
              ),
              cell(
                flex: 5,
                child: label(YorksV1LogisticsStrings.unit.active(language)),
              ),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: label(
                  YorksV1LogisticsStrings.onHand.active(language),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: label(
                  YorksV1LogisticsStrings.reserved.active(language),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: label(
                  YorksV1LogisticsStrings.available.active(language),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 7,
                alignment: Alignment.centerRight,
                child: label(
                  YorksV1InventoryStrings.minimumStock.active(language),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 8,
                child: label(YorksV1InventoryStrings.status.active(language)),
              ),
              cell(flex: 20, last: true, child: const SizedBox()),
            ]
          : [
              cell(
                flex: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${current!.itemCode ?? '—'} · ${current.description}',
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      [
                            current.sizeText,
                            current.modelReference,
                            current.brandOrigin,
                          ]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              cell(
                flex: 12,
                child: _TableCategoryPill(
                  text:
                      current.categoryPath ??
                      current.categoryName ??
                      YorksV1InventoryStrings.uncategorized.active(language),
                ),
              ),
              cell(flex: 6, child: label(current.locationBin ?? '—')),
              cell(flex: 5, child: label(current.unit)),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: label(
                  _quantity(current.onHandQuantity),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: label(
                  _quantity(current.reservedQuantity),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 6,
                alignment: Alignment.centerRight,
                child: Text(
                  _quantity(current.availableQuantity),
                  textAlign: TextAlign.end,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              cell(
                flex: 7,
                alignment: Alignment.centerRight,
                child: label(
                  current.minimumStock == null
                      ? '—'
                      : _quantity(current.minimumStock!),
                  align: TextAlign.end,
                ),
              ),
              cell(
                flex: 8,
                child: _StockBadge(item: current, language: language),
              ),
              cell(
                flex: 20,
                last: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onAdjust != null) ...[
                      OutlinedButton.icon(
                        onPressed: onAdjust,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSpacing.minTapTarget),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          YorksV1InventoryStrings.stock.active(language),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    OutlinedButton.icon(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSpacing.minTapTarget),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(
                        YorksV1InventoryStrings.view.active(language),
                      ),
                    ),
                  ],
                ),
              ),
            ],
    );
    final identity = (content.children.first as Expanded).child;
    final scrollable = Row(
      children: [
        const Expanded(flex: 24, child: SizedBox()),
        ...content.children.skip(1),
      ],
    );
    final frozen = LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: horizontal,
        builder: (context, _) => Stack(
          children: [
            scrollable,
            PositionedDirectional(
              start: horizontal.hasClients ? horizontal.offset : 0,
              top: 0,
              bottom: 0,
              width: constraints.maxWidth * .24,
              child: ColoredBox(
                color: header
                    ? AppColors.surfaceContainerLow
                    : AppColors.surface,
                child: identity,
              ),
            ),
          ],
        ),
      ),
    );
    return header
        ? ColoredBox(color: AppColors.surfaceContainerLow, child: frozen)
        : InkWell(onTap: onTap, child: frozen);
  }
}

class _TableCategoryPill extends StatelessWidget {
  const _TableCategoryPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      border: Border.all(color: AppColors.blue.withValues(alpha: .24)),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelMedium.copyWith(color: AppColors.navy),
    ),
  );
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.language,
    required this.onTap,
  });
  final YorksV1LogisticsInventoryItem item;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium,
                  ),
                ),
                _StockBadge(item: item, language: language),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${item.itemCode ?? '—'} · ${item.categoryPath ?? item.categoryName ?? YorksV1InventoryStrings.uncategorized.active(language)}',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _Fact(
                    label: YorksV1LogisticsStrings.onHand.active(language),
                    value: '${_quantity(item.onHandQuantity)} ${item.unit}',
                  ),
                ),
                Expanded(
                  child: _Fact(
                    label: YorksV1LogisticsStrings.reserved.active(language),
                    value: '${_quantity(item.reservedQuantity)} ${item.unit}',
                  ),
                ),
                Expanded(
                  child: _Fact(
                    label: YorksV1LogisticsStrings.available.active(language),
                    value: '${_quantity(item.availableQuantity)} ${item.unit}',
                  ),
                ),
              ],
            ),
            if (item.locationBin != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      item.locationBin!,
                      style: AppTypography.bodySmall,
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

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.item, required this.language});
  final YorksV1LogisticsInventoryItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (label, color, surface) = item.isOutOfStock
        ? (
            YorksV1InventoryStrings.outOfStock.active(language),
            AppColors.error,
            AppColors.errorContainer,
          )
        : item.isLowStock
        ? (
            YorksV1InventoryStrings.lowStock.active(language),
            AppColors.warning,
            AppColors.warningContainer,
          )
        : item.minimumStock == null
        ? (
            YorksV1InventoryStrings.noMinimum.active(language),
            AppColors.muted,
            AppColors.surface,
          )
        : (
            YorksV1InventoryStrings.healthy.active(language),
            AppColors.success,
            AppColors.successContainer,
          );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _PagedInventoryHistory extends ConsumerStatefulWidget {
  const _PagedInventoryHistory({required this.language, this.itemId});
  final AppLanguage language;
  final String? itemId;
  @override
  ConsumerState<_PagedInventoryHistory> createState() =>
      _PagedInventoryHistoryState();
}

class _PagedInventoryHistoryState
    extends ConsumerState<_PagedInventoryHistory> {
  late YorksV1InventoryHistoryQuery _query = YorksV1InventoryHistoryQuery(
    itemId: widget.itemId,
  );
  final _previous = <YorksV1InventoryHistoryQuery>[];
  Timer? _debounce;
  bool _exporting = false;
  DateTimeRange? _dates;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _filter({String? search, String? kind}) => setState(() {
    _previous.clear();
    _query = YorksV1InventoryHistoryQuery(
      itemId: widget.itemId,
      search: search ?? _query.search,
      kind: kind ?? _query.kind,
      fromAt: _dates?.start,
      untilAt: _dates == null
          ? null
          : DateTime(_dates!.end.year, _dates!.end.month, _dates!.end.day + 1),
    );
  });

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(yorksV1InventoryHistoryProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1InventoryStrings.stockMovements.active(widget.language),
          style: AppTypography.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        _MovementsFilterPanel(
          language: widget.language,
          filter: _WarehouseMovementType.values.byName(_query.kind),
          count: data.asData?.value.items.length ?? 0,
          onFilter: (value) => _filter(kind: value.name),
          onSearch: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) _filter(search: value.trim());
            });
          },
          onExport: _exporting ? () {} : _export,
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              onPressed: _exporting ? null : () => _export(print: true),
              icon: const Icon(Icons.print_outlined),
              label: Text(
                YorksV1InventoryStrings.printMovements.active(widget.language),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                _dates == null
                    ? YorksV1InventoryStrings.dateRange.active(widget.language)
                    : '${DateFormat.yMMMd().format(_dates!.start)} – ${DateFormat.yMMMd().format(_dates!.end)}',
              ),
              onPressed: () async {
                final dates = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: _dates,
                );
                if (!mounted || dates == null) return;
                _dates = dates;
                _filter();
              },
            ),
            if (_dates != null)
              TextButton(
                onPressed: () {
                  _dates = null;
                  _filter();
                },
                child: Text(
                  YorksV1InventoryStrings.allDates.active(widget.language),
                ),
              ),
          ],
        ),
        if (_exporting) const LinearProgressIndicator(),
        const SizedBox(height: AppSpacing.md),
        data.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _StateMessage(
            icon: Icons.cloud_off_outlined,
            message: YorksV1InventoryStrings.loadFailed.active(widget.language),
            action: YorksV1LogisticsStrings.refresh.active(widget.language),
            onAction: () =>
                ref.invalidate(yorksV1InventoryHistoryProvider(_query)),
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.items.isEmpty)
                _InlineEmpty(
                  message: YorksV1InventoryStrings.noMovements.active(
                    widget.language,
                  ),
                ),
              for (final movement in page.items)
                _MovementTile(movement: movement),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    onPressed: _previous.isEmpty
                        ? null
                        : () => setState(() => _query = _previous.removeLast()),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(
                      YorksV1InventoryStrings.newer.active(widget.language),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: !page.hasMore || page.items.isEmpty
                        ? null
                        : () => setState(() {
                            _previous.add(_query);
                            _query = _query.after(page.items.last);
                          }),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      YorksV1InventoryStrings.older.active(widget.language),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _export({bool print = false}) async {
    if (_exporting) return;
    final repository = ref.read(yorksV1LogisticsRepositoryProvider);
    final files = ref.read(yorksV1InventoryWorkbookFileServiceProvider);
    if (repository is! YorksV1InventoryHistoryRepository ||
        files is! YorksV1InventoryMovementFileService) {
      return;
    }
    var query = YorksV1InventoryHistoryQuery(
      itemId: widget.itemId,
      search: _query.search,
      kind: _query.kind,
      fromAt: _query.fromAt,
      untilAt: _query.untilAt,
      limit: 500,
    );
    final exportUser = ref.read(yorksV1AuthUserIdProvider);
    final exportRole = ref.read(yorksV1CurrentRoleProvider);
    bool sameAuthority() =>
        mounted &&
        ref.read(yorksV1AuthUserIdProvider) == exportUser &&
        ref.read(yorksV1CurrentRoleProvider) == exportRole;
    setState(() => _exporting = true);
    try {
      final rows = <YorksV1InventoryMovement>[];
      final seen = <String>{};
      while (true) {
        final page = await (repository as YorksV1InventoryHistoryRepository)
            .getInventoryHistory(query);
        if (!sameAuthority()) return;
        for (final row in page.items) {
          if (!seen.add(row.id)) {
            throw StateError('History cursor did not advance');
          }
          rows.add(row);
        }
        if (!page.hasMore) break;
        if (page.items.isEmpty) {
          throw StateError('Invalid history page');
        }
        query = query.after(page.items.last);
      }
      final saved = print
          ? await (files as YorksV1InventoryMovementPrintService)
                .printMovementRegister(rows, canPrint: sameAuthority)
          : await (files as YorksV1InventoryMovementFileService)
                .saveMovementRegister(rows);
      if (mounted && saved) {
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.exportRegisterComplete.active(
            widget.language,
          ),
          tone: YorksAppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.exportRegisterFailed.active(
            widget.language,
          ),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _MovementsFilterPanel extends StatelessWidget {
  const _MovementsFilterPanel({
    required this.language,
    required this.filter,
    required this.count,
    required this.onFilter,
    required this.onSearch,
    required this.onExport,
  });
  final AppLanguage language;
  final _WarehouseMovementType filter;
  final int count;
  final ValueChanged<_WarehouseMovementType> onFilter;
  final ValueChanged<String> onSearch;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final search = _WarehouseTextFilter(
                label: YorksV1InventoryStrings.searchMovements.active(language),
                hint: YorksV1InventoryStrings.movementSearchHint.active(
                  language,
                ),
                onChanged: onSearch,
              );
              final types = _WarehouseDropdown<_WarehouseMovementType>(
                label: YorksV1InventoryStrings.movementType.active(language),
                value: filter,
                onChanged: (value) {
                  if (value != null) onFilter(value);
                },
                items: [
                  (
                    _WarehouseMovementType.all,
                    YorksV1InventoryStrings.allMovements.active(language),
                  ),
                  (
                    _WarehouseMovementType.stockIn,
                    YorksV1InventoryStrings.stockIn.active(language),
                  ),
                  (
                    _WarehouseMovementType.stockOut,
                    YorksV1InventoryStrings.stockOut.active(language),
                  ),
                  (
                    _WarehouseMovementType.dispatch,
                    YorksV1InventoryStrings.warehouseDispatch.active(language),
                  ),
                  (
                    _WarehouseMovementType.materialReturn,
                    YorksV1InventoryStrings.materialReturn.active(language),
                  ),
                ],
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  children: [
                    search,
                    const SizedBox(height: AppSpacing.md),
                    types,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: types),
                ],
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
                  '$count ${YorksV1InventoryStrings.movements.active(language)}',
                  style: AppTypography.labelLarge,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(
                  YorksV1InventoryStrings.exportMovements.active(language),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});
  final YorksV1InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final negative = movement.quantityDelta.startsWith('-');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: negative
                ? AppColors.errorContainer
                : AppColors.successContainer,
            child: Icon(
              negative ? Icons.north_east_rounded : Icons.south_west_rounded,
              size: 18,
              color: negative ? AppColors.error : AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.itemDescription ?? movement.reason,
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${movement.reason} · ${movement.actorDisplayName}',
                  style: AppTypography.bodySmall,
                ),
                Text(
                  _dateTime(movement.createdAt),
                  style: AppTypography.labelSmall,
                ),
              ],
            ),
          ),
          Text(
            '${negative ? '' : '+'}${_quantity(movement.quantityDelta)} ${movement.unit ?? ''}',
            style: AppTypography.titleSmall.copyWith(
              color: negative ? AppColors.error : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationsTab extends StatelessWidget {
  const _ReservationsTab({required this.reservations, required this.language});
  final List<YorksV1InventoryReservation> reservations;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _TrustCard(language: language),
      const SizedBox(height: AppSpacing.lg),
      _WarehousePanel(
        title: YorksV1InventoryStrings.activeReservations.active(language),
        subtitle: YorksV1InventoryStrings.reservationsHelp.active(language),
        trailing: _CountPill(
          '${reservations.length} ${YorksV1InventoryStrings.active.active(language)}',
          tone: AppColors.purple,
        ),
        child: reservations.isEmpty
            ? _StateMessage(
                icon: Icons.lock_clock_outlined,
                message: YorksV1InventoryStrings.noReservations.active(
                  language,
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint
                    ? _ReservationsTable(
                        reservations: reservations,
                        language: language,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            for (final reservation in reservations)
                              _ReservationCard(
                                reservation: reservation,
                                language: language,
                              ),
                          ],
                        ),
                      ),
              ),
      ),
    ],
  );
}

class _ReservationsTable extends StatelessWidget {
  const _ReservationsTable({
    required this.reservations,
    required this.language,
  });
  final List<YorksV1InventoryReservation> reservations;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: 980,
      child: Column(
        children: [
          _ReservationTableRow(language: language),
          const Divider(height: 1),
          for (final reservation in reservations) ...[
            _ReservationTableRow(language: language, reservation: reservation),
            if (reservation != reservations.last) const Divider(height: 1),
          ],
        ],
      ),
    ),
  );
}

class _ReservationTableRow extends StatelessWidget {
  const _ReservationTableRow({required this.language, this.reservation});
  final AppLanguage language;
  final YorksV1InventoryReservation? reservation;

  @override
  Widget build(BuildContext context) {
    final header = reservation == null;
    Widget cell(Widget child, int flex) => Expanded(flex: flex, child: child);
    Widget heading(String value) =>
        Text(value, style: AppTypography.labelMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: header
            ? [
                cell(
                  heading(
                    YorksV1InventoryStrings.materialRequest.active(language),
                  ),
                  3,
                ),
                cell(
                  heading(
                    YorksV1InventoryStrings.projectScope.active(language),
                  ),
                  4,
                ),
                cell(
                  heading(
                    YorksV1InventoryStrings.inventoryItem.active(language),
                  ),
                  5,
                ),
                cell(
                  heading(YorksV1InventoryStrings.reserved.active(language)),
                  2,
                ),
                cell(
                  heading(YorksV1LogisticsStrings.state.active(language)),
                  2,
                ),
              ]
            : [
                cell(
                  _ReservationTwoLine(
                    title: reservation!.requestNumber,
                    subtitle: YorksV1InventoryStrings.active.active(language),
                  ),
                  3,
                ),
                cell(
                  _ReservationTwoLine(
                    title: reservation!.projectName,
                    subtitle: reservation!.scopeName,
                  ),
                  4,
                ),
                cell(
                  Text(
                    '${reservation!.itemCode ?? '—'} · ${reservation!.itemDescription}',
                    style: AppTypography.titleSmall,
                  ),
                  5,
                ),
                cell(
                  Text(
                    '${_quantity(reservation!.remainingQuantity)} ${reservation!.unit}',
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyMedium,
                  ),
                  2,
                ),
                cell(_CountPill(reservation!.state, tone: AppColors.purple), 2),
              ],
      ),
    );
  }
}

class _ReservationTwoLine extends StatelessWidget {
  const _ReservationTwoLine({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTypography.titleSmall),
      const SizedBox(height: AppSpacing.xxs),
      Text(subtitle, style: AppTypography.bodySmall),
    ],
  );
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation, required this.language});
  final YorksV1InventoryReservation reservation;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reservation.itemDescription,
                  style: AppTypography.titleMedium,
                ),
              ),
              _CountPill(
                '${_quantity(reservation.remainingQuantity)} ${reservation.unit}',
                tone: AppColors.purple,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(reservation.requestNumber, style: AppTypography.labelLarge),
          Text(
            '${reservation.projectName} · ${reservation.scopeName}',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _InventoryActionChooser extends ConsumerWidget {
  const _InventoryActionChooser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final compact = MediaQuery.sizeOf(context).width <= 720;
    final body = SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DialogHeader(
            title: YorksV1InventoryStrings.addReceive.active(language),
            subtitle: YorksV1InventoryStrings.chooseControlledAction.active(
              language,
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                _ActionChoiceTile(
                  icon: Icons.add_rounded,
                  title: YorksV1InventoryStrings.createInventoryItem.active(
                    language,
                  ),
                  subtitle: YorksV1InventoryStrings.createInventoryItemHelp
                      .active(language),
                  onTap: () =>
                      Navigator.of(context).pop(_InventoryAction.createItem),
                ),
                const SizedBox(height: AppSpacing.md),
                _ActionChoiceTile(
                  icon: Icons.history_rounded,
                  title: YorksV1InventoryStrings.adjustExistingStock.active(
                    language,
                  ),
                  subtitle: YorksV1InventoryStrings.adjustExistingStockHelp
                      .active(language),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_InventoryAction.adjustExisting),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.blueContainerStrong),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          YorksV1InventoryStrings.movementTrust.active(
                            language,
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (compact) return Dialog.fullscreen(child: body);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(width: 620, child: body),
    );
  }
}

class _ActionChoiceTile extends StatelessWidget {
  const _ActionChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, color: AppColors.blue),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: AppTypography.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ExistingStockPicker extends ConsumerStatefulWidget {
  const _ExistingStockPicker({required this.items});

  final List<YorksV1LogisticsInventoryItem> items;

  @override
  ConsumerState<_ExistingStockPicker> createState() =>
      _ExistingStockPickerState();
}

class _ExistingStockPickerState extends ConsumerState<_ExistingStockPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final compact = MediaQuery.sizeOf(context).width <= 720;
    final normalized = _query.trim().toLowerCase();
    final items = widget.items
        .where(
          (item) =>
              item.isActive &&
              (normalized.isEmpty ||
                  item.description.toLowerCase().contains(normalized) ||
                  (item.itemCode ?? '').toLowerCase().contains(normalized) ||
                  (item.categoryPath ?? item.categoryName ?? '')
                      .toLowerCase()
                      .contains(normalized)),
        )
        .toList(growable: false);
    final body = SafeArea(
      child: Column(
        children: [
          _DialogHeader(
            title: YorksV1InventoryStrings.selectExistingItem.active(language),
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: YorksV1InventoryStrings.searchInventoryItem.active(
                  language,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = items[index];
                return _Surface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    minTileHeight: 64,
                    title: Text(
                      item.description,
                      style: AppTypography.titleSmall,
                    ),
                    subtitle: Text(
                      '${item.itemCode ?? '—'} · ${item.categoryPath ?? item.categoryName ?? YorksV1InventoryStrings.uncategorized.active(language)} · ${_quantity(item.availableQuantity)} ${item.unit} ${YorksV1InventoryStrings.available.active(language)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (compact) return Dialog.fullscreen(child: body);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(width: 680, height: 620, child: body),
    );
  }
}

class _CreateInventoryItemDialog extends ConsumerStatefulWidget {
  const _CreateInventoryItemDialog({
    required this.workspace,
    required this.onCommitted,
  });

  final YorksV1InventoryWorkspace workspace;
  final VoidCallback onCommitted;

  @override
  ConsumerState<_CreateInventoryItemDialog> createState() =>
      _CreateInventoryItemDialogState();
}

class _CreateInventoryItemDialogState
    extends ConsumerState<_CreateInventoryItemDialog> {
  final _code = TextEditingController();
  final _description = TextEditingController();
  final _brand = TextEditingController();
  final _size = TextEditingController();
  final _model = TextEditingController();
  final _location = TextEditingController(text: 'Main Warehouse');
  final _minimum = TextEditingController();
  final _notes = TextEditingController();
  final _opening = TextEditingController(text: '0');
  final _openingReference = TextEditingController();
  final _reason = TextEditingController();
  String _unit = '';
  String? _categoryId;
  String? _newCategoryName;
  String? _newCategoryParentId;
  String? _sourceCategoryText;
  bool _saving = false;
  YorksV1InventoryStockCommand get _command =>
      ref.read(yorksV1InventoryStockCommandProvider);

  @override
  void dispose() {
    for (final controller in [
      _code,
      _description,
      _brand,
      _size,
      _model,
      _location,
      _minimum,
      _notes,
      _opening,
      _openingReference,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final unitsAsync = ref.watch(yorksV1ConfigurationUnitCodesProvider);
    final controlledUnits = yorksV1LoadedControlledUnits(unitsAsync);
    final unitReady = controlledUnits.contains(_unit.trim());
    final compact = MediaQuery.sizeOf(context).width <= 720;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            YorksV1InventoryStrings.itemIdentity.active(language),
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ResponsiveFields(
            children: [
              _LabeledField(
                controller: _code,
                label: YorksV1InventoryStrings.itemCodeOptional.active(
                  language,
                ),
                hint: YorksV1InventoryStrings.autoGenerated.active(language),
              ),
              YorksV1ControlledUnitDropdown(
                fieldKey: const ValueKey('create-inventory-unit'),
                label: YorksV1LogisticsStrings.unit.active(language),
                value: _unit,
                enabled: !_saving,
                showDependencyStatus: true,
                onChanged: (value) => setState(() => _unit = value),
              ),
              _LabeledField(
                controller: _description,
                label: YorksV1LogisticsStrings.itemDescription.active(language),
                hint: YorksV1InventoryStrings.materialEquipmentDescription
                    .active(language),
                fullWidth: true,
              ),
              _LabeledField(
                controller: _brand,
                label: YorksV1LogisticsStrings.brandOrigin.active(language),
              ),
              _CategoryAutocomplete(
                categories: widget.workspace.categories,
                onSelection: (categoryId, newName, parentId, sourceText) =>
                    setState(() {
                      _categoryId = categoryId;
                      _newCategoryName = newName;
                      _newCategoryParentId = parentId;
                      _sourceCategoryText = sourceText;
                    }),
              ),
              _LabeledField(
                controller: _size,
                label: YorksV1InventoryStrings.size.active(language),
              ),
              _LabeledField(
                controller: _model,
                label: YorksV1InventoryStrings.modelReference.active(language),
              ),
              _LabeledField(
                controller: _location,
                label: YorksV1InventoryStrings.location.active(language),
              ),
              _LabeledField(
                controller: _minimum,
                label: YorksV1InventoryStrings.minimumStock.active(language),
                numeric: true,
              ),
              _LabeledField(
                controller: _notes,
                label: YorksV1InventoryStrings.notes.active(language),
                lines: 3,
                fullWidth: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            YorksV1InventoryStrings.openingBalance.active(language),
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ResponsiveFields(
            children: [
              _LabeledField(
                controller: _opening,
                label: YorksV1InventoryStrings.openingQuantity.active(language),
                numeric: true,
              ),
              _LabeledField(
                controller: _openingReference,
                label: YorksV1InventoryStrings.openingReference.active(
                  language,
                ),
              ),
              _LabeledField(
                controller: _reason,
                label: YorksV1LogisticsStrings.reason.active(language),
                fullWidth: true,
              ),
            ],
          ),
        ],
      ),
    );
    final body = PopScope(
      canPop: !_saving && !_command.unresolved,
      child: SafeArea(
        child: Column(
          children: [
            _DialogHeader(
              title: YorksV1InventoryStrings.createInventoryItem.active(
                language,
              ),
              subtitle: YorksV1InventoryStrings.createInventoryItemHelp.active(
                language,
              ),
              onClose: (_saving || _command.unresolved)
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            if (_command.unresolved && !_saving)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  YorksV1InventoryStrings.uncertainSave.active(language),
                  style: AppTypography.bodyMedium,
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _saving || _command.unresolved,
                child: ExcludeFocus(
                  excluding: _saving || _command.unresolved,
                  child: content,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _saving || !unitReady ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            YorksV1InventoryStrings.createInventoryItem.active(
                              language,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (compact) return Dialog.fullscreen(child: body);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(
        width: 1160,
        height: math.min(780, MediaQuery.sizeOf(context).height - 48),
        child: body,
      ),
    );
  }

  Future<void> _save() async {
    final controlledUnits = yorksV1LoadedControlledUnits(
      ref.read(yorksV1ConfigurationUnitCodesProvider),
    );
    final opening = double.tryParse(_opening.text.trim());
    if (_description.text.trim().isEmpty ||
        !controlledUnits.contains(_unit.trim()) ||
        (_categoryId == null && _newCategoryName == null) ||
        opening == null ||
        !opening.isFinite ||
        opening < 0 ||
        (opening > 0 && _reason.text.trim().isEmpty)) {
      _failure();
      return;
    }
    setState(() => _saving = true);
    try {
      await _command.save(
        ref.read(yorksV1LogisticsRepositoryProvider),
        () => YorksV1InventoryAdjustmentInput(
          description: _description.text,
          itemCode: _code.text,
          brandOrigin: _brand.text,
          sizeText: _size.text,
          modelReference: _model.text,
          unit: _unit,
          categoryId: _categoryId,
          newCategoryName: _newCategoryName,
          newCategoryParentId: _newCategoryParentId,
          sourceCategoryText: _sourceCategoryText,
          minimumStock: _minimum.text,
          locationBin: _location.text,
          notes: _notes.text,
          quantityDelta: _opening.text,
          reference: _openingReference.text,
          reason: _reason.text,
          idempotencyKey: const Uuid().v4(),
        ),
      );
      if (!mounted) return;
      widget.onCommitted();
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _failure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _failure() {
    final language = ref.read(languageProvider);
    YorksAppToast.show(
      context,
      title:
          (_command.unresolved
                  ? YorksV1InventoryStrings.uncertainSave
                  : YorksV1InventoryStrings.savingFailed)
              .active(language),
      tone: YorksAppToastTone.error,
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final child in children)
            SizedBox(
              width:
                  (child is _LabeledField && child.fullWidth) ||
                      child is _LabeledCategoryDropdown
                  ? constraints.maxWidth
                  : width,
              child: child,
            ),
        ],
      );
    },
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.controller,
    required this.label,
    this.hint,
    this.lines = 1,
    this.numeric = false,
    this.fullWidth = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int lines;
  final bool numeric;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class _LabeledCategoryDropdown extends StatelessWidget {
  const _LabeledCategoryDropdown({
    required this.label,
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<YorksV1InventoryCategory> categories;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          for (final category in categories)
            DropdownMenuItem(
              value: category.id,
              child: Text(
                category.displayPath,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

class _CategoryAutocomplete extends ConsumerStatefulWidget {
  const _CategoryAutocomplete({
    required this.categories,
    required this.onSelection,
  });

  final List<YorksV1InventoryCategory> categories;
  final void Function(
    String? categoryId,
    String? newName,
    String? parentId,
    String? sourceText,
  )
  onSelection;

  @override
  ConsumerState<_CategoryAutocomplete> createState() =>
      _CategoryAutocompleteState();
}

class _CategoryAutocompleteState extends ConsumerState<_CategoryAutocomplete> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<YorksV1InventoryCategory> _matches = const [];
  String? _selectedId;
  bool _create = false;
  String? _parentId;
  int _request = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _matches = widget.categories
        .where((item) => item.isActive)
        .take(8)
        .toList();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final showResults = _focus.hasFocus && _controller.text.trim().isNotEmpty;
    final parents = widget.categories
        .where(
          (category) => category.parentCategoryId == null && category.isActive,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          YorksV1InventoryStrings.category.active(language),
          style: AppTypography.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: YorksV1InventoryStrings.typeCategory.active(language),
            suffixIcon: _selectedId == null
                ? const Icon(Icons.search_rounded)
                : const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (showResults && !_create)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Material(
              color: AppColors.surfaceContainerLowest,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                side: const BorderSide(color: AppColors.line),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 245),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  children: [
                    for (final category in _matches)
                      ListTile(
                        minTileHeight: AppSpacing.minTapTarget,
                        leading: const Icon(
                          Icons.grid_view_rounded,
                          color: AppColors.blue,
                        ),
                        title: Text(
                          category.displayPath,
                          style: AppTypography.titleSmall,
                        ),
                        subtitle: Text(
                          '${category.itemCount} ${YorksV1InventoryStrings.warehouseItems.active(language)}${category.aliases.isEmpty ? '' : ' · ${YorksV1InventoryStrings.alias.active(language)} ${category.aliases.first}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _select(category),
                      ),
                    ListTile(
                      minTileHeight: AppSpacing.minTapTarget,
                      tileColor: AppColors.blueContainer,
                      leading: const Icon(
                        Icons.add_rounded,
                        color: AppColors.blue,
                      ),
                      title: Text(
                        '${YorksV1InventoryStrings.createCategoryNamed.active(language)} “${yorksV1InventoryCategoryDisplayName(_controller.text)}”',
                        style: AppTypography.titleSmall,
                      ),
                      subtitle: Text(
                        YorksV1InventoryStrings.newCategory.active(language),
                      ),
                      onTap: _chooseCreate,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_create) ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            initialValue: _parentId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: YorksV1InventoryStrings.optionalParent.active(
                language,
              ),
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('—')),
              for (final parent in parents)
                DropdownMenuItem(value: parent.id, child: Text(parent.name)),
            ],
            onChanged: (value) {
              setState(() => _parentId = value);
              widget.onSelection(
                null,
                yorksV1InventoryCategoryDisplayName(_controller.text),
                value,
                _controller.text,
              );
            },
          ),
        ],
      ],
    );
  }

  void _select(YorksV1InventoryCategory category) {
    final sourceText = _controller.text.trim();
    setState(() {
      _selectedId = category.id;
      _create = false;
      _controller.text = category.displayPath;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    widget.onSelection(category.id, null, null, sourceText);
    _focus.unfocus();
  }

  void _chooseCreate() {
    final name = yorksV1InventoryCategoryDisplayName(_controller.text);
    setState(() {
      _selectedId = null;
      _create = true;
    });
    widget.onSelection(null, name, _parentId, _controller.text);
    _focus.unfocus();
  }

  void _search(String value) {
    final query = value.trim().toLowerCase();
    final request = ++_request;
    final local = widget.categories
        .where((category) {
          final haystack = [
            category.displayPath,
            ...category.aliases,
          ].join(' ').toLowerCase();
          return category.isActive && haystack.contains(query);
        })
        .take(8)
        .toList(growable: false);
    setState(() {
      _selectedId = null;
      _create = false;
      _matches = local;
    });
    widget.onSelection(null, null, null, null);
    _searchDebounce?.cancel();
    if (query.isEmpty) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => _loadRemoteSuggestions(value, request),
    );
  }

  Future<void> _loadRemoteSuggestions(String value, int request) async {
    try {
      final remote = await ref.read(
        yorksV1InventoryCategorySuggestionsProvider(value).future,
      );
      if (!mounted || request != _request || remote.isEmpty) return;
      final byId = {
        for (final category in widget.categories) category.id: category,
      };
      final resolved = [
        for (final suggestion in remote) ?byId[suggestion.categoryId],
      ];
      if (resolved.isNotEmpty) setState(() => _matches = resolved);
    } catch (_) {
      // The authorized local projection remains usable if suggestion ranking
      // is temporarily unavailable. Creation still commits through the RPC.
    }
  }
}

class _InventoryAdjustmentDialog extends ConsumerStatefulWidget {
  const _InventoryAdjustmentDialog({
    required this.workspace,
    required this.onCommitted,
    this.inventoryItem,
  });
  final YorksV1InventoryWorkspace workspace;
  final VoidCallback onCommitted;
  final YorksV1LogisticsInventoryItem? inventoryItem;

  @override
  ConsumerState<_InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState
    extends ConsumerState<_InventoryAdjustmentDialog> {
  final _description = TextEditingController();
  final _itemCode = TextEditingController();
  final _brand = TextEditingController();
  final _minimum = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  String _unit = '';
  String? _categoryId;
  bool _newCategory = false;
  final _newCategoryName = TextEditingController();
  String _action = 'add';
  final _reference = TextEditingController();
  bool _saving = false;
  YorksV1InventoryStockCommand get _command =>
      ref.read(yorksV1InventoryStockCommandProvider);

  @override
  void dispose() {
    for (final controller in [
      _description,
      _itemCode,
      _brand,
      _minimum,
      _location,
      _notes,
      _quantity,
      _reason,
      _newCategoryName,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final unitsAsync = ref.watch(yorksV1ConfigurationUnitCodesProvider);
    final controlledUnits = yorksV1LoadedControlledUnits(unitsAsync);
    final unitReady =
        widget.inventoryItem != null || controlledUnits.contains(_unit.trim());
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.inventoryItem == null) ...[
            _Input(
              controller: _description,
              label: YorksV1LogisticsStrings.itemDescription.active(language),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Input(
                    controller: _itemCode,
                    label: YorksV1InventoryStrings.itemCode.active(language),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Input(
                    controller: _brand,
                    label: YorksV1LogisticsStrings.brandOrigin.active(language),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            YorksV1ControlledUnitDropdown(
              fieldKey: const ValueKey('receive-inventory-unit'),
              label: YorksV1LogisticsStrings.unit.active(language),
              value: _unit,
              enabled: !_saving,
              showDependencyStatus: true,
              onChanged: (value) => setState(() => _unit = value),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!_newCategory)
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1InventoryStrings.category.active(language),
                  border: const OutlineInputBorder(),
                ),
                items: widget.workspace.categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _categoryId = value),
              )
            else
              _Input(
                controller: _newCategoryName,
                label: YorksV1InventoryStrings.categoryName.active(language),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _newCategory,
              title: Text(
                YorksV1InventoryStrings.newCategory.active(language),
                style: AppTypography.bodyMedium,
              ),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _newCategory = value ?? false),
            ),
            Row(
              children: [
                Expanded(
                  child: _Input(
                    controller: _minimum,
                    label: YorksV1InventoryStrings.minimumStock.active(
                      language,
                    ),
                    numeric: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Input(
                    controller: _location,
                    label: YorksV1InventoryStrings.location.active(language),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Input(
              controller: _notes,
              label: YorksV1InventoryStrings.notes.active(language),
              lines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else ...[
            Text(
              widget.inventoryItem!.description,
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'add',
                  label: Text(
                    YorksV1InventoryStrings.addStock.active(language),
                  ),
                  icon: const Icon(Icons.add_rounded),
                ),
                ButtonSegment(
                  value: 'remove',
                  label: Text(
                    YorksV1InventoryStrings.removeStock.active(language),
                  ),
                  icon: const Icon(Icons.remove_rounded),
                ),
                ButtonSegment(
                  value: 'correction',
                  label: Text(
                    YorksV1InventoryStrings.correction.active(language),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
              selected: {_action},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() => _action = value.first),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          _Input(
            controller: _quantity,
            label: YorksV1InventoryStrings.stockQuantity.active(language),
            numeric: true,
          ),
          const SizedBox(height: AppSpacing.md),
          _Input(
            controller: _reason,
            label: YorksV1LogisticsStrings.reason.active(language),
            lines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          _Input(
            controller: _reference,
            label: YorksV1InventoryStrings.referenceOptional.active(language),
          ),
        ],
      ),
    );
    final actions = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: (_saving || _command.unresolved)
                ? null
                : () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _saving || !unitReady ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              (_command.unresolved
                      ? YorksV1InventoryStrings.retrySave
                      : switch (_action) {
                          'remove' => YorksV1InventoryStrings.removeStock,
                          'correction' => YorksV1InventoryStrings.correction,
                          _ => YorksV1InventoryStrings.addStock,
                        })
                  .active(language),
            ),
          ),
        ],
      ),
    );
    final body = PopScope(
      canPop: !_saving && !_command.unresolved,
      child: Column(
        children: [
          _DialogHeader(
            title: YorksV1InventoryStrings.addReceive.active(language),
            onClose: (_saving || _command.unresolved)
                ? null
                : () => Navigator.of(context).pop(),
          ),
          if (_command.unresolved && !_saving)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                YorksV1InventoryStrings.uncertainSave.active(language),
                style: AppTypography.bodyMedium,
              ),
            ),
          Expanded(
            child: AbsorbPointer(
              absorbing: _saving || _command.unresolved,
              child: ExcludeFocus(
                excluding: _saving || _command.unresolved,
                child: content,
              ),
            ),
          ),
          const Divider(height: 1),
          actions,
        ],
      ),
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: body));
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(
        width: 680,
        height: math.min(760, MediaQuery.sizeOf(context).height - 48),
        child: body,
      ),
    );
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    final newItem = widget.inventoryItem == null;
    final controlledUnits = yorksV1LoadedControlledUnits(
      ref.read(yorksV1ConfigurationUnitCodesProvider),
    );
    if (quantity == null ||
        !quantity.isFinite ||
        (_action == 'correction' ? quantity == 0 : quantity <= 0) ||
        _reason.text.trim().isEmpty ||
        (newItem &&
            (_description.text.trim().isEmpty ||
                !controlledUnits.contains(_unit.trim()) ||
                (!_newCategory && _categoryId == null) ||
                (_newCategory && _newCategoryName.text.trim().isEmpty)))) {
      _failure();
      return;
    }
    setState(() => _saving = true);
    try {
      await _command.save(
        ref.read(yorksV1LogisticsRepositoryProvider),
        () => YorksV1InventoryAdjustmentInput(
          inventoryItemId: widget.inventoryItem?.id,
          description: newItem ? _description.text : null,
          itemCode: newItem ? _itemCode.text : null,
          brandOrigin: newItem ? _brand.text : null,
          unit: newItem ? _unit : null,
          categoryId: newItem && !_newCategory ? _categoryId : null,
          newCategoryName: newItem && _newCategory
              ? _newCategoryName.text
              : null,
          sourceCategoryText: newItem && _newCategory
              ? _newCategoryName.text
              : null,
          minimumStock: newItem ? _minimum.text : null,
          locationBin: newItem ? _location.text : null,
          notes: newItem ? _notes.text : null,
          quantityDelta: _quantity.text,
          expectedVersion: widget.inventoryItem?.recordVersion,
          action: _action,
          reference: _reference.text,
          reason: _reason.text,
          idempotencyKey: const Uuid().v4(),
        ),
      );
      if (!mounted) return;
      widget.onCommitted();
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _failure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _failure() {
    final language = ref.read(languageProvider);
    YorksAppToast.show(
      context,
      title:
          (_command.unresolved
                  ? YorksV1InventoryStrings.uncertainSave
                  : YorksV1InventoryStrings.savingFailed)
              .active(language),
      tone: YorksAppToastTone.error,
    );
  }
}

class _InventoryImportDialog extends ConsumerWidget {
  const _InventoryImportDialog({
    required this.workspace,
    required this.onCommitted,
  });
  final YorksV1InventoryWorkspace workspace;
  final VoidCallback onCommitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksV1InventoryImportControllerProvider);
    final controller = ref.read(
      yorksV1InventoryImportControllerProvider.notifier,
    );
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final preview = state.preview;
    Future<void> commit() async {
      final result = await controller.commit();
      if (result != null && context.mounted) {
        onCommitted();
        Navigator.of(context).pop();
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.importSucceeded.active(language),
          tone: YorksAppToastTone.success,
        );
      }
    }

    final body = PopScope(
      canPop: !state.isBusy,
      child: Column(
        children: [
          _DialogHeader(
            title: preview == null
                ? YorksV1InventoryStrings.importTitle.active(language)
                : YorksV1InventoryStrings.previewInventoryImport.active(
                    language,
                  ),
            subtitle: preview == null
                ? YorksV1InventoryStrings.importHelp.active(language)
                : '${preview.fileName} · ${YorksV1InventoryStrings.nothingChangesUntilConfirm.active(language)}',
            onClose: state.isBusy ? null : () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (preview == null)
                    _InventoryImportStart(
                      language: language,
                      enabled: !state.isBusy,
                      onChoose: () => controller.chooseFile(workspace),
                    ),
                  if (state.status ==
                      YorksV1InventoryImportStatus.selecting) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (preview != null) ...[
                    _ImportSummary(language: language, preview: preview),
                    const SizedBox(height: AppSpacing.lg),
                    _ImportSmartMappingNote(
                      language: language,
                      preview: preview,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ImportReviewNote(language: language, preview: preview),
                    const SizedBox(height: AppSpacing.lg),
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth >=
                              AppSpacing.yorksV1DesktopBreakpoint
                          ? _InventoryImportPreviewTable(
                              rows: preview.rows,
                              categories: workspace.categories,
                              language: language,
                              enabled: !state.isBusy,
                              onCategory: (row, categoryId) =>
                                  controller.selectExistingCategory(
                                    sourceCategory: row.sourceCategory,
                                    categoryId: categoryId,
                                  ),
                              onNew: (row) => controller.createNewCategory(
                                row.sourceCategory,
                              ),
                            )
                          : Column(
                              children: [
                                for (final row in preview.rows)
                                  _ImportRowCard(
                                    row: row,
                                    categories: workspace.categories,
                                    language: language,
                                    enabled: !state.isBusy,
                                    onCategory: (categoryId) =>
                                        controller.selectExistingCategory(
                                          sourceCategory: row.sourceCategory,
                                          categoryId: categoryId,
                                        ),
                                    onNew: () => controller.createNewCategory(
                                      row.sourceCategory,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                  if (state.status == YorksV1InventoryImportStatus.failed) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      YorksV1InventoryStrings.savingFailed.active(language),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final choose = OutlinedButton(
                  onPressed: state.isBusy
                      ? null
                      : preview == null
                      ? () => Navigator.of(context).pop()
                      : () => controller.chooseFile(workspace),
                  child: Text(
                    preview == null
                        ? MaterialLocalizations.of(context).cancelButtonLabel
                        : YorksV1InventoryStrings.chooseAnotherFile.active(
                            language,
                          ),
                  ),
                );
                if (preview == null) {
                  return Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: choose,
                  );
                }
                final download = OutlinedButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () async {
                          try {
                            final saved = await ref
                                .read(
                                  yorksV1InventoryWorkbookFileServiceProvider,
                                )
                                .saveImportTemplate();
                            if (!saved || !context.mounted) return;
                            YorksAppToast.show(
                              context,
                              title: YorksV1InventoryStrings
                                  .downloadFormatComplete
                                  .active(language),
                              tone: YorksAppToastTone.success,
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            YorksAppToast.show(
                              context,
                              title: YorksV1InventoryStrings
                                  .downloadFormatFailed
                                  .active(language),
                              tone: YorksAppToastTone.error,
                            );
                          }
                        },
                  icon: const Icon(
                    YorksDataTransferIcons.downloadTemplate,
                    size: 18,
                  ),
                  label: Text(
                    YorksV1InventoryStrings.downloadFormat.active(language),
                  ),
                );
                final confirm = FilledButton.icon(
                  onPressed: preview.canCommit && !state.isBusy ? commit : null,
                  icon: state.status == YorksV1InventoryImportStatus.committing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    '${YorksV1InventoryStrings.confirmImport.active(language)} (${preview.rowCount})',
                  ),
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: choose),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: download),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      confirm,
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    choose,
                    const SizedBox(width: AppSpacing.sm),
                    download,
                    const SizedBox(width: AppSpacing.sm),
                    confirm,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: body));
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: SizedBox(
        width: preview == null ? 760 : 1240,
        height: MediaQuery.sizeOf(context).height - 48,
        child: body,
      ),
    );
  }
}

class _InventoryImportStart extends StatelessWidget {
  const _InventoryImportStart({
    required this.language,
    required this.enabled,
    required this.onChoose,
  });
  final AppLanguage language;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _WarehousePanel(
        title: YorksV1InventoryStrings.importInventory.active(language),
        subtitle: YorksV1InventoryStrings.importHelp.active(language),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              _ImportStartStep(
                icon: YorksDataTransferIcons.downloadTemplate,
                title: YorksV1InventoryStrings.downloadImportFormat.active(
                  language,
                ),
                description: YorksV1InventoryStrings.controlledExcelStructure
                    .active(language),
                action: OutlinedButton.icon(
                  onPressed: enabled ? onChoose : null,
                  icon: const Icon(YorksDataTransferIcons.importData, size: 18),
                  label: Text(
                    YorksV1InventoryStrings.selectFile.active(language),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _ImportSmartMappingNote(language: language),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ImportStartStep extends StatelessWidget {
  const _ImportStartStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(description, style: AppTypography.bodySmall),
          ],
        );
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.blue),
              const SizedBox(height: AppSpacing.sm),
              copy,
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          );
        }
        return Row(
          children: [
            Icon(icon, color: AppColors.blue),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            action,
          ],
        );
      },
    ),
  );
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({required this.language, required this.preview});
  final AppLanguage language;
  final YorksV1InventoryImportPreview preview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 880 ? 4 : 2;
      final width =
          (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;
      final cards = [
        (
          Icons.description_outlined,
          YorksV1InventoryStrings.rowsFound.active(language),
          preview.rowCount,
          YorksV1InventoryStrings.nonEmptyDataRows.active(language),
          AppColors.blue,
        ),
        (
          Icons.add_rounded,
          YorksV1InventoryStrings.newItems.active(language),
          preview.newItemCount,
          YorksV1InventoryStrings.willCreateItemMasters.active(language),
          AppColors.success,
        ),
        (
          Icons.check_rounded,
          YorksV1InventoryStrings.existingMatches.active(language),
          preview.existingItemCount,
          YorksV1InventoryStrings.matchedByCodeOrIdentity.active(language),
          AppColors.purple,
        ),
        (
          Icons.warning_amber_rounded,
          YorksV1InventoryStrings.needReview.active(language),
          preview.warningCount + preview.errorCount,
          '${preview.errorCount} ${YorksV1InventoryStrings.errors.active(language)} · ${preview.warningCount} ${YorksV1InventoryStrings.warnings.active(language)}',
          preview.errorCount > 0 ? AppColors.error : AppColors.warning,
        ),
      ];
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final card in cards)
            SizedBox(
              width: width,
              child: _ImportMetric(
                icon: card.$1,
                label: card.$2,
                value: card.$3,
                detail: card.$4,
                tone: card.$5,
              ),
            ),
        ],
      );
    },
  );
}

class _ImportSmartMappingNote extends StatelessWidget {
  const _ImportSmartMappingNote({required this.language, this.preview});
  final AppLanguage language;
  final YorksV1InventoryImportPreview? preview;

  @override
  Widget build(BuildContext context) {
    final proposed =
        preview?.rows
            .map((row) => row.newCategoryName)
            .whereType<String>()
            .toSet()
            .length ??
        0;
    return _ImportNotice(
      icon: Icons.monitor_heart_outlined,
      tone: AppColors.blue,
      title: YorksV1InventoryStrings.smartCategoryMappingActive.active(
        language,
      ),
      body: proposed == 0
          ? YorksV1InventoryStrings.smartCategoryMappingHelp.active(language)
          : '${YorksV1InventoryStrings.smartCategoryMappingHelp.active(language)} $proposed ${YorksV1InventoryStrings.newCategory.active(language)}.',
    );
  }
}

class _ImportReviewNote extends StatelessWidget {
  const _ImportReviewNote({required this.language, required this.preview});
  final AppLanguage language;
  final YorksV1InventoryImportPreview preview;

  @override
  Widget build(BuildContext context) => _ImportNotice(
    icon: preview.errorCount > 0
        ? Icons.error_outline_rounded
        : Icons.check_rounded,
    tone: preview.errorCount > 0 ? AppColors.error : AppColors.success,
    title: preview.errorCount > 0
        ? YorksV1InventoryStrings.categoryDecision.active(language)
        : YorksV1InventoryStrings.reviewWarningsBeforeImport.active(language),
    body: YorksV1InventoryStrings.serverRevalidatesBeforeCommit.active(
      language,
    ),
  );
}

class _ImportNotice extends StatelessWidget {
  const _ImportNotice({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .06),
      border: Border.all(color: tone.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tone),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(body, style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ImportMetric extends StatelessWidget {
  const _ImportMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.tone,
  });
  final IconData icon;
  final String label;
  final int value;
  final String detail;
  final Color tone;
  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: Row(
      children: [
        Container(width: 5, height: 148, color: tone),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, color: tone, size: 20),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(label, style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.xxs),
                Text('$value', style: AppTypography.headlineMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(detail, style: AppTypography.bodySmall),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _InventoryImportPreviewTable extends StatelessWidget {
  const _InventoryImportPreviewTable({
    required this.rows,
    required this.categories,
    required this.language,
    required this.enabled,
    required this.onCategory,
    required this.onNew,
  });

  final List<YorksV1InventoryImportRow> rows;
  final List<YorksV1InventoryCategory> categories;
  final AppLanguage language;
  final bool enabled;
  final void Function(YorksV1InventoryImportRow row, String categoryId)
  onCategory;
  final ValueChanged<YorksV1InventoryImportRow> onNew;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1120,
        child: Column(
          children: [
            _InventoryImportPreviewTableRow(language: language),
            const Divider(height: 1),
            for (final row in rows) ...[
              _InventoryImportPreviewTableRow(
                row: row,
                categories: categories,
                language: language,
                enabled: enabled,
                onCategory: (categoryId) => onCategory(row, categoryId),
                onNew: () => onNew(row),
              ),
              if (row != rows.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    ),
  );
}

class _InventoryImportPreviewTableRow extends StatelessWidget {
  const _InventoryImportPreviewTableRow({
    required this.language,
    this.row,
    this.categories = const [],
    this.enabled = false,
    this.onCategory,
    this.onNew,
  });

  final YorksV1InventoryImportRow? row;
  final List<YorksV1InventoryCategory> categories;
  final AppLanguage language;
  final bool enabled;
  final ValueChanged<String>? onCategory;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final header = row == null;
    Widget cell(Widget child, int flex) => Expanded(flex: flex, child: child);
    Widget heading(String text) => Text(text, style: AppTypography.labelMedium);
    final decisionRequired = row?.requiresCategoryDecision ?? false;
    final severity = row?.hasErrors == true
        ? AppColors.error
        : row?.hasWarnings == true
        ? AppColors.warning
        : AppColors.success;
    return Container(
      color: header
          ? AppColors.surfaceContainerLow
          : severity.withValues(
              alpha: row!.hasErrors || row!.hasWarnings ? .03 : 0,
            ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: header
            ? [
                cell(heading(YorksV1InventoryStrings.row.active(language)), 1),
                cell(
                  heading(
                    YorksV1InventoryStrings.inventoryItem.active(language),
                  ),
                  4,
                ),
                cell(
                  heading(YorksV1InventoryStrings.category.active(language)),
                  3,
                ),
                cell(
                  heading(YorksV1InventoryStrings.stockAction.active(language)),
                  2,
                ),
                cell(
                  heading(YorksV1LogisticsStrings.quantity.active(language)),
                  1,
                ),
                cell(
                  heading(
                    YorksV1InventoryStrings.itemMatchResult.active(language),
                  ),
                  2,
                ),
                cell(
                  heading(YorksV1InventoryStrings.validation.active(language)),
                  3,
                ),
              ]
            : [
                cell(
                  Text(
                    '${row!.sourceRowNumber}',
                    style: AppTypography.bodyMedium,
                  ),
                  1,
                ),
                cell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row!.itemCode.isEmpty ? '—' : row!.itemCode} · ${row!.description}',
                        style: AppTypography.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        [
                          row!.brandOrigin,
                          row!.unit,
                          row!.locationBin,
                        ].where((value) => value.isNotEmpty).join(' · '),
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                  4,
                ),
                cell(
                  decisionRequired
                      ? _ImportCategoryDecision(
                          row: row!,
                          categories: categories,
                          language: language,
                          enabled: enabled,
                          onCategory: onCategory,
                          onNew: onNew,
                        )
                      : _ImportCategoryDisplay(row: row!, language: language),
                  3,
                ),
                cell(
                  Text(
                    row!.stockAction?.displayName ?? '—',
                    style: AppTypography.bodyMedium,
                  ),
                  2,
                ),
                cell(
                  Text(
                    '${_quantity(row!.quantity)} ${row!.unit}',
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyMedium,
                  ),
                  1,
                ),
                cell(_ImportRowResult(row: row!, language: language), 2),
                cell(_ImportRowValidation(row: row!, language: language), 3),
              ],
      ),
    );
  }
}

class _ImportCategoryDisplay extends StatelessWidget {
  const _ImportCategoryDisplay({required this.row, required this.language});
  final YorksV1InventoryImportRow row;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final label = row.newCategoryName ?? row.sourceCategory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        if (row.newCategoryName != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _CountPill(
            YorksV1InventoryStrings.newCategory.active(language),
            tone: AppColors.purple,
          ),
        ],
      ],
    );
  }
}

class _ImportCategoryDecision extends StatelessWidget {
  const _ImportCategoryDecision({
    required this.row,
    required this.categories,
    required this.language,
    required this.enabled,
    required this.onCategory,
    required this.onNew,
  });
  final YorksV1InventoryImportRow row;
  final List<YorksV1InventoryCategory> categories;
  final AppLanguage language;
  final bool enabled;
  final ValueChanged<String>? onCategory;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final proposedName = yorksV1InventoryCategoryDisplayName(
      row.sourceCategory,
    );
    final selected = row.newCategoryName != null
        ? _createImportedCategoryChoice
        : row.categoryId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'inventory-category-${row.sourceRowNumber}-${row.categoryId}-${row.newCategoryName}',
          ),
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          initialValue: selected,
          hint: Text(
            YorksV1InventoryStrings.chooseOrCreateCategory.active(language),
          ),
          items: [
            DropdownMenuItem(
              value: _createImportedCategoryChoice,
              child: Text(
                '${YorksV1InventoryStrings.createCategoryNamed.active(language)} “$proposedName”',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final suggestion in row.suggestions)
              DropdownMenuItem(
                value: suggestion.category.id,
                child: Text(
                  '${suggestion.category.displayPath} · ${(suggestion.score * 100).round()}%',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final category in categories)
              if (!row.suggestions.any(
                (suggestion) => suggestion.category.id == category.id,
              ))
                DropdownMenuItem(
                  value: category.id,
                  child: Text(
                    category.displayPath,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value == _createImportedCategoryChoice) {
                    onNew?.call();
                  } else if (value != null) {
                    onCategory?.call(value);
                  }
                }
              : null,
        ),
        if (row.newCategoryName != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _CountPill(
            YorksV1InventoryStrings.newCategory.active(language),
            tone: AppColors.purple,
          ),
        ],
      ],
    );
  }
}

class _ImportRowResult extends StatelessWidget {
  const _ImportRowResult({required this.row, required this.language});
  final YorksV1InventoryImportRow row;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _CountPill(
    row.isNewItem
        ? YorksV1InventoryStrings.newItems.active(language)
        : YorksV1InventoryStrings.existingMatches.active(language),
    tone: row.isNewItem ? AppColors.warning : AppColors.success,
  );
}

class _ImportRowValidation extends StatelessWidget {
  const _ImportRowValidation({required this.row, required this.language});
  final YorksV1InventoryImportRow row;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (!row.hasErrors && !row.hasWarnings) {
      return Text(
        YorksV1InventoryStrings.ready.active(language),
        style: AppTypography.labelLarge.copyWith(color: AppColors.success),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in row.issues)
          Text(
            issue.isWarning
                ? YorksV1InventoryStrings.reviewWarningsBeforeImport.active(
                    language,
                  )
                : YorksV1InventoryStrings.categoryDecision.active(language),
            style: AppTypography.bodySmall.copyWith(
              color: issue.isWarning ? AppColors.warning : AppColors.error,
            ),
          ),
      ],
    );
  }
}

class _ImportRowCard extends StatelessWidget {
  const _ImportRowCard({
    required this.row,
    required this.categories,
    required this.language,
    required this.enabled,
    required this.onCategory,
    required this.onNew,
  });
  final YorksV1InventoryImportRow row;
  final List<YorksV1InventoryCategory> categories;
  final AppLanguage language;
  final bool enabled;
  final ValueChanged<String> onCategory;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final needsDecision = row.requiresCategoryDecision;
    final decisionPending = row.issues.any(
      (issue) =>
          issue.code ==
          YorksV1InventoryImportIssueCode.categoryDecisionRequired,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  child: Text(
                    '${row.sourceRowNumber}',
                    style: AppTypography.labelSmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(row.description, style: AppTypography.titleSmall),
                ),
                Text(
                  '${_quantity(row.quantity)} ${row.unit}',
                  style: AppTypography.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${row.sourceCategory} · ${row.stockAction?.displayName ?? '—'}',
              style: AppTypography.bodySmall,
            ),
            if (row.hasErrors || decisionPending) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                decisionPending
                    ? YorksV1InventoryStrings.categoryDecision.active(language)
                    : YorksV1InventoryStrings.reviewRow.active(language),
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
            if (needsDecision) ...[
              const SizedBox(height: AppSpacing.sm),
              _ImportCategoryDecision(
                row: row,
                categories: categories,
                language: language,
                enabled: enabled,
                onCategory: onCategory,
                onNew: onNew,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoriesDialog extends ConsumerStatefulWidget {
  const _CategoriesDialog({
    required this.categories,
    required this.onCommitted,
  });
  final List<YorksV1InventoryCategory> categories;
  final VoidCallback onCommitted;
  @override
  ConsumerState<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends ConsumerState<_CategoriesDialog> {
  final _name = TextEditingController();
  String? _commandId;
  String? _commandName;
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final ordered = [...widget.categories]
      ..sort((left, right) => left.displayPath.compareTo(right.displayPath));
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xxxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1120,
            maxHeight: MediaQuery.sizeOf(context).height - (compact ? 32 : 64),
          ),
          child: Material(
            color: AppColors.surfaceContainerLowest,
            elevation: 16,
            shadowColor: AppColors.shadow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              YorksV1InventoryStrings.warehouseCategories
                                  .active(language),
                              style: AppTypography.headlineSmall.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              YorksV1InventoryStrings.warehouseCategoriesHelp
                                  .active(language),
                              style: AppTypography.bodyMedium.copyWith(
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
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Surface(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final action = FilledButton.icon(
                                onPressed: _saving ? null : _create,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(
                                  YorksV1InventoryStrings.addCategory.active(
                                    language,
                                  ),
                                ),
                              );
                              final field = TextField(
                                controller: _name,
                                enabled: !_saving,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _saving ? null : _create(),
                                decoration: InputDecoration(
                                  hintText: YorksV1InventoryStrings
                                      .parentCategoryHint
                                      .active(language),
                                ),
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (constraints.maxWidth >= 620)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          YorksV1InventoryStrings
                                              .newParentCategory
                                              .active(language),
                                          style: AppTypography.titleSmall,
                                        ),
                                        const SizedBox(width: AppSpacing.md),
                                        Expanded(child: field),
                                        const SizedBox(width: AppSpacing.md),
                                        action,
                                      ],
                                    )
                                  else ...[
                                    Text(
                                      YorksV1InventoryStrings.newParentCategory
                                          .active(language),
                                      style: AppTypography.titleSmall,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    field,
                                    const SizedBox(height: AppSpacing.sm),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: action,
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    YorksV1InventoryStrings
                                        .categoryNormalizationHelp
                                        .active(language),
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        for (final category in ordered) ...[
                          _WarehouseCategoryRow(
                            category: category,
                            language: language,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).closeButtonLabel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_commandName != name) {
      _commandName = name;
      _commandId = const Uuid().v4();
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(yorksV1LogisticsRepositoryProvider)
          .createInventoryCategory(
            YorksV1InventoryCategoryCreationInput(
              name: name,
              // Manual category management creates top-level families. The
              // existing specialist parent/child taxonomy stays intact.
              parentCategoryId: null,
              idempotencyKey: _commandId!,
            ),
          );
      if (!mounted) return;
      widget.onCommitted();
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        final language = ref.read(languageProvider);
        YorksAppToast.show(
          context,
          title: YorksV1InventoryStrings.savingFailed.active(language),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WarehouseCategoryRow extends StatelessWidget {
  const _WarehouseCategoryRow({required this.category, required this.language});

  final YorksV1InventoryCategory category;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final name = category.parentName == null
        ? category.name
        : '${category.parentName} - ${category.name}';
    final subtitle = category.isSystem
        ? YorksV1InventoryStrings.yorksStandardCategory.active(language)
        : '${YorksV1InventoryStrings.createdBy.active(language)} ${category.createdByDisplayName} · ${DateFormat('dd MMM yyyy, hh:mm a').format(category.createdAt.toLocal())}';
    final aliases = category.aliases.isEmpty
        ? YorksV1InventoryStrings.noSavedAliases.active(language)
        : '${YorksV1InventoryStrings.recognizedAs.active(language)} ${category.aliases.join(' · ')}';
    return _Surface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppTypography.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          );
          final count = _CountPill(
            '${category.itemCount} ${YorksV1InventoryStrings.itemsCount.active(language)}',
            tone: AppColors.blue,
          );
          final alias = Text(
            aliases,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          );
          if (constraints.maxWidth < 660) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: AppSpacing.sm),
                count,
                const SizedBox(height: AppSpacing.sm),
                alias,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 4, child: details),
              const SizedBox(width: AppSpacing.lg),
              count,
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 3, child: alias),
            ],
          );
        },
      ),
    );
  }
}

class _InventoryItemDetailDialog extends ConsumerWidget {
  const _InventoryItemDetailDialog({
    required this.inventoryItemId,
    required this.canManage,
    required this.onChanged,
  });
  final String inventoryItemId;
  final bool canManage;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final detail = ref.watch(
      yorksV1InventoryItemDetailProvider(inventoryItemId),
    );
    final workspace = ref.watch(yorksV1InventoryWorkspaceProvider(null));
    final compact =
        MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;
    final body = detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _StateMessage(
        icon: Icons.cloud_off_rounded,
        message: YorksV1InventoryStrings.loadFailed.active(language),
        action: YorksV1LogisticsStrings.refresh.active(language),
        onAction: () =>
            ref.invalidate(yorksV1InventoryItemDetailProvider(inventoryItemId)),
      ),
      data: (value) => _InventoryItemDetailBody(
        detail: value,
        workspace: workspace,
        language: language,
        canManage: canManage,
        onClose: () => Navigator.of(context).pop(),
        onEdit: () => _edit(context, ref, value.item),
        onAdjust: () => _adjust(context, ref, value.item),
      ),
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: body));
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.xxxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: SizedBox(
        width: 1650,
        height: math.min(760, MediaQuery.sizeOf(context).height - 64),
        child: body,
      ),
    );
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    YorksV1LogisticsInventoryItem item,
  ) async {
    final workspace = await ref.read(
      yorksV1InventoryWorkspaceProvider(null).future,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InventoryAdjustmentDialog(
        workspace: workspace,
        inventoryItem: item,
        onCommitted: () {
          ref.invalidate(yorksV1InventoryItemDetailProvider(item.id));
          onChanged();
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    YorksV1LogisticsInventoryItem item,
  ) async {
    final workspace = await ref.read(
      yorksV1InventoryWorkspaceProvider(null).future,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditInventoryItemDialog(
        item: item,
        categories: workspace.categories,
        onCommitted: () {
          ref.invalidate(yorksV1InventoryItemDetailProvider(item.id));
          onChanged();
        },
      ),
    );
  }
}

class _InventoryItemDetailBody extends StatelessWidget {
  const _InventoryItemDetailBody({
    required this.detail,
    required this.workspace,
    required this.language,
    required this.canManage,
    required this.onClose,
    required this.onEdit,
    required this.onAdjust,
  });

  final YorksV1InventoryItemDetail detail;
  final AsyncValue<YorksV1InventoryWorkspace> workspace;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final reservations = workspace.valueOrNull?.reservations
        .where(
          (reservation) =>
              reservation.inventoryItemId == item.id &&
              (reservation.state == 'active' ||
                  reservation.state == 'partially_dispatched'),
        )
        .toList(growable: false);
    return Column(
      children: [
        _DialogHeader(
          title: '${item.itemCode ?? '—'} · ${item.description}',
          subtitle:
              '${item.categoryPath ?? item.categoryName ?? YorksV1InventoryStrings.uncategorized.active(language)} · ${item.locationBin ?? '—'}',
          onClose: onClose,
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _StockBadge(item: item, language: language),
                    const Spacer(),
                    if (item.updatedAt != null)
                      Text(
                        '${YorksV1InventoryStrings.lastUpdated.active(language)} ${_dateTime(item.updatedAt!)}',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _ItemMetricGrid(item: item, language: language),
                const SizedBox(height: AppSpacing.md),
                _ItemMetadataGrid(item: item, language: language),
                const SizedBox(height: AppSpacing.xl),
                _ItemDetailSection(
                  title: YorksV1InventoryStrings.activeReservations.active(
                    language,
                  ),
                  count: reservations?.length,
                  child: reservations == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : reservations.isEmpty
                      ? _InlineEmpty(
                          message: YorksV1InventoryStrings.noReservations
                              .active(language),
                        )
                      : Column(
                          children: [
                            for (final reservation in reservations)
                              _ItemReservationTile(
                                reservation: reservation,
                                language: language,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _PagedInventoryHistory(language: language, itemId: item.id),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final actions = <Widget>[
                  OutlinedButton(
                    onPressed: onClose,
                    child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                  if (canManage) ...[
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        YorksV1InventoryStrings.editDetails.active(language),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onAdjust,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        YorksV1InventoryStrings.receiveAdjust.active(language),
                      ),
                    ),
                  ],
                ];
                if (constraints.maxWidth < 560) {
                  if (!canManage) {
                    return SizedBox(width: double.infinity, child: actions[0]);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      actions[2],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: actions[0]),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: actions[1]),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      actions[index],
                      if (index < actions.length - 1)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemMetricGrid extends StatelessWidget {
  const _ItemMetricGrid({required this.item, required this.language});

  final YorksV1LogisticsInventoryItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final values = [
        (
          YorksV1LogisticsStrings.onHand.active(language),
          '${_quantity(item.onHandQuantity)} ${item.unit}',
        ),
        (
          YorksV1LogisticsStrings.reserved.active(language),
          '${_quantity(item.reservedQuantity)} ${item.unit}',
        ),
        (
          YorksV1LogisticsStrings.available.active(language),
          '${_quantity(item.availableQuantity)} ${item.unit}',
        ),
        (
          YorksV1InventoryStrings.minimumStock.active(language),
          item.minimumStock == null
              ? YorksV1InventoryStrings.notConfigured.active(language)
              : '${_quantity(item.minimumStock!)} ${item.unit}',
        ),
      ];
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final value in values)
            SizedBox(
              width: compact
                  ? (constraints.maxWidth - AppSpacing.md) / 2
                  : (constraints.maxWidth - (AppSpacing.md * 3)) / 4,
              child: _ItemMetric(label: value.$1, value: value.$2),
            ),
        ],
      );
    },
  );
}

class _ItemMetric extends StatelessWidget {
  const _ItemMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: AppTypography.labelSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(value, style: AppTypography.titleSmall),
      ],
    ),
  );
}

class _ItemMetadataGrid extends StatelessWidget {
  const _ItemMetadataGrid({required this.item, required this.language});

  final YorksV1LogisticsInventoryItem item;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = [
        (
          YorksV1LogisticsStrings.brandOrigin.active(language),
          item.brandOrigin,
        ),
        (YorksV1InventoryStrings.size.active(language), item.sizeText),
        (
          YorksV1InventoryStrings.modelReference.active(language),
          item.modelReference,
        ),
        (YorksV1InventoryStrings.location.active(language), item.locationBin),
      ];
      final width = constraints.maxWidth < 640
          ? constraints.maxWidth
          : (constraints.maxWidth - AppSpacing.md) / 2;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final field in fields)
            SizedBox(
              width: width,
              child: _ItemMetadataField(
                label: field.$1,
                value: field.$2 ?? '—',
              ),
            ),
          if (item.notes != null)
            SizedBox(
              width: constraints.maxWidth,
              child: _ItemMetadataField(
                label: YorksV1InventoryStrings.notes.active(language),
                value: item.notes!,
              ),
            ),
        ],
      );
    },
  );
}

class _ItemMetadataField extends StatelessWidget {
  const _ItemMetadataField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 62),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: AppTypography.labelSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleSmall,
        ),
      ],
    ),
  );
}

class _ItemDetailSection extends StatelessWidget {
  const _ItemDetailSection({
    required this.title,
    required this.child,
    this.count,
  });

  final String title;
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.titleSmall)),
              if (count != null) _CountPill('$count', tone: AppColors.blue),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: child,
        ),
      ],
    ),
  );
}

class _ItemReservationTile extends StatelessWidget {
  const _ItemReservationTile({
    required this.reservation,
    required this.language,
  });

  final YorksV1InventoryReservation reservation;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user_outlined, color: AppColors.purple),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${reservation.requestNumber} · ${reservation.projectName}',
                style: AppTypography.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                reservation.scopeName,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Text(
          '${_quantity(reservation.remainingQuantity)} ${reservation.unit}',
          style: AppTypography.titleSmall,
        ),
      ],
    ),
  );
}

class _EditInventoryItemDialog extends ConsumerStatefulWidget {
  const _EditInventoryItemDialog({
    required this.item,
    required this.categories,
    required this.onCommitted,
  });

  final YorksV1LogisticsInventoryItem item;
  final List<YorksV1InventoryCategory> categories;
  final VoidCallback onCommitted;

  @override
  ConsumerState<_EditInventoryItemDialog> createState() =>
      _EditInventoryItemDialogState();
}

class _EditInventoryItemDialogState
    extends ConsumerState<_EditInventoryItemDialog> {
  late final TextEditingController _code;
  late final TextEditingController _description;
  late final TextEditingController _brand;
  late final TextEditingController _size;
  late final TextEditingController _model;
  late final TextEditingController _location;
  late final TextEditingController _minimum;
  late final TextEditingController _notes;
  late String _unit;
  String? _categoryId;
  String? _commandId;
  String? _commandFingerprint;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _code = TextEditingController(text: item.itemCode ?? '');
    _description = TextEditingController(text: item.description);
    _brand = TextEditingController(text: item.brandOrigin ?? '');
    _size = TextEditingController(text: item.sizeText ?? '');
    _model = TextEditingController(text: item.modelReference ?? '');
    _location = TextEditingController(text: item.locationBin ?? '');
    _minimum = TextEditingController(
      text: item.minimumStock == null
          ? ''
          : yorksV1DisplayQuantity(item.minimumStock!),
    );
    _notes = TextEditingController(text: item.notes ?? '');
    _unit = item.unit;
    _categoryId = item.categoryId;
  }

  @override
  void dispose() {
    for (final controller in [
      _code,
      _description,
      _brand,
      _size,
      _model,
      _location,
      _minimum,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final unitsAsync = ref.watch(yorksV1ConfigurationUnitCodesProvider);
    final controlledUnits = yorksV1LoadedControlledUnits(unitsAsync);
    final unitReady =
        controlledUnits.isNotEmpty &&
        (controlledUnits.contains(_unit.trim()) || _unit == widget.item.unit);
    final compact =
        MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;
    final categories = widget.categories
        .where((category) => category.isActive || category.id == _categoryId)
        .toList(growable: false);
    final body = PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Column(
          children: [
            _DialogHeader(
              title: YorksV1InventoryStrings.editInventoryItem.active(language),
              subtitle:
                  '${widget.item.itemCode ?? '—'} · ${YorksV1InventoryStrings.editInventoryItemHelp.active(language)}',
              onClose: _saving ? null : () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      YorksV1InventoryStrings.itemIdentity.active(language),
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ResponsiveFields(
                      children: [
                        _LabeledField(
                          controller: _code,
                          label: YorksV1InventoryStrings.itemCodeOptional
                              .active(language),
                        ),
                        YorksV1ControlledUnitDropdown(
                          fieldKey: const ValueKey('edit-inventory-unit'),
                          label: YorksV1LogisticsStrings.unit.active(language),
                          value: _unit,
                          enabled: !_saving,
                          showDependencyStatus: true,
                          onChanged: (value) => setState(() => _unit = value),
                        ),
                        _LabeledField(
                          controller: _description,
                          label: YorksV1LogisticsStrings.itemDescription.active(
                            language,
                          ),
                          fullWidth: true,
                        ),
                        _LabeledField(
                          controller: _brand,
                          label: YorksV1LogisticsStrings.brandOrigin.active(
                            language,
                          ),
                        ),
                        _LabeledCategoryDropdown(
                          label: YorksV1InventoryStrings.category.active(
                            language,
                          ),
                          value: _categoryId,
                          categories: categories,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _categoryId = value),
                        ),
                        _LabeledField(
                          controller: _size,
                          label: YorksV1InventoryStrings.size.active(language),
                        ),
                        _LabeledField(
                          controller: _model,
                          label: YorksV1InventoryStrings.modelReference.active(
                            language,
                          ),
                        ),
                        _LabeledField(
                          controller: _location,
                          label: YorksV1InventoryStrings.location.active(
                            language,
                          ),
                        ),
                        _LabeledField(
                          controller: _minimum,
                          label: YorksV1InventoryStrings.minimumStock.active(
                            language,
                          ),
                          numeric: true,
                        ),
                        _LabeledField(
                          controller: _notes,
                          label: YorksV1InventoryStrings.notes.active(language),
                          lines: 3,
                          fullWidth: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MetadataTrustCard(language: language),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _saving || !unitReady ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            YorksV1InventoryStrings.saveItemDetails.active(
                              language,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (compact) return Dialog.fullscreen(child: body);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: SizedBox(
        width: 1280,
        height: math.min(760, MediaQuery.sizeOf(context).height - 48),
        child: body,
      ),
    );
  }

  Future<void> _save() async {
    final minimum = _minimum.text.trim();
    final controlledUnits = yorksV1LoadedControlledUnits(
      ref.read(yorksV1ConfigurationUnitCodesProvider),
    );
    final unitReady =
        controlledUnits.isNotEmpty &&
        (controlledUnits.contains(_unit.trim()) || _unit == widget.item.unit);
    if (_description.text.trim().isEmpty ||
        _categoryId == null ||
        !unitReady ||
        (minimum.isNotEmpty &&
            (double.tryParse(minimum) == null || double.parse(minimum) < 0))) {
      _failure();
      return;
    }
    final fingerprint = [
      _code.text.trim(),
      _description.text.trim(),
      _categoryId,
      _brand.text.trim(),
      _size.text.trim(),
      _model.text.trim(),
      _unit,
      minimum,
      _location.text.trim(),
      _notes.text.trim(),
    ].join('\u0000');
    if (_commandFingerprint != fingerprint) {
      _commandFingerprint = fingerprint;
      _commandId = const Uuid().v4();
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(yorksV1LogisticsRepositoryProvider);
      if (repository is! YorksV1InventoryItemMetadataRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      final metadataRepository =
          repository as YorksV1InventoryItemMetadataRepository;
      await metadataRepository.updateInventoryItemMetadata(
        YorksV1InventoryItemMetadataInput(
          inventoryItemId: widget.item.id,
          expectedMetadataVersion: widget.item.metadataRecordVersion ?? 1,
          itemCode: _code.text,
          description: _description.text,
          categoryId: _categoryId,
          brandOrigin: _brand.text,
          sizeText: _size.text,
          modelReference: _model.text,
          unit: _unit,
          minimumStock: minimum,
          locationBin: _location.text,
          notes: _notes.text,
          idempotencyKey: _commandId!,
        ),
      );
      if (!mounted) return;
      widget.onCommitted();
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _failure();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _failure() => YorksAppToast.show(
    context,
    title: YorksV1InventoryStrings.savingFailed.active(
      ref.read(languageProvider),
    ),
    tone: YorksAppToastTone.error,
  );
}

class _MetadataTrustCard extends StatelessWidget {
  const _MetadataTrustCard({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user_outlined, color: AppColors.blue),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            YorksV1InventoryStrings.editInventoryItemHelp.active(language),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.onClose,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
      ],
    ),
  );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    this.numeric = false,
    this.lines = 1,
  });
  final TextEditingController controller;
  final String label;
  final bool numeric;
  final int lines;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : lines > 1
        ? TextInputType.multiline
        : TextInputType.text,
    minLines: lines,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    elevation: 1,
    shadowColor: AppColors.shadow,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      side: const BorderSide(color: AppColors.line),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelSmall),
      const SizedBox(height: AppSpacing.xs),
      Text(value, style: AppTypography.titleSmall),
    ],
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Center(
      child: Text(
        message,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      ),
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium,
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

String _quantity(String value) {
  return yorksV1DisplayQuantity(value);
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} · ${two(local.hour)}:${two(local.minute)}';
}

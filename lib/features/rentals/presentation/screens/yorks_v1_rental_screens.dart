import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../../shared/models/yorks_v1_document_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_rental_strings.dart';
import '../../../../shared/models/yorks_v1_rental.dart';
import '../../../../shared/models/yorks_v1_rental_action.dart';
import '../../../../shared/models/yorks_v1_rental_workbook.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_rental_provider.dart';
import '../../../../shared/repositories/yorks_v1_rental_repository.dart';

const _pageInset = 24.0;
const _compactAt = 720.0;
const _tableAt = 1040.0;

final _money = NumberFormat.currency(
  locale: 'en_AE',
  symbol: 'AED ',
  decimalDigits: 2,
);
final _day = DateFormat('dd MMM yyyy');
final _month = DateFormat('MMM yyyy');

String _optional(String? value) =>
    value == null || value.trim().isEmpty ? '—' : value.trim();

String _rentText(BuildContext context, YorksV1RentalProperty property) =>
    property.rentAmount == null
    ? '—'
    : '${_money.format(property.rentAmount)} / ${RentalWorkspaceStrings.text(context, property.isAnnual ? 'perYear' : 'perMonth')}';

String _occupancyText(BuildContext context, YorksV1RentalProperty property) =>
    RentalWorkspaceStrings.text(context, property.occupancy.name);

String _termOption(String value) =>
    const {
      'shop': 'Shop',
      'warehouse': 'Warehouse',
      'store': 'Store',
      'office': 'Office',
      'office_store': 'Office (Store)',
      'villa': 'Villa',
      'labour_camp': 'Labour Camp',
      'other': 'Other',
      'tenancy_contract': 'Tenancy Contract',
      'lease': 'Lease',
      'licence': 'Licence',
      'draft': 'Draft',
      'active': 'Active',
      'expired': 'Expired',
      'terminated': 'Terminated',
      'notice_due': 'Notice Due',
      'renewed': 'Renewed',
      'bank_transfer': 'Bank Transfer',
      'cash': 'Cash',
      'pdc': 'PDC',
      'cdc': 'CDC',
      'monthly': 'Monthly',
      'annual': 'Annual',
    }[value] ??
    value;

/// R38.4 normalized rental workspace. This screen intentionally does not read
/// or write the legacy local rental collections; all facts come from the
/// Admin-only trusted rental repository.
class YorksV1RentalDashboardScreen extends ConsumerStatefulWidget {
  const YorksV1RentalDashboardScreen({super.key});

  @override
  ConsumerState<YorksV1RentalDashboardScreen> createState() =>
      _YorksV1RentalDashboardScreenState();
}

class _YorksV1RentalDashboardScreenState
    extends ConsumerState<YorksV1RentalDashboardScreen> {
  final _search = TextEditingController();
  _RentalSection _section = _RentalSection.overview;
  _RentalFilter _filter = _RentalFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(yorksV1RentalCommandProvider);
    final portfolio = ref.watch(yorksV1RentalPortfolioProvider);
    final busy = ref.watch(yorksV1RentalCommandProvider).isLoading;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: portfolio.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RentalFailure(
          onRetry: () => ref.invalidate(yorksV1RentalPortfolioProvider),
        ),
        data: (data) => LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactAt;
            final padding = compact
                ? const EdgeInsets.fromLTRB(14, 18, 14, 112)
                : const EdgeInsets.fromLTRB(_pageInset, 22, _pageInset, 44);
            return ListView(
              padding: padding,
              children: [
                const _RentalPendingActionsPanel(),
                _RentalPageHeader(
                  compact: compact,
                  onRefresh: busy || portfolio.isLoading
                      ? null
                      : () => ref.invalidate(yorksV1RentalPortfolioProvider),
                  onAdd: busy ? null : () => _openPropertyEditor(context),
                  onDownloadTemplate: busy
                      ? null
                      : () => _downloadImportTemplate(context),
                  onImport: busy ? null : () => _importWorkbook(context, data),
                  onExport: busy
                      ? null
                      : (register) => _exportRegister(context, register),
                ),
                const SizedBox(height: 16),
                _RentalSectionRail(
                  selected: _section,
                  onSelected: (value) => setState(() => _section = value),
                ),
                const SizedBox(height: 16),
                if (_section == _RentalSection.overview)
                  _RentalOverview(
                    portfolio: data,
                    compact: compact,
                    onOpenProperty: _openProperty,
                    onOpenAction: _openAction,
                    onOpenSection: (section) =>
                        setState(() => _section = section),
                  )
                else if (_section == _RentalSection.properties)
                  _PropertyRegister(
                    properties: data.properties,
                    query: _search,
                    selectedFilter: _filter,
                    onFilter: (value) => setState(() => _filter = value),
                    onChanged: () => setState(() {}),
                    onOpen: _openProperty,
                  )
                else if (_section == _RentalSection.payments)
                  _PortfolioPayments(payments: data.recentPayments)
                else if (_section == _RentalSection.cheques)
                  _PortfolioCheques(
                    cheques: data.cheques,
                    onOpenProperty: _openProperty,
                  )
                else
                  _LeaseExpiryRegister(
                    properties: data.properties,
                    onOpen: _openProperty,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openProperty(YorksV1RentalProperty property) {
    context.push('${RoutePaths.rentals}/${property.id}');
  }

  void _openAction(YorksV1RentalProperty property, YorksRentalAction action) {
    context.push(
      Uri(
        path: RoutePaths.rentalUnitPath(property.id),
        queryParameters: {'action': action.name},
      ).toString(),
    );
  }

  Future<void> _openPropertyEditor(BuildContext context) async {
    final savedId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PropertyEditorDialog(
        onSave: (input, key) => ref
            .read(yorksV1RentalCommandProvider.notifier)
            .saveProperty(input, expectedVersion: null, idempotencyKey: key),
        saveError: () => ref.read(yorksV1RentalCommandProvider).error,
      ),
    );
    if (savedId != null && context.mounted) {
      _showResult(context, true, RentalWorkspaceStrings.text(context, 'saved'));
      context.push('${RoutePaths.rentals}/$savedId');
    }
  }

  Future<void> _downloadImportTemplate(BuildContext context) async {
    try {
      final saved = await ref
          .read(yorksV1RentalWorkbookFileServiceProvider)
          .saveImportTemplate();
      if (context.mounted && saved) {
        _showResult(context, true, 'Rental import format downloaded.');
      }
    } catch (_) {
      if (context.mounted) {
        _showResult(context, false, 'The rental import format was not saved.');
      }
    }
  }

  Future<void> _importWorkbook(
    BuildContext context,
    YorksV1RentalPortfolio portfolio,
  ) async {
    try {
      final selected = await ref
          .read(yorksV1RentalWorkbookFileServiceProvider)
          .selectWorkbook();
      if (selected == null || !context.mounted) return;
      final preview = ref
          .read(yorksV1RentalWorkbookCodecProvider)
          .preview(selected: selected, portfolio: portfolio);
      final imported = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RentalImportPreviewDialog(
          preview: preview,
          onConfirm: () => ref
              .read(yorksV1RentalCommandProvider.notifier)
              .importWorkbook(preview),
        ),
      );
      if (context.mounted && imported == true) {
        _showResult(context, true, 'Rental workbook imported.');
      }
    } catch (_) {
      if (context.mounted) {
        _showResult(
          context,
          false,
          'The workbook could not be previewed. Nothing was imported.',
        );
      }
    }
  }

  Future<void> _exportRegister(
    BuildContext context,
    YorksV1RentalExportRegister register,
  ) async {
    try {
      final data = await ref
          .read(yorksV1RentalRepositoryProvider)
          .getExportData();
      final bytes = ref
          .read(yorksV1RentalWorkbookCodecProvider)
          .buildExport(register: register, data: data);
      final saved = await ref
          .read(yorksV1RentalWorkbookFileServiceProvider)
          .saveExport(
            bytes: bytes,
            suggestedName:
                'Yorks_${_rentalExportSlug(register)}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx',
          );
      if (context.mounted && saved) {
        _showResult(context, true, '${_rentalExportLabel(register)} exported.');
      }
    } catch (_) {
      if (context.mounted) {
        _showResult(context, false, 'The rental register was not exported.');
      }
    }
  }
}

enum _RentalSection { overview, properties, payments, cheques, expiry }

enum _RentalFilter { all, occupied, due, overdue, expiring, vacant, archived }

class _RentalPendingActionsPanel extends ConsumerWidget {
  const _RentalPendingActionsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksV1RentalCommandProvider);
    final controller = ref.read(yorksV1RentalCommandProvider.notifier);
    final pending = controller.pendingCommands;
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _Panel(
        title: RentalWorkspaceStrings.text(context, 'unfinishedAction'),
        subtitle: RentalWorkspaceStrings.text(context, 'unfinishedActionHelp'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final command in pending)
                OutlinedButton(
                  onPressed: state.isLoading
                      ? null
                      : () => _review(context, ref, command),
                  child: Text(
                    '${RentalWorkspaceStrings.text(context, 'reviewUnfinishedAction')} · ${RentalWorkspaceStrings.text(context, 'pending_${command.commandName}')}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    YorksV1RentalPendingCommand pending,
  ) async {
    final resolve = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          RentalWorkspaceStrings.text(context, 'reviewUnfinishedAction'),
        ),
        content: Text(
          RentalWorkspaceStrings.text(context, 'resolveActionHelp'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(RentalWorkspaceStrings.text(context, 'cancelAction')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(RentalWorkspaceStrings.text(context, 'resolveAction')),
          ),
        ],
      ),
    );
    if (resolve != true || !context.mounted) return;
    final resolution = await ref
        .read(yorksV1RentalCommandProvider.notifier)
        .settlePendingCommand(pending);
    if (!context.mounted) return;
    _showResult(
      context,
      resolution != null,
      RentalWorkspaceStrings.text(context, switch (resolution) {
        YorksV1RentalIntentResolution.confirmed => 'resolvedConfirmed',
        YorksV1RentalIntentResolution.abandoned => 'resolvedAbandoned',
        null => 'resolveFailed',
      }),
    );
  }
}

class _RentalPageHeader extends StatelessWidget {
  const _RentalPageHeader({
    required this.compact,
    required this.onAdd,
    required this.onRefresh,
    required this.onDownloadTemplate,
    required this.onImport,
    required this.onExport,
  });
  final bool compact;
  final VoidCallback? onAdd;
  final VoidCallback? onRefresh;
  final VoidCallback? onDownloadTemplate;
  final VoidCallback? onImport;
  final ValueChanged<YorksV1RentalExportRegister>? onExport;

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: RentalWorkspaceStrings.text(context, 'refresh'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        PopupMenuButton<String>(
          tooltip: RentalWorkspaceStrings.text(context, 'import'),
          enabled: onImport != null,
          icon: const Icon(YorksDataTransferIcons.importData),
          onSelected: (value) => value == 'template'
              ? onDownloadTemplate?.call()
              : onImport?.call(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'import',
              child: Text(RentalWorkspaceStrings.text(context, 'import')),
            ),
            PopupMenuItem(
              value: 'template',
              child: Text(RentalWorkspaceStrings.text(context, 'template')),
            ),
          ],
        ),
        _ExportRegistersButton(onSelected: onExport),
        PrimaryButton(
          label: RentalWorkspaceStrings.text(context, 'add'),
          icon: Icons.add_rounded,
          isExpanded: false,
          onPressed: onAdd,
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            RentalWorkspaceStrings.text(context, 'title'),
            style: AppTypography.headlineMedium,
          ),
          const SizedBox(height: 12),
          actions,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            RentalWorkspaceStrings.text(context, 'title'),
            style: AppTypography.headlineMedium,
          ),
        ),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }
}

class _ExportRegistersButton extends StatelessWidget {
  const _ExportRegistersButton({required this.onSelected});

  final ValueChanged<YorksV1RentalExportRegister>? onSelected;

  @override
  Widget build(BuildContext context) =>
      PopupMenuButton<YorksV1RentalExportRegister>(
        enabled: onSelected != null,
        tooltip: RentalWorkspaceStrings.text(context, 'export'),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final register in YorksV1RentalExportRegister.values)
            PopupMenuItem(
              value: register,
              child: Text(_rentalExportLabel(register)),
            ),
        ],
        icon: const Icon(YorksDataTransferIcons.exportData),
      );
}

class _RentalSectionRail extends StatelessWidget {
  const _RentalSectionRail({required this.selected, required this.onSelected});

  final _RentalSection selected;
  final ValueChanged<_RentalSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _RentalSection.overview: (
        RentalWorkspaceStrings.text(context, 'overview'),
        Icons.home_outlined,
      ),
      _RentalSection.properties: (
        RentalWorkspaceStrings.text(context, 'properties'),
        Icons.apartment_rounded,
      ),
      _RentalSection.payments: (
        RentalWorkspaceStrings.text(context, 'payments'),
        Icons.receipt_long_outlined,
      ),
      _RentalSection.cheques: (
        RentalWorkspaceStrings.text(context, 'cheques'),
        Icons.account_balance_outlined,
      ),
      _RentalSection.expiry: (
        RentalWorkspaceStrings.text(context, 'expiry'),
        Icons.event_outlined,
      ),
    };
    if (MediaQuery.sizeOf(context).width < _compactAt) {
      return DropdownButtonFormField<_RentalSection>(
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Row(
                children: [
                  Icon(entry.value.$2, size: 18),
                  const SizedBox(width: 10),
                  Text(entry.value.$1),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in labels.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: _RailButton(
                  label: entry.value.$1,
                  icon: entry.value.$2,
                  selected: entry.key == selected,
                  onTap: () => onSelected(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.surfaceContainerLowest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: selected ? Border.all(color: AppColors.blue) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.blue : AppColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: selected ? AppColors.navy : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RentalOverview extends StatefulWidget {
  const _RentalOverview({
    required this.portfolio,
    required this.compact,
    required this.onOpenProperty,
    required this.onOpenSection,
    required this.onOpenAction,
  });

  final YorksV1RentalPortfolio portfolio;
  final bool compact;
  final ValueChanged<YorksV1RentalProperty> onOpenProperty;
  final ValueChanged<_RentalSection> onOpenSection;
  final void Function(YorksV1RentalProperty, YorksRentalAction) onOpenAction;

  @override
  State<_RentalOverview> createState() => _RentalOverviewState();
}

class _RentalOverviewState extends State<_RentalOverview> {
  bool _showAllActions = false;
  YorksV1RentalPortfolio get portfolio => widget.portfolio;
  ValueChanged<YorksV1RentalProperty> get onOpenProperty =>
      widget.onOpenProperty;
  ValueChanged<_RentalSection> get onOpenSection => widget.onOpenSection;

  @override
  Widget build(BuildContext context) {
    if (portfolio.properties.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Icon(
              Icons.apartment_outlined,
              size: 40,
              color: AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              RentalWorkspaceStrings.text(context, 'emptyTitle'),
              style: AppTypography.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              RentalWorkspaceStrings.text(context, 'emptyBody'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
          ],
        ),
      );
    }
    final summary = portfolio.summary;
    final kpis = [
      _KpiData(
        RentalWorkspaceStrings.text(context, 'annualRentRoll'),
        _money.format(summary.annualRentRoll),
        Icons.calendar_month_outlined,
        AppColors.blue,
      ),
      _KpiData(
        'Monthly rent roll',
        _money.format(summary.monthlyRentRoll),
        Icons.apartment_outlined,
        AppColors.blue,
      ),
      _KpiData(
        'Collected this month',
        _money.format(summary.collectedThisMonth),
        Icons.check_rounded,
        AppColors.success,
      ),
      _KpiData(
        'Outstanding rent',
        _money.format(summary.outstanding),
        Icons.warning_amber_rounded,
        AppColors.warning,
      ),
      _KpiData(
        'Occupancy',
        summary.totalProperties == 0
            ? '—'
            : '${summary.occupancyPercent.toStringAsFixed(0)}%',
        Icons.people_outline_rounded,
        AppColors.purple,
      ),
      _KpiData(
        'Security deposits',
        _money.format(summary.securityDeposits),
        Icons.shield_outlined,
        AppColors.navy,
      ),
      _KpiData(
        'Leases to review',
        '${summary.expiringWithin90}',
        Icons.event_outlined,
        AppColors.warning,
      ),
    ];
    final attention =
        portfolio.properties
            .where((property) => rentalActions(property).isNotEmpty)
            .toList()
          ..sort((a, b) {
            final priority = rentalActions(
              a,
            ).first.index.compareTo(rentalActions(b).first.index);
            return priority != 0 ? priority : a.unitCode.compareTo(b.unitCode);
          });
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            final register = _Panel(
              title: 'Property & Rent Register',
              subtitle: RentalWorkspaceStrings.text(context, 'registerHelp'),
              trailing: TextButton(
                onPressed: () => onOpenSection(_RentalSection.properties),
                child: Text(
                  RentalWorkspaceStrings.text(context, 'viewRegister'),
                ),
              ),
              child: _CompactPropertyList(
                properties: portfolio.properties.take(7).toList(),
                onOpen: onOpenProperty,
              ),
            );
            final action = _Panel(
              title: RentalWorkspaceStrings.text(context, 'actionTitle'),
              subtitle: RentalWorkspaceStrings.text(context, 'actionHelp'),
              trailing: _CountPill(
                attention.length,
                tone: attention.isEmpty ? AppColors.success : AppColors.warning,
              ),
              child: attention.isEmpty
                  ? _EmptyPanel(
                      message: RentalWorkspaceStrings.text(
                        context,
                        'actionEmpty',
                      ),
                    )
                  : Column(
                      children: [
                        for (final item in attention.take(
                          _showAllActions ? attention.length : 6,
                        ))
                          _AttentionRow(
                            property: item,
                            onOpen: () => widget.onOpenAction(
                              item,
                              rentalActions(item).first,
                            ),
                          ),
                        if (attention.length > 6)
                          TextButton(
                            onPressed: () => setState(
                              () => _showAllActions = !_showAllActions,
                            ),
                            child: Text(
                              RentalWorkspaceStrings.text(
                                context,
                                _showAllActions
                                    ? 'showFewerActions'
                                    : 'viewAllActions',
                              ).replaceAll('{count}', '${attention.length}'),
                            ),
                          ),
                      ],
                    ),
            );
            if (stacked) {
              return Column(
                children: [action, const SizedBox(height: 16), register],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: action),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: register),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1320
                ? 6
                : constraints.maxWidth >= 860
                ? 3
                : 2;
            final width =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final kpi in kpis)
                  SizedBox(
                    width: width,
                    child: _KpiCard(data: kpi),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Recent Payments',
          subtitle:
              'Every receipt remains attributable to its property and rent period.',
          trailing: TextButton(
            onPressed: () => onOpenSection(_RentalSection.payments),
            child: const Text('View all'),
          ),
          child: _PaymentRows(
            payments: portfolio.recentPayments.take(5).toList(),
          ),
        ),
      ],
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) => LedgerCard(
    padding: const EdgeInsets.all(18),
    child: SizedBox(
      height: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(data.value, style: AppTypography.headlineMedium),
          ),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LedgerCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stackAction =
                constraints.maxWidth < 560 &&
                trailing != null &&
                trailing is! _CountPill;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleLarge),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      if (!stackAction && trailing != null) trailing!,
                    ],
                  ),
                  if (stackAction) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: trailing!,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const Divider(height: 1, color: AppColors.line),
        child,
      ],
    ),
  );
}

class _CompactPropertyList extends StatelessWidget {
  const _CompactPropertyList({required this.properties, required this.onOpen});
  final List<YorksV1RentalProperty> properties;
  final ValueChanged<YorksV1RentalProperty> onOpen;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return const _EmptyPanel(message: 'No rental properties yet');
    }
    return Column(
      children: [
        for (final property in properties)
          _CompactPropertyRow(
            property: property,
            onOpen: () => onOpen(property),
          ),
      ],
    );
  }
}

class _CompactPropertyRow extends StatelessWidget {
  const _CompactPropertyRow({required this.property, required this.onOpen});
  final YorksV1RentalProperty property;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.propertyName,
                      style: AppTypography.titleSmall,
                    ),
                    Text(property.unitCode, style: AppTypography.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RentalStatusChip(
                label: _occupancyText(context, property),
                tone: property.isOccupied ? AppColors.success : AppColors.muted,
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
          if (property.tenantName?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(property.tenantName!, style: AppTypography.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(_rentText(context, property), style: AppTypography.labelLarge),
          if (property.billingSetupPending)
            Text(
              RentalWorkspaceStrings.text(context, 'balancePending'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
            ),
        ],
      ),
    ),
  );
}

String _actionText(
  BuildContext context,
  YorksV1RentalProperty property,
  YorksRentalAction action,
  String suffix,
) => RentalWorkspaceStrings.text(context, 'action_${action.name}$suffix')
    .replaceAll('{amount}', _money.format(property.outstanding))
    .replaceAll(
      '{date}',
      property.leaseEnd == null ? '—' : _day.format(property.leaseEnd!),
    )
    .replaceAll(
      '{fields}',
      property.missingFields
          .where((field) => field != 'billing_start')
          .map((field) => RentalWorkspaceStrings.missingField(context, field))
          .join(', '),
    );

String _actionCta(
  BuildContext context,
  YorksRentalAction action,
) => RentalWorkspaceStrings.text(
  context,
  'action_${action == YorksRentalAction.expiredLease ? 'lease' : action.name}_cta',
);

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.property, required this.onOpen});
  final YorksV1RentalProperty property;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = rentalActions(property);
    final action = actions.first;
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('rental-attention-${property.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${property.unitCode} · ${property.propertyName}',
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _actionText(context, property, action, ''),
                      style: AppTypography.labelLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _actionText(context, property, action, '_help'),
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _actionCta(context, action),
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.blue,
                      ),
                    ),
                    if (actions.length > 1)
                      Text(
                        RentalWorkspaceStrings.text(
                          context,
                          'additionalActions',
                        ).replaceAll('{count}', '${actions.length - 1}'),
                        style: AppTypography.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.count, {required this.tone});
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tone.withValues(alpha: .24)),
    ),
    child: Text(
      '$count',
      style: AppTypography.labelLarge.copyWith(color: tone),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 190,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_rounded,
            size: 34,
            color: AppColors.blueContainerStrong,
          ),
          const SizedBox(height: 12),
          Text(message, style: AppTypography.titleMedium),
        ],
      ),
    ),
  );
}

class _PropertyRegister extends StatefulWidget {
  const _PropertyRegister({
    required this.properties,
    required this.query,
    required this.selectedFilter,
    required this.onFilter,
    required this.onChanged,
    required this.onOpen,
  });
  final List<YorksV1RentalProperty> properties;
  final TextEditingController query;
  final _RentalFilter selectedFilter;
  final ValueChanged<_RentalFilter> onFilter;
  final VoidCallback onChanged;
  final ValueChanged<YorksV1RentalProperty> onOpen;

  @override
  State<_PropertyRegister> createState() => _PropertyRegisterState();
}

class _PropertyRegisterState extends State<_PropertyRegister> {
  List<YorksV1RentalProperty> get filtered {
    final q = widget.query.text.trim().toLowerCase();
    return widget.properties.where((property) {
      if (q.isNotEmpty &&
          ![
            property.unitCode,
            property.propertyName,
            property.location,
            property.tenantName ?? '',
            property.contractNumber ?? '',
          ].any((value) => value.toLowerCase().contains(q))) {
        return false;
      }
      return switch (widget.selectedFilter) {
        _RentalFilter.all => !property.isArchived,
        _RentalFilter.occupied => property.isOccupied && !property.isArchived,
        _RentalFilter.due => property.outstanding > 0 && !property.isArchived,
        _RentalFilter.overdue =>
          property.outstanding > 0 && !property.isArchived,
        _RentalFilter.expiring => property.expiringSoon && !property.isArchived,
        _RentalFilter.vacant =>
          property.occupancy == YorksV1RentalOccupancy.vacant &&
              !property.isArchived,
        _RentalFilter.archived => property.isArchived,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LedgerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: widget.query,
              onChanged: (_) {
                widget.onChanged();
                setState(() {});
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText:
                    'Search property, tenant, location, unit or contract…',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _RentalFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(filter)),
                        selected: filter == widget.selectedFilter,
                        onSelected: (_) => widget.onFilter(filter),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _Panel(
        title: 'Property & Rent Register',
        subtitle:
            '${filtered.length} properties · current position and next controlled action',
        child: filtered.isEmpty
            ? const _EmptyPanel(message: 'No matching rental properties')
            : LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= _tableAt
                    ? _PropertyDesktopTable(
                        properties: filtered,
                        onOpen: widget.onOpen,
                      )
                    : Column(
                        children: [
                          for (final property in filtered)
                            _PropertyMobileCard(
                              property: property,
                              onOpen: () => widget.onOpen(property),
                            ),
                        ],
                      ),
              ),
      ),
    ],
  );
}

String _filterLabel(_RentalFilter filter) => switch (filter) {
  _RentalFilter.all => 'All properties',
  _RentalFilter.occupied => 'Occupied',
  _RentalFilter.due => 'Due / Partial',
  _RentalFilter.overdue => 'Overdue',
  _RentalFilter.expiring => 'Expiring leases',
  _RentalFilter.vacant => 'Vacant',
  _RentalFilter.archived => 'Archived',
};

class _PropertyDesktopTable extends StatelessWidget {
  const _PropertyDesktopTable({required this.properties, required this.onOpen});
  final List<YorksV1RentalProperty> properties;
  final ValueChanged<YorksV1RentalProperty> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _RegisterRow(header: true),
      for (final property in properties)
        _RegisterRow(property: property, onOpen: () => onOpen(property)),
    ],
  );
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow({this.header = false, this.property, this.onOpen});
  final bool header;
  final YorksV1RentalProperty? property;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = property;
    Widget cell(String text, int flex, {TextStyle? style, Widget? child}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child:
                child ??
                Text(
                  text,
                  maxLines: header ? 2 : 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      style ??
                      (header
                          ? AppTypography.labelMedium.copyWith(
                              letterSpacing: .8,
                            )
                          : AppTypography.bodyMedium),
                ),
          ),
        );
    return InkWell(
      onTap: onOpen,
      child: Container(
        constraints: BoxConstraints(minHeight: header ? 44 : 72),
        decoration: BoxDecoration(
          color: header ? AppColors.surfaceContainerLow : Colors.transparent,
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            cell(
              header
                  ? 'PROPERTY'
                  : '${p!.unitCode} · ${p.propertyName}\n${p.location}',
              25,
              style: header ? null : AppTypography.titleSmall,
            ),
            cell(header ? 'TENANT' : _optional(p?.tenantName), 15),
            cell(header ? 'CONTRACT' : _optional(p?.contractNumber), 12),
            cell(
              header ? 'RENT' : (p == null ? '—' : _rentText(context, p)),
              13,
              style: header ? null : AppTypography.labelLarge,
            ),
            cell(
              header
                  ? 'CURRENT PERIOD'
                  : (p!.billingSetupPending
                        ? RentalWorkspaceStrings.text(
                            context,
                            'unconfirmedShort',
                          )
                        : p.isOccupied
                        ? (p.currentDue <= p.currentPaid
                              ? 'Paid'
                              : 'Due / Partial')
                        : _occupancyText(context, p)),
              12,
              style: !header && p!.billingSetupPending
                  ? AppTypography.bodyMedium.copyWith(color: AppColors.warning)
                  : null,
            ),
            cell(
              header
                  ? 'OUTSTANDING'
                  : (p!.billingSetupPending
                        ? RentalWorkspaceStrings.text(
                            context,
                            'unconfirmedShort',
                          )
                        : _money.format(p.outstanding)),
              13,
              style: header
                  ? null
                  : AppTypography.labelLarge.copyWith(
                      color: p!.billingSetupPending
                          ? AppColors.warning
                          : p.outstanding > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
            ),
            cell(
              header
                  ? 'NEXT CDC / PDC'
                  : (p!.nextChequeDate == null
                        ? '—'
                        : '${_day.format(p.nextChequeDate!)}\n${_optional(p.nextChequeNumber)}'),
              13,
            ),
            cell(
              header
                  ? 'LEASE'
                  : (p!.isArchived
                        ? 'Archived'
                        : p.expiringSoon
                        ? 'Expiring'
                        : p.isOccupied
                        ? 'Active'
                        : _occupancyText(context, p)),
              10,
              child: header
                  ? null
                  : _RentalStatusChip(
                      label: p!.isArchived
                          ? 'Archived'
                          : p.expiringSoon
                          ? 'Expiring'
                          : p.isOccupied
                          ? 'Active'
                          : _occupancyText(context, p),
                      tone: p.isArchived
                          ? AppColors.muted
                          : p.expiringSoon
                          ? AppColors.warning
                          : p.isOccupied
                          ? AppColors.success
                          : AppColors.muted,
                    ),
            ),
            SizedBox(
              width: 52,
              child: header
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Open property',
                      onPressed: onOpen,
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyMobileCard extends StatelessWidget {
  const _PropertyMobileCard({required this.property, required this.onOpen});
  final YorksV1RentalProperty property;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${property.unitCode} · ${property.propertyName}',
                  style: AppTypography.titleMedium,
                ),
              ),
              _RentalStatusChip(
                label: _occupancyText(context, property),
                tone: property.isOccupied ? AppColors.success : AppColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${property.propertyType} · ${property.location}',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MiniFact('Rent', _rentText(context, property))),
              Expanded(
                child: _MiniFact(
                  'Outstanding',
                  (property.billingSetupPending
                      ? RentalWorkspaceStrings.text(context, 'unconfirmedShort')
                      : _money.format(property.outstanding)),
                  color: property.billingSetupPending
                      ? AppColors.warning
                      : property.outstanding > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
              ),
              Expanded(
                child: _MiniFact(
                  'Lease end',
                  property.leaseEnd == null
                      ? '—'
                      : _day.format(property.leaseEnd!),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MiniFact extends StatelessWidget {
  const _MiniFact(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTypography.labelSmall),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: color),
      ),
    ],
  );
}

class _PortfolioPayments extends StatelessWidget {
  const _PortfolioPayments({required this.payments});
  final List<YorksV1RentalPayment> payments;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Payment Register',
    subtitle:
        'Receipts are the authoritative payment fact. Cheques alone never mark rent paid.',
    child: _PaymentRows(payments: payments),
  );
}

class _PaymentRows extends StatelessWidget {
  const _PaymentRows({required this.payments});
  final List<YorksV1RentalPayment> payments;
  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const _EmptyPanel(message: 'No payments recorded');
    }
    return Column(
      children: [
        for (final payment in payments)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '${_optional(payment.unitCode)} · ${_optional(payment.propertyName)}',
                    style: AppTypography.titleSmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    payment.periodMonth == null
                        ? '—'
                        : _month.format(payment.periodMonth!),
                  ),
                ),
                Expanded(
                  child: Text(
                    _money.format(payment.amount),
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
                Expanded(child: Text(_day.format(payment.paymentDate))),
                Expanded(child: Text(payment.paymentMethod)),
                Expanded(child: Text(_optional(payment.reference))),
              ],
            ),
          ),
      ],
    );
  }
}

class _PortfolioCheques extends StatelessWidget {
  const _PortfolioCheques({
    required this.cheques,
    required this.onOpenProperty,
  });
  final List<YorksV1RentalCheque> cheques;
  final ValueChanged<YorksV1RentalProperty> onOpenProperty;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'CDC / PDC Register',
    subtitle:
        'Cheque lifecycle is explicit. A cleared cheque still requires a recorded rent receipt.',
    child: cheques.isEmpty
        ? const _EmptyPanel(message: 'No cheques recorded')
        : Column(
            children: [
              for (final cheque in cheques) _ChequePortfolioRow(cheque: cheque),
            ],
          ),
  );
}

class _ChequePortfolioRow extends StatelessWidget {
  const _ChequePortfolioRow({required this.cheque});
  final YorksV1RentalCheque cheque;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(cheque.chequeNumber, style: AppTypography.titleSmall),
        ),
        Expanded(
          child: Text(
            '${_optional(cheque.unitCode)} · ${_optional(cheque.tenantName)}',
          ),
        ),
        Expanded(child: Text(_day.format(cheque.chequeDate))),
        Expanded(
          child: Text(
            _money.format(cheque.amount),
            style: AppTypography.labelLarge,
          ),
        ),
        _RentalStatusChip(
          label: _title(cheque.status.name),
          tone: cheque.status == YorksV1RentalChequeStatus.returned
              ? AppColors.error
              : cheque.status == YorksV1RentalChequeStatus.cleared
              ? AppColors.success
              : AppColors.warning,
        ),
      ],
    ),
  );
}

class _LeaseExpiryRegister extends StatelessWidget {
  const _LeaseExpiryRegister({required this.properties, required this.onOpen});
  final List<YorksV1RentalProperty> properties;
  final ValueChanged<YorksV1RentalProperty> onOpen;
  @override
  Widget build(BuildContext context) {
    final dated =
        properties.where((p) => p.leaseEnd != null && !p.isArchived).toList()
          ..sort((a, b) => a.leaseEnd!.compareTo(b.leaseEnd!));
    return _Panel(
      title: 'Lease Expiry Register',
      subtitle:
          'Renewal notice and lease end dates remain visible before action is required.',
      child: dated.isEmpty
          ? const _EmptyPanel(message: 'No active lease dates')
          : Column(
              children: [
                for (final p in dated)
                  _ExpiryRow(property: p, onOpen: () => onOpen(p)),
              ],
            ),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({required this.property, required this.onOpen});
  final YorksV1RentalProperty property;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final days =
        property.daysToLeaseEnd ??
        property.leaseEnd!.difference(DateTime.now()).inDays;
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '${property.unitCode} · ${property.propertyName}',
                style: AppTypography.titleSmall,
              ),
            ),
            Expanded(child: Text(_optional(property.tenantName))),
            Expanded(child: Text(_day.format(property.leaseEnd!))),
            _RentalStatusChip(
              label: days < 0 ? 'Expired' : '$days days',
              tone: days <= property.renewalNoticeDays
                  ? AppColors.warning
                  : AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}

class _RentalStatusChip extends StatelessWidget {
  const _RentalStatusChip({required this.label, required this.tone});
  final String label;
  final Color tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: AppTypography.labelSmall.copyWith(
        color: tone,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class YorksV1RentalPropertyScreen extends ConsumerStatefulWidget {
  const YorksV1RentalPropertyScreen({
    super.key,
    required this.propertyId,
    this.initialAction,
  });
  final String propertyId;
  final String? initialAction;
  @override
  ConsumerState<YorksV1RentalPropertyScreen> createState() =>
      _YorksV1RentalPropertyScreenState();
}

class _YorksV1RentalPropertyScreenState
    extends ConsumerState<YorksV1RentalPropertyScreen> {
  _PropertySection _section = _PropertySection.overview;
  final _sectionAnchor = GlobalKey();

  void _showSection(_PropertySection section) {
    setState(() => _section = section);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionAnchor.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: 0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectInitialAction();
  }

  @override
  void didUpdateWidget(covariant YorksV1RentalPropertyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        oldWidget.initialAction != widget.initialAction) {
      _selectInitialAction();
    }
  }

  void _selectInitialAction() {
    _section = switch (YorksRentalAction.fromName(widget.initialAction)) {
      YorksRentalAction.rent => _PropertySection.schedule,
      YorksRentalAction.cheque => _PropertySection.cheques,
      _ => _PropertySection.overview,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(yorksV1RentalCommandProvider);
    final detail = ref.watch(yorksV1RentalPropertyProvider(widget.propertyId));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: detail.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RentalFailure(
          onRetry: () =>
              ref.invalidate(yorksV1RentalPropertyProvider(widget.propertyId)),
        ),
        data: (data) => AbsorbPointer(
          absorbing: ref.watch(yorksV1RentalCommandProvider).isLoading,
          child: _PropertyDetailBody(
            detail: data,
            focusedAction: YorksRentalAction.fromName(widget.initialAction),
            sectionAnchor: _sectionAnchor,
            section: _section,
            onSection: _showSection,
            onEdit: () => _edit(context, data),
            onArchive: data.property.isArchived
                ? null
                : () => _archive(context, data),
            onPayment: () => _recordPayment(context, data),
            onCheque: () => _addCheque(context, data),
            onTransitionCheque: (cheque, status) =>
                _transition(context, data, cheque, status),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    YorksV1RentalPropertyDetail detail,
  ) async {
    final savedId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PropertyEditorDialog(
        detail: detail,
        onSave: (input, key) => ref
            .read(yorksV1RentalCommandProvider.notifier)
            .saveProperty(
              input,
              expectedVersion: detail.property.recordVersion,
              idempotencyKey: key,
            ),
        saveError: () => ref.read(yorksV1RentalCommandProvider).error,
      ),
    );
    if (savedId != null && context.mounted) {
      _showResult(context, true, RentalWorkspaceStrings.text(context, 'saved'));
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    YorksV1RentalPropertyDetail detail,
  ) async {
    if (!detail.periods.any((period) => period.balance > 0)) {
      _showResult(
        context,
        false,
        RentalWorkspaceStrings.text(context, 'balancePending'),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(
        detail: detail,
        onSave: (payment) => ref
            .read(yorksV1RentalCommandProvider.notifier)
            .recordPayment(
              propertyId: detail.property.id,
              periodId: payment.period.id,
              amount: payment.amount,
              paymentDate: payment.date,
              paymentMethod: payment.method,
              reference: payment.reference,
              note: payment.note,
            ),
        saveError: () => ref.read(yorksV1RentalCommandProvider).error,
      ),
    );
    if (context.mounted && ok == true) {
      _showResult(
        context,
        true,
        RentalWorkspaceStrings.text(context, 'paymentRecorded'),
      );
    }
  }

  Future<void> _addCheque(
    BuildContext context,
    YorksV1RentalPropertyDetail detail,
  ) async {
    if (detail.property.leaseId == null) {
      _showResult(
        context,
        false,
        'Save an active lease before recording a cheque.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChequeDialog(
        detail: detail,
        onSave: (input) => ref
            .read(yorksV1RentalCommandProvider.notifier)
            .saveCheque(
              propertyId: detail.property.id,
              payload: input.payload,
              expectedVersion: null,
            ),
        saveError: () => ref.read(yorksV1RentalCommandProvider).error,
      ),
    );
    if (context.mounted && ok == true) {
      _showResult(
        context,
        true,
        RentalWorkspaceStrings.text(context, 'chequeRecorded'),
      );
    }
  }

  Future<void> _transition(
    BuildContext context,
    YorksV1RentalPropertyDetail detail,
    YorksV1RentalCheque cheque,
    YorksV1RentalChequeStatus status,
  ) async {
    if (detail.property.isArchived ||
        ref.read(yorksV1RentalCommandProvider).isLoading) {
      return;
    }
    if ({
      YorksV1RentalChequeStatus.returned,
      YorksV1RentalChequeStatus.cancelled,
    }.contains(status)) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChequeReasonDialog(
          cheque: cheque,
          status: status,
          onConfirm: (reason) => ref
              .read(yorksV1RentalCommandProvider.notifier)
              .transitionCheque(
                propertyId: detail.property.id,
                cheque: cheque,
                nextStatus: status,
                reason: reason,
              ),
          saveError: () => ref.read(yorksV1RentalCommandProvider).error,
        ),
      );
      if (context.mounted && confirmed == true) {
        _showResult(
          context,
          true,
          RentalWorkspaceStrings.text(context, 'chequeUpdated'),
        );
      }
      return;
    }
    final ok = await ref
        .read(yorksV1RentalCommandProvider.notifier)
        .transitionCheque(
          propertyId: detail.property.id,
          cheque: cheque,
          nextStatus: status,
        );
    if (context.mounted) {
      _showResult(
        context,
        ok,
        RentalWorkspaceStrings.text(
          context,
          ok ? 'chequeUpdated' : 'chequeNotUpdated',
        ),
      );
    }
  }

  Future<void> _archive(
    BuildContext context,
    YorksV1RentalPropertyDetail detail,
  ) async {
    final archived = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ArchivePropertyDialog(
        property: detail.property,
        onConfirm: (reason) => ref
            .read(yorksV1RentalCommandProvider.notifier)
            .archiveProperty(property: detail.property, reason: reason),
        saveError: () => ref.read(yorksV1RentalCommandProvider).error,
      ),
    );
    if (!context.mounted || archived != true) return;
    _showResult(
      context,
      true,
      RentalWorkspaceStrings.text(context, 'propertyArchived'),
    );
    context.go(RoutePaths.rentals);
  }
}

enum _PropertySection {
  overview,
  schedule,
  payments,
  cheques,
  documents,
  activity,
}

class _PropertyDetailBody extends StatelessWidget {
  const _PropertyDetailBody({
    required this.detail,
    required this.section,
    required this.onSection,
    required this.onEdit,
    required this.onArchive,
    required this.onPayment,
    required this.onCheque,
    required this.onTransitionCheque,
    required this.sectionAnchor,
    this.focusedAction,
  });
  final YorksV1RentalPropertyDetail detail;
  final YorksRentalAction? focusedAction;
  final GlobalKey sectionAnchor;
  final _PropertySection section;
  final ValueChanged<_PropertySection> onSection;
  final VoidCallback onEdit;
  final VoidCallback? onArchive;
  final VoidCallback onPayment;
  final VoidCallback onCheque;
  final void Function(YorksV1RentalCheque, YorksV1RentalChequeStatus)
  onTransitionCheque;

  @override
  Widget build(BuildContext context) {
    final p = detail.property;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactAt;
        return ListView(
          padding: compact
              ? const EdgeInsets.fromLTRB(14, 18, 14, 112)
              : const EdgeInsets.fromLTRB(24, 22, 24, 44),
          children: [
            const _RentalPendingActionsPanel(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RENTAL PROPERTY · ${p.unitCode}',
                        style: AppTypography.eyebrow,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.propertyName,
                        style: compact
                            ? AppTypography.headlineMedium
                            : AppTypography.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            [
                              _termOption(p.propertyType),
                              p.location,
                            ].where((part) => part.isNotEmpty).join(' · '),
                            style: AppTypography.bodyMedium,
                          ),
                          _RentalStatusChip(
                            label: _occupancyText(context, p),
                            tone: p.isOccupied
                                ? AppColors.success
                                : AppColors.muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!compact)
                  Wrap(
                    spacing: 10,
                    children: [
                      SecondaryButton(
                        label: RentalWorkspaceStrings.text(context, 'edit'),
                        icon: Icons.edit_outlined,
                        isExpanded: false,
                        onPressed: onEdit,
                      ),
                      if (onArchive != null)
                        SecondaryButton(
                          label: RentalWorkspaceStrings.text(
                            context,
                            'archive',
                          ),
                          icon: Icons.archive_outlined,
                          isExpanded: false,
                          onPressed: onArchive,
                        ),
                    ],
                  ),
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: RentalWorkspaceStrings.text(context, 'edit'),
                      icon: Icons.edit_outlined,
                      onPressed: onEdit,
                    ),
                  ),
                  if (onArchive != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: SecondaryButton(
                        label: RentalWorkspaceStrings.text(context, 'archive'),
                        icon: Icons.archive_outlined,
                        onPressed: onArchive,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 18),
            _PropertyActionPanel(
              property: p,
              focusedAction: focusedAction,
              onAction: (action) {
                switch (action) {
                  case YorksRentalAction.rent:
                    onSection(_PropertySection.schedule);
                  case YorksRentalAction.cheque:
                    onSection(_PropertySection.cheques);
                  default:
                    onEdit();
                }
              },
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: sectionAnchor,
              child: _PropertySectionRail(
                selected: section,
                onSelected: onSection,
              ),
            ),
            const SizedBox(height: 16),
            if (section == _PropertySection.overview)
              _PropertyOverview(detail: detail)
            else if (section == _PropertySection.schedule)
              _RentSchedule(detail: detail, onPayment: onPayment)
            else if (section == _PropertySection.payments)
              _PropertyPayments(detail: detail, onPayment: onPayment)
            else if (section == _PropertySection.cheques)
              _PropertyCheques(
                detail: detail,
                onAdd: onCheque,
                onTransition: onTransitionCheque,
              )
            else if (section == _PropertySection.documents)
              _LeaseDocuments(detail: detail)
            else
              _RentalActivity(detail: detail),
          ],
        );
      },
    );
  }
}

class _PropertySectionRail extends StatelessWidget {
  const _PropertySectionRail({
    required this.selected,
    required this.onSelected,
  });
  final _PropertySection selected;
  final ValueChanged<_PropertySection> onSelected;
  @override
  Widget build(BuildContext context) {
    final labels = {
      _PropertySection.overview: RentalWorkspaceStrings.text(
        context,
        'overview',
      ),
      _PropertySection.schedule: RentalWorkspaceStrings.text(
        context,
        'schedule',
      ),
      _PropertySection.payments: RentalWorkspaceStrings.text(
        context,
        'payments',
      ),
      _PropertySection.cheques: RentalWorkspaceStrings.text(context, 'cheques'),
      _PropertySection.documents: RentalWorkspaceStrings.text(
        context,
        'documents',
      ),
      _PropertySection.activity: RentalWorkspaceStrings.text(
        context,
        'activity',
      ),
    };
    if (MediaQuery.sizeOf(context).width < _compactAt) {
      return DropdownButtonFormField<_PropertySection>(
        key: ValueKey(selected),
        initialValue: selected,
        isExpanded: true,
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _RailButton(
                label: entry.value,
                icon: switch (entry.key) {
                  _PropertySection.overview => Icons.home_outlined,
                  _PropertySection.schedule => Icons.calendar_month_outlined,
                  _PropertySection.payments => Icons.receipt_long_outlined,
                  _PropertySection.cheques => Icons.account_balance_outlined,
                  _PropertySection.documents => Icons.folder_outlined,
                  _PropertySection.activity => Icons.history_rounded,
                },
                selected: entry.key == selected,
                onTap: () => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _PropertyActionPanel extends StatelessWidget {
  const _PropertyActionPanel({
    required this.property,
    required this.onAction,
    this.focusedAction,
  });
  final YorksV1RentalProperty property;
  final YorksRentalAction? focusedAction;
  final ValueChanged<YorksRentalAction> onAction;

  @override
  Widget build(BuildContext context) {
    final actions = rentalActions(property);
    if (focusedAction != null && actions.remove(focusedAction)) {
      actions.insert(0, focusedAction!);
    }
    if (actions.isEmpty && focusedAction == null) {
      return const SizedBox.shrink();
    }
    return _Panel(
      title: RentalWorkspaceStrings.text(context, 'actionTitle'),
      subtitle: RentalWorkspaceStrings.text(context, 'actionHelp'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (focusedAction != null && !actions.contains(focusedAction))
              Text(RentalWorkspaceStrings.text(context, 'actionResolved')),
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _actionText(context, property, action, ''),
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _actionText(context, property, action, '_help'),
                      style: AppTypography.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      key: ValueKey('rental-action-${action.name}'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: () => onAction(action),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(_actionCta(context, action)),
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

class _PropertyOverview extends StatelessWidget {
  const _PropertyOverview({required this.detail});
  final YorksV1RentalPropertyDetail detail;
  @override
  Widget build(BuildContext context) {
    final p = detail.property;
    String trackedAmount(double amount) => p.billingSetupPending
        ? RentalWorkspaceStrings.text(context, 'unconfirmedShort')
        : _money.format(amount);
    final stats = [
      _KpiData(
        RentalWorkspaceStrings.text(
          context,
          p.isAnnual ? 'annualRent' : 'monthlyRent',
        ),
        p.rentAmount == null ? '—' : _money.format(p.rentAmount),
        Icons.payments_outlined,
        AppColors.navy,
      ),
      _KpiData(
        'Current period paid',
        trackedAmount(p.currentPaid),
        Icons.check_circle_outline,
        p.billingSetupPending ? AppColors.warning : AppColors.success,
      ),
      _KpiData(
        'Total outstanding',
        trackedAmount(p.outstanding),
        Icons.warning_amber_rounded,
        p.billingSetupPending
            ? AppColors.warning
            : p.outstanding > 0
            ? AppColors.error
            : AppColors.success,
      ),
      _KpiData(
        'Security deposit',
        _money.format(p.securityDeposit),
        Icons.shield_outlined,
        AppColors.blue,
      ),
    ];
    return Column(
      children: [
        if (p.billingSetupPending) ...[
          _Notice(
            text: RentalWorkspaceStrings.text(context, 'balancePending'),
            tone: AppColors.warning,
          ),
          const SizedBox(height: 16),
        ],
        if (p.sourceMetadata['original_values'] is Map) ...[
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              title: Text(
                RentalWorkspaceStrings.text(context, 'importedSource'),
              ),
              children: [
                for (final entry
                    in (p.sourceMetadata['original_values'] as Map).entries)
                  ListTile(
                    title: Text(entry.key.toString()),
                    subtitle: Text(entry.value?.toString() ?? '—'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 36) / 4
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final stat in stats)
                  SizedBox(
                    width: width,
                    child: _KpiCard(data: stat),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final current = _InfoPanel(
              title: 'Current Rent Position',
              rows: [
                (
                  'Tenant',
                  p.tenantName?.trim().isNotEmpty == true
                      ? _optional(p.tenantName)
                      : _occupancyText(context, p),
                ),
                (
                  'Current period',
                  detail.periods.isEmpty
                      ? '—'
                      : _month.format(detail.periods.first.periodMonth),
                ),
                ('Amount due', trackedAmount(p.currentDue)),
                ('Amount paid', trackedAmount(p.currentPaid)),
                (
                  'Balance',
                  trackedAmount(math.max(0, p.currentDue - p.currentPaid)),
                ),
                (
                  'Payment method',
                  p.defaultPaymentMethod == null
                      ? '—'
                      : _termOption(p.defaultPaymentMethod!),
                ),
              ],
            );
            final lease = _InfoPanel(
              title: 'Tenant & Lease',
              rows: [
                ('Contact', _optional(p.contactNumber)),
                ('Email', _optional(p.email)),
                ('Trade Licence', _optional(p.tradeLicenceNumber)),
                ('Contract', _optional(p.contractNumber)),
                (
                  'Lease Start',
                  p.leaseStart == null ? '—' : _day.format(p.leaseStart!),
                ),
                (
                  'Lease End',
                  p.leaseEnd == null ? '—' : _day.format(p.leaseEnd!),
                ),
                (
                  'Annual escalation',
                  '${p.annualEscalationPercent.toStringAsFixed(0)}%',
                ),
              ],
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [current, const SizedBox(height: 16), lease],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: current),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: lease),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => _Panel(
    title: title,
    subtitle: 'Authoritative property and contract facts.',
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          for (final row in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1, style: AppTypography.bodySmall)),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.end,
                      style: AppTypography.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _RentSchedule extends StatelessWidget {
  const _RentSchedule({required this.detail, required this.onPayment});
  final YorksV1RentalPropertyDetail detail;
  final VoidCallback onPayment;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Rent Schedule & Payment Ledger',
    subtitle:
        'Monthly dues and receipts remain connected to the property and tenant.',
    trailing: PrimaryButton(
      label: 'Record payment',
      icon: Icons.add_rounded,
      isExpanded: false,
      onPressed: detail.periods.where((p) => p.balance > 0).isEmpty
          ? null
          : onPayment,
    ),
    child: detail.periods.isEmpty
        ? const _EmptyPanel(message: 'No rent periods generated')
        : Column(
            children: [
              for (final period in detail.periods) _PeriodRow(period: period),
            ],
          ),
  );
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.period});
  final YorksV1RentalPeriod period;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _month.format(period.periodMonth),
            style: AppTypography.titleSmall,
          ),
        ),
        Expanded(child: Text(_day.format(period.dueDate))),
        Expanded(child: Text(_money.format(period.amountDue))),
        Expanded(
          child: Text(
            _money.format(period.amountPaid),
            style: AppTypography.labelLarge.copyWith(color: AppColors.success),
          ),
        ),
        Expanded(
          child: Text(
            _money.format(period.balance),
            style: AppTypography.labelLarge.copyWith(
              color: period.balance > 0 ? AppColors.error : AppColors.success,
            ),
          ),
        ),
        _RentalStatusChip(
          label: _periodLabel(period.status),
          tone: _periodTone(period.status),
        ),
      ],
    ),
  );
}

class _PropertyPayments extends StatelessWidget {
  const _PropertyPayments({required this.detail, required this.onPayment});
  final YorksV1RentalPropertyDetail detail;
  final VoidCallback onPayment;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Receipt History',
    subtitle:
        'Individual payment transactions with method, reference and recorder.',
    trailing: PrimaryButton(
      label: 'Record payment',
      icon: Icons.add_rounded,
      isExpanded: false,
      onPressed: detail.periods.where((p) => p.balance > 0).isEmpty
          ? null
          : onPayment,
    ),
    child: _PaymentRows(payments: detail.receipts),
  );
}

class _PropertyCheques extends ConsumerWidget {
  const _PropertyCheques({
    required this.detail,
    required this.onAdd,
    required this.onTransition,
  });
  final YorksV1RentalPropertyDetail detail;
  final VoidCallback onAdd;
  final void Function(YorksV1RentalCheque, YorksV1RentalChequeStatus)
  onTransition;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _Panel(
    title: 'Cheque Register',
    subtitle:
        'Current-dated and post-dated cheques, due dates, deposit and clearance status.',
    trailing: PrimaryButton(
      label: 'Add cheque',
      icon: Icons.add_rounded,
      isExpanded: false,
      onPressed:
          detail.property.leaseId == null ||
              detail.property.isArchived ||
              ref.watch(yorksV1RentalCommandProvider).isLoading
          ? null
          : onAdd,
    ),
    child: detail.cheques.isEmpty
        ? const _EmptyPanel(message: 'No cheques recorded')
        : Column(
            children: [
              for (final cheque in detail.cheques)
                _PropertyChequeRow(
                  cheque: cheque,
                  readOnly: detail.property.isArchived,
                  onTransition: (status) => onTransition(cheque, status),
                ),
            ],
          ),
  );
}

class _PropertyChequeRow extends ConsumerWidget {
  const _PropertyChequeRow({
    required this.cheque,
    required this.onTransition,
    this.readOnly = false,
  });
  final YorksV1RentalCheque cheque;
  final ValueChanged<YorksV1RentalChequeStatus> onTransition;
  final bool readOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(yorksV1RentalCommandProvider).isLoading;
    final actions = switch (cheque.status) {
      YorksV1RentalChequeStatus.scheduled => [
        YorksV1RentalChequeStatus.received,
        YorksV1RentalChequeStatus.cancelled,
      ],
      YorksV1RentalChequeStatus.received => [
        YorksV1RentalChequeStatus.deposited,
        YorksV1RentalChequeStatus.returned,
        YorksV1RentalChequeStatus.cancelled,
      ],
      YorksV1RentalChequeStatus.deposited => [
        YorksV1RentalChequeStatus.cleared,
        YorksV1RentalChequeStatus.returned,
      ],
      YorksV1RentalChequeStatus.returned => [
        YorksV1RentalChequeStatus.received,
        YorksV1RentalChequeStatus.cancelled,
      ],
      _ => <YorksV1RentalChequeStatus>[],
    };
    final status = _RentalStatusChip(
      label: RentalWorkspaceStrings.text(
        context,
        'chequeStatus_${cheque.status.name}',
      ),
      tone: cheque.status == YorksV1RentalChequeStatus.returned
          ? AppColors.error
          : cheque.status == YorksV1RentalChequeStatus.cleared
          ? AppColors.success
          : AppColors.warning,
    );
    final menu = actions.isEmpty || readOnly
        ? const SizedBox.shrink()
        : PopupMenuButton<YorksV1RentalChequeStatus>(
            tooltip: RentalWorkspaceStrings.text(context, 'chequeActions'),
            enabled: !busy,
            onSelected: onTransition,
            itemBuilder: (_) => [
              for (final action in actions)
                PopupMenuItem(
                  value: action,
                  child: Text(
                    RentalWorkspaceStrings.text(
                      context,
                      'chequeAction_${action.name}',
                    ),
                  ),
                ),
            ],
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _compactAt) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cheque.chequeNumber,
                        style: AppTypography.titleSmall,
                      ),
                    ),
                    status,
                    menu,
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${cheque.chequeType} · ${cheque.bankName}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(_day.format(cheque.chequeDate))),
                    Text(
                      _money.format(cheque.amount),
                      style: AppTypography.labelLarge,
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  cheque.chequeNumber,
                  style: AppTypography.titleSmall,
                ),
              ),
              Expanded(child: Text(cheque.chequeType)),
              Expanded(child: Text(cheque.bankName)),
              Expanded(child: Text(_day.format(cheque.chequeDate))),
              Expanded(
                child: Text(
                  _money.format(cheque.amount),
                  style: AppTypography.labelLarge,
                ),
              ),
              status,
              menu,
            ],
          );
        },
      ),
    );
  }
}

class _LeaseDocuments extends ConsumerStatefulWidget {
  const _LeaseDocuments({required this.detail});
  final YorksV1RentalPropertyDetail detail;

  @override
  ConsumerState<_LeaseDocuments> createState() => _LeaseDocumentsState();
}

class _LeaseDocumentsState extends ConsumerState<_LeaseDocuments> {
  bool _working = false;

  YorksV1RentalProperty get _property => widget.detail.property;

  void _refresh() =>
      ref.invalidate(yorksV1RentalDocumentWorkspaceProvider(_property.id));

  Future<void> _upload({YorksV1Document? document}) async {
    if (_working) return;
    final selected = await ref
        .read(yorksV1DocumentFileServiceProvider)
        .selectDocument();
    if (selected == null || !mounted) return;
    setState(() => _working = true);
    try {
      await ref
          .read(yorksV1RentalDocumentsRepositoryProvider)
          .uploadRental(
            YorksV1DocumentUploadInput(
              projectId: _property.id,
              entityType: YorksV1DocumentEntityType.rentalProperty,
              entityId: _property.id,
              classification: YorksV1DocumentClassification.commercial,
              fileName: selected.fileName,
              mimeType: selected.mimeType,
              bytes: selected.bytes,
              idempotencyKey: const Uuid().v4(),
              documentId: document?.id,
            ),
          );
      if (!mounted) return;
      _refresh();
      _showResult(context, true, 'Lease document stored securely.');
    } on YorksV1CommittedViewUnavailable {
      if (mounted) {
        _refresh();
        _showResult(
          context,
          true,
          YorksV1DocumentStrings.uploadConfirmedRefreshPending.primary,
        );
      }
    } catch (_) {
      if (mounted) {
        _showResult(
          context,
          false,
          'The server did not confirm the lease document.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download(YorksV1Document document) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final version = document.currentVersion;
      final bytes = await ref
          .read(yorksV1RentalDocumentsRepositoryProvider)
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
      if (mounted && saved) {
        _showResult(context, true, 'Lease document downloaded.');
      }
    } catch (_) {
      if (mounted) {
        _showResult(context, false, 'Lease document download failed.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _property;
    final workspace = ref.watch(yorksV1RentalDocumentWorkspaceProvider(p.id));
    return LayoutBuilder(
      builder: (context, constraints) {
        final lease = _InfoPanel(
          title: 'Lease Details',
          rows: [
            ('Unit Code', p.unitCode),
            ('Property No.', _optional(p.municipalityNumber)),
            ('Contract No.', _optional(p.contractNumber)),
            ('Contract Type', _optional(p.contractType)),
            ('Contract Status', _optional(p.contractStatus)),
            (
              'Lease Start',
              p.leaseStart == null ? '—' : _day.format(p.leaseStart!),
            ),
            ('Lease End', p.leaseEnd == null ? '—' : _day.format(p.leaseEnd!)),
            ('Monthly Rent', _rentText(context, p)),
            ('Due Day', '${p.monthlyDueDay}'),
            ('Grace Period', '${p.gracePeriodDays} days'),
            ('Renewal Notice', '${p.renewalNoticeDays} days'),
          ],
        );
        final documents = _Panel(
          title: 'Lease Documents',
          subtitle: 'Contracts, licences, PDC registers and renewal notices.',
          trailing: SecondaryButton(
            label: 'Add',
            icon: Icons.add_rounded,
            isExpanded: false,
            onPressed: _working ? null : _upload,
          ),
          child: workspace.when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const _EmptyPanel(
                    message: 'Lease documents could not be loaded',
                  ),
                  SecondaryButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    isExpanded: false,
                    onPressed: _working ? null : _refresh,
                  ),
                ],
              ),
            ),
            data: (value) => Column(
              children: [
                if (value.documents.isEmpty)
                  const _EmptyPanel(message: 'No lease documents attached')
                else
                  for (final document in value.documents)
                    _RentalDocumentRow(
                      document: document,
                      working: _working,
                      onDownload: () => _download(document),
                      onNewVersion: () => _upload(document: document),
                    ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: _RentalTrustBanner(
                    icon: Icons.shield_outlined,
                    title: 'Controlled document boundary',
                    message:
                        'Private, versioned and audit-attributed in Yorks Documents. Maximum file size is 20 MB.',
                  ),
                ),
              ],
            ),
          ),
        );
        if (constraints.maxWidth < 900) {
          return Column(
            children: [lease, const SizedBox(height: 16), documents],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: lease),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: documents),
          ],
        );
      },
    );
  }
}

class _RentalDocumentRow extends StatelessWidget {
  const _RentalDocumentRow({
    required this.document,
    required this.working,
    required this.onDownload,
    required this.onNewVersion,
  });

  final YorksV1Document document;
  final bool working;
  final VoidCallback onDownload;
  final VoidCallback onNewVersion;

  @override
  Widget build(BuildContext context) {
    final version = document.currentVersion;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  version.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  'Revision ${version.revisionNumber} · ${version.uploadedByDisplayName} · ${_day.format(version.uploadedAt)}',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          );
          final actions = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              IconButton(
                tooltip: 'Download ${version.fileName}',
                onPressed: working ? null : onDownload,
                icon: const Icon(Icons.download_outlined),
              ),
              IconButton(
                tooltip: 'Upload a new version',
                onPressed: working ? null : onNewVersion,
                icon: const Icon(Icons.upload_file_outlined),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [details]),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(children: [details, actions]);
        },
      ),
    );
  }
}

class _RentalActivity extends StatelessWidget {
  const _RentalActivity({required this.detail});
  final YorksV1RentalPropertyDetail detail;
  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Rental Activity',
    subtitle:
        'Append-only actions, payments, lease changes and cheque updates.',
    child: detail.activity.isEmpty
        ? const _EmptyPanel(message: 'No rental activity')
        : Column(
            children: [
              for (final event in detail.activity)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.blueContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.timeline_rounded,
                          size: 18,
                          color: AppColors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${event.actorName} · ${_title(event.eventType.replaceAll('_', ' '))}',
                              style: AppTypography.titleSmall,
                            ),
                            Text(
                              '${event.actorRole} · ${DateFormat('dd MMM yyyy, hh:mm a').format(event.occurredAt.toLocal())}',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
  );
}

class _RentalImportPreviewDialog extends StatefulWidget {
  const _RentalImportPreviewDialog({
    required this.preview,
    required this.onConfirm,
  });

  final YorksV1RentalImportPreview preview;
  final Future<bool> Function() onConfirm;

  @override
  State<_RentalImportPreviewDialog> createState() =>
      _RentalImportPreviewDialogState();
}

class _RentalImportPreviewDialogState
    extends State<_RentalImportPreviewDialog> {
  bool _issuesOnly = true;
  bool _busy = false;
  String? _failure;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final rows = _issuesOnly && preview.issues.isNotEmpty
        ? preview.rows.where((row) => row.issues.isNotEmpty).toList()
        : preview.rows;
    final rowIssues = preview.rows.expand((row) => row.issues).toSet();
    final workbookIssues = preview.issues
        .where((issue) => !rowIssues.contains(issue))
        .toList();
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1420, maxHeight: 880),
          child: Column(
            children: [
              _DialogHeader(
                canClose: !_busy,
                title: 'Preview Rental Import',
                subtitle:
                    '${preview.fileName} · Nothing changes until Confirm Import',
              ),
              const Divider(height: 1, color: AppColors.line),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < _compactAt;
                    return ListView(
                      padding: EdgeInsets.all(compact ? 14 : 22),
                      children: [
                        if (workbookIssues.isNotEmpty) ...[
                          _RentalWorkbookIssues(issues: workbookIssues),
                          const SizedBox(height: 16),
                        ],
                        _RentalImportSummary(preview: preview),
                        const SizedBox(height: 16),
                        const _RentalTrustBanner(
                          icon: Icons.monitor_heart_outlined,
                          title: 'Validated before commit',
                          message:
                              'Create and Update use exact Unit Codes. The server revalidates the same rules, locks affected records and applies the workbook once.',
                        ),
                        if (preview.errorCount > 0) ...[
                          const SizedBox(height: 14),
                          _RentalImportAlert(
                            message:
                                '${preview.errorCount} blocking ${preview.errorCount == 1 ? 'issue' : 'issues'} must be resolved in the workbook before import.',
                          ),
                        ],
                        if (_failure != null) ...[
                          const SizedBox(height: 14),
                          _RentalImportAlert(message: _failure!),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${rows.length} of ${preview.rows.length} rows',
                                style: AppTypography.labelLarge,
                              ),
                            ),
                            if (preview.issues.isNotEmpty)
                              FilterChip(
                                label: const Text('Issues first'),
                                selected: _issuesOnly,
                                onSelected: _busy
                                    ? null
                                    : (value) =>
                                          setState(() => _issuesOnly = value),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (rows.isEmpty)
                          const _EmptyPanel(
                            message: 'No import rows were found',
                          )
                        else if (compact)
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RentalImportRowCard(row: row),
                            )
                        else
                          _RentalImportRowsTable(rows: rows),
                      ],
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SecondaryButton(
                      label: 'Choose another file',
                      isExpanded: false,
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                    PrimaryButton(
                      label: _busy
                          ? 'Importing…'
                          : 'Confirm Import (${preview.rows.length})',
                      icon: _busy ? null : Icons.check_rounded,
                      isExpanded: false,
                      onPressed: preview.canConfirm && !_busy ? _confirm : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final confirmed = await widget.onConfirm();
    if (!mounted) return;
    if (confirmed) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _failure =
          'The server did not confirm the import. Nothing is shown as saved; this preview remains available for a safe retry.';
    });
  }
}

class _RentalWorkbookIssues extends StatelessWidget {
  const _RentalWorkbookIssues({required this.issues});

  final List<YorksV1RentalImportIssue> issues;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppColors.errorContainer,
      border: Border.all(color: AppColors.error.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          RentalWorkspaceStrings.text(context, 'workbookIssues'),
          style: AppTypography.titleSmall.copyWith(color: AppColors.error),
        ),
        const SizedBox(height: 6),
        Text(
          RentalWorkspaceStrings.text(context, 'importFormatHelp'),
          style: AppTypography.bodySmall,
        ),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${issue.sheet} · ${issue.rowNumber}: ${issue.message}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
      ],
    ),
  );
}

class _RentalImportSummary extends StatelessWidget {
  const _RentalImportSummary({required this.preview});

  final YorksV1RentalImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'Property rows',
        '${preview.properties.length}',
        Icons.apartment_outlined,
        AppColors.blue,
      ),
      (
        'New / updates',
        '${preview.newPropertyCount} / ${preview.updatedPropertyCount}',
        Icons.add_task_rounded,
        AppColors.success,
      ),
      (
        'Payments',
        '${preview.payments.length}',
        Icons.receipt_long_outlined,
        AppColors.purple,
      ),
      (
        'Cheques',
        '${preview.cheques.length}',
        Icons.account_balance_outlined,
        AppColors.navy,
      ),
      (
        'Need review',
        '${preview.errorCount + preview.warningCount}',
        Icons.warning_amber_rounded,
        preview.errorCount > 0 ? AppColors.error : AppColors.warning,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 5
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: Container(
                  height: 112,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(value.$3, color: value.$4, size: 20),
                      const Spacer(),
                      Text(value.$2, style: AppTypography.headlineSmall),
                      Text(value.$1, style: AppTypography.bodySmall),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RentalTrustBanner extends StatelessWidget {
  const _RentalTrustBanner({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .55),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.blue, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              const SizedBox(height: 3),
              Text(message, style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RentalImportAlert extends StatelessWidget {
  const _RentalImportAlert({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppColors.errorContainer,
      border: Border.all(color: AppColors.error.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
          ),
        ),
      ],
    ),
  );
}

class _RentalImportRowsTable extends StatelessWidget {
  const _RentalImportRowsTable({required this.rows});
  final List<YorksV1RentalImportRow> rows;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        const _RentalImportTableRow(
          cells: ['ROW', 'WORKSHEET', 'RECORD', 'ACTION', 'VALIDATION'],
          header: true,
        ),
        for (final row in rows)
          _RentalImportTableRow(
            cells: [
              '${row.rowNumber}',
              row.sheet,
              row.label,
              _rentalImportStatus(row),
              row.issues.isEmpty
                  ? 'Ready for server validation'
                  : row.issues.map((issue) => issue.message).join(' · '),
            ],
            error: row.hasError,
          ),
      ],
    ),
  );
}

class _RentalImportTableRow extends StatelessWidget {
  const _RentalImportTableRow({
    required this.cells,
    this.header = false,
    this.error = false,
  });

  final List<String> cells;
  final bool header;
  final bool error;

  @override
  Widget build(BuildContext context) {
    const flexes = [1, 2, 4, 2, 5];
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: header
            ? AppColors.surfaceContainer
            : error
            ? AppColors.errorContainer.withValues(alpha: .55)
            : AppColors.surfaceContainerLowest,
        border: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              flex: flexes[index],
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: Text(
                  cells[index],
                  maxLines: header ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: header
                      ? AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        )
                      : AppTypography.bodySmall.copyWith(
                          color: error ? AppColors.error : AppColors.onSurface,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RentalImportRowCard extends StatelessWidget {
  const _RentalImportRowCard({required this.row});
  final YorksV1RentalImportRow row;

  @override
  Widget build(BuildContext context) => LedgerCard(
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${row.sheet} · Row ${row.rowNumber}',
                style: AppTypography.labelLarge,
              ),
            ),
            _RentalStatusChip(
              label: _rentalImportStatus(row),
              tone: row.hasError
                  ? AppColors.error
                  : row.issues.isNotEmpty
                  ? AppColors.warning
                  : AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(row.label, style: AppTypography.titleSmall),
        if (row.issues.isNotEmpty) ...[
          const SizedBox(height: 7),
          for (final issue in row.issues)
            Text(
              issue.message,
              style: AppTypography.bodySmall.copyWith(
                color: issue.severity == YorksV1RentalImportSeverity.error
                    ? AppColors.error
                    : AppColors.warning,
              ),
            ),
        ],
      ],
    ),
  );
}

class _ChequeReasonDialog extends StatefulWidget {
  const _ChequeReasonDialog({
    required this.cheque,
    required this.status,
    required this.onConfirm,
    required this.saveError,
  });
  final YorksV1RentalCheque cheque;
  final YorksV1RentalChequeStatus status;
  final Future<bool> Function(String) onConfirm;
  final Object? Function() saveError;
  @override
  State<_ChequeReasonDialog> createState() => _ChequeReasonDialogState();
}

class _ChequeReasonDialogState extends State<_ChequeReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _busy = false;
  bool _unconfirmed = false;
  String? _errorKey;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        RentalWorkspaceStrings.text(
          context,
          'chequeAction_${widget.status.name}',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.cheque.chequeNumber, style: AppTypography.titleSmall),
              const SizedBox(height: 10),
              Text(RentalWorkspaceStrings.text(context, 'chequeReasonHelp')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                minLines: 3,
                maxLines: 4,
                enabled: !_busy && !_unconfirmed,
                decoration: InputDecoration(
                  labelText: RentalWorkspaceStrings.text(
                    context,
                    'chequeReason',
                  ),
                ),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : RentalWorkspaceStrings.text(
                        context,
                        'chequeReasonRequired',
                      ),
              ),
              if (_errorKey != null) ...[
                const SizedBox(height: 12),
                Text(
                  RentalWorkspaceStrings.text(context, _errorKey!),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(RentalWorkspaceStrings.text(context, 'cancelAction')),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(
            RentalWorkspaceStrings.text(
              context,
              _busy
                  ? 'saving'
                  : _unconfirmed
                  ? 'retryChequeStatus'
                  : 'chequeAction_${widget.status.name}',
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    final confirmed = await widget.onConfirm(_reason.text.trim());
    if (!mounted) return;
    if (confirmed) {
      Navigator.pop(context, true);
      return;
    }
    final failure = widget.saveError();
    final code = failure is YorksV1DomainException ? failure.code : null;
    setState(() {
      _busy = false;
      _unconfirmed =
          _unconfirmed ||
          code == null ||
          code == YorksV1DomainErrorCode.backendUnavailable ||
          code == YorksV1DomainErrorCode.unexpectedResponse;
      _errorKey = _unconfirmed ? 'chequeUnconfirmed' : 'chequeNotUpdated';
    });
  }
}

class _ArchivePropertyDialog extends StatefulWidget {
  const _ArchivePropertyDialog({
    required this.property,
    required this.onConfirm,
    required this.saveError,
  });
  final YorksV1RentalProperty property;
  final Future<bool> Function(String) onConfirm;
  final Object? Function() saveError;

  @override
  State<_ArchivePropertyDialog> createState() => _ArchivePropertyDialogState();
}

class _ArchivePropertyDialogState extends State<_ArchivePropertyDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  bool _unconfirmed = false;
  String? _errorKey;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleDialog(
    title: 'Archive Rental Property',
    subtitle: '${widget.property.unitCode} · ${widget.property.propertyName}',
    busy: _busy,
    body: Column(
      children: [
        const _RentalTrustBanner(
          icon: Icons.archive_outlined,
          title: 'Archive is controlled',
          message:
              'The server blocks archival while outstanding rent, an active lease or an open cheque remains. Historical receipts and activity are preserved.',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _reason,
          enabled: !_busy && !_unconfirmed,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Archive reason',
            hintText:
                'Explain why this property is leaving the active register',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_errorKey != null) ...[
          const SizedBox(height: 12),
          _Notice(
            text: RentalWorkspaceStrings.text(context, _errorKey!),
            tone: AppColors.warning,
          ),
        ],
      ],
    ),
    primaryLabel: RentalWorkspaceStrings.text(
      context,
      _busy
          ? 'saving'
          : _unconfirmed
          ? 'confirmArchive'
          : 'archiveProperty',
    ),
    onPrimary: _busy ? null : _save,
  );

  Future<void> _save() async {
    if (_busy) return;
    if (_reason.text.trim().length < 8) {
      _showResult(
        context,
        false,
        RentalWorkspaceStrings.text(context, 'archiveReasonRequired'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    var confirmed = false;
    Object? failure;
    try {
      confirmed = await widget.onConfirm(_reason.text.trim());
      failure = widget.saveError();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (confirmed) {
      Navigator.pop(context, true);
      return;
    }
    final code = failure is YorksV1DomainException ? failure.code : null;
    setState(() {
      _busy = false;
      _unconfirmed =
          _unconfirmed ||
          code == null ||
          code == YorksV1DomainErrorCode.backendUnavailable ||
          code == YorksV1DomainErrorCode.unexpectedResponse;
      _errorKey = _unconfirmed ? 'archiveUnconfirmed' : 'archiveRejected';
    });
  }
}

class _PropertyEditorDialog extends StatefulWidget {
  const _PropertyEditorDialog({
    this.detail,
    required this.onSave,
    required this.saveError,
  });
  final Future<String?> Function(YorksV1RentalPropertyInput, String) onSave;
  final Object? Function() saveError;
  final YorksV1RentalPropertyDetail? detail;
  @override
  State<_PropertyEditorDialog> createState() => _PropertyEditorDialogState();
}

class _PropertyEditorDialogState extends State<_PropertyEditorDialog> {
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _unconfirmed = false;
  String? _errorKey;
  String? _payloadFingerprint;
  String? _commandKey;
  YorksV1RentalPropertyInput? _pendingInput;
  late final Map<String, TextEditingController> c;
  late YorksV1RentalOccupancy occupancy;
  String propertyType = 'Shop';
  String contractType = 'Tenancy Contract';
  String contractStatus = 'Draft';
  String paymentMethod = 'PDC';
  String frequency = 'Monthly';
  DateTime? signedDate;
  DateTime? leaseStart;
  DateTime? leaseEnd;
  DateTime? billingStart;

  @override
  void initState() {
    super.initState();
    final p = widget.detail?.property;
    occupancy = p?.occupancy ?? YorksV1RentalOccupancy.vacant;
    propertyType = p?.propertyType.isNotEmpty == true
        ? _termOption(p!.propertyType)
        : 'Shop';
    contractType = p?.contractType?.isNotEmpty == true
        ? _termOption(p!.contractType!)
        : 'Tenancy Contract';
    contractStatus = p?.contractStatus?.isNotEmpty == true
        ? _termOption(p!.contractStatus!)
        : 'Draft';
    paymentMethod = p?.defaultPaymentMethod?.isNotEmpty == true
        ? _termOption(p!.defaultPaymentMethod!)
        : 'Bank Transfer';
    frequency = _termOption(p?.paymentFrequency ?? 'monthly');
    billingStart = p?.billingStart;
    signedDate = _from(p, 'signed_date');
    leaseStart = p?.leaseStart;
    leaseEnd = p?.leaseEnd;
    c = {
      'unit': TextEditingController(text: p?.unitCode ?? ''),
      'name': TextEditingController(text: p?.propertyName ?? ''),
      'municipality': TextEditingController(text: p?.municipalityNumber ?? ''),
      'location': TextEditingController(text: p?.location ?? ''),
      'description': TextEditingController(text: p?.description ?? ''),
      'tenant': TextEditingController(text: p?.tenantName ?? ''),
      'trade': TextEditingController(text: p?.tradeLicenceNumber ?? ''),
      'contact': TextEditingController(text: p?.contactNumber ?? ''),
      'email': TextEditingController(text: p?.email ?? ''),
      'contract': TextEditingController(text: p?.contractNumber ?? ''),
      'rent': TextEditingController(
        text: p != null && !p.isAnnual && p.hasRentAmount
            ? p.monthlyRent.toString()
            : '',
      ),
      'annualRent': TextEditingController(
        text: p?.annualRent?.toString() ?? '',
      ),
      'deposit': TextEditingController(text: '${p?.securityDeposit ?? 0}'),
      'due': TextEditingController(text: '${p?.monthlyDueDay ?? 1}'),
      'grace': TextEditingController(text: '${p?.gracePeriodDays ?? 5}'),
      'cheques': TextEditingController(
        text: '${widget.detail?.lease['contract_cheque_count'] ?? 0}',
      ),
      'escalation': TextEditingController(
        text: '${p?.annualEscalationPercent ?? 0}',
      ),
      'renewal': TextEditingController(text: '${p?.renewalNoticeDays ?? 90}'),
      'notes': TextEditingController(
        text: widget.detail?.lease['notes']?.toString() ?? '',
      ),
    };
  }

  DateTime? _from(YorksV1RentalProperty? p, String key) =>
      widget.detail?.lease[key] == null
      ? null
      : DateTime.tryParse(widget.detail!.lease[key].toString());

  @override
  void dispose() {
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 850),
        child: Column(
          children: [
            _DialogHeader(
              canClose: !_saving,
              title: widget.detail == null
                  ? 'Add Rental Property'
                  : 'Edit Rental Property',
              subtitle:
                  'Property, tenant, contract and payment terms are controlled in one record.',
            ),
            Expanded(
              child: ExcludeFocus(
                excluding: _saving || _unconfirmed,
                child: AbsorbPointer(
                  absorbing: _saving || _unconfirmed,
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(22),
                      children: [
                        _FormSection(
                          title: 'Property',
                          children: [
                            _Field(
                              label: 'Unit Code',
                              controller: c['unit']!,
                              required: true,
                            ),
                            _Field(
                              label: 'Property Name',
                              controller: c['name']!,
                              required: true,
                            ),
                            _DropField(
                              label: 'Property Type',
                              value: propertyType,
                              values: const [
                                'Shop',
                                'Warehouse',
                                'Store',
                                'Office',
                                'Office (Store)',
                                'Villa',
                                'Labour Camp',
                                'Other',
                              ],
                              onChanged: (v) =>
                                  setState(() => propertyType = v),
                            ),
                            _Field(
                              label: 'Property / Municipality No.',
                              controller: c['municipality']!,
                            ),
                            _Field(
                              label: 'Location',
                              controller: c['location']!,
                              wide: true,
                            ),
                            _DropField(
                              label: 'Occupancy',
                              value: switch (occupancy) {
                                YorksV1RentalOccupancy.occupied => 'Occupied',
                                YorksV1RentalOccupancy.vacant => 'Vacant',
                                YorksV1RentalOccupancy.unknown => 'Unknown',
                              },
                              values: const ['Occupied', 'Vacant', 'Unknown'],
                              onChanged: (v) => setState(
                                () => occupancy = v == 'Occupied'
                                    ? YorksV1RentalOccupancy.occupied
                                    : v == 'Vacant'
                                    ? YorksV1RentalOccupancy.vacant
                                    : YorksV1RentalOccupancy.unknown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _FormSection(
                          title: 'Tenant',
                          collapsible: true,
                          initiallyExpanded:
                              occupancy == YorksV1RentalOccupancy.occupied ||
                              widget.detail?.property.leaseId != null,
                          key: ValueKey('Tenant-${occupancy.name}'),
                          children: [
                            _Field(
                              label: 'Tenant / Company Name',
                              controller: c['tenant']!,
                            ),
                            _Field(
                              label: 'Trade Licence No.',
                              controller: c['trade']!,
                            ),
                            _Field(
                              label: 'Contact Number',
                              controller: c['contact']!,
                            ),
                            _Field(label: 'Email', controller: c['email']!),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _FormSection(
                          title: 'Tenancy Contract',
                          collapsible: true,
                          initiallyExpanded:
                              occupancy == YorksV1RentalOccupancy.occupied ||
                              widget.detail?.property.leaseId != null,
                          key: ValueKey('Tenancy Contract-${occupancy.name}'),
                          children: [
                            _Field(
                              label: 'Contract No.',
                              controller: c['contract']!,
                            ),
                            _DropField(
                              label: 'Contract Type',
                              value: contractType,
                              values: const [
                                'Tenancy Contract',
                                'Lease',
                                'Licence',
                                'Other',
                              ],
                              onChanged: (v) =>
                                  setState(() => contractType = v),
                            ),
                            _DropField(
                              label: 'Contract Status',
                              value: contractStatus,
                              values: const [
                                'Draft',
                                'Active',
                                'Notice Due',
                                'Expired',
                                'Renewed',
                                'Terminated',
                              ],
                              onChanged: (v) =>
                                  setState(() => contractStatus = v),
                            ),
                            _DateField(
                              label: 'Signed Date',
                              value: signedDate,
                              onChanged: (v) => setState(() => signedDate = v),
                            ),
                            _DateField(
                              label: 'Lease Start',
                              value: leaseStart,
                              onChanged: (v) => setState(() => leaseStart = v),
                            ),
                            _DateField(
                              label: 'Lease End',
                              value: leaseEnd,
                              onChanged: (v) => setState(() => leaseEnd = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _FormSection(
                          title: 'Rent & Payment Terms',
                          collapsible: true,
                          initiallyExpanded:
                              occupancy == YorksV1RentalOccupancy.occupied ||
                              widget.detail?.property.leaseId != null,
                          key: ValueKey(
                            'Rent & Payment Terms-${occupancy.name}',
                          ),
                          children: [
                            _Field(
                              label: RentalWorkspaceStrings.text(
                                context,
                                frequency == 'Annual'
                                    ? 'annualRent'
                                    : 'monthlyRent',
                              ),
                              controller:
                                  c[frequency == 'Annual'
                                      ? 'annualRent'
                                      : 'rent']!,
                              number: true,
                            ),
                            _Field(
                              label: 'Security Deposit (AED)',
                              controller: c['deposit']!,
                              number: true,
                            ),
                            _Field(
                              label: 'Monthly Due Day',
                              controller: c['due']!,
                              number: true,
                            ),
                            _Field(
                              label: 'Grace Period (days)',
                              controller: c['grace']!,
                              number: true,
                            ),
                            _DropField(
                              label: 'Default Payment Method',
                              value: paymentMethod,
                              values: const [
                                'PDC',
                                'CDC',
                                'Bank Transfer',
                                'Cash',
                                'Other',
                              ],
                              onChanged: (v) =>
                                  setState(() => paymentMethod = v),
                            ),
                            _DropField(
                              label: 'Payment Frequency',
                              value: frequency,
                              values: const ['Monthly', 'Annual'],
                              onChanged: (v) => setState(() => frequency = v),
                            ),
                            _Field(
                              label: 'No. of Contract Cheques',
                              controller: c['cheques']!,
                              number: true,
                            ),
                            _DateField(
                              label: RentalWorkspaceStrings.text(
                                context,
                                'billingStart',
                              ),
                              value: billingStart,
                              onChanged: (value) =>
                                  setState(() => billingStart = value),
                            ),
                            _Notice(
                              text: RentalWorkspaceStrings.text(
                                context,
                                'billingStartHelp',
                              ),
                            ),
                            _Field(
                              label: 'Annual Escalation (%)',
                              controller: c['escalation']!,
                              number: true,
                            ),
                            _Field(
                              label: 'Renewal Notice (days)',
                              controller: c['renewal']!,
                              number: true,
                            ),
                            _Field(
                              label: 'Contract / Lease Notes',
                              controller: c['notes']!,
                              wide: true,
                              lines: 3,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_errorKey != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 8,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    RentalWorkspaceStrings.text(context, _errorKey!),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
            _DialogFooter(
              primaryLabel: RentalWorkspaceStrings.text(
                context,
                _saving
                    ? 'saving'
                    : _unconfirmed
                    ? 'retrySave'
                    : widget.detail == null
                    ? 'create'
                    : 'save',
              ),
              onPrimary: _saving ? null : _save,
              canCancel: !_saving,
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    if (!_unconfirmed && !_form.currentState!.validate()) return;
    if (!_unconfirmed &&
        ['due', 'grace', 'cheques', 'renewal'].any(
          (key) =>
              c[key]!.text.trim().isNotEmpty &&
              int.tryParse(c[key]!.text.trim()) == null,
        )) {
      setState(() => _errorKey = 'invalidNumber');
      return;
    }
    if (leaseStart != null &&
        leaseEnd != null &&
        leaseEnd!.isBefore(leaseStart!)) {
      _showResult(context, false, 'Lease end must be after lease start.');
      return;
    }
    final input = _unconfirmed
        ? _pendingInput!
        : YorksV1RentalPropertyInput(
            propertyId: widget.detail?.property.id,
            leaseId: widget.detail?.property.leaseId,
            unitCode: c['unit']!.text.trim(),
            propertyName: c['name']!.text.trim(),
            propertyType: propertyType,
            municipalityNumber: c['municipality']!.text.trim(),
            location: c['location']!.text.trim(),
            description: c['description']!.text.trim(),
            occupancy: occupancy,
            tenantName: c['tenant']!.text.trim(),
            tradeLicenceNumber: c['trade']!.text.trim(),
            contactNumber: c['contact']!.text.trim(),
            email: c['email']!.text.trim(),
            contractNumber: c['contract']!.text.trim(),
            contractType: contractType,
            contractStatus: contractStatus,
            signedDate: signedDate,
            leaseStart: leaseStart,
            leaseEnd: leaseEnd,
            monthlyRent: frequency == 'Monthly'
                ? double.tryParse(c['rent']!.text)
                : null,
            annualRent: frequency == 'Annual'
                ? double.tryParse(c['annualRent']!.text)
                : null,
            billingStart: billingStart,
            sourceMetadata: widget.detail?.property.sourceMetadata,
            securityDeposit: double.tryParse(c['deposit']!.text) ?? 0,
            monthlyDueDay: int.tryParse(c['due']!.text) ?? 1,
            gracePeriodDays: int.tryParse(c['grace']!.text) ?? 0,
            defaultPaymentMethod: paymentMethod,
            paymentFrequency: frequency,
            contractCheques: int.tryParse(c['cheques']!.text) ?? 0,
            annualEscalationPercent:
                double.tryParse(c['escalation']!.text) ?? 0,
            renewalNoticeDays: int.tryParse(c['renewal']!.text) ?? 90,
            notes: c['notes']!.text.trim(),
          );
    final fingerprint = jsonEncode(input.toRpcPayload());
    if (_payloadFingerprint != fingerprint) {
      _payloadFingerprint = fingerprint;
      _commandKey = const Uuid().v4();
    }
    _pendingInput = input;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    String? savedId;
    Object? failure;
    try {
      savedId = await widget.onSave(input, _commandKey!);
      failure = widget.saveError();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (savedId != null) {
      Navigator.of(context).pop(savedId);
      return;
    }
    final code = failure is YorksV1DomainException ? failure.code : null;
    setState(() {
      _unconfirmed =
          _unconfirmed ||
          code == null ||
          code == YorksV1DomainErrorCode.backendUnavailable ||
          code == YorksV1DomainErrorCode.unexpectedResponse;
      _errorKey = _unconfirmed
          ? 'unconfirmed'
          : code == YorksV1DomainErrorCode.conflict
          ? 'conflict'
          : 'saveFailed';
    });
  }
}

class _PaymentInput {
  const _PaymentInput(
    this.period,
    this.amount,
    this.date,
    this.method,
    this.reference,
    this.note,
  );
  final YorksV1RentalPeriod period;
  final double amount;
  final DateTime date;
  final String method;
  final String? reference;
  final String? note;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.detail,
    required this.onSave,
    required this.saveError,
  });
  final YorksV1RentalPropertyDetail detail;
  final Future<bool> Function(_PaymentInput) onSave;
  final Object? Function() saveError;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  bool _busy = false;
  bool _unconfirmed = false;
  String? _errorKey;
  _PaymentInput? _pendingInput;
  final amount = TextEditingController();
  final reference = TextEditingController();
  final note = TextEditingController();
  late YorksV1RentalPeriod period;
  DateTime date = DateTime.now();
  String method = 'Bank Transfer';
  @override
  void initState() {
    super.initState();
    period = widget.detail.periods.firstWhere(
      (p) => p.balance > 0,
      orElse: () => widget.detail.periods.first,
    );
    amount.text = period.balance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleDialog(
    title: 'Record Rent Payment',
    subtitle:
        '${widget.detail.property.unitCode} · ${widget.detail.property.propertyName}',
    busy: _busy,
    body: Column(
      children: [
        if (_errorKey != null) ...[
          _Notice(
            text: RentalWorkspaceStrings.text(context, _errorKey!),
            tone: AppColors.warning,
          ),
          const SizedBox(height: 12),
        ],
        AbsorbPointer(
          absorbing: _busy || _unconfirmed,
          child: ExcludeFocus(
            excluding: _busy || _unconfirmed,
            child: Column(
              children: [
                _Notice(
                  text:
                      'Outstanding balance ${_money.format(period.balance)}. Partial and full receipts are supported.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<YorksV1RentalPeriod>(
                  initialValue: period,
                  decoration: const InputDecoration(labelText: 'Rent Period'),
                  items: [
                    for (final p in widget.detail.periods.where(
                      (p) => p.balance > 0,
                    ))
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${_month.format(p.periodMonth)} · ${_money.format(p.balance)}',
                        ),
                      ),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      setState(() {
                        period = p;
                        amount.text = p.balance.toStringAsFixed(2);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                _TextInput(
                  label: 'Amount Received (AED)',
                  controller: amount,
                  number: true,
                ),
                const SizedBox(height: 12),
                _DateInput(
                  label: 'Payment Date',
                  value: date,
                  onChanged: (v) => setState(() => date = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                  ),
                  items: [
                    for (final v in const [
                      'PDC',
                      'CDC',
                      'Bank Transfer',
                      'Cash',
                      'Other',
                    ])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => setState(() => method = v ?? method),
                ),
                const SizedBox(height: 12),
                _TextInput(
                  label: 'Receipt / Bank / Cheque Reference',
                  controller: reference,
                ),
                const SizedBox(height: 12),
                _TextInput(label: 'Payment Note', controller: note, lines: 3),
              ],
            ),
          ),
        ),
      ],
    ),
    primaryLabel: RentalWorkspaceStrings.text(
      context,
      _busy
          ? 'saving'
          : _unconfirmed
          ? 'confirmPayment'
          : 'recordPayment',
    ),
    onPrimary: _busy ? null : _save,
  );

  Future<void> _save() async {
    if (_busy) return;
    final value = double.tryParse(amount.text);
    if (!_unconfirmed &&
        (value == null ||
            !value.isFinite ||
            value <= 0 ||
            value > period.balance)) {
      _showResult(
        context,
        false,
        'Enter an amount within the outstanding balance.',
      );
      return;
    }
    _pendingInput ??= _PaymentInput(
      period,
      value!,
      date,
      method,
      reference.text.trim(),
      note.text.trim(),
    );
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    bool confirmed = false;
    Object? failure;
    try {
      confirmed = await widget.onSave(_pendingInput!);
      failure = widget.saveError();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (confirmed) {
      Navigator.pop(context, true);
      return;
    }
    final code = failure is YorksV1DomainException ? failure.code : null;
    setState(() {
      _busy = false;
      _unconfirmed =
          _unconfirmed ||
          code == null ||
          code == YorksV1DomainErrorCode.backendUnavailable ||
          code == YorksV1DomainErrorCode.unexpectedResponse;
      _errorKey = _unconfirmed ? 'paymentUnconfirmed' : 'paymentRejected';
      if (!_unconfirmed) _pendingInput = null;
    });
  }
}

class _ChequeInput {
  const _ChequeInput(this.payload);
  final Map<String, Object?> payload;
}

class _ChequeDialog extends StatefulWidget {
  const _ChequeDialog({
    required this.detail,
    required this.onSave,
    required this.saveError,
  });
  final YorksV1RentalPropertyDetail detail;
  final Future<bool> Function(_ChequeInput) onSave;
  final Object? Function() saveError;
  @override
  State<_ChequeDialog> createState() => _ChequeDialogState();
}

class _ChequeDialogState extends State<_ChequeDialog> {
  bool _busy = false;
  bool _unconfirmed = false;
  String? _errorKey;
  _ChequeInput? _pendingInput;
  final number = TextEditingController();
  final bank = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  DateTime date = DateTime.now();
  String type = 'PDC';
  @override
  void dispose() {
    number.dispose();
    bank.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleDialog(
    title: 'Add CDC / PDC Cheque',
    subtitle:
        '${widget.detail.property.unitCode} · ${widget.detail.property.propertyName}',
    busy: _busy,
    body: Column(
      children: [
        if (_errorKey != null) ...[
          _Notice(
            text: RentalWorkspaceStrings.text(context, _errorKey!),
            tone: AppColors.warning,
          ),
          const SizedBox(height: 12),
        ],
        AbsorbPointer(
          absorbing: _busy || _unconfirmed,
          child: ExcludeFocus(
            excluding: _busy || _unconfirmed,
            child: Column(
              children: [
                _TextInput(label: 'Cheque No.', controller: number),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'PDC', child: Text('PDC')),
                    DropdownMenuItem(value: 'CDC', child: Text('CDC')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                _TextInput(label: 'Bank', controller: bank),
                const SizedBox(height: 12),
                _DateInput(
                  label: 'Cheque Date',
                  value: date,
                  onChanged: (v) => setState(() => date = v),
                ),
                const SizedBox(height: 12),
                _TextInput(
                  label: 'Amount (AED)',
                  controller: amount,
                  number: true,
                ),
                const SizedBox(height: 12),
                _TextInput(label: 'Note', controller: note, lines: 2),
              ],
            ),
          ),
        ),
      ],
    ),
    primaryLabel: RentalWorkspaceStrings.text(
      context,
      _busy
          ? 'saving'
          : _unconfirmed
          ? 'confirmCheque'
          : 'addCheque',
    ),
    onPrimary: _busy ? null : _save,
  );

  Future<void> _save() async {
    if (_busy) return;
    final value = double.tryParse(amount.text);
    if (!_unconfirmed &&
        (number.text.trim().isEmpty ||
            bank.text.trim().isEmpty ||
            value == null ||
            !value.isFinite ||
            value <= 0)) {
      _showResult(
        context,
        false,
        RentalWorkspaceStrings.text(context, 'chequeRequired'),
      );
      return;
    }
    _pendingInput ??= _ChequeInput({
      'property_id': widget.detail.property.id,
      'lease_id': widget.detail.property.leaseId,
      'cheque_number': number.text.trim(),
      'cheque_type': type,
      'bank_name': bank.text.trim(),
      'cheque_date': date.toIso8601String().split('T').first,
      'amount': value!,
      'status': 'scheduled',
      'note': note.text.trim(),
    });
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    var confirmed = false;
    Object? failure;
    try {
      confirmed = await widget.onSave(_pendingInput!);
      failure = widget.saveError();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (confirmed) {
      Navigator.pop(context, true);
      return;
    }
    final code = failure is YorksV1DomainException ? failure.code : null;
    setState(() {
      _busy = false;
      _unconfirmed =
          _unconfirmed ||
          code == null ||
          code == YorksV1DomainErrorCode.backendUnavailable ||
          code == YorksV1DomainErrorCode.unexpectedResponse;
      _errorKey = _unconfirmed ? 'chequeSaveUnconfirmed' : 'chequeSaveRejected';
      if (!_unconfirmed) _pendingInput = null;
    });
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    this.canClose = true,
  });
  final bool canClose;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 12, 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.headlineSmall),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTypography.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: canClose ? () => Navigator.pop(context) : null,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _DialogFooter extends StatelessWidget {
  const _DialogFooter({
    required this.primaryLabel,
    required this.onPrimary,
    this.canCancel = true,
  });
  final bool canCancel;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SecondaryButton(
          label: 'Cancel',
          isExpanded: false,
          onPressed: canCancel ? () => Navigator.pop(context) : null,
        ),
        const SizedBox(width: 10),
        PrimaryButton(
          label: primaryLabel,
          isExpanded: false,
          onPressed: onPrimary,
        ),
      ],
    ),
  );
}

class _SimpleDialog extends StatelessWidget {
  const _SimpleDialog({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.busy = false,
  });
  final String title;
  final String subtitle;
  final Widget body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool busy;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(title: title, subtitle: subtitle, canClose: !busy),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: body,
              ),
            ),
            _DialogFooter(
              primaryLabel: primaryLabel,
              onPrimary: onPrimary,
              canCancel: !busy,
            ),
          ],
        ),
      ),
    ),
  );
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    super.key,
    required this.title,
    required this.children,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });
  final bool collapsible;
  final bool initiallyExpanded;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsible) ...[
            Text(title, style: AppTypography.titleMedium),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 12,
                children: [
                  for (final child in children)
                    SizedBox(
                      width: child is _Field && child.wide
                          ? constraints.maxWidth
                          : width,
                      child: child,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
    if (!collapsible) return content;
    return Material(
      color: AppColors.surfaceContainerLowest,
      child: ExpansionTile(
        title: Text(title, style: AppTypography.titleMedium),
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        children: [content],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = false,
    this.number = false,
    this.wide = false,
    this.lines = 1,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final bool number;
  final bool wide;
  final int lines;
  @override
  Widget build(BuildContext context) => _TextInput(
    label: label,
    controller: controller,
    required: required,
    number: number,
    lines: lines,
  );
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.label,
    required this.controller,
    this.required = false,
    this.number = false,
    this.lines = 1,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final bool number;
  final int lines;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    minLines: lines,
    maxLines: lines,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    decoration: InputDecoration(
      labelText: label,
      constraints: MediaQuery.sizeOf(context).width < 600
          ? const BoxConstraints(minHeight: 48)
          : null,
    ),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return '$label is required';
      }
      if (number && value != null && value.trim().isNotEmpty) {
        final parsed = double.tryParse(value.trim());
        if (parsed == null || !parsed.isFinite || parsed < 0) {
          return RentalWorkspaceStrings.text(context, 'invalidNumber');
        }
      }
      return null;
    },
  );
}

class _DropField extends StatelessWidget {
  const _DropField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: values.contains(value) ? value : values.first,
    decoration: InputDecoration(
      labelText: label,
      constraints: MediaQuery.sizeOf(context).width < 600
          ? const BoxConstraints(minHeight: 48)
          : null,
    ),
    items: [
      for (final option in values)
        DropdownMenuItem(
          value: option,
          child: Text(switch (option) {
            'Annual' => RentalWorkspaceStrings.text(context, 'annualOption'),
            'Monthly' => RentalWorkspaceStrings.text(context, 'monthlyOption'),
            'Unknown' => RentalWorkspaceStrings.text(context, 'unknown'),
            _ => option,
          }),
        ),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2150),
      );
      if (date != null) onChanged(date);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(Icons.calendar_today_outlined, size: 18)
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => onChanged(null),
              ),
      ),
      child: Text(value == null ? 'Select date' : _day.format(value!)),
    ),
  );
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final result = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(1990),
        lastDate: DateTime(2150),
      );
      if (result != null) onChanged(result);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(_day.format(value)),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.tone});
  final String text;
  final Color? tone;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: tone?.withValues(alpha: .08) ?? AppColors.successContainer,
      border: Border.all(
        color: (tone ?? AppColors.success).withValues(alpha: .25),
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: AppTypography.bodyMedium.copyWith(
        color: tone == null ? AppColors.onSuccessContainer : AppColors.ink,
      ),
    ),
  );
}

class _RentalFailure extends StatelessWidget {
  const _RentalFailure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: LedgerCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Rental records are unavailable',
              style: AppTypography.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing was changed. Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    ),
  );
}

void _showResult(BuildContext context, bool success, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: success ? AppColors.success : AppColors.error,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _rentalExportLabel(YorksV1RentalExportRegister register) =>
    switch (register) {
      YorksV1RentalExportRegister.propertyLease => 'Property & Lease Register',
      YorksV1RentalExportRegister.rentSchedule => 'Rent Schedule & Outstanding',
      YorksV1RentalExportRegister.payments => 'Payment Receipt Register',
      YorksV1RentalExportRegister.cheques => 'CDC / PDC Register',
      YorksV1RentalExportRegister.leaseExpiry =>
        'Lease Expiry & Renewal Register',
    };

String _rentalExportSlug(YorksV1RentalExportRegister register) =>
    switch (register) {
      YorksV1RentalExportRegister.propertyLease => 'Property_Lease_Register',
      YorksV1RentalExportRegister.rentSchedule => 'Rent_Schedule_Outstanding',
      YorksV1RentalExportRegister.payments => 'Payment_Receipt_Register',
      YorksV1RentalExportRegister.cheques => 'CDC_PDC_Register',
      YorksV1RentalExportRegister.leaseExpiry =>
        'Lease_Expiry_Renewal_Register',
    };

String _rentalImportStatus(YorksV1RentalImportRow row) {
  if (row.hasError) return 'ERROR';
  if (row.issues.isNotEmpty) return 'WARNING';
  return switch (row.action) {
    'create' => 'NEW',
    'update' => 'UPDATE',
    _ => 'READY',
  };
}

String _title(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
String _periodLabel(YorksV1RentalPeriodStatus status) => switch (status) {
  YorksV1RentalPeriodStatus.upcoming => 'Upcoming',
  YorksV1RentalPeriodStatus.due => 'Due',
  YorksV1RentalPeriodStatus.partiallyPaid => 'Partially Paid',
  YorksV1RentalPeriodStatus.paid => 'Paid',
  YorksV1RentalPeriodStatus.overdue => 'Overdue',
};
Color _periodTone(YorksV1RentalPeriodStatus status) => switch (status) {
  YorksV1RentalPeriodStatus.paid => AppColors.success,
  YorksV1RentalPeriodStatus.overdue => AppColors.error,
  YorksV1RentalPeriodStatus.partiallyPaid => AppColors.warning,
  YorksV1RentalPeriodStatus.due => AppColors.warning,
  YorksV1RentalPeriodStatus.upcoming => AppColors.blue,
};

extension on YorksV1RentalProperty {
  bool get expiringSoon =>
      leaseEnd != null &&
      (daysToLeaseEnd ?? leaseEnd!.difference(DateTime.now()).inDays) <=
          renewalNoticeDays;
}

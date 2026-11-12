import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/ledger_card.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_worker_record.dart';
import '../../../../shared/models/yorks_v1_worker_record_strings.dart';
import '../../../../shared/providers/yorks_v1_worker_record_provider.dart';
import 'yorks_v1_worker_import_dialog.dart';
import 'yorks_v1_worker_record_form.dart';

typedef _S = YorksV1WorkerRecordStrings;

/// The Workers register in User Management: the paper sheet's columns, with a
/// photo, for holders of `worker_records.view`.
///
/// It is laid out to sit inside the screen's scrolling list, so it never
/// scrolls vertically itself. Desktop shows the full table; narrow screens
/// show one card per worker.
class YorksV1WorkerRecordsTab extends ConsumerStatefulWidget {
  const YorksV1WorkerRecordsTab({
    super.key,
    required this.language,
    this.canManage = false,
  });

  final AppLanguage language;

  /// Whether the signed-in person holds `worker_records.manage`. The server
  /// rechecks it on every save; this only decides which controls are shown.
  final bool canManage;

  @override
  ConsumerState<YorksV1WorkerRecordsTab> createState() =>
      _YorksV1WorkerRecordsTabState();
}

class _YorksV1WorkerRecordsTabState
    extends ConsumerState<YorksV1WorkerRecordsTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final state = ref.watch(yorksV1WorkerRecordsControllerProvider);
    final controller = ref.read(
      yorksV1WorkerRecordsControllerProvider.notifier,
    );
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final page = state.page;

    return LedgerCard(
      key: const ValueKey('worker-records-tab'),
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(
            language: language,
            compact: compact,
            searchController: _searchController,
            companies: page?.companies ?? const [],
            company: state.query.company,
            status: state.query.status,
            onSearch: controller.setSearch,
            onCompany: controller.setCompany,
            onStatus: controller.setStatus,
          ),
          if (widget.canManage) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: OutlinedButton.icon(
                    key: const ValueKey('worker-records-import'),
                    onPressed: _import,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(_S.importFromExcel.active(language)),
                  ),
                ),
                SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: FilledButton.icon(
                    key: const ValueKey('worker-records-add'),
                    onPressed: () => _edit(null),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_S.addWorker.active(language)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (state.error != null) ...[
            _ErrorNotice(
              language: language,
              error: state.error!,
              onRetry: controller.refresh,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (page == null && state.error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (page != null) ...[
            _Summary(language: language, page: page),
            const SizedBox(height: AppSpacing.sm),
            if (state.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    _S.empty.active(language),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              )
            else if (compact)
              for (final (index, record) in state.items.indexed)
                _WorkerCard(
                  key: ValueKey('worker-record-card-${record.workerId}'),
                  language: language,
                  number: index + 1,
                  record: record,
                  onOpen: () => _open(record),
                )
            else
              _WorkerTable(
                language: language,
                records: state.items,
                totals: page.totals,
                onOpen: _open,
              ),
            if (compact && state.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _CompactTotals(language: language, totals: page.totals),
            ],
            if (state.hasMore) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: OutlinedButton(
                    key: const ValueKey('worker-records-load-more'),
                    onPressed: state.isLoadingMore ? null : controller.loadMore,
                    child: state.isLoadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_S.loadMore.active(language)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _open(YorksV1WorkerRecord record) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (_) => _WorkerRecordDialog(
        language: widget.language,
        record: record,
        canManage: widget.canManage,
      ),
    );
    if (edit == true && mounted) await _edit(record);
  }

  Future<void> _import() async {
    final result = await YorksV1WorkerImportDialog.show(
      context,
      language: widget.language,
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(yorksV1WorkerRecordsControllerProvider.notifier).refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _S.importDone
              .active(widget.language)
              .replaceAll('{created}', '${result.createdCount}')
              .replaceAll('{updated}', '${result.updatedCount}'),
        ),
      ),
    );
  }

  Future<void> _edit(YorksV1WorkerRecord? record) async {
    final saved = await YorksV1WorkerRecordFormDialog.show(
      context,
      language: widget.language,
      record: record,
    );
    if (saved != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Reload from the server: the register shows only confirmed rows.
    final controller = ref.read(
      yorksV1WorkerRecordsControllerProvider.notifier,
    );
    if (record?.photoObjectPath != null) {
      ref.invalidate(yorksV1WorkerPhotoUrlProvider(record!.photoObjectPath!));
    }
    await controller.refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(_S.recordSaved.active(widget.language))),
    );
  }
}

String _statusLabel(YorksV1WorkerStatus status, AppLanguage language) =>
    switch (status) {
      YorksV1WorkerStatus.active => _S.statusActive,
      YorksV1WorkerStatus.inactive => _S.statusInactive,
      YorksV1WorkerStatus.leftCompany => _S.statusLeft,
      YorksV1WorkerStatus.suspended => _S.statusSuspended,
    }.active(language);

String _roleLabel(String? wireRole, AppLanguage language) =>
    switch (YorksV1Role.fromServerClaim(wireRole)) {
      YorksV1Role.projectEngineer => AppStrings.projectEngineerRole,
      YorksV1Role.siteEngineer => AppStrings.siteEngineerRole,
      YorksV1Role.seniorMechanicalEngineer =>
        AppStrings.seniorMechanicalEngineerRole,
      YorksV1Role.projectManager => AppStrings.projectManagerRole,
      YorksV1Role.workshopInCharge => AppStrings.workshopInChargeRole,
      YorksV1Role.documentController => AppStrings.documentControllerRole,
      YorksV1Role.accountant => AppStrings.accountantRole,
      YorksV1Role.pr => AppStrings.prRole,
      YorksV1Role.procurement => AppStrings.procurementRole,
      YorksV1Role.admin => AppStrings.adminRole,
      null => null,
    }?.active(language) ??
    '—';

class _Filters extends StatelessWidget {
  const _Filters({
    required this.language,
    required this.compact,
    required this.searchController,
    required this.companies,
    required this.company,
    required this.status,
    required this.onSearch,
    required this.onCompany,
    required this.onStatus,
  });

  final AppLanguage language;
  final bool compact;
  final TextEditingController searchController;
  final List<String> companies;
  final String? company;
  final YorksV1WorkerStatus? status;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCompany;
  final ValueChanged<YorksV1WorkerStatus?> onStatus;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const ValueKey('worker-records-search'),
      controller: searchController,
      onChanged: onSearch,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: _S.searchHint.active(language),
        isDense: true,
      ),
    );
    // The server matches a company case-insensitively; keep the selection
    // valid while a refresh is replacing the company list.
    final selectedCompany = companies.contains(company) ? company : null;
    final companyFilter = DropdownButtonFormField<String?>(
      key: const ValueKey('worker-records-company'),
      initialValue: selectedCompany,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(_S.allCompanies.active(language)),
        ),
        for (final name in companies)
          DropdownMenuItem<String?>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onCompany,
    );
    final statusFilter = DropdownButtonFormField<YorksV1WorkerStatus?>(
      key: const ValueKey('worker-records-status'),
      initialValue: status,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        DropdownMenuItem<YorksV1WorkerStatus?>(
          value: null,
          child: Text(_S.allStatuses.active(language)),
        ),
        for (final value in YorksV1WorkerStatus.values)
          DropdownMenuItem<YorksV1WorkerStatus?>(
            value: value,
            child: Text(_statusLabel(value, language)),
          ),
      ],
      onChanged: onStatus,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: AppSpacing.sm),
          companyFilter,
          const SizedBox(height: AppSpacing.sm),
          statusFilter,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 5, child: search),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 4, child: companyFilter),
        const SizedBox(width: AppSpacing.md),
        Expanded(flex: 2, child: statusFilter),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.language, required this.page});

  final AppLanguage language;
  final YorksV1WorkerRecordPage page;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodySmall.copyWith(color: AppColors.muted);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          _S.workersCount
              .active(language)
              .replaceAll('{n}', '${page.totalCount}'),
          style: style.copyWith(color: AppColors.ink),
        ),
        Text(
          _S.recordsEntered
              .active(language)
              .replaceAll('{n}', '${page.withRecordCount}'),
          style: style,
        ),
        Text(_S.amountsInAed.active(language), style: style),
      ],
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({
    required this.language,
    required this.error,
    required this.onRetry,
  });

  final AppLanguage language;
  final YorksV1DomainErrorCode error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = switch (error) {
      YorksV1DomainErrorCode.offline => _S.offline,
      YorksV1DomainErrorCode.unauthorized ||
      YorksV1DomainErrorCode.unauthenticated => _S.noAccess,
      _ => _S.couldNotLoad,
    };
    return Container(
      key: const ValueKey('worker-records-error'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              copy.active(language),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onErrorContainer,
              ),
            ),
          ),
          if (error != YorksV1DomainErrorCode.unauthorized)
            TextButton(
              onPressed: onRetry,
              child: Text(_S.retry.active(language)),
            ),
        ],
      ),
    );
  }
}

/// Worker photo, or initials when none is stored or it cannot be loaded.
class YorksV1WorkerPhoto extends ConsumerWidget {
  const YorksV1WorkerPhoto({
    super.key,
    required this.record,
    required this.language,
    this.size = 36,
  });

  final YorksV1WorkerRecord record;
  final AppLanguage language;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = record.photoObjectPath;
    final initials = record.fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.blueContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: (size > 60 ? AppTypography.titleLarge : AppTypography.labelSmall)
            .copyWith(color: AppColors.blue),
      ),
    );
    if (path == null) return fallback;
    final url = ref.watch(yorksV1WorkerPhotoUrlProvider(path)).valueOrNull;
    if (url == null) return fallback;
    return Semantics(
      image: true,
      label: _S.photoOf.active(language).replaceAll('{name}', record.fullName),
      child: ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

const _tableMinWidth = 1080.0;

class _WorkerTable extends StatelessWidget {
  const _WorkerTable({
    required this.language,
    required this.records,
    required this.totals,
    required this.onOpen,
  });

  final AppLanguage language;
  final List<YorksV1WorkerRecord> records;
  final YorksV1WorkerRecordTotals totals;
  final ValueChanged<YorksV1WorkerRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final header = AppTypography.labelSmall.copyWith(color: AppColors.muted);
    final cell = AppTypography.bodySmall.copyWith(color: AppColors.ink);
    final money = cell.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget row(List<Widget> cells, {Color? color, VoidCallback? onTap}) =>
        Material(
          color: color ?? Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: cells),
            ),
          ),
        );
    Widget fixed(double width, Widget child, {bool end = false}) => SizedBox(
      width: width,
      child: Align(
        alignment: end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: child,
      ),
    );
    Widget flex(int flex, Widget child) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
        child: child,
      ),
    );
    Text text(String? value, TextStyle style) => Text(
      value ?? '—',
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final table = Column(
      children: [
        row(color: AppColors.surfaceContainerLow, [
          fixed(44, Text(_S.number.active(language), style: header)),
          flex(5, Text(_S.name.active(language), style: header)),
          flex(5, Text(_S.company.active(language), style: header)),
          flex(3, Text(_S.tradeLicense.active(language), style: header)),
          flex(3, Text(_S.passport.active(language), style: header)),
          fixed(
            96,
            Text(_S.basicSalary.active(language), style: header),
            end: true,
          ),
          fixed(
            84,
            Text(_S.housing.active(language), style: header),
            end: true,
          ),
          fixed(84, Text(_S.others.active(language), style: header), end: true),
          fixed(
            110,
            Text(_S.totalSalary.active(language), style: header),
            end: true,
          ),
        ]),
        for (final (index, record) in records.indexed)
          row(onTap: () => onOpen(record), [
            fixed(44, Text('${index + 1}', style: cell)),
            flex(
              5,
              Row(
                children: [
                  YorksV1WorkerPhoto(record: record, language: language),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      record.fullName,
                      key: ValueKey('worker-record-row-${record.workerId}'),
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            flex(5, text(record.employerCompany, cell)),
            flex(3, text(record.tradeLicenseNo, cell)),
            flex(3, text(record.passportNo, cell)),
            fixed(
              96,
              Text(yorksV1FormatWorkerMoney(record.basicSalary), style: money),
              end: true,
            ),
            fixed(
              84,
              Text(
                yorksV1FormatWorkerMoney(record.housingAllowance),
                style: money,
              ),
              end: true,
            ),
            fixed(
              84,
              Text(
                yorksV1FormatWorkerMoney(record.otherAllowance),
                style: money,
              ),
              end: true,
            ),
            fixed(
              110,
              Text(
                yorksV1FormatWorkerMoney(record.totalSalary),
                style: money.copyWith(fontWeight: FontWeight.w700),
              ),
              end: true,
            ),
          ]),
        row(color: AppColors.surfaceContainerLow, [
          fixed(44, const SizedBox.shrink()),
          flex(
            16,
            Text(
              _S.totals.active(language),
              style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
            ),
          ),
          fixed(
            96,
            Text(yorksV1FormatWorkerMoney(totals.basicSalary), style: money),
            end: true,
          ),
          fixed(
            84,
            Text(
              yorksV1FormatWorkerMoney(totals.housingAllowance),
              style: money,
            ),
            end: true,
          ),
          fixed(
            84,
            Text(yorksV1FormatWorkerMoney(totals.otherAllowance), style: money),
            end: true,
          ),
          fixed(
            110,
            Text(
              yorksV1FormatWorkerMoney(totals.totalSalary),
              key: const ValueKey('worker-records-grand-total'),
              style: money.copyWith(fontWeight: FontWeight.w700),
            ),
            end: true,
          ),
        ]),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _tableMinWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: _tableMinWidth, child: table),
        );
      },
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    super.key,
    required this.language,
    required this.number,
    required this.record,
    required this.onOpen,
  });

  final AppLanguage language;
  final int number;
  final YorksV1WorkerRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              YorksV1WorkerPhoto(record: record, language: language, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. ${record.fullName}',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.employerCompany,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _S.totalSalary.active(language),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    record.hasRecord
                        ? yorksV1FormatWorkerMoney(record.totalSalary)
                        : '—',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CompactTotals extends StatelessWidget {
  const _CompactTotals({required this.language, required this.totals});

  final AppLanguage language;
  final YorksV1WorkerRecordTotals totals;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _S.totals.active(language),
            style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
          ),
        ),
        Text(
          yorksV1FormatWorkerMoney(totals.totalSalary),
          key: const ValueKey('worker-records-grand-total'),
          style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
        ),
      ],
    ),
  );
}

class _WorkerRecordDialog extends StatelessWidget {
  const _WorkerRecordDialog({
    required this.language,
    required this.record,
    required this.canManage,
  });

  final AppLanguage language;
  final YorksV1WorkerRecord record;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    Widget field(
      TranslatableString label,
      String? value, {
      bool bold = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label.active(language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value ?? _S.notEntered.active(language),
              style:
                  (bold ? AppTypography.titleSmall : AppTypography.bodyMedium)
                      .copyWith(
                        color: value == null ? AppColors.muted : AppColors.ink,
                      ),
            ),
          ),
        ],
      ),
    );
    String? money(String? amount) =>
        amount == null ? null : 'AED ${yorksV1FormatWorkerMoney(amount)}';
    final updatedAt = record.updatedAt;

    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        key: const ValueKey('worker-record-dialog'),
        title: Text(_S.workerRecord.active(language)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    YorksV1WorkerPhoto(
                      record: record,
                      language: language,
                      size: 88,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.fullName,
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            record.designation,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (!record.hasRecord)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      _S.noRecordYet.active(language),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                field(_S.workerNumber, record.workerNumber),
                field(_S.status, _statusLabel(record.status, language)),
                field(_S.company, record.employerCompany),
                field(_S.tradeLicense, record.tradeLicenseNo),
                field(_S.passport, record.passportNo),
                const Divider(height: AppSpacing.lg),
                field(_S.basicSalary, money(record.basicSalary)),
                field(_S.housing, money(record.housingAllowance)),
                field(_S.others, money(record.otherAllowance)),
                field(_S.totalSalary, money(record.totalSalary), bold: true),
                if (updatedAt != null) ...[
                  const Divider(height: AppSpacing.lg),
                  Text(
                    _S.lastUpdated
                        .active(language)
                        .replaceAll('{name}', record.updatedByName ?? '—')
                        .replaceAll(
                          '{role}',
                          _roleLabel(record.updatedByRole, language),
                        )
                        .replaceAll(
                          '{date}',
                          DateFormat(
                            'd MMM yyyy, HH:mm',
                          ).format(updatedAt.toLocal()),
                        ),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_S.close.active(language)),
          ),
          if (canManage)
            FilledButton.icon(
              key: const ValueKey('worker-record-edit'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.edit_outlined),
              label: Text(_S.editRecord.active(language)),
            ),
        ],
      ),
    );
  }
}

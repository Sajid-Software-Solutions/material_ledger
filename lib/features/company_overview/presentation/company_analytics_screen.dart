import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_feature_flags.dart';
import '../../../shared/models/yorks_v1_material_request.dart';
import '../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../shared/models/yorks_v1_project.dart';
import '../data/company_analytics_project_options.dart';
import '../../../shared/models/yorks_v1_project_strings.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/models/analytics_event.dart';
import '../../../shared/services/analytics_service.dart';
import '../application/company_analytics_providers.dart';
import '../domain/company_analytics_models.dart';
import '../domain/company_analytics_strings.dart';

part 'company_overview_summary_widgets.dart';
part 'company_analytics_domain_widgets.dart';
part 'company_analytics_shared_widgets.dart';

class CompanyAnalyticsScreen extends ConsumerStatefulWidget {
  const CompanyAnalyticsScreen({
    super.key,
    this.initialProjectId,
    this.initialMonths = 6,
    this.initialDomain = 'company',
  });
  final String? initialProjectId;
  final int initialMonths;
  final String initialDomain;

  @override
  ConsumerState<CompanyAnalyticsScreen> createState() =>
      _CompanyAnalyticsScreenState();
}

/// Compact founder-facing company summary backed by the same protected
/// projection as Analytics. It owns no commands; every action opens a source
/// workspace that performs its normal authorization again.
class CompanyAnalyticsOverviewSummary extends StatefulWidget {
  const CompanyAnalyticsOverviewSummary({
    super.key,
    required this.language,
    required this.projection,
    required this.flags,
  });

  final AppLanguage language;
  final CompanyAnalyticsProjection projection;
  final YorksV1FeatureFlags flags;

  @override
  State<CompanyAnalyticsOverviewSummary> createState() =>
      _CompanyAnalyticsOverviewSummaryState();
}

class _CompanyAnalyticsOverviewSummaryState
    extends State<CompanyAnalyticsOverviewSummary> {
  String? _currencyCode;

  @override
  void didUpdateWidget(covariant CompanyAnalyticsOverviewSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currencies = widget.projection.accounts?.currencyGroups ?? const [];
    if (_currencyCode != null &&
        !currencies.any((group) => group.currencyCode == _currencyCode)) {
      _currencyCode = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final projection = widget.projection;
    final flags = widget.flags;
    final kpis = _CompanyKpiGrid(
      language: language,
      projection: projection,
      flags: flags,
    );
    final actions = _ImportantActionsCard(
      language: language,
      projection: projection,
      flags: flags,
      maxVisible: 4,
    );
    final rental = projection.rentals == null
        ? null
        : _OverviewRentalCard(
            language: language,
            data: projection.rentals!,
            onOpen: () => context.push(RoutePaths.rentals),
          );
    final statusPanels = <Widget>[
      if (projection.accounts != null)
        _OverviewFinancialStatusCard(
          language: language,
          data: projection.accounts!,
          selectedCurrency: _currencyCode,
          onCurrencyChanged: (value) => setState(() => _currencyCode = value),
          onOpen: flags.accounts
              ? () => context.push(RoutePaths.yorksV1Accounts)
              : null,
        ),
      if (projection.materialRequests != null)
        _OverviewMaterialRequestsCard(
          language: language,
          data: projection.materialRequests!,
          onOpen: () => context.push(
            RoutePaths.yorksV1MaterialRequestsPath(
              projectId: projection.projectId,
            ),
          ),
        ),
      if (projection.workforce != null)
        _OverviewWorkforceCard(
          language: language,
          data: projection.workforce!,
          onOpen: flags.workforce
              ? () => context.push(RoutePaths.yorksV1Workforce)
              : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConfirmationLine(language: language, value: projection.generatedAt),
        const SizedBox(height: AppSpacing.md),
        actions,
        const SizedBox(height: AppSpacing.lg),
        kpis,
        if (projection.projects != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ProjectReviewCard(
            language: language,
            data: projection.projects!,
            attentionOnly: true,
          ),
        ],
        if (projection.projects != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _RecentProjectActivity(
            language: language,
            data: projection.projects!,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Disclosure(
          title: Text(CompanyAnalyticsStrings.companyDetails.active(language)),
          children: [
            for (final panel in statusPanels)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: panel,
              ),
            ?rental,
            _CoverageCard(
              language: language,
              projection: projection,
              flags: flags,
            ),
          ],
        ),
      ],
    );
  }
}

class _CompanyAnalyticsScreenState
    extends ConsumerState<CompanyAnalyticsScreen> {
  late CompanyAnalyticsFilters _filters;
  late _AnalyticsDomain _domain;
  bool _refreshing = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _readInitialState();
  }

  void _readInitialState() {
    _filters = CompanyAnalyticsFilters(
      projectId: widget.initialProjectId,
      months:
          CompanyAnalyticsFilters.supportedMonths.contains(widget.initialMonths)
          ? widget.initialMonths
          : 6,
    );
    _domain =
        _AnalyticsDomain.values
            .where((d) => d.name == widget.initialDomain)
            .firstOrNull ??
        _AnalyticsDomain.company;
  }

  @override
  void didUpdateWidget(covariant CompanyAnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialProjectId != widget.initialProjectId ||
        oldWidget.initialMonths != widget.initialMonths ||
        oldWidget.initialDomain != widget.initialDomain) {
      _readInitialState();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _change({CompanyAnalyticsFilters? filters, _AnalyticsDomain? domain}) {
    setState(() {
      _filters = filters ?? _filters;
      _domain = domain ?? _domain;
    });
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.analyticsInteraction,
          properties: {
            AnalyticsProperty.actionType: domain == null ? 'filter' : 'section',
            AnalyticsProperty.source: _domain.name,
          },
        );
    GoRouter.maybeOf(context)?.replace(
      RoutePaths.yorksV1AnalyticsPath(
        projectId: _filters.projectId,
        months: _filters.months,
        domain: _domain.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final flags = ref.watch(yorksV1FeatureFlagsProvider);
    final projects = ref.watch(companyAnalyticsProjectOptionsProvider);
    final projection = ref.watch(companyAnalyticsProjectionProvider(_filters));
    final compact =
        MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;

    return ColoredBox(
      color: compact ? AppColors.mobileSurface : AppColors.surface,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const PageStorageKey('company-analytics-scroll'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                compact
                    ? AppSpacing.mobileScreenHorizontal
                    : AppSpacing.screenHorizontal,
                compact
                    ? AppSpacing.mobileScreenVertical
                    : AppSpacing.screenVertical,
                compact
                    ? AppSpacing.mobileScreenHorizontal
                    : AppSpacing.screenHorizontal,
                AppSpacing.colossal,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.pageMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AnalyticsHeader(
                          language: language,
                          compact: compact,
                          onRefresh: _refreshing ? null : _refresh,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (compact)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              key: const ValueKey('analytics-filters-button'),
                              onPressed: () => _showFilters(language),
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: Text(
                                '${CompanyAnalyticsStrings.filters.active(language)} · '
                                '${_filters.months} ${CompanyAnalyticsStrings.months.active(language)}'
                                '${_filters.projectId == null ? '' : ' · ${CompanyAnalyticsStrings.project.active(language)}'}',
                              ),
                            ),
                          )
                        else
                          _AnalyticsFilters(
                            language: language,
                            compact: false,
                            filters: _filters,
                            projects: projects.isLoading || projects.hasError
                                ? const []
                                : projects.valueOrNull ?? const [],
                            projectsLoading: projects.isLoading,
                            onProjectChanged: (id) => _change(
                              filters: CompanyAnalyticsFilters(
                                projectId: id,
                                months: _filters.months,
                              ),
                            ),
                            onMonthsChanged: (months) => _change(
                              filters: CompanyAnalyticsFilters(
                                projectId: _filters.projectId,
                                months: months,
                              ),
                            ),
                          ),
                        if (projects.hasError)
                          TextButton.icon(
                            onPressed: () => ref.invalidate(
                              companyAnalyticsProjectOptionsProvider,
                            ),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(
                              CompanyAnalyticsStrings.retryProjects.active(
                                language,
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        projection.when(
                          skipLoadingOnRefresh: false,
                          skipLoadingOnReload: false,
                          loading: () => const _AnalyticsLoading(),
                          error: (error, _) => _AnalyticsError(
                            language: language,
                            error: error,
                            onRetry: _refresh,
                          ),
                          data: (data) => _AnalyticsContent(
                            language: language,
                            compact: compact,
                            projection: data,
                            flags: flags,
                            domain: _domain,
                            onDomainChanged: (d) => _change(domain: d),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters(AppLanguage language) async {
    var pending = _filters;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => Consumer(
          builder: (context, sheetRef, _) {
            final options = sheetRef.watch(
              companyAnalyticsProjectOptionsProvider,
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      CompanyAnalyticsStrings.filters.active(language),
                      style: AppTypography.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AnalyticsFilters(
                      language: language,
                      compact: true,
                      filters: pending,
                      projects: options.isLoading || options.hasError
                          ? const []
                          : options.valueOrNull ?? const [],
                      projectsLoading: options.isLoading,
                      onProjectChanged: (id) => update(
                        () => pending = CompanyAnalyticsFilters(
                          projectId: id,
                          months: pending.months,
                        ),
                      ),
                      onMonthsChanged: (months) => update(
                        () => pending = CompanyAnalyticsFilters(
                          projectId: pending.projectId,
                          months: months,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: () => update(
                        () => pending = const CompanyAnalyticsFilters(),
                      ),
                      child: Text(
                        CompanyAnalyticsStrings.resetFilters.active(language),
                      ),
                    ),
                    FilledButton(
                      onPressed: () {
                        _change(filters: pending);
                        Navigator.pop(sheetContext);
                      },
                      child: Text(
                        CompanyAnalyticsStrings.applyFilters.active(language),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final provider = companyAnalyticsProjectionProvider(_filters);
    try {
      ref.invalidate(provider);
      await ref.read(provider.future);
    } catch (_) {
      // The provider renders the typed failure; never leave an unhandled
      // refresh future or retain a previously authorized success on failure.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader({
    required this.language,
    required this.compact,
    required this.onRefresh,
  });

  final AppLanguage language;
  final bool compact;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            CompanyAnalyticsStrings.title.active(language),
            style: compact
                ? AppTypography.headlineMedium
                : AppTypography.headlineLarge,
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          tooltip: CompanyAnalyticsStrings.refresh.active(language),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _AnalyticsFilters extends StatelessWidget {
  const _AnalyticsFilters({
    required this.language,
    required this.compact,
    required this.filters,
    required this.projects,
    required this.projectsLoading,
    required this.onProjectChanged,
    required this.onMonthsChanged,
  });

  final AppLanguage language;
  final bool compact;
  final CompanyAnalyticsFilters filters;
  final List<CompanyAnalyticsProjectOption> projects;
  final bool projectsLoading;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<int> onMonthsChanged;

  @override
  Widget build(BuildContext context) {
    final projectControl = _FilterField(
      label: CompanyAnalyticsStrings.project.active(language),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: filters.projectId,
          icon: projectsLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                CompanyAnalyticsStrings.allProjects.active(language),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (filters.projectId != null &&
                !projects.any((p) => p.id == filters.projectId))
              DropdownMenuItem<String?>(
                value: filters.projectId,
                child: Text(CompanyAnalyticsStrings.project.active(language)),
              ),
            for (final item in projects)
              DropdownMenuItem<String?>(
                value: item.id,
                child: Text(
                  '${item.reference} · ${item.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onProjectChanged,
        ),
      ),
    );
    final periodControl = _FilterField(
      label: CompanyAnalyticsStrings.period.active(language),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: filters.months,
          icon: const Icon(Icons.expand_more_rounded),
          items: [
            for (final months in CompanyAnalyticsFilters.supportedMonths)
              DropdownMenuItem<int>(
                value: months,
                child: Text(
                  '$months ${CompanyAnalyticsStrings.months.active(language)}',
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onMonthsChanged(value);
          },
        ),
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          projectControl,
          const SizedBox(height: AppSpacing.md),
          periodControl,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 2, child: projectControl),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: periodControl),
      ],
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelMedium),
          SizedBox(height: AppSpacing.minTapTarget, child: child),
        ],
      ),
    ),
  );
}

enum _AnalyticsDomain {
  company,
  accounts,
  projects,
  materials,
  workforce,
  rentals,
}

class _AnalyticsContent extends StatefulWidget {
  const _AnalyticsContent({
    required this.language,
    required this.compact,
    required this.projection,
    required this.flags,
    required this.domain,
    required this.onDomainChanged,
  });

  final _AnalyticsDomain domain;
  final ValueChanged<_AnalyticsDomain> onDomainChanged;
  final AppLanguage language;
  final bool compact;
  final CompanyAnalyticsProjection projection;
  final YorksV1FeatureFlags flags;

  @override
  State<_AnalyticsContent> createState() => _AnalyticsContentState();
}

class _AnalyticsContentState extends State<_AnalyticsContent> {
  _AnalyticsDomain get _domain => widget.domain;
  String? _currencyCode;

  @override
  void didUpdateWidget(covariant _AnalyticsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currencies = widget.projection.accounts?.currencyGroups ?? const [];
    if (_currencyCode != null &&
        !currencies.any((group) => group.currencyCode == _currencyCode)) {
      _currencyCode = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    final language = widget.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConfirmationLine(language: language, value: projection.generatedAt),
        const SizedBox(height: AppSpacing.md),
        _DomainSelector(
          language: language,
          compact: widget.compact,
          selected: _domain,
          projection: projection,
          onSelected: widget.onDomainChanged,
        ),

        const SizedBox(height: AppSpacing.sm),
        Text(
          '${CompanyAnalyticsStrings.snapshot.active(language)} · '
          '${CompanyAnalyticsStrings.monthlyMovement.active(language)}: '
          '${projection.months} ${CompanyAnalyticsStrings.months.active(language)} · ${projection.timezone}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        if (_domain == _AnalyticsDomain.company) ...[
          const SizedBox(height: AppSpacing.md),
          _ImportantActionsCard(
            language: language,
            projection: projection,
            flags: widget.flags,
            maxVisible: 4,
          ),
          const SizedBox(height: AppSpacing.lg),
          _CompanyKpiGrid(
            language: language,
            projection: projection,
            flags: widget.flags,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ..._domainSections(language, projection),
        ...[
          const SizedBox(height: AppSpacing.lg),
          _Disclosure(
            title: Text(CompanyAnalyticsStrings.coverageTitle.active(language)),
            children: [
              _CoverageCard(
                language: language,
                projection: projection,
                flags: widget.flags,
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _domainSections(
    AppLanguage language,
    CompanyAnalyticsProjection projection,
  ) {
    final projects = projection.projects;
    final requests = projection.materialRequests;
    final accounts = projection.accounts;
    final workforce = projection.workforce;
    final rentals = projection.rentals;
    if (_domain == _AnalyticsDomain.company) {
      return [
        if (projects != null)
          _ProjectReviewCard(
            language: language,
            data: projects,
            attentionOnly: true,
          ),
      ];
    }
    final sections = <Widget>[];

    void add(Widget child) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: AppSpacing.lg));
      }
      sections.add(child);
    }

    if ((_domain == _AnalyticsDomain.company ||
            _domain == _AnalyticsDomain.accounts) &&
        accounts != null) {
      add(
        _AccountsPositionCard(
          language: language,
          data: accounts,
          selectedCurrency: _currencyCode,
          onCurrencyChanged: (value) => setState(() => _currencyCode = value),
          onOpen: widget.flags.accounts
              ? () => context.push(RoutePaths.yorksV1Accounts)
              : null,
        ),
      );
    }
    if (_domain == _AnalyticsDomain.company ||
        _domain == _AnalyticsDomain.projects) {
      if (projects != null) {
        add(_ProjectReviewCard(language: language, data: projects));
      } else if (_domain == _AnalyticsDomain.projects) {
        add(_DomainUnavailableCard(language: language));
      }
    }
    if (_domain == _AnalyticsDomain.company ||
        _domain == _AnalyticsDomain.materials) {
      if (requests != null) {
        add(
          _MaterialPipelineCard(
            language: language,
            data: requests,
            projectId: projection.projectId,
          ),
        );
        add(_MonthlyMovementCard(language: language, data: requests));
      } else if (_domain == _AnalyticsDomain.materials) {
        add(_DomainUnavailableCard(language: language));
      }
    }
    if ((_domain == _AnalyticsDomain.company ||
            _domain == _AnalyticsDomain.workforce) &&
        workforce != null) {
      add(
        _WorkforceEvidenceCard(
          language: language,
          data: workforce,
          onOpen: widget.flags.workforce
              ? () => context.push(RoutePaths.yorksV1Workforce)
              : null,
        ),
      );
    } else if (_domain == _AnalyticsDomain.workforce) {
      add(_DomainUnavailableCard(language: language));
    }
    if ((_domain == _AnalyticsDomain.company ||
            _domain == _AnalyticsDomain.rentals) &&
        rentals != null) {
      add(
        _RentalBusinessCard(
          language: language,
          data: rentals,
          onOpen: () => context.push(RoutePaths.rentals),
        ),
      );
    } else if (_domain == _AnalyticsDomain.rentals) {
      add(_DomainUnavailableCard(language: language));
    }
    if (sections.isEmpty) add(_DomainUnavailableCard(language: language));
    return sections;
  }
}

class _DomainSelector extends StatelessWidget {
  const _DomainSelector({
    required this.language,
    required this.compact,
    required this.selected,
    required this.projection,
    required this.onSelected,
  });

  final AppLanguage language;
  final bool compact;
  final _AnalyticsDomain selected;
  final CompanyAnalyticsProjection projection;
  final ValueChanged<_AnalyticsDomain> onSelected;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _FilterField(
        label: CompanyAnalyticsStrings.section.active(language),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_AnalyticsDomain>(
            key: const ValueKey('company-analytics-domain-dropdown'),
            isExpanded: true,
            value: selected,
            icon: const Icon(Icons.expand_more_rounded),
            items: [
              for (final domain in _AnalyticsDomain.values)
                DropdownMenuItem<_AnalyticsDomain>(
                  value: domain,
                  child: Row(
                    children: [
                      Icon(_icon(domain), size: 18, color: _stateColor(domain)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _label(domain),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final domain in _AnalyticsDomain.values) ...[
            ChoiceChip(
              selected: selected == domain,
              onSelected: (_) => onSelected(domain),
              avatar: Icon(
                _icon(domain),
                size: 18,
                color: selected == domain
                    ? AppColors.blue
                    : _stateColor(domain),
              ),
              label: Text(_label(domain)),
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              side: BorderSide(
                color: selected == domain ? AppColors.blue : AppColors.line,
              ),
            ),
            if (domain != _AnalyticsDomain.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  String _label(_AnalyticsDomain domain) => switch (domain) {
    _AnalyticsDomain.company => CompanyAnalyticsStrings.company.active(
      language,
    ),
    _AnalyticsDomain.accounts => CompanyAnalyticsStrings.accountsSource.active(
      language,
    ),
    _AnalyticsDomain.projects => CompanyAnalyticsStrings.projectSource.active(
      language,
    ),
    _AnalyticsDomain.materials => CompanyAnalyticsStrings.requestsSource.active(
      language,
    ),
    _AnalyticsDomain.workforce =>
      CompanyAnalyticsStrings.workforceSource.active(language),
    _AnalyticsDomain.rentals => CompanyAnalyticsStrings.rentalsSource.active(
      language,
    ),
  };

  IconData _icon(_AnalyticsDomain domain) => switch (domain) {
    _AnalyticsDomain.company => Icons.space_dashboard_outlined,
    _AnalyticsDomain.accounts => Icons.account_balance_wallet_outlined,
    _AnalyticsDomain.projects => Icons.account_tree_outlined,
    _AnalyticsDomain.materials => Icons.assignment_outlined,
    _AnalyticsDomain.workforce => Icons.groups_outlined,
    _AnalyticsDomain.rentals => Icons.apartment_outlined,
  };

  Color _stateColor(_AnalyticsDomain domain) {
    final key = switch (domain) {
      _AnalyticsDomain.company => null,
      _AnalyticsDomain.accounts => 'accounts',
      _AnalyticsDomain.projects => 'projects',
      _AnalyticsDomain.materials => 'material_requests',
      _AnalyticsDomain.workforce => 'workforce',
      _AnalyticsDomain.rentals => 'rentals',
    };
    final state = key == null ? null : projection.coverage[key]?.state;
    return switch (state) {
      CompanyAnalyticsCoverageState.available || null => AppColors.success,
      CompanyAnalyticsCoverageState.sourceOnly => AppColors.blue,
      CompanyAnalyticsCoverageState.denied => AppColors.muted,
    };
  }
}

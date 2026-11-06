import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/analytics_event.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_notification_provider.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_portfolio_controller.dart';
import '../../application/accounts_portfolio_providers.dart';
import '../../application/accounts_providers.dart';
import '../../application/accounts_receivables_controller.dart';
import '../../application/accounts_receivables_providers.dart';
import '../../application/accounts_records_providers.dart';
import '../../application/accounts_supplier_controller.dart';
import '../../application/accounts_supplier_providers.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_models.dart';
import '../../domain/accounts_portfolio_models.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_records_models.dart';
import '../../domain/accounts_supplier_models.dart';
import '../widgets/yorks_accounts_baseline_action_sheet.dart';
import '../widgets/yorks_accounts_billing_workbench.dart';
import '../widgets/yorks_accounts_progress_action_sheet.dart';
import '../widgets/yorks_accounts_receivables_action_sheets.dart';
import '../widgets/yorks_accounts_records_views.dart';
import '../widgets/yorks_accounts_supplier_action_sheets.dart';
import 'yorks_accounts_control_centre_overview.dart';
import 'yorks_project_accounts_overview.dart';

class YorksAccountsPortfolioScreen extends ConsumerStatefulWidget {
  const YorksAccountsPortfolioScreen({
    super.key,
    this.controlCentre = false,
    this.billingProgress = false,
  }) : assert(!(controlCentre && billingProgress));

  final bool controlCentre;
  final bool billingProgress;

  @override
  ConsumerState<YorksAccountsPortfolioScreen> createState() =>
      _YorksAccountsPortfolioScreenState();
}

class _YorksAccountsPortfolioScreenState
    extends ConsumerState<YorksAccountsPortfolioScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  String? _commercialState;
  String? _dueState;
  String? _paymentState;
  bool _workspaceTracked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  YorksAccountsPortfolioFilters get _filters => YorksAccountsPortfolioFilters(
    search: _searchController.text,
    commercialState: _commercialState,
    dueState: _dueState,
    paymentState: _paymentState,
  );

  void _load() {
    if (!_workspaceTracked) {
      _workspaceTracked = true;
      ref
          .read(analyticsServiceProvider)
          .capture(
            AnalyticsEvent.accountsWorkspaceViewed,
            properties: {
              AnalyticsProperty.source: 'accounts_office',
              AnalyticsProperty.entryPoint: widget.controlCentre
                  ? 'overview'
                  : widget.billingProgress
                  ? 'billing_progress'
                  : 'project_accounts',
            },
          );
    }
    ref.read(yorksAccountsPortfolioControllerProvider.notifier).load(_filters);
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      _trackFilters();
      _load();
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _commercialState = null;
      _dueState = null;
      _paymentState = null;
    });
    _trackFilters();
    _load();
  }

  void _applyFilters({
    required String? commercialState,
    required String? dueState,
    required String? paymentState,
  }) {
    setState(() {
      _commercialState = commercialState;
      _dueState = dueState;
      _paymentState = paymentState;
    });
    _trackFilters();
    _load();
  }

  void _trackFilters() {
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsFilterChanged,
          properties: {
            AnalyticsProperty.source: 'accounts_portfolio',
            AnalyticsProperty.entryPoint: widget.controlCentre
                ? 'overview'
                : widget.billingProgress
                ? 'billing_progress'
                : 'project_accounts',
            AnalyticsProperty.listFilter: _activeFilterCount == 0
                ? 'none'
                : _activeFilterCount == 1
                ? 'single'
                : 'multiple',
          },
        );
  }

  int get _activeFilterCount => [
    _commercialState,
    _dueState,
    _paymentState,
    _searchController.text.trim().isEmpty ? null : _searchController.text,
  ].whereType<String>().length;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksAccountsPortfolioControllerProvider);
    if (state.status == YorksAccountsViewStatus.idle &&
        state.projection == null) {
      // Permission/session bootstrap can legitimately recreate the protected
      // controller while this route remains mounted. Re-arm the initial load
      // for that fresh controller so `idle` can never become a permanent
      // skeleton.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(yorksAccountsPortfolioControllerProvider);
        if (current.status == YorksAccountsViewStatus.idle &&
            current.projection == null) {
          _load();
        }
      });
    }
    final projection = state.projection;
    final loading = state.status == YorksAccountsViewStatus.loading;
    if (widget.controlCentre) {
      return YorksAccountsControlCentreOverview(
        state: state,
        language: language,
        searchController: _searchController,
        commercialState: _commercialState,
        dueState: _dueState,
        paymentState: _paymentState,
        activeFilterCount: _activeFilterCount,
        onSearchChanged: _searchChanged,
        onApplyFilters: _applyFilters,
        onClearFilters: _clearFilters,
        onRetry: _load,
        onRefresh: () => ref
            .read(yorksAccountsPortfolioControllerProvider.notifier)
            .load(_filters),
        onLoadMore: () => ref
            .read(yorksAccountsPortfolioControllerProvider.notifier)
            .loadMore(),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(yorksAccountsPortfolioControllerProvider.notifier)
            .load(_filters),
        child: CustomScrollView(
          key: PageStorageKey(
            widget.controlCentre
                ? 'accounts-control-centre-scroll'
                : widget.billingProgress
                ? 'accounts-billing-progress-scroll'
                : 'accounts-portfolio-scroll',
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.xxl,
                AppSpacing.xxl,
                AppSpacing.colossal,
              ),
              sliver: SliverList.list(
                children: [
                  _AccountsHero(
                    eyebrow: _t(language, 'commercial_control'),
                    title: _t(
                      language,
                      widget.controlCentre
                          ? 'control_centre_title'
                          : widget.billingProgress
                          ? 'billing_progress_title'
                          : 'portfolio_title',
                    ),
                    body: _t(
                      language,
                      widget.controlCentre
                          ? 'control_centre_body'
                          : widget.billingProgress
                          ? 'billing_progress_body'
                          : 'portfolio_body',
                    ),
                    badge: projection?.actorExactRole ?? '',
                  ),
                  if (projection?.canExport == true) ...[
                    const SizedBox(height: AppSpacing.md),
                    YorksAccountsReportActions(
                      kind: YorksAccountsReportKind.portfolio,
                      language: language,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (projection != null)
                    _PortfolioKpis(
                      totals: projection.totals,
                      language: language,
                      onFilter: (value) {
                        setState(() => _commercialState = value);
                        _load();
                      },
                    )
                  else if (loading)
                    const _KpiSkeleton(count: 8),
                  const SizedBox(height: AppSpacing.lg),
                  _PortfolioFilters(
                    language: language,
                    searchController: _searchController,
                    commercialState: _commercialState,
                    dueState: _dueState,
                    paymentState: _paymentState,
                    activeFilterCount: _activeFilterCount,
                    onSearchChanged: _searchChanged,
                    onApply: _applyFilters,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (projection != null && projection.actionQueue.isNotEmpty)
                    _ActionQueue(
                      items: projection.actionQueue,
                      language: language,
                    ),
                  if (projection != null && projection.actionQueue.isNotEmpty)
                    const SizedBox(height: AppSpacing.lg),
                  _PortfolioRegister(
                    state: state,
                    language: language,
                    onRetry: _load,
                    onClearFilters: _clearFilters,
                    onLoadMore: () => ref
                        .read(yorksAccountsPortfolioControllerProvider.notifier)
                        .loadMore(),
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

enum YorksProjectAccountsTab {
  overview,
  billing,
  invoices,
  receiptsPdc,
  supplierBills,
  documents,
  activity,
}

class YorksProjectAccountsScreen extends ConsumerStatefulWidget {
  const YorksProjectAccountsScreen({
    super.key,
    required this.projectId,
    this.initialTab = YorksProjectAccountsTab.overview,
  });

  final String projectId;
  final YorksProjectAccountsTab initialTab;

  @override
  ConsumerState<YorksProjectAccountsScreen> createState() =>
      _YorksProjectAccountsScreenState();
}

class _YorksProjectAccountsScreenState
    extends ConsumerState<YorksProjectAccountsScreen> {
  String? _openedNotificationTarget;
  RouteInformationProvider? _notificationRouteInformation;
  int _activeTabLoads = 0;
  bool _workspaceTracked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final information = GoRouter.maybeOf(context)?.routeInformationProvider;
    if (!identical(information, _notificationRouteInformation)) {
      _notificationRouteInformation?.removeListener(
        _scheduleNotificationTarget,
      );
      _notificationRouteInformation = information;
      information?.addListener(_scheduleNotificationTarget);
    }
    _scheduleNotificationTarget();
  }

  Uri? _notificationPageUri() =>
      GoRouter.maybeOf(context) == null ? null : GoRouterState.of(context).uri;

  void _scheduleNotificationTarget() {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final uri = _notificationPageUri();
    if (uri != null &&
        uri.path.startsWith('/yorks/projects/${widget.projectId}/accounts/') &&
        uri.toString() != _openedNotificationTarget &&
        uri.queryParameters.keys.any(
          (key) => const ['invoice_id', 'claim_id', 'bill_id'].contains(key),
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _notificationRouteInformation?.removeListener(_scheduleNotificationTarget);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant YorksProjectAccountsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.initialTab != widget.initialTab) {
      if (oldWidget.projectId != widget.projectId) _workspaceTracked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load({bool force = false}) async {
    final overviewProvider = yorksAccountsProjectOverviewControllerProvider(
      widget.projectId,
    );
    if (force || ref.read(overviewProvider).projection == null) {
      await ref.read(overviewProvider.notifier).load();
    }
    if (!mounted) return;
    if (!_workspaceTracked) {
      _workspaceTracked = true;
      ref
          .read(analyticsServiceProvider)
          .capture(
            AnalyticsEvent.accountsWorkspaceViewed,
            properties: {
              AnalyticsProperty.source: 'project_workspace',
              AnalyticsProperty.entryPoint: widget.initialTab.name,
            },
          );
    }
    await _loadTab(widget.initialTab, force: force);
    if (mounted) await _openNotificationTarget();
  }

  Future<void> _openNotificationTarget() async {
    final uri = _notificationPageUri();
    if (uri == null ||
        ModalRoute.of(context)?.isCurrent == false ||
        !uri.path.startsWith('/yorks/projects/${widget.projectId}/accounts/') ||
        _openedNotificationTarget == uri.toString()) {
      return;
    }
    _openedNotificationTarget = uri.toString();
    final owner = ref.read(yorksV1AuthUserIdProvider);
    final projectId = widget.projectId;
    final browserLocation = _notificationRouteInformation?.value.uri;
    bool stillCurrent() =>
        mounted &&
        owner == ref.read(yorksV1AuthUserIdProvider) &&
        projectId == widget.projectId &&
        _notificationPageUri() == uri &&
        _notificationRouteInformation?.value.uri == browserLocation;
    String? id(String key) {
      final value = uri.queryParameters[key];
      return value != null &&
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                caseSensitive: false,
              ).hasMatch(value)
          ? value
          : null;
    }

    Future<void> acknowledgeOpen() async {
      final notificationId = id('notificationId');
      if (owner == null || notificationId == null) return;
      // The protected exact record has loaded and its sheet is now visible.
      // A redirect, failed load or an account switch must retain unread state.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !stillCurrent()) return;
      try {
        await ref
            .read(yorksV1NotificationsProvider.notifier)
            .markSeen(notificationId);
      } catch (_) {
        // Retain unread state; a later explicit open can retry acknowledgement.
      }
    }

    final language = ref.read(languageProvider);
    final invoice = id('invoice_id');
    final claim = id('claim_id');
    final bill = id('bill_id');
    if (invoice != null &&
        (widget.initialTab == YorksProjectAccountsTab.invoices ||
            widget.initialTab == YorksProjectAccountsTab.receiptsPdc)) {
      final provider = yorksAccountsReceivablesControllerProvider(projectId);
      final loaded = await ref.read(provider.notifier).loadInvoice(invoice);
      if (!mounted ||
          !stillCurrent() ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final detail = ref.read(provider).selectedInvoice;
      final pdcId = id('pdc_id');
      if (!loaded ||
          detail?.projectId != projectId ||
          detail?.invoice.invoiceId != invoice ||
          (pdcId != null && !detail!.pdcs.any((pdc) => pdc.pdcId == pdcId))) {
        _openedNotificationTarget = null;
        return;
      }
      final sheet = showYorksAccountsInvoiceActionsSheet(
        context,
        projectId: projectId,
        invoiceId: invoice,
        initialPdcId: pdcId,
        language: language,
      );
      await acknowledgeOpen();
      await sheet;
    } else if (claim != null &&
        widget.initialTab == YorksProjectAccountsTab.invoices) {
      final provider = yorksAccountsReceivablesControllerProvider(projectId);
      final loaded = await ref.read(provider.notifier).loadClaim(claim);
      if (!mounted ||
          !stillCurrent() ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final detail = ref.read(provider).selectedClaim;
      final progress = ref
          .read(yorksAccountsProjectControllerProvider(projectId))
          .progress;
      if (!loaded ||
          detail?.projectId != projectId ||
          detail?.claim.claimId != claim ||
          progress == null) {
        _openedNotificationTarget = null;
        return;
      }
      final sheet = showYorksAccountsClaimActionsSheet(
        context,
        projectId: projectId,
        claimId: claim,
        progress: progress,
        language: language,
      );
      await acknowledgeOpen();
      await sheet;
    } else if (bill != null &&
        widget.initialTab == YorksProjectAccountsTab.supplierBills) {
      final provider = yorksAccountsSupplierControllerProvider(projectId);
      final loaded = await ref.read(provider.notifier).loadBill(bill);
      if (!mounted ||
          !stillCurrent() ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final detail = ref.read(provider).selectedBill;
      if (!loaded ||
          detail?.projectId != projectId ||
          detail?.supplierBill.supplierBillId != bill) {
        _openedNotificationTarget = null;
        return;
      }
      final sheet = showYorksAccountsSupplierBillActionsSheet(
        context,
        projectId: projectId,
        supplierBillId: bill,
        language: language,
      );
      await acknowledgeOpen();
      await sheet;
    }
  }

  Future<void> _loadTab(
    YorksProjectAccountsTab tab, {
    bool force = false,
  }) async {
    final pending = <Future<bool>>[];
    switch (tab) {
      case YorksProjectAccountsTab.overview:
        // The billing register can hold filtered progress. Refresh the complete
        // server projection before aggregating the overview by building.
        pending.add(
          ref
              .read(
                yorksAccountsProjectControllerProvider(
                  widget.projectId,
                ).notifier,
              )
              .load(),
        );
        break;
      case YorksProjectAccountsTab.documents:
        final provider = yorksAccountsDocumentsControllerProvider(
          widget.projectId,
        );
        if (force || ref.read(provider).workspace == null) {
          pending.add(ref.read(provider.notifier).load());
        }
        break;
      case YorksProjectAccountsTab.activity:
        final provider = yorksAccountsActivityControllerProvider(
          widget.projectId,
        );
        if (force || ref.read(provider).projection == null) {
          pending.add(ref.read(provider.notifier).load());
        }
        break;
      case YorksProjectAccountsTab.billing:
        final provider = yorksAccountsProjectControllerProvider(
          widget.projectId,
        );
        final state = ref.read(provider);
        if (force || state.baseline == null || state.progress == null) {
          pending.add(ref.read(provider.notifier).load());
        }
        break;
      case YorksProjectAccountsTab.invoices:
        final projectProvider = yorksAccountsProjectControllerProvider(
          widget.projectId,
        );
        final projectState = ref.read(projectProvider);
        if (force ||
            projectState.baseline == null ||
            projectState.progress == null) {
          pending.add(ref.read(projectProvider.notifier).load());
        }
        final receivablesProvider = yorksAccountsReceivablesControllerProvider(
          widget.projectId,
        );
        final receivablesState = ref.read(receivablesProvider);
        final controller = ref.read(receivablesProvider.notifier);
        if (force || receivablesState.claims == null) {
          pending.add(controller.loadClaims());
        }
        if (force || receivablesState.invoices == null) {
          pending.add(controller.loadInvoices());
        }
        break;
      case YorksProjectAccountsTab.receiptsPdc:
        final provider = yorksAccountsReceivablesControllerProvider(
          widget.projectId,
        );
        final state = ref.read(provider);
        final controller = ref.read(provider.notifier);
        if (force || state.ledger == null) {
          pending.add(controller.loadReceiptsAndPdc());
        }
        if (force || state.invoices == null) {
          pending.add(controller.loadInvoices());
        }
        break;
      case YorksProjectAccountsTab.supplierBills:
        final provider = yorksAccountsSupplierControllerProvider(
          widget.projectId,
        );
        if (force || ref.read(provider).bills == null) {
          pending.add(ref.read(provider.notifier).loadBills());
        }
        break;
    }
    if (pending.isEmpty) return;
    if (mounted) setState(() => _activeTabLoads++);
    try {
      await Future.wait(pending);
    } finally {
      if (mounted) setState(() => _activeTabLoads--);
    }
  }

  void _selectTab(YorksProjectAccountsTab tab) {
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsTabSelected,
          properties: {
            AnalyticsProperty.source: tab.name,
            AnalyticsProperty.entryPoint: 'project_accounts_navigation',
          },
        );
    final path = switch (tab) {
      YorksProjectAccountsTab.overview =>
        RoutePaths.yorksV1ProjectAccountsOverviewPath(widget.projectId),
      YorksProjectAccountsTab.billing =>
        RoutePaths.yorksV1ProjectAccountsBillingPath(widget.projectId),
      YorksProjectAccountsTab.invoices =>
        RoutePaths.yorksV1ProjectAccountsInvoicesPath(widget.projectId),
      YorksProjectAccountsTab.receiptsPdc =>
        RoutePaths.yorksV1ProjectAccountsReceiptsPdcPath(widget.projectId),
      YorksProjectAccountsTab.supplierBills =>
        RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(widget.projectId),
      YorksProjectAccountsTab.documents =>
        RoutePaths.yorksV1ProjectAccountsDocumentsPath(widget.projectId),
      YorksProjectAccountsTab.activity =>
        RoutePaths.yorksV1ProjectAccountsActivityPath(widget.projectId),
    };
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final overviewState = ref.watch(
      yorksAccountsProjectOverviewControllerProvider(widget.projectId),
    );
    final projection = overviewState.projection;
    if (projection == null) {
      final statePanel = _AccountsStatePanel(
        status: overviewState.status,
        language: language,
        error: overviewState.error,
        onRetry: _load,
      );
      return Material(color: AppColors.surface, child: statePanel);
    }
    final tabs = <YorksProjectAccountsTab>[
      if (projection.capabilities.viewProjectAccounts) ...[
        YorksProjectAccountsTab.overview,
        YorksProjectAccountsTab.billing,
        if (projection.capabilities.viewValues)
          YorksProjectAccountsTab.invoices,
        if (projection.capabilities.viewValues)
          YorksProjectAccountsTab.receiptsPdc,
      ],
      if (projection.capabilities.viewSupplierCosts)
        YorksProjectAccountsTab.supplierBills,
      if (projection.capabilities.viewProjectAccounts)
        YorksProjectAccountsTab.documents,
      if (projection.capabilities.viewProjectAccounts)
        YorksProjectAccountsTab.activity,
    ];
    if (tabs.isEmpty) {
      final statePanel = _AccountsStatePanel(
        status: YorksAccountsViewStatus.forbidden,
        language: language,
        onRetry: _load,
      );
      return Material(color: AppColors.surface, child: statePanel);
    }
    final selected = tabs.contains(widget.initialTab)
        ? widget.initialTab
        : tabs.first;
    final loading =
        overviewState.status == YorksAccountsViewStatus.loading ||
        _activeTabLoads > 0 ||
        _tabIsLoading(ref, widget.projectId, selected);
    final content = Stack(
      children: [
        CustomScrollView(
          key: PageStorageKey('accounts-project-${widget.projectId}-$selected'),
          slivers: [
            if (_standaloneAccountsHeaderEnabled)
              SliverToBoxAdapter(
                child: _ProjectAccountsHero(
                  projectId: widget.projectId,
                  eyebrow: projection.projectReference,
                  title: projection.projectName,
                  body: projection.projectSite ?? '',
                  badge: projection.baseline?['status'] == 'active'
                      ? _t(language, 'status_active')
                      : '',
                  language: language,
                  showProjectNavigation:
                      projection.actorExactRole != 'accountant',
                  showProjectActions: projection.actorExactRole == 'admin',
                  baselineRevision: int.tryParse(
                    '${projection.baseline?['revision_number'] ?? ''}',
                  ),
                  canPrepareClaim:
                      projection.capabilities.prepareClaim &&
                      projection.capabilities.viewValues,
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                _standaloneAccountsHeaderEnabled ? 14 : 12,
                16,
                48,
              ),
              sliver: SliverList.list(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final navigation = _ProjectAccountsTabs(
                        tabs: tabs,
                        selected: selected,
                        language: language,
                        onSelected: _selectTab,
                      );
                      final tools =
                          projection.capabilities.canExport &&
                              selected == YorksProjectAccountsTab.overview
                          ? YorksAccountsReportActions(
                              kind: _overviewExportKinds(
                                projection.capabilities,
                              ).first,
                              projectId: widget.projectId,
                              language: language,
                              overviewToolbar: true,
                              bundledKinds: _overviewExportKinds(
                                projection.capabilities,
                              ).skip(1).toList(growable: false),
                            )
                          : null;
                      if (constraints.maxWidth < 1050 || tools == null) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            navigation,
                            if (tools != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: tools,
                                ),
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: navigation),
                          const SizedBox(width: 10),
                          tools,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  if (selected != YorksProjectAccountsTab.overview &&
                      projection.capabilities.canExport &&
                      _reportKindForTab(selected, projection.capabilities) !=
                          null) ...[
                    YorksAccountsReportActions(
                      kind: _reportKindForTab(
                        selected,
                        projection.capabilities,
                      )!,
                      projectId: widget.projectId,
                      language: language,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _ProjectTabBody(
                    projectId: widget.projectId,
                    tab: selected,
                    overview: projection,
                    language: language,
                    onRetry: () => unawaited(_load(force: true)),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: ValueKey('accounts-background-loading'),
              minHeight: 3,
            ),
          ),
      ],
    );
    return Material(color: const Color(0xFFF5F9FF), child: content);
  }
}

// Project Accounts is hosted by the shared project workspace in release
// builds. This compile-time-only lane preserves isolated diagnostics without
// shipping a second project header/navigation implementation.
const _standaloneAccountsHeaderEnabled = bool.fromEnvironment(
  'YORKS_ACCOUNTS_STANDALONE_HEADER',
);

bool _tabIsLoading(
  WidgetRef ref,
  String projectId,
  YorksProjectAccountsTab tab,
) => switch (tab) {
  YorksProjectAccountsTab.overview =>
    ref.watch(yorksAccountsProjectControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.billing =>
    ref.watch(yorksAccountsProjectControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.invoices =>
    ref.watch(yorksAccountsProjectControllerProvider(projectId)).status ==
            YorksAccountsViewStatus.loading ||
        ref
                .watch(yorksAccountsReceivablesControllerProvider(projectId))
                .status ==
            YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.receiptsPdc =>
    ref.watch(yorksAccountsReceivablesControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.supplierBills =>
    ref.watch(yorksAccountsSupplierControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.documents =>
    ref.watch(yorksAccountsDocumentsControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
  YorksProjectAccountsTab.activity =>
    ref.watch(yorksAccountsActivityControllerProvider(projectId)).status ==
        YorksAccountsViewStatus.loading,
};

YorksAccountsReportKind? _reportKindForTab(
  YorksProjectAccountsTab tab,
  YorksAccountsProjectUiCapabilities capabilities,
) => switch (tab) {
  YorksProjectAccountsTab.overview when capabilities.viewValues =>
    YorksAccountsReportKind.projectSummary,
  YorksProjectAccountsTab.billing => YorksAccountsReportKind.billingProgress,
  YorksProjectAccountsTab.invoices when capabilities.viewValues =>
    YorksAccountsReportKind.clientInvoices,
  YorksProjectAccountsTab.receiptsPdc when capabilities.viewValues =>
    YorksAccountsReportKind.pdcRegister,
  YorksProjectAccountsTab.supplierBills when capabilities.viewSupplierCosts =>
    YorksAccountsReportKind.supplierBills,
  _ => null,
};

List<YorksAccountsReportKind> _overviewExportKinds(
  YorksAccountsProjectUiCapabilities capabilities,
) {
  if (!capabilities.viewValues) {
    return const [YorksAccountsReportKind.billingProgress];
  }
  return [
    YorksAccountsReportKind.projectSummary,
    YorksAccountsReportKind.commercialBaseline,
    YorksAccountsReportKind.buildingAllocations,
    YorksAccountsReportKind.stageAllocations,
    YorksAccountsReportKind.billingProgress,
    YorksAccountsReportKind.progressHistory,
    YorksAccountsReportKind.clientClaims,
    YorksAccountsReportKind.claimLines,
    YorksAccountsReportKind.clientInvoices,
    YorksAccountsReportKind.certifications,
    YorksAccountsReportKind.clientReceipts,
    YorksAccountsReportKind.pdcRegister,
    YorksAccountsReportKind.pdcEvents,
    if (capabilities.viewSupplierCosts) ...[
      YorksAccountsReportKind.supplierBills,
      YorksAccountsReportKind.supplierPayments,
    ],
    YorksAccountsReportKind.accountsDocuments,
    YorksAccountsReportKind.accountsActivity,
  ];
}

String _filterDensity(Iterable<Object?> values) {
  final count = values.where((value) => value != null).length;
  if (count == 0) return 'none';
  if (count == 1) return 'single';
  return 'multiple';
}

void _trackAccountsRecord(WidgetRef ref, String objectType, String source) {
  ref
      .read(analyticsServiceProvider)
      .capture(
        AnalyticsEvent.accountsRecordOpened,
        properties: {
          AnalyticsProperty.objectType: objectType,
          AnalyticsProperty.source: source,
        },
      );
}

class _ProjectTabBody extends ConsumerWidget {
  const _ProjectTabBody({
    required this.projectId,
    required this.tab,
    required this.overview,
    required this.language,
    required this.onRetry,
  });

  final String projectId;
  final YorksProjectAccountsTab tab;
  final YorksAccountsProjectOverviewProjection overview;
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (tab) {
    YorksProjectAccountsTab.overview => _ProjectAccountsOverview(
      overview: overview,
      projectState: ref.watch(
        yorksAccountsProjectControllerProvider(projectId),
      ),
      language: language,
      onRetry: onRetry,
      onOpen: (tab) => context.go(switch (tab) {
        YorksProjectAccountsTab.billing =>
          RoutePaths.yorksV1ProjectAccountsBillingPath(projectId),
        YorksProjectAccountsTab.invoices =>
          RoutePaths.yorksV1ProjectAccountsInvoicesPath(projectId),
        YorksProjectAccountsTab.supplierBills =>
          RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(projectId),
        YorksProjectAccountsTab.receiptsPdc =>
          RoutePaths.yorksV1ProjectAccountsReceiptsPdcPath(projectId),
        _ => RoutePaths.yorksV1ProjectAccountsOverviewPath(projectId),
      }),
    ),
    YorksProjectAccountsTab.billing => _BillingProgressView(
      state: ref.watch(yorksAccountsProjectControllerProvider(projectId)),
      language: language,
      onRetry: () => ref
          .read(yorksAccountsProjectControllerProvider(projectId).notifier)
          .load(),
      onFilter: ({buildingScopeId, stageKey, actionOwner, hasEvidence}) {
        ref
            .read(analyticsServiceProvider)
            .capture(
              AnalyticsEvent.accountsFilterChanged,
              properties: {
                AnalyticsProperty.source: 'billing_progress',
                AnalyticsProperty.listFilter: _filterDensity([
                  buildingScopeId,
                  stageKey,
                  actionOwner,
                  hasEvidence,
                ]),
              },
            );
        return ref
            .read(yorksAccountsProjectControllerProvider(projectId).notifier)
            .load(
              buildingScopeId: buildingScopeId,
              stageKey: stageKey,
              actionOwner: actionOwner,
              hasEvidence: hasEvidence,
            );
      },
      onBaseline: (baseline) => showYorksAccountsBaselineActionSheet(
        context,
        projectId: projectId,
        projection: baseline,
        language: language,
      ),
      onAction: (entry, projection) => showYorksAccountsProgressActionSheet(
        context,
        projectId: projectId,
        projectReference: overview.projectReference,
        entry: entry,
        projection: projection,
        language: language,
      ),
    ),
    YorksProjectAccountsTab.invoices => _InvoicesView(
      projectId: projectId,
      state: ref.watch(yorksAccountsReceivablesControllerProvider(projectId)),
      projectState: ref.watch(
        yorksAccountsProjectControllerProvider(projectId),
      ),
      language: language,
      onRetry: () {
        final controller = ref.read(
          yorksAccountsReceivablesControllerProvider(projectId).notifier,
        );
        controller.loadClaims();
        controller.loadInvoices();
      },
      onFilter: ({claimStatus, invoiceStatus, dueState}) async {
        ref
            .read(analyticsServiceProvider)
            .capture(
              AnalyticsEvent.accountsFilterChanged,
              properties: {
                AnalyticsProperty.source: 'claims_invoices',
                AnalyticsProperty.listFilter: _filterDensity([
                  claimStatus,
                  invoiceStatus,
                  dueState,
                ]),
              },
            );
        final controller = ref.read(
          yorksAccountsReceivablesControllerProvider(projectId).notifier,
        );
        await Future.wait([
          controller.loadClaims(status: claimStatus),
          controller.loadInvoices(status: invoiceStatus, dueState: dueState),
        ]);
      },
      onCreateClaim: (progress) => showYorksAccountsClaimDraftSheet(
        context,
        projectId: projectId,
        progress: progress,
        language: language,
      ),
      onOpenClaim: (claimId, progress) {
        _trackAccountsRecord(ref, 'client_claim', 'claims_invoices');
        return showYorksAccountsClaimActionsSheet(
          context,
          projectId: projectId,
          claimId: claimId,
          progress: progress,
          language: language,
        );
      },
      onOpenInvoice: (invoiceId) {
        _trackAccountsRecord(ref, 'client_invoice', 'claims_invoices');
        return showYorksAccountsInvoiceActionsSheet(
          context,
          projectId: projectId,
          invoiceId: invoiceId,
          language: language,
        );
      },
    ),
    YorksProjectAccountsTab.receiptsPdc => _ReceiptsPdcView(
      projectId: projectId,
      state: ref.watch(yorksAccountsReceivablesControllerProvider(projectId)),
      language: language,
      onRetry: () => ref
          .read(yorksAccountsReceivablesControllerProvider(projectId).notifier)
          .loadReceiptsAndPdc(),
      onOpenInvoice: (invoiceId) {
        _trackAccountsRecord(ref, 'client_invoice', 'receipts_pdc');
        return showYorksAccountsInvoiceActionsSheet(
          context,
          projectId: projectId,
          invoiceId: invoiceId,
          language: language,
        );
      },
    ),
    YorksProjectAccountsTab.supplierBills => _SupplierBillsView(
      projectId: projectId,
      state: ref.watch(yorksAccountsSupplierControllerProvider(projectId)),
      language: language,
      onRetry: () => ref
          .read(yorksAccountsSupplierControllerProvider(projectId).notifier)
          .loadBills(),
      onFilter: ({search, matchStatus, paymentStatus}) {
        ref
            .read(analyticsServiceProvider)
            .capture(
              AnalyticsEvent.accountsFilterChanged,
              properties: {
                AnalyticsProperty.source: 'supplier_bills',
                AnalyticsProperty.listFilter: _filterDensity([
                  search?.trim().isEmpty == false ? 'search' : null,
                  matchStatus,
                  paymentStatus,
                ]),
              },
            );
        return ref
            .read(yorksAccountsSupplierControllerProvider(projectId).notifier)
            .loadBills(
              search: search,
              matchStatus: matchStatus,
              paymentStatus: paymentStatus,
            );
      },
      onCreate: () => showYorksAccountsSupplierBillDraftSheet(
        context,
        projectId: projectId,
        language: language,
      ),
      onOpen: (supplierBillId) {
        _trackAccountsRecord(ref, 'supplier_bill', 'supplier_bills');
        return showYorksAccountsSupplierBillActionsSheet(
          context,
          projectId: projectId,
          supplierBillId: supplierBillId,
          language: language,
        );
      },
    ),
    YorksProjectAccountsTab.documents => YorksAccountsDocumentsView(
      projectId: projectId,
      language: language,
    ),
    YorksProjectAccountsTab.activity => YorksAccountsActivityView(
      projectId: projectId,
      language: language,
    ),
  };
}

class _AccountsHero extends StatelessWidget {
  const _AccountsHero({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.badge,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String badge;

  @override
  Widget build(BuildContext context) => _Panel(
    accent: AppColors.warning,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: AppTypography.eyebrow.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: compact
                  ? AppTypography.headlineMedium
                  : AppTypography.displaySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: AppTypography.bodyMedium),
          ],
        );
        final access = badge.isEmpty
            ? const SizedBox.shrink()
            : _Badge(
                badge.replaceAll('_', ' '),
                color: AppColors.successContainer,
              );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              access,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            access,
          ],
        );
      },
    ),
  );
}

class _ProjectAccountsHero extends StatelessWidget {
  const _ProjectAccountsHero({
    required this.projectId,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.badge,
    required this.language,
    required this.showProjectNavigation,
    required this.showProjectActions,
    required this.baselineRevision,
    required this.canPrepareClaim,
  });

  final String projectId;
  final String eyebrow;
  final String title;
  final String body;
  final String badge;
  final AppLanguage language;
  final bool showProjectNavigation;
  final bool showProjectActions;
  final int? baselineRevision;
  final bool canPrepareClaim;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 17, 20, 0),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: compact ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style:
                  (compact
                          ? AppTypography.titleLarge
                          : AppTypography.headlineSmall)
                      .copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF152341),
                        height: 1.15,
                      ),
            ),
            const SizedBox(height: 7),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                if (body.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppColors.inkSecondary,
                      ),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 230 : 320,
                        ),
                        child: Text(
                          body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (badge.isNotEmpty)
                  _Badge(badge, color: AppColors.successContainer),
                _Badge(
                  _t(language, 'commercial_control_badge'),
                  color: const Color(0xFFEDF3FA),
                ),
              ],
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (baselineRevision != null)
              OutlinedButton.icon(
                onPressed: () => context.go(
                  RoutePaths.yorksV1ProjectAccountsBillingPath(projectId),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(
                  '${_t(language, 'baseline_revision')} $baselineRevision',
                ),
              ),
            if (canPrepareClaim)
              FilledButton.icon(
                onPressed: () => context.go(
                  RoutePaths.yorksV1ProjectAccountsInvoicesPath(projectId),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(_t(language, 'prepare_claim')),
              ),
            if (showProjectActions)
              PopupMenuButton<String>(
                tooltip: _t(language, 'project_actions'),
                onSelected: (action) {
                  if (action == 'open') {
                    context.go(RoutePaths.yorksV1ProjectPath(projectId));
                  }
                  if (action == 'edit') {
                    context.go(RoutePaths.yorksV1ProjectEditPath(projectId));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'open',
                    child: Text(
                      YorksV1ProjectStrings.openProject.active(language),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      YorksV1ProjectStrings.editProject.active(language),
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              heading,
              if (baselineRevision != null ||
                  canPrepareClaim ||
                  showProjectActions) ...[
                const SizedBox(height: 12),
                actions,
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: actions,
                    ),
                  ),
                ],
              ),
            if (showProjectNavigation) ...[
              const SizedBox(height: 14),
              _ProjectAccountsWorkspaceNavigation(
                projectId: projectId,
                language: language,
              ),
            ] else
              const SizedBox(height: 14),
          ],
        );
      },
    ),
  );
}

class _ProjectAccountsWorkspaceNavigation extends StatefulWidget {
  const _ProjectAccountsWorkspaceNavigation({
    required this.projectId,
    required this.language,
  });

  final String projectId;
  final AppLanguage language;

  @override
  State<_ProjectAccountsWorkspaceNavigation> createState() =>
      _ProjectAccountsWorkspaceNavigationState();
}

class _ProjectAccountsWorkspaceNavigationState
    extends State<_ProjectAccountsWorkspaceNavigation> {
  final _selectedKey = GlobalKey();
  double? _lastViewportWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    if (_lastViewportWidth == width) return;
    _lastViewportWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selected = _selectedKey.currentContext;
      if (selected != null) Scrollable.ensureVisible(selected, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final links = <(IconData, String, String?)>[
      (
        Icons.home_outlined,
        YorksV1ProjectStrings.overview.active(widget.language),
        RoutePaths.yorksV1ProjectPath(widget.projectId),
      ),
      (
        Icons.list_alt_outlined,
        YorksV1ProjectStrings.boq.active(widget.language),
        RoutePaths.yorksV1BoqGroupsPath(widget.projectId),
      ),
      (
        Icons.description_outlined,
        YorksV1ProjectStrings.materialRequests.active(widget.language),
        RoutePaths.yorksV1MaterialRequestsPath(projectId: widget.projectId),
      ),
      (
        Icons.account_balance_wallet_outlined,
        YorksV1ProjectStrings.accounts.active(widget.language),
        null,
      ),
      (
        Icons.insert_drive_file_outlined,
        YorksV1ProjectStrings.documents.active(widget.language),
        RoutePaths.yorksV1ProjectDocumentsPath(widget.projectId),
      ),
      (
        Icons.apartment_outlined,
        YorksV1ProjectStrings.materialMovement.active(widget.language),
        Uri(
          path: RoutePaths.yorksV1ProjectPath(widget.projectId),
          queryParameters: const {'tab': 'material-movement'},
        ).toString(),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final link in links)
            Container(
              key: link.$3 == null ? _selectedKey : null,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: link.$3 == null
                        ? AppColors.blue
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: TextButton.icon(
                onPressed: link.$3 == null ? null : () => context.go(link.$3!),
                icon: Icon(link.$1, size: 17),
                label: Text(link.$2),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  foregroundColor: AppColors.inkSecondary,
                  disabledForegroundColor: AppColors.blue,
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PortfolioKpis extends StatelessWidget {
  const _PortfolioKpis({
    required this.totals,
    required this.language,
    required this.onFilter,
  });

  final YorksAccountsPortfolioTotals totals;
  final AppLanguage language;
  final ValueChanged<String?> onFilter;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_t(language, 'contract'), totals.contractBaseline, null),
      (_t(language, 'confirmed'), totals.confirmedEligible, 'active'),
      (_t(language, 'available'), totals.availableToClaim, 'active'),
      (_t(language, 'claimed'), totals.claimed, 'active'),
      (_t(language, 'certified'), totals.certified, 'active'),
      (_t(language, 'paid'), totals.amountPaidTillDate, 'active'),
      (_t(language, 'still_due'), totals.stillDue, 'action_required'),
      (_t(language, 'pdc'), totals.pdcExposure, 'action_required'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - AppSpacing.md * 3) / 4
            : constraints.maxWidth >= 720
            ? (constraints.maxWidth - AppSpacing.md * 2) / 3
            : (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: constraints.maxWidth < 720 ? AppSpacing.sm : AppSpacing.md,
          runSpacing: constraints.maxWidth < 720
              ? AppSpacing.sm
              : AppSpacing.md,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _KpiCard(
                  label: item.$1,
                  value: _money(item.$2),
                  onTap: () => onFilter(item.$3),
                  danger: item.$1 == _t(language, 'still_due'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PortfolioFilters extends StatelessWidget {
  const _PortfolioFilters({
    required this.language,
    required this.searchController,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApply,
    required this.onClear,
  });

  final AppLanguage language;
  final TextEditingController searchController;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final void Function({
    required String? commercialState,
    required String? dueState,
    required String? paymentState,
  })
  onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: _t(language, 'search'),
            isDense: true,
          ),
        );
        final controls = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _FilterDropdown(
              value: commercialState,
              label: _t(language, 'commercial_control'),
              values: const ['active', 'not_initialized', 'action_required'],
              onChanged: (value) => onApply(
                commercialState: value,
                dueState: dueState,
                paymentState: paymentState,
              ),
            ),
            _FilterDropdown(
              value: dueState,
              label: _t(language, 'still_due'),
              values: const ['current', 'due_soon', 'overdue'],
              onChanged: (value) => onApply(
                commercialState: commercialState,
                dueState: value,
                paymentState: paymentState,
              ),
            ),
            _FilterDropdown(
              value: paymentState,
              label: _t(language, 'paid'),
              values: const ['unpaid', 'partially_paid', 'paid'],
              onChanged: (value) => onApply(
                commercialState: commercialState,
                dueState: dueState,
                paymentState: value,
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(_t(language, 'clear')),
            ),
          ],
        );
        if (constraints.maxWidth < 720) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: AppSpacing.sm),
              Badge.count(
                count: activeFilterCount,
                isLabelVisible: activeFilterCount > 0,
                child: IconButton.outlined(
                  tooltip: _t(language, 'filters'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _PortfolioFilterSheet(
                      language: language,
                      commercialState: commercialState,
                      dueState: dueState,
                      paymentState: paymentState,
                      onApply: onApply,
                      onClear: onClear,
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          );
        }
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.sm),
              controls,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: AppSpacing.md),
            Flexible(flex: 2, child: controls),
          ],
        );
      },
    ),
  );
}

class _PortfolioRegister extends StatelessWidget {
  const _PortfolioRegister({
    required this.state,
    required this.language,
    required this.onRetry,
    required this.onClearFilters,
    required this.onLoadMore,
  });

  final YorksAccountsPortfolioState state;
  final AppLanguage language;
  final VoidCallback onRetry;
  final VoidCallback onClearFilters;
  final Future<bool> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final projection = state.projection;
    if (projection == null) {
      return _AccountsStatePanel(
        status: state.status,
        language: language,
        error: state.error,
        onRetry: onRetry,
      );
    }
    if (projection.projects.isEmpty) {
      return _EmptyPanel(
        icon: Icons.account_balance_wallet_outlined,
        title: _t(
          language,
          projection.authorizedProjectCount == 0 ? 'no_projects' : 'no_results',
        ),
        action: projection.authorizedProjectCount == 0 ? null : onClearFilters,
        actionLabel: _t(language, 'clear'),
      );
    }
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: _t(language, 'projects'),
            subtitle:
                '${projection.filteredProjectCount} / ${projection.authorizedProjectCount}',
          ),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 900
                ? Column(
                    children: [
                      for (final project in projection.projects)
                        _PortfolioProjectCard(
                          project: project,
                          language: language,
                          onOpen: () => context.go(
                            RoutePaths.yorksV1ProjectAccountsOverviewPath(
                              project.projectId,
                            ),
                          ),
                        ),
                    ],
                  )
                : _PortfolioProjectTable(
                    projects: projection.projects,
                    language: language,
                  ),
          ),
          if (projection.nextProjectId != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Align(
                alignment: AlignmentDirectional.center,
                child: OutlinedButton.icon(
                  onPressed: state.isLoadingMore ? null : onLoadMore,
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    _t(
                      language,
                      state.isLoadingMore ? 'loading_more' : 'load_more',
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (state.error != null && !state.isLoadingMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                _t(language, 'load_more_failed'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _PortfolioFilterSheet extends StatefulWidget {
  const _PortfolioFilterSheet({
    required this.language,
    required this.commercialState,
    required this.dueState,
    required this.paymentState,
    required this.onApply,
    required this.onClear,
  });

  final AppLanguage language;
  final String? commercialState;
  final String? dueState;
  final String? paymentState;
  final void Function({
    required String? commercialState,
    required String? dueState,
    required String? paymentState,
  })
  onApply;
  final VoidCallback onClear;

  @override
  State<_PortfolioFilterSheet> createState() => _PortfolioFilterSheetState();
}

class _PortfolioFilterSheetState extends State<_PortfolioFilterSheet> {
  late String? _commercialState = widget.commercialState;
  late String? _dueState = widget.dueState;
  late String? _paymentState = widget.paymentState;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.xl,
      MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t(widget.language, 'filters'),
                style: AppTypography.titleLarge,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: Navigator.of(context).pop,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SheetDropdown(
          language: widget.language,
          value: _commercialState,
          label: _t(widget.language, 'commercial_control'),
          values: const ['active', 'not_initialized', 'action_required'],
          onChanged: (value) => setState(() => _commercialState = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _SheetDropdown(
          language: widget.language,
          value: _dueState,
          label: _t(widget.language, 'still_due'),
          values: const ['current', 'due_soon', 'overdue'],
          onChanged: (value) => setState(() => _dueState = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _SheetDropdown(
          language: widget.language,
          value: _paymentState,
          label: _t(widget.language, 'paid'),
          values: const ['unpaid', 'partially_paid', 'paid'],
          onChanged: (value) => setState(() => _paymentState = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () {
            widget.onApply(
              commercialState: _commercialState,
              dueState: _dueState,
              paymentState: _paymentState,
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_t(widget.language, 'apply_filters')),
        ),
        TextButton(
          onPressed: () {
            widget.onClear();
            Navigator.of(context).pop();
          },
          child: Text(_t(widget.language, 'clear')),
        ),
      ],
    ),
  );
}

class _SheetDropdown extends StatelessWidget {
  const _SheetDropdown({
    required this.language,
    required this.value,
    required this.label,
    required this.values,
    required this.onChanged,
  });
  final AppLanguage language;
  final String? value;
  final String label;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem<String>(value: null, child: Text(_t(language, 'all'))),
      for (final item in values)
        DropdownMenuItem(value: item, child: Text(_statusLabel(item))),
    ],
    onChanged: onChanged,
  );
}

class _PortfolioProjectTable extends StatelessWidget {
  const _PortfolioProjectTable({
    required this.projects,
    required this.language,
  });

  final List<YorksAccountsPortfolioProject> projects;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 1320),
      child: DataTable(
        dataRowMinHeight: 64,
        dataRowMaxHeight: 72,
        headingRowColor: const WidgetStatePropertyAll(
          AppColors.surfaceContainerLow,
        ),
        columns: [
          DataColumn(label: Text(_t(language, 'project'))),
          DataColumn(label: Text(_t(language, 'client'))),
          DataColumn(numeric: true, label: Text(_t(language, 'contract'))),
          DataColumn(numeric: true, label: Text(_t(language, 'confirmed'))),
          DataColumn(numeric: true, label: Text(_t(language, 'claimed'))),
          DataColumn(numeric: true, label: Text(_t(language, 'certified'))),
          DataColumn(numeric: true, label: Text(_t(language, 'paid'))),
          DataColumn(numeric: true, label: Text(_t(language, 'still_due'))),
          DataColumn(label: Text(_t(language, 'progress'))),
          const DataColumn(label: SizedBox.shrink()),
        ],
        rows: [
          for (final project in projects)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 240,
                    child: _TwoLine(
                      title:
                          '${project.projectReference} · ${project.projectName}',
                      subtitle: project.projectSite ?? '',
                    ),
                  ),
                  onTap: () => context.go(
                    RoutePaths.yorksV1ProjectAccountsOverviewPath(
                      project.projectId,
                    ),
                  ),
                ),
                DataCell(Text(project.clientName ?? '—')),
                DataCell(Text(_money(project.contractBaseline))),
                DataCell(Text(_money(project.confirmedEligible))),
                DataCell(Text(_money(project.claimed))),
                DataCell(Text(_money(project.certified))),
                DataCell(Text(_money(project.amountPaidTillDate))),
                DataCell(
                  Text(
                    _money(project.stillDue),
                    style: TextStyle(
                      color: project.stillDue.isZero
                          ? AppColors.ink
                          : AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 110,
                    child: _Progress(
                      value: _percentValue(project.confirmedPercent),
                      label: _percentLabel(project.confirmedPercent),
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    tooltip: _t(language, 'project_accounts'),
                    onPressed: () => context.go(
                      RoutePaths.yorksV1ProjectAccountsOverviewPath(
                        project.projectId,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _PortfolioProjectCard extends StatelessWidget {
  const _PortfolioProjectCard({
    required this.project,
    required this.language,
    required this.onOpen,
  });
  final YorksAccountsPortfolioProject project;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconTile(Icons.folder_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TwoLine(
                  title: project.projectReference,
                  subtitle: project.projectName,
                ),
              ),
              if (project.actionCount > 0)
                _Badge(
                  '${project.actionCount}',
                  color: AppColors.errorContainer,
                ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Progress(
            value: _percentValue(project.confirmedPercent),
            label: _percentLabel(project.confirmedPercent),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: _t(language, 'certified'),
                  value: _money(project.certified),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: _t(language, 'paid'),
                  value: _money(project.amountPaidTillDate),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: _t(language, 'still_due'),
                  value: _money(project.stillDue),
                  danger: !project.stillDue.isZero,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ActionQueue extends StatelessWidget {
  const _ActionQueue({required this.items, required this.language});
  final List<YorksAccountsActionItem> items;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        _SectionHeader(title: _t(language, 'action_required')),
        for (final item in items.take(5))
          ListTile(
            minTileHeight: 58,
            leading: _IconTile(
              item.severity == 'critical'
                  ? Icons.priority_high_rounded
                  : Icons.rule_folder_outlined,
              color: item.severity == 'critical'
                  ? AppColors.errorContainer
                  : AppColors.warningContainer,
            ),
            title: Text(
              _statusLabel(item.code),
              style: AppTypography.titleSmall,
            ),
            subtitle: Text(
              '${item.projectReference} · ${item.projectName} · ${_statusLabel(item.ownerRole)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Badge('${item.count}'),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => context.go(
              item.code == 'supplier_match_review'
                  ? RoutePaths.yorksV1ProjectAccountsSupplierBillsPath(
                      item.projectId,
                    )
                  : RoutePaths.yorksV1ProjectAccountsInvoicesPath(
                      item.projectId,
                    ),
            ),
          ),
      ],
    ),
  );
}

class _ProjectAccountsOverview extends StatelessWidget {
  const _ProjectAccountsOverview({
    required this.overview,
    required this.projectState,
    required this.language,
    required this.onOpen,
    required this.onRetry,
  });

  final YorksAccountsProjectOverviewProjection overview;
  final YorksAccountsProjectState projectState;
  final AppLanguage language;
  final ValueChanged<YorksProjectAccountsTab> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final baseline = projectState.baseline;
    final progress = projectState.progress;
    if (baseline == null || progress == null) {
      return _AccountsStatePanel(
        status: projectState.status,
        language: language,
        error: projectState.error,
        onRetry: onRetry,
      );
    }
    return YorksProjectAccountsOverview(
      overview: overview,
      baseline: baseline,
      progress: progress,
      language: language,
      onBilling: () => onOpen(YorksProjectAccountsTab.billing),
      onClaims: () => onOpen(YorksProjectAccountsTab.invoices),
      onReceipts: () => onOpen(YorksProjectAccountsTab.receiptsPdc),
    );
  }
}

class _BillingProgressView extends StatefulWidget {
  const _BillingProgressView({
    required this.state,
    required this.language,
    required this.onRetry,
    required this.onFilter,
    required this.onBaseline,
    required this.onAction,
  });
  final YorksAccountsProjectState state;
  final AppLanguage language;
  final VoidCallback onRetry;
  final Future<bool> Function({
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  })
  onFilter;
  final Future<bool> Function(YorksAccountsBaselineProjection baseline)
  onBaseline;
  final Future<bool> Function(
    YorksAccountsProgressEntry entry,
    YorksAccountsProgressProjection projection,
  )
  onAction;

  @override
  State<_BillingProgressView> createState() => _BillingProgressViewState();
}

class _BillingProgressViewState extends State<_BillingProgressView> {
  String? _buildingScopeId;
  String? _stageKey;
  String? _actionOwner;
  bool? _hasEvidence;

  int get _activeFilterCount => [
    _buildingScopeId,
    _stageKey,
    _actionOwner,
    _hasEvidence,
  ].where((value) => value != null).length;

  Future<void> _applyFilters({
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  }) async {
    setState(() {
      _buildingScopeId = buildingScopeId;
      _stageKey = stageKey;
      _actionOwner = actionOwner;
      _hasEvidence = hasEvidence;
    });
    await widget.onFilter(
      buildingScopeId: buildingScopeId,
      stageKey: stageKey,
      actionOwner: actionOwner,
      hasEvidence: hasEvidence,
    );
  }

  Future<void> _clearFilters() => _applyFilters();

  @override
  Widget build(BuildContext context) {
    final progress = widget.state.progress;
    final baseline = widget.state.baseline;
    if (progress == null || baseline == null) {
      return _AccountsStatePanel(
        status: widget.state.status,
        language: widget.language,
        error: widget.state.error,
        onRetry: widget.onRetry,
      );
    }
    final canConfigure =
        baseline.commands.allows('initialize_baseline') ||
        baseline.commands.allows('revise_baseline');
    if (progress.progress.isEmpty) {
      return _EmptyPanel(
        icon: Icons.show_chart_rounded,
        title: _t(
          widget.language,
          _activeFilterCount == 0 ? 'no_records' : 'no_progress_results',
        ),
        action: _activeFilterCount > 0
            ? _clearFilters
            : canConfigure
            ? () => widget.onBaseline(baseline)
            : null,
        actionLabel: _activeFilterCount > 0
            ? _t(widget.language, 'clear')
            : canConfigure
            ? _t(
                widget.language,
                baseline.baseline == null
                    ? 'set_commercial_baseline'
                    : 'revise_commercial_baseline',
              )
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canConfigure)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => widget.onBaseline(baseline),
              icon: const Icon(Icons.settings_outlined),
              label: Text(
                _t(
                  widget.language,
                  baseline.baseline == null
                      ? 'set_commercial_baseline'
                      : 'revise_commercial_baseline',
                ),
              ),
            ),
          ),
        if (canConfigure) const SizedBox(height: AppSpacing.md),
        if (progress.capabilities.canViewValues && progress.totals != null) ...[
          _BillingFormulaStrip(
            totals: progress.totals!,
            entries: progress.progress,
            language: widget.language,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _ProgressFilters(
          language: widget.language,
          baseline: baseline,
          buildingScopeId: _buildingScopeId,
          stageKey: _stageKey,
          actionOwner: _actionOwner,
          hasEvidence: _hasEvidence,
          activeFilterCount: _activeFilterCount,
          onApply: _applyFilters,
          onClear: _clearFilters,
        ),
        const SizedBox(height: AppSpacing.md),
        YorksAccountsBillingWorkbench(
          baseline: baseline,
          progress: progress,
          language: widget.language,
          onAction: (entry) => widget.onAction(entry, progress),
        ),
      ],
    );
  }
}

class _ProgressFilters extends StatelessWidget {
  const _ProgressFilters({
    required this.language,
    required this.baseline,
    required this.buildingScopeId,
    required this.stageKey,
    required this.actionOwner,
    required this.hasEvidence,
    required this.activeFilterCount,
    required this.onApply,
    required this.onClear,
  });

  final AppLanguage language;
  final YorksAccountsBaselineProjection baseline;
  final String? buildingScopeId;
  final String? stageKey;
  final String? actionOwner;
  final bool? hasEvidence;
  final int activeFilterCount;
  final Future<void> Function({
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  })
  onApply;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Badge.count(
            count: activeFilterCount,
            isLabelVisible: activeFilterCount > 0,
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => _ProgressFilterSheet(
                  language: language,
                  baseline: baseline,
                  buildingScopeId: buildingScopeId,
                  stageKey: stageKey,
                  actionOwner: actionOwner,
                  hasEvidence: hasEvidence,
                  onApply: onApply,
                  onClear: onClear,
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
              label: Text(_t(language, 'filters')),
            ),
          ),
        );
      }
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: _ProgressDropdown<String>(
              value: buildingScopeId,
              label: _t(language, 'building'),
              items: [
                for (final building in baseline.physicalBuildings)
                  DropdownMenuItem(
                    value: building.buildingScopeId,
                    child: Text(building.buildingName),
                  ),
              ],
              onChanged: (value) => onApply(
                buildingScopeId: value,
                stageKey: stageKey,
                actionOwner: actionOwner,
                hasEvidence: hasEvidence,
              ),
              allLabel: _t(language, 'all'),
            ),
          ),
          SizedBox(
            width: 210,
            child: _ProgressDropdown<String>(
              value: stageKey,
              label: _t(language, 'stage'),
              items: [
                for (final stage in baseline.stageAllocations)
                  DropdownMenuItem(
                    value: stage.stageKey,
                    child: Text(stage.stageLabel ?? stage.stageKey),
                  ),
              ],
              onChanged: (value) => onApply(
                buildingScopeId: buildingScopeId,
                stageKey: value,
                actionOwner: actionOwner,
                hasEvidence: hasEvidence,
              ),
              allLabel: _t(language, 'all'),
            ),
          ),
          SizedBox(
            width: 210,
            child: _ProgressDropdown<String>(
              value: actionOwner,
              label: _t(language, 'action_owner'),
              items: [
                for (final owner in const [
                  'site_engineer',
                  'project_engineer',
                  'management',
                ])
                  DropdownMenuItem(
                    value: owner,
                    child: Text(_t(language, 'owner_$owner')),
                  ),
              ],
              onChanged: (value) => onApply(
                buildingScopeId: buildingScopeId,
                stageKey: stageKey,
                actionOwner: value,
                hasEvidence: hasEvidence,
              ),
              allLabel: _t(language, 'all'),
            ),
          ),
          SizedBox(
            width: 200,
            child: _ProgressDropdown<bool>(
              value: hasEvidence,
              label: _t(language, 'evidence'),
              items: [
                DropdownMenuItem(
                  value: true,
                  child: Text(_t(language, 'with_evidence')),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text(_t(language, 'without_evidence')),
                ),
              ],
              onChanged: (value) => onApply(
                buildingScopeId: buildingScopeId,
                stageKey: stageKey,
                actionOwner: actionOwner,
                hasEvidence: value,
              ),
              allLabel: _t(language, 'all'),
            ),
          ),
          if (activeFilterCount > 0)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(_t(language, 'clear')),
            ),
        ],
      );
    },
  );
}

class _ProgressDropdown<T> extends StatelessWidget {
  const _ProgressDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    required this.allLabel,
  });
  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      DropdownMenuItem<T>(value: null, child: Text(allLabel)),
      ...items,
    ],
    onChanged: onChanged,
  );
}

class _ProgressFilterSheet extends StatefulWidget {
  const _ProgressFilterSheet({
    required this.language,
    required this.baseline,
    required this.buildingScopeId,
    required this.stageKey,
    required this.actionOwner,
    required this.hasEvidence,
    required this.onApply,
    required this.onClear,
  });
  final AppLanguage language;
  final YorksAccountsBaselineProjection baseline;
  final String? buildingScopeId;
  final String? stageKey;
  final String? actionOwner;
  final bool? hasEvidence;
  final Future<void> Function({
    String? buildingScopeId,
    String? stageKey,
    String? actionOwner,
    bool? hasEvidence,
  })
  onApply;
  final Future<void> Function() onClear;

  @override
  State<_ProgressFilterSheet> createState() => _ProgressFilterSheetState();
}

class _ProgressFilterSheetState extends State<_ProgressFilterSheet> {
  late String? _buildingScopeId = widget.buildingScopeId;
  late String? _stageKey = widget.stageKey;
  late String? _actionOwner = widget.actionOwner;
  late bool? _hasEvidence = widget.hasEvidence;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.xl,
      MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t(widget.language, 'filters'), style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        _ProgressDropdown<String>(
          value: _buildingScopeId,
          label: _t(widget.language, 'building'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final building in widget.baseline.physicalBuildings)
              DropdownMenuItem(
                value: building.buildingScopeId,
                child: Text(building.buildingName),
              ),
          ],
          onChanged: (value) => setState(() => _buildingScopeId = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<String>(
          value: _stageKey,
          label: _t(widget.language, 'stage'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final stage in widget.baseline.stageAllocations)
              DropdownMenuItem(
                value: stage.stageKey,
                child: Text(stage.stageLabel ?? stage.stageKey),
              ),
          ],
          onChanged: (value) => setState(() => _stageKey = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<String>(
          value: _actionOwner,
          label: _t(widget.language, 'action_owner'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final owner in const [
              'site_engineer',
              'project_engineer',
              'management',
            ])
              DropdownMenuItem(
                value: owner,
                child: Text(_t(widget.language, 'owner_$owner')),
              ),
          ],
          onChanged: (value) => setState(() => _actionOwner = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<bool>(
          value: _hasEvidence,
          label: _t(widget.language, 'evidence'),
          allLabel: _t(widget.language, 'all'),
          items: [
            DropdownMenuItem(
              value: true,
              child: Text(_t(widget.language, 'with_evidence')),
            ),
            DropdownMenuItem(
              value: false,
              child: Text(_t(widget.language, 'without_evidence')),
            ),
          ],
          onChanged: (value) => setState(() => _hasEvidence = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () async {
            await widget.onApply(
              buildingScopeId: _buildingScopeId,
              stageKey: _stageKey,
              actionOwner: _actionOwner,
              hasEvidence: _hasEvidence,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_t(widget.language, 'apply_filters')),
        ),
        TextButton(
          onPressed: () async {
            await widget.onClear();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(_t(widget.language, 'clear')),
        ),
      ],
    ),
  );
}

class _InvoicesView extends StatefulWidget {
  const _InvoicesView({
    required this.projectId,
    required this.state,
    required this.projectState,
    required this.language,
    required this.onRetry,
    required this.onFilter,
    required this.onCreateClaim,
    required this.onOpenClaim,
    required this.onOpenInvoice,
  });
  final String projectId;
  final YorksAccountsReceivablesState state;
  final YorksAccountsProjectState projectState;
  final AppLanguage language;
  final VoidCallback onRetry;
  final Future<void> Function({
    YorksAccountsClaimStatus? claimStatus,
    YorksAccountsInvoiceStatus? invoiceStatus,
    YorksAccountsDueState? dueState,
  })
  onFilter;
  final Future<bool> Function(YorksAccountsProgressProjection progress)
  onCreateClaim;
  final Future<bool> Function(
    String claimId,
    YorksAccountsProgressProjection progress,
  )
  onOpenClaim;
  final Future<bool> Function(String invoiceId) onOpenInvoice;

  @override
  State<_InvoicesView> createState() => _InvoicesViewState();
}

class _InvoicesViewState extends State<_InvoicesView> {
  YorksAccountsClaimStatus? _claimStatus;
  YorksAccountsInvoiceStatus? _invoiceStatus;
  YorksAccountsDueState? _dueState;
  String? _selectedInvoiceId;

  int get _activeFilterCount => [
    _claimStatus,
    _invoiceStatus,
    _dueState,
  ].where((value) => value != null).length;

  Future<void> _applyFilters({
    YorksAccountsClaimStatus? claimStatus,
    YorksAccountsInvoiceStatus? invoiceStatus,
    YorksAccountsDueState? dueState,
  }) async {
    setState(() {
      _claimStatus = claimStatus;
      _invoiceStatus = invoiceStatus;
      _dueState = dueState;
    });
    await widget.onFilter(
      claimStatus: claimStatus,
      invoiceStatus: invoiceStatus,
      dueState: dueState,
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoiceProjection = widget.state.invoices;
    final claimProjection = widget.state.claims;
    final invoices = invoiceProjection?.invoices;
    final claims = claimProjection?.claims;
    if (invoices == null || claims == null) {
      return _AccountsStatePanel(
        status: widget.state.status,
        language: widget.language,
        error: widget.state.error,
        onRetry: widget.onRetry,
      );
    }
    final progress = widget.projectState.progress;
    final canCreate =
        claimProjection!.commands.createClaimDraft && progress != null;
    final empty = invoices.isEmpty && claims.isEmpty;
    final draftClaims = claims
        .where((claim) => claim.status == YorksAccountsClaimStatus.draft)
        .fold<YorksAccountsDecimal>(
          YorksAccountsDecimal.zero,
          (total, claim) => total + claim.claimedExVat,
        );
    final readyClaims = claims
        .where(
          (claim) => claim.status == YorksAccountsClaimStatus.readyForAccounts,
        )
        .fold<YorksAccountsDecimal>(
          YorksAccountsDecimal.zero,
          (total, claim) => total + claim.claimedExVat,
        );
    final submitted = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (total, invoice) => total + invoice.claimedExVat,
    );
    final certified = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (total, invoice) => total + invoice.certifiedExVat,
    );
    final stillDue = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (total, invoice) => total + invoice.stillDue,
    );
    final selectedInvoice = invoices
        .cast<YorksAccountsClientInvoiceSummary?>()
        .firstWhere(
          (invoice) => invoice?.invoiceId == _selectedInvoiceId,
          orElse: () => invoices.isEmpty ? null : invoices.first,
        );
    final selectedClaim = selectedInvoice == null
        ? null
        : claims.cast<YorksAccountsClientClaimSummary?>().firstWhere(
            (claim) => claim?.claimId == selectedInvoice.claimId,
            orElse: () => null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canCreate && !empty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => widget.onCreateClaim(progress),
              icon: const Icon(Icons.add_rounded),
              label: Text(_t(widget.language, 'prepare_claim')),
            ),
          ),
        if (canCreate && !empty) const SizedBox(height: AppSpacing.md),
        _AccountsMetricStrip(
          items: [
            (
              Icons.edit_note_outlined,
              const Color(0xFF1766D5),
              _t(widget.language, 'claim_drafts'),
              _money(draftClaims),
              '${claims.where((claim) => claim.status == YorksAccountsClaimStatus.draft).length} ${_t(widget.language, 'claims').toLowerCase()}',
            ),
            (
              Icons.verified_outlined,
              const Color(0xFF0D9D61),
              _t(widget.language, 'ready_for_invoicing'),
              _money(readyClaims),
              '${claims.where((claim) => claim.status == YorksAccountsClaimStatus.readyForAccounts).length} ${_t(widget.language, 'claims').toLowerCase()}',
            ),
            (
              Icons.receipt_long_outlined,
              const Color(0xFF7C4DDB),
              _t(widget.language, 'submitted_invoices'),
              _money(submitted),
              '${invoices.length} ${_t(widget.language, 'invoices').toLowerCase()}',
            ),
            (
              Icons.fact_check_outlined,
              const Color(0xFF12A066),
              _t(widget.language, 'client_certified'),
              _money(certified),
              _t(widget.language, 'net_excluding_vat'),
            ),
            (
              Icons.warning_amber_rounded,
              const Color(0xFFD85B45),
              _t(widget.language, 'still_due'),
              _money(stillDue),
              '${invoices.where((invoice) => invoice.dueState == YorksAccountsDueState.overdue).length} ${_t(widget.language, 'overdue').toLowerCase()}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!empty) ...[
          _ClaimsPipelineSummary(
            claims: claims,
            invoices: invoices,
            language: widget.language,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _InvoiceRegisterFilters(
          language: widget.language,
          claimStatus: _claimStatus,
          invoiceStatus: _invoiceStatus,
          dueState: _dueState,
          activeFilterCount: _activeFilterCount,
          onApply: _applyFilters,
        ),
        const SizedBox(height: AppSpacing.md),
        if (empty)
          _EmptyPanel(
            icon: Icons.receipt_long_outlined,
            title: _t(
              widget.language,
              _activeFilterCount == 0 ? 'no_records' : 'no_invoice_results',
            ),
            action: _activeFilterCount > 0
                ? _applyFilters
                : canCreate
                ? () => widget.onCreateClaim(progress)
                : null,
            actionLabel: _activeFilterCount > 0
                ? _t(widget.language, 'clear')
                : canCreate
                ? _t(widget.language, 'prepare_claim')
                : null,
          ),
        if (!empty)
          LayoutBuilder(
            builder: (context, constraints) {
              final register = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (claims.isNotEmpty)
                    _RegisterList(
                      title: _t(widget.language, 'recent_claims'),
                      children: [
                        for (final claim in claims)
                          _RegisterRow(
                            icon: Icons.fact_check_outlined,
                            title: claim.claimReference,
                            subtitle:
                                '${_wireLabel(widget.language, claim.status.wireValue)} · '
                                '${claim.periodStart} – ${claim.periodEnd}',
                            values: [_money(claim.claimedExVat)],
                            onTap: progress == null
                                ? null
                                : () => widget.onOpenClaim(
                                    claim.claimId,
                                    progress,
                                  ),
                            actionLabel: _t(widget.language, 'open_action'),
                          ),
                      ],
                    ),
                  if (claims.isNotEmpty && invoices.isNotEmpty)
                    const SizedBox(height: AppSpacing.lg),
                  if (invoices.isNotEmpty)
                    _InvoiceRegister(
                      invoices: invoices,
                      language: widget.language,
                      selectedInvoiceId: selectedInvoice?.invoiceId,
                      onSelect: (invoice) => setState(
                        () => _selectedInvoiceId = invoice.invoiceId,
                      ),
                      onOpen: widget.onOpenInvoice,
                    ),
                ],
              );
              if (constraints.maxWidth < 1120 || selectedInvoice == null) {
                return register;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: register),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 318,
                    child: _InvoiceDetailsPanel(
                      invoice: selectedInvoice,
                      claim: selectedClaim,
                      language: widget.language,
                      onOpen: () =>
                          widget.onOpenInvoice(selectedInvoice.invoiceId),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ClaimsPipelineSummary extends StatelessWidget {
  const _ClaimsPipelineSummary({
    required this.claims,
    required this.invoices,
    required this.language,
  });

  final List<YorksAccountsClientClaimSummary> claims;
  final List<YorksAccountsClientInvoiceSummary> invoices;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final claimDrafts = claims
        .where((claim) => claim.status == YorksAccountsClaimStatus.draft)
        .length;
    final ready = claims
        .where(
          (claim) => claim.status == YorksAccountsClaimStatus.readyForAccounts,
        )
        .length;
    final submittedInvoiceCount = invoices
        .where(
          (invoice) =>
              invoice.status != YorksAccountsInvoiceStatus.draft &&
              invoice.status != YorksAccountsInvoiceStatus.cancelled,
        )
        .length;
    final certifiedInvoiceCount = invoices
        .where((invoice) => invoice.certifiedExVat.isPositive)
        .length;
    final submitted = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.claimedExVat,
    );
    final certified = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.certifiedExVat,
    );
    final paid = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.amountPaidTillDate,
    );
    final due = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.stillDue,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final pipeline = _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: _t(language, 'claims_pipeline')),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _PipelineStep(
                    number: 1,
                    label: _t(language, 'claim_drafts'),
                    value: '$claimDrafts',
                    color: AppColors.primary,
                  ),
                  _PipelineStep(
                    number: 2,
                    label: _t(language, 'ready_for_invoicing'),
                    value: '$ready',
                    color: AppColors.success,
                  ),
                  _PipelineStep(
                    number: 3,
                    label: _t(language, 'submitted_invoices'),
                    value: '$submittedInvoiceCount',
                    color: AppColors.purple,
                  ),
                  _PipelineStep(
                    number: 4,
                    label: _t(language, 'client_certified'),
                    value: '$certifiedInvoiceCount',
                    color: AppColors.success,
                  ),
                ],
              ),
            ],
          ),
        );
        final summary = _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: _t(language, 'invoice_certification_summary'),
              ),
              const SizedBox(height: AppSpacing.md),
              _CommercialBar(
                label: _t(language, 'submitted_invoices'),
                amount: submitted,
                maximum: submitted,
                color: AppColors.primary,
              ),
              _CommercialBar(
                label: _t(language, 'client_certified'),
                amount: certified,
                maximum: submitted,
                color: AppColors.success,
              ),
              _CommercialBar(
                label: _t(language, 'paid_till_date'),
                amount: paid,
                maximum: submitted,
                color: AppColors.tertiary,
              ),
              _CommercialBar(
                label: _t(language, 'still_due'),
                amount: due,
                maximum: submitted,
                color: AppColors.warning,
              ),
            ],
          ),
        );
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pipeline,
              const SizedBox(height: AppSpacing.md),
              summary,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: pipeline),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: summary),
          ],
        );
      },
    );
  }
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({
    required this.number,
    required this.label,
    required this.value,
    required this.color,
  });

  final int number;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 178,
    constraints: const BoxConstraints(minHeight: 86),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: color,
          foregroundColor: AppColors.onPrimary,
          child: Text('$number', style: AppTypography.labelSmall),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: AppTypography.titleLarge),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CommercialBar extends StatelessWidget {
  const _CommercialBar({
    required this.label,
    required this.amount,
    required this.maximum,
    required this.color,
  });

  final String label;
  final YorksAccountsDecimal amount;
  final YorksAccountsDecimal maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = double.tryParse(maximum.canonicalText) ?? 0;
    final value = double.tryParse(amount.canonicalText) ?? 0;
    final progress = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.bodySmall)),
              Text(_money(amount), style: AppTypography.labelMedium),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
            color: color,
            backgroundColor: AppColors.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class _InvoiceDetailsPanel extends StatelessWidget {
  const _InvoiceDetailsPanel({
    required this.invoice,
    required this.claim,
    required this.language,
    required this.onOpen,
  });

  final YorksAccountsClientInvoiceSummary invoice;
  final YorksAccountsClientClaimSummary? claim;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t(language, 'invoice_details'),
                style: AppTypography.titleMedium,
              ),
            ),
            _Badge(_wireLabel(language, invoice.status.wireValue)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(invoice.invoiceReference, style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.md),
        _DetailLine(
          label: _t(language, 'related_claim'),
          value: claim?.claimReference ?? '—',
        ),
        _DetailLine(
          label: _t(language, 'submitted'),
          value: '${invoice.submissionDate ?? '—'}',
        ),
        _DetailLine(
          label: _t(language, 'due_date'),
          value: '${invoice.dueDate ?? '—'}',
        ),
        _DetailLine(
          label: _t(language, 'claimed_ex_vat'),
          value: _money(invoice.claimedExVat),
        ),
        _DetailLine(
          label: _t(language, 'certified_ex_vat'),
          value: _money(invoice.certifiedExVat),
        ),
        _DetailLine(
          label: _t(language, 'paid_till_date'),
          value: _money(invoice.amountPaidTillDate),
          valueColor: AppColors.success,
        ),
        _DetailLine(
          label: _t(language, 'still_due'),
          value: _money(invoice.stillDue),
          valueColor: invoice.stillDue.isPositive ? AppColors.error : null,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(_t(language, 'open_action')),
        ),
      ],
    ),
  );
}

class _ReceiptsPdcView extends StatefulWidget {
  const _ReceiptsPdcView({
    required this.projectId,
    required this.state,
    required this.language,
    required this.onRetry,
    required this.onOpenInvoice,
  });
  final String projectId;
  final YorksAccountsReceivablesState state;
  final AppLanguage language;
  final VoidCallback onRetry;
  final Future<bool> Function(String invoiceId) onOpenInvoice;

  @override
  State<_ReceiptsPdcView> createState() => _ReceiptsPdcViewState();
}

class _ReceiptsPdcViewState extends State<_ReceiptsPdcView> {
  String? _selectedLedgerEntryId;

  @override
  Widget build(BuildContext context) {
    final entries = widget.state.ledger?.entries;
    final invoices = widget.state.invoices?.invoices;
    if (entries == null || invoices == null) {
      return _AccountsStatePanel(
        status: widget.state.status,
        language: widget.language,
        error: widget.state.error,
        onRetry: widget.onRetry,
      );
    }
    final receiptTotal = entries
        .where((entry) => entry.payment != null)
        .fold<YorksAccountsDecimal>(YorksAccountsDecimal.zero, (total, entry) {
          final payment = entry.payment!;
          return payment.entryKind == YorksAccountsPaymentEntryKind.reversal
              ? total - payment.amount
              : total + payment.amount;
        });
    final pdcEvents = entries.where((entry) => entry.pdcEvent != null).toList();
    final stillDue = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.stillDue,
    );
    final certified = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.certifiedExVat,
    );
    final pdcExposure = invoices.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, invoice) => value + invoice.pdcExposure,
    );
    final overdue = invoices
        .where((invoice) => invoice.dueState == YorksAccountsDueState.overdue)
        .length;
    final cleared = pdcEvents
        .where(
          (entry) => entry.pdcEvent!.toStatus == YorksAccountsPdcStatus.cleared,
        )
        .length;
    final selected = entries
        .cast<YorksAccountsReceivablesLedgerEntry?>()
        .firstWhere(
          (entry) => entry?.ledgerEntryId == _selectedLedgerEntryId,
          orElse: () => entries.isEmpty ? null : entries.first,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountsMetricStrip(
          items: [
            (
              Icons.payments_outlined,
              const Color(0xFF0D9D61),
              _t(widget.language, 'actual_receipts_gross'),
              _money(receiptTotal),
              _t(widget.language, 'cash_received_clients'),
            ),
            (
              Icons.schedule_outlined,
              const Color(0xFFE18418),
              _t(widget.language, 'still_due_gross'),
              _money(stillDue),
              _t(widget.language, 'certified_balance_outstanding'),
            ),
            (
              Icons.credit_card_outlined,
              const Color(0xFF7C4DDB),
              _t(widget.language, 'active_pdc_exposure'),
              _money(pdcExposure),
              _t(widget.language, 'held_not_deducted'),
            ),
            (
              Icons.warning_amber_rounded,
              const Color(0xFFD84C4C),
              _t(widget.language, 'overdue_certified_invoices'),
              '$overdue',
              _t(widget.language, 'invoices_past_due'),
            ),
            (
              Icons.query_stats_rounded,
              const Color(0xFF1766D5),
              _t(widget.language, 'cleared_this_month'),
              '$cleared',
              _t(widget.language, 'pdc_receipts_month'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _CollectionsSummary(
          certified: certified,
          received: receiptTotal,
          stillDue: stillDue,
          pdcExposure: pdcExposure,
          pdcEvents: pdcEvents,
          language: widget.language,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final register = entries.isEmpty
                ? _EmptyPanel(
                    icon: Icons.payments_outlined,
                    title: _t(widget.language, 'no_records'),
                  )
                : _RegisterList(
                    title: _t(widget.language, 'receipts_pdc'),
                    children: [
                      for (final entry in entries)
                        _SelectableRegisterRow(
                          selected:
                              entry.ledgerEntryId == selected?.ledgerEntryId,
                          icon: entry.payment == null
                              ? Icons.event_note_outlined
                              : Icons.payments_outlined,
                          title:
                              entry.payment?.paymentReference ??
                              _wireLabel(
                                widget.language,
                                entry.pdcEvent?.toStatus.wireValue ?? 'pdc',
                              ),
                          subtitle:
                              '${entry.occurredAt.toLocal()} · ${entry.invoiceId}',
                          values: [
                            if (entry.payment != null)
                              _money(entry.payment!.amount),
                          ],
                          onSelect: () => setState(
                            () => _selectedLedgerEntryId = entry.ledgerEntryId,
                          ),
                          onOpen: () => widget.onOpenInvoice(entry.invoiceId),
                          actionLabel: _t(widget.language, 'open_action'),
                        ),
                    ],
                  );
            if (constraints.maxWidth < 1120 || selected == null) {
              return register;
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: register),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 318,
                  child: _ReceivableLedgerDetailsPanel(
                    entry: selected,
                    language: widget.language,
                    onOpenInvoice: () =>
                        widget.onOpenInvoice(selected.invoiceId),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SupplierBillsView extends StatefulWidget {
  const _SupplierBillsView({
    required this.projectId,
    required this.state,
    required this.language,
    required this.onRetry,
    required this.onFilter,
    required this.onCreate,
    required this.onOpen,
  });
  final String projectId;
  final YorksAccountsSupplierState state;
  final AppLanguage language;
  final VoidCallback onRetry;
  final Future<bool> Function({
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
  })
  onFilter;
  final Future<bool> Function() onCreate;
  final Future<bool> Function(String supplierBillId) onOpen;

  @override
  State<_SupplierBillsView> createState() => _SupplierBillsViewState();
}

class _SupplierBillsViewState extends State<_SupplierBillsView> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  YorksAccountsSupplierMatchStatus? _matchStatus;
  YorksAccountsSupplierPaymentStatus? _paymentStatus;
  String? _selectedBillId;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int get _activeFilterCount => [
    _searchController.text.trim().isEmpty ? null : _searchController.text,
    _matchStatus,
    _paymentStatus,
  ].where((value) => value != null).length;

  Future<void> _applyFilters({
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
  }) async {
    if (search != null && search != _searchController.text) {
      _searchController.text = search;
    }
    setState(() {
      _matchStatus = matchStatus;
      _paymentStatus = paymentStatus;
    });
    await widget.onFilter(
      search: _searchController.text,
      matchStatus: matchStatus,
      paymentStatus: paymentStatus,
    );
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 320),
      () => _applyFilters(
        matchStatus: _matchStatus,
        paymentStatus: _paymentStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = widget.state.bills?.items;
    if (bills == null) {
      return _AccountsStatePanel(
        status: widget.state.status,
        language: widget.language,
        error: widget.state.error,
        onRetry: widget.onRetry,
      );
    }
    final canCreate = widget.state.bills!.commands.createBill;
    final total = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.totalInclVat,
    );
    final approved = bills
        .where(
          (bill) => bill.status == YorksAccountsSupplierBillStatus.approved,
        )
        .fold<YorksAccountsDecimal>(
          YorksAccountsDecimal.zero,
          (value, bill) => value + bill.totalInclVat,
        );
    final paid = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.paidAmount,
    );
    final outstanding = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.outstandingAmount,
    );
    final exceptions = bills
        .where(
          (bill) =>
              bill.matchStatus != YorksAccountsSupplierMatchStatus.matched,
        )
        .length;
    final selectedBill = bills.cast<YorksAccountsSupplierBill?>().firstWhere(
      (bill) => bill?.supplierBillId == _selectedBillId,
      orElse: () => bills.isEmpty ? null : bills.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canCreate)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(_t(widget.language, 'new_supplier_bill')),
            ),
          ),
        if (canCreate) const SizedBox(height: AppSpacing.md),
        _AccountsMetricStrip(
          items: [
            (
              Icons.description_outlined,
              const Color(0xFF1766D5),
              _t(widget.language, 'supplier_bills_total'),
              _money(total),
              '${bills.length} ${_t(widget.language, 'supplier_bills').toLowerCase()}',
            ),
            (
              Icons.task_alt_rounded,
              const Color(0xFF0D9D61),
              _t(widget.language, 'approved_for_payment'),
              _money(approved),
              _t(widget.language, 'gross_including_vat'),
            ),
            (
              Icons.payments_outlined,
              const Color(0xFF0B9C61),
              _t(widget.language, 'paid_to_suppliers'),
              _money(paid),
              _t(widget.language, 'gross_including_vat'),
            ),
            (
              Icons.schedule_outlined,
              const Color(0xFFE18418),
              _t(widget.language, 'unpaid_supplier_balance'),
              _money(outstanding),
              _t(widget.language, 'gross_including_vat'),
            ),
            (
              Icons.warning_amber_rounded,
              const Color(0xFFD84C4C),
              _t(widget.language, 'evidence_exceptions'),
              '$exceptions',
              _t(widget.language, 'bills_require_attention'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (bills.isNotEmpty) ...[
          _SupplierEvidenceSummary(bills: bills, language: widget.language),
          const SizedBox(height: AppSpacing.md),
        ],
        _SupplierRegisterFilters(
          language: widget.language,
          searchController: _searchController,
          matchStatus: _matchStatus,
          paymentStatus: _paymentStatus,
          activeFilterCount: _activeFilterCount,
          onSearchChanged: _onSearchChanged,
          onApply: _applyFilters,
        ),
        const SizedBox(height: AppSpacing.md),
        if (bills.isEmpty)
          _EmptyPanel(
            icon: Icons.inventory_2_outlined,
            title: _t(
              widget.language,
              _activeFilterCount == 0 ? 'no_records' : 'no_supplier_results',
            ),
            action: _activeFilterCount > 0
                ? _applyFilters
                : canCreate
                ? widget.onCreate
                : null,
            actionLabel: _activeFilterCount > 0
                ? _t(widget.language, 'clear')
                : canCreate
                ? _t(widget.language, 'new_supplier_bill')
                : null,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final register = _SupplierBillRegister(
                bills: bills,
                language: widget.language,
                selectedBillId: selectedBill?.supplierBillId,
                onSelect: (bill) =>
                    setState(() => _selectedBillId = bill.supplierBillId),
                onOpen: widget.onOpen,
              );
              if (constraints.maxWidth < 1120 || selectedBill == null) {
                return register;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: register),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 318,
                    child: _SupplierBillDetailsPanel(
                      bill: selectedBill,
                      language: widget.language,
                      onOpen: () => widget.onOpen(selectedBill.supplierBillId),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _CollectionsSummary extends StatelessWidget {
  const _CollectionsSummary({
    required this.certified,
    required this.received,
    required this.stillDue,
    required this.pdcExposure,
    required this.pdcEvents,
    required this.language,
  });

  final YorksAccountsDecimal certified;
  final YorksAccountsDecimal received;
  final YorksAccountsDecimal stillDue;
  final YorksAccountsDecimal pdcExposure;
  final List<YorksAccountsReceivablesLedgerEntry> pdcEvents;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final counts = <YorksAccountsPdcStatus, int>{};
    for (final entry in pdcEvents) {
      final status = entry.pdcEvent!.toStatus;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    final maximum = certified.compareTo(stillDue) >= 0 ? certified : stillDue;
    final collectionPanel = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: _t(language, 'collections_summary')),
          const SizedBox(height: 4),
          Text(
            _t(language, 'collections_subtitle'),
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          _CommercialBar(
            label: _t(language, 'client_certified'),
            amount: certified,
            maximum: maximum,
            color: AppColors.primary,
          ),
          _CommercialBar(
            label: _t(language, 'actual_receipts_gross'),
            amount: received,
            maximum: maximum,
            color: AppColors.success,
          ),
          _CommercialBar(
            label: _t(language, 'still_due_gross'),
            amount: stillDue,
            maximum: maximum,
            color: AppColors.warning,
          ),
          _CommercialBar(
            label: _t(language, 'active_pdc_exposure'),
            amount: pdcExposure,
            maximum: maximum,
            color: AppColors.purple,
          ),
          const SizedBox(height: AppSpacing.sm),
          _InlineNotice(
            icon: Icons.info_outline_rounded,
            message: _t(language, 'held_pdc_note'),
          ),
        ],
      ),
    );
    final statusPanel = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: _t(language, 'pdc_instrument_status')),
          const SizedBox(height: AppSpacing.md),
          if (counts.isEmpty)
            Text(_t(language, 'no_records'), style: AppTypography.bodyMedium)
          else
            for (final entry in counts.entries)
              _DetailLine(
                label: _wireLabel(language, entry.key.wireValue),
                value: '${entry.value}',
                valueColor: _statusColor(entry.key.wireValue),
              ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              collectionPanel,
              const SizedBox(height: AppSpacing.md),
              statusPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: collectionPanel),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: statusPanel),
          ],
        );
      },
    );
  }
}

class _ReceivableLedgerDetailsPanel extends StatelessWidget {
  const _ReceivableLedgerDetailsPanel({
    required this.entry,
    required this.language,
    required this.onOpenInvoice,
  });

  final YorksAccountsReceivablesLedgerEntry entry;
  final AppLanguage language;
  final VoidCallback onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    final payment = entry.payment;
    final pdc = entry.pdcEvent;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            payment == null
                ? _t(language, 'pdc_instrument_details')
                : _t(language, 'receipt_entries'),
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            payment?.paymentReference ?? pdc?.pdcId ?? '—',
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          _DetailLine(
            label: _t(language, 'linked_invoice'),
            value: entry.invoiceId,
          ),
          if (payment != null) ...[
            _DetailLine(
              label: _t(language, 'receipt_date'),
              value: '${payment.paymentDate}',
            ),
            _DetailLine(
              label: _t(language, 'method'),
              value: payment.paymentMethod,
            ),
            _DetailLine(
              label: _t(language, 'total'),
              value: _money(payment.amount),
              valueColor: AppColors.success,
            ),
          ],
          if (pdc != null) ...[
            _DetailLine(
              label: _t(language, 'status'),
              value: _wireLabel(language, pdc.toStatus.wireValue),
              valueColor: _statusColor(pdc.toStatus.wireValue),
            ),
            _DetailLine(
              label: _t(language, 'cheque_date'),
              value: '${pdc.actionDate}',
            ),
            _DetailLine(
              label: _t(language, 'revision'),
              value: '${pdc.sequenceNumber}',
            ),
            if (pdc.reason != null)
              _DetailLine(label: _t(language, 'reason'), value: pdc.reason!),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onOpenInvoice,
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(_t(language, 'open_invoice')),
          ),
        ],
      ),
    );
  }
}

class _SupplierEvidenceSummary extends StatelessWidget {
  const _SupplierEvidenceSummary({required this.bills, required this.language});

  final List<YorksAccountsSupplierBill> bills;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final total = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.totalInclVat,
    );
    final paid = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.paidAmount,
    );
    final outstanding = bills.fold<YorksAccountsDecimal>(
      YorksAccountsDecimal.zero,
      (value, bill) => value + bill.outstandingAmount,
    );
    final matched = bills
        .where(
          (bill) =>
              bill.matchStatus == YorksAccountsSupplierMatchStatus.matched,
        )
        .length;
    final review = bills
        .where(
          (bill) => bill.matchStatus == YorksAccountsSupplierMatchStatus.review,
        )
        .length;
    final blocked = bills.length - matched - review;
    final evidencePanel = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: _t(language, 'evidence_completeness')),
          const SizedBox(height: AppSpacing.md),
          _DetailLine(
            label: _wireLabel(language, 'matched'),
            value: '$matched',
            valueColor: AppColors.success,
          ),
          _DetailLine(
            label: _wireLabel(language, 'review'),
            value: '$review',
            valueColor: AppColors.warning,
          ),
          _DetailLine(
            label: _wireLabel(language, 'blocked'),
            value: '$blocked',
            valueColor: AppColors.error,
          ),
        ],
      ),
    );
    final outlookPanel = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: _t(language, 'payment_outlook')),
          const SizedBox(height: AppSpacing.md),
          _CommercialBar(
            label: _t(language, 'supplier_bills_total'),
            amount: total,
            maximum: total,
            color: AppColors.primary,
          ),
          _CommercialBar(
            label: _t(language, 'paid_to_suppliers'),
            amount: paid,
            maximum: total,
            color: AppColors.success,
          ),
          _CommercialBar(
            label: _t(language, 'unpaid_supplier_balance'),
            amount: outstanding,
            maximum: total,
            color: AppColors.warning,
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              evidencePanel,
              const SizedBox(height: AppSpacing.md),
              outlookPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: evidencePanel),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 3, child: outlookPanel),
          ],
        );
      },
    );
  }
}

class _SupplierBillDetailsPanel extends StatelessWidget {
  const _SupplierBillDetailsPanel({
    required this.bill,
    required this.language,
    required this.onOpen,
  });

  final YorksAccountsSupplierBill bill;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t(language, 'supplier_bill_detail'),
                style: AppTypography.titleMedium,
              ),
            ),
            _Badge(_wireLabel(language, bill.status.wireValue)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(bill.supplierInvoiceReference, style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.md),
        _DetailLine(label: _t(language, 'supplier'), value: bill.supplierName),
        _DetailLine(
          label: _t(language, 'gross_including_vat'),
          value: _money(bill.totalInclVat),
        ),
        _DetailLine(
          label: _t(language, 'invoice_date'),
          value: '${bill.invoiceDate}',
        ),
        _DetailLine(label: _t(language, 'due_date'), value: '${bill.dueDate}'),
        _DetailLine(
          label: _t(language, 'match_status'),
          value: _wireLabel(language, bill.matchStatus.wireValue),
          valueColor: _statusColor(bill.matchStatus.wireValue),
        ),
        _DetailLine(
          label: _t(language, 'payment_status'),
          value: _wireLabel(language, bill.paymentStatus.wireValue),
          valueColor: _statusColor(bill.paymentStatus.wireValue),
        ),
        _DetailLine(
          label: _t(language, 'po_lpo'),
          value: bill.poLpoReference ?? '—',
        ),
        _DetailLine(
          label: _t(language, 'accepted_delivery'),
          value: bill.acceptedDeliveryReference ?? '—',
        ),
        _DetailLine(
          label: _t(language, 'paid_to_suppliers'),
          value: _money(bill.paidAmount),
          valueColor: AppColors.success,
        ),
        _DetailLine(
          label: _t(language, 'unpaid_supplier_balance'),
          value: _money(bill.outstandingAmount),
          valueColor: bill.outstandingAmount.isPositive
              ? AppColors.error
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(_t(language, 'open_action')),
        ),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: AppTypography.bodySmall)),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.labelMedium.copyWith(color: valueColor),
          ),
        ),
      ],
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: const Border(
        left: BorderSide(color: AppColors.primary, width: 3),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message, style: AppTypography.bodySmall)),
      ],
    ),
  );
}

class _SelectableRegisterRow extends StatelessWidget {
  const _SelectableRegisterRow({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.values,
    required this.onSelect,
    required this.onOpen,
    required this.actionLabel,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> values;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primaryContainer : Colors.transparent,
    child: InkWell(
      onTap: onSelect,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            _IconTile(icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TwoLine(title: title, subtitle: subtitle),
            ),
            for (final value in values)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.md),
                child: Text(value, style: AppTypography.titleSmall),
              ),
            IconButton(
              tooltip: actionLabel,
              onPressed: onOpen,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InvoiceRegister extends StatelessWidget {
  const _InvoiceRegister({
    required this.invoices,
    required this.language,
    required this.selectedInvoiceId,
    required this.onSelect,
    required this.onOpen,
  });
  final List<YorksAccountsClientInvoiceSummary> invoices;
  final AppLanguage language;
  final String? selectedInvoiceId;
  final ValueChanged<YorksAccountsClientInvoiceSummary> onSelect;
  final Future<bool> Function(String invoiceId) onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 760) {
        return _RegisterList(
          title: _t(language, 'invoices'),
          children: [
            for (final invoice in invoices)
              _RegisterRow(
                icon: Icons.receipt_long_outlined,
                title: invoice.invoiceReference,
                subtitle:
                    '${_wireLabel(language, invoice.status.wireValue)} · '
                    '${invoice.dueDate ?? '—'}',
                values: [
                  _money(invoice.claimedExVat),
                  _money(invoice.certifiedExVat),
                  _money(invoice.totalInclVat),
                  _money(invoice.amountPaidTillDate),
                  _money(invoice.stillDue),
                ],
                onTap: () => onOpen(invoice.invoiceId),
                actionLabel: _t(language, 'open_action'),
              ),
          ],
        );
      }
      return _Panel(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: _t(language, 'invoices')),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 72,
                columns: [
                  DataColumn(label: Text(_t(language, 'invoice_period'))),
                  DataColumn(label: Text(_t(language, 'status'))),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'claimed_ex_vat')),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'certified_ex_vat')),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'total_incl_vat')),
                  ),
                  DataColumn(label: Text(_t(language, 'submitted'))),
                  DataColumn(label: Text(_t(language, 'due_alert'))),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'payment_pdc')),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'paid_till_date')),
                  ),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'still_due')),
                  ),
                  DataColumn(label: Text(_t(language, 'action'))),
                ],
                rows: [
                  for (final invoice in invoices)
                    DataRow(
                      selected: invoice.invoiceId == selectedInvoiceId,
                      onSelectChanged: (_) => onSelect(invoice),
                      cells: [
                        DataCell(Text(invoice.invoiceReference)),
                        DataCell(
                          _StatusWithIcon(
                            icon: _statusIcon(invoice.status.wireValue),
                            label: _wireLabel(
                              language,
                              invoice.status.wireValue,
                            ),
                          ),
                        ),
                        DataCell(Text(_money(invoice.claimedExVat))),
                        DataCell(Text(_money(invoice.certifiedExVat))),
                        DataCell(Text(_money(invoice.totalInclVat))),
                        DataCell(Text('${invoice.submissionDate ?? '—'}')),
                        DataCell(
                          _TwoLine(
                            title: '${invoice.dueDate ?? '—'}',
                            subtitle: invoice.dueState == null
                                ? '—'
                                : _wireLabel(
                                    language,
                                    invoice.dueState!.wireValue,
                                  ),
                          ),
                        ),
                        DataCell(Text(_money(invoice.pdcExposure))),
                        DataCell(Text(_money(invoice.amountPaidTillDate))),
                        DataCell(Text(_money(invoice.stillDue))),
                        DataCell(
                          IconButton(
                            tooltip: _t(language, 'open_action'),
                            onPressed: () => onOpen(invoice.invoiceId),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SupplierBillRegister extends StatelessWidget {
  const _SupplierBillRegister({
    required this.bills,
    required this.language,
    required this.selectedBillId,
    required this.onSelect,
    required this.onOpen,
  });
  final List<YorksAccountsSupplierBill> bills;
  final AppLanguage language;
  final String? selectedBillId;
  final ValueChanged<YorksAccountsSupplierBill> onSelect;
  final Future<bool> Function(String supplierBillId) onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 760) {
        return _RegisterList(
          title: _t(language, 'supplier_bills'),
          children: [
            for (final bill in bills)
              _RegisterRow(
                icon: Icons.inventory_2_outlined,
                title: bill.supplierInvoiceReference,
                subtitle:
                    '${bill.supplierName} · '
                    '${_wireLabel(language, bill.matchStatus.wireValue)} · '
                    '${bill.dueDate}',
                values: [
                  _money(bill.totalInclVat),
                  _money(bill.paidAmount),
                  _money(bill.outstandingAmount),
                ],
                onTap: () => onOpen(bill.supplierBillId),
                actionLabel: _t(language, 'open_action'),
              ),
          ],
        );
      }
      return _Panel(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: _t(language, 'supplier_bills')),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 72,
                columns: [
                  DataColumn(label: Text(_t(language, 'supplier_invoice'))),
                  DataColumn(label: Text(_t(language, 'supplier'))),
                  DataColumn(label: Text(_t(language, 'invoice_date'))),
                  DataColumn(label: Text(_t(language, 'due_date'))),
                  DataColumn(
                    numeric: true,
                    label: Text(_t(language, 'ex_vat')),
                  ),
                  DataColumn(numeric: true, label: Text(_t(language, 'vat'))),
                  DataColumn(numeric: true, label: Text(_t(language, 'total'))),
                  DataColumn(label: Text(_t(language, 'po_lpo'))),
                  DataColumn(label: Text(_t(language, 'accepted_delivery'))),
                  DataColumn(label: Text(_t(language, 'invoice_evidence'))),
                  DataColumn(label: Text(_t(language, 'match_status'))),
                  DataColumn(label: Text(_t(language, 'payment_status'))),
                  DataColumn(label: Text(_t(language, 'action'))),
                ],
                rows: [
                  for (final bill in bills)
                    DataRow(
                      selected: bill.supplierBillId == selectedBillId,
                      onSelectChanged: (_) => onSelect(bill),
                      cells: [
                        DataCell(Text(bill.supplierInvoiceReference)),
                        DataCell(Text(bill.supplierName)),
                        DataCell(Text('${bill.invoiceDate}')),
                        DataCell(Text('${bill.dueDate}')),
                        DataCell(Text(_money(bill.exVatAmount))),
                        DataCell(Text(_money(bill.vatAmount))),
                        DataCell(Text(_money(bill.totalInclVat))),
                        DataCell(
                          _EvidenceState(
                            present: bill.poLpoDocumentId != null,
                            label: bill.poLpoReference,
                            language: language,
                          ),
                        ),
                        DataCell(
                          _EvidenceState(
                            present: bill.acceptedDelivery != null,
                            label: bill.acceptedDeliveryReference,
                            language: language,
                          ),
                        ),
                        DataCell(
                          _EvidenceState(
                            present: bill.supplierInvoiceDocumentId != null,
                            language: language,
                          ),
                        ),
                        DataCell(
                          _StatusWithIcon(
                            icon: _statusIcon(bill.matchStatus.wireValue),
                            label: _wireLabel(
                              language,
                              bill.matchStatus.wireValue,
                            ),
                          ),
                        ),
                        DataCell(
                          _StatusWithIcon(
                            icon: _statusIcon(bill.paymentStatus.wireValue),
                            label: _wireLabel(
                              language,
                              bill.paymentStatus.wireValue,
                            ),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            tooltip: _t(language, 'open_action'),
                            onPressed: () => onOpen(bill.supplierBillId),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StatusWithIcon extends StatelessWidget {
  const _StatusWithIcon({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.inkSecondary),
      const SizedBox(width: AppSpacing.xs),
      Text(label),
    ],
  );
}

class _EvidenceState extends StatelessWidget {
  const _EvidenceState({
    required this.present,
    required this.language,
    this.label,
  });
  final bool present;
  final AppLanguage language;
  final String? label;
  @override
  Widget build(BuildContext context) => _StatusWithIcon(
    icon: present ? Icons.check_circle_outline : Icons.error_outline_rounded,
    label:
        label ??
        _t(language, present ? 'evidence_present' : 'missing_evidence'),
  );
}

class _InvoiceRegisterFilters extends StatelessWidget {
  const _InvoiceRegisterFilters({
    required this.language,
    required this.claimStatus,
    required this.invoiceStatus,
    required this.dueState,
    required this.activeFilterCount,
    required this.onApply,
  });

  final AppLanguage language;
  final YorksAccountsClaimStatus? claimStatus;
  final YorksAccountsInvoiceStatus? invoiceStatus;
  final YorksAccountsDueState? dueState;
  final int activeFilterCount;
  final Future<void> Function({
    YorksAccountsClaimStatus? claimStatus,
    YorksAccountsInvoiceStatus? invoiceStatus,
    YorksAccountsDueState? dueState,
  })
  onApply;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Badge.count(
            count: activeFilterCount,
            isLabelVisible: activeFilterCount > 0,
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => _InvoiceRegisterFilterSheet(
                  language: language,
                  claimStatus: claimStatus,
                  invoiceStatus: invoiceStatus,
                  dueState: dueState,
                  onApply: onApply,
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
              label: Text(_t(language, 'filters')),
            ),
          ),
        );
      }
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: _ProgressDropdown<YorksAccountsClaimStatus>(
              value: claimStatus,
              label: _t(language, 'claim_status'),
              allLabel: _t(language, 'all'),
              items: [
                for (final status in YorksAccountsClaimStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_wireLabel(language, status.wireValue)),
                  ),
              ],
              onChanged: (value) => onApply(
                claimStatus: value,
                invoiceStatus: invoiceStatus,
                dueState: dueState,
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: _ProgressDropdown<YorksAccountsInvoiceStatus>(
              value: invoiceStatus,
              label: _t(language, 'invoice_status'),
              allLabel: _t(language, 'all'),
              items: [
                for (final status in YorksAccountsInvoiceStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_wireLabel(language, status.wireValue)),
                  ),
              ],
              onChanged: (value) => onApply(
                claimStatus: claimStatus,
                invoiceStatus: value,
                dueState: dueState,
              ),
            ),
          ),
          SizedBox(
            width: 210,
            child: _ProgressDropdown<YorksAccountsDueState>(
              value: dueState,
              label: _t(language, 'due_state'),
              allLabel: _t(language, 'all'),
              items: [
                for (final status in YorksAccountsDueState.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_wireLabel(language, status.wireValue)),
                  ),
              ],
              onChanged: (value) => onApply(
                claimStatus: claimStatus,
                invoiceStatus: invoiceStatus,
                dueState: value,
              ),
            ),
          ),
          if (activeFilterCount > 0)
            TextButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(_t(language, 'clear')),
            ),
        ],
      );
    },
  );
}

class _InvoiceRegisterFilterSheet extends StatefulWidget {
  const _InvoiceRegisterFilterSheet({
    required this.language,
    required this.claimStatus,
    required this.invoiceStatus,
    required this.dueState,
    required this.onApply,
  });
  final AppLanguage language;
  final YorksAccountsClaimStatus? claimStatus;
  final YorksAccountsInvoiceStatus? invoiceStatus;
  final YorksAccountsDueState? dueState;
  final Future<void> Function({
    YorksAccountsClaimStatus? claimStatus,
    YorksAccountsInvoiceStatus? invoiceStatus,
    YorksAccountsDueState? dueState,
  })
  onApply;

  @override
  State<_InvoiceRegisterFilterSheet> createState() =>
      _InvoiceRegisterFilterSheetState();
}

class _InvoiceRegisterFilterSheetState
    extends State<_InvoiceRegisterFilterSheet> {
  late YorksAccountsClaimStatus? _claimStatus = widget.claimStatus;
  late YorksAccountsInvoiceStatus? _invoiceStatus = widget.invoiceStatus;
  late YorksAccountsDueState? _dueState = widget.dueState;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t(widget.language, 'filters'), style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        _ProgressDropdown<YorksAccountsClaimStatus>(
          value: _claimStatus,
          label: _t(widget.language, 'claim_status'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final status in YorksAccountsClaimStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(_wireLabel(widget.language, status.wireValue)),
              ),
          ],
          onChanged: (value) => setState(() => _claimStatus = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<YorksAccountsInvoiceStatus>(
          value: _invoiceStatus,
          label: _t(widget.language, 'invoice_status'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final status in YorksAccountsInvoiceStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(_wireLabel(widget.language, status.wireValue)),
              ),
          ],
          onChanged: (value) => setState(() => _invoiceStatus = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<YorksAccountsDueState>(
          value: _dueState,
          label: _t(widget.language, 'due_state'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final status in YorksAccountsDueState.values)
              DropdownMenuItem(
                value: status,
                child: Text(_wireLabel(widget.language, status.wireValue)),
              ),
          ],
          onChanged: (value) => setState(() => _dueState = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () async {
            await widget.onApply(
              claimStatus: _claimStatus,
              invoiceStatus: _invoiceStatus,
              dueState: _dueState,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_t(widget.language, 'apply_filters')),
        ),
        TextButton(
          onPressed: () async {
            await widget.onApply();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(_t(widget.language, 'clear')),
        ),
      ],
    ),
  );
}

class _SupplierRegisterFilters extends StatelessWidget {
  const _SupplierRegisterFilters({
    required this.language,
    required this.searchController,
    required this.matchStatus,
    required this.paymentStatus,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onApply,
  });
  final AppLanguage language;
  final TextEditingController searchController;
  final YorksAccountsSupplierMatchStatus? matchStatus;
  final YorksAccountsSupplierPaymentStatus? paymentStatus;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function({
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
  })
  onApply;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        decoration: InputDecoration(
          labelText: _t(language, 'supplier_search'),
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
        ),
      );
      if (constraints.maxWidth < 720) {
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: AppSpacing.sm),
            Badge.count(
              count: activeFilterCount,
              isLabelVisible: activeFilterCount > 0,
              child: IconButton.outlined(
                tooltip: _t(language, 'filters'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (_) => _SupplierRegisterFilterSheet(
                    language: language,
                    matchStatus: matchStatus,
                    paymentStatus: paymentStatus,
                    onApply: onApply,
                  ),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
        );
      }
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 320, child: search),
          SizedBox(
            width: 210,
            child: _ProgressDropdown<YorksAccountsSupplierMatchStatus>(
              value: matchStatus,
              label: _t(language, 'match_status'),
              allLabel: _t(language, 'all'),
              items: [
                for (final status in YorksAccountsSupplierMatchStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_wireLabel(language, status.wireValue)),
                  ),
              ],
              onChanged: (value) =>
                  onApply(matchStatus: value, paymentStatus: paymentStatus),
            ),
          ),
          SizedBox(
            width: 220,
            child: _ProgressDropdown<YorksAccountsSupplierPaymentStatus>(
              value: paymentStatus,
              label: _t(language, 'payment_status'),
              allLabel: _t(language, 'all'),
              items: [
                for (final status in YorksAccountsSupplierPaymentStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_wireLabel(language, status.wireValue)),
                  ),
              ],
              onChanged: (value) =>
                  onApply(matchStatus: matchStatus, paymentStatus: value),
            ),
          ),
          if (activeFilterCount > 0)
            TextButton.icon(
              onPressed: () {
                searchController.clear();
                onApply();
              },
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(_t(language, 'clear')),
            ),
        ],
      );
    },
  );
}

class _SupplierRegisterFilterSheet extends StatefulWidget {
  const _SupplierRegisterFilterSheet({
    required this.language,
    required this.matchStatus,
    required this.paymentStatus,
    required this.onApply,
  });
  final AppLanguage language;
  final YorksAccountsSupplierMatchStatus? matchStatus;
  final YorksAccountsSupplierPaymentStatus? paymentStatus;
  final Future<void> Function({
    String? search,
    YorksAccountsSupplierMatchStatus? matchStatus,
    YorksAccountsSupplierPaymentStatus? paymentStatus,
  })
  onApply;

  @override
  State<_SupplierRegisterFilterSheet> createState() =>
      _SupplierRegisterFilterSheetState();
}

class _SupplierRegisterFilterSheetState
    extends State<_SupplierRegisterFilterSheet> {
  late YorksAccountsSupplierMatchStatus? _matchStatus = widget.matchStatus;
  late YorksAccountsSupplierPaymentStatus? _paymentStatus =
      widget.paymentStatus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t(widget.language, 'filters'), style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        _ProgressDropdown<YorksAccountsSupplierMatchStatus>(
          value: _matchStatus,
          label: _t(widget.language, 'match_status'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final status in YorksAccountsSupplierMatchStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(_wireLabel(widget.language, status.wireValue)),
              ),
          ],
          onChanged: (value) => setState(() => _matchStatus = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressDropdown<YorksAccountsSupplierPaymentStatus>(
          value: _paymentStatus,
          label: _t(widget.language, 'payment_status'),
          allLabel: _t(widget.language, 'all'),
          items: [
            for (final status in YorksAccountsSupplierPaymentStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(_wireLabel(widget.language, status.wireValue)),
              ),
          ],
          onChanged: (value) => setState(() => _paymentStatus = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () async {
            await widget.onApply(
              matchStatus: _matchStatus,
              paymentStatus: _paymentStatus,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(_t(widget.language, 'apply_filters')),
        ),
        TextButton(
          onPressed: () async {
            await widget.onApply();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(_t(widget.language, 'clear')),
        ),
      ],
    ),
  );
}

class _ProjectAccountsTabs extends StatefulWidget {
  const _ProjectAccountsTabs({
    required this.tabs,
    required this.selected,
    required this.language,
    required this.onSelected,
  });
  final List<YorksProjectAccountsTab> tabs;
  final YorksProjectAccountsTab selected;
  final AppLanguage language;
  final ValueChanged<YorksProjectAccountsTab> onSelected;

  @override
  State<_ProjectAccountsTabs> createState() => _ProjectAccountsTabsState();
}

class _ProjectAccountsTabsState extends State<_ProjectAccountsTabs> {
  final _selectedKey = GlobalKey();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _revealSelectedTab();
  }

  @override
  void didUpdateWidget(covariant _ProjectAccountsTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.tabs != widget.tabs) {
      _revealSelectedTab();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _revealSelectedTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedContext = _selectedKey.currentContext;
      if (!mounted ||
          selectedContext == null ||
          !_scrollController.hasClients) {
        return;
      }
      final selectedObject = selectedContext.findRenderObject();
      if (selectedObject == null) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      _scrollController.position.ensureVisible(
        selectedObject,
        alignment: 0.5,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in widget.tabs)
            InkWell(
              key: tab == widget.selected ? _selectedKey : null,
              onTap: () => widget.onSelected(tab),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                margin: const EdgeInsetsDirectional.only(end: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tab == widget.selected
                      ? const Color(0xFFEAF3FF)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: tab == widget.selected
                          ? AppColors.blue
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      switch (tab) {
                        YorksProjectAccountsTab.overview =>
                          Icons.dashboard_outlined,
                        YorksProjectAccountsTab.billing =>
                          Icons.bar_chart_rounded,
                        YorksProjectAccountsTab.invoices =>
                          Icons.receipt_long_outlined,
                        YorksProjectAccountsTab.receiptsPdc =>
                          Icons.payments_outlined,
                        YorksProjectAccountsTab.supplierBills =>
                          Icons.inventory_2_outlined,
                        YorksProjectAccountsTab.documents =>
                          Icons.description_outlined,
                        YorksProjectAccountsTab.activity =>
                          Icons.history_rounded,
                      },
                      size: 17,
                      color: tab == widget.selected
                          ? AppColors.blue
                          : AppColors.inkSecondary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _tabLabel(widget.language, tab),
                      style: AppTypography.labelMedium.copyWith(
                        color: tab == widget.selected
                            ? AppColors.blue
                            : AppColors.inkSecondary,
                        fontWeight: tab == widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
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

class _BillingFormulaStrip extends StatelessWidget {
  const _BillingFormulaStrip({
    required this.totals,
    required this.entries,
    required this.language,
  });

  final YorksAccountsProgressTotals totals;
  final List<YorksAccountsProgressEntry> entries;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final contractValue = totals.contractValue;
    final eligible = totals.confirmedEligible;
    final available = totals.availableToClaim;
    final pending = entries
        .where(
          (entry) => entry.reviewStatus == YorksAccountsReviewStatus.pending,
        )
        .length;
    final evidenceCount = entries.fold<int>(
      0,
      (total, entry) => total + entry.evidenceDocumentIds.length,
    );
    final items = <(IconData, Color, String, String, String)>[
      (
        Icons.description_outlined,
        const Color(0xFF1766D5),
        _t(language, 'contract_baseline'),
        contractValue == null ? '—' : _money(contractValue),
        _t(language, 'net_active_baseline'),
      ),
      (
        Icons.task_alt_rounded,
        const Color(0xFF0D9D61),
        _t(language, 'cumulative_eligible'),
        eligible == null ? '—' : _money(eligible),
        _t(language, 'confirmed'),
      ),
      (
        Icons.bar_chart_rounded,
        const Color(0xFF1766D5),
        _t(language, 'available'),
        available == null ? '—' : _money(available),
        _t(language, 'net_subject_to_review'),
      ),
      (
        Icons.rate_review_outlined,
        const Color(0xFF7C4DDB),
        _t(language, 'progress_under_review'),
        '$pending',
        _t(language, 'billing_stages'),
      ),
      (
        Icons.cloud_upload_outlined,
        const Color(0xFF1686D9),
        _t(language, 'evidence_files'),
        '$evidenceCount',
        _t(language, 'files'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 5
            : constraints.maxWidth >= 700
            ? 3
            : 1;
        const gap = AppSpacing.sm;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _AccountsMetricCard(
                  icon: item.$1,
                  color: item.$2,
                  title: item.$3,
                  value: item.$4,
                  detail: item.$5,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AccountsMetricCard extends StatelessWidget {
  const _AccountsMetricCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AccountsMetricStrip extends StatelessWidget {
  const _AccountsMetricStrip({required this.items});

  final List<(IconData, Color, String, String, String)> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1120
          ? items.length.clamp(1, 5)
          : constraints.maxWidth >= 700
          ? 3
          : 1;
      const gap = AppSpacing.sm;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: _AccountsMetricCard(
                icon: item.$1,
                color: item.$2,
                title: item.$3,
                value: item.$4,
                detail: item.$5,
              ),
            ),
        ],
      );
    },
  );
}

class _RegisterList extends StatelessWidget {
  const _RegisterList({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        _SectionHeader(title: title),
        ...children,
      ],
    ),
  );
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.values,
    this.onTap,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> values;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: constraints.maxWidth < 680
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _IconTile(icon),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _TwoLine(title: title, subtitle: subtitle),
                        ),
                      ],
                    ),
                    if (values.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [for (final value in values) _Badge(value)],
                      ),
                    ],
                    if (onTap != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: Text(actionLabel ?? ''),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    _IconTile(icon),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _TwoLine(title: title, subtitle: subtitle),
                    ),
                    for (final value in values)
                      SizedBox(
                        width: 145,
                        child: Text(
                          value,
                          textAlign: TextAlign.end,
                          style: AppTypography.titleSmall,
                        ),
                      ),
                    if (onTap != null)
                      IconButton(
                        tooltip: actionLabel,
                        onPressed: onTap,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _AccountsStatePanel extends StatelessWidget {
  const _AccountsStatePanel({
    required this.status,
    required this.language,
    required this.onRetry,
    this.error,
  });
  final YorksAccountsViewStatus status;
  final AppLanguage language;
  final VoidCallback onRetry;
  final YorksV1DomainException? error;

  @override
  Widget build(BuildContext context) {
    if (status == YorksAccountsViewStatus.loading ||
        status == YorksAccountsViewStatus.idle) {
      return const _KpiSkeleton(count: 6);
    }
    final key = switch (status) {
      YorksAccountsViewStatus.offline => 'offline',
      YorksAccountsViewStatus.forbidden => 'forbidden',
      _ => 'load_failed',
    };
    return _EmptyPanel(
      icon: status == YorksAccountsViewStatus.forbidden
          ? Icons.lock_outline_rounded
          : Icons.cloud_off_outlined,
      title: _t(language, key),
      subtitle: error?.supportReference == null
          ? null
          : '${_t(language, 'support_reference')}: ${error!.supportReference}',
      action: status == YorksAccountsViewStatus.forbidden ? null : onRetry,
      actionLabel: _t(language, 'retry'),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconTile(icon),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      for (var index = 0; index < count; index++)
        Container(
          width: 220,
          height: 118,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: const Align(
            alignment: Alignment.bottomLeft,
            child: LinearProgressIndicator(minHeight: 4),
          ),
        ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.accent,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          if (accent != null)
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusLg),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.onTap,
    this.danger = false,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$label $value',
    child: InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: danger
              ? AppColors.errorContainer
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: danger
                ? AppColors.error.withValues(alpha: .3)
                : AppColors.line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: AppTypography.headlineSmall.copyWith(
                  color: danger ? AppColors.error : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      children: [
        Expanded(child: Text(title, style: AppTypography.titleMedium)),
        if (subtitle != null) _Badge(subtitle!),
      ],
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.values,
    required this.onChanged,
  });
  final String? value;
  final String label;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 176,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(_statusLabel(item))),
      ],
      onChanged: onChanged,
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.color = AppColors.blueContainer});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      label,
      style: AppTypography.labelLarge.copyWith(color: AppColors.inkSecondary),
    ),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.color = AppColors.blueContainer});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.minTapTarget,
    height: AppSpacing.minTapTarget,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(icon, color: AppColors.blue),
  );
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSmall,
      ),
      if (subtitle.isNotEmpty)
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall,
        ),
    ],
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.label});
  final double value;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppColors.surfaceContainerHighest,
            color: AppColors.success,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Text(label, style: AppTypography.labelLarge),
    ],
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    this.danger = false,
  });
  final String label;
  final String value;
  final bool danger;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.labelSmall),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: AppTypography.titleSmall.copyWith(
            color: danger ? AppColors.error : AppColors.ink,
          ),
        ),
      ),
    ],
  );
}

String _t(AppLanguage language, String key) =>
    YorksV1AccountsStrings.text(language, key);

String _wireLabel(AppLanguage language, String wireValue) {
  final key = 'status_$wireValue';
  final localized = _t(language, key);
  return localized == key ? _statusLabel(wireValue) : localized;
}

String _money(YorksAccountsDecimal value) {
  final raw = value.canonicalText;
  final negative = raw.startsWith('-');
  final unsigned = negative ? raw.substring(1) : raw;
  final parts = unsigned.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
  return 'AED ${negative ? '-' : ''}$grouped.$fraction';
}

double _percentValue(YorksAccountsDecimal value) =>
    _percentTextValue(value.canonicalText);

double _percentTextValue(Object? value) =>
    ((double.tryParse('$value') ?? 0) / 100).clamp(0.0, 1.0);

String _percentLabel(Object? value) {
  final decimal = value is YorksAccountsDecimal
      ? value
      : YorksAccountsDecimal.tryParse('$value');
  return '${(decimal ?? YorksAccountsDecimal.zero).displayText()}%';
}

String _statusLabel(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return '—';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

IconData _statusIcon(String value) => switch (value) {
  'paid' ||
  'certified' ||
  'approved' ||
  'matched' ||
  'active' => Icons.check_circle_outline_rounded,
  'overdue' ||
  'blocked' ||
  'cancelled' ||
  'returned' ||
  'rejected' => Icons.error_outline_rounded,
  'due_soon' || 'due_today' || 'review' || 'pending' => Icons.schedule_rounded,
  _ => Icons.info_outline_rounded,
};

Color _statusColor(String value) => switch (value) {
  'paid' ||
  'certified' ||
  'approved' ||
  'matched' ||
  'active' ||
  'cleared' => AppColors.success,
  'overdue' ||
  'blocked' ||
  'cancelled' ||
  'returned' ||
  'bounced' ||
  'rejected' => AppColors.error,
  'due_soon' ||
  'due_today' ||
  'review' ||
  'pending' ||
  'deposited' => AppColors.warning,
  _ => AppColors.primary,
};

String _tabLabel(AppLanguage language, YorksProjectAccountsTab tab) =>
    _t(language, switch (tab) {
      YorksProjectAccountsTab.overview => 'overview',
      YorksProjectAccountsTab.billing => 'billing',
      YorksProjectAccountsTab.invoices => 'invoices',
      YorksProjectAccountsTab.receiptsPdc => 'receipts_pdc',
      YorksProjectAccountsTab.supplierBills => 'supplier_bills',
      YorksProjectAccountsTab.documents => 'documents',
      YorksProjectAccountsTab.activity => 'activity',
    });

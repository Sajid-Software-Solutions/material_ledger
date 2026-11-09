import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_workforce_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_notification_provider.dart';
import '../../application/workforce_daily_roster_controller.dart';
import '../../application/workforce_providers.dart';
import '../../domain/workforce_attendance_models.dart';
import '../../domain/workforce_daily_roster_models.dart';
import '../../domain/workforce_timesheet_models.dart';

class YorksWorkforceDailyAttendanceScreen extends ConsumerStatefulWidget {
  const YorksWorkforceDailyAttendanceScreen({
    super.key,
    this.initialTeamId,
    this.initialWorkDate,
  });

  final String? initialTeamId;
  final String? initialWorkDate;

  @override
  ConsumerState<YorksWorkforceDailyAttendanceScreen> createState() =>
      _YorksWorkforceDailyAttendanceScreenState();
}

class _YorksWorkforceDailyAttendanceScreenState
    extends ConsumerState<YorksWorkforceDailyAttendanceScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  bool _loadScheduled = false;
  bool _targetAttempted = false;
  bool _openingTarget = false;
  bool _targetUnavailable = false;
  int _targetGeneration = 0;
  String? _openedNotificationLocation;
  RouteInformationProvider? _notificationRouteInformation;
  String? _activeTabletWorkerId;

  bool get _hasNotificationTarget =>
      widget.initialTeamId != null || widget.initialWorkDate != null;

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
    _notificationPageUri();
    if (_openedNotificationLocation != null) _scheduleNotificationTarget();
  }

  Uri? _notificationPageUri() =>
      GoRouter.maybeOf(context) == null ? null : GoRouterState.of(context).uri;

  void _resetNotificationTarget() {
    _targetGeneration++;
    _targetAttempted = false;
    _openingTarget = false;
    _targetUnavailable = false;
  }

  void _scheduleNotificationTarget() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final uri = _notificationPageUri();
    if (uri == null || uri.path != '/yorks/workforce/attendance') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _notificationPageUri() != uri ||
          uri.queryParameters['team_id'] != widget.initialTeamId ||
          uri.queryParameters['date'] != widget.initialWorkDate ||
          _openedNotificationLocation == uri.toString()) {
        return;
      }
      setState(_resetNotificationTarget);
    });
  }

  @override
  void didUpdateWidget(
    covariant YorksWorkforceDailyAttendanceScreen oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTeamId != widget.initialTeamId ||
        oldWidget.initialWorkDate != widget.initialWorkDate) {
      _resetNotificationTarget();
    }
  }

  @override
  void dispose() {
    _notificationRouteInformation?.removeListener(_scheduleNotificationTarget);
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _t(AppLanguage language, String key) =>
      YorksV1WorkforceStrings.text(language, key);

  void _scheduleInitialLoad(YorksWorkforceDailyRosterState state) {
    if (_hasNotificationTarget && !_targetAttempted) {
      _targetAttempted = true;
      _openingTarget = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openNotificationRoster(),
      );
      return;
    }
    if (_openingTarget ||
        (_hasNotificationTarget &&
            state.status == YorksWorkforceDailyRosterStatus.idle)) {
      return;
    }
    if (state.status != YorksWorkforceDailyRosterStatus.idle) {
      _loadScheduled = false;
      return;
    }
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(yorksWorkforceDailyRosterControllerProvider.notifier).load();
    });
  }

  Future<void> _openNotificationRoster() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final teamId = widget.initialTeamId;
    final workDate = widget.initialWorkDate;
    final uri = _notificationPageUri();
    final generation = ++_targetGeneration;
    final owner = ref.read(yorksV1AuthUserIdProvider);
    _openedNotificationLocation = uri?.toString();
    bool stillCurrent() =>
        mounted &&
        generation == _targetGeneration &&
        widget.initialTeamId == teamId &&
        widget.initialWorkDate == workDate &&
        ref.read(yorksV1AuthUserIdProvider) == owner &&
        _notificationPageUri() == uri &&
        ModalRoute.of(context)?.isCurrent != false;
    final filters = YorksWorkforceRosterFilters(teamId: teamId);
    final parsedDate = workDate == null ? null : DateTime.tryParse(workDate);
    final validDate =
        workDate != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(workDate) &&
        parsedDate != null &&
        parsedDate.year > 0 &&
        '${parsedDate.year.toString().padLeft(4, '0')}-'
                '${parsedDate.month.toString().padLeft(2, '0')}-'
                '${parsedDate.day.toString().padLeft(2, '0')}' ==
            workDate;
    if (teamId == null || !filters.isValid || !validDate) {
      setState(() {
        _openingTarget = false;
        _targetUnavailable = true;
      });
      return;
    }
    setState(() {
      _openingTarget = true;
      _targetUnavailable = false;
    });
    try {
      final loaded = await ref
          .read(yorksWorkforceDailyRosterControllerProvider.notifier)
          .load(workDate: workDate, filters: filters);
      if (!stillCurrent()) return;
      final state = ref.read(yorksWorkforceDailyRosterControllerProvider);
      final projection = state.projection;
      final exactRoster =
          loaded &&
          projection != null &&
          projection.capabilities.canView &&
          projection.actorAuthUserId == owner &&
          state.workDate == workDate &&
          state.filters.teamId == teamId &&
          projection.workDate == workDate &&
          projection.filters.teamId == teamId &&
          projection.selectors.teams.any((team) => team.id == teamId);
      if (loaded && !exactRoster) {
        setState(() => _targetUnavailable = true);
        return;
      }
      final notificationId = uri?.queryParameters['notificationId'];
      if (exactRoster &&
          owner != null &&
          notificationId != null &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            caseSensitive: false,
          ).hasMatch(notificationId)) {
        await WidgetsBinding.instance.endOfFrame;
        if (!stillCurrent()) return;
        try {
          await ref
              .read(yorksV1NotificationsProvider.notifier)
              .markSeen(notificationId);
        } catch (_) {
          // A failed acknowledgement retains the authoritative unread state.
        }
      }
    } finally {
      if (stillCurrent()) setState(() => _openingTarget = false);
    }
  }

  Future<void> _retryNotificationRoster() => _openNotificationRoster();

  void _searchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final controller = ref.read(
        yorksWorkforceDailyRosterControllerProvider.notifier,
      );
      final filters = ref
          .read(yorksWorkforceDailyRosterControllerProvider)
          .filters
          .copyWith(query: value, offset: 0);
      controller.changeFilters(filters);
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final controllerState = ref.watch(
      yorksWorkforceDailyRosterControllerProvider,
    );
    final projection = controllerState.projection;
    final wrongTarget =
        _hasNotificationTarget &&
        projection != null &&
        (projection.workDate != widget.initialWorkDate ||
            projection.filters.teamId != widget.initialTeamId ||
            projection.actorAuthUserId != ref.read(yorksV1AuthUserIdProvider));
    final state = _targetUnavailable || wrongTarget
        ? controllerState.copyWith(
            status: controllerState.isBusy
                ? controllerState.status
                : YorksWorkforceDailyRosterStatus.unavailable,
            clearProjection: true,
            rows: const [],
            selectedWorkerIds: const {},
          )
        : controllerState;
    final controller = ref.read(
      yorksWorkforceDailyRosterControllerProvider.notifier,
    );
    _scheduleInitialLoad(state);
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final mobileBoundary = width < AppSpacing.compactBreakpoint;
    final tabletBoundary =
        !mobileBoundary && width < _workforceDesktopBreakpoint;
    final desktopBoundary = !mobileBoundary && !tabletBoundary;
    final tabletLandscape =
        tabletBoundary && media.orientation == Orientation.landscape;
    final activeWorker =
        state.rows
            .where((row) => row.workerId == _activeTabletWorkerId)
            .firstOrNull ??
        state.rows.where((row) => row.allocations.length > 1).firstOrNull ??
        state.rows.firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (state.isReviewing) {
              controller.saveDay();
            } else {
              controller.reviewDay();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (state.isReviewing) {
              controller.saveDay();
            } else {
              controller.reviewDay();
            }
          },
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              controller.reviewDay,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              controller.reviewDay,
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SafeArea(
            child: Column(
              children: [
                if (state.status == YorksWorkforceDailyRosterStatus.loading ||
                    state.status == YorksWorkforceDailyRosterStatus.saving)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh:
                        _hasNotificationTarget &&
                            (state.projection == null || _targetUnavailable)
                        ? _retryNotificationRoster
                        : () => controller.load(preserveDrafts: true),
                    child: CustomScrollView(
                      key: const PageStorageKey('workforce-daily-roster'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            mobileBoundary
                                ? AppSpacing.mobileScreenHorizontal
                                : AppSpacing.xxl,
                            mobileBoundary
                                ? AppSpacing.mobileScreenVertical
                                : desktopBoundary
                                ? AppSpacing.lg
                                : AppSpacing.xxl,
                            mobileBoundary
                                ? AppSpacing.mobileScreenHorizontal
                                : AppSpacing.xxl,
                            AppSpacing.colossal,
                          ),
                          sliver: SliverList.list(
                            children: [
                              if (desktopBoundary)
                                _DesktopRosterHeader(
                                  language: language,
                                  state: state,
                                )
                              else
                                _RosterHeader(
                                  language: language,
                                  state: state,
                                  compact: true,
                                  onDate: () => _pickDate(state, controller),
                                  onReview: null,
                                ),
                              const SizedBox(height: AppSpacing.lg),
                              _RosterStateBanner(
                                language: language,
                                state: state,
                                onRetry: _hasNotificationTarget
                                    ? () =>
                                          unawaited(_retryNotificationRoster())
                                    : () => controller.load(),
                              ),
                              if (state.projection != null) ...[
                                if (tabletBoundary) ...[
                                  _SummaryStrip(
                                    language: language,
                                    rows: state.rows,
                                    compact: false,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                ],
                                if (mobileBoundary)
                                  state.isReviewing
                                      ? _RosterReview(
                                          language: language,
                                          state: state,
                                          showActions: false,
                                          onBack: controller.backToEdit,
                                          onSave: state.isBusy
                                              ? null
                                              : controller.saveDay,
                                        )
                                      : _MobileTodayRoster(
                                          language: language,
                                          state: state,
                                          controller: controller,
                                          searchController: _searchController,
                                          onSearch: _searchChanged,
                                          onOpenWorker: _showMobileWorkerEditor,
                                          onBulk: _showMobileBulkActions,
                                        )
                                else if (state.isReviewing)
                                  _RosterReview(
                                    language: language,
                                    state: state,
                                    showActions: desktopBoundary,
                                    onBack: controller.backToEdit,
                                    onSave: state.isBusy
                                        ? null
                                        : controller.saveDay,
                                  )
                                else if (tabletBoundary) ...[
                                  _RosterFilters(
                                    language: language,
                                    state: state,
                                    searchController: _searchController,
                                    onSearch: _searchChanged,
                                    onChanged: controller.changeFilters,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _BulkActions(
                                    language: language,
                                    state: state,
                                    controller: controller,
                                    prompt: _prompt,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _TabletRoster(
                                    language: language,
                                    state: state,
                                    controller: controller,
                                    landscape: tabletLandscape,
                                    activeWorkerId: _activeTabletWorkerId,
                                    onWorkerSelected: (workerId) {
                                      if (tabletLandscape) {
                                        setState(() {
                                          _activeTabletWorkerId = workerId;
                                        });
                                      } else {
                                        _showTabletWorkerEditor(workerId);
                                      }
                                    },
                                  ),
                                  if (state.canLoadMore) ...[
                                    const SizedBox(height: AppSpacing.md),
                                    Align(
                                      alignment: AlignmentDirectional.center,
                                      child: OutlinedButton.icon(
                                        onPressed: state.isBusy
                                            ? null
                                            : controller.loadMore,
                                        icon: const Icon(Icons.expand_more),
                                        label: Text(_t(language, 'load_more')),
                                      ),
                                    ),
                                  ],
                                ] else ...[
                                  _DesktopCrewTimesheetWorkspace(
                                    language: language,
                                    state: state,
                                    controller: controller,
                                    searchController: _searchController,
                                    onSearch: _searchChanged,
                                    onChanged: controller.changeFilters,
                                    prompt: _prompt,
                                    activeWorker: activeWorker,
                                    onDate: () => _pickDate(state, controller),
                                    onRefresh: () =>
                                        controller.load(preserveDrafts: true),
                                    onWorkerSelected: (workerId) {
                                      setState(() {
                                        _activeTabletWorkerId = workerId;
                                      });
                                    },
                                  ),
                                ],
                              ] else if (state.status ==
                                  YorksWorkforceDailyRosterStatus.loading)
                                const _RosterSkeleton(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (tabletBoundary && state.projection != null)
                  _TabletCompletionFooter(
                    language: language,
                    state: state,
                    onReview: controller.reviewDay,
                    onBack: controller.backToEdit,
                    onSave: controller.saveDay,
                  ),
                if (desktopBoundary && state.projection != null)
                  _DesktopCompletionFooter(
                    language: language,
                    state: state,
                    onReview: controller.reviewDay,
                    onBack: controller.backToEdit,
                    onSave: controller.saveDay,
                  ),
                if (mobileBoundary && state.projection != null)
                  _MobileCompletionFooter(
                    language: language,
                    state: state,
                    onReview: controller.reviewDay,
                    onBack: controller.backToEdit,
                    onSave: controller.saveDay,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTabletWorkerEditor(String workerId) async {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      sheetAnimationStyle: disableAnimations
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(yorksWorkforceDailyRosterControllerProvider);
          final row = state.rows
              .where((item) => item.workerId == workerId)
              .firstOrNull;
          if (row == null || state.projection == null) {
            return Center(
              child: Text(
                _t(ref.watch(languageProvider), 'empty'),
                textAlign: TextAlign.center,
              ),
            );
          }
          return FractionallySizedBox(
            heightFactor: .9,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: _TabletWorkerEditor(
                key: ValueKey('tablet-sheet-${row.workerId}'),
                language: ref.watch(languageProvider),
                row: row,
                allocationTargets: state.projection!.allocationTargets,
                controller: ref.read(
                  yorksWorkforceDailyRosterControllerProvider.notifier,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showMobileWorkerEditor(String workerId) async {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      sheetAnimationStyle: disableAnimations
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(yorksWorkforceDailyRosterControllerProvider);
          final row = state.rows
              .where((item) => item.workerId == workerId)
              .firstOrNull;
          if (row == null || state.projection == null) {
            return Center(
              child: Text(
                _t(ref.watch(languageProvider), 'empty'),
                textAlign: TextAlign.center,
              ),
            );
          }
          return AnimatedPadding(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: FractionallySizedBox(
              heightFactor: .94,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.mobileScreenHorizontal,
                  0,
                  AppSpacing.mobileScreenHorizontal,
                  AppSpacing.md,
                ),
                child: _TabletWorkerEditor(
                  key: ValueKey('mobile-sheet-${row.workerId}'),
                  language: ref.watch(languageProvider),
                  row: row,
                  allocationTargets: state.projection!.allocationTargets,
                  controller: ref.read(
                    yorksWorkforceDailyRosterControllerProvider.notifier,
                  ),
                  mobile: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showMobileBulkActions() async {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      sheetAnimationStyle: disableAnimations
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(yorksWorkforceDailyRosterControllerProvider);
          final controller = ref.read(
            yorksWorkforceDailyRosterControllerProvider.notifier,
          );
          if (state.projection == null) return const SizedBox.shrink();
          return AnimatedPadding(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 160),
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: FractionallySizedBox(
              heightFactor: .82,
              child: SingleChildScrollView(
                key: const Key('workforce-mobile-bulk-sheet'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.mobileScreenHorizontal,
                  0,
                  AppSpacing.mobileScreenHorizontal,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t(ref.watch(languageProvider), 'mobile_bulk_actions'),
                      style: AppTypography.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${state.selectedWorkerIds.length} ${_t(ref.watch(languageProvider), 'affected')}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _BulkActions(
                      language: ref.watch(languageProvider),
                      state: state,
                      controller: controller,
                      prompt: _prompt,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickDate(
    YorksWorkforceDailyRosterState state,
    YorksWorkforceDailyRosterController controller,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final parsed = DateTime.tryParse(state.workDate);
    final initial = parsed == null || parsed.isAfter(today) ? today : parsed;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (selected == null || !mounted) return;
    controller.changeDate(_isoDate(selected));
  }

  Future<String?> _prompt(
    String title, {
    String? initial,
    int maxLength = 500,
  }) async {
    final textController = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: maxLength,
          maxLines: 3,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              YorksV1WorkforceStrings.text(ref.read(languageProvider), 'close'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: Text(
              YorksV1WorkforceStrings.text(ref.read(languageProvider), 'apply'),
            ),
          ),
        ],
      ),
    );
    textController.dispose();
    return value;
  }
}

const _workforceDesktopBreakpoint = 1200.0;

class _DesktopRosterHeader extends StatelessWidget {
  const _DesktopRosterHeader({required this.language, required this.state});

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;

  @override
  Widget build(BuildContext context) {
    final demo = state.rows.any(
      (row) => row.source.workerNumber.toUpperCase().startsWith('DEMO-'),
    );
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  YorksV1WorkforceStrings.text(language, 'daily_attendance'),
                  style: AppTypography.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1WorkforceStrings.text(
                    language,
                    'daily_attendance_body',
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (demo)
            Container(
              key: const Key('workforce-demo-data-badge'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.warningContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: .28),
                ),
              ),
              child: Text(
                YorksV1WorkforceStrings.text(language, 'demo_data'),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopCrewTimesheetWorkspace extends StatelessWidget {
  const _DesktopCrewTimesheetWorkspace({
    required this.language,
    required this.state,
    required this.controller,
    required this.searchController,
    required this.onSearch,
    required this.onChanged,
    required this.prompt,
    required this.activeWorker,
    required this.onDate,
    required this.onRefresh,
    required this.onWorkerSelected,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final ValueChanged<YorksWorkforceRosterFilters> onChanged;
  final _Prompt prompt;
  final YorksWorkforceDailyRosterDraftRow? activeWorker;
  final VoidCallback onDate;
  final VoidCallback onRefresh;
  final ValueChanged<String> onWorkerSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _DesktopContextBar(
        language: language,
        state: state,
        onDate: onDate,
        onChanged: onChanged,
        onRefresh: onRefresh,
      ),
      const SizedBox(height: AppSpacing.md),
      _DesktopDailySummary(language: language, rows: state.rows),
      const SizedBox(height: AppSpacing.sm),
      _DesktopWorkspaceTabs(language: language),
      _DesktopRosterTools(
        language: language,
        state: state,
        controller: controller,
        searchController: searchController,
        onSearch: onSearch,
      ),
      if (state.selectedWorkerIds.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _BulkActions(
          language: language,
          state: state,
          controller: controller,
          prompt: prompt,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _RosterGrid(
              language: language,
              state: state,
              controller: controller,
              activeWorkerId: activeWorker?.workerId,
              onWorkerSelected: onWorkerSelected,
            ),
          ),
          if (activeWorker != null) ...[
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              key: const Key('workforce-desktop-worker-editor'),
              width: 404,
              height: 528,
              child: _TabletWorkerEditor(
                key: ValueKey('desktop-${activeWorker!.workerId}'),
                language: language,
                row: activeWorker!,
                allocationTargets: state.projection!.allocationTargets,
                controller: controller,
                mobile: true,
              ),
            ),
          ],
        ],
      ),
      if (state.canLoadMore) ...[
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.center,
          child: OutlinedButton.icon(
            onPressed: state.isBusy ? null : controller.loadMore,
            icon: const Icon(Icons.expand_more),
            label: Text(YorksV1WorkforceStrings.text(language, 'load_more')),
          ),
        ),
      ],
    ],
  );
}

class _DesktopContextBar extends StatelessWidget {
  const _DesktopContextBar({
    required this.language,
    required this.state,
    required this.onDate,
    required this.onChanged,
    required this.onRefresh,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final VoidCallback onDate;
  final ValueChanged<YorksWorkforceRosterFilters> onChanged;
  final VoidCallback onRefresh;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final selectors = state.projection!.selectors;
    final scopes = selectors.projectScopes
        .where(
          (row) =>
              state.filters.projectId == null ||
              row.projectId == state.filters.projectId,
        )
        .toList(growable: false);
    return Container(
      key: const Key('workforce-desktop-context-bar'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 174,
            child: _DesktopDateField(
              label: _t('date'),
              value: state.workDate,
              onPressed: onDate,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FilterSelect(
              width: double.infinity,
              label: _t('team'),
              allLabel: _t('all'),
              value: state.filters.teamId,
              values: [for (final row in selectors.teams) (row.id, row.name)],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  teamId: value,
                  clearTeam: value == null,
                  offset: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: _FilterSelect(
              width: double.infinity,
              label: _t('project'),
              allLabel: _t('all'),
              value: state.filters.projectId,
              values: [
                for (final row in selectors.projects)
                  (row.id, '${row.reference} · ${row.name}'),
              ],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  projectId: value,
                  clearProject: value == null,
                  clearProjectScope: true,
                  offset: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FilterSelect(
              width: double.infinity,
              label: _t('site'),
              allLabel: _t('all'),
              value: state.filters.projectScopeId,
              values: [for (final row in scopes) (row.id, row.name)],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  projectScopeId: value,
                  clearProjectScope: value == null,
                  offset: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FilterSelect(
              width: double.infinity,
              label: _t('location'),
              allLabel: _t('all'),
              value: state.filters.internalLocationId,
              values: [
                for (final row in selectors.internalLocations)
                  (row.id, row.name),
              ],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  internalLocationId: value,
                  clearInternalLocation: value == null,
                  offset: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox.square(
            dimension: 48,
            child: IconButton.outlined(
              onPressed: state.isBusy ? null : onRefresh,
              tooltip: _t('refresh'),
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopDateField extends StatelessWidget {
  const _DesktopDateField({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge,
      ),
    ),
  );
}

class _DesktopDailySummary extends StatelessWidget {
  const _DesktopDailySummary({required this.language, required this.rows});

  final AppLanguage language;
  final List<YorksWorkforceDailyRosterDraftRow> rows;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final regular = rows.fold<int>(0, (sum, row) => sum + row.regularMinutes);
    final overtime = rows.fold<int>(0, (sum, row) => sum + row.overtimeMinutes);
    final attention = rows
        .where(
          (row) =>
              row.status == YorksWorkforceAttendanceStatus.notEntered ||
              !row.isValid,
        )
        .length;
    final metrics = <(String, String, IconData, Color)>[
      (
        'total_workers',
        '${rows.length}',
        Icons.groups_outlined,
        AppColors.blue,
      ),
      (
        'regular_hours',
        _compactHours(regular),
        Icons.schedule_outlined,
        AppColors.success,
      ),
      (
        'overtime_hours',
        _compactHours(overtime),
        Icons.more_time_outlined,
        AppColors.warning,
      ),
      (
        'need_attention',
        '$attention',
        Icons.warning_amber_rounded,
        AppColors.error,
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < metrics.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _DesktopMetricCard(
              metric: metrics[index],
              label: _t(metrics[index].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopMetricCard extends StatelessWidget {
  const _DesktopMetricCard({required this.metric, required this.label});

  final (String, String, IconData, Color) metric;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: metric.$4.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Icon(metric.$3, color: metric.$4, size: 23),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(metric.$2, style: AppTypography.titleLarge),
              Text(
                label,
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

class _DesktopWorkspaceTabs extends StatelessWidget {
  const _DesktopWorkspaceTabs({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, String, bool)>[
      ('overview_tab', '/yorks/workforce', false),
      ('daily_attendance_tab', '/yorks/workforce/attendance', true),
      ('timesheets', '/yorks/workforce/timesheets', false),
      ('administration_tab', '/yorks/workforce/administration', false),
    ];
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            InkWell(
              onTap: tab.$3 ? null : () => context.go(tab.$2),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab.$3 ? AppColors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  YorksV1WorkforceStrings.text(language, tab.$1),
                  style: AppTypography.labelLarge.copyWith(
                    color: tab.$3 ? AppColors.primary : AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DesktopRosterTools extends StatelessWidget {
  const _DesktopRosterTools({
    required this.language,
    required this.state,
    required this.controller,
    required this.searchController,
    required this.onSearch,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: YorksV1WorkforceStrings.text(
                language,
                'search_workers',
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton.icon(
          onPressed: controller.selectVisible,
          icon: const Icon(Icons.select_all, size: 18),
          label: Text(
            YorksV1WorkforceStrings.text(language, 'select_all_visible'),
          ),
        ),
        const Spacer(),
        if (state.selectedWorkerIds.isNotEmpty)
          _StatusDot(
            label:
                '${state.selectedWorkerIds.length} ${YorksV1WorkforceStrings.text(language, 'affected')}',
            color: AppColors.primary,
          ),
      ],
    ),
  );
}

class _DesktopCompletionFooter extends StatelessWidget {
  const _DesktopCompletionFooter({
    required this.language,
    required this.state,
    required this.onReview,
    required this.onBack,
    required this.onSave,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final bool Function() onReview;
  final VoidCallback onBack;
  final Future<YorksWorkforceDailyRosterSaveResult?> Function() onSave;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final entered = state.rows
        .where((row) => row.status != YorksWorkforceAttendanceStatus.notEntered)
        .length;
    final canReview =
        state.dirtyRows.isNotEmpty &&
        state.invalidWorkerIds.isEmpty &&
        state.isOnline &&
        !state.isBusy &&
        state.projection?.isFuture != true;
    final issues = state.invalidWorkerIds.length;
    return Material(
      key: const Key('workforce-desktop-completion-footer'),
      elevation: 12,
      color: AppColors.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 230,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_t('day_status'), style: AppTypography.labelSmall),
                        const SizedBox(width: AppSpacing.sm),
                        _StatusDot(
                          label: state.isReviewing
                              ? _t('reviewing_status')
                              : _t('draft_status'),
                          color: state.isReviewing
                              ? AppColors.blue
                              : AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$entered/${state.rows.length} ${_t('tablet_completion')}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _DesktopLifecycle(
                  language: language,
                  reviewing: state.isReviewing,
                ),
              ),
              if (state.isReviewing) ...[
                OutlinedButton(
                  onPressed: state.isBusy ? null : onBack,
                  child: Text(_t('back_to_edit')),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: canReview ? () => onSave() : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_t('save_day')),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: issues == 0 ? null : onReview,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text('${_t('review_issues')} ($issues)'),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: canReview ? () => onReview() : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_t('review_day')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopLifecycle extends StatelessWidget {
  const _DesktopLifecycle({required this.language, required this.reviewing});

  final AppLanguage language;
  final bool reviewing;

  @override
  Widget build(BuildContext context) {
    final labels = ['draft_status', 'reviewing_status', 'saved'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          YorksV1WorkforceStrings.text(language, 'lifecycle'),
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(width: AppSpacing.md),
        for (var index = 0; index < labels.length; index++) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == (reviewing ? 1 : 0)
                  ? AppColors.primary
                  : AppColors.surfaceContainerLowest,
              border: Border.all(
                color: index <= (reviewing ? 1 : 0)
                    ? AppColors.primary
                    : AppColors.lineStrong,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            YorksV1WorkforceStrings.text(language, labels[index]),
            style: AppTypography.labelSmall.copyWith(
              color: index == (reviewing ? 1 : 0)
                  ? AppColors.primary
                  : AppColors.muted,
            ),
          ),
          if (index != labels.length - 1) ...[
            const SizedBox(width: AppSpacing.sm),
            const SizedBox(
              width: 18,
              child: Divider(color: AppColors.lineStrong),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

String _compactHours(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes.remainder(60);
  return remainder == 0
      ? '$hours'
      : '$hours:${remainder.toString().padLeft(2, '0')}';
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader({
    required this.language,
    required this.state,
    required this.compact,
    required this.onDate,
    required this.onReview,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final bool compact;
  final VoidCallback onDate;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final title = YorksV1WorkforceStrings.text(
      language,
      MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint
          ? 'mobile_attendance_title'
          : 'daily_attendance',
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: onDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(state.workDate),
        ),
        if (!compact)
          ElevatedButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(YorksV1WorkforceStrings.text(language, 'review_day')),
          ),
      ],
    );
    return Semantics(
      header: true,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1WorkforceStrings.text(
                    language,
                    MediaQuery.sizeOf(context).width <
                            AppSpacing.compactBreakpoint
                        ? 'mobile_attendance_hint'
                        : 'daily_attendance_body',
                  ),
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                actions,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        YorksV1WorkforceStrings.text(language, 'workforce'),
                        style: AppTypography.eyebrow,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(title, style: AppTypography.headlineMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        YorksV1WorkforceStrings.text(
                          language,
                          compact
                              ? 'mobile_attendance_hint'
                              : 'daily_attendance_body',
                        ),
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                actions,
              ],
            ),
    );
  }
}

class _RosterStateBanner extends StatelessWidget {
  const _RosterStateBanner({
    required this.language,
    required this.state,
    required this.onRetry,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final config = switch (state.status) {
      YorksWorkforceDailyRosterStatus.offline => (
        Icons.cloud_off_outlined,
        AppColors.warningContainer,
        AppColors.warning,
        'offline',
        'offline_body',
      ),
      YorksWorkforceDailyRosterStatus.conflict => (
        Icons.sync_problem_outlined,
        AppColors.errorContainer,
        AppColors.error,
        'conflict',
        'conflict_body',
      ),
      YorksWorkforceDailyRosterStatus.uncertain => (
        Icons.help_outline,
        AppColors.warningContainer,
        AppColors.warning,
        'uncertain',
        'uncertain_body',
      ),
      YorksWorkforceDailyRosterStatus.forbidden ||
      YorksWorkforceDailyRosterStatus.sessionExpired ||
      YorksWorkforceDailyRosterStatus.unavailable => (
        Icons.lock_outline,
        AppColors.errorContainer,
        AppColors.error,
        'permission_lost',
        'permission_lost_body',
      ),
      YorksWorkforceDailyRosterStatus.saved => (
        Icons.cloud_done_outlined,
        AppColors.successContainer,
        AppColors.success,
        'saved',
        'saved',
      ),
      YorksWorkforceDailyRosterStatus.failure => (
        Icons.error_outline,
        AppColors.errorContainer,
        AppColors.error,
        'load_failed',
        'load_failed_body',
      ),
      _
          when state.projection?.isFuture == true &&
              state.projection!.rows.isNotEmpty =>
        (
          Icons.event_busy_outlined,
          AppColors.warningContainer,
          AppColors.warning,
          'future_day',
          'future_day',
        ),
      _ => null,
    };
    if (config == null) return const SizedBox.shrink();
    final (icon, background, foreground, titleKey, bodyKey) = config;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: foreground.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  YorksV1WorkforceStrings.text(language, titleKey),
                  style: AppTypography.labelLarge.copyWith(color: foreground),
                ),
                if (bodyKey != titleKey)
                  Text(
                    YorksV1WorkforceStrings.text(language, bodyKey),
                    style: AppTypography.bodySmall.copyWith(color: foreground),
                  ),
              ],
            ),
          ),
          if (state.status == YorksWorkforceDailyRosterStatus.conflict ||
              state.status == YorksWorkforceDailyRosterStatus.failure)
            TextButton(
              onPressed: onRetry,
              child: Text(YorksV1WorkforceStrings.text(language, 'retry')),
            ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.language,
    required this.rows,
    required this.compact,
  });

  final AppLanguage language;
  final List<YorksWorkforceDailyRosterDraftRow> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    int count(YorksWorkforceAttendanceStatus status) =>
        rows.where((row) => row.status == status).length;
    final leave = rows
        .where(
          (row) => switch (row.status) {
            YorksWorkforceAttendanceStatus.annualLeave ||
            YorksWorkforceAttendanceStatus.sickLeave ||
            YorksWorkforceAttendanceStatus.officialLeave ||
            YorksWorkforceAttendanceStatus.unpaidLeave => true,
            _ => false,
          },
        )
        .length;
    final overtime = rows.fold<int>(0, (sum, row) => sum + row.overtimeMinutes);
    final metrics = <(String, String, IconData, Color)>[
      (
        'total_workers',
        '${rows.length}',
        Icons.groups_outlined,
        AppColors.blue,
      ),
      (
        'present_today',
        '${count(YorksWorkforceAttendanceStatus.present)}',
        Icons.how_to_reg_outlined,
        AppColors.success,
      ),
      (
        'absent_today',
        '${count(YorksWorkforceAttendanceStatus.absent)}',
        Icons.person_off_outlined,
        AppColors.error,
      ),
      ('on_leave', '$leave', Icons.beach_access_outlined, AppColors.purple),
      (
        'not_entered_count',
        '${count(YorksWorkforceAttendanceStatus.notEntered)}',
        Icons.pending_actions_outlined,
        AppColors.warning,
      ),
      (
        'overtime_today',
        _minutes(overtime),
        Icons.more_time_outlined,
        AppColors.blue,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = compact
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : math.max(132.0, (constraints.maxWidth - 5 * AppSpacing.sm) / 6);
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: cardWidth,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: metric.$4.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: Icon(metric.$3, color: metric.$4, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(metric.$2, style: AppTypography.titleMedium),
                            Text(
                              YorksV1WorkforceStrings.text(language, metric.$1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelSmall,
                            ),
                          ],
                        ),
                      ),
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

class _RosterFilters extends StatelessWidget {
  const _RosterFilters({
    required this.language,
    required this.state,
    required this.searchController,
    required this.onSearch,
    required this.onChanged,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final ValueChanged<YorksWorkforceRosterFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectors = state.projection!.selectors;
    final scopes = selectors.projectScopes
        .where(
          (row) =>
              state.filters.projectId == null ||
              row.projectId == state.filters.projectId,
        )
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchController,
                onChanged: onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: YorksV1WorkforceStrings.text(
                    language,
                    'search_workers',
                  ),
                ),
              ),
            ),
            _FilterSelect(
              width: 190,
              label: YorksV1WorkforceStrings.text(language, 'team'),
              allLabel: YorksV1WorkforceStrings.text(language, 'all'),
              value: state.filters.teamId,
              values: [for (final row in selectors.teams) (row.id, row.name)],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  teamId: value,
                  clearTeam: value == null,
                  offset: 0,
                ),
              ),
            ),
            _FilterSelect(
              width: 240,
              label: YorksV1WorkforceStrings.text(language, 'project'),
              allLabel: YorksV1WorkforceStrings.text(language, 'all'),
              value: state.filters.projectId,
              values: [
                for (final row in selectors.projects)
                  (row.id, '${row.reference} · ${row.name}'),
              ],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  projectId: value,
                  clearProject: value == null,
                  clearProjectScope: true,
                  offset: 0,
                ),
              ),
            ),
            _FilterSelect(
              width: 190,
              label: YorksV1WorkforceStrings.text(language, 'site'),
              allLabel: YorksV1WorkforceStrings.text(language, 'all'),
              value: state.filters.projectScopeId,
              values: [for (final row in scopes) (row.id, row.name)],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  projectScopeId: value,
                  clearProjectScope: value == null,
                  offset: 0,
                ),
              ),
            ),
            _FilterSelect(
              width: 190,
              label: YorksV1WorkforceStrings.text(language, 'location'),
              allLabel: YorksV1WorkforceStrings.text(language, 'all'),
              value: state.filters.internalLocationId,
              values: [
                for (final row in selectors.internalLocations)
                  (row.id, row.name),
              ],
              onChanged: (value) => onChanged(
                state.filters.copyWith(
                  internalLocationId: value,
                  clearInternalLocation: value == null,
                  offset: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSelect extends StatelessWidget {
  const _FilterSelect({
    required this.width,
    required this.label,
    required this.allLabel,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final double width;
  final String label;
  final String allLabel;
  final String? value;
  final List<(String, String)> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String?>(
      initialValue: values.any((row) => row.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final row in values)
          DropdownMenuItem<String?>(
            value: row.$1,
            child: Text(row.$2, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

typedef _Prompt =
    Future<String?> Function(String title, {String? initial, int maxLength});

enum _BulkSelectionKind { team, trade, missing }

final class _BulkSelectionOption {
  const _BulkSelectionOption({
    required this.kind,
    required this.label,
    this.id,
  });

  final _BulkSelectionKind kind;
  final String label;
  final String? id;
}

class _BulkActions extends StatelessWidget {
  const _BulkActions({
    required this.language,
    required this.state,
    required this.controller,
    required this.prompt,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final _Prompt prompt;

  @override
  Widget build(BuildContext context) {
    final count = state.selectedWorkerIds.length;
    final enabled = count > 0 && !state.isBusy;
    final targetOptions = _targetOptions(state.projection!.allocationTargets);
    final trades = <String, String>{
      for (final row in state.rows)
        if (row.source.tradeId != null && row.source.tradeName != null)
          row.source.tradeId!: row.source.tradeName!,
    };
    final selectionOptions = <_BulkSelectionOption>[
      _BulkSelectionOption(
        kind: _BulkSelectionKind.missing,
        label: YorksV1WorkforceStrings.text(language, 'select_missing'),
      ),
      for (final team in state.projection!.selectors.teams)
        _BulkSelectionOption(
          kind: _BulkSelectionKind.team,
          id: team.id,
          label:
              '${YorksV1WorkforceStrings.text(language, 'select_team')}: ${team.name}',
        ),
      for (final trade in trades.entries)
        _BulkSelectionOption(
          kind: _BulkSelectionKind.trade,
          id: trade.key,
          label:
              '${YorksV1WorkforceStrings.text(language, 'select_trade')}: ${trade.value}',
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: count > 0
            ? AppColors.blueContainer
            : AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: controller.selectVisible,
            icon: const Icon(Icons.select_all, size: 18),
            label: Text(
              YorksV1WorkforceStrings.text(language, 'select_all_visible'),
            ),
          ),
          PopupMenuButton<_BulkSelectionOption>(
            tooltip: YorksV1WorkforceStrings.text(language, 'select_more'),
            onSelected: (option) {
              switch (option.kind) {
                case _BulkSelectionKind.team:
                  controller.selectTeam(option.id!);
                  break;
                case _BulkSelectionKind.trade:
                  controller.selectTrade(option.id!);
                  break;
                case _BulkSelectionKind.missing:
                  controller.selectMissing();
                  break;
              }
            },
            itemBuilder: (context) => [
              for (final option in selectionOptions)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: IgnorePointer(
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text(
                  YorksV1WorkforceStrings.text(language, 'select_more'),
                ),
              ),
            ),
          ),
          if (count > 0)
            Text(
              '$count ${YorksV1WorkforceStrings.text(language, 'affected')}',
              style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
            ),
          OutlinedButton(
            onPressed: enabled ? controller.applyStandardMinutes : null,
            child: Text(
              YorksV1WorkforceStrings.text(language, 'set_present_standard'),
            ),
          ),
          OutlinedButton(
            onPressed: enabled ? controller.markAbsent : null,
            child: Text(YorksV1WorkforceStrings.text(language, 'set_absent')),
          ),
          OutlinedButton(
            onPressed: enabled
                ? () async {
                    final value = await prompt(
                      YorksV1WorkforceStrings.text(language, 'set_regular'),
                    );
                    final minutes = int.tryParse(value?.trim() ?? '');
                    if (minutes != null) {
                      controller.setRegularMinutesForSelected(minutes);
                    }
                  }
                : null,
            child: Text(YorksV1WorkforceStrings.text(language, 'set_regular')),
          ),
          OutlinedButton(
            onPressed: enabled
                ? () async {
                    final value = await prompt(
                      YorksV1WorkforceStrings.text(language, 'set_overtime'),
                    );
                    final minutes = int.tryParse(value?.trim() ?? '');
                    if (minutes != null) {
                      controller.setOvertimeForSelected(minutes);
                    }
                  }
                : null,
            child: Text(YorksV1WorkforceStrings.text(language, 'set_overtime')),
          ),
          PopupMenuButton<_TargetOption>(
            enabled: enabled,
            tooltip: YorksV1WorkforceStrings.text(language, 'assign_target'),
            onSelected: (option) {
              if (option.kind ==
                  YorksWorkforceAllocationTargetKind.projectWork) {
                controller.assignProjectToSelected(
                  projectId: option.projectId!,
                  projectScopeId: option.scopeId!,
                );
              } else {
                controller.assignInternalLocationToSelected(option.locationId!);
              }
            },
            itemBuilder: (context) => [
              for (final option in targetOptions)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
            child: IgnorePointer(
              child: OutlinedButton.icon(
                onPressed: enabled ? () {} : null,
                icon: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(
                  YorksV1WorkforceStrings.text(language, 'assign_target'),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: enabled
                ? () async {
                    final value = await prompt(
                      YorksV1WorkforceStrings.text(language, 'apply_activity'),
                    );
                    if (value != null) {
                      controller.applyActivityToSelected(value);
                    }
                  }
                : null,
            child: Text(
              YorksV1WorkforceStrings.text(language, 'apply_activity'),
            ),
          ),
          OutlinedButton(
            onPressed: enabled
                ? () async {
                    final value = await prompt(
                      YorksV1WorkforceStrings.text(language, 'add_note'),
                      maxLength: 2000,
                    );
                    if (value != null) {
                      controller.applyNoteToSelected(value);
                    }
                  }
                : null,
            child: Text(YorksV1WorkforceStrings.text(language, 'add_note')),
          ),
          Tooltip(
            message: YorksV1WorkforceStrings.text(
              language,
              'copy_previous_safe_hint',
            ),
            child: OutlinedButton.icon(
              onPressed: enabled ? controller.copyPreviousDay : null,
              icon: const Icon(Icons.content_copy_outlined, size: 17),
              label: Text(
                YorksV1WorkforceStrings.text(language, 'copy_previous_day'),
              ),
            ),
          ),
          if (count > 0)
            IconButton(
              onPressed: controller.clearSelection,
              tooltip: YorksV1WorkforceStrings.text(
                language,
                'clear_selection',
              ),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _TabletRoster extends StatelessWidget {
  const _TabletRoster({
    required this.language,
    required this.state,
    required this.controller,
    required this.landscape,
    required this.activeWorkerId,
    required this.onWorkerSelected,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final bool landscape;
  final String? activeWorkerId;
  final ValueChanged<String> onWorkerSelected;

  @override
  Widget build(BuildContext context) {
    if (state.rows.isEmpty) {
      return Card(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Text(
              YorksV1WorkforceStrings.text(language, 'empty'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final active = state.rows
        .where((row) => row.workerId == activeWorkerId)
        .firstOrNull;
    final selected = active ?? state.rows.first;
    final height = landscape
        ? 540.0
        : math.min(480.0, math.max(170.0, 54 + state.rows.length * 76.0));
    final master = Card(
      key: const Key('workforce-tablet-roster-master'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      YorksV1WorkforceStrings.text(language, 'tablet_roster'),
                      style: AppTypography.titleMedium,
                    ),
                  ),
                  Text(
                    '${state.rows.length}',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                key: const Key('workforce-tablet-roster-list'),
                itemCount: state.rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = state.rows[index];
                  return _TabletWorkerTile(
                    language: language,
                    row: row,
                    active: landscape && row.workerId == selected.workerId,
                    selected: state.selectedWorkerIds.contains(row.workerId),
                    onToggle: controller.toggleSelection,
                    onOpen: onWorkerSelected,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!landscape) return master;
    return SizedBox(
      key: const Key('workforce-tablet-landscape-master-detail'),
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 330, child: master),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _TabletWorkerEditor(
              key: ValueKey('tablet-detail-${selected.workerId}'),
              language: language,
              row: selected,
              allocationTargets: state.projection!.allocationTargets,
              controller: controller,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletWorkerTile extends StatelessWidget {
  const _TabletWorkerTile({
    required this.language,
    required this.row,
    required this.active,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterDraftRow row;
  final bool active;
  final bool selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label:
        '${row.source.workerName}, ${row.source.workerNumber}, ${_statusLabel(language, row.status)}',
    child: Material(
      color: active
          ? AppColors.blueContainer
          : row.isDirty
          ? AppColors.warningContainer.withValues(alpha: .4)
          : AppColors.surfaceContainerLowest,
      child: InkWell(
        key: Key('workforce-tablet-worker-${row.workerId}'),
        onTap: () => onOpen(row.workerId),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: Checkbox(
                    value: selected,
                    onChanged: row.isEditable
                        ? (_) => onToggle(row.workerId)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.source.workerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          row.source.workerNumber,
                          row.source.tradeName ?? row.source.designation,
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      Text(
                        '${_statusLabel(language, row.status)} · ${_minutes(row.regularMinutes)} + ${_minutes(row.overtimeMinutes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: _statusColor(row.status),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!row.isValid)
                  const Icon(Icons.error, color: AppColors.error, size: 18),
                const SizedBox(width: AppSpacing.xs),
                const SizedBox.square(
                  dimension: 44,
                  child: Icon(Icons.chevron_right, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TabletWorkerEditor extends StatefulWidget {
  const _TabletWorkerEditor({
    super.key,
    required this.language,
    required this.row,
    required this.allocationTargets,
    required this.controller,
    this.mobile = false,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterDraftRow row;
  final YorksWorkforceRosterAllocationTargets allocationTargets;
  final YorksWorkforceDailyRosterController controller;
  final bool mobile;

  @override
  State<_TabletWorkerEditor> createState() => _TabletWorkerEditorState();
}

class _TabletWorkerEditorState extends State<_TabletWorkerEditor> {
  late final TextEditingController _regular;
  late final TextEditingController _overtime;
  late final TextEditingController _activity;
  late final TextEditingController _exception;

  YorksWorkforceAllocationInput? get _first =>
      widget.row.allocations.length == 1 ? widget.row.allocations.single : null;
  String get _exceptionValue => widget.row.overtimeMinutes > 0
      ? widget.row.overtimeReason ?? ''
      : _first?.notes ?? '';

  @override
  void initState() {
    super.initState();
    _regular = TextEditingController(text: '${widget.row.regularMinutes}');
    _overtime = TextEditingController(text: '${widget.row.overtimeMinutes}');
    _activity = TextEditingController(text: _first?.activityTask ?? '');
    _exception = TextEditingController(text: _exceptionValue);
  }

  @override
  void didUpdateWidget(covariant _TabletWorkerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_regular, '${widget.row.regularMinutes}');
    _sync(_overtime, '${widget.row.overtimeMinutes}');
    _sync(_activity, _first?.activityTask ?? '');
    _sync(_exception, _exceptionValue);
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value) controller.text = value;
  }

  @override
  void dispose() {
    _regular.dispose();
    _overtime.dispose();
    _activity.dispose();
    _exception.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final targetOptions = _targetOptions(widget.allocationTargets);
    final currentTarget = _targetValue(row);
    final exceptionEditsEvidence = row.overtimeMinutes > 0;
    final enabled = row.isEditable;
    final direction = Directionality.of(context);
    void next() => FocusScope.of(context).nextFocus();
    void previous() => FocusScope.of(context).previousFocus();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): next,
        const SingleActivator(LogicalKeyboardKey.arrowUp): previous,
        const SingleActivator(LogicalKeyboardKey.enter): next,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            direction == TextDirection.rtl ? previous : next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            direction == TextDirection.rtl ? next : previous,
      },
      child: Card(
        key: Key(
          '${widget.mobile ? 'workforce-mobile' : 'workforce-tablet'}-worker-editor-${row.workerId}',
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 560;
            final fieldWidth = twoColumns
                ? (constraints.maxWidth - AppSpacing.xl * 2 - AppSpacing.md) / 2
                : constraints.maxWidth - AppSpacing.xl * 2;
            return SingleChildScrollView(
              padding: EdgeInsets.all(
                widget.mobile ? AppSpacing.md : AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.blueContainer,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: const Icon(
                          Icons.badge_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.source.workerName,
                              style: AppTypography.titleLarge,
                            ),
                            Text(
                              '${row.source.workerNumber} · ${row.source.tradeName ?? row.source.designation ?? '—'}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            Text(
                              _assignment(row),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _StatusDot(
                        label: _sourceLabel(widget.language, row),
                        color: row.isDirty
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (!enabled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Text(
                        YorksV1WorkforceStrings.text(
                          widget.language,
                          row.source.allocationDetailsRestricted
                              ? 'allocation_restricted'
                              : 'read_only_mobile',
                        ),
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      _tabletField(
                        fieldWidth,
                        DropdownButtonFormField<YorksWorkforceAttendanceStatus>(
                          key: ValueKey(
                            '${row.workerId}-tablet-status-${row.status.wireValue}',
                          ),
                          initialValue: row.status,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: YorksV1WorkforceStrings.text(
                              widget.language,
                              'status',
                            ),
                          ),
                          items: [
                            for (final status
                                in YorksWorkforceAttendanceStatus.values)
                              DropdownMenuItem(
                                value: status,
                                child: Text(
                                  _statusLabel(widget.language, status),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: enabled
                              ? (value) {
                                  if (value != null) {
                                    widget.controller.updateRow(
                                      row.workerId,
                                      status: value,
                                    );
                                  }
                                }
                              : null,
                        ),
                      ),
                      _tabletField(
                        fieldWidth,
                        widget.mobile
                            ? _MobileMinuteControl(
                                key: Key(
                                  'workforce-mobile-regular-${row.workerId}',
                                ),
                                language: widget.language,
                                labelKey: 'regular',
                                value: row.regularMinutes,
                                enabled:
                                    enabled &&
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.present,
                                onChanged: (value) =>
                                    widget.controller.updateRow(
                                      row.workerId,
                                      regularMinutes: value,
                                    ),
                              )
                            : TextField(
                                controller: _regular,
                                enabled:
                                    enabled &&
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.present,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: YorksV1WorkforceStrings.text(
                                    widget.language,
                                    'regular',
                                  ),
                                ),
                                onChanged: (value) =>
                                    widget.controller.updateRow(
                                      row.workerId,
                                      regularMinutes: int.tryParse(value) ?? 0,
                                    ),
                              ),
                      ),
                      _tabletField(
                        fieldWidth,
                        widget.mobile
                            ? _MobileMinuteControl(
                                key: Key(
                                  'workforce-mobile-overtime-${row.workerId}',
                                ),
                                language: widget.language,
                                labelKey: 'overtime',
                                value: row.overtimeMinutes,
                                enabled:
                                    enabled &&
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.present,
                                onChanged: (value) =>
                                    widget.controller.updateRow(
                                      row.workerId,
                                      overtimeMinutes: value,
                                    ),
                              )
                            : TextField(
                                controller: _overtime,
                                enabled:
                                    enabled &&
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.present,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: YorksV1WorkforceStrings.text(
                                    widget.language,
                                    'overtime',
                                  ),
                                ),
                                onChanged: (value) =>
                                    widget.controller.updateRow(
                                      row.workerId,
                                      overtimeMinutes: int.tryParse(value) ?? 0,
                                    ),
                              ),
                      ),
                      _tabletField(
                        fieldWidth,
                        row.source.allocationDetailsRestricted
                            ? InputDecorator(
                                decoration: InputDecoration(
                                  labelText: YorksV1WorkforceStrings.text(
                                    widget.language,
                                    'target',
                                  ),
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  color: AppColors.muted,
                                ),
                              )
                            : DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '${row.workerId}-tablet-target-${currentTarget ?? 'none'}',
                                ),
                                initialValue:
                                    targetOptions.any(
                                      (option) => option.value == currentTarget,
                                    )
                                    ? currentTarget
                                    : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: YorksV1WorkforceStrings.text(
                                    widget.language,
                                    'target',
                                  ),
                                ),
                                hint: Text(
                                  row.allocations.length > 1
                                      ? YorksV1WorkforceStrings.text(
                                          widget.language,
                                          'multiple_allocations',
                                        )
                                      : YorksV1WorkforceStrings.text(
                                          widget.language,
                                          'none',
                                        ),
                                ),
                                items: [
                                  for (final option in targetOptions)
                                    DropdownMenuItem(
                                      value: option.value,
                                      child: Text(
                                        option.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged:
                                    row.isAllocationEditable &&
                                        row.status ==
                                            YorksWorkforceAttendanceStatus
                                                .present &&
                                        row.regularMinutes +
                                                row.overtimeMinutes >
                                            0
                                    ? (value) {
                                        final option = targetOptions
                                            .where(
                                              (item) => item.value == value,
                                            )
                                            .firstOrNull;
                                        if (option == null) return;
                                        if (option.kind ==
                                            YorksWorkforceAllocationTargetKind
                                                .projectWork) {
                                          widget.controller.assignProject(
                                            row.workerId,
                                            projectId: option.projectId!,
                                            projectScopeId: option.scopeId!,
                                          );
                                        } else {
                                          widget.controller
                                              .assignInternalLocation(
                                                row.workerId,
                                                option.locationId!,
                                              );
                                        }
                                      }
                                    : null,
                              ),
                      ),
                      _tabletField(
                        fieldWidth,
                        TextField(
                          controller: _activity,
                          enabled:
                              row.isAllocationEditable &&
                              row.allocations.isNotEmpty,
                          maxLength: 500,
                          buildCounter: _RosterDataRowState._noCounter,
                          decoration: InputDecoration(
                            labelText: YorksV1WorkforceStrings.text(
                              widget.language,
                              'activity',
                            ),
                          ),
                          onChanged: (value) => widget.controller
                              .updateActivity(row.workerId, value),
                        ),
                      ),
                      _tabletField(
                        fieldWidth,
                        TextField(
                          controller: _exception,
                          enabled: exceptionEditsEvidence
                              ? row.canEditAttendanceEvidence
                              : row.isAllocationEditable &&
                                    row.allocations.isNotEmpty,
                          maxLength: 2000,
                          buildCounter: _RosterDataRowState._noCounter,
                          decoration: InputDecoration(
                            labelText: YorksV1WorkforceStrings.text(
                              widget.language,
                              'note_exception',
                            ),
                          ),
                          onChanged: (value) {
                            if (exceptionEditsEvidence) {
                              widget.controller.updateRow(
                                row.workerId,
                                overtimeReason: value,
                                clearOvertimeReason: value.trim().isEmpty,
                              );
                            } else {
                              widget.controller.updateAllocationNote(
                                row.workerId,
                                value,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (row.allocations.length > 1) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _AllocationSplitEditor(
                      language: widget.language,
                      row: row,
                      targetOptions: targetOptions,
                      controller: widget.controller,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: row.isEditable
                              ? () {
                                  final suggestion =
                                      row.source.scheduleSuggestion;
                                  widget.controller.updateRow(
                                    row.workerId,
                                    status: suggestion.suggestedStatus,
                                    regularMinutes:
                                        suggestion.suggestedRegularMinutes,
                                    overtimeMinutes:
                                        suggestion.suggestedOvertimeMinutes,
                                    clearOvertimeReason: true,
                                    source: YorksWorkforceRosterDraftSource
                                        .scheduleStandard,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          label: Text(
                            YorksV1WorkforceStrings.text(
                              widget.language,
                              'prefilled_shift',
                            ),
                          ),
                        ),
                      ),
                      if (row.allocations.length == 1 &&
                          targetOptions.length > 1)
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            key: Key(
                              'workforce-split-allocation-${row.workerId}',
                            ),
                            onPressed: row.isAllocationEditable
                                ? () => widget.controller.replaceAllocations(
                                    row.workerId,
                                    _splitAllocationDraft(
                                      row.allocations,
                                      targetOptions,
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.call_split_outlined),
                            label: Text(
                              YorksV1WorkforceStrings.text(
                                widget.language,
                                'split_allocation',
                              ),
                            ),
                          ),
                        ),
                      if (!row.isValid)
                        _StatusDot(
                          label: YorksV1WorkforceStrings.text(
                            widget.language,
                            'validation_minutes',
                          ),
                          color: AppColors.error,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tabletField(double width, Widget child) =>
      SizedBox(width: math.max(240, width), child: child);
}

class _AllocationSplitEditor extends StatelessWidget {
  const _AllocationSplitEditor({
    required this.language,
    required this.row,
    required this.targetOptions,
    required this.controller,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterDraftRow row;
  final List<_TargetOption> targetOptions;
  final YorksWorkforceDailyRosterController controller;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final allocatedRegular = row.allocations.fold<int>(
      0,
      (sum, item) => sum + item.regularMinutes,
    );
    final allocatedOvertime = row.allocations.fold<int>(
      0,
      (sum, item) => sum + item.overtimeMinutes,
    );
    final balanced =
        allocatedRegular == row.regularMinutes &&
        allocatedOvertime == row.overtimeMinutes &&
        row.allocations.every((item) => item.isValid);
    return Container(
      key: Key('workforce-allocation-split-editor-${row.workerId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.call_split_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _t('split_allocation'),
                  style: AppTypography.titleMedium,
                ),
              ),
              Text(
                '${_minutes(allocatedRegular)} + ${_minutes(allocatedOvertime)}',
                style: AppTypography.labelLarge.copyWith(
                  color: balanced ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(_t('split_allocation_body'), style: AppTypography.bodySmall),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < row.allocations.length; index++) ...[
            _AllocationLineEditor(
              language: language,
              index: index,
              allocation: row.allocations[index],
              targetOptions: targetOptions,
              canRemove: row.allocations.length > 1,
              onChanged: (next) {
                final allocations = [...row.allocations];
                allocations[index] = next;
                controller.replaceAllocations(row.workerId, allocations);
              },
              onRemove: () {
                final allocations = [...row.allocations];
                final removed = allocations.removeAt(index);
                if (allocations.isEmpty) return;
                allocations[0] = _copyAllocationInput(
                  allocations[0],
                  regularMinutes:
                      allocations[0].regularMinutes + removed.regularMinutes,
                  overtimeMinutes:
                      allocations[0].overtimeMinutes + removed.overtimeMinutes,
                );
                controller.replaceAllocations(row.workerId, allocations);
              },
            ),
            if (index != row.allocations.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: balanced
                        ? AppColors.successContainer
                        : AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        balanced
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 18,
                        color: balanced ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _t(
                            balanced
                                ? 'allocation_balanced'
                                : 'allocation_unbalanced',
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: balanced
                                ? AppColors.success
                                : AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.outlined(
                tooltip: _t('add_allocation'),
                onPressed: targetOptions.length > 1
                    ? () => controller.replaceAllocations(
                        row.workerId,
                        _splitAllocationDraft(row.allocations, targetOptions),
                      )
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllocationLineEditor extends StatelessWidget {
  const _AllocationLineEditor({
    required this.language,
    required this.index,
    required this.allocation,
    required this.targetOptions,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final AppLanguage language;
  final int index;
  final YorksWorkforceAllocationInput allocation;
  final List<_TargetOption> targetOptions;
  final bool canRemove;
  final ValueChanged<YorksWorkforceAllocationInput> onChanged;
  final VoidCallback onRemove;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final targetValue = _targetValueForAllocation(allocation);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('allocation-$index-$targetValue'),
                  initialValue:
                      targetOptions.any((option) => option.value == targetValue)
                      ? targetValue
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: _t('target')),
                  items: [
                    for (final option in targetOptions)
                      DropdownMenuItem(
                        value: option.value,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    final option = targetOptions
                        .where((item) => item.value == value)
                        .firstOrNull;
                    if (option == null) return;
                    onChanged(_allocationForTarget(option, allocation));
                  },
                ),
              ),
              if (canRemove) ...[
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: _t('remove_allocation'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, color: AppColors.error),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('allocation-$index-regular'),
                  initialValue: '${allocation.regularMinutes}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: _t('regular')),
                  onChanged: (value) => onChanged(
                    _copyAllocationInput(
                      allocation,
                      regularMinutes: int.tryParse(value) ?? 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  key: ValueKey('allocation-$index-overtime'),
                  initialValue: '${allocation.overtimeMinutes}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: _t('overtime')),
                  onChanged: (value) => onChanged(
                    _copyAllocationInput(
                      allocation,
                      overtimeMinutes: int.tryParse(value) ?? 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: ValueKey('allocation-$index-activity'),
            initialValue: allocation.activityTask ?? '',
            maxLength: 500,
            buildCounter: _RosterDataRowState._noCounter,
            decoration: InputDecoration(labelText: _t('activity')),
            onChanged: (value) => onChanged(
              _copyAllocationInput(allocation, activityTask: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMinuteControl extends StatelessWidget {
  const _MobileMinuteControl({
    super.key,
    required this.language,
    required this.labelKey,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AppLanguage language;
  final String labelKey;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = YorksV1WorkforceStrings.text(language, labelKey);
    return Semantics(
      container: true,
      label: '$label, ${_minutes(value)}',
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: IconButton.outlined(
                key: Key('$labelKey-minute-decrease'),
                tooltip: YorksV1WorkforceStrings.text(
                  language,
                  'decrease_minutes',
                ),
                onPressed: enabled && value > 0
                    ? () => onChanged(math.max(0, value - 15))
                    : null,
                icon: const Icon(Icons.remove),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_minutes(value), style: AppTypography.titleMedium),
                  Text(
                    '$value ${YorksV1WorkforceStrings.text(language, 'minutes_short')}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox.square(
              dimension: 44,
              child: IconButton.outlined(
                key: Key('$labelKey-minute-increase'),
                tooltip: YorksV1WorkforceStrings.text(
                  language,
                  'increase_minutes',
                ),
                onPressed: enabled && value < 1440
                    ? () => onChanged(math.min(1440, value + 15))
                    : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletCompletionFooter extends StatelessWidget {
  const _TabletCompletionFooter({
    required this.language,
    required this.state,
    required this.onReview,
    required this.onBack,
    required this.onSave,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final bool Function() onReview;
  final VoidCallback onBack;
  final Future<YorksWorkforceDailyRosterSaveResult?> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final entered = state.rows
        .where((row) => row.status != YorksWorkforceAttendanceStatus.notEntered)
        .length;
    final canReview =
        state.dirtyRows.isNotEmpty &&
        state.invalidWorkerIds.isEmpty &&
        state.isOnline &&
        !state.isBusy &&
        state.projection?.isFuture != true;
    final canSave = state.isReviewing && canReview;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${YorksV1WorkforceStrings.text(language, 'tablet_completion')}: $entered/${state.rows.length}',
      child: Material(
        key: const Key('workforce-tablet-completion-footer'),
        elevation: 10,
        color: AppColors.surfaceContainerLowest,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$entered/${state.rows.length} ${YorksV1WorkforceStrings.text(language, 'tablet_completion')}',
                        style: AppTypography.labelLarge,
                      ),
                      Text(
                        '${state.dirtyRows.length} ${YorksV1WorkforceStrings.text(language, 'changed_rows')}',
                        style: AppTypography.bodySmall.copyWith(
                          color: state.invalidWorkerIds.isEmpty
                              ? AppColors.muted
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.isReviewing) ...[
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      key: const Key('workforce-tablet-back-to-edit'),
                      onPressed: state.isBusy ? null : onBack,
                      child: Text(
                        YorksV1WorkforceStrings.text(language, 'back_to_edit'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      key: const Key('workforce-tablet-save-day'),
                      onPressed: canSave ? () => onSave() : null,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        YorksV1WorkforceStrings.text(language, 'save_day'),
                      ),
                    ),
                  ),
                ] else
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      key: const Key('workforce-tablet-review-day'),
                      onPressed: canReview ? () => onReview() : null,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(
                        YorksV1WorkforceStrings.text(language, 'review_day'),
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
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class _RosterGrid extends StatefulWidget {
  const _RosterGrid({
    required this.language,
    required this.state,
    required this.controller,
    required this.activeWorkerId,
    required this.onWorkerSelected,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final String? activeWorkerId;
  final ValueChanged<String> onWorkerSelected;

  @override
  State<_RosterGrid> createState() => _RosterGridState();
}

class _RosterGridState extends State<_RosterGrid> {
  static const _workerWidth = 220.0;
  static const _dataWidth = 1030.0;
  static const _rowHeight = 64.0;
  final _horizontal = ScrollController();
  final _workerVertical = ScrollController();
  final _dataVertical = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _workerVertical.addListener(() => _sync(_workerVertical, _dataVertical));
    _dataVertical.addListener(() => _sync(_dataVertical, _workerVertical));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    final target = from.offset.clamp(0.0, to.position.maxScrollExtent);
    if ((to.offset - target).abs() > .5) to.jumpTo(target);
    _syncing = false;
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _workerVertical.dispose();
    _dataVertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.rows.isEmpty) {
      return Card(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              YorksV1WorkforceStrings.text(widget.language, 'empty'),
              style: AppTypography.bodyMedium,
            ),
          ),
        ),
      );
    }
    final bodyHeight = math.min(
      416.0,
      math.max(156.0, widget.state.rows.length * _rowHeight),
    );
    return Card(
      key: const Key('workforce-desktop-roster-grid'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 48 + bodyHeight,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  SizedBox(
                    width: _workerWidth,
                    child: _WorkerHeader(
                      language: widget.language,
                      allSelected: widget.state.rows
                          .where((row) => row.isEditable)
                          .every(
                            (row) => widget.state.selectedWorkerIds.contains(
                              row.workerId,
                            ),
                          ),
                      onToggle: widget.controller.selectVisible,
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: AnimatedBuilder(
                        animation: _horizontal,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(
                            -(_horizontal.hasClients
                                ? _horizontal.offset
                                : 0.0),
                            0,
                          ),
                          child: child,
                        ),
                        child: OverflowBox(
                          alignment: AlignmentDirectional.centerStart,
                          minWidth: _dataWidth,
                          maxWidth: _dataWidth,
                          child: SizedBox(
                            width: _dataWidth,
                            child: _DataHeader(language: widget.language),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _workerWidth,
                    child: ListView.builder(
                      controller: _workerVertical,
                      itemExtent: _rowHeight,
                      itemCount: widget.state.rows.length,
                      itemBuilder: (context, index) => _WorkerCell(
                        row: widget.state.rows[index],
                        selected: widget.state.selectedWorkerIds.contains(
                          widget.state.rows[index].workerId,
                        ),
                        focused:
                            widget.activeWorkerId ==
                            widget.state.rows[index].workerId,
                        onToggle: widget.controller.toggleSelection,
                        onOpen: widget.onWorkerSelected,
                      ),
                    ),
                  ),
                  const VerticalDivider(),
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _dataWidth,
                          height: bodyHeight,
                          child: ListView.builder(
                            controller: _dataVertical,
                            itemExtent: _rowHeight,
                            itemCount: widget.state.rows.length,
                            itemBuilder: (context, index) => _RosterDataRow(
                              key: ValueKey(widget.state.rows[index].workerId),
                              index: index,
                              language: widget.language,
                              row: widget.state.rows[index],
                              allocationTargets:
                                  widget.state.projection!.allocationTargets,
                              selected: widget.state.selectedWorkerIds.contains(
                                widget.state.rows[index].workerId,
                              ),
                              controller: widget.controller,
                            ),
                          ),
                        ),
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
  }
}

class _WorkerHeader extends StatelessWidget {
  const _WorkerHeader({
    required this.language,
    required this.allSelected,
    required this.onToggle,
  });

  final AppLanguage language;
  final bool allSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceContainerLow,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    child: Row(
      children: [
        Checkbox(value: allSelected, onChanged: (_) => onToggle()),
        Text(
          YorksV1WorkforceStrings.text(language, 'worker'),
          style: AppTypography.labelLarge,
        ),
      ],
    ),
  );
}

class _DataHeader extends StatelessWidget {
  const _DataHeader({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceContainerLow,
    child: Row(
      children: [
        _header(language, 'assignment', 170),
        _header(language, 'status', 150),
        _header(language, 'regular', 90),
        _header(language, 'overtime', 90),
        _header(language, 'target', 220),
        _header(language, 'activity', 145),
        _header(language, 'note_exception', 165),
      ],
    ),
  );

  Widget _header(AppLanguage language, String key, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        YorksV1WorkforceStrings.text(language, key),
        style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _WorkerCell extends StatelessWidget {
  const _WorkerCell({
    required this.row,
    required this.selected,
    required this.focused,
    required this.onToggle,
    required this.onOpen,
  });
  final YorksWorkforceDailyRosterDraftRow row;
  final bool selected;
  final bool focused;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${row.source.workerName}, ${row.source.workerNumber}',
    selected: selected,
    excludeSemantics: true,
    child: Material(
      color: focused
          ? AppColors.primaryContainer
          : selected
          ? AppColors.blueContainer
          : Colors.white,
      child: InkWell(
        onTap: () => onOpen(row.workerId),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: AppColors.line),
              left: BorderSide(
                color: focused ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: row.isEditable
                    ? (_) => onToggle(row.workerId)
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.source.workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge,
                    ),
                    Text(
                      [
                        row.source.workerNumber,
                        row.source.tradeName ?? row.source.designation,
                      ].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!row.isValid)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(Icons.error, size: 16, color: AppColors.error),
                )
              else if (focused)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RosterDataRow extends StatefulWidget {
  const _RosterDataRow({
    super.key,
    required this.index,
    required this.language,
    required this.row,
    required this.allocationTargets,
    required this.selected,
    required this.controller,
  });

  final int index;
  final AppLanguage language;
  final YorksWorkforceDailyRosterDraftRow row;
  final YorksWorkforceRosterAllocationTargets allocationTargets;
  final bool selected;
  final YorksWorkforceDailyRosterController controller;

  @override
  State<_RosterDataRow> createState() => _RosterDataRowState();
}

class _RosterDataRowState extends State<_RosterDataRow> {
  late final TextEditingController _regular;
  late final TextEditingController _overtime;
  late final TextEditingController _activity;
  late final TextEditingController _exception;

  @override
  void initState() {
    super.initState();
    _regular = TextEditingController(text: '${widget.row.regularMinutes}');
    _overtime = TextEditingController(text: '${widget.row.overtimeMinutes}');
    _activity = TextEditingController(text: _first?.activityTask ?? '');
    _exception = TextEditingController(text: _exceptionValue);
  }

  YorksWorkforceAllocationInput? get _first =>
      widget.row.allocations.length == 1 ? widget.row.allocations.single : null;
  String get _exceptionValue => widget.row.overtimeMinutes > 0
      ? widget.row.overtimeReason ?? ''
      : _first?.notes ?? '';

  @override
  void didUpdateWidget(covariant _RosterDataRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_regular, '${widget.row.regularMinutes}');
    _sync(_overtime, '${widget.row.overtimeMinutes}');
    _sync(_activity, _first?.activityTask ?? '');
    _sync(_exception, _exceptionValue);
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value) controller.text = value;
  }

  @override
  void dispose() {
    _regular.dispose();
    _overtime.dispose();
    _activity.dispose();
    _exception.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final enabled = row.isEditable;
    final targetOptions = _targetOptions(widget.allocationTargets);
    final currentTarget = _targetValue(row);
    final exceptionEditsEvidence = row.overtimeMinutes > 0;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    void next() => FocusScope.of(context).nextFocus();
    void previous() => FocusScope.of(context).previousFocus();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): next,
        const SingleActivator(LogicalKeyboardKey.arrowUp): previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight): isRtl
            ? previous
            : next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): isRtl
            ? next
            : previous,
        const SingleActivator(LogicalKeyboardKey.enter): next,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): previous,
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.blueContainer.withValues(alpha: .55)
              : row.isDirty
              ? AppColors.warningContainer.withValues(alpha: .45)
              : AppColors.surfaceContainerLowest,
          border: const Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            _cell(
              170,
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _assignment(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  Text(
                    _sourceLabel(widget.language, row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color:
                          row.draftSource ==
                              YorksWorkforceRosterDraftSource.previousDay
                          ? AppColors.warning
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            _cell(
              150,
              FocusTraversalOrder(
                order: NumericFocusOrder(widget.index * 10 + 1),
                child: DropdownButtonFormField<YorksWorkforceAttendanceStatus>(
                  key: ValueKey(
                    '${row.workerId}-status-${row.status.wireValue}',
                  ),
                  initialValue: row.status,
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: [
                    for (final status in YorksWorkforceAttendanceStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(
                          _statusLabel(widget.language, status),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) {
                          if (value != null) {
                            widget.controller.updateRow(
                              row.workerId,
                              status: value,
                            );
                          }
                        }
                      : null,
                ),
              ),
            ),
            _cell(
              90,
              _minuteField(
                _regular,
                enabled && row.status == YorksWorkforceAttendanceStatus.present,
                widget.index * 10 + 2,
                (value) => widget.controller.updateRow(
                  row.workerId,
                  regularMinutes: int.tryParse(value) ?? 0,
                ),
              ),
            ),
            _cell(
              90,
              _minuteField(
                _overtime,
                enabled && row.status == YorksWorkforceAttendanceStatus.present,
                widget.index * 10 + 3,
                (value) => widget.controller.updateRow(
                  row.workerId,
                  overtimeMinutes: int.tryParse(value) ?? 0,
                ),
              ),
            ),
            _cell(
              220,
              row.source.allocationDetailsRestricted
                  ? _locked(widget.language, 'allocation_restricted')
                  : DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${row.workerId}-target-${currentTarget ?? 'none'}',
                      ),
                      initialValue:
                          targetOptions.any(
                            (option) => option.value == currentTarget,
                          )
                          ? currentTarget
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(),
                      hint: Text(
                        row.allocations.length > 1
                            ? YorksV1WorkforceStrings.text(
                                widget.language,
                                'multiple_allocations',
                              )
                            : YorksV1WorkforceStrings.text(
                                widget.language,
                                'none',
                              ),
                      ),
                      items: [
                        for (final option in targetOptions)
                          DropdownMenuItem(
                            value: option.value,
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged:
                          row.isAllocationEditable &&
                              row.status ==
                                  YorksWorkforceAttendanceStatus.present &&
                              row.regularMinutes + row.overtimeMinutes > 0
                          ? (value) {
                              final option = targetOptions
                                  .where((row) => row.value == value)
                                  .firstOrNull;
                              if (option == null) return;
                              if (option.kind ==
                                  YorksWorkforceAllocationTargetKind
                                      .projectWork) {
                                widget.controller.assignProject(
                                  row.workerId,
                                  projectId: option.projectId!,
                                  projectScopeId: option.scopeId!,
                                );
                              } else {
                                widget.controller.assignInternalLocation(
                                  row.workerId,
                                  option.locationId!,
                                );
                              }
                            }
                          : null,
                    ),
            ),
            _cell(
              145,
              TextField(
                controller: _activity,
                enabled: row.isAllocationEditable && row.allocations.isNotEmpty,
                maxLength: 500,
                buildCounter: _noCounter,
                decoration: const InputDecoration(),
                onChanged: (value) =>
                    widget.controller.updateActivity(row.workerId, value),
              ),
            ),
            _cell(
              165,
              TextField(
                controller: _exception,
                enabled: exceptionEditsEvidence
                    ? row.canEditAttendanceEvidence
                    : row.isAllocationEditable && row.allocations.isNotEmpty,
                maxLength: 2000,
                buildCounter: _noCounter,
                decoration: const InputDecoration(),
                onChanged: (value) {
                  if (exceptionEditsEvidence) {
                    widget.controller.updateRow(
                      row.workerId,
                      overtimeReason: value,
                      clearOvertimeReason: value.trim().isEmpty,
                    );
                  } else {
                    widget.controller.updateAllocationNote(row.workerId, value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(double width, Widget child) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: child,
    ),
  );

  Widget _minuteField(
    TextEditingController controller,
    bool enabled,
    double order,
    ValueChanged<String> changed,
  ) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.end,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(),
      onChanged: changed,
    ),
  );

  Widget _locked(AppLanguage language, String key) => Tooltip(
    message: YorksV1WorkforceStrings.text(language, key),
    child: const Align(
      alignment: AlignmentDirectional.centerStart,
      child: Icon(Icons.lock_outline, color: AppColors.muted, size: 18),
    ),
  );

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}

class _MobileTodayRoster extends StatelessWidget {
  const _MobileTodayRoster({
    required this.language,
    required this.state,
    required this.controller,
    required this.searchController,
    required this.onSearch,
    required this.onOpenWorker,
    required this.onBulk,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final YorksWorkforceDailyRosterController controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onOpenWorker;
  final VoidCallback onBulk;

  void _quickMark(
    BuildContext context,
    YorksWorkforceDailyRosterDraftRow before,
    VoidCallback action,
  ) {
    action();
    final after = controller.currentRow(before.workerId);
    if (after == null || identical(before, after)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            YorksV1WorkforceStrings.text(language, 'attendance_changed'),
          ),
          action: SnackBarAction(
            label: YorksV1WorkforceStrings.text(language, 'undo_mark'),
            onPressed: () => controller.undoQuickMark(before, after),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final entered = state.rows
        .where((row) => row.status != YorksWorkforceAttendanceStatus.notEntered)
        .length;
    final missing = state.rows.length - entered;
    final targets = state.projection!.allocationTargets;
    return Column(
      key: const Key('workforce-mobile-today-team'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
                          YorksV1WorkforceStrings.text(
                            language,
                            'mobile_today_team',
                          ),
                          style: AppTypography.titleLarge,
                        ),
                        Text(
                          state.workDate,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      key: const Key('workforce-mobile-bulk-actions'),
                      onPressed: state.isBusy ? null : onBulk,
                      icon: const Icon(Icons.playlist_add_check, size: 18),
                      label: Text(
                        YorksV1WorkforceStrings.text(
                          language,
                          'mobile_bulk_short',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  _MobileCountCue(
                    icon: Icons.groups_outlined,
                    label:
                        '${state.rows.length} ${YorksV1WorkforceStrings.text(language, 'total_workers')}',
                    color: AppColors.blue,
                  ),
                  _MobileCountCue(
                    icon: Icons.task_alt_outlined,
                    label:
                        '$entered ${YorksV1WorkforceStrings.text(language, 'mobile_complete')}',
                    color: AppColors.success,
                  ),
                  _MobileCountCue(
                    icon: Icons.pending_actions_outlined,
                    label:
                        '$missing ${YorksV1WorkforceStrings.text(language, 'mobile_missing')}',
                    color: missing == 0 ? AppColors.success : AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('workforce-mobile-worker-search'),
                controller: searchController,
                onChanged: onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: YorksV1WorkforceStrings.text(
                    language,
                    'search_workers',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (state.rows.isEmpty)
          Card(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    YorksV1WorkforceStrings.text(language, 'empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          )
        else
          for (final row in state.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _MobileWorkerCard(
                language: language,
                row: row,
                targetLabel: row.source.allocationDetailsRestricted
                    ? YorksV1WorkforceStrings.text(
                        language,
                        'allocation_restricted',
                      )
                    : _targetLabel(language, row, targets),
                selected: state.selectedWorkerIds.contains(row.workerId),
                onToggle: controller.toggleSelection,
                onOpen: onOpenWorker,
                onPresent: state.isBusy || !row.isEditable
                    ? null
                    : () {
                        _quickMark(context, row, () {
                          if (!controller.markPresent(row.workerId)) {
                            onOpenWorker(row.workerId);
                          }
                        });
                      },
                onAbsent: state.isBusy || !row.isEditable
                    ? null
                    : () => _quickMark(
                        context,
                        row,
                        () => controller.updateRow(
                          row.workerId,
                          status: YorksWorkforceAttendanceStatus.absent,
                        ),
                      ),
              ),
            ),
        if (state.canLoadMore) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: state.isBusy ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(YorksV1WorkforceStrings.text(language, 'load_more')),
            ),
          ),
        ],
      ],
    );
  }
}

class _MobileCountCue extends StatelessWidget {
  const _MobileCountCue({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelSmall),
      ],
    ),
  );
}

class _MobileWorkerCard extends StatelessWidget {
  const _MobileWorkerCard({
    required this.language,
    required this.row,
    required this.targetLabel,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    required this.onPresent,
    required this.onAbsent,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterDraftRow row;
  final String targetLabel;
  final bool selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onOpen;
  final VoidCallback? onPresent;
  final VoidCallback? onAbsent;

  @override
  Widget build(BuildContext context) {
    final status = _statusLabel(language, row.status);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${row.source.workerName}, ${row.source.workerNumber}, $status, ${_minutes(row.regularMinutes)} ${YorksV1WorkforceStrings.text(language, 'regular_hours')}, ${_minutes(row.overtimeMinutes)} ${YorksV1WorkforceStrings.text(language, 'overtime_hours')}',
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: row.isDirty
            ? AppColors.warningContainer.withValues(alpha: .34)
            : AppColors.surfaceContainerLowest,
        child: InkWell(
          key: Key('workforce-mobile-worker-${row.workerId}'),
          onTap: () => onOpen(row.workerId),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 116),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 44,
                    child: Checkbox(
                      value: selected,
                      onChanged: row.isEditable
                          ? (_) => onToggle(row.workerId)
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.source.workerName,
                          style: AppTypography.titleSmall,
                        ),
                        Text(
                          [
                            row.source.workerNumber,
                            row.source.tradeName ?? row.source.designation,
                          ].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: 2,
                          children: [
                            _StatusDot(
                              label: status,
                              color: _statusColor(row.status),
                            ),
                            _StatusDot(
                              label:
                                  '${_minutes(row.regularMinutes)} + ${_minutes(row.overtimeMinutes)} OT',
                              color: AppColors.blue,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(
                              row.source.allocationDetailsRestricted
                                  ? Icons.lock_outline
                                  : Icons.location_on_outlined,
                              size: 15,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                targetLabel ==
                                        YorksV1WorkforceStrings.text(
                                          language,
                                          'none',
                                        )
                                    ? _assignment(row)
                                    : targetLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            OutlinedButton(
                              key: Key('workforce-present-${row.workerId}'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                backgroundColor:
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.present
                                    ? AppColors.successContainer
                                    : null,
                              ),
                              onPressed: onPresent,
                              child: Text(
                                _statusLabel(
                                  language,
                                  YorksWorkforceAttendanceStatus.present,
                                ),
                              ),
                            ),
                            OutlinedButton(
                              key: Key('workforce-absent-${row.workerId}'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                backgroundColor:
                                    row.status ==
                                        YorksWorkforceAttendanceStatus.absent
                                    ? AppColors.warningContainer
                                    : null,
                              ),
                              onPressed: onAbsent,
                              child: Text(
                                _statusLabel(
                                  language,
                                  YorksWorkforceAttendanceStatus.absent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          key: Key('workforce-mobile-details-${row.workerId}'),
                          onPressed: () => onOpen(row.workerId),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.tune, size: 18),
                          label: Text(
                            YorksV1WorkforceStrings.text(
                              language,
                              'mobile_more',
                            ),
                          ),
                        ),
                        if (row.isDirty || !row.isValid) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            row.isValid
                                ? _sourceLabel(language, row)
                                : YorksV1WorkforceStrings.text(
                                    language,
                                    'validation_minutes',
                                  ),
                            style: AppTypography.labelSmall.copyWith(
                              color: row.isValid
                                  ? AppColors.warning
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox.square(
                    dimension: 44,
                    child: Icon(Icons.chevron_right, color: AppColors.muted),
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

class _MobileCompletionFooter extends StatelessWidget {
  const _MobileCompletionFooter({
    required this.language,
    required this.state,
    required this.onReview,
    required this.onBack,
    required this.onSave,
  });

  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final bool Function() onReview;
  final VoidCallback onBack;
  final Future<YorksWorkforceDailyRosterSaveResult?> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final entered = state.rows
        .where((row) => row.status != YorksWorkforceAttendanceStatus.notEntered)
        .length;
    final canReview =
        state.dirtyRows.isNotEmpty &&
        state.invalidWorkerIds.isEmpty &&
        state.isOnline &&
        !state.isBusy &&
        state.projection?.isFuture != true;
    final canSave = state.isReviewing && canReview;
    final hint = state.isBusy || state.projection?.isFuture == true
        ? null
        : !state.isOnline
        ? 'mobile_save_offline'
        : state.invalidWorkerIds.isNotEmpty
        ? 'mobile_save_invalid'
        : state.dirtyRows.isEmpty
        ? 'mobile_save_idle'
        : null;

    return Material(
      key: const Key('workforce-mobile-completion-footer'),
      elevation: 12,
      color: AppColors.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.mobileScreenHorizontal,
            AppSpacing.sm,
            AppSpacing.mobileScreenHorizontal,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                label:
                    '$entered ${YorksV1WorkforceStrings.text(language, 'mobile_of')} ${state.rows.length} ${YorksV1WorkforceStrings.text(language, 'mobile_complete')}',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$entered ${YorksV1WorkforceStrings.text(language, 'mobile_of')} ${state.rows.length} ${YorksV1WorkforceStrings.text(language, 'mobile_complete')}',
                        style: AppTypography.labelLarge,
                      ),
                    ),
                    Text(
                      '${state.dirtyRows.length} ${YorksV1WorkforceStrings.text(language, 'mobile_unsaved')}',
                      style: AppTypography.labelSmall.copyWith(
                        color: state.invalidWorkerIds.isEmpty
                            ? AppColors.muted
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1WorkforceStrings.text(language, hint),
                  key: const Key('workforce-mobile-save-hint'),
                  style: AppTypography.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (state.isReviewing)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          key: const Key('workforce-mobile-back-to-edit'),
                          onPressed: state.isBusy ? null : onBack,
                          child: Text(
                            YorksV1WorkforceStrings.text(
                              language,
                              'back_to_edit',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          key: const Key('workforce-mobile-save-day'),
                          onPressed: canSave ? () => onSave() : null,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            YorksV1WorkforceStrings.text(language, 'save_day'),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    key: const Key('workforce-mobile-review-day'),
                    onPressed: canReview ? () => onReview() : null,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      YorksV1WorkforceStrings.text(
                        language,
                        'mobile_check_save',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RosterReview extends StatelessWidget {
  const _RosterReview({
    required this.language,
    required this.state,
    this.showActions = true,
    required this.onBack,
    required this.onSave,
  });
  final AppLanguage language;
  final YorksWorkforceDailyRosterState state;
  final bool showActions;
  final VoidCallback onBack;
  final Future<YorksWorkforceDailyRosterSaveResult?> Function()? onSave;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
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
                      YorksV1WorkforceStrings.text(language, 'review_title'),
                      style: AppTypography.titleLarge,
                    ),
                    Text(
                      YorksV1WorkforceStrings.text(language, 'review_body'),
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (showActions) ...[
                OutlinedButton(
                  onPressed: onBack,
                  child: Text(
                    YorksV1WorkforceStrings.text(language, 'back_to_edit'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    YorksV1WorkforceStrings.text(language, 'save_day'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${state.dirtyRows.length} ${YorksV1WorkforceStrings.text(language, 'changed_rows')}',
            style: AppTypography.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in state.dirtyRows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                row.isValid ? Icons.check_circle : Icons.error,
                color: row.isValid ? AppColors.success : AppColors.error,
              ),
              title: Text(row.source.workerName),
              subtitle: Text(
                '${_statusLabel(language, row.status)} · ${_minutes(row.regularMinutes)} + ${_minutes(row.overtimeMinutes)} · ${_sourceLabel(language, row)}',
              ),
              trailing: Text(
                _targetLabel(
                  language,
                  row,
                  state.projection!.allocationTargets,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: List.generate(
          6,
          (index) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: LinearProgressIndicator(
              minHeight: 16,
              color: AppColors.surfaceContainerHighest,
              backgroundColor: AppColors.surfaceContainerLow,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _TargetOption {
  const _TargetOption({
    required this.value,
    required this.label,
    required this.kind,
    this.projectId,
    this.scopeId,
    this.locationId,
  });
  final String value;
  final String label;
  final YorksWorkforceAllocationTargetKind kind;
  final String? projectId;
  final String? scopeId;
  final String? locationId;
}

List<_TargetOption> _targetOptions(
  YorksWorkforceRosterAllocationTargets targets,
) {
  final projects = {for (final row in targets.projects) row.id: row};
  return [
    for (final scope in targets.projectScopes)
      _TargetOption(
        value: 'p:${scope.projectId}:${scope.id}',
        label: '${projects[scope.projectId]?.reference ?? ''} · ${scope.name}',
        kind: YorksWorkforceAllocationTargetKind.projectWork,
        projectId: scope.projectId,
        scopeId: scope.id,
      ),
    for (final location in targets.internalLocations)
      _TargetOption(
        value: 'i:${location.id}',
        label: location.name,
        kind: YorksWorkforceAllocationTargetKind.internalWork,
        locationId: location.id,
      ),
  ];
}

String _targetValueForAllocation(YorksWorkforceAllocationInput allocation) =>
    switch (allocation.targetKind) {
      YorksWorkforceAllocationTargetKind.projectWork =>
        'p:${allocation.projectId}:${allocation.projectScopeId}',
      YorksWorkforceAllocationTargetKind.internalWork =>
        'i:${allocation.internalLocationId}',
    };

YorksWorkforceAllocationInput _allocationForTarget(
  _TargetOption option,
  YorksWorkforceAllocationInput source,
) => YorksWorkforceAllocationInput(
  targetKind: option.kind,
  projectId: option.projectId,
  projectScopeId: option.scopeId,
  internalLocationId: option.locationId,
  activityTask: source.activityTask,
  notes: source.notes,
  regularMinutes: source.regularMinutes,
  overtimeMinutes: source.overtimeMinutes,
  startTime: source.startTime,
  endTime: source.endTime,
);

YorksWorkforceAllocationInput _copyAllocationInput(
  YorksWorkforceAllocationInput source, {
  int? regularMinutes,
  int? overtimeMinutes,
  String? activityTask,
}) => YorksWorkforceAllocationInput(
  targetKind: source.targetKind,
  projectId: source.projectId,
  projectScopeId: source.projectScopeId,
  internalLocationId: source.internalLocationId,
  activityTask: activityTask ?? source.activityTask,
  notes: source.notes,
  regularMinutes: regularMinutes ?? source.regularMinutes,
  overtimeMinutes: overtimeMinutes ?? source.overtimeMinutes,
  startTime: source.startTime,
  endTime: source.endTime,
);

List<YorksWorkforceAllocationInput> _splitAllocationDraft(
  List<YorksWorkforceAllocationInput> current,
  List<_TargetOption> targetOptions,
) {
  if (current.isEmpty || targetOptions.isEmpty) return current;
  var sourceIndex = 0;
  for (var index = 1; index < current.length; index++) {
    final candidate =
        current[index].regularMinutes + current[index].overtimeMinutes;
    final source =
        current[sourceIndex].regularMinutes +
        current[sourceIndex].overtimeMinutes;
    if (candidate > source) sourceIndex = index;
  }
  final source = current[sourceIndex];
  final total = source.regularMinutes + source.overtimeMinutes;
  if (total < 2) return current;
  final used = current.map(_targetValueForAllocation).toSet();
  final option =
      targetOptions.where((item) => !used.contains(item.value)).firstOrNull ??
      targetOptions.first;
  var newRegular = source.regularMinutes ~/ 2;
  var newOvertime = source.overtimeMinutes ~/ 2;
  if (newRegular + newOvertime == 0) {
    if (source.regularMinutes > 0) {
      newRegular = 1;
    } else {
      newOvertime = 1;
    }
  }
  final result = [...current];
  result[sourceIndex] = _copyAllocationInput(
    source,
    regularMinutes: source.regularMinutes - newRegular,
    overtimeMinutes: source.overtimeMinutes - newOvertime,
  );
  result.add(
    YorksWorkforceAllocationInput(
      targetKind: option.kind,
      projectId: option.projectId,
      projectScopeId: option.scopeId,
      internalLocationId: option.locationId,
      activityTask: source.activityTask,
      notes: source.notes,
      regularMinutes: newRegular,
      overtimeMinutes: newOvertime,
    ),
  );
  return result;
}

String? _targetValue(YorksWorkforceDailyRosterDraftRow row) {
  if (row.allocations.length != 1) return null;
  final target = row.allocations.single;
  return switch (target.targetKind) {
    YorksWorkforceAllocationTargetKind.projectWork =>
      'p:${target.projectId}:${target.projectScopeId}',
    YorksWorkforceAllocationTargetKind.internalWork =>
      'i:${target.internalLocationId}',
  };
}

String _targetLabel(
  AppLanguage language,
  YorksWorkforceDailyRosterDraftRow row,
  YorksWorkforceRosterAllocationTargets targets,
) {
  final value = _targetValue(row);
  final none = YorksV1WorkforceStrings.text(language, 'none');
  if (value == null) return none;
  return _targetOptions(targets)
          .where((option) => option.value == value)
          .map((option) => option.label)
          .firstOrNull ??
      none;
}

String _assignment(YorksWorkforceDailyRosterDraftRow row) {
  final assignment = row.source.assignment;
  return assignment.projectRef != null
      ? [
          assignment.projectRef,
          assignment.projectScopeName,
        ].whereType<String>().join(' · ')
      : assignment.internalLocationName ?? assignment.teamName;
}

String _sourceLabel(
  AppLanguage language,
  YorksWorkforceDailyRosterDraftRow row,
) => YorksV1WorkforceStrings.text(language, switch (row.draftSource) {
  YorksWorkforceRosterDraftSource.scheduleStandard => 'prefilled_shift',
  YorksWorkforceRosterDraftSource.previousDay => 'needs_review',
  YorksWorkforceRosterDraftSource.committed => 'committed_source',
  YorksWorkforceRosterDraftSource.manual => 'manual_source',
  YorksWorkforceRosterDraftSource.empty => 'standard_source',
});

String _statusLabel(
  AppLanguage language,
  YorksWorkforceAttendanceStatus status,
) => YorksV1WorkforceStrings.text(language, status.wireValue);

Color _statusColor(YorksWorkforceAttendanceStatus status) => switch (status) {
  YorksWorkforceAttendanceStatus.present => AppColors.success,
  YorksWorkforceAttendanceStatus.absent => AppColors.error,
  YorksWorkforceAttendanceStatus.notEntered => AppColors.warning,
  _ => AppColors.purple,
};

String _minutes(int value) {
  final hours = value ~/ 60;
  final minutes = value % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

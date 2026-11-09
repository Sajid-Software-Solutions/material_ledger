import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/ledger_card.dart';
import '../../../../core/widgets/yorks_v1_active_text.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_user_management_strings.dart';
import '../../../../shared/models/yorks_v1_user_project_access.dart';
import '../../../../shared/providers/yorks_v1_user_project_access_provider.dart';
import '../../../../shared/repositories/yorks_v1_user_project_access_repository.dart';

typedef _S = YorksV1UserManagementStrings;

enum YorksV1UserManagementTab { users, projectAccess, accessHistory }

// ─── Header ─────────────────────────────────────────────────────────────────

/// Same header pattern as the Material Request and Material Return centres.
class YorksV1UserManagementHeader extends StatelessWidget {
  const YorksV1UserManagementHeader({
    super.key,
    required this.language,
    required this.onCreate,
    required this.onRefresh,
  });

  final AppLanguage language;
  final VoidCallback? onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
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
            Icons.manage_accounts_outlined,
            color: AppColors.blue,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YorksV1ActiveText(
                copy: _S.title,
                language: language,
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.displaySmall)
                        .copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              YorksV1ActiveText(
                copy: _S.description,
                language: language,
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
          message: _S.refresh.active(language),
          child: SizedBox.square(
            dimension: AppSpacing.minTapTarget,
            child: IconButton(
              key: const ValueKey('user-management-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        if (onCreate != null)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: FilledButton.icon(
              key: const ValueKey('user-management-create'),
              onPressed: onCreate,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: YorksV1ActiveText(
                copy: _S.newUser,
                language: language,
                style: AppTypography.titleSmall.copyWith(color: Colors.white),
              ),
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
        actions,
      ],
    );
  }
}

// ─── Metrics ────────────────────────────────────────────────────────────────

class YorksV1UserMetric {
  const YorksV1UserMetric({
    required this.id,
    required this.label,
    required this.hint,
    required this.value,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String id;
  final TranslatableString label;
  final TranslatableString hint;
  final String value;
  final IconData icon;
  final Color foreground;
  final Color background;
}

/// Clickable metric cards, laid out like the Material Request Centre.
class YorksV1UserMetricsGrid extends StatelessWidget {
  const YorksV1UserMetricsGrid({
    super.key,
    required this.metrics,
    required this.language,
    required this.selectedId,
    required this.onSelected,
  });

  final List<YorksV1UserMetric> metrics;
  final AppLanguage language;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= AppSpacing.wideBreakpoint
          ? metrics.length
          : width >= AppSpacing.compactBreakpoint
          ? 3
          : 2;
      const gap = AppSpacing.sm;
      final cardWidth = (width - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                metric: metric,
                language: language,
                selected: selectedId == metric.id,
                onTap: () => onSelected(metric.id),
              ),
            ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final YorksV1UserMetric metric;
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: metric.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(metric.icon, color: metric.foreground, size: 21),
    );
    final value = Text(
      metric.value,
      style: AppTypography.headlineSmall.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
    );
    final hint = YorksV1ActiveText(
      copy: metric.hint,
      language: language,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        elevation: selected ? 2 : 1,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? metric.foreground : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: InkWell(
          key: ValueKey('user-management-metric-${metric.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 170) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [icon, const Spacer(), value]),
                      const SizedBox(height: AppSpacing.xs),
                      YorksV1ActiveText(
                        copy: metric.label,
                        language: language,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      hint,
                    ],
                  );
                }
                return Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          YorksV1ActiveText(
                            copy: metric.label,
                            language: language,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          value,
                          hint,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tabs ───────────────────────────────────────────────────────────────────

class YorksV1UserManagementTabs extends StatelessWidget {
  const YorksV1UserManagementTabs({
    super.key,
    required this.language,
    required this.selected,
    required this.showAccessHistory,
    required this.onChanged,
  });

  final AppLanguage language;
  final YorksV1UserManagementTab selected;
  final bool showAccessHistory;
  final ValueChanged<YorksV1UserManagementTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      (YorksV1UserManagementTab.users, _S.usersTab, Icons.people_alt_outlined),
      (
        YorksV1UserManagementTab.projectAccess,
        _S.projectAccessTab,
        Icons.account_tree_outlined,
      ),
      if (showAccessHistory)
        (
          YorksV1UserManagementTab.accessHistory,
          _S.accessHistoryTab,
          Icons.history_rounded,
        ),
    ];
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (tab, label, icon) in options)
                _SegmentOption(
                  key: ValueKey('user-management-tab-${tab.name}'),
                  icon: icon,
                  label: label.active(language),
                  selected: selected == tab,
                  onPressed: () => onChanged(tab),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.surfaceContainerLowest : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.blue : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? AppColors.blue : AppColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─── Shared pills and cells ─────────────────────────────────────────────────

enum YorksV1PillTone { info, success, warning, danger, neutral, accent }

class YorksV1Pill extends StatelessWidget {
  const YorksV1Pill({
    super.key,
    required this.label,
    this.tone = YorksV1PillTone.neutral,
    this.icon,
  });

  final String label;
  final YorksV1PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      YorksV1PillTone.info => (
        AppColors.blueContainer,
        AppColors.onPrimaryContainer,
      ),
      YorksV1PillTone.success => (
        AppColors.successContainer,
        AppColors.onSuccessContainer,
      ),
      YorksV1PillTone.warning => (
        AppColors.warningContainer,
        AppColors.onWarningContainer,
      ),
      YorksV1PillTone.danger => (
        AppColors.errorContainer,
        AppColors.onErrorContainer,
      ),
      YorksV1PillTone.accent => (
        AppColors.purpleContainer,
        AppColors.onTertiaryContainer,
      ),
      YorksV1PillTone.neutral => (
        AppColors.neutralContainer,
        AppColors.neutralText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TranslatableString yorksV1ProjectStateCopy(YorksV1ProjectLifecycle? state) =>
    switch (state) {
      YorksV1ProjectLifecycle.draft => _S.stateDraft,
      YorksV1ProjectLifecycle.active => _S.stateActive,
      YorksV1ProjectLifecycle.onHold => _S.stateOnHold,
      YorksV1ProjectLifecycle.completed => _S.stateCompleted,
      YorksV1ProjectLifecycle.archived => _S.stateArchived,
      null => _S.stateDraft,
    };

YorksV1PillTone yorksV1ProjectStateTone(YorksV1ProjectLifecycle? state) =>
    switch (state) {
      YorksV1ProjectLifecycle.active => YorksV1PillTone.success,
      YorksV1ProjectLifecycle.onHold => YorksV1PillTone.warning,
      YorksV1ProjectLifecycle.completed => YorksV1PillTone.info,
      YorksV1ProjectLifecycle.archived => YorksV1PillTone.neutral,
      _ => YorksV1PillTone.neutral,
    };

TranslatableString yorksV1MembershipRoleCopy(
  YorksV1ProjectMembershipRole role,
) => switch (role) {
  YorksV1ProjectMembershipRole.projectEngineer => _S.projectEngineerRole,
  YorksV1ProjectMembershipRole.siteEngineer => _S.siteEngineerRole,
};

/// Last sign-in as a short, relative label.
String yorksV1LastSignInLabel(
  DateTime? value,
  AppLanguage language, {
  DateTime? now,
}) {
  if (value == null) return _S.neverSignedIn.active(language);
  final local = value.toLocal();
  final today = DateUtils.dateOnly((now ?? DateTime.now()).toLocal());
  final days = today.difference(DateUtils.dateOnly(local)).inDays;
  if (days <= 0) return _S.today.active(language);
  if (days == 1) return _S.yesterday.active(language);
  if (days < 7) return _S.daysAgo(days).active(language);
  return DateFormat('d MMM yyyy').format(local);
}

/// The "Project access" cell of the user directory.
class YorksV1ProjectAccessSummary extends StatelessWidget {
  const YorksV1ProjectAccessSummary({
    super.key,
    required this.access,
    required this.loading,
    required this.language,
    this.maxChips = 2,
  });

  final YorksV1UserProjectAccess? access;
  final bool loading;
  final AppLanguage language;
  final int maxChips;

  @override
  Widget build(BuildContext context) {
    final value = access;
    if (value == null) {
      return Text(
        loading ? _S.projectAccessLoading.active(language) : '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    final (headline, tone) = switch (value.basis) {
      YorksV1ProjectAccessBasis.allProjects => (
        _S.allProjects(value.projectCount),
        YorksV1PillTone.info,
      ),
      YorksV1ProjectAccessBasis.activeProjects => (
        _S.activeProjects(value.projectCount),
        YorksV1PillTone.accent,
      ),
      YorksV1ProjectAccessBasis.assigned =>
        value.memberships.isEmpty
            ? (_S.notOnProject, YorksV1PillTone.warning)
            : (_S.projectsCount(value.projectCount), YorksV1PillTone.success),
      YorksV1ProjectAccessBasis.none => (
        _S.noProjectAccess,
        YorksV1PillTone.neutral,
      ),
    };
    final memberships = value.memberships;
    final shown = memberships.take(maxChips).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        YorksV1Pill(label: headline.active(language), tone: tone),
        if (shown.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final membership in shown)
                Tooltip(
                  message:
                      '${membership.projectName} · ${yorksV1MembershipRoleCopy(membership.role).active(language)}',
                  child: Text(
                    membership.projectRef,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (memberships.length > shown.length)
                Text(
                  _S
                      .moreCount(memberships.length - shown.length)
                      .active(language),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class YorksV1CommercialSummaryPill extends StatelessWidget {
  const YorksV1CommercialSummaryPill({
    super.key,
    required this.summary,
    required this.language,
  });

  final YorksV1UserCommercialSummary? summary;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    if (value == null) {
      return Text(
        '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    if (value.canManage) {
      return YorksV1Pill(
        label: _S.commercialManage.active(language),
        tone: YorksV1PillTone.accent,
      );
    }
    if (value.canView) {
      return YorksV1Pill(
        label: _S.commercialView.active(language),
        tone: YorksV1PillTone.info,
      );
    }
    return YorksV1Pill(
      label: _S.commercialNone.active(language),
      tone: YorksV1PillTone.neutral,
    );
  }
}

class YorksV1UserInitials extends StatelessWidget {
  const YorksV1UserInitials({
    super.key,
    required this.name,
    this.size = 40,
    this.muted = false,
  });

  final String name;
  final double size;
  final bool muted;

  static String initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final part = parts.first;
      return (part.length >= 2 ? part.substring(0, 2) : part).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: muted ? AppColors.neutralContainer : AppColors.blueContainer,
      shape: BoxShape.circle,
    ),
    child: Text(
      initialsFor(name),
      style: (size >= 40 ? AppTypography.labelLarge : AppTypography.labelSmall)
          .copyWith(
            color: muted ? AppColors.neutralText : AppColors.blue,
            fontWeight: FontWeight.w800,
          ),
    ),
  );
}

// ─── Errors ────────────────────────────────────────────────────────────────

TranslatableString yorksV1TeamChangeError(Object error) {
  if (error is YorksV1DomainException) {
    final message = error.serverMessage ?? '';
    if (message.contains('V1_ACTIVE_PROJECT_REQUIRES_PROJECT_ENGINEER')) {
      return _S.needsProjectEngineerError;
    }
    if (message.contains('MUST_HAVE_PROJECT_OR_SITE_ENGINEER')) {
      return _S.notEligibleError;
    }
    if (message.contains('NOT_EDITABLE_IN_CURRENT_STATE')) {
      return _S.projectClosedError;
    }
    if (error.code == YorksV1DomainErrorCode.conflict) {
      return _S.versionConflict;
    }
    if (error.code == YorksV1DomainErrorCode.unauthorized) {
      return _S.notAllowedError;
    }
  }
  return _S.teamChangeFailed;
}

// ─── Project Access tab ────────────────────────────────────────────────────

enum _ProjectFilter { all, open, needsProjectEngineer }

/// Project teams across every readable project, with team management.
class YorksV1ProjectTeamsPanel extends ConsumerStatefulWidget {
  const YorksV1ProjectTeamsPanel({
    super.key,
    required this.language,
    required this.names,
    required this.roleLabels,
    required this.onOpenUser,
  });

  final AppLanguage language;

  /// App user ID → full name from the user directory.
  final Map<String, String> names;

  /// App user ID → role label.
  final Map<String, String> roleLabels;
  final ValueChanged<String> onOpenUser;

  @override
  ConsumerState<YorksV1ProjectTeamsPanel> createState() =>
      _YorksV1ProjectTeamsPanelState();
}

class _YorksV1ProjectTeamsPanelState
    extends ConsumerState<YorksV1ProjectTeamsPanel> {
  final _search = TextEditingController();
  _ProjectFilter _filter = _ProjectFilter.open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _nameFor(YorksV1ProjectTeamAccessMember member) {
    final id = member.appUserId;
    final name = id == null ? null : widget.names[id];
    return (name == null || name.trim().isEmpty) ? member.displayName : name;
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final state = ref.watch(yorksV1UserProjectAccessProvider);
    final repository = ref.watch(yorksV1UserProjectAccessRepositoryProvider);
    if (repository == null) {
      return _PanelMessage(
        icon: Icons.cloud_off_outlined,
        copy: _S.projectAccessOffline,
        language: language,
      );
    }
    return state.when(
      loading: () => const LedgerCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => _PanelMessage(
        icon: Icons.cloud_off_outlined,
        copy: _S.projectAccessUnavailable,
        language: language,
        onRetry: () => ref.invalidate(yorksV1UserProjectAccessProvider),
      ),
      data: (directory) {
        if (directory == null) {
          return _PanelMessage(
            icon: Icons.cloud_off_outlined,
            copy: _S.projectAccessOffline,
            language: language,
          );
        }
        return _buildDirectory(context, directory);
      },
    );
  }

  String _organisationWideDetail(YorksV1UserProjectAccess user) {
    final language = widget.language;
    final scope = user.basis == YorksV1ProjectAccessBasis.activeProjects
        ? _S.activeProjects(user.projectCount)
        : _S.allProjects(user.projectCount);
    final role = widget.roleLabels[user.appUserId] ?? '';
    return [
      role,
      scope.active(language),
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  Widget _buildDirectory(
    BuildContext context,
    YorksV1UserProjectAccessDirectory directory,
  ) {
    final language = widget.language;
    final query = _search.text.trim().toLowerCase();
    final projects = directory.projects
        .where((project) {
          final keep = switch (_filter) {
            _ProjectFilter.all => true,
            _ProjectFilter.open => project.isOpen,
            _ProjectFilter.needsProjectEngineer => project.needsProjectEngineer,
          };
          if (!keep) return false;
          if (query.isEmpty) return true;
          final text = [
            project.projectRef,
            project.projectName,
            for (final member in project.members) _nameFor(member),
          ].join(' ').toLowerCase();
          return text.contains(query);
        })
        .toList(growable: false);
    final needsCount = directory.projects
        .where((project) => project.needsProjectEngineer)
        .length;
    final organisationWide =
        directory.users.values
            .where(
              (user) =>
                  user.isActive &&
                  (user.basis == YorksV1ProjectAccessBasis.allProjects ||
                      user.basis == YorksV1ProjectAccessBasis.activeProjects),
            )
            .toList()
          ..sort(
            (left, right) => (widget.names[left.appUserId] ?? left.appUserId)
                .toLowerCase()
                .compareTo(
                  (widget.names[right.appUserId] ?? right.appUserId)
                      .toLowerCase(),
                ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    YorksV1ActiveText(
                      copy: _S.projectTeams,
                      language: language,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    YorksV1ActiveText(
                      copy: _S.projectTeamsDescription,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _RulesBanner(language: language),
                    const SizedBox(height: AppSpacing.md),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final search = TextField(
                          key: const ValueKey('project-teams-search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: _S.searchProjects.active(language),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: _S.clearSearch.active(language),
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => setState(_search.clear),
                                  ),
                          ),
                        );
                        final filters = Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final filter in _ProjectFilter.values)
                              ChoiceChip(
                                key: ValueKey(
                                  'project-teams-filter-${filter.name}',
                                ),
                                selected: _filter == filter,
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                                label: Text(switch (filter) {
                                  _ProjectFilter.all =>
                                    _S.allProjectsFilter.active(language),
                                  _ProjectFilter.open =>
                                    _S.openProjectsFilter.active(language),
                                  _ProjectFilter.needsProjectEngineer =>
                                    '${_S.needsProjectEngineerFilter.active(language)} · $needsCount',
                                }),
                              ),
                          ],
                        );
                        if (constraints.maxWidth < 900) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              search,
                              const SizedBox(height: AppSpacing.sm),
                              filters,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: AppSpacing.md),
                            filters,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.line),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: projects.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxl,
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.search_off_rounded,
                              size: 36,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            YorksV1ActiveText(
                              copy: _S.noProjects,
                              language: language,
                              textAlign: TextAlign.center,
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < projects.length; i++) ...[
                            _ProjectTeamCard(
                              project: projects[i],
                              language: language,
                              nameFor: _nameFor,
                              onOpenUser: widget.onOpenUser,
                              onManage: projects[i].canManageTeam
                                  ? () => showYorksV1ProjectTeamDialog(
                                      context,
                                      project: projects[i],
                                      directory: directory,
                                      names: widget.names,
                                      roleLabels: widget.roleLabels,
                                      language: language,
                                    )
                                  : null,
                            ),
                            if (i != projects.length - 1)
                              const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (organisationWide.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          LedgerCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public_rounded, color: AppColors.blue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: YorksV1ActiveText(
                        copy: _S.organisationWide,
                        language: language,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                YorksV1ActiveText(
                  copy: _S.organisationWideHint,
                  language: language,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final user in organisationWide)
                      _PersonChip(
                        name: widget.names[user.appUserId] ?? user.appUserId,
                        detail: _organisationWideDetail(user),
                        onTap: () => widget.onOpenUser(user.appUserId),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RulesBanner extends StatelessWidget {
  const _RulesBanner({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .45),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
          child: YorksV1ActiveText(
            copy: _S.accessRules,
            language: language,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.copy,
    required this.language,
    this.onRetry,
  });

  final IconData icon;
  final TranslatableString copy;
  final AppLanguage language;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => LedgerCard(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      children: [
        Icon(icon, size: 36, color: AppColors.muted),
        const SizedBox(height: AppSpacing.sm),
        YorksV1ActiveText(
          copy: copy,
          language: language,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: YorksV1ActiveText(copy: _S.retry, language: language),
          ),
        ],
      ],
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.name,
    required this.detail,
    this.onTap,
    this.muted = false,
  });

  final String name;
  final String detail;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.md, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YorksV1UserInitials(name: name, size: 30, muted: muted),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: muted ? AppColors.muted : AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail.trim().isNotEmpty)
                    Text(
                      detail,
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
        ),
      ),
    ),
  );
}

class _ProjectTeamCard extends StatelessWidget {
  const _ProjectTeamCard({
    required this.project,
    required this.language,
    required this.nameFor,
    required this.onOpenUser,
    required this.onManage,
  });

  final YorksV1ProjectTeamAccess project;
  final AppLanguage language;
  final String Function(YorksV1ProjectTeamAccessMember) nameFor;
  final ValueChanged<String> onOpenUser;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.warningContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(
            Icons.folder_rounded,
            color: AppColors.warning,
            size: 23,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.projectRef,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
              ),
              const SizedBox(height: 2),
              Text(
                project.projectName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  YorksV1Pill(
                    label: yorksV1ProjectStateCopy(
                      project.state,
                    ).active(language),
                    tone: yorksV1ProjectStateTone(project.state),
                  ),
                  if (project.needsProjectEngineer)
                    YorksV1Pill(
                      label: _S.needsProjectEngineerFilter.active(language),
                      tone: YorksV1PillTone.warning,
                      icon: Icons.warning_amber_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    Widget group(
      TranslatableString label,
      Iterable<YorksV1ProjectTeamAccessMember> members,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YorksV1ActiveText(
          copy: label,
          language: language,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (members.isEmpty)
          YorksV1ActiveText(
            copy: _S.noneAssigned,
            language: language,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final member in members)
                _PersonChip(
                  name: nameFor(member),
                  detail: _S
                      .since(
                        DateFormat(
                          'd MMM yyyy',
                        ).format(member.effectiveFrom.toLocal()),
                      )
                      .active(language),
                  muted: !member.isActive,
                  onTap: member.appUserId == null
                      ? null
                      : () => onOpenUser(member.appUserId!),
                ),
            ],
          ),
      ],
    );
    final action = onManage == null
        ? YorksV1Pill(
            label: _S.viewOnly.active(language),
            tone: YorksV1PillTone.neutral,
            icon: Icons.visibility_outlined,
          )
        : SizedBox(
            height: AppSpacing.minTapTarget,
            child: OutlinedButton.icon(
              key: ValueKey('project-team-manage-${project.projectId}'),
              onPressed: onManage,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: YorksV1ActiveText(copy: _S.manageTeam, language: language),
            ),
          );
    return Container(
      key: ValueKey('project-team-${project.projectId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: project.needsProjectEngineer
              ? AppColors.warning.withValues(alpha: .45)
              : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pe = group(_S.projectEngineers, project.projectEngineers);
          final se = group(_S.siteEngineers, project.siteEngineers);
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppSpacing.md),
                pe,
                const SizedBox(height: AppSpacing.md),
                se,
                const SizedBox(height: AppSpacing.md),
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: identity),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 4, child: pe),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 4, child: se),
              const SizedBox(width: AppSpacing.md),
              action,
            ],
          );
        },
      ),
    );
  }
}

// ─── Team dialog ────────────────────────────────────────────────────────────

Future<void> showYorksV1ProjectTeamDialog(
  BuildContext context, {
  required YorksV1ProjectTeamAccess project,
  required YorksV1UserProjectAccessDirectory directory,
  required Map<String, String> names,
  required Map<String, String> roleLabels,
  required AppLanguage language,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim.withValues(alpha: .38),
  builder: (_) => _ProjectTeamDialog(
    project: project,
    directory: directory,
    names: names,
    roleLabels: roleLabels,
    language: language,
  ),
);

class _ProjectTeamDialog extends ConsumerStatefulWidget {
  const _ProjectTeamDialog({
    required this.project,
    required this.directory,
    required this.names,
    required this.roleLabels,
    required this.language,
  });

  final YorksV1ProjectTeamAccess project;
  final YorksV1UserProjectAccessDirectory directory;
  final Map<String, String> names;
  final Map<String, String> roleLabels;
  final AppLanguage language;

  @override
  ConsumerState<_ProjectTeamDialog> createState() => _ProjectTeamDialogState();
}

class _ProjectTeamDialogState extends ConsumerState<_ProjectTeamDialog> {
  late final Map<String, YorksV1ProjectMembershipRole?> _current;
  late final Map<String, YorksV1ProjectMembershipRole?> _selected;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = {
      for (final member in widget.project.members)
        if (member.appUserId != null) member.appUserId!: member.role,
    };
    _selected = {..._current};
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Map<String, YorksV1ProjectMembershipRole?> get _changes => {
    for (final entry in _selected.entries)
      if (entry.value != _current[entry.key]) entry.key: entry.value,
  };

  String _name(String appUserId, String fallback) {
    final name = widget.names[appUserId];
    return name == null || name.trim().isEmpty ? fallback : name;
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final repository = ref.read(yorksV1UserProjectAccessRepositoryProvider);
    if (repository == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final reason = _reason.text.trim().isEmpty
        ? _S.defaultReason.primary
        : _reason.text.trim();
    // Additions and promotions first, removals last, so an active project is
    // never left without a Project Engineer between two commands.
    final ordered = changes.entries.toList()
      ..sort((left, right) {
        int rank(MapEntry<String, YorksV1ProjectMembershipRole?> entry) =>
            switch (entry.value) {
              YorksV1ProjectMembershipRole.projectEngineer => 0,
              YorksV1ProjectMembershipRole.siteEngineer => 1,
              null => 2,
            };
        return rank(left).compareTo(rank(right));
      });
    var version = widget.project.recordVersion;
    try {
      for (final entry in ordered) {
        final result = await repository.setMembership(
          YorksV1SetUserProjectMembershipInput(
            appUserId: entry.key,
            projectId: widget.project.projectId,
            role: entry.value,
            expectedProjectVersion: version,
            reason: reason,
            idempotencyKey: const Uuid().v4(),
          ),
        );
        version = result.projectRecordVersion;
        _current[entry.key] = entry.value;
      }
      ref.invalidate(yorksV1UserProjectAccessProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_S.teamUpdated.active(widget.language))),
      );
    } catch (error) {
      ref.invalidate(yorksV1UserProjectAccessProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = yorksV1TeamChangeError(error).active(widget.language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final project = widget.project;
    final memberIds = _current.keys.toSet();
    final members = [
      for (final member in project.members)
        if (member.appUserId != null) member,
    ];
    final available =
        widget.directory.users.values
            .where(
              (user) =>
                  user.teamEligible && !memberIds.contains(user.appUserId),
            )
            .toList()
          ..sort(
            (left, right) =>
                _name(left.appUserId, left.appUserId).toLowerCase().compareTo(
                  _name(right.appUserId, right.appUserId).toLowerCase(),
                ),
          );
    final pending = _changes.length;
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;

    Widget row({
      required String appUserId,
      required String name,
      required String detail,
      bool muted = false,
    }) => _TeamRoleRow(
      key: ValueKey('team-role-$appUserId'),
      name: name,
      detail: detail,
      muted: muted,
      value: _selected[appUserId],
      changed: _selected[appUserId] != _current[appUserId],
      enabled: !_saving,
      language: language,
      onChanged: (value) => setState(() {
        _selected[appUserId] = value;
        _error = null;
      }),
    );

    return Dialog(
      insetPadding: compact
          ? const EdgeInsets.all(AppSpacing.sm)
          : const EdgeInsets.all(AppSpacing.xl),
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.blueContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.groups_2_outlined,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _S
                              .manageTeamTitle(project.projectRef)
                              .active(language),
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          project.projectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        YorksV1ActiveText(
                          copy: _S.teamDialogDescription,
                          language: language,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _S.close.active(language),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _DialogSectionLabel(
                    copy: _S.onThisProject,
                    language: language,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (members.isEmpty)
                    YorksV1ActiveText(
                      copy: _S.noneAssigned,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  for (final member in members) ...[
                    row(
                      appUserId: member.appUserId!,
                      name: _name(member.appUserId!, member.displayName),
                      detail:
                          widget.roleLabels[member.appUserId!] ??
                          yorksV1MembershipRoleCopy(
                            member.role,
                          ).active(language),
                      muted: !member.isActive,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _DialogSectionLabel(
                    copy: _S.availableEngineers,
                    language: language,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (available.isEmpty)
                    YorksV1ActiveText(
                      copy: _S.noEligibleEngineers,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  for (final user in available) ...[
                    row(
                      appUserId: user.appUserId,
                      name: _name(user.appUserId, user.appUserId),
                      detail: [
                        widget.roleLabels[user.appUserId] ?? '',
                        user.memberships.isEmpty
                            ? _S.notOnProject.active(language)
                            : _S
                                  .projectsCount(user.memberships.length)
                                  .active(language),
                      ].where((part) => part.isNotEmpty).join(' · '),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const ValueKey('project-team-reason'),
                    controller: _reason,
                    enabled: !_saving,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: _S.changeReason.active(language),
                      hintText: _S.changeReasonHint.active(language),
                    ),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xs),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.onErrorContainer,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pending == 0
                          ? ''
                          : _S.changesPending(pending).active(language),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: YorksV1ActiveText(
                      copy: _S.cancel,
                      language: language,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    key: const ValueKey('project-team-save'),
                    onPressed: _saving || pending == 0 ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: YorksV1ActiveText(
                      copy: _S.saveTeam,
                      language: language,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
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

class _DialogSectionLabel extends StatelessWidget {
  const _DialogSectionLabel({required this.copy, required this.language});

  final TranslatableString copy;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => YorksV1ActiveText(
    copy: copy,
    language: language,
    style: AppTypography.labelMedium.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
      letterSpacing: .4,
    ),
  );
}

class _TeamRoleRow extends StatelessWidget {
  const _TeamRoleRow({
    super.key,
    required this.name,
    required this.detail,
    required this.value,
    required this.changed,
    required this.enabled,
    required this.language,
    required this.onChanged,
    this.muted = false,
  });

  final String name;
  final String detail;
  final YorksV1ProjectMembershipRole? value;
  final bool changed;
  final bool enabled;
  final bool muted;
  final AppLanguage language;
  final ValueChanged<YorksV1ProjectMembershipRole?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: changed
          ? AppColors.blueContainer.withValues(alpha: .35)
          : AppColors.surfaceContainerLowest,
      border: Border.all(color: changed ? AppColors.blue : AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final identity = Row(
          children: [
            YorksV1UserInitials(name: name, size: 36, muted: muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                      color: muted ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
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
        final selector = YorksV1MembershipRoleField(
          value: value,
          language: language,
          enabled: enabled,
          allowNone: true,
          onChanged: onChanged,
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: AppSpacing.sm),
              selector,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 230, child: selector),
          ],
        );
      },
    ),
  );
}

/// Role picker for a project membership.
class YorksV1MembershipRoleField extends StatelessWidget {
  const YorksV1MembershipRoleField({
    super.key,
    required this.value,
    required this.language,
    required this.enabled,
    required this.onChanged,
    this.allowNone = false,
    this.label,
  });

  final YorksV1ProjectMembershipRole? value;
  final AppLanguage language;
  final bool enabled;
  final bool allowNone;
  final TranslatableString? label;
  final ValueChanged<YorksV1ProjectMembershipRole?> onChanged;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<YorksV1ProjectMembershipRole?>(
        key: ValueKey('membership-role-${value?.wireValue ?? 'none'}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          labelText: label?.active(language),
        ),
        items: [
          if (allowNone)
            DropdownMenuItem<YorksV1ProjectMembershipRole?>(
              value: null,
              child: Text(
                _S.notOnThisProject.active(language),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final role in YorksV1ProjectMembershipRole.values)
            DropdownMenuItem<YorksV1ProjectMembershipRole?>(
              value: role,
              child: Text(
                yorksV1MembershipRoleCopy(role).active(language),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      );
}

// ─── Edit panel building blocks ────────────────────────────────────────────

/// A titled card inside the edit-user panel.
class YorksV1EditPanelSection extends StatelessWidget {
  const YorksV1EditPanelSection({
    super.key,
    required this.icon,
    required this.title,
    required this.language,
    required this.child,
    this.subtitle,
    this.danger = false,
    this.trailing,
  });

  final IconData icon;
  final TranslatableString title;
  final TranslatableString? subtitle;
  final AppLanguage language;
  final Widget child;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    // A Material (not a decorated box) so switch tiles inside the section
    // keep their ink and background.
    color: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: danger ? AppColors.error.withValues(alpha: .35) : AppColors.line,
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: danger
                      ? AppColors.errorContainer
                      : AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: danger ? AppColors.error : AppColors.blue,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YorksV1ActiveText(
                      copy: title,
                      language: language,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: danger ? AppColors.error : AppColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      YorksV1ActiveText(
                        copy: subtitle!,
                        language: language,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    ),
  );
}

/// Project access inside the edit-user panel: the access basis, the dated
/// memberships, and assignment controls for the projects the actor manages.
class YorksV1UserProjectAccessSection extends ConsumerStatefulWidget {
  const YorksV1UserProjectAccessSection({
    super.key,
    required this.appUserId,
    required this.roleLabel,
    required this.language,
    required this.onOpenProject,
  });

  final String appUserId;
  final String roleLabel;
  final AppLanguage language;
  final ValueChanged<String> onOpenProject;

  @override
  ConsumerState<YorksV1UserProjectAccessSection> createState() =>
      _YorksV1UserProjectAccessSectionState();
}

class _YorksV1UserProjectAccessSectionState
    extends ConsumerState<YorksV1UserProjectAccessSection> {
  String? _addProjectId;
  YorksV1ProjectMembershipRole _addRole =
      YorksV1ProjectMembershipRole.siteEngineer;
  String? _busyProjectId;
  String? _error;

  Future<void> _apply(
    YorksV1ProjectTeamAccess project,
    YorksV1ProjectMembershipRole? role,
  ) async {
    final repository = ref.read(yorksV1UserProjectAccessRepositoryProvider);
    if (repository == null || _busyProjectId != null) return;
    setState(() {
      _busyProjectId = project.projectId;
      _error = null;
    });
    try {
      await repository.setMembership(
        YorksV1SetUserProjectMembershipInput(
          appUserId: widget.appUserId,
          projectId: project.projectId,
          role: role,
          expectedProjectVersion: project.recordVersion,
          reason: _S.defaultReason.primary,
          idempotencyKey: const Uuid().v4(),
        ),
      );
      ref.invalidate(yorksV1UserProjectAccessProvider);
      if (!mounted) return;
      setState(() {
        _busyProjectId = null;
        _addProjectId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_S.projectAccessUpdated.active(widget.language)),
        ),
      );
    } catch (error) {
      ref.invalidate(yorksV1UserProjectAccessProvider);
      if (!mounted) return;
      setState(() {
        _busyProjectId = null;
        _error = yorksV1TeamChangeError(error).active(widget.language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final repository = ref.watch(yorksV1UserProjectAccessRepositoryProvider);
    if (repository == null) {
      return YorksV1ActiveText(
        copy: _S.projectAccessOffline,
        language: language,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      );
    }
    final state = ref.watch(yorksV1UserProjectAccessProvider);
    return state.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, _) => Row(
        children: [
          Expanded(
            child: YorksV1ActiveText(
              copy: _S.projectAccessUnavailable,
              language: language,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(yorksV1UserProjectAccessProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: YorksV1ActiveText(copy: _S.retry, language: language),
          ),
        ],
      ),
      data: (directory) {
        final access = directory?.userFor(widget.appUserId);
        if (directory == null || access == null) {
          return YorksV1ActiveText(
            copy: _S.projectAccessUnavailable,
            language: language,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          );
        }
        return _buildAccess(directory, access);
      },
    );
  }

  Widget _buildAccess(
    YorksV1UserProjectAccessDirectory directory,
    YorksV1UserProjectAccess access,
  ) {
    final language = widget.language;
    final basisCopy = !access.isActive
        ? _S.inactiveBasis
        : switch (access.basis) {
            YorksV1ProjectAccessBasis.allProjects => _S.allProjectsBasis(
              widget.roleLabel,
              access.projectCount,
            ),
            YorksV1ProjectAccessBasis.activeProjects => _S.activeProjectsBasis(
              access.projectCount,
            ),
            YorksV1ProjectAccessBasis.assigned => _S.assignedBasis,
            YorksV1ProjectAccessBasis.none => _S.noneBasis,
          };
    final addable = directory.projects
        .where(
          (project) =>
              project.canManageTeam &&
              access.membershipFor(project.projectId) == null,
        )
        .toList(growable: false);
    final canAssign = access.teamEligible && access.isActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YorksV1ProjectAccessSummary(
              access: access,
              loading: false,
              language: language,
              maxChips: 0,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: YorksV1ActiveText(
                copy: basisCopy,
                language: language,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ],
        ),
        if (access.memberships.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final membership in access.memberships) ...[
            _MembershipRow(
              membership: membership,
              project: directory.projectFor(membership.projectId),
              language: language,
              busy: _busyProjectId == membership.projectId,
              enabled: _busyProjectId == null,
              onRoleChanged: (role) {
                final project = directory.projectFor(membership.projectId);
                if (project != null) _apply(project, role);
              },
              onOpen: () => widget.onOpenProject(membership.projectId),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ] else if (access.basis == YorksV1ProjectAccessBasis.assigned) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warningContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.onWarningContainer,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: YorksV1ActiveText(
                    copy: _S.notOnAnyProject,
                    language: language,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onWarningContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canAssign) ...[
          const SizedBox(height: AppSpacing.md),
          if (addable.isEmpty)
            YorksV1ActiveText(
              copy: _S.noProjectsToAdd,
              language: language,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final projectField = DropdownButtonFormField<String>(
                  key: const ValueKey('user-project-add-project'),
                  initialValue: _addProjectId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _S.chooseProject.active(language),
                  ),
                  items: [
                    for (final project in addable)
                      DropdownMenuItem(
                        value: project.projectId,
                        child: Text(
                          '${project.projectRef} · ${project.projectName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busyProjectId != null
                      ? null
                      : (value) => setState(() => _addProjectId = value),
                );
                final roleField = YorksV1MembershipRoleField(
                  value: _addRole,
                  language: language,
                  enabled: _busyProjectId == null,
                  label: _S.projectRole,
                  onChanged: (role) {
                    if (role != null) setState(() => _addRole = role);
                  },
                );
                final selected = _addProjectId == null
                    ? null
                    : directory.projectFor(_addProjectId!);
                final add = SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: FilledButton.icon(
                    key: const ValueKey('user-project-add'),
                    onPressed: selected == null || _busyProjectId != null
                        ? null
                        : () => _apply(selected, _addRole),
                    icon:
                        _busyProjectId != null &&
                            _busyProjectId == _addProjectId
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: YorksV1ActiveText(
                      copy: _S.addToProjectAction,
                      language: language,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
                if (constraints.maxWidth < 460) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      projectField,
                      const SizedBox(height: AppSpacing.sm),
                      roleField,
                      const SizedBox(height: AppSpacing.sm),
                      add,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 3, child: projectField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 2, child: roleField),
                    const SizedBox(width: AppSpacing.sm),
                    add,
                  ],
                );
              },
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _MembershipRow extends StatelessWidget {
  const _MembershipRow({
    required this.membership,
    required this.project,
    required this.language,
    required this.busy,
    required this.enabled,
    required this.onRoleChanged,
    required this.onOpen,
  });

  final YorksV1UserProjectMembership membership;
  final YorksV1ProjectTeamAccess? project;
  final AppLanguage language;
  final bool busy;
  final bool enabled;
  final ValueChanged<YorksV1ProjectMembershipRole?> onRoleChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final canManage = project?.canManageTeam ?? false;
    final identity = InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, color: AppColors.warning, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.projectRef,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.blue,
                  ),
                ),
                Text(
                  membership.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
                ),
                Text(
                  '${yorksV1ProjectStateCopy(membership.projectState).active(language)} · ${_S.since(DateFormat('d MMM yyyy').format(membership.effectiveFrom.toLocal())).active(language)}',
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
      ),
    );
    final control = canManage
        ? YorksV1MembershipRoleField(
            value: membership.role,
            language: language,
            enabled: enabled,
            allowNone: true,
            onChanged: (role) {
              if (role != membership.role) onRoleChanged(role);
            },
          )
        : YorksV1Pill(
            label: yorksV1MembershipRoleCopy(membership.role).active(language),
            tone: YorksV1PillTone.info,
          );
    return Container(
      key: ValueKey('user-project-membership-${membership.projectId}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trailing = busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : control;
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: trailing,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: canManage ? 210 : null,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

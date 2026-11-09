import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_mobile_ui.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_role_overview_strings.dart';
import 'yorks_v1_role_overview_spec.dart';

typedef _S = YorksV1RoleOverviewStrings;

/// Renders a [YorksRoleOverviewSpec] as the role-based Overview.
///
/// Desktop: page header, KPI tiles, then a wide work column beside a narrower
/// context column, with wide tables across the full page. Phone: greeting,
/// the main action, a 2 × 2 tile grid and the cards in [phoneOrder].
class YorksRoleOverviewLayout extends StatefulWidget {
  const YorksRoleOverviewLayout({
    super.key,
    required this.spec,
    required this.language,
    required this.onRefresh,
    this.updatedAt,
    this.refreshing = false,
    this.compact,
  });

  final YorksRoleOverviewSpec spec;
  final AppLanguage language;
  final Future<void> Function() onRefresh;
  final DateTime? updatedAt;
  final bool refreshing;

  /// Forces the phone layout; defaults to the shared mobile breakpoint.
  final bool? compact;

  @override
  State<YorksRoleOverviewLayout> createState() =>
      _YorksRoleOverviewLayoutState();
}

class _YorksRoleOverviewLayoutState extends State<YorksRoleOverviewLayout> {
  final Map<String, GlobalKey> _keys = {};
  final Map<String, String> _queueTabs = {};
  String? _selectedKpi;

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void _selectKpi(YorksOverviewKpi kpi) {
    if (kpi.onTap != null) {
      kpi.onTap!();
      return;
    }
    final target = kpi.targetSection;
    if (target == null) return;
    setState(() {
      _selectedKpi = kpi.id;
      if (kpi.queueTab != null) _queueTabs[target] = kpi.queueTab!;
    });
    final context = _keys[target]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: MediaQuery.disableAnimationsOf(this.context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  Widget _section(YorksOverviewSection section, {required bool compact}) =>
      KeyedSubtree(
        key: _keyFor(section.id),
        child: _OverviewSectionCard(
          section: section,
          language: widget.language,
          compact: compact,
          queueTab: _queueTabs[section.id],
          onQueueTab: (tab) => setState(() => _queueTabs[section.id] = tab),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact ?? YorksMobileUi.isActive(context);
    final spec = widget.spec;
    final gap = compact ? AppSpacing.md : AppSpacing.lg;

    final children = compact
        ? _phoneChildren(spec, gap)
        : _desktopChildren(spec, gap);

    return ColoredBox(
      color: compact ? AppColors.mobileSurface : AppColors.surface,
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: SingleChildScrollView(
          key: const ValueKey('role-overview-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
            compact ? AppSpacing.lg : 22,
            compact ? AppSpacing.mobileScreenHorizontal : AppSpacing.xxl,
            compact ? AppSpacing.xxxl : 56,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _desktopChildren(YorksRoleOverviewSpec spec, double gap) => [
    _DesktopHeader(
      spec: spec,
      language: widget.language,
      updatedAt: widget.updatedAt,
      refreshing: widget.refreshing,
      onRefresh: widget.onRefresh,
    ),
    const SizedBox(height: AppSpacing.lg),
    LayoutBuilder(
      builder: (context, constraints) {
        final count = spec.kpis.length;
        var perRow = count == 6 ? 3 : count;
        if (constraints.maxWidth < 900) perRow = 2;
        return _KpiGrid(
          kpis: spec.kpis,
          perRow: perRow,
          gap: gap,
          selected: _selectedKpi,
          onSelect: _selectKpi,
          language: widget.language,
        );
      },
    ),
    SizedBox(height: gap),
    for (final section in spec.top) ...[
      _section(section, compact: false),
      SizedBox(height: gap),
    ],
    LayoutBuilder(
      builder: (context, constraints) {
        final left = [
          for (final section in spec.left) _section(section, compact: false),
        ];
        final right = [
          for (final section in spec.right) _section(section, compact: false),
        ];
        if (constraints.maxWidth < AppSpacing.stackedBreakpoint) {
          return _Stack(gap: gap, children: [...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 162,
              child: _Stack(gap: gap, children: left),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: 100,
              child: _Stack(gap: gap, children: right),
            ),
          ],
        );
      },
    ),
    for (final section in spec.full) ...[
      SizedBox(height: gap),
      _section(section, compact: false),
    ],
  ];

  List<Widget> _phoneChildren(YorksRoleOverviewSpec spec, double gap) {
    final byId = {for (final s in spec.allSections) s.id: s};
    final phoneKpis = [
      for (final index in spec.phoneKpis)
        if (index >= 0 && index < spec.kpis.length) spec.kpis[index],
    ];
    return [
      _PhoneHeader(
        spec: spec,
        language: widget.language,
        updatedAt: widget.updatedAt,
        refreshing: widget.refreshing,
      ),
      if (spec.actions.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _PhoneActions(actions: spec.actions),
      ],
      const SizedBox(height: AppSpacing.md),
      _KpiGrid(
        kpis: phoneKpis,
        perRow: 2,
        gap: AppSpacing.sm + 2,
        selected: _selectedKpi,
        onSelect: _selectKpi,
        language: widget.language,
        compact: true,
      ),
      for (final id in spec.phoneOrder)
        if (byId[id] != null) ...[
          SizedBox(height: gap),
          _section(byId[id]!, compact: true),
        ],
    ];
  }
}

class _Stack extends StatelessWidget {
  const _Stack({required this.gap, required this.children});

  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );
}

// ─── Header ───────────────────────────────────────────────────────────────

String _updatedLabel(AppLanguage language, DateTime? at, bool refreshing) {
  if (refreshing || at == null) return _S.checkingServer.active(language);
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return _S.updatedAt.active(language).replaceAll('{time}', '$hh:$mm');
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.spec,
    required this.language,
    required this.updatedAt,
    required this.refreshing,
    required this.onRefresh,
  });

  final YorksRoleOverviewSpec spec;
  final AppLanguage language;
  final DateTime? updatedAt;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spec.greeting,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              spec.title,
              key: const ValueKey('role-overview-title'),
              style: AppTypography.headlineMedium.copyWith(
                fontSize: 28,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            _RoleChip(label: spec.roleLabel),
          ],
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            spec.description,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.inkSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Chip(
              label: spec.scope,
              icon: Icons.visibility_outlined,
              emphasis: _ChipTone.blue,
            ),
            const _DotSeparator(),
            Text(
              _updatedLabel(language, updatedAt, refreshing),
              key: const ValueKey('role-overview-updated'),
              style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
            ),
            _GhostButton(
              icon: Icons.refresh_rounded,
              label: _S.refresh.active(language),
              onTap: refreshing ? null : onRefresh,
            ),
          ],
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final action in spec.actions) _ActionButton(action: action),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.lg),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.48,
              ),
              child: actions,
            ),
          ],
        );
      },
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({
    required this.spec,
    required this.language,
    required this.updatedAt,
    required this.refreshing,
  });

  final YorksRoleOverviewSpec spec;
  final AppLanguage language;
  final DateTime? updatedAt;
  final bool refreshing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        spec.greeting,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            spec.title,
            key: const ValueKey('role-overview-title'),
            style: AppTypography.headlineSmall.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          _RoleChip(label: spec.roleLabel),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        spec.description,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.inkSecondary,
          fontSize: 12.5,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _updatedLabel(language, updatedAt, refreshing),
            key: const ValueKey('role-overview-updated'),
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          const _DotSeparator(),
          Text(
            spec.scope,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    ],
  );
}

class _PhoneActions extends StatelessWidget {
  const _PhoneActions({required this.actions});

  final List<YorksOverviewAction> actions;

  @override
  Widget build(BuildContext context) {
    final first = actions.first;
    final rest = actions.skip(1).take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          action: YorksOverviewAction(
            icon: first.icon,
            label: first.label,
            onTap: first.onTap,
            primary: true,
          ),
          block: true,
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < rest.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: _ActionButton(action: rest[i], block: true)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      key: const ValueKey('role-overview-role-chip'),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.blue,
        fontWeight: FontWeight.w700,
        fontSize: 11,
      ),
    ),
  );
}

class _DotSeparator extends StatelessWidget {
  const _DotSeparator();

  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 3,
    decoration: const BoxDecoration(
      color: AppColors.mutedLight,
      shape: BoxShape.circle,
    ),
  );
}

enum _ChipTone { neutral, blue, ok, warn, bad, violet }

_ChipTone _chipTone(YorksOverviewEmphasis emphasis) => switch (emphasis) {
  YorksOverviewEmphasis.ok => _ChipTone.ok,
  YorksOverviewEmphasis.warn => _ChipTone.warn,
  YorksOverviewEmphasis.bad => _ChipTone.bad,
  YorksOverviewEmphasis.violet => _ChipTone.violet,
  YorksOverviewEmphasis.strong => _ChipTone.blue,
  YorksOverviewEmphasis.none => _ChipTone.neutral,
};

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.icon,
    this.emphasis = _ChipTone.neutral,
  });

  final String label;
  final IconData? icon;
  final _ChipTone emphasis;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (emphasis) {
      _ChipTone.neutral => (AppColors.neutralContainer, AppColors.neutralText),
      _ChipTone.blue => (AppColors.blueContainer, AppColors.blue),
      _ChipTone.ok => (AppColors.successContainer, AppColors.success),
      _ChipTone.warn => (AppColors.warningContainer, AppColors.warning),
      _ChipTone.bad => (AppColors.errorContainer, AppColors.error),
      _ChipTone.violet => (AppColors.purpleContainer, AppColors.purple),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, this.block = false});

  final YorksOverviewAction action;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    final fg = primary ? AppColors.onPrimary : AppColors.inkSecondary;
    final radius = primary ? AppSpacing.radiusFull : AppSpacing.radiusMd;
    return Semantics(
      button: true,
      enabled: action.onTap != null,
      child: Material(
        color: primary ? AppColors.navy : AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: primary ? AppColors.navy : AppColors.line),
        ),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: primary ? 18 : 14),
              child: Row(
                mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon, size: 17, color: fg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
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
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.blue,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      textStyle: AppTypography.labelMedium.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 6)],
        Text(label),
      ],
    ),
  );
}

// ─── KPI tiles ────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.kpis,
    required this.perRow,
    required this.gap,
    required this.selected,
    required this.onSelect,
    required this.language,
    this.compact = false,
  });

  final List<YorksOverviewKpi> kpis;
  final int perRow;
  final double gap;
  final String? selected;
  final ValueChanged<YorksOverviewKpi> onSelect;
  final AppLanguage language;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();
    final rows = <List<YorksOverviewKpi>>[];
    for (var i = 0; i < kpis.length; i += perRow) {
      rows.add(kpis.sublist(i, (i + perRow).clamp(0, kpis.length)));
    }
    return Column(
      key: const ValueKey('role-overview-metrics'),
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < perRow; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: i < rows[r].length
                        ? _KpiTile(
                            kpi: rows[r][i],
                            selected: selected == rows[r][i].id,
                            onTap: () => onSelect(rows[r][i]),
                            compact: compact,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({
    required this.icon,
    required this.tone,
    this.size = 42,
    this.iconSize = 20,
    this.radius = 11,
  });

  final IconData icon;
  final YorksOverviewTone tone;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tone.background,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(icon, size: iconSize, color: tone.foreground),
  );
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.kpi,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final YorksOverviewKpi kpi;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final loading = kpi.load == YorksOverviewLoad.loading;
    final interactive = kpi.onTap != null || kpi.targetSection != null;
    final valueStyle = AppTypography.headlineMedium.copyWith(
      fontSize: kpi.money ? (compact ? 16 : 19) : (compact ? 22 : 26),
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: kpi.emphasis.color(),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      button: interactive,
      label: '${kpi.label}: ${kpi.value}${kpi.valueSuffix ?? ''}',
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: selected ? AppColors.blue : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('role-overview-kpi-${kpi.id}'),
          onTap: interactive ? onTap : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 104 : 122),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: compact ? 12 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ToneIcon(
                        icon: kpi.icon,
                        tone: kpi.tone,
                        size: compact ? 30 : 34,
                        iconSize: compact ? 16 : 18,
                        radius: 9,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          kpi.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.inkSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 12 : 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: kpi.money ? 12 : 8),
                  if (loading)
                    const _Skeleton(height: 24, widthFactor: .45)
                  else
                    Text.rich(
                      TextSpan(
                        text: kpi.value,
                        children: [
                          if (kpi.valueSuffix != null)
                            TextSpan(
                              text: ' ${kpi.valueSuffix}',
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  const SizedBox(height: 4),
                  if (loading)
                    const _Skeleton(height: 10, widthFactor: .7)
                  else
                    Text(
                      kpi.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
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
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, this.widthFactor = 1});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}

// ─── Cards ────────────────────────────────────────────────────────────────

class _OverviewSectionCard extends StatelessWidget {
  const _OverviewSectionCard({
    required this.section,
    required this.language,
    required this.compact,
    required this.queueTab,
    required this.onQueueTab,
  });

  final YorksOverviewSection section;
  final AppLanguage language;
  final bool compact;
  final String? queueTab;
  final ValueChanged<String> onQueueTab;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final Widget body;
    if (s.load == YorksOverviewLoad.loading) {
      body = const _SkeletonRows(count: 3);
    } else if (s.load == YorksOverviewLoad.error) {
      body = _ErrorRow(language: language, onRetry: s.onRetry);
    } else {
      body = switch (s) {
        YorksOverviewQueueSection() => _QueueBody(
          section: s,
          language: language,
          compact: compact,
          tab: queueTab ?? 'all',
          onTab: onQueueTab,
        ),
        // A table in a narrow column reads better as cards than with
        // truncated headers.
        YorksOverviewTableSection() => LayoutBuilder(
          builder: (context, constraints) =>
              compact || constraints.maxWidth < 560
              ? _TableCards(section: s)
              : _TableBody(section: s),
        ),
        YorksOverviewPipelineSection() => _PipelineBody(section: s),
        YorksOverviewListSection() => _ListBody(section: s),
        YorksOverviewTrackSection() => _TrackBody(section: s),
        YorksOverviewMoneySection() => _MoneyBody(section: s),
        YorksOverviewToolsSection() => _ToolsBody(section: s),
      };
    }
    final total = s is YorksOverviewQueueSection && s.load.isReady
        ? (s.total ?? s.rows.length)
        : 0;
    return Container(
      key: ValueKey('role-overview-section-${s.id}'),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(section: s, count: total, compact: compact),
          body,
        ],
      ),
    );
  }
}

extension on YorksOverviewLoad {
  bool get isReady => this == YorksOverviewLoad.ready;
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.section,
    required this.count,
    required this.compact,
  });

  final YorksOverviewSection section;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 16, compact ? 10 : 18, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(section.icon, size: 21, color: AppColors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    section.title,
                    style: AppTypography.titleMedium.copyWith(
                      fontSize: 15.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (count > 0)
                    _Chip(label: '$count', emphasis: _ChipTone.blue),
                ],
              ),
              if (section.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  section.subtitle!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.inkSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (section.linkLabel != null && section.onLink != null) ...[
          const SizedBox(width: 8),
          _GhostButton(label: section.linkLabel!, onTap: section.onLink),
        ],
      ],
    ),
  );
}

const _rowBorder = BorderSide(color: AppColors.surfaceContainerHigh);

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('role-overview-loading'),
    children: [
      for (var i = 0; i < count; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(border: Border(top: _rowBorder)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Skeleton(height: 12, widthFactor: .62),
                    SizedBox(height: 7),
                    _Skeleton(height: 10, widthFactor: .4),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
    decoration: const BoxDecoration(border: Border(top: _rowBorder)),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 20, color: AppColors.error),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _S.couldNotLoad.active(language),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        if (onRetry != null)
          _GhostButton(label: _S.retry.active(language), onTap: onRetry),
      ],
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
    decoration: const BoxDecoration(border: Border(top: _rowBorder)),
    child: Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.muted,
        fontSize: 12.5,
      ),
    ),
  );
}

// Queue ---------------------------------------------------------------------

class _QueueBody extends StatefulWidget {
  const _QueueBody({
    required this.section,
    required this.language,
    required this.compact,
    required this.tab,
    required this.onTab,
  });

  final YorksOverviewQueueSection section;
  final AppLanguage language;
  final bool compact;
  final String tab;
  final ValueChanged<String> onTab;

  @override
  State<_QueueBody> createState() => _QueueBodyState();
}

class _QueueBodyState extends State<_QueueBody> {
  bool _showAll = false;

  @override
  void didUpdateWidget(covariant _QueueBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) _showAll = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final rows = s.rows;
    final tab = s.tabs.any((t) => t.key == widget.tab) ? widget.tab : 'all';
    final shown = tab == 'all'
        ? rows
        : rows.where((row) => row.tab == tab).toList(growable: false);
    final limit = widget.compact ? 4 : 8;
    final visible = _showAll ? shown : shown.take(limit).toList();
    final total = s.total ?? rows.length;
    final language = widget.language;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.tabs.isNotEmpty && rows.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 14 : 18,
              0,
              widget.compact ? 14 : 18,
              12,
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in s.tabs)
                  if (t.key == 'all' || rows.any((row) => row.tab == t.key))
                    _QueueTabChip(
                      label: t.label,
                      count: t.key == 'all'
                          ? rows.length
                          : rows.where((row) => row.tab == t.key).length,
                      selected: tab == t.key,
                      onTap: () => widget.onTab(t.key),
                    ),
              ],
            ),
          ),
        if (shown.isEmpty)
          _AllClear(title: s.clearTitle, body: s.clearBody)
        else ...[
          for (final row in visible)
            _QueueRow(row: row, compact: widget.compact, language: language),
          if (shown.length > limit && !_showAll)
            _MoreButton(
              label: _S.showAll
                  .active(language)
                  .replaceAll('{count}', '${shown.length}'),
              onTap: () => setState(() => _showAll = true),
            )
          else if (total > rows.length && s.onOpenAll != null)
            _MoreButton(
              label:
                  s.openAllLabel ??
                  _S.openAll.active(language).replaceAll('{count}', '$total'),
              onTap: s.onOpenAll!,
            ),
        ],
        if (s.footnote != null)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: const BoxDecoration(border: Border(top: _rowBorder)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.footnote!,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QueueTabChip extends StatelessWidget {
  const _QueueTabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.blue : AppColors.inkSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? AppColors.blueContainer
            : AppColors.surfaceContainerLowest,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.blueContainerStrong : AppColors.line,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTypography.labelSmall.copyWith(
                    color: selected ? AppColors.blue : AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
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

class _AllClear extends StatelessWidget {
  const _AllClear({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('role-overview-all-clear'),
    padding: const EdgeInsets.all(18),
    decoration: const BoxDecoration(border: Border(top: _rowBorder)),
    child: Row(
      children: [
        const _ToneIcon(
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.green,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLow,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: const BoxDecoration(border: Border(top: _rowBorder)),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.blue,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.row,
    required this.compact,
    required this.language,
  });

  final YorksOverviewQueueRow row;
  final bool compact;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              row.title,
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: AppColors.ink,
              ),
            ),
            if (row.reference != null) _Reference(text: row.reference!),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              row.meta,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
                fontSize: 12.5,
              ),
            ),
            if (row.tag != null)
              _Chip(label: row.tag!, emphasis: _chipTone(row.tagTone)),
          ],
        ),
        if (row.quote != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: const Border(
                left: BorderSide(color: AppColors.warning, width: 3),
              ),
            ),
            child: Text(
              row.quote!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
        if (row.byline != null) ...[
          const SizedBox(height: 2),
          Text(
            row.byline!,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
    final age = row.age == null
        ? const SizedBox(width: 0)
        : SizedBox(
            width: compact ? 52 : 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  row.age!,
                  style: AppTypography.labelLarge.copyWith(
                    color: row.ageEmphasis.color(),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _S.waiting.active(language),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
    final button = _RowButton(
      label: row.actionLabel,
      primary: row.primary,
      onTap: row.onTap,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: 12,
          ),
          decoration: const BoxDecoration(border: Border(top: _rowBorder)),
          child: Row(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              _ToneIcon(
                icon: row.icon,
                tone: row.tone,
                size: compact ? 36 : 40,
                iconSize: compact ? 17 : 19,
                radius: 10,
              ),
              SizedBox(width: compact ? 12 : 14),
              Expanded(
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [body, const SizedBox(height: 8), button],
                      )
                    : body,
              ),
              SizedBox(width: compact ? 8 : 14),
              age,
              if (!compact) ...[const SizedBox(width: 14), button],
            ],
          ),
        ),
      ),
    );
  }
}

class _Reference extends StatelessWidget {
  const _Reference({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w700,
      fontSize: 11.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = primary ? AppSpacing.radiusFull : 8.0;
    return Material(
      color: primary ? AppColors.blue : AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: primary ? AppColors.blue : AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: AppTypography.labelMedium.copyWith(
              color: primary ? AppColors.onPrimary : AppColors.inkSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

// Table ---------------------------------------------------------------------

class _TableBody extends StatelessWidget {
  const _TableBody({required this.section});

  final YorksOverviewTableSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    if (s.rows.isEmpty) return _EmptyRow(text: s.emptyText);
    Widget cellRow(List<Widget> cells, {VoidCallback? onTap, Color? color}) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: s.columns[i].flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: s.columns[i].numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: cells[i],
                  ),
                ),
              ),
          ],
        ),
      );
      return Material(
        color: color ?? Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.line),
            ),
          ),
          child: cellRow([
            for (final column in s.columns)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  column.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: .4,
                  ),
                ),
              ),
          ], color: AppColors.surfaceContainerLow),
        ),
        for (final row in s.rows)
          DecoratedBox(
            decoration: const BoxDecoration(border: Border(bottom: _rowBorder)),
            child: cellRow([
              for (var i = 0; i < row.cells.length; i++)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _CellView(
                      cell: row.cells[i],
                      numeric: s.columns[i].numeric,
                      first: i == 0,
                    ),
                  ),
                ),
            ], onTap: row.onTap),
          ),
      ],
    );
  }
}

class _CellView extends StatelessWidget {
  const _CellView({
    required this.cell,
    required this.numeric,
    required this.first,
  });

  final YorksOverviewCell cell;
  final bool numeric;
  final bool first;

  @override
  Widget build(BuildContext context) {
    if (cell.chip) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _Chip(label: cell.text, emphasis: _chipTone(cell.emphasis)),
      );
    }
    final style = AppTypography.bodySmall.copyWith(
      fontSize: first ? 13 : 12.5,
      color: cell.text == '0' && numeric
          ? AppColors.mutedLight
          : cell.emphasis.color(first ? AppColors.ink : AppColors.inkSecondary),
      fontWeight:
          first ||
              cell.emphasis == YorksOverviewEmphasis.strong ||
              cell.emphasis == YorksOverviewEmphasis.bad
          ? FontWeight.w700
          : FontWeight.w500,
      fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: numeric
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          cell.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        if (cell.subtitle != null)
          Text(
            cell.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _TableCards extends StatelessWidget {
  const _TableCards({required this.section});

  final YorksOverviewTableSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    if (s.rows.isEmpty) return _EmptyRow(text: s.emptyText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in s.rows)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: row.onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                decoration: const BoxDecoration(
                  border: Border(top: _rowBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CellView(
                      cell: row.cells.first,
                      numeric: false,
                      first: true,
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            for (final index in s.mobileColumns)
                              if (index < row.cells.length)
                                SizedBox(
                                  width: width,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.columns[index].label.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.labelSmall
                                            .copyWith(
                                              color: AppColors.muted,
                                              fontSize: 10.5,
                                              letterSpacing: .4,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      _CellView(
                                        cell: row.cells[index],
                                        numeric: false,
                                        first: false,
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Pipeline ------------------------------------------------------------------

class _PipelineBody extends StatelessWidget {
  const _PipelineBody({required this.section});

  final YorksOverviewPipelineSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final max = s.stages.fold<int>(1, (m, x) => x.count > m ? x.count : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stage in s.stages)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: stage.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.label,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.inkSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                          if (stage.hint != null)
                            Text(
                              stage.hint!,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 10,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: AppColors.surfaceContainerHighest,
                                ),
                              ),
                              Positioned.fill(
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: FractionallySizedBox(
                                    widthFactor: stage.count == 0
                                        ? 0.03
                                        : (stage.count / max).clamp(0.03, 1.0),
                                    heightFactor: 1,
                                    child: ColoredBox(
                                      color: stage.tone.foreground,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${stage.count}',
                        textAlign: TextAlign.right,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: stage.count == 0
                              ? AppColors.mutedLight
                              : AppColors.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (s.footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Text(
              s.footnote!,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          const SizedBox(height: 10),
      ],
    );
  }
}

// List ----------------------------------------------------------------------

class _ListBody extends StatelessWidget {
  const _ListBody({required this.section});

  final YorksOverviewListSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    if (s.items.isEmpty) return _EmptyRow(text: s.emptyText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in s.items.take(s.limit))
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: item.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: _rowBorder),
                ),
                child: Row(
                  children: [
                    _ToneIcon(
                      icon: item.icon,
                      tone: item.tone,
                      size: 36,
                      iconSize: 17,
                      radius: 10,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            item.detail,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.inkSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.trailing != null) ...[
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.trailing!,
                            style: AppTypography.labelMedium.copyWith(
                              color: item.trailingEmphasis.color(),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (item.trailingSub != null)
                            Text(
                              item.trailingSub!,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Track ---------------------------------------------------------------------

class _TrackBody extends StatelessWidget {
  const _TrackBody({required this.section});

  final YorksOverviewTrackSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    if (s.items.isEmpty) return _EmptyRow(text: s.emptyText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in s.items)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: item.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: _rowBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Reference(text: item.reference),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (item.age != null)
                          Text(
                            item.age!,
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      label: item.stageLabel,
                      child: Row(
                        children: [
                          for (var i = 1; i <= s.stageNames.length; i++) ...[
                            if (i > 1) const SizedBox(width: 4),
                            Expanded(
                              child: Tooltip(
                                message: s.stageNames[i - 1],
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: i < item.stage
                                        ? AppColors.blueContainerStrong
                                        : i == item.stage
                                        ? (item.warning
                                              ? AppColors.warning
                                              : AppColors.blue)
                                        : AppColors.surfaceContainerHighest,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: item.stageLabel,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: ' · ${item.owner}'),
                          if (item.note != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: item.note,
                              style: TextStyle(
                                color: item.noteEmphasis.color(
                                  AppColors.inkSecondary,
                                ),
                                fontWeight:
                                    item.noteEmphasis ==
                                        YorksOverviewEmphasis.none
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Money / key values --------------------------------------------------------

class _MoneyBody extends StatelessWidget {
  const _MoneyBody({required this.section});

  final YorksOverviewMoneySection section;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in section.rows)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: const BoxDecoration(border: Border(top: _rowBorder)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    if (row.hint != null)
                      Text(
                        row.hint!,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(
                row.value,
                style: AppTypography.labelLarge.copyWith(
                  color: row.emphasis.color(),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 6),
    ],
  );
}

// Tools ---------------------------------------------------------------------

class _ToolsBody extends StatelessWidget {
  const _ToolsBody({required this.section});

  final YorksOverviewToolsSection section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 320 ? 2 : 1;
        final width = (constraints.maxWidth - (perRow - 1) * 10) / perRow;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tool in section.tools)
              SizedBox(
                width: width,
                child: Material(
                  color: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.line),
                  ),
                  child: InkWell(
                    onTap: tool.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          _ToneIcon(
                            icon: tool.icon,
                            tone: YorksOverviewTone.blue,
                            size: 36,
                            iconSize: 18,
                            radius: 10,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tool.label,
                                  style: AppTypography.labelLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  tool.description,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

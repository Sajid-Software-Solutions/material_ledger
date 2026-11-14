import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_my_profile_workspace.dart';
import '../../../../shared/models/yorks_v1_profile_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';

/// The My Yorks tabs: the person's own record, their work, and settings.
enum YorksMyProfileSection { me, work, settings }

enum YorksMyProfileLayout { compact, medium, expanded }

enum YorksAccountEvidenceState { loading, verified, unavailable }

class YorksProfileSectionDefinition {
  const YorksProfileSectionDefinition({
    required this.section,
    required this.label,
    required this.icon,
  });

  final YorksMyProfileSection section;
  final String label;
  final IconData icon;
}

/// Resolves the profile presentation without changing its content model.
YorksMyProfileLayout yorksMyProfileLayoutFor(double width) {
  if (width <= AppSpacing.compactBreakpoint) {
    return YorksMyProfileLayout.compact;
  }
  if (width < AppSpacing.yorksV1DesktopBreakpoint) {
    return YorksMyProfileLayout.medium;
  }
  return YorksMyProfileLayout.expanded;
}

class YorksProfileSectionNavigation extends StatelessWidget {
  const YorksProfileSectionNavigation({
    super.key,
    required this.language,
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final AppLanguage language;
  final List<YorksProfileSectionDefinition> sections;
  final YorksMyProfileSection selected;
  final ValueChanged<YorksMyProfileSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: YorksV1ProfileStrings.sectionNavigation.active(language),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.line),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabs = [
              for (final definition in sections)
                _ProfileSectionTab(
                  definition: definition,
                  selected: selected == definition.section,
                  onPressed: () => onSelected(definition.section),
                ),
            ];
            // The tabs share the width when each still fits its label;
            // otherwise (large text) they scroll sideways.
            final fits =
                constraints.maxWidth / sections.length >=
                112 * MediaQuery.textScalerOf(context).scale(1);
            return FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: fits
                  ? Row(
                      children: [for (final tab in tabs) Expanded(child: tab)],
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: tabs),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileSectionTab extends StatelessWidget {
  const _ProfileSectionTab({
    required this.definition,
    required this.selected,
    required this.onPressed,
  });

  final YorksProfileSectionDefinition definition;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(112, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      foregroundColor: WidgetStatePropertyAll(
        selected ? AppColors.blue : AppColors.inkSecondary,
      ),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(AppColors.blueContainer),
      side: const WidgetStatePropertyAll(BorderSide(color: Colors.transparent)),
    );
    final key = ValueKey('my-yorks-section-${definition.section.name}');
    return Semantics(
      selected: selected,
      button: true,
      child: Container(
        decoration: BoxDecoration(
          border: selected
              ? const Border(
                  bottom: BorderSide(color: AppColors.blue, width: 3),
                )
              : null,
        ),
        child: selected
            ? FilledButton.tonalIcon(
                key: key,
                onPressed: onPressed,
                style: style,
                icon: Icon(definition.icon, size: 20),
                label: Text(definition.label),
              )
            : TextButton.icon(
                key: key,
                onPressed: onPressed,
                style: style,
                icon: Icon(definition.icon, size: 20),
                label: Text(definition.label),
              ),
      ),
    );
  }
}

class YorksIdentityHero extends StatelessWidget {
  const YorksIdentityHero({
    super.key,
    required this.language,
    required this.state,
    this.displayName,
    this.email,
    this.role,
    this.onRetry,
    this.compact = false,
    this.secondaryName,
    this.subtitle,
    this.detailLine,
    this.documentsLabel,
    this.documentsColor,
  });

  final AppLanguage language;
  final YorksAccountEvidenceState state;
  final String? displayName;

  /// Shown under the name; the header hides it when null.
  final String? email;
  final YorksV1Role? role;
  final VoidCallback? onRetry;
  final bool compact;

  /// From the People record once the account is linked: the Arabic name,
  /// the position in the company, the record number and company, and how
  /// the person's documents stand.
  final String? secondaryName;
  final String? subtitle;
  final String? detailLine;
  final String? documentsLabel;
  final Color? documentsColor;

  @override
  Widget build(BuildContext context) {
    final verified = state == YorksAccountEvidenceState.verified;
    final name = displayName?.trim();
    final safeName = name == null || name.isEmpty
        ? AppStrings.profile.active(language)
        : name;
    final roleLabel =
        subtitle ??
        (role == null ? null : YorksV1ProfileStrings.role(role!, language));
    final semantics = [
      YorksV1ProfileStrings.accountCardSemantic.active(language),
      if (verified) safeName,
      if (verified && secondaryName != null) secondaryName!,
      ?roleLabel,
      if (verified && detailLine != null) detailLine!,
      if (verified && email?.trim().isNotEmpty == true) email!.trim(),
      if (verified && documentsLabel != null) documentsLabel!,
    ].join(', ');

    return Semantics(
      container: true,
      label: semantics,
      child: Container(
        key: const ValueKey('my-yorks-identity-hero'),
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0D2F57),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = !compact && constraints.maxWidth >= 560;
            final title = verified
                ? safeName
                : state == YorksAccountEvidenceState.loading
                ? YorksV1ProfileStrings.verifyingAccount.active(language)
                : YorksV1ProfileStrings.accountUnavailable.active(language);
            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: compact ? 64 : 72,
                    height: compact ? 64 : 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .13),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .42),
                      ),
                    ),
                    child: Text(
                      verified ? _initials(safeName) : 'Y',
                      style: AppTypography.headlineMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (secondaryName != null && verified)
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Text(
                            secondaryName!,
                            key: const ValueKey('my-yorks-identity-arabic'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyLarge.copyWith(
                              color: const Color(0xFFBFD7F4),
                            ),
                          ),
                        ),
                      if (roleLabel != null && verified) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          roleLabel,
                          style: AppTypography.bodyLarge.copyWith(
                            color: const Color(0xFFD7E7F7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (detailLine != null && verified)
                        Text(
                          detailLine!,
                          key: const ValueKey('my-yorks-identity-record'),
                          style: AppTypography.bodySmall.copyWith(
                            color: const Color(0xFFBFD7F4),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide && verified && email?.trim().isNotEmpty == true)
                  Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: AppSpacing.xxl),
                      Container(
                        width: 1,
                        height: 56,
                        color: Colors.white.withValues(alpha: .16),
                      ),
                      const SizedBox(width: AppSpacing.xxl),
                      SizedBox(
                        width: 240,
                        child: _IdentityEmail(
                          language: language,
                          email: email!.trim(),
                        ),
                      ),
                    ],
                  )
                else ...[
                  identity,
                  if (verified && email?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _IdentityEmail(language: language, email: email!.trim()),
                  ],
                ],
                const SizedBox(height: AppSpacing.lg),
                if (verified)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _IdentityStatusPill(
                        icon: Icons.circle,
                        label: YorksV1ProfileStrings.active.active(language),
                        foreground: const Color(0xFF65E6B5),
                      ),
                      if (documentsLabel != null)
                        _IdentityStatusPill(
                          key: const ValueKey('my-yorks-identity-documents'),
                          icon: Icons.badge_outlined,
                          label: documentsLabel!,
                          foreground: documentsColor ?? Colors.white,
                        )
                      else
                        _IdentityStatusPill(
                          icon: Icons.verified_user_outlined,
                          label: YorksV1ProfileStrings.verifiedAccount.active(
                            language,
                          ),
                          foreground: Colors.white,
                        ),
                    ],
                  )
                else
                  YorksAccountStateBanner(
                    language: language,
                    state: state,
                    onRetry: onRetry,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IdentityEmail extends StatelessWidget {
  const _IdentityEmail({required this.language, required this.email});

  final AppLanguage language;
  final String email;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 22),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              YorksV1ProfileStrings.signedInEmail.active(language),
              style: AppTypography.labelSmall.copyWith(
                color: const Color(0xFFBFD7F4),
              ),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _IdentityStatusPill extends StatelessWidget {
  const _IdentityStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 36),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 12 : 18, color: foreground),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(color: foreground),
        ),
      ],
    ),
  );
}

class YorksAccountStateBanner extends StatelessWidget {
  const YorksAccountStateBanner({
    super.key,
    required this.language,
    required this.state,
    this.onRetry,
  });

  final AppLanguage language;
  final YorksAccountEvidenceState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, description, foreground, background) = switch (state) {
      YorksAccountEvidenceState.verified => (
        Icons.verified_user_outlined,
        YorksV1ProfileStrings.verifiedAccount.active(language),
        YorksV1ProfileStrings.verifiedByYorks.active(language),
        const Color(0xFFDAF7EC),
        Colors.white.withValues(alpha: .10),
      ),
      YorksAccountEvidenceState.loading => (
        Icons.sync_rounded,
        YorksV1ProfileStrings.verifyingAccount.active(language),
        YorksV1ProfileStrings.verifyingAccountDescription.active(language),
        const Color(0xFFD7E7F7),
        Colors.white.withValues(alpha: .08),
      ),
      YorksAccountEvidenceState.unavailable => (
        Icons.error_outline_rounded,
        YorksV1ProfileStrings.accountUnavailable.active(language),
        YorksV1ProfileStrings.accountUnavailableDescription.active(language),
        const Color(0xFFFFDEDE),
        const Color(0x33C23737),
      ),
    };
    return Semantics(
      liveRegion: state != YorksAccountEvidenceState.verified,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: foreground.withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground, size: 21),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.titleSmall.copyWith(
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
                        style: AppTypography.bodySmall.copyWith(
                          color: foreground.withValues(alpha: .90),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (state == YorksAccountEvidenceState.loading) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFFD7E7F7),
                backgroundColor: Color(0x33FFFFFF),
              ),
            ],
            if (state == YorksAccountEvidenceState.unavailable &&
                onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x99FFFFFF)),
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(YorksV1ProfileStrings.tryAgain.active(language)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class YorksProfileSectionCard extends StatelessWidget {
  const YorksProfileSectionCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.children,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final showDescription = MediaQuery.sizeOf(context).width > 720;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: AppSpacing.ambientBlur,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, color: AppColors.blue, size: 19),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: AppTypography.titleMedium),
                      ),
                      if (showDescription) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          description,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(
                height: 1,
                indent: 62,
                endIndent: AppSpacing.lg,
                color: AppColors.line,
              ),
          ],
        ],
      ),
    );
  }
}

/// A server-confirmed operational signal. It intentionally accepts a plain
/// value rather than deriving a total from client state, so a loading/error
/// profile can never be rendered as a misleading zero.
class YorksRoleMetricCard extends StatelessWidget {
  const YorksRoleMetricCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.icon,
  });

  final String title;
  final String description;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title: $value. $description',
      child: Container(
        constraints: const BoxConstraints(minHeight: 108),
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
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, size: 19, color: AppColors.blue),
                ),
                const Spacer(),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '$value',
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class YorksProfileQuickAction {
  const YorksProfileQuickAction({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Responsive, keyboard-accessible navigation only. Every item has already
/// been confirmed by P01 and still passes ordinary route/RPC guards after tap.
class YorksQuickActionGrid extends StatelessWidget {
  const YorksQuickActionGrid({
    super.key,
    required this.actions,
    required this.compact,
  });

  final List<YorksProfileQuickAction> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns = compact || textScale >= 1.6
            ? 1
            : constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    label: action.title,
                    value: action.description,
                    child: Material(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: InkWell(
                        key: ValueKey('my-yorks-action-${action.id}'),
                        onTap: action.onPressed,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                        focusColor: AppColors.blueContainer,
                        hoverColor: AppColors.blueContainer,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AppSpacing.minTapTarget,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.blueContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd,
                                    ),
                                  ),
                                  child: Icon(
                                    action.icon,
                                    color: AppColors.blue,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        action.title,
                                        style: AppTypography.titleSmall,
                                      ),
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        action.description,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.inkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 19,
                                  color: AppColors.inkSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A concise, read-only explanation of the currently effective server scope.
class YorksAccessSummaryCard extends StatelessWidget {
  const YorksAccessSummaryCard({
    super.key,
    required this.language,
    required this.scope,
    required this.verifiedAt,
  });

  final AppLanguage language;
  final YorksV1MyProfileAccessScope scope;
  final DateTime verifiedAt;

  @override
  Widget build(BuildContext context) {
    return YorksProfileSectionCard(
      title: YorksV1ProfileStrings.accessAndScope.active(language),
      description: YorksV1ProfileStrings.accessAndScopeDescription.active(
        language,
      ),
      icon: Icons.shield_outlined,
      children: [
        YorksScopeList(
          language: language,
          scope: scope,
          verifiedAt: verifiedAt,
        ),
      ],
    );
  }
}

class YorksScopeList extends StatelessWidget {
  const YorksScopeList({
    super.key,
    required this.language,
    required this.scope,
    required this.verifiedAt,
  });

  final AppLanguage language;
  final YorksV1MyProfileAccessScope scope;
  final DateTime verifiedAt;

  @override
  Widget build(BuildContext context) {
    final facts = <(IconData, String, int)>[
      (
        Icons.account_tree_outlined,
        YorksV1ProfileStrings.technicalProjectScope.active(language),
        scope.technicalProjectCount,
      ),
      (
        Icons.people_outline_rounded,
        YorksV1ProfileStrings.directMembershipScope.active(language),
        scope.activeDirectMembershipCount,
      ),
      if (scope.accountsPortfolioAvailable)
        (
          Icons.account_balance_outlined,
          YorksV1ProfileStrings.accountsProjectScope.active(language),
          scope.accountsProjectCount,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < facts.length; index++) ...[
            _ScopeFactRow(
              icon: facts[index].$1,
              label: facts[index].$2,
              value: facts[index].$3,
            ),
            if (index != facts.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppColors.line),
              ),
          ],
          if (scope.effectiveSourceKinds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              YorksV1ProfileStrings.accessSource.active(language),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final source in scope.effectiveSourceKinds)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.blueContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Text(
                      YorksV1ProfileStrings.sourceKind(source, language),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.blue,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      YorksV1ProfileStrings.serverConfirmed.active(language),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    Text(
                      '${YorksV1ProfileStrings.lastVerified.active(language)}: '
                      '${MaterialLocalizations.of(context).formatShortDate(verifiedAt.toLocal())} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(verifiedAt.toLocal()))}',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class YorksWorkIdentityCard extends StatelessWidget {
  const YorksWorkIdentityCard({
    super.key,
    required this.language,
    required this.worker,
  });

  final AppLanguage language;
  final YorksV1MyProfileWorkerIdentity worker;

  @override
  Widget build(BuildContext context) {
    if (!worker.isLinked) {
      return YorksProfileSectionCard(
        title: YorksV1ProfileStrings.workIdentity.active(language),
        description: YorksV1ProfileStrings.workIdentityDescription.active(
          language,
        ),
        icon: Icons.badge_outlined,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _IdentityNotice(
              icon: Icons.link_off_rounded,
              title: YorksV1ProfileStrings.workerNotLinked.active(language),
              description: YorksV1ProfileStrings.workerNotLinkedDescription
                  .active(language),
            ),
          ),
        ],
      );
    }
    return YorksProfileSectionCard(
      title: YorksV1ProfileStrings.workIdentity.active(language),
      description: YorksV1ProfileStrings.workIdentityDescription.active(
        language,
      ),
      icon: Icons.badge_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IdentityNotice(
                icon: Icons.link_rounded,
                title: YorksV1ProfileStrings.workerLinked.active(language),
                description: YorksV1ProfileStrings.workerLinkedDescription
                    .active(language),
              ),
              const SizedBox(height: AppSpacing.lg),
              YorksProfileFactRow(
                label: YorksV1ProfileStrings.workRecordName.active(language),
                value: worker.displayName!,
              ),
              YorksProfileFactRow(
                label: YorksV1ProfileStrings.workerNumber.active(language),
                value: worker.workerNumber!,
                forceLtr: true,
              ),
              YorksProfileFactRow(
                label: YorksV1ProfileStrings.designation.active(language),
                value: worker.designation!,
              ),
              if (worker.department != null)
                YorksProfileFactRow(
                  label: YorksV1ProfileStrings.department.active(language),
                  value: worker.department!,
                ),
              YorksProfileFactRow(
                label: YorksV1ProfileStrings.workCategory.active(language),
                value: YorksV1ProfileStrings.workerType(
                  worker.workerType!,
                  language,
                ),
              ),
              YorksProfileFactRow(
                label: YorksV1ProfileStrings.workStatus.active(language),
                value: YorksV1ProfileStrings.workerStatus(
                  worker.currentStatus!,
                  language,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopeFactRow extends StatelessWidget {
  const _ScopeFactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.inkSecondary, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTypography.bodyMedium)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '$value',
            style: AppTypography.titleSmall.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}

class _IdentityNotice extends StatelessWidget {
  const _IdentityNotice({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.blue, size: 21),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
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
}

class YorksProfileFactRow extends StatelessWidget {
  const YorksProfileFactRow({
    super.key,
    required this.label,
    required this.value,
    this.forceLtr = false,
  });

  final String label;
  final String value;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Directionality(
              textDirection: forceLtr
                  ? TextDirection.ltr
                  : Directionality.of(context),
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class YorksPreferenceRow extends StatelessWidget {
  const YorksPreferenceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onPressed,
    this.value,
    this.valueTextDirection,
    this.trailing,
    this.destructive = false,
    this.toggled,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPressed;
  final String? value;
  final TextDirection? valueTextDirection;
  final Widget? trailing;
  final bool destructive;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.inkSecondary;
    final semanticValue = [
      if (value?.isNotEmpty == true) value!,
      description,
    ].join('. ');
    return Semantics(
      button: onPressed != null,
      enabled: onPressed != null,
      toggled: toggled,
      label: title,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            focusColor: AppColors.blueContainer,
            hoverColor: AppColors.surfaceContainerLow,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.titleSmall.copyWith(
                              color: destructive ? AppColors.error : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            description,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (value?.isNotEmpty == true)
                      Flexible(
                        child: Text(
                          value!,
                          textDirection: valueTextDirection,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppTypography.bodyMedium.copyWith(
                            color: destructive
                                ? AppColors.error
                                : AppColors.blue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (value?.isNotEmpty == true)
                      const SizedBox(width: AppSpacing.xs),
                    trailing ??
                        Icon(
                          onPressed == null
                              ? Icons.lock_outline_rounded
                              : Directionality.of(context) == TextDirection.rtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: onPressed == null ? 18 : 24,
                          color: destructive
                              ? AppColors.error
                              : AppColors.muted,
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Y';
  if (parts.length == 1) {
    final word = parts.single;
    return String.fromCharCodes(word.runes.take(2)).toUpperCase();
  }
  return String.fromCharCodes([
    parts.first.runes.first,
    parts.last.runes.first,
  ]).toUpperCase();
}

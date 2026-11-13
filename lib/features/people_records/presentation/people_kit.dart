/// People — shared pieces in the Material Request style: status colours,
/// pills, expiry cells, metric cards, surfaces, dates and error copy.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/models/yorks_v1_people_strings.dart';

typedef PS = PeopleStrings;

const peoplePath = '/yorks/people';
const peopleNewPath = '/yorks/people/new';
String peoplePersonPath(String id) => '/yorks/people/$id';
String peopleEditPath(String id) => '/yorks/people/$id/edit';

String peopleKindLabel(
  PeopleDocumentKind kind,
  AppLanguage language, {
  String? label,
}) => switch (kind) {
  PeopleDocumentKind.visa => PS.t(PS.kindVisa, language),
  PeopleDocumentKind.passport => PS.t(PS.kindPassport, language),
  PeopleDocumentKind.labourCard => PS.t(PS.kindLabourCard, language),
  PeopleDocumentKind.iloe => PS.t(PS.kindIloe, language),
  PeopleDocumentKind.emiratesId => PS.t(PS.kindEmiratesId, language),
  PeopleDocumentKind.cicpaPass => PS.t(PS.kindCicpa, language),
  PeopleDocumentKind.cmwPass => PS.t(PS.kindCmw, language),
  PeopleDocumentKind.other => label ?? PS.t(PS.kindOther, language),
};

IconData peopleKindIcon(PeopleDocumentKind kind) => switch (kind) {
  PeopleDocumentKind.visa => Icons.badge_outlined,
  PeopleDocumentKind.passport => Icons.menu_book_outlined,
  PeopleDocumentKind.labourCard => Icons.work_outline_rounded,
  PeopleDocumentKind.iloe => Icons.health_and_safety_outlined,
  PeopleDocumentKind.emiratesId => Icons.credit_card_outlined,
  PeopleDocumentKind.cicpaPass => Icons.verified_user_outlined,
  PeopleDocumentKind.cmwPass => Icons.confirmation_number_outlined,
  PeopleDocumentKind.other => Icons.description_outlined,
};

String peopleCategoryLabel(PeopleCategory category, AppLanguage language) =>
    PS.t(category == PeopleCategory.staff ? PS.staff : PS.labour, language);

({Color color, Color background}) peopleStatusColors(
  PeopleDocumentStatus status,
) => switch (status) {
  PeopleDocumentStatus.expired => (
    color: AppColors.error,
    background: AppColors.errorContainer,
  ),
  PeopleDocumentStatus.expiring => (
    color: AppColors.warning,
    background: AppColors.warningContainer,
  ),
  PeopleDocumentStatus.ok => (
    color: AppColors.success,
    background: AppColors.successContainer,
  ),
  PeopleDocumentStatus.noExpiry => (
    color: AppColors.neutralText,
    background: AppColors.neutralContainer,
  ),
};

String peopleStatusLabel(PeopleDocumentStatus status, AppLanguage language) =>
    PS.t(switch (status) {
      PeopleDocumentStatus.expired => PS.statusExpired,
      PeopleDocumentStatus.expiring => PS.statusExpiring,
      PeopleDocumentStatus.ok => PS.statusOk,
      PeopleDocumentStatus.noExpiry => PS.noExpiry,
    }, language);

/// `2027-01-31` → `31 Jan 2027`.
String peopleDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final date = DateTime.tryParse(iso);
  return date == null ? iso : DateFormat('d MMM yyyy').format(date);
}

String peopleStamp(DateTime? at) =>
    at == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(at.toLocal());

/// "12 days left", "Expired 3 days ago", "Expires today" or "No expiry".
String peopleDaysText(PeopleDocument document, AppLanguage language) {
  final days = document.daysLeft;
  if (days == null) return PS.t(PS.noExpiry, language);
  if (days == 0) return PS.t(PS.expiresToday, language);
  if (days < 0) return PS.t(PS.expiredAgo, language, {'n': -days});
  return PS.t(PS.daysLeft, language, {'n': days});
}

String peopleErrorText(Object? error, AppLanguage language) {
  if (error is YorksV1DomainException) {
    return PS.t(switch (error.code) {
      YorksV1DomainErrorCode.offline => PS.errOffline,
      YorksV1DomainErrorCode.unauthorized ||
      YorksV1DomainErrorCode.unauthenticated => PS.errDenied,
      YorksV1DomainErrorCode.conflict => PS.errConflict,
      YorksV1DomainErrorCode.invalidInput => PS.errInvalid,
      _ => PS.errGeneric,
    }, language);
  }
  return PS.t(PS.errGeneric, language);
}

/// A small rounded label.
class PeoplePill extends StatelessWidget {
  const PeoplePill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.blue,
    this.background = AppColors.blueContainer,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class PeopleStatusPill extends StatelessWidget {
  const PeopleStatusPill({
    super.key,
    required this.status,
    required this.language,
  });

  final PeopleDocumentStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final colors = peopleStatusColors(status);
    return PeoplePill(
      label: peopleStatusLabel(status, language),
      color: colors.color,
      background: colors.background,
    );
  }
}

/// An expiry date coloured by how soon it ends, or a dash.
class PeopleExpiryCell extends StatelessWidget {
  const PeopleExpiryCell({
    super.key,
    required this.document,
    required this.language,
    this.dense = false,
  });

  final PeopleDocument? document;
  final AppLanguage language;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    if (doc == null) {
      return Text(
        '—',
        style: AppTypography.bodySmall.copyWith(color: AppColors.mutedLight),
      );
    }
    final colors = peopleStatusColors(doc.status);
    final text = doc.expiryDate == null
        ? (doc.number == null ? PS.t(PS.noExpiry, language) : doc.number!)
        : peopleDate(doc.expiryDate);
    return Tooltip(
      message: [
        peopleKindLabel(doc.kind, language, label: doc.label),
        if (doc.number != null) doc.number!,
        peopleDaysText(doc, language),
      ].join(' · '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (dense ? AppTypography.labelMedium : AppTypography.bodySmall)
                      .copyWith(
                        color: doc.status.needsAttention
                            ? colors.color
                            : AppColors.ink,
                        fontWeight: doc.status.needsAttention
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Material Request record surface: white, outlined, softly raised.
class PeopleSurface extends StatelessWidget {
  const PeopleSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

/// A record section heading: title and one line of description.
class PeopleSectionHeading extends StatelessWidget {
  const PeopleSectionHeading({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// The Material Request metric tile.
class PeopleMetricCard extends StatelessWidget {
  const PeopleMetricCard({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final int value;
  final IconData icon;
  final Color foreground;
  final Color background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(icon, color: foreground, size: 21),
    );
    final number = Text(
      '$value',
      style: AppTypography.headlineSmall.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
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
            color: selected ? foreground : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: InkWell(
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
                      Row(children: [iconBox, const Spacer(), number]),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    iconBox,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          number,
                          Text(
                            hint,
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
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A centred icon, message and optional action: empty and error states.
class PeopleMessage extends StatelessWidget {
  const PeopleMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xxl,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: AppColors.mutedLight),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
        if (action != null && onPressed != null) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onPressed, child: Text(action!)),
        ],
      ],
    ),
  );
}

/// One label/value fact, label above.
class PeopleFact extends StatelessWidget {
  const PeopleFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value.isEmpty ? '—' : value,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

void peopleToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

/// Crew requests — building blocks in the Material Request style (the same
/// cards, step indicator, numbered sections, readiness rows and register
/// cards as Company Material Requests), so the two flows look and behave
/// alike on desktop and phone.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/crew_request_models.dart';
import 'crew_request_common.dart';

/// The bordered, softly shadowed card used by Material Requests.
class CrCard extends StatelessWidget {
  const CrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
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
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

/// 1 — 2 — 3 step indicator.
class CrStepIndicator extends StatelessWidget {
  const CrStepIndicator({
    super.key,
    required this.labels,
    required this.active,
  });

  final List<String> labels;
  final int active;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${active + 1} / ${labels.length}',
    child: Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (index > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index <= active
                              ? AppColors.blue
                              : AppColors.lineStrong,
                        ),
                      ),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index <= active
                            ? AppColors.blue
                            : AppColors.surfaceContainerLowest,
                        border: Border.all(
                          color: index <= active
                              ? AppColors.blue
                              : AppColors.lineStrong,
                        ),
                      ),
                      child: index < active
                          ? const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            )
                          : Text(
                              '${index + 1}',
                              style: AppTypography.labelMedium.copyWith(
                                color: index == active
                                    ? Colors.white
                                    : AppColors.muted,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    if (index < labels.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index < active
                              ? AppColors.blue
                              : AppColors.lineStrong,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  labels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: index == active ? AppColors.blue : AppColors.muted,
                    fontWeight: index == active
                        ? FontWeight.w900
                        : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A numbered desktop section: "1  Request information".
class CrSection extends StatelessWidget {
  const CrSection({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    required this.child,
  });

  final String number;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => CrCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.blueContainer,
                child: Text(
                  number,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
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
        ),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: child),
      ],
    ),
  );
}

class CrReadiness extends StatelessWidget {
  const CrReadiness({
    super.key,
    required this.label,
    required this.ready,
    required this.language,
  });

  final String label;
  final bool ready;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 19,
          color: ready ? AppColors.success : AppColors.muted,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTypography.bodySmall)),
        Text(
          CRS.t(ready ? CRS.ready : CRS.required, language),
          style: AppTypography.labelSmall.copyWith(
            color: ready ? AppColors.success : AppColors.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class CrFact extends StatelessWidget {
  const CrFact({
    super.key,
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.bodyMedium),
      ],
    ),
  );
}

class CrPill extends StatelessWidget {
  const CrPill({
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Stage of the request on its four-step track: Requested, Approval,
/// Assigning workers, Done.
int crewRequestStage(CrewRequestState state) => switch (state) {
  CrewRequestState.submitted || CrewRequestState.returned => 1,
  CrewRequestState.approved || CrewRequestState.partiallyFulfilled => 2,
  CrewRequestState.fulfilled ||
  CrewRequestState.closed ||
  CrewRequestState.rejected ||
  CrewRequestState.cancelled => 3,
};

/// The state as Material Requests colour it.
({Color color, Color background}) crewRequestStateColors(
  CrewRequestState state,
) => switch (state) {
  CrewRequestState.submitted => (
    color: AppColors.warning,
    background: AppColors.warningContainer,
  ),
  CrewRequestState.returned || CrewRequestState.rejected => (
    color: AppColors.error,
    background: AppColors.errorContainer,
  ),
  CrewRequestState.approved => (
    color: AppColors.blue,
    background: AppColors.blueContainer,
  ),
  CrewRequestState.partiallyFulfilled => (
    color: AppColors.purple,
    background: AppColors.purpleContainer,
  ),
  CrewRequestState.fulfilled => (
    color: AppColors.success,
    background: AppColors.successContainer,
  ),
  CrewRequestState.closed || CrewRequestState.cancelled => (
    color: AppColors.neutralText,
    background: AppColors.neutralContainer,
  ),
};

class CrStatePill extends StatelessWidget {
  const CrStatePill({super.key, required this.request, required this.language});

  final CrewRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final colors = crewRequestStateColors(request.state);
    return CrPill(
      label: crewRequestStateChip(request.state, language).text,
      color: colors.color,
      background: colors.background,
    );
  }
}

/// A register card: number and state, what is asked, where, and who has it.
class CrewRequestCard extends StatelessWidget {
  const CrewRequestCard({
    super.key,
    required this.request,
    required this.language,
    required this.onOpen,
  });

  final CrewRequest request;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('crew-request-card-${request.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.groups_outlined, color: AppColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        request.number,
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.blue,
                        ),
                      ),
                      Text(
                        crewRequestStateChip(request.state, language).text,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                      if (request.overdue)
                        Text(
                          CRS.t(CRS.neededNow, language),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    crewRequestPeople(request),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${crewRequestWhere(request, language)} · ${crewRequestDates(request, language)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${crewRequestOwnerLabel(request, language)} · ${crewRequestNextStep(request, language)}',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: request.access.mine
                          ? AppColors.blue
                          : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

/// An empty or error message in the register style.
class CrMessage extends StatelessWidget {
  const CrMessage({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.onPressed,
  });

  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
          if (action != null && onPressed != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onPressed, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

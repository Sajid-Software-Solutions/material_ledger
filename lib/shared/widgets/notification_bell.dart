import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/constants/constants.dart';
import '../models/app_notification.dart';
import '../models/app_strings.dart';
import '../models/notification_experience_strings.dart';
import '../providers/yorks_v1_notification_provider.dart';
import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import 'notification_delivery_card.dart';

/// Universal notification entry point. Phones open the full-screen center;
/// tablet and desktop show a compact recent-alert panel first.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.foregroundColor});

  /// Feature chrome may supply its contrast color without changing delivery,
  /// unread state or the shared notification centre.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return Semantics(
      button: true,
      label: AppStrings.notifications.active(ref.watch(languageProvider)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: AppStrings.notifications.active(
              ref.watch(languageProvider),
            ),
            onPressed: () => _open(context),
            icon: const Icon(Icons.notifications_outlined),
            style: IconButton.styleFrom(
              foregroundColor: foregroundColor ?? AppColors.primary,
            ),
          ),
          if (unread > 0)
            Positioned(
              top: 3,
              right: 2,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onPrimary,
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (MediaQuery.sizeOf(context).width <= 720) {
      context.push(RoutePaths.notifications);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .12),
      builder: (_) => const _NotificationPreviewPanel(),
    );
  }
}

class _NotificationPreviewPanel extends ConsumerWidget {
  const _NotificationPreviewPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final notifications = ref.watch(visibleNotificationsProvider);
    final server = ref.watch(yorksV1NotificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final recent = notifications.take(6).toList(growable: false);
    return Dialog(
      alignment: AlignmentDirectional.topEnd,
      insetPadding: const EdgeInsets.only(top: 68, right: 24, left: 24),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.recentNotifications.active(language),
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (unread > 0)
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(notificationActionsProvider)
                              .markAllRead();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  NotificationExperienceStrings.readFailed
                                      .active(language),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: Text(AppStrings.markAllRead.active(language)),
                    ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const NotificationDeliveryCard(compact: true),
              if (server.hasError && recent.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      ref.read(yorksV1NotificationsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    NotificationExperienceStrings.stale.active(language),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 38,
                        color: AppColors.mutedLight,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        (server.hasError
                                ? AppStrings.couldNotLoadNotifications
                                : server.isLoading
                                ? AppStrings.checkingAlertDelivery
                                : AppStrings.allCaughtUp)
                            .active(language),
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _PreviewRow(notification: recent[index]),
                  ),
                ),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(RoutePaths.notifications);
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(AppStrings.viewAllNotifications.active(language)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends ConsumerWidget {
  const _PreviewRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notification.isRead;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () {
        final router = GoRouter.of(context);
        final actions = ref.read(notificationActionsProvider);
        Navigator.pop(context);
        unawaited(
          actions
              .open(notification, navigate: (location) => router.push(location))
              .catchError((Object _) {}),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unread
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_rounded,
                size: 20,
                color: unread ? AppColors.blue : AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                notification.relativeTimeFor(ref.watch(languageProvider)),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

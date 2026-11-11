import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/constants/constants.dart';
import '../../core/widgets/widgets.dart';
import '../models/app_notification.dart';
import '../models/app_strings.dart';
import '../models/material_request.dart';
import '../providers/language_provider.dart';
import '../providers/material_request_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/session_provider.dart';

/// Shared engineer ↔ procurement discussion thread for a single request. Used on
/// both the engineer's request detail and procurement's dispatch screen — each
/// side posts as its own role and the other side is notified (deep-linked).
class RequestCommentsSection extends ConsumerStatefulWidget {
  const RequestCommentsSection({
    super.key,
    required this.requestId,
    required this.authorRole,
    required this.notifyAudience,
    required this.notifyRoute,
  });

  /// 'Engineer' or 'Procurement' — stamped on the comment.
  final String authorRole;

  /// Role that should be alerted when this side posts (the other party).
  final String notifyAudience;

  /// Where the alert deep-links the recipient (their view of this request).
  final String notifyRoute;

  final String requestId;

  @override
  ConsumerState<RequestCommentsSection> createState() =>
      _RequestCommentsSectionState();
}

class _RequestCommentsSectionState
    extends ConsumerState<RequestCommentsSection> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(MaterialRequest req) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await ref
        .read(materialRequestsProvider.notifier)
        .addRequestComment(
          req.id,
          text: text,
          authorName: ref.read(actorNameProvider),
          authorRole: widget.authorRole,
        );
    final lang = ref.read(languageProvider);
    await ref
        .read(notificationsProvider.notifier)
        .add(
          type: NotificationType.request,
          title: AppStrings.notifNewRequestComment.primary,
          titleSecondary: AppStrings.notifNewRequestComment.secondary(lang),
          body: '${req.projectName} · "$text"',
          refId: req.id,
          route: widget.notifyRoute,
          audience: widget.notifyAudience,
        );
    _controller.clear();
    if (!mounted) return;
    setState(() => _sending = false);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final req = ref
        .watch(materialRequestsProvider)
        .where((r) => r.id == widget.requestId)
        .firstOrNull;
    if (req == null) return const SizedBox.shrink();
    final comments = req.comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.comments.primary,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        const Gap(AppSpacing.sm),
        if (comments.isEmpty) ...[
          Text(
            AppStrings.noCommentsYet.primary,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const Gap(AppSpacing.sm),
        ],
        for (final c in comments) ...[
          _CommentBubble(comment: c),
          const Gap(AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: LedgerTextField(
                controller: _controller,
                label: AppStrings.addComment.primary,
              ),
            ),
            const Gap(AppSpacing.sm),
            IconButton.filled(
              onPressed: _sending ? null : () => _send(req),
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment});
  final RequestComment comment;

  @override
  Widget build(BuildContext context) {
    return LedgerCard(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${comment.authorName} · ${comment.authorRole}',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(AppSpacing.xxs),
          Text(comment.text, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

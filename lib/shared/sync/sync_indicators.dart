import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import 'connectivity_service.dart';
import 'sync_engine.dart';

/// A small inline pill shown on a list row while that record still has a write
/// waiting to reach the server. Amber = queued/syncing, red = needs attention.
/// Renders nothing once the record is fully committed, so synced rows stay clean.
class PendingSyncBadge extends ConsumerWidget {
  const PendingSyncBadge(this.docId, {super.key, this.compact = false});

  /// Client-generated document id of the record this row represents.
  final String docId;

  /// When true, shows just the icon (for dense rows).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordSyncStateProvider(docId));
    if (state == RecordSyncState.none) return const SizedBox.shrink();

    final failed = state == RecordSyncState.failed;
    final fg = failed
        ? AppColors.onErrorContainer
        : AppColors.onWarningContainer;
    final bg = failed ? AppColors.errorContainer : AppColors.warningContainer;
    final icon = failed
        ? Icons.sync_problem_rounded
        : Icons.cloud_upload_rounded;
    final label = failed ? 'Sync failed' : 'Pending sync';

    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(label: label, child: pill);
  }
}

/// Shows a connectivity-honest SnackBar after a critical write. The work is
/// always durably saved locally and queued; the wording never claims the server
/// has it when we are offline (FR — never show "success" until confirmed).
void showSyncSnack(
  BuildContext context,
  WidgetRef ref, {
  required String savedLabel,
}) {
  if (!context.mounted) return;
  final online = ref.read(isOnlineProvider);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: online
          ? AppColors.onSurface
          : AppColors.onWarningContainer,
      content: Row(
        children: [
          Icon(
            online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online
                  ? '$savedLabel — syncing'
                  : '$savedLabel offline — will sync when back online',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

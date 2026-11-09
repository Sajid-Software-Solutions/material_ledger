import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/constants.dart';
import '../models/app_language.dart';
import '../models/yorks_v1_command_outcome.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_material_request_strings.dart';
import '../models/yorks_v1_procurement_progress_strings.dart';
import '../providers/yorks_v1_material_workflow_command_provider.dart';

/// Manual, read-only recovery remains available after automatic checks stop.
/// This uses existing command leases and never submits a replacement command.
class YorksV1MaterialWorkflowRecoveryPanel extends ConsumerStatefulWidget {
  const YorksV1MaterialWorkflowRecoveryPanel({
    super.key,
    required this.requestId,
    required this.language,
    required this.onConfirmed,
    this.arrangementIds = const [],
    this.dispatchIds = const [],
    this.includeRequestDecisions = true,
  });

  final String requestId;
  final AppLanguage language;
  final VoidCallback onConfirmed;
  final List<String> arrangementIds;
  final List<String> dispatchIds;
  final bool includeRequestDecisions;

  @override
  ConsumerState<YorksV1MaterialWorkflowRecoveryPanel> createState() =>
      _YorksV1MaterialWorkflowRecoveryPanelState();
}

class _YorksV1MaterialWorkflowRecoveryPanelState
    extends ConsumerState<YorksV1MaterialWorkflowRecoveryPanel> {
  bool _checking = false;
  String? _failure;

  @override
  Widget build(BuildContext context) {
    var sending = false;
    for (final id in {
      widget.requestId,
      ...widget.arrangementIds,
      ...widget.dispatchIds,
    }) {
      final phase = ref.watch(yorksV1CommandPhaseProvider(id));
      sending =
          sending ||
          phase == YorksV1CommandPhase.inFlight ||
          phase == YorksV1CommandPhase.checking;
    }
    final controller = ref.watch(
      yorksV1MaterialWorkflowCommandControllerProvider,
    );
    final pending = controller
        .pendingCommandsForRequest(
          widget.requestId,
          arrangementIds: widget.arrangementIds,
          dispatchIds: widget.dispatchIds,
        )
        .where(
          (command) =>
              widget.includeRequestDecisions ||
              !command.operation.startsWith('decide_material_request_'),
        )
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    final busy = _checking || sending;
    return Container(
      key: const ValueKey('material-command-recovery'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.blueContainer,
        border: Border.all(color: AppColors.blueContainerStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _failure ??
                      (busy
                              ? YorksV1ProcurementProgressStrings.checkingResult
                              : YorksV1MaterialRequestStrings.commandUnknown)
                          .active(widget.language),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            key: const ValueKey('material-command-check-status'),
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      _checking = true;
                      _failure = null;
                    });
                    var confirmed = false;
                    try {
                      for (final command in pending) {
                        try {
                          final receipt = await controller.checkCommandStatus(
                            command,
                          );
                          confirmed = confirmed || receipt != null;
                        } on YorksV1CommandOutcomeUnknown {
                          // Keep the original key and the manual action available.
                        }
                      }
                    } on YorksV1DomainException catch (error) {
                      if (mounted) {
                        _failure = YorksV1MaterialRequestStrings.commandFailure(
                          error.code,
                        ).active(widget.language);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _checking = false);
                        if (confirmed) widget.onConfirmed();
                      }
                    }
                  },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              YorksV1ProcurementProgressStrings.checkStatus.active(
                widget.language,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

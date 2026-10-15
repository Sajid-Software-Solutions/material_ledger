import 'package:flutter/material.dart';

import '../../core/constants/constants.dart';
import '../controllers/yorks_v1_procurement_progress_controller.dart';
import '../models/app_language.dart';
import '../models/yorks_v1_procurement_progress.dart';
import '../models/yorks_v1_procurement_progress_strings.dart';

/// One recovery/status surface for desktop and compact editors. Its actions
/// affect private progress only; final command replay belongs to the caller.
class YorksV1ProcurementProgressPanel extends StatelessWidget {
  const YorksV1ProcurementProgressPanel({
    super.key,
    required this.controller,
    required this.language,
    this.onRetryPending,
    this.onSaveProgress,
    this.onReload,
    this.onConfirmed,
    this.onCommandAbandoned,
  });
  final YorksV1ProcurementProgressController controller;
  final AppLanguage language;
  final Future<void> Function()? onRetryPending;
  final Future<void> Function()? onSaveProgress;
  final VoidCallback? onReload;
  final VoidCallback? onConfirmed;
  final Future<void> Function(YorksV1ProcurementPendingCommand command)?
  onCommandAbandoned;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final strings = YorksV1ProcurementProgressStrings.saveProgress;
      if (state.current == null) return const SizedBox.shrink();
      final actions = <Widget>[];
      String message;
      IconData icon;
      var attention = false;
      var commandInformation = false;
      var commandConfirmed = false;
      if (state.isLoading) {
        message = YorksV1ProcurementProgressStrings.checkingResult.active(
          language,
        );
        icon = Icons.sync;
      } else if (state.outcome?.isConfirmed == true || state.isRetired) {
        commandConfirmed = true;
        final reference =
            state.outcome?.effectReference ?? state.outcome?.effectId;
        message =
            (state.commandPhase ==
                        YorksV1ProcurementCommandPhase.viewRefreshDegraded
                    ? YorksV1ProcurementProgressStrings.confirmedRefreshDegraded
                    : state.current?.editorKind ==
                              YorksV1ProcurementEditorKind.dispatch &&
                          reference != null
                    ? YorksV1ProcurementProgressStrings.confirmedDispatch(
                        reference,
                      )
                    : YorksV1ProcurementProgressStrings.confirmedResult)
                .active(language);
        icon = Icons.check_circle_outline;
      } else if (state.isPending) {
        commandInformation = true;
        message =
            (state.commandPhase == YorksV1ProcurementCommandPhase.inFlight
                    ? YorksV1ProcurementProgressStrings.sendingCommand
                    : state.isChecking || state.isRecovering
                    ? state.current?.editorKind ==
                              YorksV1ProcurementEditorKind.dispatch
                          ? YorksV1ProcurementProgressStrings.checkingDispatch
                          : YorksV1ProcurementProgressStrings.checkingResult
                    : YorksV1ProcurementProgressStrings.uncertainResult)
                .active(language);
        icon = state.isChecking || state.isRecovering
            ? Icons.sync
            : Icons.info_outline;
        actions.add(
          TextButton.icon(
            onPressed:
                state.isChecking ||
                    state.isRecovering ||
                    state.commandPhase ==
                        YorksV1ProcurementCommandPhase.inFlight
                ? null
                : () async {
                    final result = await controller.checkCommandStatus();
                    if (result?.isConfirmed == true) onConfirmed?.call();
                  },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              YorksV1ProcurementProgressStrings.checkStatus.active(language),
            ),
          ),
        );
        if (controller.pendingCommandPayload != null &&
            onRetryPending != null &&
            !state.isChecking &&
            !state.isRecovering &&
            state.commandPhase != YorksV1ProcurementCommandPhase.inFlight) {
          actions.add(
            TextButton(
              onPressed: onRetryPending,
              child: Text(
                YorksV1ProcurementProgressStrings.retrySame.active(language),
              ),
            ),
          );
        }
        if (state.outcome?.status == 'prepared' ||
            state.outcome?.status == 'not_found' ||
            state.outcome?.status == 'abandoned') {
          actions.add(
            TextButton(
              onPressed: state.isChecking || state.isRecovering
                  ? null
                  : () async {
                      final command = controller.state.pendingCommand;
                      final unlocked = await controller
                          .resumeEditingAfterCheck();
                      if (unlocked && command != null) {
                        await onCommandAbandoned?.call(command);
                      }
                      if (!unlocked &&
                          controller.state.outcome?.isConfirmed == true) {
                        onConfirmed?.call();
                      }
                    },
              child: Text(
                YorksV1ProcurementProgressStrings.editAgain.active(language),
              ),
            ),
          );
        }
      } else if (state.hasVersionConflict) {
        attention = true;
        message = YorksV1ProcurementProgressStrings.staleProgress.active(
          language,
        );
        icon = Icons.compare_arrows;
        if (onReload != null) {
          actions.add(
            TextButton(
              onPressed: state.isSaving
                  ? null
                  : () async {
                      if (!await _confirmDiscard(context, language)) return;
                      if (await controller.discardSavedProgress()) {
                        onReload?.call();
                      }
                    },
              child: Text(
                YorksV1ProcurementProgressStrings.discardProgress.active(
                  language,
                ),
              ),
            ),
          );
        }
      } else if (state.needsRecoveryChoice) {
        attention = true;
        message = YorksV1ProcurementProgressStrings.chooseRecovery.active(
          language,
        );
        icon = Icons.restore;
        actions.add(
          TextButton(
            onPressed: controller.acceptDeviceRecovery,
            child: Text(
              YorksV1ProcurementProgressStrings.useDeviceCopy.active(language),
            ),
          ),
        );
        actions.add(
          TextButton(
            onPressed: controller.useAccountProgress,
            child: Text(
              YorksV1ProcurementProgressStrings.useAccountCopy.active(language),
            ),
          ),
        );
      } else if (state.recoveryCorrupt) {
        attention = true;
        message = YorksV1ProcurementProgressStrings.corruptRecovery.active(
          language,
        );
        icon = Icons.info_outline;
      } else if (state.error != null || state.recoveryError != null) {
        attention = true;
        message = YorksV1ProcurementProgressStrings.saveFailed.active(language);
        icon = Icons.error_outline;
        actions.add(
          TextButton(
            onPressed: state.isSaving ? null : controller.saveProgress,
            child: Text(strings.active(language)),
          ),
        );
      } else {
        message =
            (state.isSaving
                    ? YorksV1ProcurementProgressStrings.saving
                    : !state.isDirty && state.checkpoint != null
                    ? YorksV1ProcurementProgressStrings.accountSaved
                    : state.deviceSaved
                    ? YorksV1ProcurementProgressStrings.deviceSaved
                    : YorksV1ProcurementProgressStrings.unsaved)
                .active(language);
        icon = state.isSaving
            ? Icons.sync
            : state.isDirty
            ? Icons.edit_outlined
            : Icons.check_circle_outline;
      }
      if (onSaveProgress != null &&
          state.canEdit &&
          state.error == null &&
          state.recoveryError == null) {
        actions.add(
          TextButton.icon(
            onPressed: state.isSaving ? null : onSaveProgress,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(strings.active(language)),
          ),
        );
      }
      return Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: commandConfirmed
                ? AppColors.successContainer
                : commandInformation
                ? AppColors.primaryContainer
                : attention
                ? Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: .25)
                : AppColors.surfaceContainerLowest,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (state.hasUnsavedCommercialChanges)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    YorksV1ProcurementProgressStrings.costsNotSaved.active(
                      language,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (actions.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool> _confirmDiscard(
  BuildContext context,
  AppLanguage language,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          YorksV1ProcurementProgressStrings.discardProgress.active(language),
        ),
        content: Text(
          YorksV1ProcurementProgressStrings.staleProgress.active(language),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              YorksV1ProcurementProgressStrings.keepEditing.active(language),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              YorksV1ProcurementProgressStrings.discardProgress.active(
                language,
              ),
            ),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmYorksV1ProcurementLeave(
  BuildContext context, {
  required YorksV1ProcurementProgressController controller,
  required AppLanguage language,
  bool isOnline = true,
}) async {
  final state = controller.state;
  if (state.isSaving || state.isLoading || state.isChecking) return false;
  if (state.isPending) {
    // The prepared server intent remains recoverable. Leaving does not retry or
    // discard it; the next visit checks its original result before editing.
    await controller.flushRecovery();
    return true;
  }
  if (!state.isDirty && !state.needsRecoveryChoice) return true;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(
        YorksV1ProcurementProgressStrings.beforeLeaving.active(language),
      ),
      content: Text(
        [
          YorksV1ProcurementProgressStrings.noStockChange.active(language),
          if (state.hasUnsavedCommercialChanges)
            YorksV1ProcurementProgressStrings.costsNotSaved.active(language),
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'keep'),
          child: Text(
            YorksV1ProcurementProgressStrings.keepEditing.active(language),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: Text(
            YorksV1ProcurementProgressStrings.discardChanges.active(language),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, isOnline ? 'save' : 'device'),
          child: Text(
            (isOnline
                    ? YorksV1ProcurementProgressStrings.saveAndReturn
                    : YorksV1ProcurementProgressStrings.deviceOnlyExit)
                .active(language),
          ),
        ),
      ],
    ),
  );
  switch (choice) {
    case 'save':
      return controller.saveProgress();
    case 'device':
      return controller.flushRecovery();
    case 'discard':
      await controller.discardChanges();
      return true;
    default:
      return false;
  }
}

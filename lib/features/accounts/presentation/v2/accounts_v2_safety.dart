/// R39 Accounts Workspace V2 — ways back from a mistake.
///
/// * [showAccountsV2Undo]: a short message with Undo after a change made with
///   one click (removing a row, filling or clearing many fields, discarding).
/// * [AccountsV2SubmitDialog]: a command dialog stays open while the server
///   decides. A refusal is shown inside the dialog with everything typed still
///   there, instead of closing first and losing it.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import 'accounts_v2_common.dart';
import 'kit/accounts_v2_kit.dart';

/// Shows [message] with an Undo button for a few seconds. Only the latest
/// change can be undone; a newer message replaces the older one.
void showAccountsV2Undo(
  BuildContext context, {
  required AppLanguage language,
  required String message,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        persist: false,
        action: SnackBarAction(
          label: accountsV2Text(language, 'v2_undo'),
          onPressed: onUndo,
        ),
      ),
    );
}

/// Shows [message] briefly (no action).
void showAccountsV2Message(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A command the dialog runs before it closes: null on success, else the
/// failure code the controllers return.
typedef AccountsV2DialogCommand<T> = Future<String?> Function(T input);

/// For a dialog that collects an input and runs a server command with it.
///
/// [submit] keeps the dialog open, disables both buttons and Escape while the
/// command runs, closes with the input once the server confirms, and otherwise
/// shows the reason in [submitError] with every field as the person left it.
/// Without a command the dialog closes with the input as before.
mixin AccountsV2SubmitDialog<W extends StatefulWidget> on State<W> {
  bool submitting = false;
  String? submitError;

  AppLanguage get submitLanguage;

  Future<void> submit<T>(T input, AccountsV2DialogCommand<T>? command) async {
    if (submitting) return;
    if (command == null) {
      Navigator.of(context).pop(input);
      return;
    }
    setState(() {
      submitting = true;
      submitError = null;
    });
    String? error;
    try {
      error = await command(input);
    } catch (_) {
      error = 'action_failed';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(input);
      return;
    }
    setState(() {
      submitting = false;
      submitError = accountsV2ErrorText(submitLanguage, error);
    });
  }

  /// Clears a shown refusal once the person changes something.
  void clearSubmitError() {
    if (submitError != null) setState(() => submitError = null);
  }

  /// The refusal, for the end of the dialog's content.
  Widget submitErrorLine() {
    final error = submitError;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline,
                size: 18,
                color: AccountsV2Colors.bad,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                key: const ValueKey('accounts-v2-dialog-error'),
                style: v2Style(13, color: AccountsV2Colors.bad),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cancel and the confirm button, disabled while the command runs.
  List<Widget> submitActions({
    required String confirmLabel,
    required VoidCallback? onConfirm,
    String? cancelLabel,
  }) => [
    TextButton(
      onPressed: submitting ? null : () => Navigator.of(context).pop(),
      child: Text(cancelLabel ?? accountsV2Text(submitLanguage, 'v2_cancel')),
    ),
    FilledButton(
      key: const ValueKey('accounts-v2-dialog-confirm'),
      onPressed: submitting ? null : onConfirm,
      child: submitting
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(accountsV2Text(submitLanguage, 'v2c_saving')),
              ],
            )
          : Text(confirmLabel),
    ),
  ];

  /// The dialog itself: [content] with the refusal under it, and a dialog
  /// that can't be closed (Escape, back, a tap outside) mid-command.
  Widget submitDialog({
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) => PopScope(
    canPop: !submitting,
    child: AlertDialog(
      title: title,
      // A long refusal wraps instead of widening the dialog.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: content),
            submitErrorLine(),
          ],
        ),
      ),
      actions: actions,
    ),
  );
}

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
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_receivables_inputs.dart' show YorksAccountsDate;
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
  ///
  /// When [onConfirm] is null because something is missing, [blockedReason]
  /// keeps the button pressable: pressing it says what to fix, in the dialog,
  /// instead of a greyed-out button that never explains itself.
  /// [destructive] colours the button red for an action that removes or ends
  /// something.
  List<Widget> submitActions({
    required String confirmLabel,
    required VoidCallback? onConfirm,
    String? cancelLabel,
    String? blockedReason,
    bool destructive = false,
  }) {
    final VoidCallback? press =
        onConfirm ??
        (blockedReason == null
            ? null
            : () => setState(() => submitError = blockedReason));
    return [
      TextButton(
        onPressed: submitting ? null : () => Navigator.of(context).pop(),
        child: Text(cancelLabel ?? accountsV2Text(submitLanguage, 'v2_cancel')),
      ),
      FilledButton(
        key: const ValueKey('accounts-v2-dialog-confirm'),
        style: destructive
            ? FilledButton.styleFrom(
                backgroundColor: AccountsV2Colors.bad,
                foregroundColor: Colors.white,
              )
            : null,
        onPressed: submitting ? null : press,
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
  }

  /// A line at the top of a dialog naming what it acts on (invoice, amount).
  Widget submitSummary(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      key: const ValueKey('accounts-v2-dialog-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AccountsV2Colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AccountsV2Colors.line),
      ),
      child: Text(text, style: v2Style(13, weight: FontWeight.w600)),
    ),
  );

  /// The dialog itself: [content] with the refusal under it, and a dialog
  /// that can't be closed (Escape, back, a tap outside) mid-command.
  Widget submitDialog({
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) => PopScope(
    canPop: !submitting,
    child: AccountsV2AlertDialog(
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

// ─── What a blocked dialog is missing ────────────────────────────────────────

/// One requirement of a dialog: whether it is met, and what to say if not.
typedef AccountsV2Check = (bool ok, String message);

/// The first unmet requirement's message, or null when all are met.
String? accountsV2FirstBlocker(List<AccountsV2Check> checks) {
  for (final (ok, message) in checks) {
    if (!ok) return message;
  }
  return null;
}

String _named(AppLanguage language, String key, String field) =>
    accountsV2Text(language, key).replaceAll('{field}', field);

/// [field] must not be empty.
AccountsV2Check accountsV2NeedText(
  AppLanguage language,
  TextEditingController controller,
  String field,
) => (
  controller.text.trim().isNotEmpty,
  _named(language, 'v2b_need_text', field),
);

/// [field] must be an amount above zero (or zero and above when [allowZero]),
/// with at most two decimals.
AccountsV2Check accountsV2NeedAmount(
  AppLanguage language,
  TextEditingController controller,
  String field, {
  bool allowZero = false,
}) {
  final value = YorksAccountsDecimal.tryParse(controller.text.trim());
  final ok =
      value != null &&
      (allowZero ? !value.isNegative : value.isPositive) &&
      value.fractionDigits <= 2;
  return (ok, _named(language, 'v2b_need_amount', field));
}

/// [field] must be a date.
AccountsV2Check accountsV2NeedDate(
  AppLanguage language,
  TextEditingController controller,
  String field,
) => (
  YorksAccountsDate.tryParse(controller.text.trim()) != null,
  _named(language, 'v2b_need_date', field),
);

// ─── One look for every Accounts dialog ──────────────────────────────────────

/// An [AlertDialog] drawn like the rest of the Accounts workspace: a white
/// card with the workspace's radius, title type, field borders and buttons,
/// so a dialog and the side drawer read as one design.
class AccountsV2AlertDialog extends StatelessWidget {
  const AccountsV2AlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final radius = BorderRadius.circular(10);
    const pri = AccountsV2Colors.pri;
    final buttonText = v2Style(13, weight: FontWeight.w700);
    const minSize = Size(44, 40);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(primary: pri),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          border: OutlineInputBorder(borderRadius: radius),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: const BorderSide(color: AccountsV2Colors.lineS),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: const BorderSide(color: pri, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: pri,
            foregroundColor: Colors.white,
            minimumSize: minSize,
            textStyle: buttonText,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AccountsV2Colors.ink2,
            minimumSize: minSize,
            textStyle: buttonText,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: const BorderSide(color: AccountsV2Colors.lineS),
            ),
          ),
        ),
      ),
      child: AlertDialog(
        // Phones: nearly the full width, so fields and two buttons fit.
        insetPadding: MediaQuery.sizeOf(context).width <= 640
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 24)
            : null,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: v2Style(17, weight: FontWeight.w700),
        contentTextStyle: v2Style(13.5, color: AccountsV2Colors.ink2),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}

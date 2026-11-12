/// Workforce attendance V2 — dialogs that wait for the server, and Undo.
///
/// Same rules as the Accounts workspace: a command dialog stays open while
/// the server decides; a refusal is shown inside it with everything typed
/// still there; it cannot be closed mid-command; one-tap changes to many rows
/// offer Undo.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/accounts_v2_safety.dart'
    show AccountsV2AlertDialog;
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import 'attendance_common.dart';

/// Runs on Confirm with the typed text ('' when there is no field). Returns
/// null when the server confirmed, or the failure to show in the dialog.
typedef AttendanceDialogCommand = Future<Object?> Function(String text);

/// Opens a command dialog. Resolves to the text once the command succeeds
/// (or immediately, without a command), and to null when cancelled.
Future<String?> showAttendanceCommandDialog(
  BuildContext context, {
  required AppLanguage language,
  required String title,
  required String confirmLabel,
  String? summary,
  String? body,
  String? fieldLabel,
  bool destructive = false,
  AttendanceDialogCommand? command,
}) => showDialog<String>(
  context: context,
  builder: (_) => _AttendanceCommandDialog(
    language: language,
    title: title,
    confirmLabel: confirmLabel,
    summary: summary,
    body: body,
    fieldLabel: fieldLabel,
    destructive: destructive,
    command: command,
  ),
);

class _AttendanceCommandDialog extends StatefulWidget {
  const _AttendanceCommandDialog({
    required this.language,
    required this.title,
    required this.confirmLabel,
    this.summary,
    this.body,
    this.fieldLabel,
    this.destructive = false,
    this.command,
  });

  final AppLanguage language;
  final String title;
  final String confirmLabel;
  final String? summary;
  final String? body;
  final String? fieldLabel;
  final bool destructive;
  final AttendanceDialogCommand? command;

  @override
  State<_AttendanceCommandDialog> createState() =>
      _AttendanceCommandDialogState();
}

class _AttendanceCommandDialogState extends State<_AttendanceCommandDialog> {
  final _text = TextEditingController();
  bool _running = false;
  String? _error;

  AppLanguage get _language => widget.language;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final text = _text.text.trim();
    if (widget.fieldLabel != null && text.isEmpty) {
      setState(
        () =>
            _error = AS.t(AS.needText, _language, {'field': widget.fieldLabel}),
      );
      return;
    }
    final command = widget.command;
    if (command == null) {
      Navigator.of(context).pop(text);
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    Object? failure;
    try {
      failure = await command(text);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(text);
      return;
    }
    setState(() {
      _running = false;
      _error = attendanceErrorText(failure, _language);
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    return PopScope(
      canPop: !_running,
      child: AccountsV2AlertDialog(
        title: Text(widget.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.summary != null)
                Container(
                  key: const ValueKey('attendance-dialog-summary'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AccountsV2Colors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AccountsV2Colors.line),
                  ),
                  child: Text(
                    widget.summary!,
                    style: v2Style(13, weight: FontWeight.w600),
                  ),
                ),
              if (widget.body != null)
                Text(
                  widget.body!,
                  style: v2Style(13, color: AccountsV2Colors.ink2),
                ),
              if (widget.fieldLabel != null) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('attendance-text-dialog-field'),
                  controller: _text,
                  enabled: !_running,
                  autofocus: true,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _confirm(),
                  decoration: InputDecoration(
                    labelText: widget.fieldLabel,
                    counterText: '',
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: AccountsV2Colors.bad,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            key: const ValueKey('attendance-dialog-error'),
                            style: v2Style(13, color: AccountsV2Colors.bad),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _running ? null : () => Navigator.of(context).pop(),
            child: Text(AS.t(AS.cancel, language)),
          ),
          FilledButton(
            key: const ValueKey('attendance-text-dialog-confirm'),
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AccountsV2Colors.bad,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: _running ? null : _confirm,
            child: _running
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(AS.t(AS.saving, language)),
                    ],
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

/// A short message with Undo after a one-tap change to many rows.
void showAttendanceUndo(
  BuildContext context, {
  required AppLanguage language,
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        persist: false,
        // Floats above the Save bar so Save stays reachable meanwhile.
        behavior: SnackBarBehavior.floating,
        margin: attendanceSnackMargin(context),
        action: SnackBarAction(
          key: const ValueKey('attendance-undo'),
          label: AS.t(AS.undo, language),
          onPressed: onUndo,
        ),
      ),
    );
}

/// R39 Accounts Workspace V2 — Export Excel / Save PDF / Print buttons.
///
/// The prototype's report buttons, wired to the existing protected Accounts
/// reports: the server builds each register for the signed-in person, so a file
/// never holds a figure that person cannot see on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../../shared/models/app_language.dart';
import '../../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../application/accounts_records_providers.dart';
import '../../../data/accounts_report_service.dart';
import '../../../domain/accounts_records_models.dart';
import 'accounts_v2_kit.dart';

/// Which file the button produces.
enum AccountsV2ReportOutput { excel, pdf, print }

/// One report button. [kind] is the main register; [companions] add sheets.
class AccountsV2ReportButton extends ConsumerStatefulWidget {
  const AccountsV2ReportButton({
    super.key,
    required this.projectId,
    required this.kind,
    required this.output,
    required this.language,
    this.companions = const [],
    this.icon,
  });

  final String projectId;
  final YorksAccountsReportKind kind;
  final List<YorksAccountsReportKind> companions;
  final AccountsV2ReportOutput output;
  final AppLanguage language;

  /// Overrides the default icon (the Overview uses a download arrow).
  final String? icon;

  @override
  ConsumerState<AccountsV2ReportButton> createState() =>
      _AccountsV2ReportButtonState();
}

class _AccountsV2ReportButtonState
    extends ConsumerState<AccountsV2ReportButton> {
  bool _busy = false;

  String _t(String key) => YorksV1AccountsStrings.text(widget.language, key);

  void _say(String key) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(_t(key))));
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repository = ref.read(yorksAccountsRecordsRepositoryProvider);
    final service = ref.read(yorksAccountsReportServiceProvider);
    final files = ref.read(yorksV1DocumentFileServiceProvider);
    try {
      final kinds = <YorksAccountsReportKind>[
        widget.kind,
        for (final k in widget.companions)
          if (k != widget.kind) k,
      ];
      final reports = await Future.wait([
        for (final kind in kinds)
          repository.getReport(
            kind,
            projectId: widget.projectId,
            idempotencyKey: const Uuid().v4(),
          ),
      ]);
      final report = reports.first;
      final companions = reports.skip(1).toList(growable: false);
      switch (widget.output) {
        case AccountsV2ReportOutput.excel:
          final saved = await files.saveDocument(
            bytes: service.buildExcel(report, companionReports: companions),
            fileName: service.excelFileName(report),
            mimeType: YorksAccountsReportService.xlsxMimeType,
          );
          if (mounted) _say(saved ? 'report_saved' : 'document_cancelled');
        case AccountsV2ReportOutput.pdf:
          final saved = await files.saveDocument(
            bytes: await service.buildPdf(report, companionReports: companions),
            fileName: service.pdfFileName(report),
            mimeType: YorksAccountsReportService.pdfMimeType,
          );
          if (mounted) _say(saved ? 'report_saved' : 'document_cancelled');
        case AccountsV2ReportOutput.print:
          await service.printPdf(report, companionReports: companions);
      }
    } catch (_) {
      if (mounted) _say('report_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (widget.output) {
      AccountsV2ReportOutput.excel => ('sheet', 'export_excel'),
      AccountsV2ReportOutput.pdf => ('pdf', 'save_pdf'),
      AccountsV2ReportOutput.print => ('print', 'print'),
    };
    return AccountsV2Button(
      label: _t(label),
      icon: _busy ? 'clock' : (widget.icon ?? icon),
      onPressed: _busy ? null : _run,
    );
  }
}

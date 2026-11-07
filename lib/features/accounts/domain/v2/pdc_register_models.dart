/// R39 Accounts Workspace V2 — project cheque (PDC) register models (P8).
///
/// Typed parse of `v1_list_project_client_pdcs`: one row per client post-dated
/// cheque for a project, joined to its invoice reference, with the current
/// lifecycle status and the `record_version` the transition command needs.
///
/// The read is gated behind `view_project_commercial_values`, so the whole
/// register is simply absent for an actor without that capability (the read
/// throws). Amounts therefore always arrive here and parse through
/// [YorksAccountsDecimal], which rejects JSON numbers so a binary double can
/// never become a commercial value.
library;

import '../accounts_decimal.dart';
import '../accounts_receivables_inputs.dart'
    show YorksAccountsDate, YorksAccountsPdcStatus;
import '../accounts_receivables_models.dart' show YorksAccountsPdcStatusParser;

/// One cheque in the project register.
final class YorksAccountsProjectPdc {
  const YorksAccountsProjectPdc({
    required this.pdcId,
    required this.invoiceId,
    required this.invoiceReference,
    required this.chequeNumber,
    required this.chequeDate,
    required this.receivedDate,
    required this.bankName,
    required this.amount,
    required this.status,
    required this.actionRequired,
    required this.recordVersion,
  });

  final String pdcId;
  final String invoiceId;
  final String invoiceReference;
  final String chequeNumber;
  final YorksAccountsDate chequeDate;
  final YorksAccountsDate? receivedDate;
  final String? bankName;
  final YorksAccountsDecimal amount;
  final YorksAccountsPdcStatus status;
  final bool actionRequired;
  final int recordVersion;

  factory YorksAccountsProjectPdc.fromJson(Map<String, dynamic> json) {
    final status = YorksAccountsPdcStatusParser.tryParse(json['status']);
    if (status == null) {
      throw FormatException('Invalid PDC status.', json['status']);
    }
    final receivedRaw = json['received_date'];
    final bankRaw = json['bank_name'];
    return YorksAccountsProjectPdc(
      pdcId: json['pdc_id'] as String,
      invoiceId: json['invoice_id'] as String,
      invoiceReference: json['invoice_reference'] as String,
      chequeNumber: json['cheque_number'] as String,
      chequeDate: YorksAccountsDate.parse(json['cheque_date'] as String),
      receivedDate: receivedRaw is String
          ? YorksAccountsDate.parse(receivedRaw)
          : null,
      bankName: bankRaw is String && bankRaw.trim().isNotEmpty ? bankRaw : null,
      amount: YorksAccountsDecimal.fromRpcValue(json['amount'], key: 'amount'),
      status: status,
      actionRequired: json['action_required'] == true,
      recordVersion: (json['record_version'] as num).toInt(),
    );
  }

  /// Transitions the server accepts from the cheque's current state, in the
  /// order the register offers them. Every state can be walked back except a
  /// replaced cheque, which its replacement stands in for.
  List<YorksAccountsPdcStatus> get nextStatuses {
    switch (status) {
      case YorksAccountsPdcStatus.expected:
        return const [
          YorksAccountsPdcStatus.received,
          YorksAccountsPdcStatus.cancelled,
        ];
      case YorksAccountsPdcStatus.received:
        return const [
          YorksAccountsPdcStatus.deposited,
          YorksAccountsPdcStatus.returned,
          YorksAccountsPdcStatus.bounced,
          YorksAccountsPdcStatus.cancelled,
          YorksAccountsPdcStatus.expected,
        ];
      case YorksAccountsPdcStatus.deposited:
        return const [
          YorksAccountsPdcStatus.cleared,
          YorksAccountsPdcStatus.returned,
          YorksAccountsPdcStatus.bounced,
          YorksAccountsPdcStatus.received,
        ];
      case YorksAccountsPdcStatus.cleared:
        return const [
          YorksAccountsPdcStatus.deposited,
          YorksAccountsPdcStatus.bounced,
          YorksAccountsPdcStatus.returned,
        ];
      case YorksAccountsPdcStatus.returned:
      case YorksAccountsPdcStatus.bounced:
        return const [
          YorksAccountsPdcStatus.received,
          YorksAccountsPdcStatus.cancelled,
        ];
      case YorksAccountsPdcStatus.cancelled:
        return const [YorksAccountsPdcStatus.expected];
      case YorksAccountsPdcStatus.replaced:
        return const [];
    }
  }

  /// Whether moving to [target] walks a step back. The server wants a reason.
  bool isBackwardMove(YorksAccountsPdcStatus target) =>
      status == YorksAccountsPdcStatus.cleared ||
      status == YorksAccountsPdcStatus.returned ||
      status == YorksAccountsPdcStatus.bounced ||
      status == YorksAccountsPdcStatus.cancelled ||
      (status == YorksAccountsPdcStatus.received &&
          target == YorksAccountsPdcStatus.expected) ||
      (status == YorksAccountsPdcStatus.deposited &&
          target == YorksAccountsPdcStatus.received);

  /// A cleared cheque has its clearing undone before its details change.
  bool get canEditDetails =>
      status != YorksAccountsPdcStatus.cleared &&
      status != YorksAccountsPdcStatus.replaced;
}

/// The whole project cheque register.
final class YorksAccountsProjectPdcRegister {
  const YorksAccountsProjectPdcRegister({
    required this.schemaVersion,
    required this.projectId,
    required this.pdcs,
  });

  final int schemaVersion;
  final String projectId;
  final List<YorksAccountsProjectPdc> pdcs;

  factory YorksAccountsProjectPdcRegister.fromJson(Map<String, dynamic> json) {
    final rows = (json['pdcs'] as List<dynamic>? ?? const [])
        .map((e) => YorksAccountsProjectPdc.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return YorksAccountsProjectPdcRegister(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      projectId: json['project_id'] as String,
      pdcs: rows,
    );
  }

  bool get isEmpty => pdcs.isEmpty;
}

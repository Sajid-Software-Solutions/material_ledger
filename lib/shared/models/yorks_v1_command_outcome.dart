import 'yorks_v1_domain_error.dart';

/// Command truth is independent of network, sync and optional view health.
enum YorksV1CommandPhase {
  notSent,
  inFlight,
  checking,
  confirmed,
  rejected,
  unknown,
  confirmedViewUnavailable,
}

class YorksV1CommandReceipt {
  const YorksV1CommandReceipt({
    required this.commandName,
    required this.commandKey,
    required this.entityId,
    this.recordVersion,
  });
  final String commandName;
  final String commandKey;
  final String entityId;
  final int? recordVersion;
}

class YorksV1CommandOutcomeUnknown extends YorksV1DomainException {
  const YorksV1CommandOutcomeUnknown(this.commandKey, {super.cause})
    : super(YorksV1DomainErrorCode.backendUnavailable);
  final String commandKey;
}

/// A durable effect was witnessed; an optional projection could not be read.
class YorksV1CommittedViewUnavailable extends YorksV1DomainException {
  const YorksV1CommittedViewUnavailable(this.receipt, {super.cause})
    : super(YorksV1DomainErrorCode.backendUnavailable);
  final YorksV1CommandReceipt receipt;
}

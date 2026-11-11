import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_logistics.dart';
import '../repositories/yorks_v1_logistics_repository.dart';

/// Keeps an uncertain command immutable until the server resolves its outcome.
/// Retrying must replay both the payload and key, including expected version.
class YorksV1InventoryStockCommand {
  YorksV1InventoryStockCommand({
    YorksV1InventoryAdjustmentInput? recovered,
    this.persist,
    this.canExecute,
    this.recoveryBlocked = false,
  }) : _pending = recovered;
  final Future<void> Function(YorksV1InventoryAdjustmentInput?)? persist;
  final bool Function()? canExecute;
  final bool recoveryBlocked;
  YorksV1InventoryAdjustmentInput? get pending => _pending;

  YorksV1InventoryAdjustmentInput? _pending;
  bool busy = false;
  bool get unresolved => recoveryBlocked || _pending != null;

  Future<void> save(
    YorksV1LogisticsRepository repository,
    YorksV1InventoryAdjustmentInput Function() input,
  ) async {
    if (busy) return;
    if (recoveryBlocked) throw StateError('Recovery record requires review');
    final wasUnresolved = unresolved;
    busy = true;
    try {
      _pending ??= input();
      // Persist before sending: a reload must replay the same command.
      if (persist != null) await persist!(_pending);
      if (canExecute != null && !canExecute!()) {
        throw StateError('Inventory authority changed');
      }
      await repository.adjustInventory(_pending!);
      if (persist != null) await persist!(null);
      _pending = null;
    } on YorksV1DomainException catch (error) {
      if (!(wasUnresolved && error.code == YorksV1DomainErrorCode.offline) &&
          !{
            YorksV1DomainErrorCode.backendUnavailable,
            YorksV1DomainErrorCode.unexpectedResponse,
          }.contains(error.code)) {
        if (persist != null) await persist!(null);
        _pending = null;
      }
      rethrow;
    } finally {
      busy = false;
    }
  }
}

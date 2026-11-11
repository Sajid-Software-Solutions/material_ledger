import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_inventory_strings.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_import_recovery_provider.dart';
import '../../../../shared/providers/yorks_v1_inventory_supplier_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_repository_provider.dart';

class YorksV1InventoryImportRecoveryPanel extends ConsumerStatefulWidget {
  const YorksV1InventoryImportRecoveryPanel({
    super.key,
    required this.onResolved,
  });
  final VoidCallback onResolved;
  @override
  ConsumerState<YorksV1InventoryImportRecoveryPanel> createState() =>
      _RecoveryState();
}

class _RecoveryState
    extends ConsumerState<YorksV1InventoryImportRecoveryPanel> {
  bool busy = false;
  bool invalid = false;
  Future<void> retry() async {
    final recovery = ref.read(yorksV1InventoryImportRecoveryProvider);
    if (recovery == null || recovery.busy || busy) return;
    setState(() => busy = true);
    recovery.busy = true;
    try {
      final saved = recovery.read();
      final payload = Map<String, Object?>.from(saved['payload'] as Map);
      final key = saved['key'] as String;
      if (!recovery.active) return;
      if (saved['supplier'] == true) {
        await ref
            .read(yorksV1InventorySupplierRepositoryProvider)
            .importPrepared(payload: payload, idempotencyKey: key);
      } else {
        final input = YorksV1InventoryImportInput(
          fileName: payload['file_name'] as String,
          rows: [
            for (final row in payload['rows'] as List)
              YorksV1InventoryImportRowInput.fromRecoveryJson(
                Map<String, dynamic>.from(row as Map),
              ),
          ],
          idempotencyKey: key,
        );
        await ref
            .read(yorksV1LogisticsRepositoryProvider)
            .importInventory(input);
      }
      await recovery.persist(null);
      if (!mounted || !recovery.active) return;
      ref.invalidate(yorksV1InventoryWorkspaceProvider);
      ref.invalidate(yorksV1InventoryRegisterProvider);
      ref.invalidate(yorksV1InventoryHistoryProvider);
      ref.invalidate(yorksV1InventoryItemDetailProvider);
      ref.invalidate(yorksV1InventorySupplierDirectoryProvider);
      ref.invalidate(yorksV1InventorySupplierFolderProvider);
      widget.onResolved();
    } on YorksV1DomainException catch (error) {
      if (!{
        YorksV1DomainErrorCode.offline,
        YorksV1DomainErrorCode.backendUnavailable,
        YorksV1DomainErrorCode.unexpectedResponse,
      }.contains(error.code)) {
        await recovery.persist(null);
        if (mounted && recovery.active) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                YorksV1InventoryStrings.saveRejected.active(
                  ref.read(languageProvider),
                ),
              ),
            ),
          );
          widget.onResolved();
        }
      }
      // Unconfirmed input remains available; never fabricate a success.
    } on FormatException {
      invalid = true;
    } on TypeError {
      invalid = true;
    } catch (_) {
      // Network/storage failure leaves the original identity intact.
    } finally {
      recovery.busy = false;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions_outlined, size: 40),
              const SizedBox(height: AppSpacing.lg),
              Text(
                (invalid
                        ? YorksV1InventoryStrings.recoveryBlocked
                        : YorksV1InventoryStrings.uncertainSave)
                    .active(language),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (busy)
                const CircularProgressIndicator()
              else if (!invalid)
                FilledButton(
                  onPressed: retry,
                  child: Text(
                    YorksV1InventoryStrings.retrySave.active(language),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

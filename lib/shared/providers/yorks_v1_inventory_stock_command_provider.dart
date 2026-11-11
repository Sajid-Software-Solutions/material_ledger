import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/yorks_v1_inventory_stock_command.dart';
import '../models/yorks_v1_logistics.dart';
import 'language_provider.dart';
import 'yorks_v1_identity_provider.dart';

/// Recovery contains the user's submitted input, never an authoritative balance.
/// A changed account/role cannot restore or replay another authority's command.
final yorksV1InventoryStockCommandProvider =
    Provider<YorksV1InventoryStockCommand>((ref) {
      final user = ref.watch(yorksV1AuthUserIdProvider);
      final role = ref.watch(yorksV1CurrentRoleProvider);
      if (user == null || role == null || !role.canManageInventory) {
        return YorksV1InventoryStockCommand();
      }
      final prefs = ref.watch(sharedPreferencesProvider);
      final key = 'yorks.inventory.pending.v1.$user.${role.name}';
      final stored = prefs.get(key);
      if (stored != null && stored is! String) {
        return YorksV1InventoryStockCommand(recoveryBlocked: true);
      }
      final saved = stored as String?;
      // Invalid records remain untouched. Failing closed avoids silently
      // replacing a command whose server outcome has not been reconciled.
      YorksV1InventoryAdjustmentInput? recovered;
      try {
        recovered = saved == null
            ? null
            : YorksV1InventoryAdjustmentInput.fromRecoveryJson(
                Map<String, dynamic>.from(jsonDecode(saved) as Map),
              );
      } catch (_) {
        return YorksV1InventoryStockCommand(recoveryBlocked: true);
      }
      var ownedKey = recovered?.idempotencyKey;
      var active = true;
      ref.onDispose(() => active = false);
      return YorksV1InventoryStockCommand(
        recovered: recovered,
        canExecute: () => active,
        persist: (input) async {
          await prefs.reload();
          final existing = prefs.getString(key);
          if (existing != null) {
            final savedKey = (jsonDecode(existing) as Map)['idempotencyKey'];
            if (savedKey != (input?.idempotencyKey ?? ownedKey)) {
              throw StateError('Resolve the previous stock command first');
            }
          }
          if (input != null) ownedKey = input.idempotencyKey;
          final ok = input == null
              ? await prefs.remove(key)
              : await prefs.setString(key, jsonEncode(input.toRecoveryJson()));
          if (!ok) throw StateError('Inventory recovery storage failed');
        },
      );
    });

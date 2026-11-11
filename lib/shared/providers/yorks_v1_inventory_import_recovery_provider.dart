import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/yorks_v1_inventory_import_recovery.dart';
import 'language_provider.dart';
import 'yorks_v1_identity_provider.dart';

final yorksV1InventoryImportRecoveryProvider =
    Provider<YorksV1InventoryImportRecovery?>((ref) {
      final user = ref.watch(yorksV1AuthUserIdProvider);
      final role = ref.watch(yorksV1CurrentRoleProvider);
      if (user == null || role == null || !role.canManageInventory) return null;
      final recovery = YorksV1InventoryImportRecovery(
        ref.watch(sharedPreferencesProvider),
        'yorks.inventory.import.v1.$user.${role.name}',
      );
      ref.onDispose(() => recovery.active = false);
      return recovery;
    });

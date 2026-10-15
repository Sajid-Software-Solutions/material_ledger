import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/yorks_v1_material_workflow_command_controller.dart';
import '../models/yorks_v1_command_outcome.dart';
import '../services/yorks_v1_critical_command_key_store.dart';
import '../repositories/yorks_v1_command_outcome_repository.dart';
import '../services/analytics_service.dart';
import 'yorks_v1_read_activity_provider.dart';
import 'language_provider.dart';
import 'yorks_v1_arrangement_repository_provider.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_logistics_repository_provider.dart';
import 'yorks_v1_material_request_repository_provider.dart';

final yorksV1CommandPhaseProvider =
    StateProvider.family<YorksV1CommandPhase?, String>((ref, id) => null);

final yorksV1MaterialWorkflowCommandControllerProvider =
    Provider<YorksV1MaterialWorkflowCommandController>((ref) {
      final actorAuthUserId = ref.watch(yorksV1AuthUserIdProvider) ?? '';
      ref.watch(yorksV1CurrentRoleProvider);
      var active = true;
      ref.onDispose(() => active = false);
      return YorksV1MaterialWorkflowCommandController(
        materialRequests: ref.watch(yorksV1MaterialRequestRepositoryProvider),
        arrangements: ref.watch(yorksV1ArrangementRepositoryProvider),
        logistics: ref.watch(yorksV1LogisticsRepositoryProvider),
        outcomes: ref.watch(yorksV1MaterialRequestRpcClientProvider) == null
            ? null
            : YorksV1RpcCommandOutcomeRepository(
                ref.watch(yorksV1MaterialRequestRpcClientProvider)!,
              ),
        analytics: ref.watch(analyticsServiceProvider),
        isCurrentAuthority: () => active,
        onPhase: (id, phase) =>
            ref.read(yorksV1CommandPhaseProvider(id).notifier).state = phase,
        beginActivity: ref.watch(yorksV1ReadActivityGateProvider).begin,
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: actorAuthUserId,
          backendNamespace: const String.fromEnvironment(
            'SUPABASE_URL',
            defaultValue: 'unconfigured',
          ),
        ),
      );
    });

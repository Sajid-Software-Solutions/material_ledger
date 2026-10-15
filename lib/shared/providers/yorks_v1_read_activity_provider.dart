import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/yorks_v1_read_activity_gate.dart';
import 'yorks_v1_identity_provider.dart';

/// Scheduling only; this gate grants no authority and stores no business data.
final yorksV1ReadActivityGateProvider = Provider<YorksV1ReadActivityGate>((
  ref,
) {
  ref.watch(yorksV1AuthUserIdProvider);
  ref.watch(yorksV1CurrentRoleProvider);
  final gate = YorksV1ReadActivityGate();
  ref.onDispose(gate.dispose);
  return gate;
});

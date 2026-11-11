import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../data/workforce_repository.dart';

class WorkforceTeamWorkersController
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  WorkforceTeamWorkersController(this.repository, this.keys)
    : super(const AsyncLoading());
  final YorksWorkforceTeamWorkerRepository repository;
  final YorksV1CriticalCommandKeyStore keys;
  String? teamId;
  bool saving = false;
  int _load = 0;

  Future<void> load({String? selectedTeam}) async {
    final revision = ++_load;
    teamId = selectedTeam;
    state = const AsyncLoading();
    try {
      var data = await repository.getTeamWorkers(teamId: selectedTeam);
      if (!mounted || revision != _load) return;
      final teams = data['teams'] as List;
      if (teamId == null && teams.isNotEmpty) {
        teamId = teams.first['id'] as String;
        data = await repository.getTeamWorkers(teamId: teamId);
      }
      if (mounted && revision == _load) state = AsyncData(data);
    } catch (error, stack) {
      if (mounted && revision == _load) state = AsyncError(error, stack);
    }
  }

  Future<bool> create(Map<String, Object?> payload) async {
    final team = teamId;
    if (saving || team == null || !state.hasValue) return false;
    saving = true;
    try {
      final key = await keys.acquire(
        operation: 'create_team_worker',
        entityId: team,
        payload: payload,
      );
      if (!mounted) return false;
      await repository.createTeamWorker(team, payload, key);
      await keys.confirm(
        operation: 'create_team_worker',
        entityId: team,
        idempotencyKey: key,
      );
      if (!mounted) return false;
      await load(selectedTeam: team);
      return true;
    } finally {
      saving = false;
    }
  }

  Future<void> loadMore() async {
    final previous = state.valueOrNull;
    final team = teamId;
    if (previous == null || team == null || saving) return;
    final revision = ++_load;
    final rows = previous['workers'] as List;
    try {
      final next = await repository.getTeamWorkers(
        teamId: team,
        offset: rows.length,
      );
      if (mounted && revision == _load) {
        state = AsyncData({
          ...next,
          'workers': [...rows, ...next['workers'] as List],
          'has_more': (next['workers'] as List).length == 50,
        });
      }
    } catch (error, stack) {
      if (mounted && revision == _load) state = AsyncError(error, stack);
    }
  }
}

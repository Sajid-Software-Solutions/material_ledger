import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/features/workforce/application/workforce_team_workers_controller.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'uncertain create retains the command key and reuses it on retry',
    () async {
      final repo = _Repo()..fail = true;
      final c = await _controller(repo);
      await c.load();
      expect(c.teamId, 'team-a');
      await expectLater(c.create({'full_name': 'Worker'}), throwsStateError);
      repo.fail = false;
      expect(await c.create({'full_name': 'Worker'}), isTrue);
      expect(repo.keys.length, 2);
      expect(repo.keys[0], repo.keys[1]);
      c.dispose();
    },
  );
  test('older team response cannot replace the selected team', () async {
    final repo = _Repo();
    final c = await _controller(repo);
    repo.pending = Completer<Map<String, dynamic>>();
    final old = c.load(selectedTeam: 'slow');
    await c.load(selectedTeam: 'team-a');
    repo.pending!.complete({
      'teams': [],
      'workers': [
        {'name': 'stale'},
      ],
    });
    await old;
    expect(c.teamId, 'team-a');
    expect(c.state.value!['workers'], isEmpty);
    c.dispose();
  });
  test('disposed authority does not restore protected worker data', () async {
    final repo = _Repo()..pending = Completer<Map<String, dynamic>>();
    final c = await _controller(repo);
    final load = c.load(selectedTeam: 'slow');
    c.dispose();
    repo.pending!.complete({'teams': [], 'workers': []});
    await load;
  });
}

Future<WorkforceTeamWorkersController> _controller(_Repo repo) async =>
    WorkforceTeamWorkersController(
      repo,
      YorksV1CriticalCommandKeyStore(
        preferences: await SharedPreferences.getInstance(),
        actorAuthUserId: 'actor',
      ),
    );

class _Repo implements YorksWorkforceTeamWorkerRepository {
  bool fail = false;
  final keys = <String>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> getTeamWorkers({
    String? teamId,
    int offset = 0,
  }) async {
    if (teamId == 'slow') return pending!.future;
    return {
      'teams': [
        {'id': 'team-a', 'name': 'Own team'},
      ],
      'workers': [],
    };
  }

  @override
  Future<Map<String, dynamic>> createTeamWorker(
    String teamId,
    Map<String, Object?> payload,
    String idempotencyKey,
  ) async {
    keys.add(idempotencyKey);
    if (fail) throw StateError('uncertain');
    return {'worker_id': 'worker'};
  }
}

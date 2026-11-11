import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';

YorksV1MaterialRequestDraft _draft({
  required String projectId,
  required DateTime updatedAt,
  String id = 'draft',
  int privateSyncVersion = 0,
}) => YorksV1MaterialRequestDraft(
  id: id,
  ownerAuthUserId: 'owner',
  submissionIdempotencyKey: 'submit',
  projectId: projectId,
  title: 'Draft',
  privateSyncVersion: privateSyncVersion,
  updatedAt: updatedAt,
);

void main() {
  test('a draft moved to another project leaves no stale copy behind', () {
    // The account copy still names project A; this device has since moved
    // the same draft to project B.
    final account = _draft(
      projectId: 'a',
      updatedAt: DateTime.utc(2026, 11, 8),
      privateSyncVersion: 2,
    );
    final device = _draft(projectId: 'b', updatedAt: DateTime.utc(2026, 11, 9));

    expect(
      mergeRecoverableMaterialRequestDrafts(
        [device],
        [account],
        projectId: 'a',
      ),
      isEmpty,
    );
    final onB = mergeRecoverableMaterialRequestDrafts(
      [device],
      [account],
      projectId: 'b',
    );
    expect(onB, hasLength(1));
    expect(onB.single.updatedAt, device.updatedAt);
    // The account copy's sync version is kept so deletion targets it.
    expect(onB.single.privateSyncVersion, 2);
  });

  test('the newest copy wins and other projects are filtered out', () {
    final older = _draft(projectId: 'a', updatedAt: DateTime.utc(2026, 11, 8));
    final newer = _draft(
      projectId: 'a',
      updatedAt: DateTime.utc(2026, 11, 9),
      privateSyncVersion: 1,
    );
    final elsewhere = _draft(
      id: 'other',
      projectId: 'c',
      updatedAt: DateTime.utc(2026, 11, 10),
    );

    final merged = mergeRecoverableMaterialRequestDrafts(
      [older, elsewhere],
      [newer],
      projectId: 'a',
    );
    expect(merged.map((draft) => draft.updatedAt), [newer.updatedAt]);
    expect(
      mergeRecoverableMaterialRequestDrafts([older, elsewhere], [newer]),
      hasLength(2),
    );
  });
}

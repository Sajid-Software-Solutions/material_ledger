import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_dispatch_centre.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';

void main() {
  for (final scenario in <({String name, Size size, String golden})>[
    (
      name: 'desktop',
      size: const Size(1440, 1000),
      golden: 'goldens/r35/dispatch_centre_1440x1000.png',
    ),
    (
      name: 'mobile',
      size: const Size(390, 844),
      golden: 'goldens/r35/dispatch_centre_390x844.png',
    ),
  ]) {
    testWidgets('Dispatch Centre ${scenario.name} reference', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('dispatch-centre-golden'),
              child: YorksV1DispatchCentre(
                requests: _requests,
                language: AppLanguage.english,
                onOpen: (_) {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey('dispatch-centre-golden')),
        matchesGoldenFile(scenario.golden),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

final _requests = <YorksV1MaterialRequest>[
  _request(
    id: 'mr-ready',
    number: 'YRA322-MR006',
    projectId: 'project-322',
    projectReference: 'YRA-322',
    projectName: 'N-19957.2 Project Nexus (Power)',
    scopeName: 'DF6W - 132/33kV Substation Building',
    requester: 'Omar Farooq',
    state: YorksV1MaterialRequestState.approved,
    itemCount: 4,
    updatedAt: DateTime.utc(2026, 8, 24, 9, 30),
  ),
  _request(
    id: 'mr-dispatched',
    number: 'YRA323-MR001',
    projectId: 'project-323',
    projectReference: 'YRA-323',
    projectName: 'N-19955.2 Project Nexus Transmission Scheme',
    scopeName: 'Common / All Buildings',
    requester: 'Masaud Khan',
    state: YorksV1MaterialRequestState.dispatched,
    itemCount: 2,
    updatedAt: DateTime.utc(2026, 8, 24, 8, 15),
  ),
  _request(
    id: 'mr-receipt',
    number: 'YRA324-MR009',
    projectId: 'project-324',
    projectReference: 'YRA-324',
    projectName: 'N-19957.1 Nexus Bulk Transmission Scheme',
    scopeName: 'DF1W - 132/33kV Building',
    requester: 'Silvin Pailo',
    state: YorksV1MaterialRequestState.partiallyReceived,
    itemCount: 3,
    updatedAt: DateTime.utc(2026, 8, 23, 17, 45),
  ),
  _request(
    id: 'mr-closed',
    number: 'YRA314-MR007',
    projectId: 'project-314',
    projectReference: 'YRA-314',
    projectName: 'New 220-33kV Substation at ICAD-B',
    scopeName: 'Common / All Buildings',
    requester: 'Arnel Palma',
    state: YorksV1MaterialRequestState.closed,
    itemCount: 6,
    updatedAt: DateTime.utc(2026, 8, 22, 14, 10),
  ),
];

YorksV1MaterialRequest _request({
  required String id,
  required String number,
  required String projectId,
  required String projectReference,
  required String projectName,
  required String scopeName,
  required String requester,
  required YorksV1MaterialRequestState state,
  required int itemCount,
  required DateTime updatedAt,
}) => YorksV1MaterialRequest(
  id: id,
  projectId: projectId,
  projectReference: projectReference,
  projectName: projectName,
  scopeId: '$projectId-scope',
  scopeName: scopeName,
  state: state,
  recordVersion: 1,
  createdAt: updatedAt.subtract(const Duration(days: 2)),
  updatedAt: updatedAt,
  timing: YorksV1MaterialRequestTiming.normal,
  requestNumber: number,
  requesterDisplayName: requester,
  requesterProjectRole: 'Project Engineer',
  itemCount: itemCount,
  lines: const [],
  dispatchReady: state == YorksV1MaterialRequestState.approved,
);

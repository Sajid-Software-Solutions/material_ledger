import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';

void main() {
  test('setup events admit only documented categorical context', () {
    final safe =
        projectSetupAnalyticsProperties(AnalyticsEvent.projectSetupStepViewed, {
          AnalyticsProperty.mode: 'create',
          AnalyticsProperty.step: 'buildings',
          AnalyticsProperty.entryPoint: 'projects',
          AnalyticsProperty.source: 'client_name',
          AnalyticsProperty.itemCount: 32,
          AnalyticsProperty.outcome: 'project_123',
        });
    expect(safe, {
      AnalyticsProperty.mode: 'create',
      AnalyticsProperty.step: 'buildings',
      AnalyticsProperty.entryPoint: 'projects',
    });
  });
  test('identifier-shaped strings cannot enter allowed setup fields', () {
    for (final event in [
      AnalyticsEvent.projectDraftSaved,
      AnalyticsEvent.projectCommandReconciled,
      AnalyticsEvent.projectSetupCompleted,
    ]) {
      final safe = projectSetupAnalyticsProperties(event, {
        for (final key in AnalyticsProperty.values) key: 'project_abc123',
      });
      expect(safe, isEmpty);
    }
  });
  test('confirmed core creation remains a distinct existing event', () {
    const props = {
      AnalyticsProperty.buildingCount: 2,
      AnalyticsProperty.attachmentCount: 3,
    };
    expect(
      projectSetupAnalyticsProperties(AnalyticsEvent.projectCreated, props),
      props,
    );
    expect(
      AnalyticsEvent.projectSetupCompleted.wireName,
      'project setup completed',
    );
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/analytics_configuration.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';

void main() {
  late _RecordingSink sink;
  late GuardedAnalyticsService analytics;
  late DateTime now;

  setUp(() async {
    sink = _RecordingSink();
    now = DateTime.utc(2026, 9, 9, 8);
    analytics = GuardedAnalyticsService(
      configuration: const AnalyticsConfiguration(
        requestedEnabled: true,
        projectToken: 'phc_test',
        host: 'https://eu.i.posthog.com',
        environment: AnalyticsEnvironment.staging,
        platform: AnalyticsPlatform.android,
        appVersion: '1.2.3',
        appBuild: '45',
      ),
      sink: sink,
      now: () => now,
      noFeedbackWindow: const Duration(milliseconds: 10),
    );
    await analytics.initialize();
  });

  test('taxonomy stays bounded, stable, and unique', () {
    final names = AnalyticsEvent.values.map((event) => event.wireName).toList();
    expect(names, hasLength(59));
    expect(names.toSet(), hasLength(names.length));
    expect(names, everyElement(matches(RegExp(r'^[a-z0-9]+(?: [a-z0-9]+)*$'))));
    expect(names, isNot(contains('material_request_opened')));
    expect(names, contains('material request opened'));
    expect(names, contains('reliability error occurred'));
  });

  test(
    'identity uses UUID plus role only and reset follows sign out',
    () async {
      analytics.identify(
        userId: '3f784ff0-6bca-4cfe-ac06-105f4f7dcad0',
        role: 'project_engineer',
      );
      analytics.capture(AnalyticsEvent.authenticationSucceeded);
      analytics.reset();
      await analytics.drain();

      expect(
        sink.operations,
        containsAllInOrder([
          'identify:3f784ff0-6bca-4cfe-ac06-105f4f7dcad0:project_engineer',
          'capture:authentication succeeded',
          'reset',
        ]),
      );
    },
  );

  test('identity rejects non-Supabase identifiers', () async {
    analytics.identify(userId: 'local-user', role: 'project_engineer');
    analytics.identify(userId: 'person@example.com', role: 'admin');
    await analytics.drain();

    expect(
      sink.operations.where((value) => value.startsWith('identify:')),
      isEmpty,
    );
  });

  test('verified role changes re-identify the same Supabase user', () async {
    const userId = '3f784ff0-6bca-4cfe-ac06-105f4f7dcad0';
    analytics.identify(userId: userId, role: 'site_engineer');
    analytics.identify(userId: userId, role: 'project_engineer');
    await analytics.drain();

    expect(
      sink.operations.where((value) => value.startsWith('identify:')),
      <String>[
        'identify:$userId:site_engineer',
        'identify:$userId:project_engineer',
      ],
    );
  });

  test('free text and PII-shaped values are dropped before the sink', () async {
    analytics.capture(
      AnalyticsEvent.projectCreated,
      properties: const {
        AnalyticsProperty.source: 'person@example.com',
        AnalyticsProperty.outcome: 'Alpha Tower Project',
        AnalyticsProperty.itemCount: 4,
      },
    );
    await analytics.drain();

    final properties = sink.events.single.properties;
    expect(properties, isNot(contains('source')));
    expect(properties, isNot(contains('outcome')));
    expect(properties['item_count'], 4);
    expect(properties['schema_version'], analyticsSchemaVersion);
    expect(properties['app_version'], '1.2.3');
    expect(properties['app_build'], '45');
    expect(properties['environment'], 'staging');
    expect(properties['platform'], 'android');
  });

  test('screen tracking is stable and de-duplicated', () async {
    analytics.screenViewed(AnalyticsScreen.projectDetail);
    analytics.screenViewed(AnalyticsScreen.projectDetail);
    await analytics.drain();

    expect(sink.screens, hasLength(1));
    expect(sink.screens.single.name, 'project_detail');
    expect(sink.screens.single.properties, isNot(contains(r'$current_url')));
  });

  test('three rapid action attempts emit one repeated-action event', () async {
    for (var index = 0; index < 3; index++) {
      analytics.recordActionAttempt(
        action: 'submit_material_request',
        screen: AnalyticsScreen.materialRequestDraft,
        operationWasLoading: index > 0,
      );
      now = now.add(const Duration(milliseconds: 300));
    }
    await analytics.drain();

    final event = sink.events.singleWhere(
      (item) => item.name == 'repeated action detected',
      orElse: () => throw StateError('missing repeated action event'),
    );
    expect(event.properties['tap_count'], 3);
    expect(event.properties['operation_was_loading'], isTrue);
  });

  test('no-feedback event fires only when feedback is not observed', () async {
    final observed = analytics.expectFeedback(
      action: 'save_project',
      screen: AnalyticsScreen.projectCreate,
    );
    observed.feedbackObserved();
    analytics.expectFeedback(
      action: 'submit_material_request',
      screen: AnalyticsScreen.materialRequestDraft,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await analytics.drain();

    expect(
      sink.events.where((event) => event.name == 'action produced no feedback'),
      hasLength(1),
    );
  });

  test('search struggle uses counts and never receives the query', () async {
    analytics.recordMaterialSearch(
      queryLength: 4,
      resultCount: 0,
      duration: const Duration(milliseconds: 50),
    );
    now = now.add(const Duration(seconds: 1));
    analytics.recordMaterialSearch(
      queryLength: 7,
      resultCount: 0,
      duration: const Duration(milliseconds: 70),
    );
    now = now.add(const Duration(seconds: 1));
    analytics.recordMaterialSearch(
      queryLength: 8,
      resultCount: 2,
      duration: const Duration(milliseconds: 90),
    );
    await analytics.drain();

    final struggle = sink.events.singleWhere(
      (event) => event.name == 'search struggle detected',
    );
    expect(struggle.properties['attempt_count'], 3);
    expect(struggle.properties['no_result_count'], 2);
    expect(
      struggle.properties.values.whereType<String>(),
      isNot(contains('duct tape')),
    );
  });

  test(
    'inventory search emits semantic result events without query text',
    () async {
      analytics.recordMaterialSearch(
        queryLength: 9,
        resultCount: 0,
        duration: const Duration(milliseconds: 80),
        context: AnalyticsSearchContext.inventory,
      );
      await analytics.drain();

      expect(
        sink.events.map((event) => event.name),
        containsAll(<String>[
          'inventory searched',
          'inventory search no results',
        ]),
      );
      expect(
        sink.events
            .expand((event) => event.properties.values)
            .whereType<String>(),
        isNot(contains('private material')),
      );
    },
  );

  test(
    'three matching safe validation failures emit one loop signal',
    () async {
      for (var index = 0; index < 3; index++) {
        analytics.capture(
          AnalyticsEvent.formValidationFailed,
          properties: const {
            AnalyticsProperty.formType: 'material_request',
            AnalyticsProperty.validationReason: 'incomplete_request',
          },
        );
        now = now.add(const Duration(seconds: 5));
      }
      await analytics.drain();

      expect(
        sink.events.where((event) => event.name == 'validation loop detected'),
        hasLength(1),
      );
    },
  );

  test('failed operation emits normalized reliability context', () async {
    analytics.screenViewed(AnalyticsScreen.inventory);
    analytics.identify(
      userId: '3f784ff0-6bca-4cfe-ac06-105f4f7dcad0',
      role: 'procurement',
    );
    final operation = analytics.beginOperation('inventory_load');
    operation.fail(TimeoutException('sensitive backend detail'));
    await analytics.drain();

    final event = sink.events.singleWhere(
      (item) => item.name == 'reliability error occurred',
    );
    expect(event.properties['operation'], 'inventory_load');
    expect(event.properties['error_category'], 'timeout');
    expect(event.properties['retryable'], isTrue);
    expect(event.properties['screen_name'], 'inventory');
    expect(event.properties['role'], 'procurement');
    expect(
      event.properties.values,
      isNot(contains('sensitive backend detail')),
    );
  });

  test('feature flag evaluation fails closed', () async {
    sink.throwOnFlags = true;
    expect(
      await analytics.isFeatureEnabled(
        AnalyticsFeatureFlag.compactRequestWorkspace,
      ),
      isFalse,
    );
  });

  test('sink failures remain isolated from the caller', () async {
    sink.throwOnCapture = true;
    analytics.capture(AnalyticsEvent.projectOpened);

    await expectLater(analytics.drain(), completes);
  });

  test('disabled and CI configurations are no-ops', () async {
    final disabled = GuardedAnalyticsService(
      configuration: const AnalyticsConfiguration(
        requestedEnabled: true,
        projectToken: 'phc_test',
        host: 'https://eu.i.posthog.com',
        environment: AnalyticsEnvironment.ci,
        platform: AnalyticsPlatform.android,
        appVersion: '1',
        appBuild: '1',
      ),
      sink: sink,
    );
    await disabled.initialize();
    disabled.capture(AnalyticsEvent.projectOpened);
    await disabled.drain();
    expect(disabled.enabled, isFalse);
    expect(sink.events, isEmpty);
  });

  test('invalid direct-build configuration fails closed', () {
    const unknownEnvironment = AnalyticsConfiguration(
      requestedEnabled: true,
      projectToken: 'phc_test',
      host: 'https://us.i.posthog.com',
      environment: AnalyticsEnvironment.unknown,
      platform: AnalyticsPlatform.web,
      appVersion: '1',
      appBuild: '1',
    );
    const unsafeHost = AnalyticsConfiguration(
      requestedEnabled: true,
      projectToken: 'phc_test',
      host: 'https://us.i.posthog.com/unexpected-path',
      environment: AnalyticsEnvironment.production,
      platform: AnalyticsPlatform.web,
      appVersion: '1',
      appBuild: '1',
    );

    expect(unknownEnvironment.enabled, isFalse);
    expect(unsafeHost.enabled, isFalse);
    expect(
      const AnalyticsConfiguration(
        requestedEnabled: true,
        projectToken: 'phc_test',
        host: 'https://us.i.posthog.com',
        environment: AnalyticsEnvironment.production,
        platform: AnalyticsPlatform.web,
        appVersion: '1',
        appBuild: '1',
        debugRequested: true,
      ).debug,
      isFalse,
    );
    expect(
      AnalyticsConfiguration.resolveEnvironment(
        postHogValue: 'staging',
        r35Value: 'production',
      ),
      AnalyticsEnvironment.unknown,
    );
    expect(
      AnalyticsConfiguration.resolveEnvironment(
        postHogValue: 'development',
        r35Value: 'local',
      ),
      AnalyticsEnvironment.local,
    );
  });
}

class _RecordingSink implements AnalyticsSink {
  final operations = <String>[];
  final events = <_RecordedEvent>[];
  final screens = <_RecordedScreen>[];
  bool throwOnFlags = false;
  bool throwOnCapture = false;

  @override
  Future<void> initialize(AnalyticsConfiguration configuration) async {
    operations.add('initialize');
  }

  @override
  Future<void> identify({required String userId, required String role}) async {
    operations.add('identify:$userId:$role');
  }

  @override
  Future<void> reset() async {
    operations.add('reset');
  }

  @override
  Future<void> capture({
    required String eventName,
    required Map<String, Object> properties,
  }) async {
    if (throwOnCapture) throw StateError('transport unavailable');
    operations.add('capture:$eventName');
    events.add(_RecordedEvent(eventName, properties));
  }

  @override
  Future<void> screen({
    required String screenName,
    required Map<String, Object> properties,
  }) async {
    screens.add(_RecordedScreen(screenName, properties));
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    if (throwOnFlags) throw TimeoutException('test');
    return true;
  }
}

class _RecordedEvent {
  const _RecordedEvent(this.name, this.properties);

  final String name;
  final Map<String, Object> properties;
}

class _RecordedScreen {
  const _RecordedScreen(this.name, this.properties);

  final String name;
  final Map<String, Object> properties;
}

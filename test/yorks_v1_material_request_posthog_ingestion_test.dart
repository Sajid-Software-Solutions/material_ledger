// Opt-in live contract check. Synthetic events are always environment=local.
// This proves controller -> privacy guard -> ingestion, not a deployed web SDK.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/controllers/yorks_v1_material_request_draft_controller.dart';
import 'package:material_ledger/shared/models/analytics_configuration.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/repositories/collection_store.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';

void main() {
  final token = Platform.environment['YORKS_POSTHOG_VERIFY_TOKEN'] ?? '';
  test(
    'synthetic local draft outcomes pass the privacy guard and live ingestion',
    () async {
      final sink = _IngestionSink();
      final analytics = GuardedAnalyticsService(
        configuration: AnalyticsConfiguration(
          requestedEnabled: true,
          projectToken: token,
          host:
              Platform.environment['YORKS_POSTHOG_VERIFY_HOST'] ??
              'https://us.i.posthog.com',
          environment: AnalyticsEnvironment.local,
          platform: AnalyticsPlatform.macos,
          appVersion: '1',
          appBuild: '20260927',
          releaseId:
              Platform.environment['YORKS_POSTHOG_VERIFY_RELEASE'] ?? 'unknown',
        ),
        sink: sink,
      );
      await analytics.initialize();
      expect(analytics.enabled, isTrue);
      for (final fails in [false, true]) {
        final controller = YorksV1MaterialRequestDraftController(
          ownerAuthUserId: 'private-owner',
          draftId: 'private-draft',
          store: _Store(),
          repository: _Repo(fails),
          analytics: analytics,
        );
        try {
          if (fails) {
            await expectLater(
              controller.discardLocal(requireServerConfirmation: true),
              throwsA(isA<YorksV1DomainException>()),
            );
          } else {
            await controller.discardLocal(requireServerConfirmation: true);
          }
        } finally {
          controller.dispose();
        }
      }
      await analytics.drain();
      sink.client.close();
      expect(
        sink.accepted,
        containsAll([
          'material request draft delete attempted',
          'material request draft deleted',
          'material request draft delete failed',
        ]),
      );
      expect(sink.failed, isEmpty);
    },
    skip: token.isEmpty ? 'Explicit local ingestion opt-in is absent' : false,
  );
}

class _IngestionSink implements AnalyticsSink {
  final client = HttpClient();
  late AnalyticsConfiguration configuration;
  final accepted = <String>[];
  final failed = <String>[];
  @override
  Future<void> initialize(AnalyticsConfiguration config) async {
    configuration = config;
  }

  @override
  Future<void> identify({required String userId, required String role}) async {}
  @override
  Future<void> reset() async {}
  @override
  Future<bool> isFeatureEnabled(String key) async => false;
  @override
  Future<void> screen({
    required String screenName,
    required Map<String, Object> properties,
  }) async {}
  @override
  Future<void> capture({
    required String eventName,
    required Map<String, Object> properties,
  }) async {
    expect(properties['environment'], 'local');
    expect(properties.toString(), isNot(contains('private-owner')));
    expect(properties.toString(), isNot(contains('private-draft')));
    final request = await client.postUrl(
      configuration.validatedHost!.resolve('/i/v0/e/'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'api_key': configuration.projectToken,
        'distinct_id': 'yorks-draft-deletion-local-verification-20260927',
        'event': eventName,
        'properties': {...properties, r'$process_person_profile': false},
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    (response.statusCode >= 200 && response.statusCode < 300
            ? accepted
            : failed)
        .add(eventName);
  }
}

class _Store implements CollectionStore<YorksV1MaterialRequestDraft> {
  List<YorksV1MaterialRequestDraft> items = [];
  @override
  bool get isSeeded => true;
  @override
  List<YorksV1MaterialRequestDraft> readAll() => items;
  @override
  Future<void> writeAll(List<YorksV1MaterialRequestDraft> drafts) async {
    items = drafts;
  }
}

class _Repo extends Fake
    implements
        YorksV1MaterialRequestRepository,
        YorksV1MaterialRequestPhase2Repository {
  _Repo(this.fails);
  final bool fails;
  @override
  Future<YorksV1PrivateMaterialRequestDraftRecord?> getPrivateDraft({
    required String draftId,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) async => null;
  @override
  Future<void> deletePrivateDraft({
    required String draftId,
    required int expectedSyncVersion,
    required String idempotencyKey,
  }) async {
    if (fails) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.offline);
    }
  }
}

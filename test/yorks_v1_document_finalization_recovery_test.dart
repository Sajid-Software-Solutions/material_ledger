import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/analytics_event.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/services/analytics_service.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

void main() {
  for (final analytics in [
    const _ThrowingAnalytics(throwBegin: true),
    const _ThrowingAnalytics(),
  ]) {
    test(
      'throwing upload telemetry cannot block dispatch or erase confirmed success (begin=${analytics.throwBegin})',
      () async {
        final fixture = _Fixture(analytics: analytics);
        final result = await fixture.repository.upload(_input());
        expect(result.projectId, 'project-1');
        expect(fixture.storage.uploads, 1);
        expect(fixture.finalizer.calls, ['intent-1']);
        expect(fixture.rpc.workspaceReads, 1);
      },
    );
  }

  test('throwing failure telemetry preserves authoritative denial', () async {
    final fixture = _Fixture(analytics: const _ThrowingAnalytics());
    fixture.rpc.error = const YorksV1DomainException(
      YorksV1DomainErrorCode.unauthorized,
    );
    await expectLater(
      fixture.repository.upload(_input()),
      throwsA(_domainCode(YorksV1DomainErrorCode.unauthorized)),
    );
    expect(fixture.storage.uploads, 0);
    expect(fixture.finalizer.calls, isEmpty);
    expect(fixture.rpc.workspaceReads, 0);
  });

  final malformedReceipts = <String, Object?>{
    'null': null,
    'empty': <String, Object?>{},
    'missing version identity': {
      'document_id': 'document-1',
      'revision_number': 1,
    },
    'empty document identity': {
      'document_id': ' ',
      'document_version_id': 'version-1',
      'revision_number': 1,
    },
    'wrong planned revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 2,
    },
    'non-integer revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 1.0,
    },
  };
  for (final receipt in malformedReceipts.entries) {
    test('${receipt.key} finalizer response remains unconfirmed', () async {
      final fixture = _Fixture();
      fixture.finalizer.response = receipt.value;
      await expectLater(
        fixture.repository.upload(_input()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.storage.uploads, 1);
      expect(fixture.finalizer.calls, ['intent-1']);
      expect(fixture.rpc.workspaceReads, 0);
    });
  }

  test(
    'replacement finalizer must confirm the exact reviewed document identity',
    () async {
      final fixture = _Fixture();
      await expectLater(
        fixture.repository.upload(_input(documentId: 'existing-document')),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.rpc.workspaceReads, 0);
      fixture.finalizer.response = {
        'document_id': 'existing-document',
        'document_version_id': 'version-2',
        'revision_number': 1,
      };
      expect(
        (await fixture.repository.upload(
          _input(documentId: ' existing-document '),
        )).projectId,
        'project-1',
      );
    },
  );

  test(
    'authoritative finalized prepare receipt skips immutable upload and finalizer on replay',
    () async {
      final fixture = _Fixture();
      fixture.rpc.finalizedDocumentId = 'document-1';
      fixture.rpc.finalizedVersionId = 'version-1';
      await fixture.repository.upload(_input());
      await fixture.repository.upload(_input());
      expect(fixture.rpc.prepareCalls, hasLength(2));
      expect(
        fixture.rpc.prepareCalls
            .map((call) => call['p_idempotency_key'])
            .toSet(),
        {'reviewed-upload-key'},
      );
      expect(fixture.storage.uploads, 0);
      expect(fixture.finalizer.calls, isEmpty);
      expect(fixture.rpc.workspaceReads, 2);
    },
  );

  test(
    'retained SQL finalization receipt preserves exact identities and skips immutable upload on replay',
    () async {
      final fixture = _Fixture();
      fixture.rpc.retainedReceipt = {
        'document_id': 'document-1',
        'document_version_id': 'version-1',
        'revision_number': 1,
      };
      final intent = YorksV1DocumentUploadIntent.fromRpcJson(
        await fixture.rpc.invoke(
              functionName: 'v1_prepare_document_upload',
              parameters: const {},
            )
            as Map<String, dynamic>,
      );
      expect(intent.finalizedDocumentId, 'document-1');
      expect(intent.finalizedVersionId, 'version-1');
      expect(intent.plannedRevisionNumber, 1);
      fixture.rpc.prepareCalls.clear();

      await fixture.repository.upload(_input());
      await fixture.repository.upload(_input());
      expect(fixture.rpc.prepareCalls, hasLength(2));
      expect(fixture.rpc.prepareCalls.first, fixture.rpc.prepareCalls.last);
      expect(fixture.storage.uploads, 0);
      expect(fixture.finalizer.calls, isEmpty);
      expect(fixture.rpc.workspaceReads, 2);
    },
  );

  final malformedRetainedReceipts = <String, Map<String, Object?>>{
    'missing document identity': {
      'document_version_id': 'version-1',
      'revision_number': 1,
    },
    'missing version identity': {
      'document_id': 'document-1',
      'revision_number': 1,
    },
    'missing revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
    },
    'empty version identity': {
      'document_id': 'document-1',
      'document_version_id': ' ',
      'revision_number': 1,
    },
    'wrong planned revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 2,
    },
    'non-integer revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 1.0,
    },
    'fractional planned revision': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 1,
      'planned_revision_number': 1.5,
    },
    'contradictory alias type': {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 1,
      'finalized_document_id': 123,
      'finalized_version_id': 456,
    },
  };
  for (final receipt in malformedRetainedReceipts.entries) {
    test('${receipt.key} retained prepare receipt fails closed', () async {
      final fixture = _Fixture();
      fixture.rpc.retainedReceipt = receipt.value;
      await expectLater(
        fixture.repository.upload(_input()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.storage.uploads, 0);
      expect(fixture.finalizer.calls, isEmpty);
      expect(fixture.rpc.workspaceReads, 0);
    });
  }

  test('matching retained receipt aliases remain compatible', () async {
    final fixture = _Fixture();
    fixture.rpc.finalizedDocumentId = 'document-1';
    fixture.rpc.finalizedVersionId = 'version-1';
    fixture.rpc.retainedReceipt = {
      'document_id': 'document-1',
      'document_version_id': 'version-1',
      'revision_number': 1,
    };
    expect((await fixture.repository.upload(_input())).projectId, 'project-1');
    expect(fixture.storage.uploads, 0);
    expect(fixture.finalizer.calls, isEmpty);
    expect(fixture.rpc.workspaceReads, 1);
  });

  for (final identity in ['document', 'version']) {
    test('conflicting $identity receipt aliases fail closed', () async {
      final fixture = _Fixture();
      fixture.rpc.finalizedDocumentId = identity == 'document'
          ? 'another-document'
          : 'document-1';
      fixture.rpc.finalizedVersionId = identity == 'version'
          ? 'another-version'
          : 'version-1';
      fixture.rpc.retainedReceipt = {
        'document_id': 'document-1',
        'document_version_id': 'version-1',
        'revision_number': 1,
      };
      await expectLater(
        fixture.repository.upload(_input()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.storage.uploads, 0);
      expect(fixture.finalizer.calls, isEmpty);
      expect(fixture.rpc.workspaceReads, 0);
    });
  }

  for (final onlyDocument in [true, false]) {
    test(
      'partial finalized prepare identity fails closed (document=$onlyDocument)',
      () async {
        final fixture = _Fixture();
        if (onlyDocument) {
          fixture.rpc.finalizedDocumentId = 'document-1';
        } else {
          fixture.rpc.finalizedVersionId = 'version-1';
        }
        await expectLater(
          fixture.repository.upload(_input()),
          throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
        );
        expect(fixture.storage.uploads, 0);
        expect(fixture.finalizer.calls, isEmpty);
        expect(fixture.rpc.workspaceReads, 0);
      },
    );
  }

  test(
    'a finalized prepare replay cannot substitute another replacement document',
    () async {
      final fixture = _Fixture();
      fixture.rpc.finalizedDocumentId = 'different-document';
      fixture.rpc.finalizedVersionId = 'version-1';
      await expectLater(
        fixture.repository.upload(_input(documentId: 'existing-document')),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.rpc.workspaceReads, 0);
      expect(fixture.storage.uploads, 0);
    },
  );

  test(
    'retained SQL receipt cannot substitute another replacement document',
    () async {
      final fixture = _Fixture();
      fixture.rpc.retainedReceipt = {
        'document_id': 'different-document',
        'document_version_id': 'version-1',
        'revision_number': 1,
      };
      await expectLater(
        fixture.repository.upload(_input(documentId: 'existing-document')),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      expect(fixture.rpc.workspaceReads, 0);
      expect(fixture.storage.uploads, 0);
      expect(fixture.finalizer.calls, isEmpty);
    },
  );

  test(
    'lost finalizer receipt is reconciled through the original prepared upload key',
    () async {
      final fixture = _Fixture();
      fixture.finalizer.response = null;
      await expectLater(
        fixture.repository.upload(_input()),
        throwsA(_domainCode(YorksV1DomainErrorCode.unexpectedResponse)),
      );
      final originalPayload = fixture.rpc.prepareCalls.single['p_payload'];
      // The server has finalized the first immutable upload despite the lost
      // response. Its retained prepare receipt is the retry authority.
      fixture.rpc.retainedReceipt = {
        'document_id': 'document-1',
        'document_version_id': 'version-1',
        'revision_number': 1,
      };
      expect(
        (await fixture.repository.upload(_input())).projectId,
        'project-1',
      );
      expect(fixture.rpc.prepareCalls.last['p_payload'], originalPayload);
      expect(
        fixture.rpc.prepareCalls
            .map((call) => call['p_idempotency_key'])
            .toSet(),
        {'reviewed-upload-key'},
      );
      expect(fixture.storage.uploads, 1);
      expect(fixture.finalizer.calls, ['intent-1']);
      expect(fixture.rpc.workspaceReads, 1);
    },
  );
}

Matcher _domainCode(YorksV1DomainErrorCode code) =>
    isA<YorksV1DomainException>().having((error) => error.code, 'code', code);

YorksV1DocumentUploadInput _input({String? documentId}) =>
    YorksV1DocumentUploadInput(
      projectId: 'project-1',
      entityType: YorksV1DocumentEntityType.project,
      entityId: 'project-1',
      classification: YorksV1DocumentClassification.operational,
      fileName: 'reviewed.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
      idempotencyKey: 'reviewed-upload-key',
      documentId: documentId,
    );

class _Fixture {
  _Fixture({AnalyticsService analytics = const NoopAnalyticsService()}) {
    repository = YorksV1SupabaseDocumentsRepository(
      featureFlags: const YorksV1FeatureFlags(
        foundation: true,
        projects: true,
        boq: true,
        excel: true,
        requests: true,
        arrangement: true,
        logistics: true,
        returnsDocuments: true,
        documents: true,
      ),
      connectivity: DefaultConnectivity(),
      rpcClient: rpc,
      storageClient: storage,
      finalizerClient: finalizer,
      analytics: analytics,
    );
  }
  final rpc = _Rpc();
  final storage = _Storage();
  final finalizer = _Finalizer();
  late final YorksV1SupabaseDocumentsRepository repository;
}

class _Rpc implements YorksV1MaterialRequestRpcClient {
  final prepareCalls = <Map<String, Object?>>[];
  int workspaceReads = 0;
  Object? error;
  String? finalizedDocumentId;
  String? finalizedVersionId;
  Map<String, Object?> retainedReceipt = const {};
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    if (error != null) throw error!;
    if (functionName == 'v1_prepare_document_upload') {
      prepareCalls.add(parameters);
      return {
        'upload_intent_id': 'intent-1',
        'bucket_id': 'v1-controlled-documents',
        'object_path': 'project/project-1/immutable.pdf',
        'mime_type': 'application/pdf',
        'byte_size': 3,
        'expires_at': '2026-10-04T09:30:00Z',
        'planned_revision_number': 1,
        'finalized_document_id': finalizedDocumentId,
        'finalized_version_id': finalizedVersionId,
        ...retainedReceipt,
      };
    }
    if (functionName == 'v1_document_workspace_projection') {
      workspaceReads++;
      return {
        'project_id': 'project-1',
        'documents': <Object?>[],
        'audit_entries': <Object?>[],
      };
    }
    throw StateError('Unexpected RPC $functionName');
  }
}

class _Storage implements YorksV1DocumentStorageClient {
  int uploads = 0;
  @override
  Future<Uint8List> download({
    required String bucketId,
    required String objectPath,
  }) async => Uint8List(0);
  @override
  Future<void> upload({
    required String bucketId,
    required String objectPath,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads++;
  }
}

class _Finalizer implements YorksV1DocumentFinalizerClient {
  Object? response = {
    'document_id': 'document-1',
    'document_version_id': 'version-1',
    'revision_number': 1,
  };
  final calls = <String>[];
  @override
  Future<Object?> finalize(String uploadIntentId) async {
    calls.add(uploadIntentId);
    return response;
  }
}

class _ThrowingAnalytics extends NoopAnalyticsService {
  const _ThrowingAnalytics({this.throwBegin = false});
  final bool throwBegin;
  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) => throw StateError('Telemetry unavailable');
  @override
  AnalyticsOperation beginOperation(
    String operation, {
    AnalyticsProperties properties = const {},
  }) {
    if (throwBegin) throw StateError('Telemetry unavailable');
    return _ThrowingOperation();
  }
}

class _ThrowingOperation implements AnalyticsOperation {
  @override
  void complete({
    bool cached = false,
    int? resultCount,
    AnalyticsProperties properties = const {},
  }) => throw StateError('Telemetry unavailable');
  @override
  void fail(Object error, {AnalyticsProperties properties = const {}}) =>
      throw StateError('Telemetry unavailable');
}

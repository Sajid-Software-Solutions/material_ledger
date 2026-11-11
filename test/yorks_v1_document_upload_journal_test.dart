import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_project_draft_storage_native.dart';
import 'package:material_ledger/shared/services/yorks_v1_document_upload_journal.dart';

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  YorksV1DocumentUploadJournal journal({
    String owner = 'owner',
    String backend = 'local',
  }) => YorksV1DocumentUploadJournal(
    storage: createProjectDraftAtomicStorage(preferences),
    backend: backend,
    owner: owner,
  );

  Future<String> acquire(
    YorksV1DocumentUploadJournal store,
    String key, {
    String hash = 'same-hash',
    String name = 'test.pdf',
  }) => store.acquire(
    input: _input(key, name: name),
    operation: 'v1_prepare_document_upload',
    contentHash: hash,
    payload: {
      'file_name': name,
      'sha256': hash,
      'business_reference': 'never-persist-this-commercial-value',
    },
  );

  test(
    'reload and competing callers share the original key and payload hash',
    () async {
      final keys = await Future.wait([
        acquire(journal(), 'key-1'),
        acquire(journal(), 'key-2'),
      ]);
      expect(keys, ['key-1', 'key-1']);
      expect(await acquire(journal(), 'key-3'), 'key-1');
      final pending = journal().pending('project');
      expect(pending.single['file_name'], 'test.pdf');
      expect(pending.single['byte_size'], 3);
      final raw = preferences.getString(preferences.getKeys().single)!;
      expect(raw, isNot(contains('never-persist-this-commercial-value')));
      expect(raw, isNot(contains('object_path')));
      expect(raw, isNot(contains('bytes')));
    },
  );
  test('a changed file cannot replace an unresolved upload intent', () async {
    await acquire(journal(), 'original');
    await expectLater(
      acquire(journal(), 'changed', hash: 'changed-content'),
      throwsA(
        isA<YorksV1DomainException>().having(
          (e) => e.code,
          'code',
          YorksV1DomainErrorCode.conflict,
        ),
      ),
    );
    expect(await acquire(journal(), 'retry'), 'original');
  });
  test('actor and backend isolation never adopts another upload key', () async {
    expect(await acquire(journal(), 'first'), 'first');
    expect(await acquire(journal(owner: 'other'), 'second'), 'second');
    expect(await acquire(journal(backend: 'staging'), 'third'), 'third');
    expect(journal(owner: 'none').pending('project'), isEmpty);
  });
  test('acknowledgement removes only the matching intent', () async {
    final store = journal();
    await acquire(store, 'first');
    await acquire(store, 'second', name: 'another.pdf');
    await store.confirm(
      input: _input('first'),
      operation: 'v1_prepare_document_upload',
      key: 'first',
    );
    expect(store.pending('project').single['key'], 'second');
    expect(await acquire(store, 'new-revision'), 'new-revision');
  });
  test('unknown journal fields survive later independent uploads', () async {
    await acquire(journal(), 'first');
    final key = preferences.getKeys().single;
    final value = jsonDecode(preferences.getString(key)!) as Map;
    value['unknown_future'] = {'keep': true};
    await preferences.setString(key, jsonEncode(value));
    await acquire(journal(), 'second', name: 'another.pdf');
    expect((jsonDecode(preferences.getString(key)!) as Map)['unknown_future'], {
      'keep': true,
    });
  });
  test(
    'corrupt metadata is preserved and blocks new transfer identities',
    () async {
      await acquire(journal(), 'first');
      final key = preferences.getKeys().single;
      await preferences.setString(key, '{not json');
      await expectLater(acquire(journal(), 'second'), throwsFormatException);
      expect(preferences.getString(key), '{not json');
    },
  );
}

YorksV1DocumentUploadInput _input(String key, {String name = 'test.pdf'}) =>
    YorksV1DocumentUploadInput(
      projectId: 'project',
      entityType: YorksV1DocumentEntityType.project,
      entityId: 'project',
      classification: YorksV1DocumentClassification.operational,
      fileName: name,
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
      idempotencyKey: key,
    );

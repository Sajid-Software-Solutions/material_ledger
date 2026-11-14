// Bulk upload: guessing whose file it is and which document it copies
// (PRODUCT_DECISIONS section 49). Every name and number is fictional.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/services/yorks_v1_bulk_attach.dart';

const _people = [
  BulkAttachOwner(
    id: 'p1',
    name: 'RAVI TEST KUMAR',
    codes: ['WR-000101'],
    documents: [
      BulkAttachDocument(
        id: 'p1-passport',
        kind: 'passport',
        number: 'TP1000001',
      ),
      BulkAttachDocument(id: 'p1-visa', kind: 'visa'),
      BulkAttachDocument(
        id: 'p1-eid',
        kind: 'emirates_id',
        number: '784199000000011',
      ),
      BulkAttachDocument(id: 'p1-visa-old', kind: 'visa', isCurrent: false),
    ],
  ),
  BulkAttachOwner(
    id: 'p2',
    name: 'MUHAMMAD ALI KHAN',
    codes: ['WR-000102'],
    documents: [BulkAttachDocument(id: 'p2-passport', kind: 'passport')],
  ),
  BulkAttachOwner(
    id: 'p3',
    name: 'MOHAMMED ALI RAZA',
    codes: ['WR-000103'],
    documents: [
      BulkAttachDocument(id: 'p3-cicpa-1', kind: 'cicpa_pass'),
      BulkAttachDocument(id: 'p3-cicpa-2', kind: 'cicpa_pass'),
    ],
  ),
];

BulkAttachGuess _guess(String name) =>
    bulkAttachGuess(name, _people, kinds: bulkAttachPeopleKinds);

void main() {
  group('people', () {
    test('a worker number names the person; a word names the document', () {
      final guess = _guess('WR-000101 Passport.pdf');
      expect(guess.by, BulkAttachBy.number);
      expect(guess.ownerId, 'p1');
      expect(guess.documentId, 'p1-passport');
      expect(
        _guess('wr 000101 visa.jpg').documentId,
        'p1-visa',
        reason: 'only the current visa',
      );
    });

    test('a document number names the person and the document', () {
      final guess = _guess('scan TP1000001.pdf');
      expect(guess.ownerId, 'p1');
      expect(guess.documentId, 'p1-passport');
      final eid = _guess('784-1990-0000001-1 front.jpg');
      expect(eid.ownerId, 'p1');
      expect(eid.documentId, 'p1-eid');
    });

    test('a name with at least two of its words', () {
      final guess = _guess('Ravi Kumar passport copy.PDF');
      expect(guess.by, BulkAttachBy.name);
      expect(guess.ownerId, 'p1');
      expect(guess.documentId, 'p1-passport');
      expect(
        _guess('Ravi passport.pdf').by,
        BulkAttachBy.none,
        reason: 'one word of a three-word name is not enough',
      );
    });

    test(
      'Muhammad is one name however it is spelt; ties are left to choose',
      () {
        expect(_guess('Mohd Ali Khan EID.jpg').ownerId, 'p2');
        expect(_guess('Mohd Ali Khan EID.jpg').kind, 'emirates_id');
        expect(_guess('Muhammad Ali visa.pdf').by, BulkAttachBy.ambiguous);
      },
    );

    test('a kind with more than one current document is left to choose', () {
      final guess = _guess('WR-000103 cicpa pass.pdf');
      expect(guess.ownerId, 'p3');
      expect(guess.kind, 'cicpa_pass');
      expect(guess.documentId, isNull);
    });

    test('nothing to go on', () {
      final guess = _guess('IMG_20261114_0012.jpg');
      expect(guess.by, BulkAttachBy.none);
      expect(guess.ownerId, isNull);
    });

    test('document words', () {
      for (final (name, kind) in [
        ('x labour card.pdf', 'labour_card'),
        ('x work permit.pdf', 'labour_card'),
        ('x ILOE.pdf', 'iloe'),
        ('x Emirates ID back.png', 'emirates_id'),
        ('x residence visa.pdf', 'visa'),
        ('x CMW.pdf', 'cmw_pass'),
        ('x photo.jpg', null),
      ]) {
        expect(bulkAttachKind(name, bulkAttachPeopleKinds), kind, reason: name);
      }
    });
  });

  group('company records', () {
    const records = [
      BulkAttachOwner(
        id: 'c1',
        name: 'EXAMPLE MAIN',
        codes: ['CN-0000001'],
        documents: [
          BulkAttachDocument(id: 'c1-licence', kind: 'licence'),
          BulkAttachDocument(id: 'c1-est', kind: 'establishment_card'),
        ],
      ),
      BulkAttachOwner(
        id: 'c2',
        name: 'TEST PICKUP 11111',
        codes: ['11111'],
        documents: [
          BulkAttachDocument(id: 'c2-reg', kind: 'registration'),
          BulkAttachDocument(id: 'c2-asateel', kind: 'asateel_permit'),
        ],
      ),
      BulkAttachOwner(
        id: 'c3',
        name: 'LOA 900001 · TEST PLANT',
        codes: ['900001'],
        documents: [BulkAttachDocument(id: 'c3-loa', kind: 'contract')],
      ),
    ];
    BulkAttachGuess guess(String name) =>
        bulkAttachGuess(name, records, kinds: bulkAttachCompanyKinds);

    test('licence numbers, plates and LOAs', () {
      expect(guess('CN-0000001 trade licence.pdf').documentId, 'c1-licence');
      expect(guess('Example Main establishment card.pdf').documentId, 'c1-est');
      expect(guess('11111 mulkiya.jpg').documentId, 'c2-reg');
      expect(guess('Pickup 11111 Asateel.jpg').documentId, 'c2-asateel');
      expect(guess('LOA 900001.pdf').documentId, 'c3-loa');
    });
  });
}

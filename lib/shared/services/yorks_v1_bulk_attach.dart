/// Bulk upload — guessing, from a file's name, whose file it is and which
/// of their documents it copies (PRODUCT_DECISIONS section 49).
///
/// "WR-000101 passport.pdf", "Ravi Kumar visa.jpg", "P1234567.pdf" or
/// "Pickup 11111 mulkiya.jpg" are matched to a person or company record by,
/// in order: one of its document numbers, one of its own numbers (worker
/// number, licence number, plate, LOA), then its name: the owner with the
/// most words of its name in the file name wins, with at least two words
/// (or the whole name when it is one word). A file that fits two owners
/// equally is left for the person uploading to choose. The document
/// comes from a matching document number, or from a word such as passport,
/// visa or mulkiya when the owner holds exactly one current document of that
/// kind. Nothing here is sent anywhere; every guess is shown and can be
/// changed before upload.
library;

/// One of an owner's documents.
final class BulkAttachDocument {
  const BulkAttachDocument({
    required this.id,
    required this.kind,
    this.number,
    this.isCurrent = true,
  });

  final String id;

  /// The wire value of the owner's document kind (e.g. `passport`).
  final String kind;
  final String? number;
  final bool isCurrent;
}

/// A person or a company record files can belong to.
final class BulkAttachOwner {
  const BulkAttachOwner({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.codes = const [],
    this.documents = const [],
  });

  final String id;
  final String name;

  /// Shown under the name when choosing (number, company, kind).
  final String subtitle;

  /// Numbers that name this owner: worker number, unified number, licence
  /// number, plate, LOA.
  final List<String> codes;
  final List<BulkAttachDocument> documents;
}

/// How an owner was found for a file.
enum BulkAttachBy {
  /// One of the owner's numbers or document numbers is in the name.
  number,

  /// Every word of the owner's name is in the name.
  name,

  /// More than one owner fits; the person uploading chooses.
  ambiguous,

  /// Nothing fits.
  none,
}

/// The guess for one file.
final class BulkAttachGuess {
  const BulkAttachGuess({
    required this.by,
    this.ownerId,
    this.documentId,
    this.kind,
  });

  final BulkAttachBy by;
  final String? ownerId;
  final String? documentId;

  /// The document kind named in the file, if any.
  final String? kind;
}

/// Words that name each People document kind, most specific first.
const bulkAttachPeopleKinds = <String, List<String>>{
  'cicpa_pass': ['cicpa'],
  'cmw_pass': ['cmw'],
  'iloe': ['iloe', 'unemployment insurance', 'unemployment'],
  'labour_card': [
    'labour card',
    'labor card',
    'labourcard',
    'laborcard',
    'work permit',
    'workpermit',
  ],
  'emirates_id': [
    'emirates id',
    'emirate id',
    'emiratesid',
    'eid',
    'id card',
    'idcard',
  ],
  'passport': ['passport', 'pasport', 'passprt'],
  'visa': ['visa', 'residence', 'residency', 'entry permit'],
};

/// Words that name each Company document kind, most specific first.
const bulkAttachCompanyKinds = <String, List<String>>{
  'asateel_permit': ['asateel'],
  'cicpa_pass': ['cicpa', 'gate pass'],
  'establishment_card': [
    'establishment card',
    'establishment',
    'immigration card',
  ],
  'labour_file': ['labour file', 'labor file', 'mohre file'],
  'pro_card': ['pro card', 'procard'],
  'registration': [
    'mulkiya',
    'mulkia',
    'vehicle registration',
    'registration card',
    'registration',
  ],
  'insurance': ['insurance', 'policy'],
  'contract': ['loa', 'contract'],
  'licence': ['trade licence', 'trade license', 'licence', 'license'],
  'certificate': [
    'certificate',
    'civil defence',
    'civil defense',
    'iso',
    'icv',
  ],
};

final _extension = RegExp(r'\.[a-z0-9]{1,5}$');
final _nonWord = RegExp(r'[^a-z0-9]+');
final _muhammad = RegExp(
  r'^(mohammed|mohammad|mohamed|mohamad|muhamad|muhammed|mohd|md|mhd)$',
);

String _foldAccents(String text) {
  const from = 'àáâãäåèéêëìíîïòóôõöùúûüýÿñç';
  const to = 'aaaaaaeeeeiiiiooooouuuuyync';
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

/// Lower-case words of a file or owner name, without the extension, with
/// the common spellings of Muhammad made one.
List<String> bulkAttachWords(String text) {
  final plain = _foldAccents(
    text.toLowerCase(),
  ).replaceFirst(_extension, '').replaceAll(_nonWord, ' ').trim();
  if (plain.isEmpty) return const [];
  return [
    for (final word in plain.split(' '))
      if (word.isNotEmpty) _muhammad.hasMatch(word) ? 'muhammad' : word,
  ];
}

/// Letters and digits only: "WR-000101" and "wr 000101" are the same code.
String _compact(String text) =>
    _foldAccents(text.toLowerCase()).replaceAll(_nonWord, '');

/// Every run of one to five neighbouring words, joined: an Emirates ID
/// written "784-1990-1234567-8" or a visa "201/2024/7/123456" is one code.
Set<String> _spans(List<String> words) => {
  for (var start = 0; start < words.length; start++)
    for (var end = start + 1; end <= words.length && end <= start + 5; end++)
      words.sublist(start, end).join(),
};

bool _hasPhrase(List<String> words, String phrase) {
  final target = bulkAttachWords(phrase);
  if (target.isEmpty || target.length > words.length) return false;
  for (var start = 0; start + target.length <= words.length; start++) {
    var all = true;
    for (var i = 0; i < target.length; i++) {
      if (words[start + i] != target[i]) {
        all = false;
        break;
      }
    }
    if (all) return true;
  }
  return false;
}

/// The document kind a file names, if any.
String? bulkAttachKind(String fileName, Map<String, List<String>> kinds) {
  final words = bulkAttachWords(fileName);
  for (final MapEntry(key: kind, value: phrases) in kinds.entries) {
    if (phrases.any((phrase) => _hasPhrase(words, phrase))) return kind;
  }
  return null;
}

/// Guesses whose file [fileName] is and which document it copies.
BulkAttachGuess bulkAttachGuess(
  String fileName,
  List<BulkAttachOwner> owners, {
  required Map<String, List<String>> kinds,
}) {
  final words = bulkAttachWords(fileName);
  final spans = _spans(words);
  final kind = bulkAttachKind(fileName, kinds);

  // 1. A document number, then an owner number.
  for (final owner in owners) {
    for (final document in owner.documents) {
      final number = document.number;
      if (number == null) continue;
      final code = _compact(number);
      if (code.length >= 5 && spans.contains(code)) {
        return BulkAttachGuess(
          by: BulkAttachBy.number,
          ownerId: owner.id,
          documentId: document.id,
          kind: document.kind,
        );
      }
    }
  }
  final byCode = [
    for (final owner in owners)
      if (owner.codes.any((code) {
        final compact = _compact(code);
        return compact.length >= 4 && spans.contains(compact);
      }))
        owner,
  ];
  if (byCode.length == 1) {
    return _withDocument(byCode.single, BulkAttachBy.number, kind);
  }
  if (byCode.length > 1) {
    return BulkAttachGuess(by: BulkAttachBy.ambiguous, kind: kind);
  }

  // 2. The name: most words present wins (at least two, or the whole of a
  // one-word name); a tie is ambiguous.
  final present = words.toSet();
  var best = 0;
  final fits = <BulkAttachOwner>[];
  for (final owner in owners) {
    final name = {
      for (final word in bulkAttachWords(owner.name))
        if (word.length > 1) word,
    };
    if (name.isEmpty) continue;
    final score = name.where(present.contains).length;
    final enough = name.length == 1 ? score == 1 : score >= 2;
    if (!enough) continue;
    if (score > best) {
      best = score;
      fits
        ..clear()
        ..add(owner);
    } else if (score == best) {
      fits.add(owner);
    }
  }
  if (fits.length == 1) {
    return _withDocument(fits.single, BulkAttachBy.name, kind);
  }
  if (fits.length > 1) {
    return BulkAttachGuess(by: BulkAttachBy.ambiguous, kind: kind);
  }
  return BulkAttachGuess(by: BulkAttachBy.none, kind: kind);
}

BulkAttachGuess _withDocument(
  BulkAttachOwner owner,
  BulkAttachBy by,
  String? kind,
) => BulkAttachGuess(
  by: by,
  ownerId: owner.id,
  kind: kind,
  documentId: kind == null ? null : bulkAttachDocumentFor(owner, kind),
);

/// The owner's one current document of [kind], or null when there is none
/// or more than one.
String? bulkAttachDocumentFor(BulkAttachOwner owner, String kind) {
  final current = [
    for (final document in owner.documents)
      if (document.kind == kind && document.isCurrent) document,
  ];
  return current.length == 1 ? current.single.id : null;
}

/// Workforce attendance V2 — names and projects that forgive spelling.
///
/// "oheed" finds Oheedullah, "mohd" finds Muhammad, "swehan 321" finds
/// SWEIHAN 321. Same rules as the approved prototype.
library;

final _nonWord = RegExp(r'[^a-z0-9 ]');
final _muhammad = RegExp(
  r'\b(mohammed|mohammad|mohamed|mohamad|muhamad|mohd|md|muhammed)\b',
);
final _ullah = RegExp(r'ul+ah?\b');
final _sweihan = RegExp(r'\b(sweihan|swehan|suwaihan|swihan)\b');
final _spaces = RegExp(r'\s+');

/// Lower-case, accent-free, with common spellings made the same.
String attendanceCanon(String input) {
  var text = input.toLowerCase();
  text = _stripAccents(text);
  text = text.replaceAll(_nonWord, ' ');
  text = text.replaceAll(_muhammad, 'muhammad');
  text = text.replaceAll(_ullah, 'ullah');
  text = text.replaceAll(_sweihan, 'sweihan');
  return text.replaceAll(_spaces, ' ').trim();
}

String _stripAccents(String text) {
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

/// Edit distance between two short strings.
int attendanceLevenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

/// One search hit. [score] 0 is a prefix match, 1 a contained match, 2 or
/// more a spelling correction.
final class AttendanceSearchHit<T> {
  const AttendanceSearchHit(this.item, this.score);

  final T item;
  final int score;

  /// Shown as "Did you mean …?" when the best hit is a correction.
  bool get isCorrection => score >= 2;
}

/// Up to [limit] items matching [query], best first.
List<AttendanceSearchHit<T>> attendanceFuzzySearch<T>(
  String query,
  Iterable<T> items,
  String Function(T item) key, {
  int limit = 6,
}) {
  final q = attendanceCanon(query);
  if (q.isEmpty) return const [];
  final flatQuery = q.replaceAll(' ', '');
  final hits = <AttendanceSearchHit<T>>[];
  for (final item in items) {
    final name = attendanceCanon(key(item));
    if (name.isEmpty) continue;
    final flatName = name.replaceAll(' ', '');
    final words = name.split(' ');
    int score;
    if (flatName.startsWith(flatQuery) ||
        words.any((word) => word.startsWith(q))) {
      score = 0;
    } else if (flatName.contains(flatQuery)) {
      score = 1;
    } else {
      var best = attendanceLevenshtein(
        flatQuery,
        flatName.substring(
          0,
          flatQuery.length < flatName.length
              ? flatQuery.length
              : flatName.length,
        ),
      );
      for (final word in words) {
        final prefix = word.length < q.length
            ? word
            : word.substring(0, q.length);
        final distance = attendanceLevenshtein(q, prefix);
        if (distance < best) best = distance;
      }
      final allowed = (q.length ~/ 4) < 1 ? 1 : q.length ~/ 4;
      if (best > allowed) continue;
      score = 2 + best;
    }
    hits.add(AttendanceSearchHit(item, score));
  }
  hits.sort((a, b) => a.score.compareTo(b.score));
  return hits.take(limit).toList(growable: false);
}

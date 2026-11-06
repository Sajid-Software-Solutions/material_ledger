/// Exact decimal value used by the R39 Accounts client boundary.
///
/// PostgreSQL `numeric` remains authoritative. The client accepts numeric
/// values only as decimal strings, never as JSON numbers, so a binary Dart
/// `double` can neither round a commercial value nor affect a comparison.
final class YorksAccountsDecimal implements Comparable<YorksAccountsDecimal> {
  const YorksAccountsDecimal._(this._coefficient, this._scale);

  // Fraction digits are not capped at a display precision: unrounded Postgres
  // numerics such as a stage value of 429800.000000000000 must parse exactly.
  // Command inputs enforce their own limits through `fractionDigits`.
  static final RegExp _pattern = RegExp(
    r'^([+-]?)(\d{1,30})(?:\.(\d{1,30}))?$',
  );

  final BigInt _coefficient;
  final int _scale;

  static final zero = YorksAccountsDecimal._(BigInt.zero, 0);
  static final hundred = YorksAccountsDecimal._(BigInt.from(100), 0);

  static YorksAccountsDecimal? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    final coefficient = BigInt.tryParse('$whole$fraction');
    if (coefficient == null) return null;
    final signed = match.group(1) == '-' ? -coefficient : coefficient;
    return _normalize(signed, fraction.length);
  }

  factory YorksAccountsDecimal.parse(String raw) {
    final value = tryParse(raw);
    if (value == null) {
      throw FormatException('Invalid exact decimal value.', raw);
    }
    return value;
  }

  /// Parses an RPC field and deliberately rejects `num`/`double` values.
  static YorksAccountsDecimal fromRpcValue(Object? raw, {required String key}) {
    if (raw is! String) {
      throw FormatException('$key must be a decimal string.', raw);
    }
    final value = tryParse(raw);
    if (value == null) {
      throw FormatException('$key is not a valid decimal string.', raw);
    }
    return value;
  }

  bool get isZero => _coefficient == BigInt.zero;
  bool get isPositive => _coefficient > BigInt.zero;
  bool get isNegative => _coefficient < BigInt.zero;
  int get fractionDigits => _scale;

  YorksAccountsDecimal operator +(YorksAccountsDecimal other) {
    final aligned = _align(other);
    return _normalize(aligned.$1 + aligned.$2, aligned.$3);
  }

  YorksAccountsDecimal operator -(YorksAccountsDecimal other) {
    final aligned = _align(other);
    return _normalize(aligned.$1 - aligned.$2, aligned.$3);
  }

  @override
  int compareTo(YorksAccountsDecimal other) {
    final aligned = _align(other);
    return aligned.$1.compareTo(aligned.$2);
  }

  String get canonicalText {
    if (_scale == 0) return _coefficient.toString();
    final negative = _coefficient.isNegative;
    final digits = _coefficient.abs().toString().padLeft(_scale + 1, '0');
    final split = digits.length - _scale;
    final value = '${digits.substring(0, split)}.${digits.substring(split)}';
    return negative ? '-$value' : value;
  }

  /// Presentation-safe decimal text with no unnecessary trailing zeroes.
  ///
  /// Exact PostgreSQL numeric values remain unchanged for commands and
  /// comparisons. This method only rounds their visible representation when a
  /// screen needs a bounded number of fractional digits.
  String displayText({int maximumFractionDigits = 4}) {
    if (maximumFractionDigits < 0 || maximumFractionDigits > 8) {
      throw RangeError.range(maximumFractionDigits, 0, 8);
    }
    if (_scale <= maximumFractionDigits) return canonicalText;

    final divisor = _powerOfTen(_scale - maximumFractionDigits);
    final absolute = _coefficient.abs();
    var rounded = absolute ~/ divisor;
    if ((absolute % divisor) * BigInt.from(2) >= divisor) {
      rounded += BigInt.one;
    }
    final signed = _coefficient.isNegative ? -rounded : rounded;
    return _normalize(signed, maximumFractionDigits).canonicalText;
  }

  /// Safe value to send as a PostgreSQL numeric RPC parameter.
  String get postgresText => canonicalText;

  (BigInt, BigInt, int) _align(YorksAccountsDecimal other) {
    final scale = _scale > other._scale ? _scale : other._scale;
    return (
      _coefficient * _powerOfTen(scale - _scale),
      other._coefficient * _powerOfTen(scale - other._scale),
      scale,
    );
  }

  static YorksAccountsDecimal _normalize(BigInt coefficient, int scale) {
    var normalized = coefficient;
    var normalizedScale = scale;
    while (normalizedScale > 0 && normalized % BigInt.from(10) == BigInt.zero) {
      normalized ~/= BigInt.from(10);
      normalizedScale--;
    }
    return YorksAccountsDecimal._(normalized, normalizedScale);
  }

  static BigInt _powerOfTen(int exponent) {
    var value = BigInt.one;
    for (var i = 0; i < exponent; i++) {
      value *= BigInt.from(10);
    }
    return value;
  }

  @override
  String toString() => canonicalText;

  @override
  bool operator ==(Object other) =>
      other is YorksAccountsDecimal && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(_coefficient, _scale);
}

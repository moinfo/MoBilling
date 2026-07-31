/// Tolerant readers for the MoBilling API's JSON.
///
/// The portal endpoints build their responses by hand inside `->map()` closures
/// rather than through API Resources, so field types are inconsistent in ways
/// that are invisible until they crash a client:
///
///   * `(float) $doc->total` yields a JSON number, but an uncast
///     `->sum('total')` on a decimal column yields a *string* — both appear in
///     the same dashboard payload (`PortalDashboardController`).
///   * Laravel casts `decimal:2` model attributes to strings on serialisation,
///     so `amount` is `"1500.00"` on some endpoints and `1500.0` on others.
///   * Nullable relations serialise as absent, null, or `{}` depending on
///     whether `unsetRelation` ran.
///
/// Strict casts (`json['x'] as double`) would throw on any of those. These
/// helpers coerce instead, because a dashboard that renders 0.00 for one field
/// beats a screen that fails to build at all.
extension JsonMap on Map<String, dynamic> {
  /// A number that may arrive as num, decimal string, or null.
  double money(String key, {double fallback = 0}) =>
      readDouble(this[key], fallback: fallback);

  /// A count that may arrive as int, numeric string, or null.
  int count(String key, {int fallback = 0}) =>
      readInt(this[key], fallback: fallback);

  /// A string that may be absent or null.
  String? str(String key) {
    final value = this[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  /// A required string, falling back rather than throwing on absence.
  String strOr(String key, String fallback) => str(key) ?? fallback;

  /// An ID. UUIDs everywhere, but stringify defensively — legacy_id columns
  /// exist and integers do occasionally surface.
  String id([String key = 'id']) => this[key]?.toString() ?? '';

  bool flag(String key, {bool fallback = false}) => switch (this[key]) {
        bool v => v,
        // Laravel booleans survive as 1/0 through some hand-built arrays.
        num v => v != 0,
        'true' || '1' => true,
        'false' || '0' => false,
        _ => fallback,
      };

  DateTime? date(String key) => readDate(this[key]);

  /// A nested object, or null when absent/blank. Treats `{}` as absent, which
  /// is what an unset relation looks like.
  Map<String, dynamic>? object(String key) {
    final value = this[key];
    if (value is! Map || value.isEmpty) return null;
    return Map<String, dynamic>.from(value);
  }

  /// A nested list, mapped through [fromJson]. Missing or malformed lists yield
  /// an empty list — a dashboard widget with nothing in it is a valid state.
  List<T> list<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final value = this[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// A nested list of plain strings.
  List<String> strings(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return value.map((e) => e.toString()).toList();
  }
}

double readDouble(Object? value, {double fallback = 0}) => switch (value) {
      num v when v.isFinite => v.toDouble(),
      String v => double.tryParse(v.trim()) ?? fallback,
      _ => fallback,
    };

int readInt(Object? value, {int fallback = 0}) => switch (value) {
      int v => v,
      num v when v.isFinite => v.toInt(),
      String v => int.tryParse(v.trim()) ?? _fromDecimalString(v, fallback),
      _ => fallback,
    };

int _fromDecimalString(String value, int fallback) {
  final parsed = double.tryParse(value.trim());
  return parsed == null ? fallback : parsed.toInt();
}

/// ISO-8601 from `toISOString()`, plain `Y-m-d` from date-only columns, and
/// MySQL's `Y-m-d H:i:s` all appear. Anything unparseable yields null so the UI
/// can show a placeholder.
DateTime? readDate(Object? value) => switch (value) {
      DateTime v => v,
      String v when v.trim().isNotEmpty =>
        DateTime.tryParse(v.trim().replaceFirst(' ', 'T')),
      _ => null,
    };

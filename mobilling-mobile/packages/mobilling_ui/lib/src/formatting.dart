import 'package:intl/intl.dart';

/// Money and date formatting, deliberately identical to the web client so the
/// same invoice never renders differently on the two platforms.
///
/// Mirrors `mobilling-ui/src/utils/formatCurrency.ts` and `formatDate.ts`.
class Formatting {
  Formatting._();

  /// Currency is a tenant-level setting (`tenants.currency`), not a platform
  /// constant. TZS is the fallback, matching both the web default and
  /// `config/pesapal.php`.
  static const String defaultCurrency = 'TZS';

  static String _tenantCurrency = defaultCurrency;

  /// Set once from the tenant on the login response. The web client does the
  /// same via `setTenantCurrency`.
  static void setTenantCurrency(String? currency) {
    _tenantCurrency = (currency == null || currency.isEmpty)
        ? defaultCurrency
        : currency;
  }

  static String get tenantCurrency => _tenantCurrency;

  static final NumberFormat _amount = NumberFormat('#,##0.00', 'en_US');

  /// `TZS 1,234.56`.
  ///
  /// Accepts num or String because the API is inconsistent: totals arrive as
  /// numbers on some endpoints and as decimal strings on others (Laravel casts
  /// `decimal` columns to strings). Null and unparseable values render as zero
  /// rather than throwing — dashboards legitimately omit fields the caller may
  /// not see, and a crash there would be worse than a 0.00.
  static String currency(Object? amount, {String? currencyCode}) {
    final code = currencyCode ?? _tenantCurrency;
    return '$code ${_amount.format(_toDouble(amount))}';
  }

  /// The bare number, no currency code — for table columns that carry the
  /// currency in the header instead of on every row.
  static String amount(Object? value) => _amount.format(_toDouble(value));

  static double _toDouble(Object? value) => switch (value) {
        num v when v.isFinite => v.toDouble(),
        String v => double.tryParse(v) ?? 0,
        _ => 0,
      };

  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, HH:mm');

  /// `29 Jul 2026`, matching the web's `DD MMM YYYY`.
  static String date(Object? value) {
    final parsed = parseDate(value);
    return parsed == null ? '—' : _date.format(parsed);
  }

  /// `29 Jul 2026, 14:30`.
  static String dateTime(Object? value) {
    final parsed = parseDate(value);
    return parsed == null ? '—' : _dateTime.format(parsed.toLocal());
  }

  /// Laravel serialises dates as ISO-8601, but plain `Y-m-d` also appears on
  /// date-only columns like `due_date`. Both parse; anything else yields null
  /// so callers can render a placeholder instead of crashing.
  static DateTime? parseDate(Object? value) => switch (value) {
        DateTime v => v,
        String v when v.isNotEmpty => DateTime.tryParse(v),
        _ => null,
      };

  /// Days until [value]; negative once past. Null when undated.
  static int? daysUntil(Object? value) {
    final parsed = parseDate(value);
    if (parsed == null) return null;
    final now = DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  /// Human phrasing for a due date — the single most-read string in a billing
  /// app, so it is worth getting the near cases right rather than printing a
  /// raw date and making the reader do the arithmetic.
  static String dueDescription(Object? value) {
    final days = daysUntil(value);
    if (days == null) return 'No due date';
    return switch (days) {
      0 => 'Due today',
      1 => 'Due tomorrow',
      -1 => 'Overdue by 1 day',
      < 0 => 'Overdue by ${-days} days',
      _ => 'Due in $days days',
    };
  }
}

import '../api_client.dart';
import 'reports_models.dart';

/// The thirteen staff reports.
///
/// One dispatch method rather than thirteen public ones: the screens are
/// driven by [ReportSpec], so they need to fetch "whatever report this slug
/// names". The per-report parsing still happens in a typed factory.
class ReportsService {
  const ReportsService(this._api);

  final ApiClient _api;

  /// Fetch and parse one report.
  ///
  /// [from]/[to] are Y-m-d and ignored by the point-in-time reports;
  /// [clientId] is only used by the client statement.
  Future<ReportResult> fetch(
    String slug, {
    String? from,
    String? to,
    String? clientId,
  }) async {
    final (path, parser) = _endpointFor(slug);

    final body = await _api.get<Map<String, dynamic>>(
      path,
      query: {
        'start_date': from,
        'end_date': to,
        'date_from': from,
        'date_to': to,
        'client_id': clientId,
      },
    );
    return parser(body);
  }

  /// Maps a spec slug to its endpoint and typed parser. Kept in one place so
  /// a new report is a single entry here plus a [ReportSpec].
  (String, ReportResult Function(Map<String, dynamic>)) _endpointFor(
      String slug) {
    return switch (slug) {
      'revenue' => ('/reports/revenue-summary', ReportResult.revenueSummary),
      'aging' => ('/reports/outstanding-aging', ReportResult.outstandingAging),
      'client-statement' => (
          '/reports/client-statement',
          ReportResult.clientStatement
        ),
      'payment-collection' => (
          '/reports/payment-collection',
          ReportResult.paymentCollection
        ),
      'expenses' => ('/reports/expense-report', ReportResult.expenseReport),
      'profit-loss' => ('/reports/profit-loss', ReportResult.profitLoss),
      'statutory' => (
          '/reports/statutory-compliance',
          ReportResult.statutoryCompliance
        ),
      'subscriptions' => (
          '/reports/subscription-report',
          ReportResult.subscriptionReport
        ),
      'collection-effectiveness' => (
          '/reports/collection-effectiveness',
          ReportResult.collectionEffectiveness
        ),
      'satisfaction-calls' => (
          '/reports/satisfaction-calls',
          ReportResult.satisfaction
        ),
      'communication-log' => (
          '/reports/communication-log',
          ReportResult.communicationLog
        ),
      'system-records' => (
          '/reports/system-records-report',
          ReportResult.systemRecords
        ),
      'system-verifications' => (
          '/reports/system-verifications-report',
          ReportResult.systemVerifications
        ),
      _ => throw ArgumentError('Unknown report: $slug'),
    };
  }
}

/// The thirteen staff reports.
///
/// Each report has a genuinely different payload, but every one of them is
/// "some headline numbers plus a list of detail rows". Rather than thirteen
/// bespoke screens, each report gets a typed factory that knows its *real*
/// field names and folds them into [ReportResult] — so parsing stays faithful
/// to the API while rendering goes through one path.
///
/// Note which reports accept a date range: aging, statutory compliance and the
/// subscription report are point-in-time and take no parameters at all.
library;

import '../json.dart';

/// A headline figure.
class ReportMetric {
  const ReportMetric({
    required this.label,
    required this.value,
    this.isMoney = false,
    this.tone = MetricTone.neutral,
  });

  final String label;
  final double value;

  /// Render through the tenant currency rather than as a bare number.
  final bool isMoney;
  final MetricTone tone;

  /// Percentages arrive as 0–100 from the API, not 0–1.
  static ReportMetric percent(String label, double value,
          {MetricTone tone = MetricTone.neutral}) =>
      ReportMetric(label: label, value: value, tone: tone);
}

enum MetricTone { neutral, good, warn, bad }

/// One detail row.
class ReportRow {
  const ReportRow({
    required this.title,
    this.subtitle,
    this.amount,
    this.status,
    this.count,
  });

  final String title;
  final String? subtitle;
  final double? amount;

  /// Rendered as a status chip when present.
  final String? status;

  /// Shown instead of [amount] for count-based reports.
  final int? count;
}

/// A parsed report: headline metrics plus detail rows.
class ReportResult {
  const ReportResult({
    required this.metrics,
    required this.rows,
    this.rowsLabel = 'Details',
    this.percentSuffixLabels = const {},
  });

  final List<ReportMetric> metrics;
  final List<ReportRow> rows;
  final String rowsLabel;

  /// Metric labels whose value should render with a '%' suffix.
  final Set<String> percentSuffixLabels;

  bool get isEmpty => metrics.isEmpty && rows.isEmpty;

  // -------------------------------------------------------------------------
  // 1. Revenue summary
  // -------------------------------------------------------------------------
  factory ReportResult.revenueSummary(Map<String, dynamic> json) {
    final growth = json['revenue_growth'];
    return ReportResult(
      rowsLabel: 'Invoices',
      percentSuffixLabels: const {'Collection rate', 'Growth'},
      metrics: [
        ReportMetric(
            label: 'Invoiced',
            value: json.money('total_invoiced'),
            isMoney: true),
        ReportMetric(
            label: 'Collected',
            value: json.money('total_collected'),
            isMoney: true,
            tone: MetricTone.good),
        ReportMetric.percent('Collection rate', json.money('collection_rate')),
        if (growth != null)
          ReportMetric.percent('Growth', readDouble(growth),
              tone: readDouble(growth) >= 0
                  ? MetricTone.good
                  : MetricTone.bad),
      ],
      rows: json.list('invoices', (row) {
        final client = row.object('client');
        return ReportRow(
          title: client?.str('name') ??
              row.str('client_name') ??
              row.strOr('document_number', '—'),
          subtitle: [
            row.strOr('document_number', ''),
            if (row.date('date') != null) _d(row.date('date')),
          ].where((s) => s.isNotEmpty).join(' · '),
          amount: row.money('total'),
          status: row.str('status'),
        );
      }),
    );
  }

  // -------------------------------------------------------------------------
  // 2. Outstanding & ageing
  // -------------------------------------------------------------------------
  factory ReportResult.outstandingAging(Map<String, dynamic> json) {
    // band_totals is a map of band name -> amount; bands is band -> invoices.
    final bandTotals = json.object('band_totals') ?? const {};
    final bands = json.object('bands') ?? const {};

    final rows = <ReportRow>[];
    bands.forEach((band, invoices) {
      if (invoices is! List) return;
      for (final raw in invoices.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        rows.add(ReportRow(
          title: row.object('client')?.str('name') ??
              row.strOr('client_name', row.strOr('document_number', '—')),
          subtitle: [
            band,
            row.strOr('document_number', ''),
            if (row['days_overdue'] != null)
              '${row.count('days_overdue')}d overdue',
          ].where((s) => s.isNotEmpty).join(' · '),
          // Aging rows carry `balance` (total − paid); `balance_due` is the
          // document-detail spelling.
          amount: row['balance'] != null
              ? row.money('balance')
              : row['balance_due'] != null
                  ? row.money('balance_due')
                  : row.money('total'),
          status: row.str('status'),
        ));
      }
    });

    return ReportResult(
      rowsLabel: 'Outstanding invoices',
      metrics: [
        ReportMetric(
            label: 'Outstanding',
            value: json.money('total_outstanding'),
            isMoney: true,
            tone: MetricTone.bad),
        ReportMetric(
            label: 'Invoices', value: json.count('total_invoices').toDouble()),
        for (final entry in bandTotals.entries)
          ReportMetric(
            label: entry.key,
            value: readDouble(entry.value),
            isMoney: true,
          ),
      ],
      rows: rows,
    );
  }

  // -------------------------------------------------------------------------
  // 3. Client statement
  // -------------------------------------------------------------------------
  factory ReportResult.clientStatement(Map<String, dynamic> json) =>
      ReportResult(
        rowsLabel: 'Ledger',
        metrics: [
          ReportMetric(
              label: 'Debits',
              value: json.money('total_debit'),
              isMoney: true),
          ReportMetric(
              label: 'Credits',
              value: json.money('total_credit'),
              isMoney: true,
              tone: MetricTone.good),
          ReportMetric(
            label: 'Balance',
            value: json.money('closing_balance', fallback: json.money('balance')),
            isMoney: true,
            tone: MetricTone.warn,
          ),
        ],
        rows: json.list('entries', (row) {
          final debit = row.money('debit');
          final credit = row.money('credit');
          // Statement entries are `{date, type, reference, debit, credit,
          // balance}` — the type ("invoice" / "payment") is the title.
          final type = row.strOr('type', '');
          return ReportRow(
            title: row.str('description') ??
                (type.isEmpty
                    ? '—'
                    : '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}'),
            subtitle: [
              if (row.date('date') != null) _d(row.date('date')),
              row.strOr('reference', ''),
            ].where((s) => s.isNotEmpty).join(' · '),
            amount: credit > 0 ? -credit : debit,
          );
        }),
      );

  // -------------------------------------------------------------------------
  // 4. Payment collection
  // -------------------------------------------------------------------------
  factory ReportResult.paymentCollection(Map<String, dynamic> json) =>
      ReportResult(
        rowsLabel: 'Payments',
        metrics: [
          ReportMetric(
              label: 'Collected',
              value: json.money('total_collected'),
              isMoney: true,
              tone: MetricTone.good),
          ReportMetric(
              label: 'Transactions',
              value: json.count('total_transactions').toDouble()),
          for (final method in json.list('by_method', (m) => m))
            ReportMetric(
              label: method.strOr('payment_method', method.strOr('method', '—')),
              value: method.money('total', fallback: method.money('amount')),
              isMoney: true,
            ),
        ],
        rows: json.list('payments', (row) => ReportRow(
              title: row.object('client')?.str('name') ??
                  row.strOr('client_name', 'Payment'),
              subtitle: [
                if (row.date('payment_date') != null)
                  _d(row.date('payment_date')),
                row.strOr('payment_method', ''),
                row.strOr('reference', ''),
              ].where((s) => s.isNotEmpty).join(' · '),
              amount: row.money('amount'),
            )),
      );

  // -------------------------------------------------------------------------
  // 5. Expense report
  // -------------------------------------------------------------------------
  factory ReportResult.expenseReport(Map<String, dynamic> json) =>
      ReportResult(
        rowsLabel: 'Expenses',
        metrics: [
          ReportMetric(
              label: 'Total expenses',
              value: json.money('total_expenses'),
              isMoney: true,
              tone: MetricTone.warn),
          for (final category in json.list('by_category', (c) => c))
            ReportMetric(
              label: category.strOr('name', category.strOr('category', '—')),
              value: category.money('total', fallback: category.money('amount')),
              isMoney: true,
            ),
        ],
        rows: json.list('expenses', (row) => ReportRow(
              title: row.strOr('description', '—'),
              subtitle: [
                if (row.date('expense_date') != null)
                  _d(row.date('expense_date')),
                row.strOr('category', ''),
                row.strOr('payment_method', ''),
              ].where((s) => s.isNotEmpty).join(' · '),
              amount: row.money('amount'),
            )),
      );

  // -------------------------------------------------------------------------
  // 6. Profit & loss
  // -------------------------------------------------------------------------
  factory ReportResult.profitLoss(Map<String, dynamic> json) {
    final net = json.money('net_profit');
    return ReportResult(
      rowsLabel: 'Entries',
      percentSuffixLabels: const {'Margin'},
      metrics: [
        ReportMetric(
            label: 'Revenue', value: json.money('revenue'), isMoney: true),
        ReportMetric(
            label: 'Expenses',
            value: json.money('expenses'),
            isMoney: true,
            tone: MetricTone.warn),
        ReportMetric(
            label: 'Bill payments',
            value: json.money('bill_payments'),
            isMoney: true),
        ReportMetric(
          label: 'Net profit',
          value: net,
          isMoney: true,
          tone: net >= 0 ? MetricTone.good : MetricTone.bad,
        ),
        ReportMetric.percent('Margin', json.money('profit_margin'),
            tone: net >= 0 ? MetricTone.good : MetricTone.bad),
      ],
      rows: json.list('entries', (row) => ReportRow(
            title: row.strOr('description', row.strOr('label', '—')),
            subtitle: [
              if (row.date('date') != null) _d(row.date('date')),
              row.strOr('type', ''),
            ].where((s) => s.isNotEmpty).join(' · '),
            amount: row.money('amount'),
          )),
    );
  }

  // -------------------------------------------------------------------------
  // 7. Statutory compliance
  // -------------------------------------------------------------------------
  factory ReportResult.statutoryCompliance(Map<String, dynamic> json) {
    final summary = json.object('summary') ?? const {};
    return ReportResult(
      rowsLabel: 'Obligations',
      percentSuffixLabels: const {'Compliance rate'},
      metrics: [
        ReportMetric(
            label: 'Active', value: summary.count('total_active').toDouble()),
        ReportMetric(
            label: 'Overdue',
            value: summary.count('overdue').toDouble(),
            tone: MetricTone.bad),
        ReportMetric(
            label: 'Due soon',
            value: summary.count('due_soon').toDouble(),
            tone: MetricTone.warn),
        ReportMetric.percent(
            'Compliance rate', summary.money('compliance_rate'),
            tone: MetricTone.good),
      ],
      rows: json.list('obligations', (row) => ReportRow(
            title: row.strOr('name', '—'),
            subtitle: [
              if (row.date('next_due_date') != null)
                'due ${_d(row.date('next_due_date'))}',
              row.strOr('cycle', ''),
            ].where((s) => s.isNotEmpty).join(' · '),
            amount: row.money('amount'),
            status: row.str('status'),
          )),
    );
  }

  // -------------------------------------------------------------------------
  // 8. Subscription report
  // -------------------------------------------------------------------------
  factory ReportResult.subscriptionReport(Map<String, dynamic> json) {
    final byStatus = json.object('by_status') ?? const {};
    return ReportResult(
      rowsLabel: 'Upcoming renewals',
      metrics: [
        ReportMetric(
            label: 'Active',
            value: byStatus.count('active').toDouble(),
            tone: MetricTone.good),
        ReportMetric(
            label: 'Suspended',
            value: byStatus.count('suspended').toDouble(),
            tone: MetricTone.warn),
        ReportMetric(
            label: 'Monthly revenue',
            value: json.money('active_monthly_revenue'),
            isMoney: true),
        ReportMetric(
            label: 'Yearly forecast',
            value: json.money('yearly_total'),
            isMoney: true),
      ],
      rows: json.list('upcoming_renewals', (row) => ReportRow(
            title: row.object('client')?.str('name') ??
                row.strOr('client_name', '—'),
            subtitle: [
              row.strOr('product', row.strOr('product_name', '')),
              if ((row.date('next_bill_date') ?? row.date('expire_date')) !=
                  null)
                'renews ${_d(row.date('next_bill_date') ?? row.date('expire_date'))}',
            ].where((s) => s.isNotEmpty).join(' · '),
            amount: row.money('amount', fallback: row.money('price')),
          )),
    );
  }

  // -------------------------------------------------------------------------
  // 9. Collection effectiveness
  // -------------------------------------------------------------------------
  factory ReportResult.collectionEffectiveness(Map<String, dynamic> json) {
    final byOutcome = json.object('by_outcome') ?? const {};
    return ReportResult(
      rowsLabel: 'Follow-ups',
      percentSuffixLabels: const {'Promises kept'},
      metrics: [
        ReportMetric(
            label: 'Follow-ups',
            value: json.count('total_followups').toDouble()),
        ReportMetric(
            label: 'Promises', value: json.count('promise_count').toDouble()),
        ReportMetric(
            label: 'Fulfilled',
            value: json.count('promises_fulfilled').toDouble(),
            tone: MetricTone.good),
        ReportMetric.percent(
            'Promises kept', json.money('fulfillment_rate'),
            tone: MetricTone.good),
        for (final entry in byOutcome.entries)
          ReportMetric(
            label: entry.key.replaceAll('_', ' '),
            value: readDouble(entry.value),
          ),
      ],
      rows: json.list('followups', (row) => ReportRow(
            title: row.object('client')?.str('name') ??
                row.strOr('client_name', '—'),
            subtitle: [
              row.strOr('outcome', ''),
              if (row.date('call_date') != null) _d(row.date('call_date')),
            ].where((s) => s.isNotEmpty).join(' · '),
            amount: row['promise_amount'] == null
                ? null
                : row.money('promise_amount'),
            status: row.str('status'),
          )),
    );
  }

  // -------------------------------------------------------------------------
  // 10. Satisfaction calls
  // -------------------------------------------------------------------------
  factory ReportResult.satisfaction(Map<String, dynamic> json) {
    final stats = json.object('stats') ?? const {};
    final avg = stats['avg_rating'];
    return ReportResult(
      rowsLabel: 'Calls',
      percentSuffixLabels: const {
        'Completion rate',
        'Satisfaction',
        'Complaints'
      },
      metrics: [
        ReportMetric(
            label: 'Scheduled',
            value: stats.count('total_scheduled').toDouble()),
        ReportMetric(
            label: 'Completed',
            value: stats.count('total_completed').toDouble(),
            tone: MetricTone.good),
        ReportMetric.percent(
            'Completion rate', stats.money('completion_rate')),
        if (avg != null)
          ReportMetric(label: 'Avg rating', value: readDouble(avg)),
        ReportMetric.percent('Satisfaction', stats.money('satisfaction_rate'),
            tone: MetricTone.good),
        ReportMetric.percent('Complaints', stats.money('complaint_rate'),
            tone: MetricTone.bad),
      ],
      rows: json.list('calls', (row) => ReportRow(
            title: row.object('client')?.str('name') ??
                row.strOr('client_name', '—'),
            subtitle: [
              row.strOr('outcome', ''),
              if (row['rating'] != null) '${row.count('rating')}★',
              if ((row.date('scheduled_date') ?? row.date('called_at')) !=
                  null)
                _d(row.date('scheduled_date') ?? row.date('called_at')),
            ].where((s) => s.isNotEmpty).join(' · '),
            status: row.str('status'),
          )),
    );
  }

  // -------------------------------------------------------------------------
  // 11. Communication log
  // -------------------------------------------------------------------------
  factory ReportResult.communicationLog(Map<String, dynamic> json) =>
      ReportResult(
        rowsLabel: 'Messages',
        metrics: [
          for (final channel in json.list('by_channel', (c) => c))
            ReportMetric(
              label: channel.strOr('channel', '—'),
              value: channel.count('total', fallback: channel.count('count'))
                  .toDouble(),
            ),
          for (final type in json.list('by_type', (t) => t))
            ReportMetric(
              label: type.strOr('type', '—').replaceAll('_', ' '),
              value:
                  type.count('total', fallback: type.count('count')).toDouble(),
            ),
        ],
        // `ReportController::communicationLog` names the rows `messages`.
        rows: json.list(json['messages'] is List ? 'messages' : 'logs',
            (row) => ReportRow(
              title: row.strOr('subject', row.strOr('type', 'Message')),
              subtitle: [
                row.object('client')?.str('name') ?? row.strOr('recipient', ''),
                row.strOr('channel', ''),
                if (row.date('created_at') != null) _d(row.date('created_at')),
              ].where((s) => s.isNotEmpty).join(' · '),
              status: row.str('status'),
            )),
      );

  // -------------------------------------------------------------------------
  // 12 & 13. System records / verifications
  // -------------------------------------------------------------------------
  /// `ReportController::systemRecords` returns `{period_start, period_end,
  /// days: [{date, day_total, systems: [{name, subtotal, properties}]}],
  /// system_totals: [{name, total}], grand_total}`. Rows are one per system
  /// for the period, then one per day underneath.
  factory ReportResult.systemRecords(Map<String, dynamic> json) {
    final systems = json.list('system_totals', (r) => r);
    final days = json.list('days', (r) => r);
    return ReportResult(
      rowsLabel: 'Totals',
      metrics: [
        ReportMetric(
            label: 'Total', value: json.money('grand_total'), isMoney: true),
        ReportMetric(label: 'Systems', value: systems.length.toDouble()),
        ReportMetric(label: 'Days', value: days.length.toDouble()),
      ],
      rows: [
        for (final system in systems)
          ReportRow(
            title: system.strOr('name', '—'),
            subtitle: 'Period total',
            amount: system.money('total'),
          ),
        for (final day in days)
          ReportRow(
            title: day.date('date') == null
                ? day.strOr('date', '—')
                : _d(day.date('date')),
            subtitle: day
                .list('systems', (s) => s)
                .map((s) => '${s.strOr('name', '—')} ${s.money('subtotal')}')
                .join(' · '),
            amount: day.money('day_total'),
          ),
      ],
    );
  }

  /// `ReportController::systemVerifications` returns `{total_days,
  /// systems: [{system_name, domain_name, assigned_user, total_days,
  /// completed_days, ok_count, issue_count, missed_days, submission_rate}],
  /// by_staff: [...]}`.
  factory ReportResult.systemVerifications(Map<String, dynamic> json) {
    final systems = json.list('systems', (r) => r);
    int sum(String key) =>
        systems.fold<int>(0, (total, s) => total + s.count(key));
    return ReportResult(
      rowsLabel: 'Systems',
      metrics: [
        ReportMetric(label: 'Days', value: json.count('total_days').toDouble()),
        ReportMetric(
            label: 'Checked', value: sum('completed_days').toDouble()),
        ReportMetric(
            label: 'Issues',
            value: sum('issue_count').toDouble(),
            tone: MetricTone.bad),
        ReportMetric(
            label: 'Missed',
            value: sum('missed_days').toDouble(),
            tone: MetricTone.bad),
      ],
      rows: [
        for (final s in systems)
          ReportRow(
            title: s.strOr('system_name', '—'),
            subtitle: [
              s.object('assigned_user')?.str('name') ?? '',
              '${s.count('completed_days')}/${s.count('total_days')} days',
              '${s.money('submission_rate').toStringAsFixed(0)}%',
              if (s.count('missed_days') > 0) '${s.count('missed_days')} missed',
            ].where((t) => t.isNotEmpty).join(' · '),
            status: s.count('issue_count') > 0
                ? 'overdue'
                : s.count('missed_days') > 0
                    ? 'partial'
                    : 'active',
          ),
      ],
    );
  }

  /// Compact date for row subtitles — the UI formats metrics itself, but rows
  /// are pre-joined strings so the date has to be baked in here.
  static String _d(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

/// Everything the UI needs to list, route to and fetch one report.
class ReportSpec {
  const ReportSpec({
    required this.slug,
    required this.title,
    required this.description,
    required this.permission,
    this.needsDateRange = true,
    this.needsClient = false,
  });

  final String slug;
  final String title;
  final String description;
  final String permission;

  /// Aging, statutory compliance and the subscription report are
  /// point-in-time — the endpoints take no parameters.
  final bool needsDateRange;

  /// Only the client statement needs a client picked first.
  final bool needsClient;

  static const all = <ReportSpec>[
    ReportSpec(
      slug: 'revenue',
      title: 'Revenue summary',
      description: 'Invoiced vs collected, with the collection rate',
      permission: 'reports.revenue',
    ),
    ReportSpec(
      slug: 'aging',
      title: 'Outstanding & aging',
      description: 'What is owed, bucketed by how old it is',
      permission: 'reports.aging',
      needsDateRange: false,
    ),
    ReportSpec(
      slug: 'client-statement',
      title: 'Client statement',
      description: 'One client’s ledger over a period',
      permission: 'reports.client_statement',
      needsClient: true,
    ),
    ReportSpec(
      slug: 'payment-collection',
      title: 'Payment collection',
      description: 'What came in, by method and by day',
      permission: 'reports.payment_collection',
    ),
    ReportSpec(
      slug: 'expenses',
      title: 'Expense report',
      description: 'Spending by category',
      permission: 'reports.expense',
    ),
    ReportSpec(
      slug: 'profit-loss',
      title: 'Profit & loss',
      description: 'Revenue against costs, with margin',
      permission: 'reports.profit_loss',
    ),
    ReportSpec(
      slug: 'statutory',
      title: 'Statutory compliance',
      description: 'Obligations on track, due soon or overdue',
      permission: 'reports.statutory',
      needsDateRange: false,
    ),
    ReportSpec(
      slug: 'subscriptions',
      title: 'Subscriptions',
      description: 'Recurring revenue and upcoming renewals',
      permission: 'reports.subscription',
      needsDateRange: false,
    ),
    ReportSpec(
      slug: 'collection-effectiveness',
      title: 'Collection effectiveness',
      description: 'Follow-up outcomes and promises kept',
      permission: 'reports.collection',
    ),
    ReportSpec(
      slug: 'satisfaction-calls',
      title: 'Satisfaction calls',
      description: 'Completion, ratings and complaints',
      permission: 'reports.satisfaction',
    ),
    ReportSpec(
      slug: 'communication-log',
      title: 'Communication log',
      description: 'Messages sent, by channel and type',
      permission: 'reports.communication',
    ),
    ReportSpec(
      slug: 'system-records',
      title: 'System records report',
      description: 'Recorded amounts by system',
      permission: 'reports.system_records',
    ),
    ReportSpec(
      slug: 'system-verifications',
      title: 'System verifications report',
      description: 'Daily checks and issues raised',
      permission: 'reports.system_verifications',
    ),
  ];

  static ReportSpec? bySlug(String slug) {
    for (final spec in all) {
      if (spec.slug == slug) return spec;
    }
    return null;
  }
}

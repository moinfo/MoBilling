import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../admin/admin_providers.dart' show adminServiceProvider;
import '../common/pickers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmCardList, CrmMetaLine;

final Provider<ReportsService> reportsServiceProvider =
    Provider<ReportsService>(
      (ref) => ReportsService(ref.watch(apiClientProvider)),
    );

/// A report request: which report, over what window, for whom.
typedef ReportQuery = ({
  String slug,
  String? from,
  String? to,
  String? clientId,
});

final AutoDisposeFutureProviderFamily<ReportResult, ReportQuery>
reportProvider = FutureProvider.autoDispose.family<ReportResult, ReportQuery>(
  (ref, query) => ref
      .watch(reportsServiceProvider)
      .fetch(
        query.slug,
        from: query.from,
        to: query.to,
        clientId: query.clientId,
      ),
);

// ---------------------------------------------------------------------------
// Hub
// ---------------------------------------------------------------------------

/// The reports index. Rows are filtered by the same `reports.*` permissions
/// the route middleware enforces, so nothing here opens onto a 403.
class ReportsHubScreen extends ConsumerWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final available = ReportSpec.all
        .where(
          (spec) =>
              (auth?.can(spec.permission) ?? false) &&
              (spec.alsoRequires == null ||
                  (auth?.can(spec.alsoRequires!) ?? false)),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Reports', title: 'Reports'),
      body: available.isEmpty
          ? const StateMessage(
              icon: Icons.lock_outline,
              title: 'No reports available',
              message: 'Your role does not include any report permissions.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                CrmCardList(
                  children: [
                    for (final spec in available)
                      ListTile(
                        title: Text(
                          spec.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            spec.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: scheme.outline,
                        ),
                        onTap: () => context.push('/reports/${spec.slug}'),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// One report
// ---------------------------------------------------------------------------

/// Renders any of the thirteen reports: the headline figure, the metrics that
/// explain it, then the detail rows.
///
/// The period filter only appears for reports whose endpoint accepts one —
/// aging, statutory compliance and the subscription report are point-in-time.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTimeRange? _range;
  StaffClient? _client;

  static final _ymd = DateFormat('yyyy-MM-dd');

  ReportSpec get _spec =>
      ReportSpec.bySlug(widget.slug) ??
      const ReportSpec(
        slug: 'unknown',
        title: 'Report',
        description: '',
        permission: '',
      );

  ReportQuery get _query => (
    slug: widget.slug,
    from: _range == null ? null : _ymd.format(_range!.start),
    to: _range == null ? null : _ymd.format(_range!.end),
    clientId: _client?.id,
  );

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange:
          _range ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickClient() async {
    final chosen = await ClientPickerSheet.show(context);
    if (chosen != null) setState(() => _client = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = _spec;

    // The client statement is meaningless without a client, so ask first
    // rather than firing a request that returns nothing useful.
    final needsClientFirst = spec.needsClient && _client == null;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Reports',
        title: spec.title,
        trailing: needsClientFirst
            ? null
            : _ExportAction(spec: spec, query: _query),
      ),
      body: Column(
        children: [
          if (spec.needsDateRange || spec.needsClient)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  if (spec.needsClient)
                    Expanded(
                      child: _FilterPill(
                        icon: Icons.person_outline,
                        label: _client?.name ?? 'Choose client',
                        selected: _client != null,
                        onTap: _pickClient,
                      ),
                    ),
                  if (spec.needsClient && spec.needsDateRange)
                    const SizedBox(width: Spacing.sm),
                  if (spec.needsDateRange)
                    Expanded(
                      child: _FilterPill(
                        icon: Icons.date_range_outlined,
                        // The server defaults to the current month when no
                        // range is sent.
                        label: _range == null
                            ? 'This month'
                            : '${Formatting.date(_range!.start)} – '
                                  '${Formatting.date(_range!.end)}',
                        selected: _range != null,
                        onTap: _pickRange,
                      ),
                    ),
                  if (_range != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Clear period',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _range = null),
                    ),
                ],
              ),
            ),
          Expanded(
            child: needsClientFirst
                ? StateMessage(
                    icon: Icons.person_search_outlined,
                    title: 'Choose a client',
                    message:
                        'A statement is for one client over a period of time.',
                    actionLabel: 'Choose client',
                    onAction: _pickClient,
                  )
                : _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final report = ref.watch(reportProvider(_query));
    final scheme = theme.colorScheme;

    return CrmAsyncView(
      value: report,
      errorTitle: 'Could not run this report',
      onRetry: () => ref.invalidate(reportProvider(_query)),
      builder: (result) => result.isEmpty
          ? const StateMessage(
              icon: Icons.bar_chart_outlined,
              title: 'Nothing to report',
              message: 'No data for this period.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(reportProvider(_query).future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  if (result.metrics.isNotEmpty) ...[
                    // The first metric is what the report answers; the rest
                    // are the working behind it.
                    Reveal(
                      child: _HeroMetric(
                        metric: result.metrics.first,
                        formatted: _formatMetric(result, result.metrics.first),
                        tone: _toneColor(result.metrics.first.tone),
                      ),
                    ),
                    if (result.metrics.length > 1) ...[
                      const SizedBox(height: Spacing.sm),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: Spacing.sm,
                        crossAxisSpacing: Spacing.sm,
                        childAspectRatio: 1.9,
                        children: [
                          for (final metric in result.metrics.skip(1))
                            if (metric.isMoney)
                              StatTile.money(
                                label: metric.label,
                                amount: metric.value,
                                emphasis: _toneColor(metric.tone),
                              )
                            else
                              StatTile(
                                label: metric.label,
                                value: _formatMetric(result, metric),
                                emphasis: _toneColor(metric.tone),
                              ),
                        ],
                      ),
                    ],
                  ],
                  if (result.rows.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    SectionHeader(
                      result.rowsLabel,
                      trailing: CrmMetaLine(
                        Formatting.integer(result.rows.length),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    CrmCardList(
                      children: [
                        // Long reports are capped — the phone is for reading
                        // the shape, not exporting 2,000 rows.
                        for (final row in result.rows.take(200))
                          _RowTile(row: row),
                      ],
                    ),
                    if (result.rows.length > 200)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.sm),
                        child: Text(
                          'Showing the first 200 of '
                          '${Formatting.integer(result.rows.length)} — '
                          'export CSV above for every row.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  if (result.secondaryRows.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    SectionHeader(
                      result.secondaryRowsLabel ?? 'Breakdown',
                      trailing: CrmMetaLine(
                        Formatting.integer(result.secondaryRows.length),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    CrmCardList(
                      children: [
                        for (final row in result.secondaryRows.take(200))
                          _RowTile(row: row),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _formatMetric(ReportResult result, ReportMetric metric) {
    if (metric.isMoney) return Formatting.amount(metric.value);
    if (result.percentSuffixLabels.contains(metric.label)) {
      return '${metric.value.toStringAsFixed(metric.value % 1 == 0 ? 0 : 1)}%';
    }
    // Counts render clean; averages keep one decimal.
    return metric.value % 1 == 0
        ? metric.value.toStringAsFixed(0)
        : metric.value.toStringAsFixed(1);
  }

  Color? _toneColor(MetricTone tone) => switch (tone) {
    MetricTone.good => context.statusColors.settled,
    MetricTone.warn => context.statusColors.attention,
    MetricTone.bad => context.statusColors.overdue,
    MetricTone.neutral => null,
  };
}

/// Mirrors the web report pages' "Export CSV" button — every one of them
/// does a pure client-side CSV export of whatever's already on screen (see
/// `mobilling-ui/src/components/Reports/ExportButton.tsx`), so this shares
/// the same already-fetched [ReportResult] as text rather than adding a
/// second network round trip or a backend export endpoint that doesn't
/// exist.
class _ExportAction extends ConsumerWidget {
  const _ExportAction({required this.spec, required this.query});

  final ReportSpec spec;
  final ReportQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(reportProvider(query)).valueOrNull;
    if (result == null || result.isEmpty) return const SizedBox.shrink();

    return InkActionButton(
      icon: Icons.ios_share_rounded,
      tooltip: 'Export CSV',
      onPressed: () => Share.share(
        _toCsv(spec, result),
        subject: '${spec.title} — ${Formatting.date(DateTime.now())}',
      ),
    );
  }
}

/// `title,subtitle,amount,status,count` plus a small metrics header — the
/// same shape [ReportRow] already commits to, so every report exports
/// through one honest path instead of thirteen bespoke column sets.
String _toCsv(ReportSpec spec, ReportResult result) {
  String cell(Object? value) {
    final text = value?.toString() ?? '';
    return text.contains(',') || text.contains('"') || text.contains('\n')
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final lines = <String>[spec.title];
  for (final metric in result.metrics) {
    lines.add('${cell(metric.label)},${cell(metric.value)}');
  }
  if (result.metrics.isNotEmpty && result.rows.isNotEmpty) lines.add('');
  if (result.rows.isNotEmpty) {
    lines.add(result.rowsLabel);
    lines.add('Title,Subtitle,Amount,Status,Count');
    for (final row in result.rows) {
      lines.add(
        [
          cell(row.title),
          cell(row.subtitle),
          cell(row.amount),
          cell(row.status),
          cell(row.count),
        ].join(','),
      );
    }
  }
  if (result.secondaryRows.isNotEmpty) {
    lines.add('');
    lines.add(result.secondaryRowsLabel ?? 'Breakdown');
    lines.add('Title,Subtitle,Amount,Status,Count');
    for (final row in result.secondaryRows) {
      lines.add(
        [
          cell(row.title),
          cell(row.subtitle),
          cell(row.amount),
          cell(row.status),
          cell(row.count),
        ].join(','),
      );
    }
  }
  return lines.join('\n');
}

/// The report's headline figure: a mono eyebrow naming it, the figure itself
/// at display scale. A tone only washes the card when the number is itself
/// the news.
class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.metric,
    required this.formatted,
    required this.tone,
  });

  final ReportMetric metric;
  final String formatted;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: tone == null
          ? null
          : Color.alphaBlend(tone!.withValues(alpha: 0.06), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: metric.isMoney
                  ? Money(metric.value, scale: MoneyScale.display, color: tone)
                  : Text(
                      formatted,
                      style: Type.display(
                        MoneyScale.display.size,
                        color: tone ?? scheme.onSurface,
                      ).copyWith(fontFeatures: Type.figures),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One detail row. The status moves down beside the reference so the trailing
/// column is figures only — which is what makes a report read as a table
/// rather than as a list of odd shapes.
class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final ReportRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = row.subtitle ?? '';

    return ListTile(
      dense: true,
      title: Text(
        row.title,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: row.status == null && meta.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: row.status == null
                  ? CrmMetaLine(meta)
                  : Row(
                      children: [
                        StatusChip(row.status, dense: true),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(width: Spacing.sm),
                          Flexible(child: CrmMetaLine(meta)),
                        ],
                      ],
                    ),
            ),
      trailing: row.amount != null
          ? Money(row.amount, showCode: false)
          : row.count != null
          ? Text(
              Formatting.integer(row.count),
              style: TextStyle(
                fontSize: MoneyScale.row.size,
                fontWeight: FontWeight.w700,
                letterSpacing: MoneyScale.row.size * -0.02,
                height: 1,
                color: scheme.onSurface,
                fontFeatures: Type.figures,
              ),
            )
          : null,
    );
  }
}

/// A quiet filter control under the masthead — the chip shape the rest of the
/// app filters with, sized to hold a date range. Candidate for `mobilling_ui`.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + 2,
            vertical: Spacing.sm + 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Spacing.sm - 2),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bank balance statement — not one of the thirteen ReportSpec reports (see
// BankBalanceStatement's doc comment); a bank account has to be picked
// before anything else can be asked for.
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<List<BankAccount>> _reportBankAccountsProvider =
    FutureProvider.autoDispose<List<BankAccount>>(
  (ref) async =>
      (await ref.watch(adminServiceProvider).bankAccounts()).items,
);

typedef _BankStatementQuery = ({
  String bankAccountId,
  String? from,
  String? to,
});

final AutoDisposeFutureProviderFamily<BankBalanceStatement, _BankStatementQuery>
_bankBalanceStatementProvider =
    FutureProvider.autoDispose.family<BankBalanceStatement, _BankStatementQuery>(
  (ref, query) => ref.watch(reportsServiceProvider).bankBalanceStatement(
        bankAccountId: query.bankAccountId,
        startDate: query.from == null ? null : DateTime.parse(query.from!),
        endDate: query.to == null ? null : DateTime.parse(query.to!),
      ),
);

class BankBalanceStatementScreen extends ConsumerStatefulWidget {
  const BankBalanceStatementScreen({super.key});

  @override
  ConsumerState<BankBalanceStatementScreen> createState() =>
      _BankBalanceStatementScreenState();
}

class _BankBalanceStatementScreenState
    extends ConsumerState<BankBalanceStatementScreen> {
  BankAccount? _account;
  DateTimeRange? _range;

  static final _ymd = DateFormat('yyyy-MM-dd');

  Future<void> _pickAccount() async {
    final accounts = ref.read(_reportBankAccountsProvider).valueOrNull;
    if (accounts == null || accounts.isEmpty) return;

    final chosen = await showModalBottomSheet<BankAccount>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final account in accounts.where((a) => a.isActive))
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(account.bankName),
                  subtitle: account.accountNumber == null
                      ? null
                      : Text(account.accountNumber!),
                  onTap: () => Navigator.pop(sheetContext, account),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _account = chosen);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange:
          _range ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(_reportBankAccountsProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'Bank balance statement',
        trailing: _account == null
            ? null
            : _BankStatementExportAction(
                query: (
                  bankAccountId: _account!.id,
                  from: _range == null ? null : _ymd.format(_range!.start),
                  to: _range == null ? null : _ymd.format(_range!.end),
                ),
              ),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorBanner(
          message: e is ApiException
              ? e.message
              : 'Could not load bank accounts.',
          onRetry: () => ref.invalidate(_reportBankAccountsProvider),
        ),
        data: (list) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _FilterPill(
                      icon: Icons.account_balance_outlined,
                      label: _account == null
                          ? 'Choose a bank account'
                          : _account!.bankName,
                      selected: _account != null,
                      onTap: _pickAccount,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: _FilterPill(
                      icon: Icons.date_range_outlined,
                      label: _range == null
                          ? 'This month'
                          : '${Formatting.date(_range!.start)} – '
                              '${Formatting.date(_range!.end)}',
                      selected: _range != null,
                      onTap: _pickRange,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _account == null
                  ? StateMessage(
                      icon: Icons.account_balance_outlined,
                      title: 'Choose a bank account',
                      message: 'Its statement appears here once you do.',
                      actionLabel: list.isEmpty ? null : 'Choose account',
                      onAction: list.isEmpty ? null : _pickAccount,
                    )
                  : _StatementBody(
                      query: (
                        bankAccountId: _account!.id,
                        from: _range == null ? null : _ymd.format(_range!.start),
                        to: _range == null ? null : _ymd.format(_range!.end),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same client-side CSV export as [_ExportAction], for the one report that
/// isn't driven by the generic [ReportScreen].
class _BankStatementExportAction extends ConsumerWidget {
  const _BankStatementExportAction({required this.query});

  final _BankStatementQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(_bankBalanceStatementProvider(query)).valueOrNull;
    if (statement == null || statement.rows.isEmpty) {
      return const SizedBox.shrink();
    }

    String cell(Object? value) {
      final text = value?.toString() ?? '';
      return text.contains(',') || text.contains('"') || text.contains('\n')
          ? '"${text.replaceAll('"', '""')}"'
          : text;
    }

    final lines = <String>[
      statement.bankAccountName,
      'Opening balance,${statement.openingBalance}',
      'Closing balance,${statement.closingBalance}',
      'Total deposits,${statement.totalDeposits}',
      'Total withdrawals,${statement.totalWithdrawals}',
      'Total charges,${statement.totalCharges}',
      '',
      'Date,Type,System,Property,Amount,Running balance,Notes',
      for (final row in statement.rows)
        [
          cell(row.recordDate),
          cell(row.type),
          cell(row.systemName),
          cell(row.propertyName),
          cell(row.signedAmount),
          cell(row.runningBalance),
          cell(row.notes),
        ].join(','),
    ];

    return InkActionButton(
      icon: Icons.ios_share_rounded,
      tooltip: 'Export CSV',
      onPressed: () => Share.share(
        lines.join('\n'),
        subject: 'Bank balance statement — ${statement.bankAccountName}',
      ),
    );
  }
}

class _StatementBody extends ConsumerWidget {
  const _StatementBody({required this.query});

  final _BankStatementQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(_bankBalanceStatementProvider(query));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return CrmAsyncView(
      value: statement,
      errorTitle: 'Could not load the statement',
      onRetry: () => ref.invalidate(_bankBalanceStatementProvider(query)),
      builder: (r) => ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          Text(
            r.bankAccountName,
            style: theme.textTheme.titleSmall,
          ),
          Text(
            '${Formatting.date(DateTime.parse(r.periodStart))} — '
            '${Formatting.date(DateTime.parse(r.periodEnd))}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.md),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.sm,
            crossAxisSpacing: Spacing.sm,
            childAspectRatio: 2.4,
            children: [
              StatTile.money(label: 'Opening balance', amount: r.openingBalance),
              StatTile.money(
                label: 'Closing balance',
                amount: r.closingBalance,
                emphasis: scheme.primary,
              ),
              StatTile.money(
                label: 'Deposits',
                amount: r.totalDeposits,
                emphasis: status.settled,
              ),
              StatTile.money(
                label: 'Withdrawals + charges',
                amount: r.totalWithdrawals + r.totalCharges,
                emphasis: status.overdue,
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Transactions'),
          const SizedBox(height: Spacing.sm),
          if (r.rows.isEmpty)
            const StateMessage(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions',
              message: 'Nothing recorded against this account in this period.',
            )
          else
            CrmCardList(
              children: [
                for (final row in r.rows)
                  ListTile(
                    leading: StatusChip(row.type, dense: true),
                    title: Text(row.systemName ?? '—'),
                    subtitle: CrmMetaLine(
                      [
                        Formatting.date(DateTime.parse(row.recordDate)),
                        if (row.propertyName != null) row.propertyName!,
                        if (row.notes != null) row.notes!,
                      ].join(' · '),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Money(
                          row.signedAmount,
                          scale: MoneyScale.dense,
                          showCode: false,
                          color: row.signedAmount < 0
                              ? status.overdue
                              : status.settled,
                        ),
                        const SizedBox(height: 2),
                        Money(
                          row.runningBalance,
                          scale: MoneyScale.dense,
                          showCode: false,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

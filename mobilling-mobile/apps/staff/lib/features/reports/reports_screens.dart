import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;

final Provider<ReportsService> reportsServiceProvider =
    Provider<ReportsService>(
  (ref) => ReportsService(ref.watch(apiClientProvider)),
);

/// A report request: which report, over what window, for whom.
typedef ReportQuery = ({String slug, String? from, String? to, String? clientId});

final AutoDisposeFutureProviderFamily<ReportResult, ReportQuery>
    reportProvider =
    FutureProvider.autoDispose.family<ReportResult, ReportQuery>(
  (ref, query) => ref.watch(reportsServiceProvider).fetch(
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

    final available = ReportSpec.all
        .where((spec) => auth?.can(spec.permission) ?? false)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: available.isEmpty
          ? const StateMessage(
              icon: Icons.lock_outline,
              title: 'No reports available',
              message: 'Your role does not include any report permissions.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: available.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Spacing.sm),
              itemBuilder: (context, index) {
                final spec = available[index];
                return Card(
                  child: ListTile(
                    title: Text(spec.title),
                    subtitle: Text(spec.description,
                        style: theme.textTheme.bodySmall),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/reports/${spec.slug}'),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// One report
// ---------------------------------------------------------------------------

/// Renders any of the thirteen reports: headline metrics, then detail rows.
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
      initialDateRange: _range ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickClient() async {
    final chosen = await showModalBottomSheet<StaffClient>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _ClientPickerSheet(),
    );
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
      appBar: AppBar(title: Text(spec.title)),
      body: Column(
        children: [
          if (spec.needsDateRange || spec.needsClient)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
              child: Row(
                children: [
                  if (spec.needsClient)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: Text(_client?.name ?? 'Choose client',
                            overflow: TextOverflow.ellipsis),
                        onPressed: _pickClient,
                      ),
                    ),
                  if (spec.needsClient && spec.needsDateRange)
                    const SizedBox(width: Spacing.sm),
                  if (spec.needsDateRange)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range_outlined, size: 18),
                        label: Text(
                          _range == null
                              ? 'All time'
                              : '${Formatting.date(_range!.start)} – ${Formatting.date(_range!.end)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _pickRange,
                      ),
                    ),
                  if (_range != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear period',
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
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  if (result.metrics.isNotEmpty)
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: Spacing.sm,
                      crossAxisSpacing: Spacing.sm,
                      childAspectRatio: 1.9,
                      children: [
                        for (final metric in result.metrics)
                          StatTile(
                            label: metric.label,
                            value: _formatMetric(result, metric),
                            emphasis: _toneColor(metric.tone),
                          ),
                      ],
                    ),
                  if (result.rows.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(result.rowsLabel,
                              style: theme.textTheme.titleSmall),
                        ),
                        Text('${result.rows.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          // Long reports are capped — the phone is for
                          // reading the shape, not exporting 2,000 rows.
                          for (final (i, row)
                              in result.rows.take(200).indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _RowTile(row: row),
                          ],
                        ],
                      ),
                    ),
                    if (result.rows.length > 200)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.sm),
                        child: Text(
                          'Showing the first 200 of ${result.rows.length} — '
                          'use the web app for the full export.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  const SizedBox(height: Spacing.xl),
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

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final ReportRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: row.subtitle == null || row.subtitle!.isEmpty
          ? null
          : Text(row.subtitle!,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (row.amount != null)
            Text(Formatting.amount(row.amount),
                style: theme.textTheme.labelLarge)
          else if (row.count != null)
            Text('${row.count}', style: theme.textTheme.labelLarge),
          if (row.status != null) StatusChip(row.status, dense: true),
        ],
      ),
    );
  }
}

/// Searchable client picker for the client statement.
class _ClientPickerSheet extends ConsumerStatefulWidget {
  const _ClientPickerSheet();

  @override
  ConsumerState<_ClientPickerSheet> createState() =>
      _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<_ClientPickerSheet> {
  final _search = TextEditingController();
  List<StaffClient> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref.read(staffServiceProvider).clients(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            perPage: 50,
          );
      if (mounted) setState(() => _results = page.items);
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search clients',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _load,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final client = _results[index];
                  return ListTile(
                    dense: true,
                    title: Text(client.name),
                    subtitle: client.phone == null
                        ? null
                        : Text(client.phone!),
                    onTap: () => Navigator.of(context).pop(client),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

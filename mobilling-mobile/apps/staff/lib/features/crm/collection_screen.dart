import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'crm_providers.dart';
import 'crm_ui.dart';

/// Debt collection: what is owed, how old it is, and who to ring today.
///
/// The backend exposes a single dashboard endpoint — there is no collection
/// list or log-outcome route. Acting on a row therefore means scheduling a
/// *follow-up*, which is the tap-through offered on each invoice.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

enum _View { today, overdue, upcoming }

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  _View _view = _View.today;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(collectionDashboardProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Collection'),
      body: CrmAsyncView(
        value: dashboard,
        errorTitle: 'Could not load collection',
        onRetry: () => ref.invalidate(collectionDashboardProvider),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(collectionDashboardProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // The hero: the one figure this screen is about.
              Reveal(child: _OutstandingCard(summary: data.summary)),
              const SizedBox(height: Spacing.sm),
              Reveal(
                delay: const Duration(milliseconds: 80),
                child: _CollectedTiles(summary: data.summary),
              ),
              const SizedBox(height: Spacing.sm),
              _TargetProgressCard(summary: data.summary),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Ageing'),
              const SizedBox(height: Spacing.sm),
              _AgeingBar(aging: data.aging),
              const SizedBox(height: Spacing.lg),
              _CallsToMakeCard(data: data),
              const SizedBox(height: Spacing.lg),
              _CallPlanCalendar(callPlan: data.callPlan),
              const SizedBox(height: Spacing.lg),
              _TodayPaymentsCard(payments: data.todayPayments),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Who to ring'),
              const SizedBox(height: Spacing.sm),
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                    value: _View.today,
                    label: Text(
                      'Today (${Formatting.integer(data.todayDue.length)})',
                    ),
                  ),
                  ButtonSegment(
                    value: _View.overdue,
                    label: Text(
                      'Overdue (${Formatting.integer(data.overdue.length)})',
                    ),
                  ),
                  ButtonSegment(
                    value: _View.upcoming,
                    label: Text(
                      'Soon (${Formatting.integer(data.upcoming.length)})',
                    ),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: Spacing.sm),
              _buildList(context, data),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, CollectionDashboard data) {
    final invoices = switch (_view) {
      _View.today => data.todayDue,
      _View.overdue => data.overdue,
      _View.upcoming => data.upcoming,
    };

    if (invoices.isEmpty) {
      return StateMessage(
        icon: Icons.check_circle_outline,
        title: switch (_view) {
          _View.today => 'Nothing due today',
          _View.overdue => 'Nothing overdue',
          _View.upcoming => 'Nothing due soon',
        },
        message: switch (_view) {
          _View.today => 'Invoices falling due today will be listed here.',
          _View.overdue => 'Well collected — every invoice is within terms.',
          _View.upcoming => 'Invoices due in the next few days appear here.',
        },
      );
    }

    return CrmCardList(
      children: [
        for (final invoice in invoices)
          _InvoiceTile(
            invoice: invoice,
            // The dashboard carries phones separately, keyed by document.
            phone: data.phoneByDocument[invoice.id],
          ),
      ],
    );
  }
}

/// Total outstanding in the display scale, with the overdue share under it
/// — the two figures a collector reads before deciding who to chase.
class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Outstanding'.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(
                summary.totalOutstanding,
                scale: MoneyScale.display,
                color: summary.totalOutstanding > 0 ? status.overdue : null,
              ),
            ),
            const Divider(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overdue balance',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Money(
                  summary.overdueBalance,
                  scale: MoneyScale.dense,
                  color: summary.overdueBalance > 0 ? status.attention : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What has come in: today and this month.
class _CollectedTiles extends StatelessWidget {
  const _CollectedTiles({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    // Plain center cross-alignment, matching every other stat-tile row in
    // this app (e.g. attendance_screen.dart) — `stretch` here demands a
    // bounded height from a Row sitting directly in a ListView, which has
    // none, and throws "BoxConstraints forces an infinite height."
    return Row(
      children: [
        Expanded(
          child: StatTile.money(
            label: 'Collected today',
            amount: summary.todayCollected,
            emphasis: status.settled,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: StatTile.money(
            label: 'Collected this month',
            amount: summary.monthCollected,
          ),
        ),
      ],
    );
  }
}

/// Ageing buckets as proportional segments — the shape of the debt matters
/// more than the exact figures when you are deciding who to chase.
class _AgeingBar extends StatelessWidget {
  const _AgeingBar({required this.aging});

  final CollectionAging aging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ramp = context.statusColors.agingRamp;

    final buckets = <(String, double, Color)>[
      ('Current', aging.current, ramp[0]),
      ('1–30 days', aging.days1To30, ramp[1]),
      ('31–60 days', aging.days31To60, ramp[2]),
      ('61–90 days', aging.days61To90, ramp[3]),
      ('Over 90 days', aging.over90, ramp[4]),
    ];
    final total = buckets.fold<double>(0, (sum, b) => sum + b.$2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total <= 0)
              Text(
                'Nothing outstanding.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Row(
                  children: [
                    for (final (_, amount, color) in buckets)
                      if (amount > 0)
                        Expanded(
                          flex: (amount / total * 1000).round().clamp(1, 1000),
                          child: Container(height: 8, color: color),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final (i, (label, amount, color)) in buckets.indexed)
                if (amount > 0) ...[
                  if (i > 0) const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                      Money(amount, scale: MoneyScale.dense, showCode: false),
                    ],
                  ),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

/// One invoice to chase: who, the reference and how late, the balance, and
/// the number one tap away. The call button keeps a fixed slot so the money
/// column stays aligned whether or not a phone is on file.
class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, this.phone});

  final CollectionInvoice invoice;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final overdue = (invoice.daysOverdue ?? 0) > 0;

    final meta = [
      invoice.documentNumber,
      if (overdue)
        '${invoice.daysOverdue}d overdue'
      else if (invoice.daysUntilDue != null)
        'due in ${invoice.daysUntilDue}d',
    ].join(' · ');

    return ListTile(
      onTap: () => context.push('/documents/${invoice.id}'),
      title: Text(
        invoice.clientName ?? invoice.documentNumber,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: CrmStatusLine(
          status: invoice.status,
          meta: meta,
          tone: overdue ? status.overdue : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(invoice.balanceDue),
          const SizedBox(width: Spacing.xs),
          SizedBox(width: 40, child: ContactRow(phone: phone, compact: true)),
        ],
      ),
    );
  }
}

/// Target vs. collected, for the month and for today — the figures a
/// manager asks for first. A plain [LinearProgressIndicator] stands in for
/// web's two rings; the numbers underneath carry the actual information.
class _TargetProgressCard extends StatelessWidget {
  const _TargetProgressCard({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final todayProgress = summary.todayDue <= 0
        ? 0.0
        : (summary.todayDuePaid / summary.todayDue).clamp(0, 1).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _progressRow(
              context,
              label: 'Month target',
              value: summary.monthProgress,
              barColor: status.pending,
              figures: [
                ('Target', summary.monthTarget, null),
                ('Collected', summary.monthCollected, status.settled),
                ('Remaining', summary.monthBalance, status.overdue),
              ],
            ),
            const Divider(height: Spacing.lg),
            _progressRow(
              context,
              label: 'Due today',
              value: todayProgress,
              barColor: status.settled,
              figures: [
                ('Due', summary.todayDue, null),
                ('Paid', summary.todayDuePaid, status.settled),
                ('Balance', summary.todayBalance, status.overdue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressRow(
    BuildContext context, {
    required String label,
    required double value,
    required Color barColor,
    required List<(String, double, Color?)> figures,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            color: barColor,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            for (final (flabel, amount, fcolor) in figures)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Money(amount, scale: MoneyScale.dense, showCode: false, color: fcolor),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Merges the invoices due today with everything overdue into one "who to
/// ring right now" panel, the same headline web puts above its three
/// tables. Sourced from data this screen already loaded — no second
/// endpoint — with a link off to the dedicated follow-ups worklist.
class _CallsToMakeCard extends StatelessWidget {
  const _CallsToMakeCard({required this.data});

  final CollectionDashboard data;

  static const _shown = 8;

  @override
  Widget build(BuildContext context) {
    final calls = [...data.todayDue, ...data.overdue];
    if (calls.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final status = context.statusColors;
    final visible = calls.take(_shown).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_in_talk_outlined, size: 18, color: status.attention),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text('Calls to make', style: theme.textTheme.titleSmall),
                ),
                Text(
                  Formatting.integer(calls.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            for (final invoice in visible)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => context.push('/documents/${invoice.id}'),
                title: Text(
                  invoice.clientName ?? invoice.documentNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: CrmMetaLine(invoice.documentNumber),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Money(invoice.balanceDue, scale: MoneyScale.dense),
                    const SizedBox(width: Spacing.xs),
                    SizedBox(
                      width: 40,
                      child: ContactRow(
                        phone: data.phoneByDocument[invoice.id],
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('View all in follow-ups'),
                onPressed: () => context.push('/followups'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The itemized receipts behind "collected today" — client, invoice,
/// amount, method, reference, so a collector can check off a specific
/// payment rather than trusting the total.
class _TodayPaymentsCard extends StatelessWidget {
  const _TodayPaymentsCard({required this.payments});

  final List<CollectionPayment> payments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: status.settled),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text("Today's payments", style: theme.textTheme.titleSmall),
                ),
                Text(
                  Formatting.integer(payments.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (payments.isEmpty)
              Text(
                'No payments received today.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final (i, payment) in payments.indexed) ...[
                if (i > 0) const Divider(height: Spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(payment.clientName ?? '—', style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 2),
                          CrmMetaLine(
                            [
                              payment.documentNumber ?? '—',
                              if (payment.paymentMethod != null) payment.paymentMethod!,
                              if (payment.reference != null) payment.reference!,
                            ].join(' · '),
                          ),
                        ],
                      ),
                    ),
                    Money(payment.amount, scale: MoneyScale.dense, color: status.settled),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// The month's scheduled calls as a two-column grid of day cards — a
/// compact stand-in for web's `SimpleGrid` of `Paper` tiles, sized to fit a
/// phone rather than a desktop.
class _CallPlanCalendar extends StatelessWidget {
  const _CallPlanCalendar({required this.callPlan});

  final Map<String, List<CallPlanEntry>> callPlan;

  @override
  Widget build(BuildContext context) {
    if (callPlan.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final status = context.statusColors;
    // The backend hands the map back `ksort`ed; sorting again here is cheap
    // insurance rather than a fresh assumption.
    final days = callPlan.keys.toList()..sort();
    final total = callPlan.values.fold<int>(0, (sum, l) => sum + l.length);
    final today = _ymd(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 18, color: status.pending),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text('Call plan — this month', style: theme.textTheme.titleSmall),
                ),
                Text(
                  '$total ${total == 1 ? 'call' : 'calls'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // A plain two-up row grid rather than Wrap+LayoutBuilder — this
            // screen's data can flip between an empty and a populated shape
            // on the same frame (dashboard loads, list goes from 0 rows to
            // N), and every other grid-shaped list in this app already
            // avoids that pairing for exactly that reason.
            for (var i = 0; i < days.length; i += 2)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i + 2 < days.length ? Spacing.sm : 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CallPlanDayCard(
                        day: days[i],
                        entries: callPlan[days[i]]!,
                        isToday: days[i] == today,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: i + 1 < days.length
                          ? _CallPlanDayCard(
                              day: days[i + 1],
                              entries: callPlan[days[i + 1]]!,
                              isToday: days[i + 1] == today,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// One day of the call plan grid: a compact header plus up to three calls,
/// with the rest tucked behind "+N more" rather than growing the cell
/// unpredictably tall.
class _CallPlanDayCard extends StatelessWidget {
  const _CallPlanDayCard({
    required this.day,
    required this.entries,
    required this.isToday,
  });

  final String day;
  final List<CallPlanEntry> entries;
  final bool isToday;

  static const _maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateTime.tryParse(day);
    final label = date == null ? day : DateFormat('EEE d MMM').format(date);
    final shown = entries.take(_maxShown).toList();
    final more = entries.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: isToday ? scheme.primary : scheme.outlineVariant,
          width: isToday ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: isToday ? FontWeight.w700 : null,
                  ),
                ),
              ),
              Text('${entries.length}', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          for (final entry in shown) _CallPlanEntryTile(entry: entry),
          if (more > 0)
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => _showDaySheet(context, label),
              child: Text('+$more more'),
            ),
        ],
      ),
    );
  }

  void _showDaySheet(BuildContext context, String label) {
    showCrmSheet<void>(
      context: context,
      builder: (_) => CrmSheet(
        eyebrow: 'Call plan',
        title: label,
        children: [for (final entry in entries) _CallPlanEntryTile(entry: entry)],
      ),
    );
  }
}

/// One call in the plan: client, reference and balance, tinted by the
/// backend's `type` and one tap from the invoice it is about.
class _CallPlanEntryTile extends StatelessWidget {
  const _CallPlanEntryTile({required this.entry});

  final CallPlanEntry entry;

  Color _colorFor(BuildContext context) {
    final status = context.statusColors;
    return switch (entry.type) {
      'overdue_urgent' => status.overdue,
      'overdue_followup' => status.attention,
      'due_date' => status.pending,
      'followup' => status.settled,
      _ => status.inactive,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(context);

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () => context.push('/documents/${entry.documentId}'),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: Spacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.clientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.documentNumber,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Money(entry.balance, scale: MoneyScale.dense, showCode: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

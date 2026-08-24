import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmAsyncView;
import 'staff_self_providers.dart';

/// My attendance for the current month.
///
/// Lateness, absence and missed check-outs are all flagged server-side against
/// the tenant's configured hours, and excused days (leave/sick/field) suppress
/// every flag — so this screen only renders what the API decided.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance = ref.watch(myAttendanceProvider);
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'HR', title: 'My attendance'),
      body: CrmAsyncView(
        value: attendance,
        errorTitle: 'Could not load attendance',
        onRetry: () => ref.invalidate(myAttendanceProvider),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(myAttendanceProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // Today first — the thing you check on arrival.
              Reveal(child: _TodayCard(data: data)),
              const SizedBox(height: Spacing.md),
              Reveal(
                delay: const Duration(milliseconds: 80),
                child: Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Present · ${data.monthLabel}',
                        value: Formatting.integer(data.presentDays),
                      ),
                    ),
                    if (data.settings.penaltiesEnabled) ...[
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: StatTile.money(
                          label: 'Deductions',
                          amount: data.deductionTotal,
                          emphasis: data.deductionTotal > 0
                              ? status.overdue
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (data.deductions.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                const SectionHeader('Deductions'),
                const SizedBox(height: Spacing.sm),
                _DeductionList(items: data.deductions),
              ],
              const SizedBox(height: Spacing.lg),
              const SectionHeader('This month'),
              const SizedBox(height: Spacing.sm),
              if (data.monthRecords.isEmpty)
                const Card(
                  child: StateMessage(
                    icon: Icons.fact_check_outlined,
                    title: 'Nothing recorded yet',
                    message: 'Days appear here once you check in.',
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MonthStrip(records: data.monthRecords),
                        const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.sm + 2,
                          runSpacing: Spacing.xs,
                          children: [
                            _Legend(color: status.settled, label: 'On time'),
                            _Legend(color: status.attention, label: 'Late'),
                            _Legend(color: status.pending, label: 'Excused'),
                            _Legend(color: status.overdue, label: 'Absent'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                _DayList(days: data.monthRecords),
              ],
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's check-in state: the TODAY eyebrow, the status chip, and the in/out
/// pair measured against the tenant's hours — the dashboard's attendance card,
/// given the whole width.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.data});

  final MyAttendance data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = data.today;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Today · ${Formatting.date(DateTime.now())}'.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (today == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'NOT CHECKED IN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  StatusChip(today.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _Clock(
                    icon: Icons.login_rounded,
                    time: today?.checkInAt,
                    target: data.settings.checkInTime,
                    label: 'in',
                  ),
                ),
                Expanded(
                  child: _Clock(
                    icon: Icons.logout_rounded,
                    time: today?.checkOutAt,
                    target: data.settings.checkOutTime,
                    label: 'out',
                  ),
                ),
              ],
            ),
            if (today != null && today.isExcused) ...[
              const SizedBox(height: Spacing.sm),
              Text(today.summary, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// One half of the in/out pair. Shows the recorded time, or the target it is
/// measured against while the day is still open.
class _Clock extends StatelessWidget {
  const _Clock({
    required this.icon,
    required this.label,
    this.time,
    this.target,
  });

  final IconData icon;
  final String label;
  final String? time;
  final String? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final marked = time != null && time!.isNotEmpty;

    return Row(
      children: [
        Icon(icon, size: 18, color: marked ? scheme.onSurface : scheme.outline),
        const SizedBox(width: Spacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              marked ? time! : '—',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: Type.figures,
                color: marked ? scheme.onSurface : scheme.outline,
              ),
            ),
            Text(
              (target == null ? label : '$label · target $target')
                  .toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The month as one mark per day, so a pattern of lateness is visible without
/// reading a table. Days with no record render as a faint tick rather than as
/// absence — the server decides what counts as absent, not the strip.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.records});

  final List<AttendanceDay> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    final byDay = <int, AttendanceDay>{
      for (final r in records)
        if (r.date != null) r.date!.day: r,
    };

    Color colorFor(AttendanceDay? r) {
      if (r == null) return theme.colorScheme.outlineVariant;
      if (r.isExcused) return status.pending;
      if (r.absent) return status.overdue;
      if (r.late || r.leftEarly || r.noCheckout) return status.attention;
      return status.settled;
    }

    return Row(
      children: [
        for (var day = 1; day <= days; day++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '$day: ${byDay[day]?.summary ?? 'no record'}',
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: colorFor(byDay[day]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Spacing.xs),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Every recorded day, newest as the API orders them. The chip carries the
/// verdict; the mono line carries the times the verdict was made from.
class _DayList extends StatelessWidget {
  const _DayList({required this.days});

  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (final (i, day) in days.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(
                Formatting.date(day.date),
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    StatusChip(day.chipStatus, dense: true),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        day.summary.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeductionList extends StatelessWidget {
  const _DeductionList({required this.items});

  final List<AttendancePenalty> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (final (i, penalty) in items.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(penalty.label, style: theme.textTheme.titleSmall),
              subtitle: Text(
                Formatting.date(penalty.date).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Money(penalty.amount),
            ),
          ],
        ],
      ),
    );
  }
}

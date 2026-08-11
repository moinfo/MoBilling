import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('My attendance')),
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today', style: theme.textTheme.labelMedium),
                      const SizedBox(height: Spacing.xs),
                      if (data.today == null)
                        Text('Not checked in yet',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: status.attention))
                      else ...[
                        Text(data.today!.summary,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: Spacing.xs),
                        StatusChip(data.today!.chipStatus, dense: true),
                      ],
                      if (data.settings.checkInTime != null) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Hours ${data.settings.checkInTime} – ${data.settings.checkOutTime ?? ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Present (${data.monthLabel})',
                      value: '${data.presentDays}',
                      icon: Icons.event_available_outlined,
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
                        icon: Icons.money_off_outlined,
                      ),
                    ),
                  ],
                ],
              ),
              if (data.deductions.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Text('Deductions', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (final (i, penalty) in data.deductions.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.remove_circle_outline,
                              size: 20, color: status.overdue),
                          title: Text(penalty.label),
                          subtitle: Text(Formatting.date(penalty.date)),
                          trailing: Money(penalty.amount),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              Text('This month', style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              if (data.monthRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  child: Center(
                    child: Text('Nothing recorded yet.',
                        style: theme.textTheme.bodySmall),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, day) in data.monthRecords.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(Formatting.date(day.date)),
                          subtitle: Text(day.summary,
                              style: theme.textTheme.bodySmall),
                          trailing: day.isClean && !day.isExcused
                              ? Icon(Icons.check_circle_outline,
                                  size: 20, color: status.settled)
                              : StatusChip(day.chipStatus, dense: true),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

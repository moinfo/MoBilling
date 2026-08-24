import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmField, CrmPickerField, CrmSheet, showCrmSheet;
import 'staff_self_providers.dart';

/// Attendance: my month, and — for whoever holds `attendance.manage` — the
/// whole team's day and the deductions ledger.
///
/// Lateness, absence and missed check-outs are all flagged server-side against
/// the tenant's configured hours, and excused days (leave/sick/field) suppress
/// every flag — so this screen only renders what the API decided.
///
/// The one thing to know about the clock: `POST /attendance/record` is gated
/// on `attendance.manage`, so the check-in / check-out buttons only appear for
/// the attendance clerk. Everyone else is marked by the fingerprint device or
/// an iVMS import, and their card says so rather than offering a button the
/// API would refuse.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(StaffSelfPermissions.attendanceManage) ??
        false;

    final tabs = <(String, Widget)>[
      ('Today', _MeTab(canRecord: canManage)),
      ('My month', const _MyReportTab()),
      if (canManage) ('Team', const _TeamTab()),
      if (canManage) ('Deductions', const _DeductionsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'HR',
          title: 'Attendance',
          bottom: InkTabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) label],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today — my own month, and the clock
// ---------------------------------------------------------------------------

class _MeTab extends ConsumerStatefulWidget {
  const _MeTab({required this.canRecord});

  final bool canRecord;

  @override
  ConsumerState<_MeTab> createState() => _MeTabState();
}

class _MeTabState extends ConsumerState<_MeTab> {
  /// What the last write returned, shown until the refetch lands so the
  /// recorded time appears the instant it is taken.
  AttendanceDay? _justRecorded;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(myAttendanceProvider);
    final status = context.statusColors;

    return CrmAsyncView(
      value: attendance,
      errorTitle: 'Could not load attendance',
      onRetry: () => ref.invalidate(myAttendanceProvider),
      builder: (data) {
        final today = _justRecorded ?? data.today;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _justRecorded = null);
            ref.invalidate(myAttendanceProvider);
            await ref.read(myAttendanceProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // Today first — the thing you check on arrival.
              Reveal(
                child: _TodayCard(settings: data.settings, today: today),
              ),
              if (widget.canRecord) ...[
                const SizedBox(height: Spacing.md),
                Reveal(
                  delay: const Duration(milliseconds: 60),
                  child: _ClockActions(
                    today: today,
                    busy: _busy,
                    onCheckIn: () => _stamp(checkOut: false, day: today),
                    onCheckOut: () => _stamp(checkOut: true, day: today),
                    onEdit: () => _editToday(data, today),
                  ),
                ),
              ] else ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  'Recorded by the fingerprint device — see the attendance '
                  'clerk if a day is wrong.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
        );
      },
    );
  }

  /// Stamp the current time onto today. The route replaces both fields on
  /// every write, so the half we are not stamping is sent back verbatim —
  /// otherwise checking out would erase the morning's check-in and the day
  /// would immediately count as absent.
  Future<void> _stamp({required bool checkOut, AttendanceDay? day}) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    final now = _hhmm(TimeOfDay.now());

    await _write(
      userId: userId,
      date: DateTime.now(),
      checkIn: checkOut ? day?.checkInAt : now,
      checkOut: checkOut ? now : day?.checkOutAt,
      message: checkOut ? 'Checked out at $now.' : 'Checked in at $now.',
    );
  }

  Future<void> _editToday(MyAttendance data, AttendanceDay? day) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;

    final result = await showCrmSheet<_RecordResult>(
      context: context,
      builder: (_) => _RecordDaySheet(
        who: 'Me',
        date: DateTime.now(),
        day: day,
        settings: data.settings,
      ),
    );
    if (result == null) return;

    await _write(
      userId: userId,
      date: DateTime.now(),
      status: result.status,
      statusNote: result.statusNote,
      checkIn: result.checkIn,
      checkOut: result.checkOut,
      message: 'Today updated.',
    );
  }

  Future<void> _write({
    required String userId,
    required DateTime date,
    required String message,
    String? status,
    String? statusNote,
    String? checkIn,
    String? checkOut,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final day = await ref
          .read(staffSelfServiceProvider)
          .recordAttendance(
            userId: userId,
            date: date,
            status: status,
            statusNote: statusNote,
            checkIn: checkIn,
            checkOut: checkOut,
          );
      if (!mounted) return;
      setState(() => _justRecorded = day);
      // The staff dashboard carries an attendance card, and the clerk views
      // are now stale too.
      ref
        ..invalidate(myAttendanceProvider)
        ..invalidate(myAttendanceReportProvider)
        ..invalidate(dashboardProvider)
        ..invalidate(attendanceOverviewProvider)
        ..invalidate(attendanceBoardProvider);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Today's check-in state: the TODAY eyebrow, the status chip, and the in/out
/// pair measured against the tenant's hours — the dashboard's attendance card,
/// given the whole width.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.settings, this.today});

  final AttendanceSettings settings;
  final AttendanceDay? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                  StatusChip(today!.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _Clock(
                    icon: Icons.login_rounded,
                    time: today?.checkInAt,
                    target: settings.checkInTime,
                    label: 'in',
                  ),
                ),
                Expanded(
                  child: _Clock(
                    icon: Icons.logout_rounded,
                    time: today?.checkOutAt,
                    target: settings.checkOutTime,
                    label: 'out',
                  ),
                ),
              ],
            ),
            if (today != null && today!.isExcused) ...[
              const SizedBox(height: Spacing.sm),
              Text(today!.summary, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

/// The clock itself. Check-in is the screen's one primary action until it is
/// taken, and then check-out is; the other half stays available as an outline
/// so a forgotten stamp can still be filled in.
class _ClockActions extends StatelessWidget {
  const _ClockActions({
    required this.today,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onEdit,
  });

  final AttendanceDay? today;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final checkedIn = today?.checkInAt != null && today!.checkInAt!.isNotEmpty;
    final checkedOut =
        today?.checkOutAt != null && today!.checkOutAt!.isNotEmpty;
    final excused = today?.isExcused ?? false;

    if (excused) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
        label: const Text('Change today'),
        onPressed: busy ? null : onEdit,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!checkedIn)
          PrimaryButton(
            label: busy ? 'Recording…' : 'Check in now',
            icon: Icons.login_rounded,
            busy: busy,
            onPressed: busy ? null : onCheckIn,
          )
        else if (!checkedOut)
          PrimaryButton(
            label: busy ? 'Recording…' : 'Check out now',
            icon: Icons.logout_rounded,
            busy: busy,
            onPressed: busy ? null : onCheckOut,
          ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            if (checkedIn && !checkedOut)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Redo check-in'),
                  onPressed: busy ? null : onCheckIn,
                ),
              )
            else if (!checkedIn)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Check out'),
                  onPressed: busy ? null : onCheckOut,
                ),
              ),
            if (!checkedIn || (checkedIn && !checkedOut))
              const SizedBox(width: Spacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Edit today'),
                onPressed: busy ? null : onEdit,
              ),
            ),
          ],
        ),
      ],
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

// ---------------------------------------------------------------------------
// My month — GET /attendance/my-report
// ---------------------------------------------------------------------------

class _MyReportTab extends ConsumerStatefulWidget {
  const _MyReportTab();

  @override
  ConsumerState<_MyReportTab> createState() => _MyReportTabState();
}

class _MyReportTabState extends ConsumerState<_MyReportTab> {
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final key = monthKeyOf(_month);
    final report = ref.watch(myAttendanceReportProvider(key));
    final status = context.statusColors;

    return Column(
      children: [
        MonthStepper(
          month: _month,
          onChanged: (m) => setState(() => _month = m),
        ),
        Expanded(
          child: CrmAsyncView(
            value: report,
            errorTitle: 'Could not load your report',
            onRetry: () => ref.invalidate(myAttendanceReportProvider(key)),
            builder: (data) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myAttendanceReportProvider(key));
                await ref.read(myAttendanceReportProvider(key).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  Reveal(
                    child: StatRail(
                      items: [
                        StatRailItem(
                          label: 'Present',
                          value: Formatting.integer(data.totals.present),
                          emphasis: data.totals.present > 0
                              ? status.settled
                              : null,
                        ),
                        StatRailItem(
                          label: 'Late',
                          value: Formatting.integer(data.totals.late),
                          emphasis: data.totals.late > 0
                              ? status.attention
                              : null,
                        ),
                        StatRailItem(
                          label: 'Absent',
                          value: Formatting.integer(data.totals.absent),
                          emphasis: data.totals.absent > 0
                              ? status.overdue
                              : null,
                        ),
                        StatRailItem(
                          label: 'Excused',
                          value: Formatting.integer(data.totals.excused),
                        ),
                      ],
                    ),
                  ),
                  if (data.totals.deductionTotal > 0) ...[
                    const SizedBox(height: Spacing.sm),
                    StatTile.money(
                      label: 'Docked · ${data.monthLabel}',
                      amount: data.totals.deductionTotal,
                      emphasis: status.overdue,
                    ),
                  ],
                  const SizedBox(height: Spacing.lg),
                  SectionHeader(
                    data.checkInTime == null
                        ? 'Day by day'
                        : 'Day by day · in by ${data.checkInTime}'
                              ' · out by ${data.checkOutTime}',
                  ),
                  const SizedBox(height: Spacing.sm),
                  if (data.days.isEmpty)
                    const Card(
                      child: StateMessage(
                        icon: Icons.event_busy_outlined,
                        title: 'Nothing to report',
                        message: 'This month has no days on record yet.',
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final (i, day) in data.days.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _ReportDayTile(day: day),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportDayTile extends StatelessWidget {
  const _ReportDayTile({required this.day});

  final AttendanceReportDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    // Off days and holidays are context, not news.
    final quiet = !day.working && !day.isPresent && !day.isExcused;

    return Opacity(
      opacity: quiet ? 0.55 : 1,
      child: ListTile(
        dense: true,
        title: Text(
          '${Formatting.date(day.date)} · ${day.weekday}',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              if (!quiet) ...[
                StatusChip(day.chipStatus, dense: true),
                const SizedBox(width: Spacing.sm),
              ],
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
        trailing: day.deduction > 0
            ? Money(
                day.deduction,
                scale: MoneyScale.dense,
                color: status.overdue,
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team — the clerk's day board (attendance.manage)
// ---------------------------------------------------------------------------

class _TeamTab extends ConsumerStatefulWidget {
  const _TeamTab();

  @override
  ConsumerState<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<_TeamTab> {
  DateTime _date = DateTime.now();

  String get _key => _ymd(_date);

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(attendanceBoardProvider(_key));
    final overview = ref.watch(attendanceOverviewProvider);
    final status = context.statusColors;
    final theme = Theme.of(context);

    return Column(
      children: [
        _DayBar(date: _date, onChanged: (d) => setState(() => _date = d)),
        Expanded(
          child: CrmAsyncView(
            value: board,
            errorTitle: 'Could not load the day',
            onRetry: () => ref.invalidate(attendanceBoardProvider(_key)),
            builder: (data) => RefreshIndicator(
              onRefresh: () async {
                ref
                  ..invalidate(attendanceBoardProvider(_key))
                  ..invalidate(attendanceOverviewProvider);
                await ref.read(attendanceBoardProvider(_key).future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  overview.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => ErrorBanner(
                      message: e is ApiException
                          ? e.message
                          : 'Could not load the overview',
                      onRetry: () => ref.invalidate(attendanceOverviewProvider),
                    ),
                    data: (o) => StatRail(
                      items: [
                        StatRailItem(
                          label: 'Present',
                          value: '${o.today.present}/${o.today.total}',
                          emphasis: status.settled,
                        ),
                        StatRailItem(
                          label: 'Late',
                          value: Formatting.integer(o.today.late),
                          emphasis: o.today.late > 0 ? status.attention : null,
                        ),
                        StatRailItem(
                          label: 'Excused',
                          value: Formatting.integer(o.today.excused),
                        ),
                        StatRailItem(
                          label: 'Missing',
                          value: Formatting.integer(o.today.notRecorded),
                          emphasis: o.today.notRecorded > 0
                              ? status.overdue
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  SectionHeader(
                    data.checkInTime == null
                        ? 'Staff'
                        : 'Staff · in by ${data.checkInTime}'
                              ' · out by ${data.checkOutTime}',
                  ),
                  const SizedBox(height: Spacing.sm),
                  if (data.staff.isEmpty)
                    const Card(
                      child: StateMessage(
                        icon: Icons.groups_outlined,
                        title: 'No active staff',
                        message: 'Nobody to record for this date.',
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, row) in data.staff.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _BoardTile(row: row, onTap: () => _record(row)),
                          ],
                        ],
                      ),
                    ),
                  if (overview.valueOrNull != null) ...[
                    const SizedBox(height: Spacing.lg),
                    SectionHeader('This month · ${overview.value!.monthLabel}'),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, s)
                              in overview.value!.staff.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(
                                s.userName,
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                '${Formatting.integer(s.presentDays)}'
                                        ' / ${Formatting.integer(overview.value!.workingDaysSoFar)}'
                                        ' DAYS PRESENT'
                                    .toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: s.deductions > 0
                                  ? Money(
                                      s.deductions,
                                      scale: MoneyScale.dense,
                                      color: status.overdue,
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Spacing.xl),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _record(AttendanceBoardRow row) async {
    final board = ref.read(attendanceBoardProvider(_key)).valueOrNull;
    final result = await showCrmSheet<_RecordResult>(
      context: context,
      builder: (_) => _RecordDaySheet(
        who: row.userName,
        date: _date,
        day: row.day,
        settings: AttendanceSettings(
          penaltiesEnabled: false,
          checkInTime: board?.checkInTime,
          checkOutTime: board?.checkOutTime,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(staffSelfServiceProvider)
          .recordAttendance(
            userId: row.userId,
            date: _date,
            status: result.status,
            statusNote: result.statusNote,
            checkIn: result.checkIn,
            checkOut: result.checkOut,
          );
      ref
        ..invalidate(attendanceBoardProvider(_key))
        ..invalidate(attendanceOverviewProvider)
        ..invalidate(attendancePenaltiesProvider)
        ..invalidate(myAttendanceProvider)
        ..invalidate(dashboardProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Saved — ${row.userName}\'s day updated.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.row, required this.onTap});

  final AttendanceBoardRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = row.day;

    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(row.userName, style: theme.textTheme.titleSmall),
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
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ---------------------------------------------------------------------------
// Deductions — the ledger and the waive (attendance.manage)
// ---------------------------------------------------------------------------

class _DeductionsTab extends ConsumerStatefulWidget {
  const _DeductionsTab();

  @override
  ConsumerState<_DeductionsTab> createState() => _DeductionsTabState();
}

class _DeductionsTabState extends ConsumerState<_DeductionsTab> {
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final key = monthKeyOf(_month);
    final ledger = ref.watch(attendancePenaltiesProvider(key));

    return Column(
      children: [
        MonthStepper(
          month: _month,
          onChanged: (m) => setState(() => _month = m),
        ),
        Expanded(
          child: PenaltyLedgerView(
            value: ledger,
            emptyMessage: 'No attendance deductions this month.',
            onRetry: () => ref.invalidate(attendancePenaltiesProvider(key)),
            onRefresh: () async {
              ref.invalidate(attendancePenaltiesProvider(key));
              await ref.read(attendancePenaltiesProvider(key).future);
            },
            onWaive: (entry, reason) async {
              final message = await ref
                  .read(staffSelfServiceProvider)
                  .waiveAttendancePenalty(entry.id, reason: reason);
              ref
                ..invalidate(attendancePenaltiesProvider(key))
                ..invalidate(myAttendanceProvider)
                ..invalidate(attendanceOverviewProvider);
              return message;
            },
            onUnwaive: (entry) async {
              final message = await ref
                  .read(staffSelfServiceProvider)
                  .unwaiveAttendancePenalty(entry.id);
              ref
                ..invalidate(attendancePenaltiesProvider(key))
                ..invalidate(myAttendanceProvider)
                ..invalidate(attendanceOverviewProvider);
              return message;
            },
          ),
        ),
      ],
    );
  }
}

/// The deductions ledger, shared by attendance and staff reports: a month
/// total, one expandable group per person, and the waive that is the only
/// thing anyone comes here to do.
///
/// The waive/unwaive calls are passed in because the two ledgers hit different
/// routes — both gated, respectively, on `attendance.manage` and
/// `staff_reports.review`, so this widget is only ever built behind one.
class PenaltyLedgerView extends StatelessWidget {
  const PenaltyLedgerView({
    super.key,
    required this.value,
    required this.emptyMessage,
    required this.onRetry,
    required this.onRefresh,
    required this.onWaive,
    required this.onUnwaive,
  });

  final AsyncValue<PenaltyLedger> value;
  final String emptyMessage;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  /// Both return the API's message for the snackbar.
  final Future<String> Function(PenaltyEntry entry, String? reason) onWaive;
  final Future<String> Function(PenaltyEntry entry) onUnwaive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: value,
      errorTitle: 'Could not load deductions',
      onRetry: onRetry,
      builder: (data) => RefreshIndicator(
        onRefresh: onRefresh,
        child: data.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: StateMessage(
                      icon: Icons.money_off_outlined,
                      title: 'Nothing docked',
                      message: emptyMessage,
                    ),
                  ),
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  Reveal(
                    child: StatTile.money(
                      label: 'Total · ${data.monthLabel}',
                      amount: data.grandTotal,
                      emphasis: data.grandTotal > 0 ? status.overdue : null,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('By staff member'),
                  const SizedBox(height: Spacing.sm),
                  for (final group in data.staff) ...[
                    Card(
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          group.userName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${Formatting.integer(group.items.length)} CHARGE'
                          '${group.items.length == 1 ? '' : 'S'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Money(
                          group.total,
                          scale: MoneyScale.dense,
                          color: group.total > 0 ? status.overdue : null,
                        ),
                        children: [
                          for (final entry in group.items)
                            _PenaltyTile(
                              entry: entry,
                              onWaive: onWaive,
                              onUnwaive: onUnwaive,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                  ],
                  const SizedBox(height: Spacing.xl),
                ],
              ),
      ),
    );
  }
}

class _PenaltyTile extends StatefulWidget {
  const _PenaltyTile({
    required this.entry,
    required this.onWaive,
    required this.onUnwaive,
  });

  final PenaltyEntry entry;
  final Future<String> Function(PenaltyEntry entry, String? reason) onWaive;
  final Future<String> Function(PenaltyEntry entry) onUnwaive;

  @override
  State<_PenaltyTile> createState() => _PenaltyTileState();
}

class _PenaltyTileState extends State<_PenaltyTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final entry = widget.entry;

    return Opacity(
      opacity: entry.waived ? 0.6 : 1,
      child: ListTile(
        dense: true,
        title: Text(entry.label, style: theme.textTheme.titleSmall),
        subtitle: Text(
          [
            Formatting.date(entry.date),
            if (entry.waived)
              'waived${entry.waiveReason == null ? '' : ': ${entry.waiveReason}'}',
          ].join(' · ').toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Money(
              entry.amount,
              scale: MoneyScale.dense,
              color: entry.waived ? theme.colorScheme.outline : status.overdue,
            ),
            const SizedBox(width: Spacing.sm),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: entry.waived ? _unwaive : _waive,
                child: Text(entry.waived ? 'Reinstate' : 'Waive'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _waive() async {
    final reason = await _askReason(context);
    if (reason == null || !mounted) return;
    await _run(
      () => widget.onWaive(widget.entry, reason.isEmpty ? null : reason),
    );
  }

  Future<void> _unwaive() => _run(() => widget.onUnwaive(widget.entry));

  Future<void> _run(Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Returns the reason ('' when left blank), or null when dismissed.
Future<String?> _askReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Waive this deduction'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Reason, for the record (optional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Waive'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// The record sheet — POST /attendance/record
// ---------------------------------------------------------------------------

/// What [_RecordDaySheet] returns. A null time means *clear it*, which is
/// exactly what the route does with a missing field.
class _RecordResult {
  const _RecordResult({
    this.status,
    this.statusNote,
    this.checkIn,
    this.checkOut,
  });

  final String? status;
  final String? statusNote;
  final String? checkIn;
  final String? checkOut;
}

class _RecordDaySheet extends StatefulWidget {
  const _RecordDaySheet({
    required this.who,
    required this.date,
    required this.settings,
    this.day,
  });

  final String who;
  final DateTime date;
  final AttendanceSettings settings;
  final AttendanceDay? day;

  @override
  State<_RecordDaySheet> createState() => _RecordDaySheetState();
}

class _RecordDaySheetState extends State<_RecordDaySheet> {
  late String _status;
  late final TextEditingController _note;
  String? _checkIn;
  String? _checkOut;

  /// '' is "present" — the API's null status.
  static const _statuses = <(String, String)>[
    ('', 'Present (kazini)'),
    ('leave', 'Ruhusa (leave)'),
    ('sick', 'Mgonjwa (sick)'),
    ('field', 'Kazi za nje (field)'),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.day?.status ?? '';
    _note = TextEditingController(text: widget.day?.statusNote ?? '');
    _checkIn = widget.day?.checkInAt;
    _checkOut = widget.day?.checkOutAt;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool out}) async {
    final current = out ? _checkOut : _checkIn;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(current) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (out) {
        _checkOut = _hhmm(picked);
      } else {
        _checkIn = _hhmm(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final excused = _status.isNotEmpty;

    return CrmSheet(
      eyebrow: '${widget.who} · ${Formatting.date(widget.date)}',
      title: 'Record the day',
      children: [
        CrmField(
          label: 'Day',
          child: DropdownButtonFormField<String>(
            initialValue: _status,
            items: [
              for (final (value, label) in _statuses)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) => setState(() => _status = v ?? ''),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (excused) ...[
          CrmField(
            label: 'Note',
            child: TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Optional — why the day is excused',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'An excused day carries no times and no deduction.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: CrmPickerField(
                  label: 'Check-in',
                  icon: Icons.login_rounded,
                  value: _checkIn ?? 'Not set',
                  placeholder: _checkIn == null,
                  onTap: () => _pick(out: false),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: CrmPickerField(
                  label: 'Check-out',
                  icon: Icons.logout_rounded,
                  value: _checkOut ?? 'Not set',
                  placeholder: _checkOut == null,
                  onTap: () => _pick(out: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _checkIn == null
                      ? null
                      : () => setState(() => _checkIn = null),
                  child: const Text('Clear check-in'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _checkOut == null
                      ? null
                      : () => setState(() => _checkOut = null),
                  child: const Text('Clear check-out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'A missing check-in counts as absent even when a check-out is '
            'entered'
            '${widget.settings.checkInTime == null ? '' : '. Targets: in by ${widget.settings.checkInTime}, out by ${widget.settings.checkOutTime}'}'
            '.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: 'Save the day',
          onPressed: () => Navigator.of(context).pop(
            _RecordResult(
              status: excused ? _status : null,
              statusNote: excused && _note.text.trim().isNotEmpty
                  ? _note.text.trim()
                  : null,
              checkIn: excused ? null : _checkIn,
              checkOut: excused ? null : _checkOut,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period pickers
// ---------------------------------------------------------------------------

/// A month stepper. Flutter has no month picker, and a full calendar for a
/// choice with twelve values a year would be a heavier control than the
/// choice deserves. Shared with the staff-reports deductions ledger.
class MonthStepper extends StatelessWidget {
  const MonthStepper({super.key, required this.month, required this.onChanged});

  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final atLatest = month.year == now.year && month.month == now.month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () =>
                onChanged(DateTime(month.year, month.month - 1, 1)),
          ),
          Expanded(
            child: Text(
              _monthLabel(month).toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            // The API caps every report at today, so there is nothing ahead.
            onPressed: atLatest
                ? null
                : () => onChanged(DateTime(month.year, month.month + 1, 1)),
          ),
        ],
      ),
    );
  }
}

/// The day stepper over the team board, with a tap-through to the calendar
/// for a date further back.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final atLatest = _ymd(date) == _ymd(today);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous day',
            onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(today.year - 2),
                  lastDate: today,
                );
                if (picked != null) onChanged(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  Formatting.date(date).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next day',
            onPressed: atLatest
                ? null
                : () => onChanged(date.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthLabel(DateTime date) => '${_months[date.month - 1]} ${date.year}';

String _ymd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `HH:mm` — the only time format `POST /attendance/record` accepts.
String _hhmm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parse(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

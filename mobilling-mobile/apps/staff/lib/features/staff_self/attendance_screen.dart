import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../common/pickers.dart' show StaffUserPickerSheet;
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
      if (canManage) ('Report', const _StaffReportTab()),
      if (canManage) ('Import', const _ImportTab()),
      if (canManage) ('Device', const _DeviceTab()),
      if (canManage) ('Settings', const _AttendanceSettingsTab()),
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
              child: _ReportBody(data: data),
            ),
          ),
        ),
      ],
    );
  }
}

/// The body of an [AttendanceReport] — totals, the docked amount, and the
/// day-by-day list — shared by "My month" and the clerk's "Report" tab
/// (which runs the same view for an arbitrary staff member and adds the
/// export buttons via [actions]).
class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data, this.actions});

  final AttendanceReport data;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Reveal(
          child: StatRail(
            items: [
              StatRailItem(
                label: 'Present',
                value: Formatting.integer(data.totals.present),
                emphasis: data.totals.present > 0 ? status.settled : null,
              ),
              StatRailItem(
                label: 'Late',
                value: Formatting.integer(data.totals.late),
                emphasis: data.totals.late > 0 ? status.attention : null,
              ),
              StatRailItem(
                label: 'Absent',
                value: Formatting.integer(data.totals.absent),
                emphasis: data.totals.absent > 0 ? status.overdue : null,
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
        if (actions != null) ...[
          const SizedBox(height: Spacing.md),
          actions!,
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
// Report — the clerk's version of "My month", for any staff member
// (attendance.manage)
// ---------------------------------------------------------------------------

/// The key `attendanceReport`/`attendanceReportExport` are fetched by: whose
/// month, and which one.
typedef _ReportKey = ({String userId, int year, int month});

/// GET /attendance/report. Needs `attendance.manage`.
final AutoDisposeFutureProviderFamily<AttendanceReport, _ReportKey>
_staffAttendanceReportProvider = FutureProvider.autoDispose
    .family<AttendanceReport, _ReportKey>(
      (ref, key) => ref
          .watch(staffSelfServiceProvider)
          .attendanceReport(userId: key.userId, month: key.month, year: key.year),
    );

class _StaffReportTab extends ConsumerStatefulWidget {
  const _StaffReportTab();

  @override
  ConsumerState<_StaffReportTab> createState() => _StaffReportTabState();
}

class _StaffReportTabState extends ConsumerState<_StaffReportTab> {
  StaffUser? _user;
  DateTime _month = DateTime.now();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
          child: _StaffPickerRow(user: user, onPick: _pickUser),
        ),
        if (user != null)
          MonthStepper(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
        Expanded(
          child: user == null
              ? const StateMessage(
                  icon: Icons.badge_outlined,
                  title: 'Choose a staff member',
                  message: 'Pick who to run the attendance report for.',
                )
              : _buildReport(user),
        ),
      ],
    );
  }

  Widget _buildReport(StaffUser user) {
    final key = (userId: user.id, year: _month.year, month: _month.month);
    final report = ref.watch(_staffAttendanceReportProvider(key));

    return CrmAsyncView(
      value: report,
      errorTitle: 'Could not load the report',
      onRetry: () => ref.invalidate(_staffAttendanceReportProvider(key)),
      builder: (data) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_staffAttendanceReportProvider(key));
          await ref.read(_staffAttendanceReportProvider(key).future);
        },
        child: _ReportBody(
          data: data,
          actions: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export PDF'),
                  onPressed: _exporting ? null : () => _export(user, 'pdf'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Export CSV'),
                  onPressed: _exporting ? null : () => _export(user, 'csv'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickUser() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null) return;
    setState(() => _user = user);
  }

  Future<void> _export(StaffUser user, String format) async {
    setState(() => _exporting = true);
    final monthKey =
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    await _exportAttendanceFile(
      context,
      fetch: () => ref
          .read(staffSelfServiceProvider)
          .attendanceReportExport(
            userId: user.id,
            month: _month.month,
            year: _month.year,
            format: format,
          ),
      filename: 'attendance-${user.name.replaceAll(' ', '_')}-$monthKey.$format',
      mimeType: format == 'pdf' ? 'application/pdf' : 'text/csv',
    );
    if (mounted) setState(() => _exporting = false);
  }
}

/// Names who the report tab is showing, and opens the picker to change it.
class _StaffPickerRow extends StatelessWidget {
  const _StaffPickerRow({required this.user, required this.onPick});

  final StaffUser? user;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(
          user?.name ?? 'No staff member chosen',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: user?.roleName == null
            ? null
            : Text(
                user!.roleName!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: TextButton(
          onPressed: onPick,
          child: Text(user == null ? 'Choose' : 'Change'),
        ),
      ),
    );
  }
}

/// Download report bytes and hand them to the platform share sheet — the
/// same pattern `share_pdf.dart` uses, generalised to the CSV format the
/// export route also returns.
Future<void> _exportAttendanceFile(
  BuildContext context, {
  required Future<Uint8List> Function() fetch,
  required String filename,
  required String mimeType,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Preparing the file…'),
      duration: Duration(seconds: 8),
    ),
  );

  try {
    final bytes = await fetch();
    if (bytes.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That came back empty. Try again in a moment.'),
        ),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    messenger.hideCurrentSnackBar();
    await Share.shareXFiles([
      XFile(file.path, mimeType: mimeType),
    ], subject: filename);
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ---------------------------------------------------------------------------
// Import — the iVMS CSV import (attendance.manage)
// ---------------------------------------------------------------------------

class _ImportTab extends ConsumerStatefulWidget {
  const _ImportTab();

  @override
  ConsumerState<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<_ImportTab> {
  String? _filePath;
  String? _fileName;
  AttendanceImportPreview? _preview;
  AttendanceImportResult? _result;
  bool _busy = false;

  String _matchBy = 'name';
  int? _identityCol;
  String _timeMode = 'single';
  int? _dateCol;
  int? _timeCol;
  int? _inCol;
  int? _outCol;
  int? _employeeNoCol;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        if (_result != null)
          _buildResultStep()
        else if (_preview == null)
          _buildPickStep()
        else
          _buildMappingStep(),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }

  Widget _buildPickStep() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.upload_file_outlined, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: Spacing.sm),
            Text('Import from a device export', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Choose the CSV file exported from iVMS. The next step lets '
              'you confirm how its columns map to a name and a time before '
              'anything is saved.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            PrimaryButton(
              label: _busy ? 'Reading file…' : 'Choose CSV file',
              icon: Icons.folder_outlined,
              busy: _busy,
              onPressed: _busy ? null : _pickFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingStep() {
    final theme = Theme.of(context);
    final preview = _preview!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_fileName ?? '', style: theme.textTheme.titleSmall),
        Text(
          '${Formatting.integer(preview.total)} ROWS DETECTED',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        const SectionHeader('Sample rows'),
        const SizedBox(height: Spacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: _ImportPreviewTable(preview: preview),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Confirm the mapping'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CrmField(
                  label: 'Match staff by',
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'name', label: Text('Name')),
                      ButtonSegment(
                        value: 'employee_no',
                        label: Text('Employee no.'),
                      ),
                    ],
                    selected: {_matchBy},
                    onSelectionChanged: (s) =>
                        setState(() => _matchBy = s.first),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: _matchBy == 'name'
                      ? 'Name column'
                      : 'Employee no. column',
                  child: DropdownButtonFormField<int>(
                    initialValue: _identityCol,
                    items: _requiredColumnItems(preview),
                    onChanged: (v) => setState(() => _identityCol = v),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Date column',
                  child: DropdownButtonFormField<int?>(
                    initialValue: _dateCol,
                    items: _optionalColumnItems(preview),
                    onChanged: (v) => setState(() => _dateCol = v),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Time format',
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'single',
                        label: Text('One column'),
                      ),
                      ButtonSegment(value: 'inout', label: Text('In / out')),
                    ],
                    selected: {_timeMode},
                    onSelectionChanged: (s) =>
                        setState(() => _timeMode = s.first),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                if (_timeMode == 'single')
                  CrmField(
                    label: 'Time column',
                    child: DropdownButtonFormField<int?>(
                      initialValue: _timeCol,
                      items: _optionalColumnItems(preview),
                      onChanged: (v) => setState(() => _timeCol = v),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: CrmField(
                          label: 'In column',
                          child: DropdownButtonFormField<int?>(
                            initialValue: _inCol,
                            items: _optionalColumnItems(preview),
                            onChanged: (v) => setState(() => _inCol = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: CrmField(
                          label: 'Out column',
                          child: DropdownButtonFormField<int?>(
                            initialValue: _outCol,
                            items: _optionalColumnItems(preview),
                            onChanged: (v) => setState(() => _outCol = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Employee no. column (optional)',
                  child: DropdownButtonFormField<int?>(
                    initialValue: _employeeNoCol,
                    items: _optionalColumnItems(preview),
                    onChanged: (v) => setState(() => _employeeNoCol = v),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: PrimaryButton(
                label: _busy ? 'Importing…' : 'Import',
                busy: _busy,
                onPressed: _busy || _identityCol == null ? null : _commit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final theme = Theme.of(context);
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: context.statusColors.settled,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text('Import complete', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                StatRail(
                  items: [
                    StatRailItem(
                      label: 'Days',
                      value: Formatting.integer(result.days),
                    ),
                    StatRailItem(
                      label: 'Matched',
                      value: Formatting.integer(result.matchedRows),
                    ),
                    StatRailItem(
                      label: 'Skipped',
                      value: Formatting.integer(result.skipped),
                    ),
                    StatRailItem(
                      label: 'Linked',
                      value: Formatting.integer(result.linked),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (result.unmatched.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Not matched to a staff member'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, entry) in result.unmatched.entries.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(entry.key),
                    trailing: Text(
                      '${entry.value} ROW${entry.value == 1 ? '' : 'S'}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        OutlinedButton(
          onPressed: _reset,
          child: const Text('Import another file'),
        ),
      ],
    );
  }

  List<DropdownMenuItem<int>> _requiredColumnItems(
    AttendanceImportPreview preview,
  ) => [
    for (final (i, h) in preview.headers.indexed)
      DropdownMenuItem<int>(
        value: i,
        child: Text(
          h.isEmpty ? 'Column ${i + 1}' : h,
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];

  List<DropdownMenuItem<int?>> _optionalColumnItems(
    AttendanceImportPreview preview,
  ) => [
    const DropdownMenuItem<int?>(value: null, child: Text('Not used')),
    for (final (i, h) in preview.headers.indexed)
      DropdownMenuItem<int?>(
        value: i,
        child: Text(
          h.isEmpty ? 'Column ${i + 1}' : h,
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];

  void _reset() {
    setState(() {
      _filePath = null;
      _fileName = null;
      _preview = null;
      _result = null;
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final file = (picked?.files ?? const <PlatformFile>[]).firstOrNull;
    if (file?.path == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _filePath = file!.path;
      _fileName = file.name;
      _busy = true;
    });
    try {
      final preview = await ref
          .read(staffSelfServiceProvider)
          .previewAttendanceImport(_filePath!);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _matchBy = preview.guess.matchBy;
        _identityCol = preview.guess.identityCol;
        _timeMode = preview.guess.timeMode;
        _dateCol = preview.guess.dateCol;
        _timeCol = preview.guess.timeCol;
        _inCol = preview.guess.inCol;
        _outCol = preview.guess.outCol;
        _employeeNoCol = preview.guess.employeeNoCol;
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) {
        setState(() {
          _filePath = null;
          _fileName = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final path = _filePath;
    final identityCol = _identityCol;
    if (path == null || identityCol == null) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(staffSelfServiceProvider)
          .commitAttendanceImport(
            path,
            matchBy: _matchBy,
            identityCol: identityCol,
            timeMode: _timeMode,
            dateCol: _dateCol,
            timeCol: _timeMode == 'single' ? _timeCol : null,
            inCol: _timeMode == 'inout' ? _inCol : null,
            outCol: _timeMode == 'inout' ? _outCol : null,
            employeeNoCol: _employeeNoCol,
          );
      ref
        ..invalidate(attendanceBoardProvider)
        ..invalidate(attendanceOverviewProvider)
        ..invalidate(myAttendanceProvider)
        ..invalidate(dashboardProvider);
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The first ~8 rows of the chosen file, so the mapping form below is
/// confirming something visible rather than guessing blind.
class _ImportPreviewTable extends StatelessWidget {
  const _ImportPreviewTable({required this.preview});

  final AttendanceImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 36,
        columns: [
          for (final h in preview.headers)
            DataColumn(
              label: Text(
                h.isEmpty ? '—' : h,
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
        rows: [
          for (final row in preview.rows)
            DataRow(
              cells: [
                for (var i = 0; i < preview.headers.length; i++)
                  DataCell(
                    Text(
                      i < row.length ? row[i] : '',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device — the HIKVISION webhook (attendance.manage)
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<DeviceAttendanceConfig>
_deviceAttendanceConfigProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(staffSelfServiceProvider).deviceAttendanceConfig(),
);

final AutoDisposeFutureProvider<List<DeviceEvent>> _deviceEventsProvider =
    FutureProvider.autoDispose(
      (ref) => ref.watch(staffSelfServiceProvider).deviceEvents(),
    );

final AutoDisposeFutureProvider<DeviceMappings> _deviceMappingsProvider =
    FutureProvider.autoDispose(
      (ref) => ref.watch(staffSelfServiceProvider).deviceMappings(),
    );

class _DeviceTab extends ConsumerStatefulWidget {
  const _DeviceTab();

  @override
  ConsumerState<_DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends ConsumerState<_DeviceTab> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(_deviceAttendanceConfigProvider);
    final mappings = ref.watch(_deviceMappingsProvider);
    final events = ref.watch(_deviceEventsProvider);

    return CrmAsyncView(
      value: config,
      errorTitle: 'Could not load the device',
      onRetry: () => ref.invalidate(_deviceAttendanceConfigProvider),
      builder: (cfg) => RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(_deviceAttendanceConfigProvider)
            ..invalidate(_deviceMappingsProvider)
            ..invalidate(_deviceEventsProvider);
          await ref.read(_deviceAttendanceConfigProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Reveal(
              child: _DeviceConfigCard(
                config: cfg,
                busy: _busy,
                onRegenerate: _regenerate,
                onRunNow: _runNow,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Staff mappings'),
            const SizedBox(height: Spacing.sm),
            mappings.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorBanner(
                message: e is ApiException
                    ? e.message
                    : 'Could not load the mappings',
                onRetry: () => ref.invalidate(_deviceMappingsProvider),
              ),
              data: (m) => _MappingsList(
                mappings: m,
                onEditRow: _editMapping,
                onAssignUnlinked: _assignUnlinked,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            events.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorBanner(
                message: e is ApiException
                    ? e.message
                    : 'Could not load recent events',
                onRetry: () => ref.invalidate(_deviceEventsProvider),
              ),
              data: (list) => _RecentEvents(events: list),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Regenerate the webhook?'),
        content: const Text(
          'The old URL stops working immediately — update the device with '
          'the new one before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(staffSelfServiceProvider).regenerateDeviceToken();
      ref.invalidate(_deviceAttendanceConfigProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Webhook regenerated.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(staffSelfServiceProvider)
          .runDeviceImportNow();
      _refreshAfterImport();
      messenger.showSnackBar(SnackBar(content: Text(_importSummary(result))));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMapping(DeviceStaffMapping row) async {
    final controller = TextEditingController(text: row.deviceEmployeeNo ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(row.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device employee number',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (row.isLinked)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await _saveMapping(row.id, value.isEmpty ? null : value);
  }

  Future<void> _assignUnlinked(String deviceNo) async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null || !mounted) return;
    await _saveMapping(user.id, deviceNo);
  }

  Future<void> _saveMapping(String userId, String? deviceEmployeeNo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(staffSelfServiceProvider)
          .saveDeviceMapping(userId: userId, deviceEmployeeNo: deviceEmployeeNo);
      _refreshAfterImport();
      messenger.showSnackBar(SnackBar(content: Text(_importSummary(result))));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _refreshAfterImport() {
    ref
      ..invalidate(_deviceMappingsProvider)
      ..invalidate(attendanceBoardProvider)
      ..invalidate(attendanceOverviewProvider)
      ..invalidate(myAttendanceProvider)
      ..invalidate(dashboardProvider);
  }
}

String _importSummary(AttendanceImportResult r) =>
    '${Formatting.integer(r.days)} day${r.days == 1 ? '' : 's'} imported · '
    '${Formatting.integer(r.matchedRows)} matched'
    '${r.skipped > 0 ? ' · ${Formatting.integer(r.skipped)} skipped' : ''}';

class _DeviceConfigCard extends StatelessWidget {
  const _DeviceConfigCard({
    required this.config,
    required this.busy,
    required this.onRegenerate,
    required this.onRunNow,
  });

  final DeviceAttendanceConfig config;
  final bool busy;
  final VoidCallback onRegenerate;
  final VoidCallback onRunNow;

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
                  child: Text(config.name, style: theme.textTheme.titleMedium),
                ),
                StatusChip(config.isActive ? 'active' : 'inactive', dense: true),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'WEBHOOK URL',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    config.webhookUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: Type.figures,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: config.webhookUrl),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied.')),
                      );
                    }
                  },
                ),
              ],
            ),
            if (config.lastEventAt != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Last event ${Formatting.dateTime(config.lastEventAt)}'
                    .toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Run import now'),
                    onPressed: busy ? null : onRunNow,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('Regenerate'),
                    onPressed: busy ? null : onRegenerate,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MappingsList extends StatelessWidget {
  const _MappingsList({
    required this.mappings,
    required this.onEditRow,
    required this.onAssignUnlinked,
  });

  final DeviceMappings mappings;
  final ValueChanged<DeviceStaffMapping> onEditRow;
  final ValueChanged<String> onAssignUnlinked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mappings.staff.isEmpty)
          const Card(
            child: StateMessage(
              icon: Icons.badge_outlined,
              title: 'No staff yet',
              message: 'Active staff members appear here to map to a device.',
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, row) in mappings.staff.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(row.name, style: theme.textTheme.titleSmall),
                    subtitle: Text(
                      (row.isLinked ? row.deviceEmployeeNo! : 'Not linked')
                          .toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: row.isLinked
                            ? theme.colorScheme.onSurfaceVariant
                            : status.attention,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onEditRow(row),
                  ),
                ],
              ],
            ),
          ),
        if (mappings.unlinked.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Unclaimed device numbers'),
          const SizedBox(height: Spacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, no) in mappings.unlinked.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.device_unknown_outlined),
                    title: Text(
                      no,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: Type.figures,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => onAssignUnlinked(no),
                      child: const Text('Assign'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.events});

  final List<DeviceEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('Recent events', style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${events.length} DELIVERIES',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Text('No deliveries yet.'),
            )
          else
            for (final (i, event) in events.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _EventTile(event: event),
            ],
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final DeviceEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      dense: true,
      title: Text(
        [
          if (event.employeeNo != null) event.employeeNo!,
          if (event.eventTime != null) Formatting.dateTime(event.eventTime),
        ].join(' · '),
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        event.contentType.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              event.payload,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: Type.figures,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings — the tenant's hours and penalty amounts. Anyone may read; only
// `staff_reports.review` may write.
// ---------------------------------------------------------------------------

final AutoDisposeFutureProvider<AttendanceSettings>
_attendanceSettingsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(staffSelfServiceProvider).attendanceSettings(),
);

const _weekdayLabels = <int, String>{
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

class _AttendanceSettingsTab extends ConsumerStatefulWidget {
  const _AttendanceSettingsTab();

  @override
  ConsumerState<_AttendanceSettingsTab> createState() =>
      _AttendanceSettingsTabState();
}

class _AttendanceSettingsTabState
    extends ConsumerState<_AttendanceSettingsTab> {
  bool _seeded = false;
  TimeOfDay _checkIn = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _checkOut = const TimeOfDay(hour: 17, minute: 0);
  bool _penaltiesEnabled = false;
  Set<int> _workingDays = {1, 2, 3, 4, 5};
  final _absent = TextEditingController();
  final _late = TextEditingController();
  final _leftEarly = TextEditingController();
  final _noCheckout = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _absent.dispose();
    _late.dispose();
    _leftEarly.dispose();
    _noCheckout.dispose();
    super.dispose();
  }

  void _seed(AttendanceSettings s) {
    if (_seeded) return;
    _seeded = true;
    _checkIn = _parse(s.checkInTime) ?? _checkIn;
    _checkOut = _parse(s.checkOutTime) ?? _checkOut;
    _penaltiesEnabled = s.penaltiesEnabled;
    _workingDays = s.workingDays.toSet();
    _absent.text = _moneyText(s.penaltyAbsent);
    _late.text = _moneyText(s.penaltyLate);
    _leftEarly.text = _moneyText(s.penaltyLeftEarly);
    _noCheckout.text = _moneyText(s.penaltyNoCheckout);
  }

  static String _moneyText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(StaffSelfPermissions.staffReportsReview) ??
        false;
    final settings = ref.watch(_attendanceSettingsProvider);

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load attendance settings',
      onRetry: () => ref.invalidate(_attendanceSettingsProvider),
      builder: (data) {
        _seed(data);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_attendanceSettingsProvider);
            await ref.read(_attendanceSettingsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (canEdit) ..._buildForm(context) else ..._buildReadOnly(data),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildReadOnly(AttendanceSettings data) {
    final theme = Theme.of(context);
    return [
      Card(
        child: Column(
          children: [
            _SettingsRow(label: 'Check-in target', value: data.checkInTime ?? '—'),
            const Divider(height: 1),
            _SettingsRow(label: 'Check-out target', value: data.checkOutTime ?? '—'),
            const Divider(height: 1),
            _SettingsRow(
              label: 'Penalties',
              value: data.penaltiesEnabled ? 'Enabled' : 'Disabled',
            ),
            const Divider(height: 1),
            _SettingsRow(
              label: 'Working days',
              value: data.workingDays.isEmpty
                  ? '—'
                  : (data.workingDays.toList()..sort())
                        .map((d) => _weekdayLabels[d] ?? d.toString())
                        .join(', '),
            ),
          ],
        ),
      ),
      if (data.penaltiesEnabled) ...[
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Penalty amounts'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              _SettingsRow(
                label: 'Absent',
                value: data.penaltyAbsent == null
                    ? '—'
                    : Formatting.currency(data.penaltyAbsent),
              ),
              const Divider(height: 1),
              _SettingsRow(
                label: 'Late',
                value: data.penaltyLate == null
                    ? '—'
                    : Formatting.currency(data.penaltyLate),
              ),
              const Divider(height: 1),
              _SettingsRow(
                label: 'Left early',
                value: data.penaltyLeftEarly == null
                    ? '—'
                    : Formatting.currency(data.penaltyLeftEarly),
              ),
              const Divider(height: 1),
              _SettingsRow(
                label: 'No check-out',
                value: data.penaltyNoCheckout == null
                    ? '—'
                    : Formatting.currency(data.penaltyNoCheckout),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Spacing.md),
      Text(
        'Only a staff-report reviewer may change these.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _buildForm(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(
            child: CrmPickerField(
              label: 'Check-in target',
              icon: Icons.login_rounded,
              value: _hhmm(_checkIn),
              onTap: () => _pickTime(out: false),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: CrmPickerField(
              label: 'Check-out target',
              icon: Icons.logout_rounded,
              value: _hhmm(_checkOut),
              onTap: () => _pickTime(out: true),
            ),
          ),
        ],
      ),
      const SizedBox(height: Spacing.md),
      Card(
        child: SwitchListTile(
          title: const Text('Deduct pay for attendance faults'),
          subtitle: const Text('Absence, lateness, leaving early, no check-out'),
          value: _penaltiesEnabled,
          onChanged: (v) => setState(() => _penaltiesEnabled = v),
        ),
      ),
      if (_penaltiesEnabled) ...[
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Absent',
          child: TextField(
            controller: _absent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'TZS '),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Late',
          child: TextField(
            controller: _late,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'TZS '),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Left early',
          child: TextField(
            controller: _leftEarly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'TZS '),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'No check-out',
          child: TextField(
            controller: _noCheckout,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'TZS '),
          ),
        ),
      ],
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Working days',
        child: Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(_weekdayLabels[day]!),
                selected: _workingDays.contains(day),
                onSelected: (v) => setState(() {
                  if (v) {
                    _workingDays.add(day);
                  } else {
                    _workingDays.remove(day);
                  }
                }),
              ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _saving ? 'Saving…' : 'Save settings',
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    ];
  }

  Future<void> _pickTime({required bool out}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: out ? _checkOut : _checkIn,
    );
    if (picked == null) return;
    setState(() {
      if (out) {
        _checkOut = picked;
      } else {
        _checkIn = picked;
      }
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(staffSelfServiceProvider)
          .updateAttendanceSettings(
            checkInTime: _hhmm(_checkIn),
            checkOutTime: _hhmm(_checkOut),
            penaltiesEnabled: _penaltiesEnabled,
            penaltyAbsent: _penaltiesEnabled
                ? double.tryParse(_absent.text.trim())
                : null,
            penaltyLate: _penaltiesEnabled
                ? double.tryParse(_late.text.trim())
                : null,
            penaltyLeftEarly: _penaltiesEnabled
                ? double.tryParse(_leftEarly.text.trim())
                : null,
            penaltyNoCheckout: _penaltiesEnabled
                ? double.tryParse(_noCheckout.text.trim())
                : null,
            workingDays: _workingDays.toList()..sort(),
          );
      ref
        ..invalidate(_attendanceSettingsProvider)
        ..invalidate(myAttendanceProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.titleSmall),
      trailing: Text(value, style: theme.textTheme.bodyMedium),
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

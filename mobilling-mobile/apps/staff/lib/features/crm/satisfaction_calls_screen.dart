import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/pickers.dart';
import 'call_script_sheet.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';
import 'field_marketing_screen.dart' show confirmCrmAction;

/// Satisfaction calls: ring the client, capture a rating and feedback.
///
/// Logging a call can also request an appointment — that is the only way an
/// appointment gets created, since appointments are satisfaction calls with
/// `appointment_requested` set rather than their own table.

/// The queue's three filters as one family key, so a change to any of them
/// is one cache entry rather than three nested lookups.
typedef _CallFilter = ({String? status, String? outcome, String? month});

final AutoDisposeFutureProviderFamily<List<SatisfactionCall>, _CallFilter>
_callsProvider = FutureProvider.autoDispose.family<List<SatisfactionCall>, _CallFilter>(
  (ref, filter) => ref
      .watch(crmServiceProvider)
      .satisfactionCalls(
        status: filter.status,
        outcome: filter.outcome,
        month: filter.month,
      ),
);

/// Last 12 months as `(YYYY-MM, "September 2026")`, newest first — the same
/// window the web's month filter offers.
List<(String?, String)> _monthFilterOptions() {
  final now = DateTime.now();
  final label = DateFormat('MMMM yyyy');
  final options = <(String?, String)>[(null, 'All')];
  for (var i = 0; i < 12; i++) {
    final month = DateTime(now.year, now.month - i);
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    options.add((key, label.format(month)));
  }
  return options;
}

class SatisfactionCallsScreen extends ConsumerStatefulWidget {
  const SatisfactionCallsScreen({super.key});

  @override
  ConsumerState<SatisfactionCallsScreen> createState() =>
      _SatisfactionCallsScreenState();
}

class _SatisfactionCallsScreenState
    extends ConsumerState<SatisfactionCallsScreen> {
  String? _status;
  String? _outcome;
  String? _month;

  // `SatisfactionCall.status` is scheduled | completed | missed | cancelled
  // (ScheduleSatisfactionCalls sets `missed` when a scheduled date passes).
  static const _statusFilters = <(String?, String)>[
    (null, 'All'),
    ('scheduled', 'Scheduled'),
    ('missed', 'Missed'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  static const _outcomeFilters = <(String?, String)>[
    (null, 'All outcomes'),
    ...SatisfactionOutcomes.values,
  ];

  late final _monthFilters = _monthFilterOptions();

  _CallFilter get _filter =>
      (status: _status, outcome: _outcome, month: _month);

  void _invalidate() {
    ref.invalidate(satisfactionDashboardProvider);
    ref.invalidate(_callsProvider(_filter));
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(satisfactionDashboardProvider);
    final calls = ref.watch(_callsProvider(_filter));
    final status = context.statusColors;
    final authSession = ref.watch(sessionControllerProvider).session;
    final canLog = authSession?.can(CrmPermissions.satisfactionLog) ?? false;
    // Handing a call to a colleague means listing `/users`, which carries its
    // own permission on the API. The web only checks `satisfaction_calls
    // .assign` because it lists candidates from a separate, lower-privilege
    // endpoint the mobile API layer does not expose; without that, loosening
    // this would show an Assign action that immediately 403s for anyone
    // without settings.users, so both checks stay.
    final canAssign =
        (authSession?.can(CrmPermissions.satisfactionAssign) ?? false) &&
        (authSession?.can(CrmPermissions.settingsUsers) ?? false);
    final canReschedule =
        authSession?.can(CrmPermissions.satisfactionReschedule) ?? false;
    final canCancel = authSession?.can(CrmPermissions.satisfactionCancel) ?? false;
    final agentName = authSession?.user.name ?? 'Agent';

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Satisfaction calls',
        trailing: InkActionButton(
          icon: Icons.menu_book_outlined,
          tooltip: 'Call script',
          onPressed: () => showCrmSheet<void>(
            context: context,
            builder: (_) => CallScriptSheet(agentName: agentName),
          ),
        ),
      ),
      body: Column(
        children: [
          dashboard.maybeWhen(
            data: (d) => Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                0,
              ),
              child: Reveal(
                child: StatRail(
                  items: [
                    StatRailItem(
                      label: 'Due today',
                      value: Formatting.integer(d.stats.dueToday),
                    ),
                    StatRailItem(
                      label: 'Overdue',
                      value: Formatting.integer(d.stats.overdue),
                      emphasis: d.stats.overdue > 0 ? status.overdue : null,
                    ),
                    StatRailItem(
                      label: 'Completed',
                      value:
                          '${Formatting.integer(d.stats.completedThisMonth)}'
                          '/${Formatting.integer(d.stats.totalThisMonth)}',
                    ),
                    StatRailItem(
                      label: 'Avg rating',
                      value: d.stats.avgRating == null
                          ? '—'
                          : d.stats.avgRating!.toStringAsFixed(1),
                    ),
                  ],
                ),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          dashboard.maybeWhen(
            data: (d) => Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                0,
              ),
              child: _MyPerformancePanel(stats: d.myStats),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          FilterStrip(
            options: _statusFilters,
            selected: _status,
            onSelect: (v) => setState(() => _status = v),
          ),
          FilterStrip(
            options: _outcomeFilters,
            selected: _outcome,
            onSelect: (v) => setState(() => _outcome = v),
          ),
          FilterStrip(
            options: _monthFilters,
            selected: _month,
            onSelect: (v) => setState(() => _month = v),
          ),
          Expanded(
            child: CrmAsyncView(
              value: calls,
              errorTitle: 'Could not load calls',
              onRetry: () => ref.invalidate(_callsProvider(_filter)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.favorite_outline,
                      title: 'No calls in this view',
                      message:
                          'Scheduled satisfaction calls appear here as they fall due.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        _invalidate();
                        await ref.read(_callsProvider(_filter).future);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.md,
                          Spacing.sm,
                          Spacing.md,
                          Spacing.xl,
                        ),
                        children: [
                          CrmCardList(
                            children: [
                              for (final call in items)
                                _CallRow(
                                  call: call,
                                  canLog: canLog,
                                  canAssign: canAssign,
                                  canReschedule: canReschedule,
                                  canCancel: canCancel,
                                  onChanged: _invalidate,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The signed-in caller's own numbers — a team lead reads the rail above for
/// the queue's health, but an agent's own day is what they are measured on.
class _MyPerformancePanel extends StatelessWidget {
  const _MyPerformancePanel({required this.stats});

  final SatisfactionMyStats stats;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final remaining = stats.todayTotal - stats.todayCompleted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('My performance'),
        const SizedBox(height: Spacing.sm),
        StatRail(
          items: [
            StatRailItem(
              label: 'Today',
              value: '${stats.todayCompleted}/${stats.todayTotal}',
            ),
            StatRailItem(
              label: 'This month',
              value: '${stats.monthCompleted}/${stats.monthTotal}',
            ),
            StatRailItem(
              label: 'My rating',
              value: stats.avgRating == null
                  ? '—'
                  : stats.avgRating!.toStringAsFixed(1),
            ),
            StatRailItem(
              label: 'My overdue',
              value: Formatting.integer(stats.overdue),
              emphasis: stats.overdue > 0 ? status.overdue : null,
            ),
            StatRailItem(
              label: 'Remaining',
              value: Formatting.integer(remaining < 0 ? 0 : remaining),
              emphasis: remaining > 0 ? status.pending : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A coloured pill for `call.outcome`, matching [StatusChip]'s dense look —
/// `StatusColors.forStatus` doesn't know this vocabulary, so the mapping
/// lives here rather than stretching that shared switch for one screen.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip(this.outcome);

  final String outcome;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final color = switch (outcome) {
      'satisfied' => status.settled,
      'needs_improvement' => status.attention,
      'complaint' => status.overdue,
      'suggestion' => status.pending,
      _ => status.inactive, // no_answer, unreachable
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        SatisfactionOutcomes.label(outcome).toUpperCase(),
        style: Type.mono(9.5, tracking: 0.08, color: color),
      ),
    );
  }
}

/// One call: the client, the rating as the trailing figure once given, the
/// dates and outcome in the metadata lines, what they said, and the
/// call-and-log row.
class _CallRow extends ConsumerWidget {
  const _CallRow({
    required this.call,
    required this.canLog,
    required this.canAssign,
    required this.canReschedule,
    required this.canCancel,
    required this.onChanged,
  });

  final SatisfactionCall call;
  final bool canLog;
  final bool canAssign;
  final bool canReschedule;
  final bool canCancel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    // A completed or cancelled call is history; only an open one can be
    // logged, rescheduled, cancelled or handed on.
    final isOpen = call.status == 'scheduled' || call.status == 'missed';
    final canAct = canLog && isOpen;
    final canHandOn = canAssign && isOpen;
    final canMoveDate = canReschedule && isOpen;
    final canDrop = canCancel && isOpen;
    final hasMenu = canHandOn || canMoveDate || canDrop;
    final hasPhone = call.clientPhone != null;

    final meta = [
      if (call.scheduledDate != null)
        'scheduled ${Formatting.date(call.scheduledDate)}',
      if (call.calledAt != null) 'called ${Formatting.date(call.calledAt)}',
      if (call.isFollowUp) 'follow-up',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        hasPhone || canAct || hasMenu ? Spacing.xs : Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _ClientLink(call: call)),
              if (call.rating != null) ...[
                const SizedBox(width: Spacing.sm),
                RatingStars(rating: call.rating, compact: true),
              ],
            ],
          ),
          const SizedBox(height: Spacing.xs),
          CrmStatusLine(status: call.status, meta: meta),
          if (call.outcome != null) ...[
            const SizedBox(height: Spacing.xs),
            _OutcomeChip(call.outcome!),
          ],
          if (call.assignedTo != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Assigned to ${call.assignedTo}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (call.feedback != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              '“${call.feedback}”',
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (call.appointmentRequested) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 14,
                  color: status.pending,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    'Appointment ${call.appointmentStatus ?? 'requested'}'
                    '${call.appointmentDate == null ? '' : ' · ${Formatting.date(call.appointmentDate)}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.pending,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (hasPhone || canAct || hasMenu) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                ContactRow(phone: call.clientPhone, compact: true),
                const Spacer(),
                if (canAct)
                  TextButton.icon(
                    icon: const Icon(Icons.phone_in_talk_outlined, size: 18),
                    label: const Text('Log call'),
                    onPressed: () => _showLogSheet(context, ref),
                  ),
                if (hasMenu)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'More actions',
                    onSelected: (action) => switch (action) {
                      'assign' => _assign(context, ref),
                      'reschedule' => _showRescheduleSheet(context, ref),
                      _ => _cancel(context, ref),
                    },
                    itemBuilder: (context) => [
                      if (canHandOn)
                        const PopupMenuItem(
                          value: 'assign',
                          child: Text('Assign'),
                        ),
                      if (canMoveDate)
                        const PopupMenuItem(
                          value: 'reschedule',
                          child: Text('Reschedule'),
                        ),
                      if (canDrop)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel call'),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showLogSheet(BuildContext context, WidgetRef ref) async {
    final logged = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _LogSatisfactionSheet(call: call),
    );
    if (logged == true) onChanged();
  }

  Future<void> _showRescheduleSheet(BuildContext context, WidgetRef ref) async {
    final done = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _RescheduleSheet(call: call),
    );
    if (done == true) onChanged();
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final sure = await confirmCrmAction(
      context,
      title: 'Cancel this call?',
      message:
          'The satisfaction call for ${call.clientName ?? 'this client'} '
          'will be marked cancelled.',
      verb: 'Cancel call',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmServiceProvider).cancelSatisfactionCall(call.id);
      onChanged();
      messenger.showSnackBar(
        const SnackBar(content: Text('Call cancelled.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// `PATCH /satisfaction-calls/{id}/assign` — hand the call to a colleague.
  /// The server answers with the sentence to show, naming who now owns it.
  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(crmServiceProvider)
          .assignSatisfactionCall(call.id, userId: user.id);
      onChanged();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The client's name, tappable through to their profile when the call
/// carries a client id (a phone-only lead never got one).
class _ClientLink extends StatelessWidget {
  const _ClientLink({required this.call});

  final SatisfactionCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = Text(
      call.clientName ?? 'Client',
      style: theme.textTheme.titleSmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final clientId = call.clientId;
    if (clientId == null) return name;

    return InkWell(
      onTap: () => context.push(
        '${Routes.clientPath(clientId)}'
        '?name=${Uri.encodeComponent(call.clientName ?? '')}',
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: name),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _RescheduleSheet extends ConsumerStatefulWidget {
  const _RescheduleSheet({required this.call});

  final SatisfactionCall call;

  @override
  ConsumerState<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<_RescheduleSheet> {
  DateTime? _date;
  bool _submitting = false;
  String? _error;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.call.scheduledDate?.isAfter(now) ?? false
          ? widget.call.scheduledDate!
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final date = _date;
    if (date == null) {
      setState(() => _error = 'Pick a new date.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(crmServiceProvider)
          .rescheduleSatisfactionCall(widget.call.id, scheduledDate: date);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Call rescheduled.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: widget.call.clientName,
    title: 'Reschedule call',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmPickerField(
        label: 'New date',
        value: _date == null ? 'Choose a date' : Formatting.date(_date),
        placeholder: _date == null,
        onTap: _submitting ? null : _pickDate,
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Saving…' : 'Reschedule',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

class _LogSatisfactionSheet extends ConsumerStatefulWidget {
  const _LogSatisfactionSheet({required this.call});

  final SatisfactionCall call;

  @override
  ConsumerState<_LogSatisfactionSheet> createState() =>
      _LogSatisfactionSheetState();
}

class _LogSatisfactionSheetState extends ConsumerState<_LogSatisfactionSheet> {
  final _feedback = TextEditingController();
  final _internalNotes = TextEditingController();
  final _appointmentNotes = TextEditingController();

  // The vocabulary `logCall` validates — see SatisfactionOutcomes.
  static const _outcomes = SatisfactionOutcomes.values;

  String _outcome = 'satisfied';
  int? _rating;
  bool _wantsAppointment = false;
  DateTime? _appointmentDate;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    _internalNotes.dispose();
    _appointmentNotes.dispose();
    super.dispose();
  }

  Future<void> _pickAppointment() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _appointmentDate = picked);
  }

  Future<void> _submit() async {
    if (_wantsAppointment && _appointmentDate == null) {
      setState(() => _error = 'Pick the appointment date.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(crmServiceProvider)
          .logSatisfactionCall(
            widget.call.id,
            outcome: _outcome,
            rating: _rating,
            feedback: _feedback.text.trim().isEmpty
                ? null
                : _feedback.text.trim(),
            internalNotes: _internalNotes.text.trim().isEmpty
                ? null
                : _internalNotes.text.trim(),
            appointmentRequested: _wantsAppointment ? true : null,
            appointmentDate: _wantsAppointment ? _appointmentDate : null,
            appointmentNotes:
                _wantsAppointment && _appointmentNotes.text.trim().isNotEmpty
                ? _appointmentNotes.text.trim()
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Call logged.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reached = SatisfactionOutcomes.reached(_outcome);

    return CrmSheet(
      eyebrow: widget.call.clientName,
      title: 'Log call',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Outcome',
          child: DropdownButtonFormField<String>(
            initialValue: _outcome,
            items: [
              for (final (value, label) in _outcomes)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _outcome = v!),
          ),
        ),
        // Rating and feedback only make sense if someone actually spoke.
        if (reached) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Rating',
            child: Align(
              alignment: Alignment.centerLeft,
              child: RatingStars(
                rating: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'What did they say?',
            child: TextField(
              controller: _feedback,
              enabled: !_submitting,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Their words, as close as you can',
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'They want an appointment',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            value: _wantsAppointment,
            onChanged: _submitting
                ? null
                : (v) => setState(() => _wantsAppointment = v),
          ),
          if (_wantsAppointment) ...[
            const SizedBox(height: Spacing.sm),
            CrmPickerField(
              label: 'Appointment date',
              value: _appointmentDate == null
                  ? 'Choose a date'
                  : Formatting.date(_appointmentDate),
              placeholder: _appointmentDate == null,
              onTap: _submitting ? null : _pickAppointment,
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Appointment notes (optional)',
              child: TextField(
                controller: _appointmentNotes,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  hintText: 'Where, when, and what for',
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Internal notes (not shared)',
          child: TextField(
            controller: _internalNotes,
            enabled: !_submitting,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Only your team sees this',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save call',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

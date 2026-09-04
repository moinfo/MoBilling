import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';
import '../common/pickers.dart';
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
            builder: (_) => _CallScriptSheet(agentName: agentName),
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

// ─────────────────────────────────────────────────────────────────────────
// Call script — a read-only crib sheet, the mobile equivalent of the web's
// CallScriptDrawer. Content is bilingual (Swahili first, since that is the
// language most calls are actually made in) with `{name}` standing in for
// the caller's own name.
// ─────────────────────────────────────────────────────────────────────────

const Map<String, String> _scriptSw = {
  'tip':
      'Maneno yaliyoandikwa kwa herufi nzito yanasomwa kwa sauti kwa mteja. '
      'Badilisha [Jina la Mteja] na jina halisi la mteja.',
  's1': 'Sehemu 1: Mawasiliano Mapya',
  's1_answer_h': '📞 KUJIBU SIMU',
  's1_answer':
      'Habari za asubuhi/mchana/jioni! Asante kwa kupiga simu Moinfotech. '
      'Mimi ni {name}. Naweza kukusaidia vipi leo?',
  's1_call_h': '📲 KUPIGA SIMU — UTAMBULISHO',
  's1_call':
      'Habari! Ninaomba kuzungumza na [Jina la Mteja]. Mimi ni {name} '
      'kutoka Moinfotech.',
  's1_services_h': '📋 MAELEZO YA HUDUMA',
  's1_services':
      'Moinfotech ni kampuni ya teknolojia inayosaidia biashara kukua. '
      'Kauli mbiu yetu ni "Making Technology work for you". Tunatoa huduma '
      'mbalimbali: uwekaji wa tovuti na usajili wa domain, utengenezaji wa '
      'tovuti za kisasa, mifumo maalum (POS, Hotel, School, SACCO, HR, '
      'E-commerce na zaidi ya 50+), jukwaa la SMS nyingi, programu za simu, '
      'na msaada wa kiufundi wakati wowote.',
  's1_close_h': '✅ MWISHO WA MAZUNGUMZO',
  's1_close':
      'Ahsante sana [Jina la Mteja] kwa muda wako. Ikiwa una swali lolote, '
      'usisite kutupigia. Uwe na siku njema!',
  's2': 'Sehemu 2: Simu ya Ufuatiliaji',
  's2_follow_h': '🔄 SIMU YA UFUATILIAJI',
  's2_follow':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia kufuatilia mazungumzo yetu ya awali kuhusu huduma zetu. Je, '
      'umepata nafasi ya kufikiria?',
  's2_tip':
      'Sikiliza kwa makini jibu la mteja. Ikiwa ana maswali, jibu kwa upole '
      'na uwazi.',
  's2_happy_h': '😊 MTEJA AMERIDHIKA',
  's2_happy':
      'Tunafurahi sana kusikia hivyo! Ikiwa kuna jambo lingine tunaloweza '
      'kukusaidia, tuko tayari wakati wowote.',
  's2_issue_h': '😟 MTEJA ANA TATIZO',
  's2_issue':
      'Pole sana kwa usumbufu huo. Naelewa jinsi linavyokusumbua. Hebu '
      'nieleze tatizo lako ili niweze kukusaidia vizuri zaidi.',
  's3': 'Sehemu 3: Kukusanya Malipo',
  's3_remind_h': '💰 KUKUMBUSHA MALIPO',
  's3_remind':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia kukumbusha kuhusu invoice yako ambayo inafikia tarehe ya '
      'kulipa hivi karibuni. Je, umepata nafasi ya kulipa?',
  's3_late_h': '⏰ MALIPO YAMECHELEWA',
  's3_late':
      'Habari [Jina la Mteja]. Mimi ni {name} kutoka Moinfotech. '
      'Tunaona invoice yako bado haijalipwa na imepita tarehe yake. Je, '
      'kuna changamoto yoyote tunayoweza kukusaidia?',
  's3_tip':
      'Ikiwa mteja anaomba muda zaidi, panga tarehe mpya ya malipo na weka '
      'kwenye mfumo.',
  's3_overdue_h': '🔴 MALIPO YA MUDA MREFU (OVERDUE)',
  's3_overdue':
      'Habari [Jina la Mteja]. Mimi ni {name} kutoka Moinfotech. Invoice '
      'yako imechelewa kwa muda mrefu sasa. Tunataka kukusaidia kupanga '
      'malipo ili huduma zako ziendelee bila usumbufu.',
  's4': 'Sehemu 4: Msaada wa Kiufundi',
  's4_receive_h': '🔧 KUPOKEA TATIZO',
  's4_receive':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. Pole '
      'kwa tatizo unalokutana nalo. Hebu nieleze zaidi ili tuweze '
      'kukusaidia.',
  's4_diag_h': '🔍 MASWALI YA TATIZO',
  's4_diag':
      'Je, tatizo hili lilianza lini? Je, umejaribu kuzima na kuwasha '
      'tena? Je, tatizo linaathiri vifaa vyote au kimoja tu?',
  's4_tip': 'Sikiliza jibu kwa makini. Andika maelezo yote kwenye mfumo.',
  's4_resolve_h': '✅ HATUA ZA SULUHISHO',
  's4_resolve':
      'Sawa [Jina la Mteja], kulingana na maelezo yako, nitapeleka tatizo '
      'hili kwa timu yetu ya kiufundi. Watakuwasiliana ndani ya masaa 24.',
  's4_escalate_h': '🔁 ESCALATION',
  's4_escalate':
      'Pole sana [Jina la Mteja]. Tatizo hili linahitaji msaada wa '
      'ziada. Nitawasilisha kwa timu yetu maalum na watakupigia simu haraka '
      'iwezekanavyo.',
  's5': 'Sehemu 5: Simu za Kuridhika kwa Mteja',
  's5_goal':
      'Kupiga simu kwa mteja kila mwezi kujua kuridhika kwake na huduma '
      'zetu, kurekodi matatizo, na kupanga ziara za ana kwa ana '
      'inapohitajika.',
  's5_1_h': '📞 SIMU YA KURIDHIKA — UTANGULIZI',
  's5_1_intro':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia simu yetu ya kila mwezi ya kuridhika kwa mteja. Je, una '
      'dakika chache tuzungumze kuhusu huduma zetu?',
  's5_1_cont':
      'Ahsante! Tunataka kujua jinsi unavyojisikia kuhusu huduma zetu na '
      'ikiwa kuna jambo lolote tunaloweza kuboresha.',
  's5_2_h': '⭐ KIWANGO CHA KURIDHIKA (1-5)',
  's5_2_ask':
      'Kwa kiwango cha 1 hadi 5, ambapo 1 ni mbaya sana na 5 ni bora sana, '
      'unaweza kutupa kiwango gani kwa huduma zetu?',
  's5_2_why': 'Ahsante! Je, kuna sababu maalum ya kiwango hicho?',
  's5_2_tip':
      'Andika kiwango (rating) kwenye mfumo mara moja. Ikiwa mteja '
      'amesita, msaidie kwa kutoa mifano.',
  's5_3_sat_h': '😊 MTEJA AMERIDHIKA',
  's5_3_sat':
      'Tunafurahi sana kusikia hivyo! Maoni yako mazuri yanatuhamasisha '
      'kuendelea kutoa huduma bora. Je, kuna pendekezo lolote la kuboresha '
      'zaidi?',
  's5_3_imp_h': '🔧 MAPENDEKEZO YA KUBORESHA',
  's5_3_imp':
      'Ahsante kwa uaminifu wako. Pendekezo lako ni muhimu sana kwetu. '
      'Nitaliandika na timu yetu italifanyia kazi.',
  's5_3_comp_h': '😟 MALALAMIKO',
  's5_3_comp':
      'Pole sana kwa usumbufu huo. Naelewa jinsi hilo linavyokusumbua. '
      'Nitaliandika malalamiko yako na timu yetu itakuwasiliana haraka '
      'iwezekanavyo.',
  's5_3_sug_h': '💡 WAZO/PENDEKEZO',
  's5_3_sug':
      'Ahsante kwa wazo hilo! Tunapenda kupokea maoni ya wateja wetu. '
      'Nitaliandika na kulipeleka kwa timu husika.',
  's5_4_h': '📍 KUOMBA ZIARA YA MTEJA',
  's5_4_ask':
      'Kwa sababu ya suala hili, tungependa kupanga ziara ya ana kwa ana '
      'ili tuweze kusaidia vizuri zaidi. Je, kuna siku na wakati unaofaa '
      'kwako?',
  's5_4_confirm':
      'Sawa, nimepanga ziara yako tarehe [Tarehe]. Mtu wetu atakuja '
      'kukutembelea. Je, kuna maelezo mengine ya ziara?',
  's5_4_decline':
      'Hakuna shida. Ikiwa utabadilisha mawazo yako, tuko tayari '
      'kukusaidia wakati wowote.',
  's5_4_tip':
      'Pendekeza ziara kwa malalamiko makubwa au matatizo ya kiufundi '
      'ambayo hayawezi kutatuliwa kwa simu.',
  's5_5_h': '📵 MTEJA HAJAJIBU / HAFIKIKI',
  's5_5_step1': 'Jaribu mara 2-3 kwa nyakati tofauti.',
  's5_5_step2':
      'Ikiwa bado hajibu, rekodi kwenye mfumo: outcome = no_answer au '
      'unreachable — mfumo utapanga simu ya ufuatiliaji siku ya kazi '
      'inayofuata.',
  's5_6_h': '✅ MWISHO WA SIMU YA KURIDHIKA',
  's5_6_close':
      'Ahsante sana [Jina la Mteja] kwa muda wako na maoni yako. Maoni '
      'yako yanasaidia sana kuboresha huduma zetu. Tutaendelea kukupigia '
      'simu kila mwezi kujua hali yako.',
  's5_6_appt':
      'Na kumbuka, timu yetu itakuja kukutembelea tarehe [Tarehe]. '
      'Tutakutumia ujumbe wa kukumbushia.',
  'qr_angry': 'Mteja anakasirika',
  'qr_angry_say': 'Naelewa frustration yako. Hili ni muhimu kwetu pia.',
  'qr_dunno': 'Hujui jibu',
  'qr_dunno_say': 'Naomba dakika moja tu. Nataka kukupa jibu sahihi.',
  'qr_mgr': 'Mteja anataka msimamizi',
  'qr_mgr_say': 'Nakuelewa. Nitamwita msimamizi wangu sasa hivi.',
  'qr_sat': 'Mteja ameridhika (simu ya kuridhika)',
  'qr_sat_say': 'Tunafurahi sana kusikia hivyo! Kiwango chako ni muhimu kwetu.',
  'qr_prob': 'Mteja ana tatizo (simu ya kuridhika)',
  'qr_prob_say':
      'Pole sana. Nitaliandika na timu yetu italifanyia kazi haraka.',
  'qr_visit': 'Kuomba ziara',
  'qr_visit_say':
      'Tungependa kupanga ziara ili tuweze kusaidia vizuri zaidi.',
  'qr_end': 'Kumalizia mazungumzo',
  'qr_end_say': 'Asante kwa muda wako [Jina la Mteja]. Uwe na siku njema!',
};

const Map<String, String> _scriptEn = {
  'tip':
      'Words written in bold are read aloud to the client. Replace '
      '[Client Name] with the actual client name.',
  's1': 'Section 1: New Contact',
  's1_answer_h': '📞 ANSWERING A CALL',
  's1_answer':
      'Good morning/afternoon/evening! Thank you for calling Moinfotech. '
      'My name is {name}. How can I help you today?',
  's1_call_h': '📲 MAKING A CALL — INTRODUCTION',
  's1_call':
      'Hello! May I speak with [Client Name]? My name is {name} from '
      'Moinfotech.',
  's1_services_h': '📋 SERVICE DESCRIPTION',
  's1_services':
      'Moinfotech is a technology company that helps businesses grow. Our '
      'motto is "Making Technology work for you". We offer hosting and '
      'domain registration, modern responsive websites, custom systems '
      '(POS, Hotel, School, SACCO, HR, E-commerce and 50+ more), bulk SMS, '
      'mobile apps, and technical support anytime.',
  's1_close_h': '✅ CLOSING THE CONVERSATION',
  's1_close':
      'Thank you very much [Client Name] for your time. If you have any '
      'questions, do not hesitate to call us. Have a great day!',
  's2': 'Section 2: Follow-up Call',
  's2_follow_h': '🔄 FOLLOW-UP CALL',
  's2_follow':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling to follow up on our previous conversation about our '
      'services. Have you had a chance to think about it?',
  's2_tip':
      'Listen carefully to the client\'s response. If they have '
      'questions, answer politely and clearly.',
  's2_happy_h': '😊 CLIENT IS SATISFIED',
  's2_happy':
      'We are very happy to hear that! If there is anything else we can '
      'help you with, we are ready anytime.',
  's2_issue_h': '😟 CLIENT HAS AN ISSUE',
  's2_issue':
      'We are very sorry for the inconvenience. I understand how it '
      'affects you. Please explain the issue so I can help you better.',
  's3': 'Section 3: Payment Collection',
  's3_remind_h': '💰 PAYMENT REMINDER',
  's3_remind':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling to remind you about your invoice that is approaching its '
      'due date. Have you had a chance to make the payment?',
  's3_late_h': '⏰ LATE PAYMENT',
  's3_late':
      'Hello [Client Name]. My name is {name} from Moinfotech. We '
      'notice your invoice is still unpaid and past its due date. Is '
      'there any challenge we can help you with?',
  's3_tip':
      'If the client asks for more time, schedule a new payment date and '
      'record it in the system.',
  's3_overdue_h': '🔴 LONG OVERDUE PAYMENT',
  's3_overdue':
      'Hello [Client Name]. My name is {name} from Moinfotech. Your '
      'invoice has been overdue for a long time now. We want to help you '
      'arrange payment so your services continue without interruption.',
  's4': 'Section 4: Technical Support',
  's4_receive_h': '🔧 RECEIVING AN ISSUE',
  's4_receive':
      'Hello [Client Name]! My name is {name} from Moinfotech. Sorry '
      'about the issue you\'re experiencing. Please tell me more so we '
      'can help you.',
  's4_diag_h': '🔍 DIAGNOSTIC QUESTIONS',
  's4_diag':
      'When did this issue start? Have you tried turning it off and on '
      'again? Does the issue affect all devices or just one?',
  's4_tip': 'Listen carefully to the answer. Record all details in the system.',
  's4_resolve_h': '✅ RESOLUTION STEPS',
  's4_resolve':
      'Okay [Client Name], based on your description, I will escalate '
      'this issue to our technical team. They will contact you within 24 '
      'hours.',
  's4_escalate_h': '🔁 ESCALATION',
  's4_escalate':
      'We are very sorry [Client Name]. This issue requires additional '
      'support. I will forward it to our specialized team and they will '
      'call you as soon as possible.',
  's5': 'Section 5: Satisfaction Calls',
  's5_goal':
      'Call each client monthly to assess their satisfaction with our '
      'services, record any issues, and schedule in-person visits when '
      'needed.',
  's5_1_h': '📞 SATISFACTION CALL — INTRODUCTION',
  's5_1_intro':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling for our monthly customer satisfaction check-in. Do you '
      'have a few minutes to talk about our services?',
  's5_1_cont':
      'Thank you! We want to know how you feel about our services and if '
      'there is anything we can improve.',
  's5_2_h': '⭐ SATISFACTION RATING (1-5)',
  's5_2_ask':
      'On a scale of 1 to 5, where 1 is very poor and 5 is excellent, '
      'how would you rate our services?',
  's5_2_why': 'Thank you! Is there a specific reason for that rating?',
  's5_2_tip':
      'Record the rating in the system immediately. If the client '
      'hesitates, help them by giving examples.',
  's5_3_sat_h': '😊 CLIENT IS SATISFIED',
  's5_3_sat':
      'We are so happy to hear that! Your positive feedback motivates us '
      'to continue providing excellent service. Do you have any '
      'suggestions for improvement?',
  's5_3_imp_h': '🔧 NEEDS IMPROVEMENT',
  's5_3_imp':
      'Thank you for your honesty. Your suggestion is very important to '
      'us. I will record it and our team will work on it.',
  's5_3_comp_h': '😟 COMPLAINT',
  's5_3_comp':
      'We are very sorry for the inconvenience. I understand how '
      'frustrating that is. I will record your complaint and our team '
      'will get back to you as soon as possible.',
  's5_3_sug_h': '💡 IDEA/SUGGESTION',
  's5_3_sug':
      'Thank you for that idea! We love receiving feedback from our '
      'clients. I will record it and forward it to the relevant team.',
  's5_4_h': '📍 REQUESTING A CLIENT VISIT',
  's5_4_ask':
      'Because of this issue, we would like to schedule an in-person '
      'visit so we can help you better. Is there a day and time that '
      'works for you?',
  's5_4_confirm':
      'Great, I have scheduled your visit for [Date]. Our representative '
      'will come to see you. Are there any other details about the '
      'visit?',
  's5_4_decline':
      'No problem. If you change your mind, we are ready to help you '
      'anytime.',
  's5_4_tip':
      'Suggest visits for serious complaints or technical issues that '
      'cannot be resolved over the phone.',
  's5_5_h': '📵 NO ANSWER / UNREACHABLE',
  's5_5_step1': 'Try 2-3 times at different times.',
  's5_5_step2':
      'If still no answer, record in system: outcome = no_answer or '
      'unreachable — the follow-up call will appear on your schedule the '
      'next business day.',
  's5_6_h': '✅ END OF SATISFACTION CALL',
  's5_6_close':
      'Thank you so much [Client Name] for your time and feedback. Your '
      'feedback helps us greatly improve our services. We will continue '
      'calling you monthly to check in.',
  's5_6_appt':
      'And remember, our team will come to visit you on [Date]. We will '
      'send you a reminder message.',
  'qr_angry': 'Client is angry',
  'qr_angry_say': 'I understand your frustration. This is important to us too.',
  'qr_dunno': 'You don\'t know the answer',
  'qr_dunno_say': 'Just a moment please. I want to give you the right answer.',
  'qr_mgr': 'Client wants a manager',
  'qr_mgr_say': 'I understand. Let me get my supervisor right away.',
  'qr_sat': 'Client is satisfied (satisfaction call)',
  'qr_sat_say': 'We are so happy to hear that! Your rating is very important to us.',
  'qr_prob': 'Client has a problem (satisfaction call)',
  'qr_prob_say': 'We are very sorry. I will record it and our team will work on it quickly.',
  'qr_visit': 'Requesting a visit',
  'qr_visit_say': 'We would like to schedule a visit so we can help you better.',
  'qr_end': 'Closing the conversation',
  'qr_end_say': 'Thank you for your time [Client Name]. Have a great day!',
};

class _CallScriptSheet extends StatefulWidget {
  const _CallScriptSheet({required this.agentName});

  final String agentName;

  @override
  State<_CallScriptSheet> createState() => _CallScriptSheetState();
}

class _CallScriptSheetState extends State<_CallScriptSheet> {
  bool _swahili = true;

  String _t(String key) {
    final t = _swahili ? _scriptSw : _scriptEn;
    return (t[key] ?? '').replaceAll('{name}', widget.agentName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          sheetBottomInset(context) + Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Customer care call script',
              style: Type.display(20, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('🇹🇿 Swahili')),
                ButtonSegment(value: false, label: Text('🇬🇧 English')),
              ],
              selected: {_swahili},
              onSelectionChanged: (s) => setState(() => _swahili = s.first),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    margin: const EdgeInsets.only(bottom: Spacing.md),
                    decoration: BoxDecoration(
                      color: status.pending.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text('💡 ${_t('tip')}', style: theme.textTheme.bodySmall),
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.call_outlined,
                    title: _t('s1'),
                    children: [
                      _block(context, _t('s1_answer_h'), _t('s1_answer')),
                      _block(context, _t('s1_call_h'), _t('s1_call')),
                      _block(context, _t('s1_services_h'), _t('s1_services')),
                      _block(context, _t('s1_close_h'), _t('s1_close')),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.repeat_outlined,
                    title: _t('s2'),
                    children: [
                      _block(context, _t('s2_follow_h'), _t('s2_follow')),
                      _tip(context, _t('s2_tip')),
                      _block(
                        context,
                        _t('s2_happy_h'),
                        _t('s2_happy'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s2_issue_h'),
                        _t('s2_issue'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.receipt_long_outlined,
                    title: _t('s3'),
                    children: [
                      _block(context, _t('s3_remind_h'), _t('s3_remind')),
                      _block(
                        context,
                        _t('s3_late_h'),
                        _t('s3_late'),
                        color: status.attention,
                      ),
                      _tip(context, _t('s3_tip')),
                      _block(
                        context,
                        _t('s3_overdue_h'),
                        _t('s3_overdue'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.build_outlined,
                    title: _t('s4'),
                    children: [
                      _block(context, _t('s4_receive_h'), _t('s4_receive')),
                      _block(context, _t('s4_diag_h'), _t('s4_diag')),
                      _tip(context, _t('s4_tip')),
                      _block(
                        context,
                        _t('s4_resolve_h'),
                        _t('s4_resolve'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s4_escalate_h'),
                        _t('s4_escalate'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.favorite_outline,
                    title: _t('s5'),
                    initiallyExpanded: true,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(Spacing.sm),
                        margin: const EdgeInsets.only(bottom: Spacing.sm),
                        decoration: BoxDecoration(
                          color: status.settled.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Text(_t('s5_goal'), style: theme.textTheme.bodySmall),
                      ),
                      _block(context, _t('s5_1_h'), _t('s5_1_intro')),
                      _block(context, '', _t('s5_1_cont')),
                      _block(context, _t('s5_2_h'), _t('s5_2_ask')),
                      _block(context, '', _t('s5_2_why')),
                      _tip(context, _t('s5_2_tip')),
                      _block(
                        context,
                        _t('s5_3_sat_h'),
                        _t('s5_3_sat'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s5_3_imp_h'),
                        _t('s5_3_imp'),
                        color: status.attention,
                      ),
                      _block(
                        context,
                        _t('s5_3_comp_h'),
                        _t('s5_3_comp'),
                        color: status.overdue,
                      ),
                      _block(
                        context,
                        _t('s5_3_sug_h'),
                        _t('s5_3_sug'),
                        color: status.pending,
                      ),
                      _block(context, _t('s5_4_h'), _t('s5_4_ask')),
                      _block(context, '', _t('s5_4_confirm')),
                      _block(context, '', _t('s5_4_decline')),
                      _tip(context, _t('s5_4_tip')),
                      _block(
                        context,
                        _t('s5_5_h'),
                        '${_t('s5_5_step1')}\n${_t('s5_5_step2')}',
                      ),
                      _block(context, _t('s5_6_h'), _t('s5_6_close')),
                      _block(context, '', _t('s5_6_appt')),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.star_outline,
                    title: _swahili ? 'Jedwali la Kumbukumbu' : 'Quick Reference',
                    children: [
                      for (final key in [
                        'angry',
                        'dunno',
                        'mgr',
                        'sat',
                        'prob',
                        'visit',
                        'end',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t('qr_$key'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '"${_t('qr_${key}_say')}"',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
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

Widget _scriptSection(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> children,
  bool initiallyExpanded = false,
}) => Card(
  clipBehavior: Clip.antiAlias,
  margin: const EdgeInsets.only(bottom: Spacing.sm),
  child: ExpansionTile(
    leading: Icon(icon),
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    initiallyExpanded: initiallyExpanded,
    childrenPadding: const EdgeInsets.fromLTRB(
      Spacing.md,
      0,
      Spacing.md,
      Spacing.md,
    ),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
);

Widget _block(
  BuildContext context,
  String heading,
  String body, {
  Color? color,
}) {
  final theme = Theme.of(context);
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: Spacing.sm),
    padding: const EdgeInsets.all(Spacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: theme.colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading.isNotEmpty) ...[
          Text(
            heading,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color ?? context.statusColors.pending,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(body, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}

Widget _tip(BuildContext context, String text) {
  final status = context.statusColors;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: Spacing.sm),
    padding: const EdgeInsets.all(Spacing.sm),
    decoration: BoxDecoration(
      color: status.attention.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Text('💡 $text', style: Theme.of(context).textTheme.bodySmall),
  );
}

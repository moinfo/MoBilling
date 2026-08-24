import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Satisfaction calls: ring the client, capture a rating and feedback.
///
/// Logging a call can also request an appointment — that is the only way an
/// appointment gets created, since appointments are satisfaction calls with
/// `appointment_requested` set rather than their own table.
class SatisfactionCallsScreen extends ConsumerStatefulWidget {
  const SatisfactionCallsScreen({super.key});

  @override
  ConsumerState<SatisfactionCallsScreen> createState() =>
      _SatisfactionCallsScreenState();
}

class _SatisfactionCallsScreenState
    extends ConsumerState<SatisfactionCallsScreen> {
  String? _status;

  static const _filters = <(String?, String)>[
    // `SatisfactionCall.status` is scheduled | completed | missed | cancelled
    // (ScheduleSatisfactionCalls sets `missed` when a scheduled date passes).
    (null, 'All'),
    ('scheduled', 'Scheduled'),
    ('missed', 'Missed'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(satisfactionDashboardProvider);
    final calls = ref.watch(satisfactionCallsProvider(_status));
    final status = context.statusColors;
    final canLog =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.satisfactionLog) ??
        false;

    return Scaffold(
      appBar: const ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Satisfaction calls',
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
                      label: 'Mine today',
                      value:
                          '${Formatting.integer(d.myStats.todayCompleted)}'
                          '/${Formatting.integer(d.myStats.todayTotal)}',
                    ),
                    StatRailItem(
                      label: 'Overdue',
                      value: Formatting.integer(d.stats.overdue),
                      emphasis: d.stats.overdue > 0 ? status.overdue : null,
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
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (v) => setState(() => _status = v),
          ),
          Expanded(
            child: CrmAsyncView(
              value: calls,
              errorTitle: 'Could not load calls',
              onRetry: () => ref.invalidate(satisfactionCallsProvider(_status)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.favorite_outline,
                      title: 'No calls in this view',
                      message:
                          'Scheduled satisfaction calls appear here as they fall due.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(satisfactionDashboardProvider);
                        ref.invalidate(satisfactionCallsProvider(_status));
                        await ref.read(
                          satisfactionCallsProvider(_status).future,
                        );
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
                                  onChanged: () {
                                    ref.invalidate(
                                      satisfactionDashboardProvider,
                                    );
                                    ref.invalidate(
                                      satisfactionCallsProvider(_status),
                                    );
                                  },
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

/// One call: the client, the rating as the trailing figure once given, the
/// dates in the metadata line, what they said, and the call-and-log row.
class _CallRow extends ConsumerWidget {
  const _CallRow({
    required this.call,
    required this.canLog,
    required this.onChanged,
  });

  final SatisfactionCall call;
  final bool canLog;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final canAct =
        canLog && (call.status == 'scheduled' || call.status == 'missed');
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
        hasPhone || canAct ? Spacing.xs : Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  call.clientName ?? 'Client',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (call.rating != null) ...[
                const SizedBox(width: Spacing.sm),
                RatingStars(rating: call.rating, compact: true),
              ],
            ],
          ),
          const SizedBox(height: Spacing.xs),
          CrmStatusLine(status: call.status, meta: meta),
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
          if (hasPhone || canAct) ...[
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

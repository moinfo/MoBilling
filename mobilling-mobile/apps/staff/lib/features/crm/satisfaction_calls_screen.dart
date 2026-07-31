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
    (null, 'All'),
    ('pending', 'Pending'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(satisfactionDashboardProvider);
    final calls = ref.watch(satisfactionCallsProvider(_status));
    final canLog = ref.watch(sessionControllerProvider).session?.can(
              CrmPermissions.satisfactionLog,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Satisfaction calls')),
      body: Column(
        children: [
          dashboard.maybeWhen(
            data: (d) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'My today',
                      value:
                          '${d.myStats.todayCompleted}/${d.myStats.todayTotal}',
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Overdue',
                      value: '${d.stats.overdue}',
                      emphasis: d.stats.overdue > 0
                          ? context.statusColors.overdue
                          : null,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Avg rating',
                      value: d.stats.avgRating == null
                          ? '—'
                          : d.stats.avgRating!.toStringAsFixed(1),
                      icon: Icons.star_outline_rounded,
                    ),
                  ),
                ],
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
              onRetry: () =>
                  ref.invalidate(satisfactionCallsProvider(_status)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.favorite_outline,
                      title: 'No calls in this view',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(satisfactionDashboardProvider);
                        ref.invalidate(satisfactionCallsProvider(_status));
                        await ref
                            .read(satisfactionCallsProvider(_status).future);
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: Spacing.sm),
                        itemBuilder: (context, index) => _CallCard(
                          call: items[index],
                          canLog: canLog,
                          onChanged: () {
                            ref.invalidate(satisfactionDashboardProvider);
                            ref.invalidate(
                                satisfactionCallsProvider(_status));
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallCard extends ConsumerWidget {
  const _CallCard({
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(call.clientName ?? 'Client',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                StatusChip(call.status, dense: true),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (call.scheduledDate != null)
                  'scheduled ${Formatting.date(call.scheduledDate)}',
                if (call.calledAt != null)
                  'called ${Formatting.date(call.calledAt)}',
                if (call.isFollowUp) 'follow-up',
                if (call.assignedTo != null) '→ ${call.assignedTo}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (call.rating != null) ...[
              const SizedBox(height: Spacing.xs),
              RatingStars(rating: call.rating),
            ],
            if (call.feedback != null) ...[
              const SizedBox(height: Spacing.xs),
              Text('“${call.feedback}”',
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (call.appointmentRequested) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.event_available_outlined,
                      size: 14, color: context.statusColors.pending),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    'Appointment ${call.appointmentStatus ?? 'requested'}'
                    '${call.appointmentDate == null ? '' : ' · ${Formatting.date(call.appointmentDate)}'}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: context.statusColors.pending),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                if (call.clientPhone != null)
                  ContactRow(phone: call.clientPhone, compact: true),
                const Spacer(),
                if (canLog && call.status == 'pending')
                  FilledButton.tonal(
                    onPressed: () => _showLogSheet(context, ref),
                    child: const Text('Log call'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogSheet(BuildContext context, WidgetRef ref) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
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

class _LogSatisfactionSheetState
    extends ConsumerState<_LogSatisfactionSheet> {
  final _feedback = TextEditingController();
  final _internalNotes = TextEditingController();
  final _appointmentNotes = TextEditingController();

  static const _outcomes = <(String, String)>[
    ('reached', 'Reached and spoke'),
    ('no_answer', 'No answer'),
    ('wrong_number', 'Wrong number'),
    ('call_back', 'Asked to call back'),
  ];

  String _outcome = 'reached';
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
      await ref.read(crmServiceProvider).logSatisfactionCall(
            widget.call.id,
            outcome: _outcome,
            rating: _rating,
            feedback:
                _feedback.text.trim().isEmpty ? null : _feedback.text.trim(),
            internalNotes: _internalNotes.text.trim().isEmpty
                ? null
                : _internalNotes.text.trim(),
            appointmentRequested: _wantsAppointment ? true : null,
            appointmentDate: _wantsAppointment ? _appointmentDate : null,
            appointmentNotes: _wantsAppointment &&
                    _appointmentNotes.text.trim().isNotEmpty
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
    final theme = Theme.of(context);
    final reached = _outcome == 'reached';

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log call',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            Text(widget.call.clientName ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            DropdownButtonFormField<String>(
              initialValue: _outcome,
              decoration: const InputDecoration(labelText: 'Outcome'),
              items: [
                for (final (value, label) in _outcomes)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged:
                  _submitting ? null : (v) => setState(() => _outcome = v!),
            ),
            // Rating and feedback only make sense if someone actually spoke.
            if (reached) ...[
              const SizedBox(height: Spacing.md),
              Text('Rating', style: theme.textTheme.labelMedium),
              Center(
                child: RatingStars(
                  rating: _rating,
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _feedback,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What did they say?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('They want an appointment'),
                value: _wantsAppointment,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _wantsAppointment = v),
              ),
              if (_wantsAppointment) ...[
                InkWell(
                  onTap: _submitting ? null : _pickAppointment,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Appointment date',
                      suffixIcon:
                          Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(_appointmentDate == null
                        ? 'Choose a date'
                        : Formatting.date(_appointmentDate)),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: _appointmentNotes,
                  decoration: const InputDecoration(
                      labelText: 'Appointment notes (optional)'),
                ),
              ],
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _internalNotes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Internal notes (not shared)',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save call'),
            ),
          ],
        ),
      ),
    );
  }
}

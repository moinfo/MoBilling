import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../router.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Appointments booked off satisfaction calls.
///
/// There is no appointments table — an appointment is a satisfaction call with
/// `appointment_requested` set, which is why the status actions here PATCH the
/// call's appointment fields rather than a separate resource.
class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('pending', 'Pending'),
    ('confirmed', 'Confirmed'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  Future<void> _update(
    Appointment appointment, {
    String? status,
    DateTime? date,
    String? notes,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .updateAppointment(
            appointment.id,
            appointmentStatus: status,
            appointmentDate: date,
            appointmentNotes: notes,
          );
      ref.invalidate(appointmentsProvider(_status));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            date != null ? 'Appointment moved.' : 'Marked $status.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Web's status-change modal always asks for notes before it PATCHes; a
  /// sheet returning `null` means the user backed out rather than confirmed
  /// with no notes (which comes back as `''`).
  Future<void> _changeStatus(Appointment appointment, String status) async {
    final notes = await showCrmSheet<String>(
      context: context,
      builder: (_) => _StatusNotesSheet(
        status: status,
        initialNotes: appointment.appointmentNotes,
      ),
    );
    if (notes == null) return;
    await _update(appointment, status: status, notes: notes.isEmpty ? null : notes);
  }

  Future<void> _reschedule(Appointment appointment) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: appointment.appointmentDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    // The API requires the status on every update; resend the current one.
    if (picked != null) {
      await _update(
        appointment,
        status: appointment.appointmentStatus ?? 'pending',
        date: picked,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(appointmentsProvider(_status));
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Engagement', title: 'Appointments'),
      body: Column(
        children: [
          page.maybeWhen(
            data: (p) => Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                0,
              ),
              child: StatRail(
                items: [
                  StatRailItem(
                    label: 'Today',
                    value: Formatting.integer(p.stats.today),
                  ),
                  StatRailItem(
                    label: 'Upcoming',
                    value: Formatting.integer(p.stats.upcoming),
                  ),
                  StatRailItem(
                    label: 'Overdue',
                    value: Formatting.integer(p.stats.overdue),
                    emphasis: p.stats.overdue > 0 ? status.overdue : null,
                  ),
                  StatRailItem(
                    label: 'Pending',
                    value: Formatting.integer(p.stats.pending),
                  ),
                  StatRailItem(
                    label: 'Confirmed',
                    value: Formatting.integer(p.stats.confirmed),
                  ),
                  StatRailItem(
                    label: 'Completed',
                    value: Formatting.integer(p.stats.completed),
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
              value: page,
              errorTitle: 'Could not load appointments',
              onRetry: () => ref.invalidate(appointmentsProvider(_status)),
              builder: (p) => p.page.isEmpty
                  ? const StateMessage(
                      icon: Icons.event_outlined,
                      title: 'No appointments',
                      message:
                          'Appointments booked during satisfaction calls appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(appointmentsProvider(_status).future),
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
                              for (final appointment in p.page.items)
                                _AppointmentTile(
                                  appointment: appointment,
                                  onStatusChange: (s) =>
                                      _changeStatus(appointment, s),
                                  onReschedule: () => _reschedule(appointment),
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

/// Colours for a satisfaction-call outcome. `StatusColors.forStatus` doesn't
/// know these values (they're call outcomes, not document/appointment
/// statuses), so map them here onto the same green/amber/red/grey vocabulary
/// the rest of the app already uses.
Color _outcomeColor(BuildContext context, String outcome) {
  final status = context.statusColors;
  return switch (outcome) {
    'satisfied' => status.settled,
    'needs_improvement' => status.attention,
    'complaint' => status.overdue,
    'suggestion' => status.pending,
    _ => status.inactive, // no_answer, unreachable
  };
}

/// A dense pill for `Appointment.outcome`, styled like [StatusChip] since it
/// sits right next to one.
class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.outcome});

  final String outcome;

  @override
  Widget build(BuildContext context) {
    final color = _outcomeColor(context, outcome);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: 2,
      ),
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

/// One appointment: who, when (and how late), where, and the status menu.
class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    required this.onStatusChange,
    required this.onReschedule,
  });

  final Appointment appointment;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = appointment.appointmentStatus ?? 'pending';
    final settled = status == 'completed' || status == 'cancelled';
    final days = Formatting.daysUntil(appointment.appointmentDate);
    final late = !settled && (days ?? 0) < 0;
    final clientId = appointment.clientId;

    final meta = [
      if (appointment.appointmentDate != null)
        Formatting.date(appointment.appointmentDate),
      if (!settled && days != null)
        days < 0
            ? '${-days}d late'
            : days == 0
            ? 'today'
            : 'in ${days}d',
    ].join(' · ');

    return ListTile(
      title: GestureDetector(
        onTap: clientId == null
            ? null
            : () => context.push(Routes.clientPath(clientId)),
        child: Text(
          appointment.clientName ?? 'Client',
          style: theme.textTheme.titleSmall?.copyWith(
            color: clientId == null ? null : scheme.primary,
            decoration: clientId == null ? null : TextDecoration.underline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.xs),
          CrmStatusLine(
            status: status,
            meta: meta,
            tone: late ? context.statusColors.overdue : null,
          ),
          if (appointment.outcome != null) ...[
            const SizedBox(height: Spacing.xs),
            _OutcomeBadge(outcome: appointment.outcome!),
          ],
          if (appointment.assignedTo != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Assigned to ${appointment.assignedTo}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (appointment.clientAddress != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 14, color: scheme.outline),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    appointment.clientAddress!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (appointment.appointmentNotes != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              appointment.appointmentNotes!,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ContactRow(phone: appointment.clientPhone, compact: true),
          if (!settled)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
              tooltip: 'Appointment actions',
              onSelected: (action) => switch (action) {
                'reschedule' => onReschedule(),
                _ => onStatusChange(action),
              },
              itemBuilder: (context) => [
                if (status != 'confirmed')
                  const PopupMenuItem(value: 'confirmed', child: Text('Confirm')),
                const PopupMenuItem(
                  value: 'completed',
                  child: Text('Mark completed'),
                ),
                const PopupMenuItem(
                  value: 'reschedule',
                  child: Text('Reschedule'),
                ),
                const PopupMenuItem(
                  value: 'cancelled',
                  child: Text('Cancel appointment'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Notes captured on every status change, as the web modal requires.
class _StatusNotesSheet extends StatefulWidget {
  const _StatusNotesSheet({required this.status, this.initialNotes});

  final String status;
  final String? initialNotes;

  @override
  State<_StatusNotesSheet> createState() => _StatusNotesSheetState();
}

class _StatusNotesSheetState extends State<_StatusNotesSheet> {
  late final _notes = TextEditingController(text: widget.initialNotes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = switch (widget.status) {
      'confirmed' => 'Confirm',
      'completed' => 'Mark completed',
      'cancelled' => 'Cancel appointment',
      _ => 'Save',
    };

    return CrmSheet(
      eyebrow: 'Appointment',
      title: action,
      children: [
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Visit notes, observations, next steps…',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_notes.text.trim()),
          child: Text(action),
        ),
      ],
    );
  }
}

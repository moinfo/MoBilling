import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

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
  ConsumerState<AppointmentsScreen> createState() =>
      _AppointmentsScreenState();
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
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .updateAppointment(
            appointment.id,
            appointmentStatus: status,
            appointmentDate: date,
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
                                  onConfirm: () =>
                                      _update(appointment, status: 'confirmed'),
                                  onComplete: () =>
                                      _update(appointment, status: 'completed'),
                                  onCancel: () =>
                                      _update(appointment, status: 'cancelled'),
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

/// One appointment: who, when (and how late), where, and the status menu.
class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    required this.onConfirm,
    required this.onComplete,
    required this.onCancel,
    required this.onReschedule,
  });

  final Appointment appointment;
  final VoidCallback onConfirm;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = appointment.appointmentStatus ?? 'pending';
    final settled = status == 'completed' || status == 'cancelled';
    final days = Formatting.daysUntil(appointment.appointmentDate);
    final late = !settled && (days ?? 0) < 0;

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
      title: Text(
        appointment.clientName ?? 'Client',
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
                'confirm' => onConfirm(),
                'complete' => onComplete(),
                'cancel' => onCancel(),
                _ => onReschedule(),
              },
              itemBuilder: (context) => [
                if (status != 'confirmed')
                  const PopupMenuItem(value: 'confirm', child: Text('Confirm')),
                const PopupMenuItem(
                  value: 'complete',
                  child: Text('Mark completed'),
                ),
                const PopupMenuItem(
                  value: 'reschedule',
                  child: Text('Reschedule'),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancel appointment'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

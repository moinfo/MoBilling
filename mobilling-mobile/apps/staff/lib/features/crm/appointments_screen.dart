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
      await ref.read(crmServiceProvider).updateAppointment(
            appointment.id,
            appointmentStatus: status,
            appointmentDate: date,
          );
      ref.invalidate(appointmentsProvider(_status));
      messenger.showSnackBar(
          SnackBar(content: Text(date != null ? 'Moved.' : 'Marked $status.')));
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
      await _update(appointment,
          status: appointment.appointmentStatus ?? 'pending', date: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(appointmentsProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('Appointments')),
      body: Column(
        children: [
          page.maybeWhen(
            data: (p) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Today',
                      value: '${p.stats.today}',
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Upcoming',
                      value: '${p.stats.upcoming}',
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Overdue',
                      value: '${p.stats.overdue}',
                      emphasis: p.stats.overdue > 0
                          ? context.statusColors.overdue
                          : null,
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
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        itemCount: p.page.items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: Spacing.sm),
                        itemBuilder: (context, index) {
                          final appointment = p.page.items[index];
                          return _AppointmentCard(
                            appointment: appointment,
                            onConfirm: () =>
                                _update(appointment, status: 'confirmed'),
                            onComplete: () =>
                                _update(appointment, status: 'completed'),
                            onCancel: () =>
                                _update(appointment, status: 'cancelled'),
                            onReschedule: () => _reschedule(appointment),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
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
    final status = appointment.appointmentStatus ?? 'pending';
    final settled = status == 'completed' || status == 'cancelled';
    final days = Formatting.daysUntil(appointment.appointmentDate);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(appointment.clientName ?? 'Client',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                StatusChip(status, dense: true),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (appointment.appointmentDate != null)
                  Formatting.date(appointment.appointmentDate),
                if (!settled && days != null)
                  days < 0
                      ? '${-days}d late'
                      : days == 0
                          ? 'today'
                          : 'in ${days}d',
                if (appointment.assignedTo != null)
                  '→ ${appointment.assignedTo}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: !settled && (days ?? 0) < 0
                    ? context.statusColors.overdue
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (appointment.clientAddress != null) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(appointment.clientAddress!,
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            if (appointment.appointmentNotes != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(appointment.appointmentNotes!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                if (appointment.clientPhone != null)
                  ContactRow(phone: appointment.clientPhone, compact: true),
                const Spacer(),
                if (!settled)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) => switch (action) {
                      'confirm' => onConfirm(),
                      'complete' => onComplete(),
                      'cancel' => onCancel(),
                      _ => onReschedule(),
                    },
                    itemBuilder: (context) => [
                      if (status != 'confirmed')
                        const PopupMenuItem(
                            value: 'confirm', child: Text('Confirm')),
                      const PopupMenuItem(
                          value: 'complete', child: Text('Mark completed')),
                      const PopupMenuItem(
                          value: 'reschedule', child: Text('Reschedule')),
                      const PopupMenuItem(
                          value: 'cancel', child: Text('Cancel')),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

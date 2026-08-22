import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, FilterStrip;
import 'staff_self_providers.dart';

/// Periodic staff reports — what you did, what blocked you, what's next.
///
/// The API decides whose reports come back: your own, plus subordinates' if
/// you review, plus everyone's if you manage. Nothing here filters by user.
class StaffReportsScreen extends ConsumerStatefulWidget {
  const StaffReportsScreen({super.key});

  @override
  ConsumerState<StaffReportsScreen> createState() =>
      _StaffReportsScreenState();
}

class _StaffReportsScreenState extends ConsumerState<StaffReportsScreen> {
  String? _type;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('daily', 'Daily'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
  ];

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(staffReportsProvider(_type));
    final canSubmit = ref.watch(sessionControllerProvider).session?.can(
            'staff_reports.submit') ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Staff reports')),
      floatingActionButton: canSubmit
          ? FloatingActionButton.extended(
              onPressed: () => _submit(context),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Submit'),
            )
          : null,
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _type,
            onSelect: (v) => setState(() => _type = v),
          ),
          Expanded(
            child: CrmAsyncView(
              value: reports,
              errorTitle: 'Could not load reports',
              onRetry: () => ref.invalidate(staffReportsProvider(_type)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.assignment_outlined,
                      title: 'No reports yet',
                      message: 'Submit your first report with the button below.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(staffReportsProvider(_type));
                        await ref.read(staffReportsProvider(_type).future);
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: Spacing.sm),
                        itemBuilder: (context, index) => _ReportCard(
                          report: items[index],
                          onChanged: () =>
                              ref.invalidate(staffReportsProvider(_type)),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _SubmitReportSheet(),
    );
    if (saved == true) ref.invalidate(staffReportsProvider(_type));
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report, required this.onChanged});

  final StaffReport report;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(report.periodLabel),
        subtitle: Text(
          [
            if (report.userName != null) report.userName!,
            report.reportType,
            if (report.isLate) 'late',
            if (report.isReviewed) 'reviewed',
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: report.isLate ? status.attention : null,
          ),
        ),
        trailing: report.rating == null
            ? StatusChip(report.isReviewed ? 'active' : 'pending', dense: true)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded,
                      size: 16, color: status.attention),
                  Text('${report.rating}',
                      style: theme.textTheme.labelLarge),
                ],
              ),
        childrenPadding: const EdgeInsets.fromLTRB(
            Spacing.md, 0, Spacing.md, Spacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.achievements != null)
            _Section('Achievements', report.achievements!),
          if (report.challenges != null)
            _Section('Challenges', report.challenges!),
          if (report.plans != null) _Section('Plans', report.plans!),
          if (report.reviewNotes != null) ...[
            const Divider(height: Spacing.lg),
            _Section('Review by ${report.reviewerName ?? 'supervisor'}',
                report.reviewNotes!),
          ],
          if (report.replies.isNotEmpty) ...[
            const Divider(height: Spacing.lg),
            Text('Discussion', style: theme.textTheme.labelMedium),
            const SizedBox(height: Spacing.xs),
            for (final reply in report.replies)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reply.userName ?? 'Someone'} · ${Formatting.date(reply.createdAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: reply.isReviewer
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(reply.message, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.reply_outlined, size: 16),
              label: const Text('Reply'),
              onPressed: () => _reply(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reply(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reply'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;

    try {
      await ref
          .read(staffSelfServiceProvider)
          .replyToStaffReport(report.id, message);
      onChanged();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, this.body);

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SubmitReportSheet extends ConsumerStatefulWidget {
  const _SubmitReportSheet();

  @override
  ConsumerState<_SubmitReportSheet> createState() =>
      _SubmitReportSheetState();
}

class _SubmitReportSheetState extends ConsumerState<_SubmitReportSheet> {
  final _achievements = TextEditingController();
  final _challenges = TextEditingController();
  final _plans = TextEditingController();

  String _type = 'daily';
  DateTime _period = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _achievements.dispose();
    _challenges.dispose();
    _plans.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_achievements.text.trim().isEmpty) {
      setState(() => _error = 'Describe what you achieved.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(staffSelfServiceProvider).submitStaffReport(
            reportType: _type,
            periodDate: _period,
            achievements: _achievements.text.trim(),
            challenges: _challenges.text.trim().isEmpty
                ? null
                : _challenges.text.trim(),
            plans: _plans.text.trim().isEmpty ? null : _plans.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error =
          e.errorFor('period_date') ?? e.errorFor('achievements') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            Text('Submit report',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Period'),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged:
                  _submitting ? null : (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: Spacing.md),
            InkWell(
              onTap: _submitting
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _period,
                        firstDate: DateTime(DateTime.now().year - 1),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _period = picked);
                    },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Period date',
                  helperText: 'Any date inside the period being reported',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(Formatting.date(_period)),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _achievements,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What did you achieve?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _challenges,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Challenges (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _plans,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Plans (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
  }
}

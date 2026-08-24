import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'staff_self_providers.dart';

// ---------------------------------------------------------------------------
// Staff targets
// ---------------------------------------------------------------------------

/// Performance targets and their commission.
///
/// The lifecycle is assigned → self-reported → verified, and only *verified*
/// numbers pay. The screen therefore labels commission as an estimate until
/// a supervisor has signed off.
class StaffTargetsScreen extends ConsumerStatefulWidget {
  const StaffTargetsScreen({super.key});

  @override
  ConsumerState<StaffTargetsScreen> createState() =>
      _StaffTargetsScreenState();
}

class _StaffTargetsScreenState extends ConsumerState<StaffTargetsScreen> {
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'To report'),
    ('self_reported', 'Awaiting check'),
    ('verified', 'Verified'),
  ];

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(staffTargetsProvider(_status));

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'HR', title: 'My targets'),
      body: Column(
        children: [
          _ChoiceRow(
            options: _filters,
            selected: _status,
            onSelect: (v) => setState(() => _status = v),
          ),
          Expanded(
            child: CrmAsyncView(
              value: targets,
              errorTitle: 'Could not load targets',
              onRetry: () => ref.invalidate(staffTargetsProvider(_status)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.flag_outlined,
                      title: 'No targets',
                      message: 'Targets assigned to you appear here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) => _TargetCard(
                        target: items[index],
                        onChanged: () =>
                            ref.invalidate(staffTargetsProvider(_status)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet single row of choice chips under the masthead. `null` is "all".
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      itemCount: options.length,
      separatorBuilder: (context, index) => const SizedBox(width: Spacing.sm),
      itemBuilder: (context, index) {
        final (value, label) = options[index];
        return ChoiceChip(
          label: Text(label.toUpperCase()),
          selected: selected == value,
          showCheckmark: false,
          onSelected: (_) => onSelect(value),
        );
      },
    ),
  );
}

class _TargetCard extends ConsumerWidget {
  const _TargetCard({required this.target, required this.onChanged});

  final StaffTarget target;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final eyebrow = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    target.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                StatusChip(target.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                if (target.periodStart != null && target.periodEnd != null)
                  '${Formatting.date(target.periodStart)} – ${Formatting.date(target.periodEnd)}',
                if (target.assignedByName != null)
                  'by ${target.assignedByName}',
              ].join(' · ').toUpperCase(),
              style: eyebrow,
            ),
            const SizedBox(height: Spacing.md),
            for (final criterion in target.criteria) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      criterion.label,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    '${Formatting.amount(criterion.effectiveValue ?? 0)} / ${Formatting.amount(criterion.goalValue)}'
                            '${criterion.unit == null ? '' : ' ${criterion.unit}'}'
                        .toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: criterion.goalMet == true
                          ? status.settled
                          : scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: criterion.progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    criterion.goalMet == true ? status.settled : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            if (target.totalCommission > 0) ...[
              const Divider(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Honest about what the number means before sign-off.
                      (target.isVerified
                              ? 'Commission earned'
                              : 'Estimated commission')
                          .toUpperCase(),
                      style: eyebrow,
                    ),
                  ),
                  Money(
                    target.totalCommission,
                    color: target.isVerified ? status.settled : null,
                  ),
                ],
              ),
            ],
            if ((target.salaryDeduction ?? 0) > 0) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text('SALARY DEDUCTION', style: eyebrow),
                  ),
                  Money(
                    target.salaryDeduction,
                    scale: MoneyScale.dense,
                    color: status.overdue,
                  ),
                ],
              ),
            ],
            if (target.supervisorNotes != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                target.supervisorNotes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (target.awaitingSelfReport && target.criteria.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                onPressed: () => _selfReport(context, ref),
                child: const Text('Report my numbers'),
              ),
            ],
            if (target.awaitingVerification) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Waiting for your supervisor to verify.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.pending,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selfReport(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _SelfReportSheet(target: target),
    );
    if (saved == true) onChanged();
  }
}

class _SelfReportSheet extends ConsumerStatefulWidget {
  const _SelfReportSheet({required this.target});

  final StaffTarget target;

  @override
  ConsumerState<_SelfReportSheet> createState() => _SelfReportSheetState();
}

class _SelfReportSheetState extends ConsumerState<_SelfReportSheet> {
  late final Map<String, TextEditingController> _controllers;
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final criterion in widget.target.criteria)
        criterion.id: TextEditingController(
          text: criterion.achievedValue?.toStringAsFixed(0) ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final values = <String, double>{};
    for (final entry in _controllers.entries) {
      final parsed = double.tryParse(entry.value.text.trim());
      if (parsed == null) {
        setState(() => _error = 'Enter a number for every criterion.');
        return;
      }
      values[entry.key] = parsed;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(staffSelfServiceProvider)
          .selfReportTarget(
            widget.target.id,
            values: values,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'TARGET',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text('Report my numbers', style: Type.display(22)),
            const SizedBox(height: Spacing.xs),
            Text(
              widget.target.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            for (final criterion in widget.target.criteria) ...[
              Text(criterion.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _controllers[criterion.id],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'Achieved',
                  helperText:
                      'Goal ${Formatting.amount(criterion.goalValue)}${criterion.unit == null ? '' : ' ${criterion.unit}'}',
                  suffixText: criterion.unit,
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            Text('Notes', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _notes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Optional — anything your supervisor should know',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Submitting…' : 'Submit for review',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Your supervisor confirms these before commission is paid.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System verifications
// ---------------------------------------------------------------------------

/// Daily system checks. Each row shows whether today's check is done, and
/// submitting one is a two-tap action.
class MyVerificationsScreen extends ConsumerWidget {
  const MyVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verifications = ref.watch(systemVerificationsProvider);
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'My verifications',
      ),
      body: CrmAsyncView(
        value: verifications,
        errorTitle: 'Could not load verifications',
        onRetry: () => ref.invalidate(systemVerificationsProvider),
        builder: (items) {
          final active = items.where((v) => v.isActive).toList();
          if (active.isEmpty) {
            return const StateMessage(
              icon: Icons.verified_user_outlined,
              title: 'Nothing to verify',
              message: 'Systems assigned to you for daily checks appear here.',
            );
          }

          final pending = active.where((v) => !v.checkedToday).length;
          final issues = active.where((v) => v.hasIssueToday).length;
          final clear = active.length - pending - issues;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(systemVerificationsProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Reveal(
                  child: StatRail(
                    items: [
                      StatRailItem(
                        label: 'To check',
                        value: Formatting.integer(pending),
                        emphasis: pending > 0 ? status.attention : null,
                      ),
                      StatRailItem(
                        label: 'All good',
                        value: Formatting.integer(clear),
                        emphasis: clear > 0 ? status.settled : null,
                      ),
                      StatRailItem(
                        label: 'Issues',
                        value: Formatting.integer(issues),
                        emphasis: issues > 0 ? status.overdue : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                SectionHeader(
                  'Today · ${Formatting.date(DateTime.now())}',
                ),
                const SizedBox(height: Spacing.sm),
                for (final (i, verification) in active.indexed) ...[
                  if (i > 0) const SizedBox(height: Spacing.sm),
                  _VerificationCard(verification: verification),
                ],
                const SizedBox(height: Spacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends ConsumerWidget {
  const _VerificationCard({required this.verification});

  final SystemVerification verification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

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
                    verification.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (verification.checkedToday)
                  StatusChip(
                    verification.hasIssueToday ? 'overdue' : 'active',
                    dense: true,
                  ),
              ],
            ),
            if (verification.domainName != null) ...[
              const SizedBox(height: 2),
              Text(
                verification.domainName!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (verification.checkedToday) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                verification.hasIssueToday
                    ? 'Issue reported${verification.todayNotes == null ? '' : ': ${verification.todayNotes}'}'
                    : 'Checked — all good',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: verification.hasIssueToday
                      ? status.overdue
                      : status.settled,
                ),
              ),
            ] else ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('All good'),
                      onPressed: () => _submit(context, ref, 'ok'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.report_problem_outlined, size: 18),
                      label: const Text('Report issue'),
                      onPressed: () => _reportIssue(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    String status, {
    String? notes,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(staffSelfServiceProvider)
          .submitVerification(verification.id, status: status, notes: notes);
      ref.invalidate(systemVerificationsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Check recorded.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reportIssue(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Issue with ${verification.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What is wrong?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Report issue'),
          ),
        ],
      ),
    );
    if (notes == null || notes.isEmpty) return;
    if (!context.mounted) return;
    await _submit(context, ref, 'issue', notes: notes);
  }
}

// ---------------------------------------------------------------------------
// System records
// ---------------------------------------------------------------------------

class SystemRecordsScreen extends ConsumerStatefulWidget {
  const SystemRecordsScreen({super.key});

  @override
  ConsumerState<SystemRecordsScreen> createState() =>
      _SystemRecordsScreenState();
}

class _SystemRecordsScreenState extends ConsumerState<SystemRecordsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'System records',
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) =>
            ref.read(staffSelfServiceProvider).systemRecords(page: page),
        itemBuilder: (context, record) => Card(
          child: ListTile(
            title: Text(
              record.systemName ?? '—',
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (record.propertyName != null) record.propertyName!,
                  Formatting.date(record.recordDate),
                  if (record.bankName != null) record.bankName!,
                  if (record.createdByName != null) record.createdByName!,
                ].join(' · ').toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            trailing: Money(record.amount),
          ),
        ),
        emptyIcon: Icons.dns_outlined,
        emptyTitle: 'No system records',
        emptyMessage: 'Records appear here as they are entered.',
      ),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        FilterStrip,
        showCrmSheet;
import 'staff_self_providers.dart';

// ---------------------------------------------------------------------------
// Staff targets
// ---------------------------------------------------------------------------

/// Performance targets and their commission.
///
/// The lifecycle is assigned → self-reported → verified, and only *verified*
/// numbers pay. The screen therefore labels commission as an estimate until a
/// supervisor has signed off — and carries both halves of that loop: the
/// staff member's self-report and, behind `staff_targets.verify`, the
/// supervisor's confirmation.
class StaffTargetsScreen extends ConsumerWidget {
  const StaffTargetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    final canManage =
        session?.can(StaffSelfPermissions.staffTargetsManage) ?? false;
    final canVerify =
        session?.can(StaffSelfPermissions.staffTargetsVerify) ?? false;

    final tabs = <(String, Widget)>[
      ('Targets', _TargetsTab(canManage: canManage, canVerify: canVerify)),
      ('Commission', const _CommissionTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'HR',
          title: 'Staff targets',
          trailing: canManage
              ? InkActionButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Assign a target',
                  onPressed: () => _openTargetForm(context, ref),
                )
              : null,
          bottom: InkTabBar(tabs: [for (final (label, _) in tabs) label]),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

Future<void> _openTargetForm(
  BuildContext context,
  WidgetRef ref, {
  StaffTarget? target,
}) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _TargetFormSheet(target: target),
  );
  if (saved == true) {
    ref
      ..invalidate(staffTargetsProvider)
      ..invalidate(targetCommissionsProvider);
  }
}

class _TargetsTab extends ConsumerStatefulWidget {
  const _TargetsTab({required this.canManage, required this.canVerify});

  final bool canManage;
  final bool canVerify;

  @override
  ConsumerState<_TargetsTab> createState() => _TargetsTabState();
}

class _TargetsTabState extends ConsumerState<_TargetsTab> {
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

    return Column(
      children: [
        FilterStrip(
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
                ? StateMessage(
                    icon: Icons.flag_outlined,
                    title: 'No targets',
                    message: widget.canManage
                        ? 'Assign one to start the loop.'
                        : 'Targets assigned to you appear here.',
                    actionLabel: widget.canManage ? 'Assign a target' : null,
                    onAction: widget.canManage
                        ? () => _openTargetForm(context, ref)
                        : null,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(staffTargetsProvider(_status));
                      await ref.read(staffTargetsProvider(_status).future);
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) => _TargetCard(
                        target: items[index],
                        canManage: widget.canManage,
                        canVerify: widget.canVerify,
                        onChanged: _refresh,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _refresh() => ref
    ..invalidate(staffTargetsProvider(_status))
    ..invalidate(targetCommissionsProvider)
    ..invalidate(dashboardProvider);
}

class _TargetCard extends ConsumerWidget {
  const _TargetCard({
    required this.target,
    required this.canManage,
    required this.canVerify,
    required this.onChanged,
  });

  final StaffTarget target;
  final bool canManage;
  final bool canVerify;
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
                if (target.userName != null) target.userName!,
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
                  Expanded(child: Text('SALARY DEDUCTION', style: eyebrow)),
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
            if (target.awaitingVerification && !canVerify) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Waiting for your supervisor to verify.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.pending,
                ),
              ),
            ],
            // Each action is exactly the permission its route asks for.
            if (_hasActions) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                children: [
                  if (target.awaitingSelfReport && target.criteria.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.edit_note_outlined, size: 16),
                      label: const Text('Report my numbers'),
                      onPressed: () => _selfReport(context, ref),
                    ),
                  if (canVerify &&
                      target.isVerifiable &&
                      target.criteria.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: const Text('Verify'),
                      onPressed: () => _verify(context, ref),
                    ),
                  if (canManage && target.isEditable)
                    TextButton.icon(
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Edit'),
                      onPressed: () =>
                          _openTargetForm(context, ref, target: target),
                    ),
                  if (canManage && target.isDeletable)
                    TextButton.icon(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: scheme.error,
                      ),
                      label: Text(
                        'Delete',
                        style: TextStyle(color: scheme.error),
                      ),
                      onPressed: () => _delete(context, ref),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasActions =>
      (target.awaitingSelfReport && target.criteria.isNotEmpty) ||
      (canVerify && target.isVerifiable && target.criteria.isNotEmpty) ||
      (canManage && (target.isEditable || target.isDeletable));

  Future<void> _selfReport(BuildContext context, WidgetRef ref) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _TargetValuesSheet(target: target, verifying: false),
    );
    if (saved == true) onChanged();
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _TargetValuesSheet(target: target, verifying: true),
    );
    if (saved == true) onChanged();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this target?'),
        content: Text(
          '"${target.title}" and everything reported against it will be '
          'removed for ${target.userName ?? 'this staff member'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(staffSelfServiceProvider).deleteStaffTarget(target.id);
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Target deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// One sheet for both halves of the loop.
///
/// Self-report and verify take the same shape — a number per criterion and a
/// note — and differ only in which field they write (`achieved_value` vs
/// `verified_value`), what the note is called, and who is allowed to send it.
/// Verifying pre-fills what the staff member reported, because confirming it
/// unchanged is the common case.
class _TargetValuesSheet extends ConsumerStatefulWidget {
  const _TargetValuesSheet({required this.target, required this.verifying});

  final StaffTarget target;
  final bool verifying;

  @override
  ConsumerState<_TargetValuesSheet> createState() => _TargetValuesSheetState();
}

class _TargetValuesSheetState extends ConsumerState<_TargetValuesSheet> {
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
          text: _initial(criterion)?.toStringAsFixed(0) ?? '',
        ),
    };
    if (widget.verifying && widget.target.supervisorNotes != null) {
      _notes.text = widget.target.supervisorNotes!;
    }
  }

  double? _initial(TargetCriterion c) =>
      widget.verifying ? (c.verifiedValue ?? c.achievedValue) : c.achievedValue;

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
      if (parsed == null || parsed < 0) {
        setState(() => _error = 'Enter a number for every criterion.');
        return;
      }
      values[entry.key] = parsed;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    try {
      final service = ref.read(staffSelfServiceProvider);
      if (widget.verifying) {
        await service.verifyTarget(
          widget.target.id,
          values: values,
          supervisorNotes: notes,
        );
      } else {
        await service.selfReportTarget(
          widget.target.id,
          values: values,
          notes: notes,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.verifying
                ? 'Verified — commission is now confirmed.'
                : 'Sent to your supervisor for verification.',
          ),
        ),
      );
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
    final verifying = widget.verifying;

    return CrmSheet(
      eyebrow: verifying
          ? 'Target · ${widget.target.userName ?? 'staff'}'
          : 'Target',
      title: verifying ? 'Verify the numbers' : 'Report my numbers',
      children: [
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
          CrmField(
            label: criterion.label,
            child: TextField(
              controller: _controllers[criterion.id],
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: verifying ? 'Confirmed' : 'Achieved',
                helperText: [
                  'Goal ${Formatting.amount(criterion.goalValue)}'
                      '${criterion.unit == null ? '' : ' ${criterion.unit}'}',
                  if (verifying && criterion.achievedValue != null)
                    'reported ${Formatting.amount(criterion.achievedValue)}',
                ].join(' · '),
                suffixText: criterion.unit,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: verifying ? 'Supervisor notes' : 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: verifying
                  ? 'Optional — recorded on the target'
                  : 'Optional — anything your supervisor should know',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Submitting…'
              : verifying
              ? 'Verify and pay'
              : 'Submit for review',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          verifying
              ? 'These figures decide the commission, the group bonus and any '
                    'salary deduction. A target can only be verified once.'
              : 'Your supervisor confirms these before commission is paid.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The target form — POST/PUT /staff-targets
// ---------------------------------------------------------------------------

/// One criterion, held as controllers while the form is open.
class _CriterionDraft {
  _CriterionDraft([TargetCriterionInput? from])
    : type = from?.type ?? 'custom',
      commissionType = from?.commissionType ?? 'none',
      label = TextEditingController(text: from?.label ?? ''),
      unit = TextEditingController(text: from?.unit ?? ''),
      goal = TextEditingController(
        text: from == null ? '' : Formatting.amount(from.goalValue),
      ),
      commissionValue = TextEditingController(
        text: from?.commissionValue == null
            ? ''
            : Formatting.amount(from!.commissionValue),
      );

  String type;
  String commissionType;
  final TextEditingController label;
  final TextEditingController unit;
  final TextEditingController goal;
  final TextEditingController commissionValue;

  void dispose() {
    label.dispose();
    unit.dispose();
    goal.dispose();
    commissionValue.dispose();
  }

  TargetCriterionInput? build() {
    final name = label.text.trim();
    final goalValue = double.tryParse(goal.text.trim().replaceAll(',', ''));
    if (name.isEmpty || goalValue == null) return null;
    return TargetCriterionInput(
      type: type,
      label: name,
      unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
      goalValue: goalValue,
      commissionType: commissionType,
      commissionValue: commissionType == 'none'
          ? null
          : double.tryParse(commissionValue.text.trim().replaceAll(',', '')),
    );
  }
}

const _criterionTypes = <(String, String)>[
  ('customer_count', 'Customers'),
  ('revenue', 'Revenue'),
  ('item_sales', 'Item sales'),
  ('custom', 'Custom'),
];

const _commissionTypes = <(String, String)>[
  ('none', 'No commission'),
  ('fixed', 'Fixed amount'),
  ('percentage', 'Percent of salary'),
];

class _TargetFormSheet extends ConsumerStatefulWidget {
  const _TargetFormSheet({this.target});

  final StaffTarget? target;

  @override
  ConsumerState<_TargetFormSheet> createState() => _TargetFormSheetState();
}

class _TargetFormSheetState extends ConsumerState<_TargetFormSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _salary = TextEditingController();
  final _groupValue = TextEditingController();
  final _managerValue = TextEditingController();

  late List<_CriterionDraft> _criteria;
  String? _userId;
  String? _managerId;
  String _groupType = 'none';
  String _managerType = 'none';
  bool _deductOnFailure = false;
  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;
  String? _error;

  bool get _editing => widget.target != null;

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    if (t == null) {
      _criteria = [_CriterionDraft()];
      return;
    }
    _title.text = t.title;
    _description.text = t.description ?? '';
    _salary.text = t.staffSalary == null
        ? ''
        : Formatting.amount(t.staffSalary);
    _groupType = t.groupCommissionType;
    _groupValue.text = t.groupCommissionValue == null
        ? ''
        : Formatting.amount(t.groupCommissionValue);
    _managerId = t.managerId;
    _managerType = t.managerCommissionType;
    _managerValue.text = t.managerCommissionValue == null
        ? ''
        : Formatting.amount(t.managerCommissionValue);
    _deductOnFailure = t.deductOnFailure;
    _userId = t.userId;
    _start = t.periodStart;
    _end = t.periodEnd;
    _criteria = [
      for (final c in t.criteria) _CriterionDraft(TargetCriterionInput.from(c)),
    ];
    if (_criteria.isEmpty) _criteria = [_CriterionDraft()];
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _salary.dispose();
    _groupValue.dispose();
    _managerValue.dispose();
    for (final c in _criteria) {
      c.dispose();
    }
    super.dispose();
  }

  double? _money(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', ''));

  Future<void> _pickPeriod({required bool end}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (end ? _end : _start) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _end = picked;
      } else {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    final criteria = <TargetCriterionInput>[];
    for (final draft in _criteria) {
      final built = draft.build();
      if (built == null) {
        setState(
          () => _error = 'Every criterion needs a label and a goal value.',
        );
        return;
      }
      criteria.add(built);
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the target a title.');
      return;
    }
    if (_userId == null) {
      setState(() => _error = 'Choose who this target is for.');
      return;
    }
    if (_start == null || _end == null) {
      setState(() => _error = 'Set the period this target covers.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(staffSelfServiceProvider);
      if (_editing) {
        await service.updateStaffTarget(
          widget.target!.id,
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          periodStart: _start,
          periodEnd: _end,
          criteria: criteria,
          groupCommissionType: _groupType,
          groupCommissionValue: _groupType == 'none'
              ? null
              : _money(_groupValue),
          staffSalary: _money(_salary),
          deductOnFailure: _deductOnFailure,
          managerId: _managerId,
          managerCommissionType: _managerId == null ? 'none' : _managerType,
          managerCommissionValue: _managerId == null || _managerType == 'none'
              ? null
              : _money(_managerValue),
        );
      } else {
        await service.createStaffTarget(
          userId: _userId!,
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          periodStart: _start!,
          periodEnd: _end!,
          criteria: criteria,
          groupCommissionType: _groupType,
          groupCommissionValue: _groupType == 'none'
              ? null
              : _money(_groupValue),
          staffSalary: _money(_salary),
          deductOnFailure: _deductOnFailure,
          managerId: _managerId,
          managerCommissionType: _managerId == null ? 'none' : _managerType,
          managerCommissionValue: _managerId == null || _managerType == 'none'
              ? null
              : _money(_managerValue),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Target updated.' : 'Target assigned.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('user_id') ??
            e.errorFor('period_end') ??
            e.errorFor('criteria') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colleagues = ref.watch(colleaguesProvider);

    return CrmSheet(
      eyebrow: 'Staff targets',
      title: _editing ? 'Edit target' : 'Assign a target',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        // `/staff-reports/supervisors` is where the web's form gets its
        // people from, and it needs `staff_reports.review` — so say which
        // permission is missing rather than showing an empty dropdown.
        colleagues.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorBanner(
            message: e is ApiException
                ? 'Could not load the staff list: ${e.message}'
                : 'Could not load the staff list.',
            onRetry: () => ref.invalidate(colleaguesProvider),
          ),
          // The list is active staff only, so a target belonging to someone
          // since deactivated has an id with no matching item — which the
          // dropdown asserts on. Fall back to the hint in that case.
          data: (people) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CrmField(
                label: 'For',
                child: DropdownButtonFormField<String>(
                  initialValue: people.any((p) => p.id == _userId)
                      ? _userId
                      : null,
                  isExpanded: true,
                  hint: Text(
                    _editing
                        ? widget.target!.userName ?? 'Choose a staff member'
                        : 'Choose a staff member',
                  ),
                  items: [
                    for (final person in people)
                      DropdownMenuItem(
                        value: person.id,
                        child: Text(
                          person.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  // The assignee is fixed once the target exists — the update
                  // route does not accept a new user_id.
                  onChanged: _submitting || _editing
                      ? null
                      : (v) => setState(() => _userId = v),
                ),
              ),
              const SizedBox(height: Spacing.md),
              CrmField(
                label: 'Team lead (optional)',
                child: DropdownButtonFormField<String>(
                  initialValue:
                      people.any((p) => p.id == _managerId && p.id != _userId)
                      ? _managerId
                      : null,
                  isExpanded: true,
                  hint: const Text('Nobody'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Nobody')),
                    for (final person in people)
                      if (person.id != _userId)
                        DropdownMenuItem(
                          value: person.id,
                          child: Text(
                            person.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _managerId = v),
                ),
              ),
            ],
          ),
        ),
        if (_managerId != null) ...[
          const SizedBox(height: Spacing.md),
          _CommissionFields(
            label: 'Team lead override',
            type: _managerType,
            value: _managerValue,
            enabled: !_submitting,
            onType: (v) => setState(() => _managerType = v),
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Title',
          child: TextField(
            controller: _title,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. August new customers',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional — what good looks like',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: CrmPickerField(
                label: 'From',
                value: _start == null ? 'Pick a date' : Formatting.date(_start),
                placeholder: _start == null,
                onTap: _submitting ? null : () => _pickPeriod(end: false),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: CrmPickerField(
                label: 'To',
                value: _end == null ? 'Pick a date' : Formatting.date(_end),
                placeholder: _end == null,
                onTap: _submitting ? null : () => _pickPeriod(end: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Criteria'),
        const SizedBox(height: Spacing.sm),
        for (final (i, draft) in _criteria.indexed) ...[
          _CriterionEditor(
            index: i,
            draft: draft,
            enabled: !_submitting,
            onChanged: () => setState(() {}),
            onRemove: _criteria.length == 1
                ? null
                : () => setState(() {
                    _criteria.removeAt(i).dispose();
                  }),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a criterion'),
            onPressed: _submitting
                ? null
                : () => setState(() => _criteria.add(_CriterionDraft())),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Salary and bonus'),
        const SizedBox(height: Spacing.sm),
        CrmField(
          label: 'Staff salary',
          child: TextField(
            controller: _salary,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '${Formatting.tenantCurrency} ',
              helperText: 'Percentage commissions are worked out from this.',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        _CommissionFields(
          label: 'All-goals-met bonus',
          type: _groupType,
          value: _groupValue,
          enabled: !_submitting,
          onType: (v) => setState(() => _groupType = v),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Dock half the salary on failure',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            'Applied at verification when any goal is missed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          value: _deductOnFailure,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _deductOnFailure = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : _editing
              ? 'Save changes'
              : 'Assign target',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        if (_editing) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            'Saving replaces the criteria, so anything already reported '
            'against them is cleared.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// The commission-type / commission-value pair, which appears three times in
/// the target form and behaves identically each time.
class _CommissionFields extends StatelessWidget {
  const _CommissionFields({
    required this.label,
    required this.type,
    required this.value,
    required this.enabled,
    required this.onType,
  });

  final String label;
  final String type;
  final TextEditingController value;
  final bool enabled;
  final ValueChanged<String> onType;

  @override
  Widget build(BuildContext context) {
    final percentage = type == 'percentage';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrmField(
          label: label,
          child: DropdownButtonFormField<String>(
            initialValue: type,
            isExpanded: true,
            items: [
              for (final (v, l) in _commissionTypes)
                DropdownMenuItem(value: v, child: Text(l)),
            ],
            onChanged: enabled ? (v) => onType(v ?? 'none') : null,
          ),
        ),
        if (type != 'none') ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: value,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: percentage ? '0' : '0.00',
              prefixText: percentage ? null : '${Formatting.tenantCurrency} ',
              suffixText: percentage ? '%' : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _CriterionEditor extends StatelessWidget {
  const _CriterionEditor({
    required this.index,
    required this.draft,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _CriterionDraft draft;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'CRITERION ${index + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onRemove : null,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: draft.label,
              enabled: enabled,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What is measured',
                hintText: 'e.g. New customers signed',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final (v, l) in _criterionTypes)
                        DropdownMenuItem(value: v, child: Text(l)),
                    ],
                    onChanged: enabled
                        ? (v) {
                            draft.type = v ?? 'custom';
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: TextField(
                    controller: draft.goal,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Goal'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: draft.unit,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'Optional — customers, units',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            _CommissionFields(
              label: 'Pays',
              type: draft.commissionType,
              value: draft.commissionValue,
              enabled: enabled,
              onType: (v) {
                draft.commissionType = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Commission — GET /staff-targets/summary
// ---------------------------------------------------------------------------

class _CommissionTab extends ConsumerWidget {
  const _CommissionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(targetCommissionsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: summary,
      errorTitle: 'Could not load commission',
      onRetry: () => ref.invalidate(targetCommissionsProvider),
      builder: (rows) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(targetCommissionsProvider);
          await ref.read(targetCommissionsProvider.future);
        },
        child: rows.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const StateMessage(
                      icon: Icons.payments_outlined,
                      title: 'Nothing verified yet',
                      message:
                          'Commission appears here once a target is verified.',
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
                      label: 'Verified commission',
                      amount: rows.fold<double>(
                        0,
                        (sum, r) => sum + r.totalCommission,
                      ),
                      emphasis: status.settled,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('By staff member'),
                  const SizedBox(height: Spacing.sm),
                  for (final row in rows) ...[
                    Card(
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          row.userName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          [
                            '${Formatting.integer(row.targetsCount)} target'
                                '${row.targetsCount == 1 ? '' : 's'}',
                            if (row.managerCommission > 0) 'incl. override',
                          ].join(' · ').toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Money(
                          row.totalCommission,
                          scale: MoneyScale.dense,
                          color: status.settled,
                        ),
                        children: [
                          for (final line in row.targets)
                            _CommissionLineTile(line: line),
                          for (final line in row.managedTargets)
                            _CommissionLineTile(line: line, managed: true),
                          if (row.salaryDeductions > 0)
                            ListTile(
                              dense: true,
                              title: Text(
                                'Salary deductions',
                                style: theme.textTheme.titleSmall,
                              ),
                              trailing: Money(
                                row.salaryDeductions,
                                scale: MoneyScale.dense,
                                color: status.overdue,
                              ),
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

class _CommissionLineTile extends StatelessWidget {
  const _CommissionLineTile({required this.line, this.managed = false});

  final TargetCommissionLine line;
  final bool managed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        line.title,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (managed) 'override',
          if (line.staffName != null) line.staffName!,
          line.period,
        ].join(' · ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Money(line.commissionEarned, scale: MoneyScale.dense),
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
                SectionHeader('Today · ${Formatting.date(DateTime.now())}'),
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

/// The money logged against each system property, and the form that logs it.
///
/// Entering a record is what this module exists for, so the masthead carries
/// the action; every row opens its own sheet for the receipt, the edit and
/// the delete rather than crowding four icons onto a phone-width row.
class SystemRecordsScreen extends ConsumerStatefulWidget {
  const SystemRecordsScreen({super.key});

  @override
  ConsumerState<SystemRecordsScreen> createState() =>
      _SystemRecordsScreenState();
}

class _SystemRecordsScreenState extends ConsumerState<SystemRecordsScreen> {
  final _listKey = GlobalKey<PagedListViewState<SystemRecord>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate =
        session?.can(StaffSelfPermissions.systemRecordsCreate) ?? false;
    final canUpdate =
        session?.can(StaffSelfPermissions.systemRecordsUpdate) ?? false;
    final canDelete =
        session?.can(StaffSelfPermissions.systemRecordsDelete) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'System records',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add a record',
                onPressed: () => _openForm(),
              )
            : null,
      ),
      body: PagedListView<SystemRecord>(
        key: _listKey,
        fetch: (page) =>
            ref.read(staffSelfServiceProvider).systemRecords(page: page),
        itemBuilder: (context, record) => Card(
          child: ListTile(
            onTap: () => _openDetail(record, canUpdate, canDelete),
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
        emptyMessage: canCreate
            ? 'Add the first one from the button above.'
            : 'Records appear here as they are entered.',
      ),
    );
  }

  Future<void> _openForm({SystemRecord? record}) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _SystemRecordSheet(record: record),
    );
    if (saved == true) await _listKey.currentState?.reload();
  }

  Future<void> _openDetail(
    SystemRecord record,
    bool canUpdate,
    bool canDelete,
  ) async {
    final action = await showCrmSheet<String>(
      context: context,
      builder: (_) => _SystemRecordDetailSheet(
        record: record,
        canUpdate: canUpdate,
        canDelete: canDelete,
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _openForm(record: record);
    } else if (action == 'delete') {
      await _delete(record);
    }
  }

  Future<void> _delete(SystemRecord record) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          '${Formatting.currency(record.amount)} on '
          '${Formatting.date(record.recordDate)}'
          '${record.systemName == null ? '' : ' for ${record.systemName}'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(staffSelfServiceProvider).deleteSystemRecord(record.id);
      await _listKey.currentState?.reload();
      messenger.showSnackBar(
        const SnackBar(content: Text('System record deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The row's actions, one tap from the row itself.
class _SystemRecordDetailSheet extends StatelessWidget {
  const _SystemRecordDetailSheet({
    required this.record,
    required this.canUpdate,
    required this.canDelete,
  });

  final SystemRecord record;
  final bool canUpdate;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmSheet(
      eyebrow: Formatting.date(record.recordDate),
      title: record.systemName ?? 'System record',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Money(record.amount, scale: MoneyScale.headline),
        ),
        const SizedBox(height: Spacing.md),
        if (record.propertyName != null)
          CrmDetailRow('Property', record.propertyName!),
        if (record.bankName != null) CrmDetailRow('Bank', record.bankName!),
        if (record.createdByName != null)
          CrmDetailRow('Entered by', record.createdByName!),
        CrmDetailRow(
          'Receipt',
          record.receiptUrl == null ? 'None on file' : 'On file',
        ),
        if (record.notes != null) CrmDetailRow('Notes', record.notes!),
        const SizedBox(height: Spacing.lg),
        if (canUpdate)
          PrimaryButton(
            label: 'Edit this record',
            icon: Icons.edit_outlined,
            onPressed: () => Navigator.of(context).pop('edit'),
          ),
        if (canDelete) ...[
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
            label: Text('Delete', style: TextStyle(color: scheme.error)),
            onPressed: () => Navigator.of(context).pop('delete'),
          ),
        ],
        if (!canUpdate && !canDelete)
          Text(
            'You can view records but not change them.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

/// Create or correct a record. The receipt is required on create and optional
/// on edit — the API's own rule, since an existing record already has one.
class _SystemRecordSheet extends ConsumerStatefulWidget {
  const _SystemRecordSheet({this.record});

  final SystemRecord? record;

  @override
  ConsumerState<_SystemRecordSheet> createState() => _SystemRecordSheetState();
}

class _SystemRecordSheetState extends ConsumerState<_SystemRecordSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  String? _systemId;
  String? _propertyId;
  String? _bankId;
  DateTime _date = DateTime.now();
  PlatformFile? _receipt;
  bool _submitting = false;
  String? _error;

  /// The API's `max:10240` on the receipt, in bytes.
  static const _maxReceiptBytes = 10 * 1024 * 1024;

  bool get _editing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r == null) return;
    _systemId = r.systemId;
    _propertyId = r.systemPropertyId;
    _bankId = r.bankAccountId;
    _amount.text = Formatting.amount(r.amount);
    _notes.text = r.notes ?? '';
    _date = r.recordDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // Exactly the API's `mimes:pdf,jpg,jpeg,png`.
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final file = (result?.files ?? const <PlatformFile>[]).firstOrNull;
    if (file == null || file.path == null) return;
    if (file.size > _maxReceiptBytes) {
      setState(() => _error = 'That receipt is over the 10 MB limit.');
      return;
    }
    setState(() {
      _receipt = file;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      // `before_or_equal:today` — a record cannot be forward-dated.
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_systemId == null || _propertyId == null) {
      setState(() => _error = 'Choose a system and a property.');
      return;
    }
    if (amount == null || amount < 0) {
      setState(() => _error = 'Enter the amount.');
      return;
    }
    if (!_editing && _receipt?.path == null) {
      setState(() => _error = 'A receipt is required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(staffSelfServiceProvider);
      final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      if (_editing) {
        await service.updateSystemRecord(
          widget.record!.id,
          systemId: _systemId!,
          systemPropertyId: _propertyId!,
          recordDate: _date,
          amount: amount,
          bankAccountId: _bankId,
          notes: notes,
          receiptPath: _receipt?.path,
        );
      } else {
        await service.createSystemRecord(
          systemId: _systemId!,
          systemPropertyId: _propertyId!,
          recordDate: _date,
          amount: amount,
          bankAccountId: _bankId,
          notes: notes,
          receiptPath: _receipt!.path!,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editing ? 'Record updated.' : 'Record added.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('receipt') ??
            e.errorFor('record_date') ??
            e.errorFor('amount') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmSheet(
      eyebrow: 'System records',
      title: _editing ? 'Edit record' : 'Add a record',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        _OptionField(
          label: 'System',
          hint: 'Choose a system',
          provider: systemsProvider,
          value: _systemId,
          enabled: !_submitting,
          onChanged: (v) => setState(() => _systemId = v),
        ),
        const SizedBox(height: Spacing.md),
        _OptionField(
          label: 'Property',
          hint: 'Choose a property',
          provider: systemPropertiesProvider,
          value: _propertyId,
          enabled: !_submitting,
          onChanged: (v) => setState(() => _propertyId = v),
        ),
        const SizedBox(height: Spacing.md),
        _BankField(
          value: _bankId,
          enabled: !_submitting,
          onChanged: (v) => setState(() => _bankId = v),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Date',
          value: Formatting.date(_date),
          onTap: _submitting ? null : _pickDate,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Amount',
          child: TextField(
            controller: _amount,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: _editing ? 'Replace receipt (optional)' : 'Receipt',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(
              _receipt?.name ??
                  (_editing ? 'Keep the receipt on file' : 'Attach a receipt'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _submitting ? null : _pickReceipt,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'PDF or photo, up to 10 MB.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional — what this covers',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : _editing
              ? 'Save changes'
              : 'Add record',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// A dropdown over one of the reference lists, which each sit behind their own
/// read permission — so a 403 on one names itself instead of leaving an empty
/// menu the user cannot explain.
class _OptionField extends ConsumerWidget {
  const _OptionField({
    required this.label,
    required this.hint,
    required this.provider,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final AutoDisposeFutureProvider<List<SystemOption>> provider;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(provider);

    return options.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorBanner(
        message: e is ApiException
            ? 'Could not load ${label.toLowerCase()}s: ${e.message}'
            : 'Could not load ${label.toLowerCase()}s.',
        onRetry: () => ref.invalidate(provider),
      ),
      data: (rows) {
        final active = rows.where((r) => r.isActive || r.id == value).toList();
        return CrmField(
          label: label,
          child: DropdownButtonFormField<String>(
            initialValue: active.any((r) => r.id == value) ? value : null,
            isExpanded: true,
            hint: Text(hint),
            items: [
              for (final row in active)
                DropdownMenuItem(
                  value: row.id,
                  child: Text(row.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        );
      },
    );
  }
}

/// The bank account is optional — null means cash or an unstated channel — so
/// a failure to load it must not block the form.
class _BankField extends ConsumerWidget {
  const _BankField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(recordBankAccountsProvider);

    return accounts.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => const SizedBox.shrink(),
      data: (rows) => CrmField(
        label: 'Bank account (optional)',
        child: DropdownButtonFormField<String>(
          initialValue: rows.any((r) => r.id == value) ? value : null,
          isExpanded: true,
          hint: const Text('Cash or unspecified'),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Cash or unspecified'),
            ),
            for (final row in rows)
              DropdownMenuItem(
                value: row.id,
                child: Text(
                  [
                    row.bankName,
                    row.accountNumber,
                  ].whereType<String>().join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

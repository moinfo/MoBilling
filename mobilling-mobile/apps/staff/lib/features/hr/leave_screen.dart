import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, FilterStrip;
import 'hr_providers.dart';

/// Leave: balances, my requests, team approvals, and (for HR) the types and
/// per-employee allocations.
///
/// Mirrors the web's four tabs. The server decides whose requests you see
/// (`leave.view_all` → everyone, `leave.review` → your direct reports),
/// so the Team tab simply lists what comes back.
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canReview =
        (auth?.can(HrPermissions.leaveReview) ?? false) ||
        (auth?.can(HrPermissions.leaveViewAll) ?? false);
    final canManage = auth?.can(HrPermissions.leaveManage) ?? false;

    final tabs = <(String, Widget)>[
      ('Overview', _OverviewTab(canReview: canReview)),
      ('My requests', const _MyRequestsTab()),
      if (canReview) ('Team', const _TeamTab()),
      if (canManage) ('Settings', const _SettingsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'HR',
          title: 'Leave',
          // Requesting leave is the one thing every reader of this screen
          // can do, so it lives on the masthead rather than on one tab.
          trailing: InkActionButton(
            icon: Icons.add_rounded,
            tooltip: 'Request leave',
            onPressed: () => _requestLeave(context, ref),
          ),
          bottom: InkTabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) label],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

Future<void> _requestLeave(BuildContext context, WidgetRef ref) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => const _RequestLeaveSheet(),
  );
  if (submitted ?? false) {
    ref.invalidate(leaveRequestsProvider);
    ref.invalidate(myLeaveBalanceProvider);
  }
}

// ---------------------------------------------------------------------------
// Overview — my balances
// ---------------------------------------------------------------------------

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.canReview});

  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(myLeaveBalanceProvider);
    final pending = canReview
        ? ref.watch(leaveRequestsProvider('pending'))
        : null;
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: balances,
      errorTitle: 'Could not load leave balances',
      onRetry: () => ref.invalidate(myLeaveBalanceProvider),
      builder: (rows) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaveRequestsProvider);
          ref.invalidate(myLeaveBalanceProvider);
          await ref.read(myLeaveBalanceProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (pending?.valueOrNull?.isNotEmpty ?? false) ...[
              Reveal(
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.pending_actions_outlined,
                      color: status.attention,
                    ),
                    title: Text(
                      '${Formatting.integer(pending!.value!.length)} leave request'
                      '${pending.value!.length == 1 ? '' : 's'} awaiting your review',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'TEAM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    // The Team tab is always the third when it exists.
                    onTap: () => DefaultTabController.of(context).animateTo(2),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            // The year in four figures before the per-type breakdown: what
            // matters at a glance is how many days are left, not which type
            // they belong to. One strip beats four cards restating it.
            if (rows.isNotEmpty) ...[
              Reveal(
                delay: const Duration(milliseconds: 60),
                child: StatRail(
                  items: [
                    StatRailItem(
                      label: 'Days left',
                      value: Formatting.integer(
                        rows.fold<int>(0, (sum, r) => sum + r.remainingDays),
                      ),
                      // Red only when there is genuinely nothing left to
                      // take — a figure that is always coloured says nothing.
                      emphasis: rows.every((r) => r.remainingDays <= 0)
                          ? status.overdue
                          : null,
                    ),
                    StatRailItem(
                      label: 'Used',
                      value: Formatting.integer(
                        rows.fold<int>(0, (sum, r) => sum + r.usedDays),
                      ),
                    ),
                    StatRailItem(
                      label: 'Allocated',
                      value: Formatting.integer(
                        rows.fold<int>(0, (sum, r) => sum + r.allocatedDays),
                      ),
                    ),
                    StatRailItem(
                      label: 'Types',
                      value: Formatting.integer(rows.length),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            const SectionHeader('Balance this year'),
            const SizedBox(height: Spacing.sm),
            if (rows.isEmpty)
              const Card(
                child: StateMessage(
                  icon: Icons.beach_access_outlined,
                  title: 'No leave types configured yet',
                  message: 'Balances appear here once HR sets up leave types.',
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Spacing.sm,
                crossAxisSpacing: Spacing.sm,
                childAspectRatio: 1.45,
                children: [for (final row in rows) _BalanceTile(row: row)],
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// One leave type's balance: the eyebrow names the type, the figure is the
/// days left, and the bar is how much of the year's allocation is gone.
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.row});

  final MyLeaveBalance row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final exhausted = row.remainingDays <= 0;
    final fraction = row.allocatedDays <= 0
        ? 0.0
        : (row.usedDays / row.allocatedDays).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.leaveType.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Formatting.integer(row.remainingDays),
                  style: TextStyle(
                    fontFamily: Type.family,
                    fontSize: MoneyScale.headline.size,
                    fontWeight: FontWeight.w700,
                    letterSpacing: MoneyScale.headline.size * -0.02,
                    height: 1,
                    color: exhausted ? status.overdue : scheme.onSurface,
                    fontFeatures: Type.figures,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  '/ ${Formatting.integer(row.allocatedDays)} DAYS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  exhausted ? status.overdue : scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${Formatting.integer(row.usedDays)} USED',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My requests
// ---------------------------------------------------------------------------

class _MyRequestsTab extends ConsumerWidget {
  const _MyRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(leaveRequestsProvider(null));
    final me = ref.watch(currentUserProvider)?.id;

    return CrmAsyncView(
      value: requests,
      errorTitle: 'Could not load your requests',
      onRetry: () => ref.invalidate(leaveRequestsProvider(null)),
      builder: (all) {
        // Reviewers get their team's requests in the same response.
        final mine = all.where((r) => r.userId == me).toList();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(leaveRequestsProvider(null).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (mine.isEmpty)
                SizedBox(
                  height: 320,
                  child: StateMessage(
                    icon: Icons.beach_access_outlined,
                    title: 'No leave requests yet',
                    message: 'Your requests and their status appear here.',
                    actionLabel: 'Request leave',
                    onAction: () => _requestLeave(context, ref),
                  ),
                )
              else
                _RequestList(
                  requests: mine,
                  showUser: false,
                  onTap: (r) =>
                      _showRequest(context, ref, r, canCancel: r.isPending),
                ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        );
      },
    );
  }
}

class _RequestLeaveSheet extends ConsumerStatefulWidget {
  const _RequestLeaveSheet();

  @override
  ConsumerState<_RequestLeaveSheet> createState() => _RequestLeaveSheetState();
}

class _RequestLeaveSheetState extends ConsumerState<_RequestLeaveSheet> {
  final _reason = TextEditingController();
  String? _typeId;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _days =>
      _start == null || _end == null ? 0 : _end!.difference(_start!).inDays + 1;

  Future<void> _pickDate({required bool start}) async {
    final initial = start
        ? (_start ?? DateTime.now())
        : (_end ?? _start ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_typeId == null || _start == null || _end == null) {
      setState(() => _error = 'Choose a leave type and both dates.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(hrServiceProvider)
          .requestLeave(
            leaveTypeId: _typeId!,
            startDate: _start!,
            endDate: _end!,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final types = ref.watch(leaveTypesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'LEAVE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Request leave',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            Text('Leave type', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            types.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorBanner(
                message: e is ApiException
                    ? e.message
                    : 'Could not load leave types',
              ),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _typeId,
                decoration: const InputDecoration(hintText: 'Choose a type'),
                items: [
                  for (final t in list)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text('${t.name} (${t.daysPerYear} days/yr)'),
                    ),
                ],
                onChanged: (v) => setState(() => _typeId = v),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text('Dates', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _start == null ? 'First day' : Formatting.date(_start),
                    ),
                    onPressed: () => _pickDate(start: true),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 16),
                    label: Text(
                      _end == null ? 'Last day' : Formatting.date(_end),
                    ),
                    onPressed: () => _pickDate(start: false),
                  ),
                ),
              ],
            ),
            if (_days > 0) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                '${Formatting.integer(_days)} DAY${_days == 1 ? '' : 'S'} · INCLUSIVE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Text('Reason', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _reason,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Optional — what your reviewer should know',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Submitting…' : 'Submit request',
              busy: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team approvals
// ---------------------------------------------------------------------------

class _TeamTab extends ConsumerStatefulWidget {
  const _TeamTab();

  @override
  ConsumerState<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<_TeamTab> {
  String? _status = 'pending';

  static const _filters = <(String?, String)>[
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    (null, 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(leaveRequestsProvider(_status));
    final me = ref.read(currentUserProvider)?.id;

    return Column(
      children: [
        FilterStrip(
          options: _filters,
          selected: _status,
          onSelect: (v) => setState(() => _status = v),
        ),
        Expanded(
          child: CrmAsyncView(
            value: requests,
            errorTitle: 'Could not load team requests',
            onRetry: () => ref.invalidate(leaveRequestsProvider(_status)),
            builder: (all) {
              // Your own requests are reviewed by your supervisor, not you.
              final team = all.where((r) => r.userId != me).toList();
              return RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(leaveRequestsProvider(_status).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.md,
                  ),
                  children: [
                    if (team.isEmpty)
                      const SizedBox(
                        height: 320,
                        child: StateMessage(
                          icon: Icons.task_alt_outlined,
                          title: 'Nothing to review',
                          message: 'Requests from your team appear here.',
                        ),
                      )
                    else
                      _RequestList(
                        requests: team,
                        showUser: true,
                        onTap: (r) => _showRequest(
                          context,
                          ref,
                          r,
                          canReview: r.isPending,
                        ),
                      ),
                    const SizedBox(height: Spacing.xl),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared request list + detail sheet
// ---------------------------------------------------------------------------

/// Requests as one card of rows: the name (or type) as the title, the status
/// chip beside the dates, and the day count as the aligned trailing figure.
class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.showUser,
    required this.onTap,
  });

  final List<LeaveRequest> requests;
  final bool showUser;
  final ValueChanged<LeaveRequest> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: Column(
        children: [
          for (final (i, request) in requests.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              onTap: () => onTap(request),
              title: Text(
                showUser ? request.userName : request.typeName,
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    StatusChip(request.status, dense: true),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        [
                          if (showUser) request.typeName,
                          '${Formatting.date(request.startDate)} – ${Formatting.date(request.endDate)}',
                        ].join(' · ').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Text(
                '${Formatting.integer(request.days)} ${request.days == 1 ? 'DAY' : 'DAYS'}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label/value line for detail sheets: the label in the mono eyebrow face,
/// the value in body text (or a widget, for money).
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, {this.value, this.child})
    : assert(value != null || child != null);

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: child ?? Text(value!, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRequest(
  BuildContext context,
  WidgetRef ref,
  LeaveRequest request, {
  bool canCancel = false,
  bool canReview = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(hrServiceProvider);

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'LEAVE REQUEST',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      request.userName,
                      style: Type.display(22, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  StatusChip(request.status),
                ],
              ),
              const SizedBox(height: Spacing.md),
              _DetailRow('Type', value: request.typeName),
              _DetailRow(
                'Dates',
                value:
                    '${Formatting.date(request.startDate)} – '
                    '${Formatting.date(request.endDate)}',
              ),
              _DetailRow('Days', value: Formatting.integer(request.days)),
              if (request.reason != null)
                _DetailRow('Reason', value: request.reason!),
              if (request.reviewer != null)
                _DetailRow(
                  'Reviewed by',
                  value:
                      '${request.reviewer!.name}'
                      '${request.reviewedAt == null ? '' : ' · ${Formatting.date(request.reviewedAt)}'}',
                ),
              if (request.reviewNote != null)
                _DetailRow('Note', value: request.reviewNote!),
              _DetailRow(
                'Requested',
                value: Formatting.dateTime(request.createdAt),
              ),
              if (canReview) ...[
                const SizedBox(height: Spacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        onPressed: () => Navigator.pop(context, 'reject'),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        icon: Icons.check,
                        label: 'Approve',
                        onPressed: () => Navigator.pop(context, 'approve'),
                      ),
                    ),
                  ],
                ),
              ],
              if (canCancel) ...[
                const SizedBox(height: Spacing.lg),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel request'),
                  onPressed: () => Navigator.pop(context, 'cancel'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  try {
    switch (action) {
      case 'cancel':
        await service.cancelLeaveRequest(request.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Request cancelled.')),
        );
      case 'approve' || 'reject':
        final note = await _askNote(
          context,
          title: action == 'approve' ? 'Approve leave' : 'Reject leave',
          verb: action == 'approve' ? 'Approve' : 'Reject',
        );
        if (note == null) return; // dismissed
        await service.reviewLeaveRequest(
          request.id,
          approve: action == 'approve',
          note: note.isEmpty ? null : note,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              action == 'approve'
                  ? 'Approved — the days are marked excused in attendance.'
                  : 'Request rejected.',
            ),
          ),
        );
    }
    ref.invalidate(leaveRequestsProvider);
    ref.invalidate(myLeaveBalanceProvider);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Returns the note ('' when left blank), or null when dismissed.
Future<String?> _askNote(
  BuildContext context, {
  required String title,
  required String verb,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Note for the employee (optional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(verb),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Settings — leave types and allocations (leave.manage)
// ---------------------------------------------------------------------------

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(leaveTypesProvider);
    final balances = ref.watch(leaveBalancesProvider(_year));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaveTypesProvider);
        ref.invalidate(leaveBalancesProvider);
        await ref.read(leaveTypesProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          SectionHeader(
            'Leave types',
            trailing: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add type'),
              onPressed: () => _editType(context, null),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          types.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorBanner(
              message: e is ApiException ? e.message : 'Could not load types',
              onRetry: () => ref.invalidate(leaveTypesProvider),
            ),
            data: (list) => list.isEmpty
                ? Card(
                    child: StateMessage(
                      icon: Icons.beach_access_outlined,
                      title: 'No leave types yet',
                      message: 'Add one to get started.',
                      actionLabel: 'Add a leave type',
                      onAction: () => _editType(context, null),
                    ),
                  )
                : Card(
                    child: Column(
                      children: [
                        for (final (i, t) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            // The type's own colour, as set on the web — the
                            // one dot here that is data rather than decoration.
                            leading: CircleAvatar(
                              radius: 6,
                              backgroundColor:
                                  _parseColor(t.color) ?? scheme.primary,
                            ),
                            title: Text(
                              t.name,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              '${Formatting.integer(t.daysPerYear)} days/yr · ${t.isPaid ? 'paid' : 'unpaid'}'
                                      '${t.isActive ? '' : ' · inactive'}'
                                  .toUpperCase(),
                              style: muted,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _editType(context, t),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Allocations'),
          const SizedBox(height: Spacing.sm),
          Text(
            'Each employee gets the type\'s default days unless an '
            'allocation is set here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          // Chips in the app's filter recipe — signal blue for the choice, a
          // hairline otherwise — so picking a year reads as the same gesture
          // as picking a status on the Team tab.
          Wrap(
            spacing: Spacing.sm,
            children: [
              for (
                var y = DateTime.now().year - 1;
                y <= DateTime.now().year + 1;
                y++
              )
                _YearChip(
                  year: y,
                  selected: _year == y,
                  onSelected: () => setState(() => _year = y),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          balances.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorBanner(
              message: e is ApiException
                  ? e.message
                  : 'Could not load allocations',
              onRetry: () => ref.invalidate(leaveBalancesProvider(_year)),
            ),
            data: (page) {
              final typeList = types.valueOrNull ?? const <LeaveType>[];
              if (page.users.isEmpty) {
                return const Card(
                  child: StateMessage(
                    icon: Icons.people_outline,
                    title: 'No active employees',
                    message: 'Allocations appear here once staff are added.',
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final (i, user) in page.users.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ExpansionTile(
                        title: Text(
                          user.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        children: [
                          for (final t in typeList)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(
                                left: Spacing.lg,
                                right: Spacing.md,
                              ),
                              title: Text(t.name),
                              trailing: Text(
                                page.allocationFor(user.id, t.id) == null
                                    ? '${Formatting.integer(t.daysPerYear)} · DEFAULT'
                                    : '${Formatting.integer(page.allocationFor(user.id, t.id)!.allocatedDays)} DAYS',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      page.allocationFor(user.id, t.id) == null
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                                ),
                              ),
                              onTap: () => _setAllocation(
                                context,
                                user: user,
                                type: t,
                                current:
                                    page
                                        .allocationFor(user.id, t.id)
                                        ?.allocatedDays ??
                                    t.daysPerYear,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  Future<void> _editType(BuildContext context, LeaveType? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _LeaveTypeSheet(existing: existing),
    );
    if (saved ?? false) {
      ref.invalidate(leaveTypesProvider);
      ref.invalidate(myLeaveBalanceProvider);
    }
  }

  Future<void> _setAllocation(
    BuildContext context, {
    required NamedUser user,
    required LeaveType type,
    required int current,
  }) async {
    final controller = TextEditingController(text: '$current');
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${user.name} · ${type.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'Days for $_year'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save allocation'),
          ),
        ],
      ),
    );
    if (days == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(hrServiceProvider)
          .setLeaveBalance(
            userId: user.id,
            leaveTypeId: type.id,
            year: _year,
            allocatedDays: days,
          );
      ref.invalidate(leaveBalancesProvider(_year));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _LeaveTypeSheet extends ConsumerStatefulWidget {
  const _LeaveTypeSheet({this.existing});

  final LeaveType? existing;

  @override
  ConsumerState<_LeaveTypeSheet> createState() => _LeaveTypeSheetState();
}

class _LeaveTypeSheetState extends ConsumerState<_LeaveTypeSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _days = TextEditingController(
    text: '${widget.existing?.daysPerYear ?? 0}',
  );
  late bool _paid = widget.existing?.isPaid ?? true;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final days = int.tryParse(_days.text.trim());
    if (name.isEmpty || days == null || days < 0) {
      setState(() => _error = 'Enter a name and a whole number of days.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = ref.read(hrServiceProvider);
    try {
      if (widget.existing == null) {
        await service.createLeaveType(
          name: name,
          daysPerYear: days,
          isPaid: _paid,
        );
      } else {
        await service.updateLeaveType(
          widget.existing!.id,
          name: name,
          daysPerYear: days,
          isPaid: _paid,
          isActive: _active,
          color: widget.existing!.color,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete leave type?'),
        content: Text(
          'Requests already made against "${widget.existing!.name}" keep their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(hrServiceProvider).deleteLeaveType(widget.existing!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'LEAVE TYPE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              editing ? 'Edit leave type' : 'New leave type',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            Text('Name', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Annual leave'),
            ),
            const SizedBox(height: Spacing.md),
            Text('Days per year', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '0'),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Paid leave'),
              value: _paid,
              onChanged: (v) => setState(() => _paid = v),
            ),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Inactive types cannot be requested'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: Spacing.md),
            PrimaryButton(
              label: _saving
                  ? 'Saving…'
                  : editing
                  ? 'Save changes'
                  : 'Create leave type',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (editing) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _saving ? null : _delete,
                child: Text(
                  'Delete leave type',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One year in the allocations picker, cut to the same recipe as the app's
/// [FilterStrip] chips — there are only ever three, so they sit in a wrap
/// rather than in a scrolling strip.
class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.year,
    required this.selected,
    required this.onSelected,
  });

  final int year;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ChoiceChip(
      label: Text('$year'),
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: scheme.primary.withValues(alpha: 0.10),
      backgroundColor: theme.cardTheme.color,
      side: BorderSide(
        color: selected
            ? scheme.primary.withValues(alpha: 0.45)
            : scheme.outlineVariant,
      ),
      onSelected: (_) => onSelected(),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

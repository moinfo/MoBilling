import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow, FilterStrip;
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
    final canReview = (auth?.can(HrPermissions.leaveReview) ?? false) ||
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
        appBar: AppBar(
          title: const Text('Leave'),
          bottom: TabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
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
    final pending =
        canReview ? ref.watch(leaveRequestsProvider('pending')) : null;
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
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: status.attention.withValues(alpha: 0.12),
                  borderRadius: Radii.card,
                ),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions_outlined,
                        size: 18, color: status.attention),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        '${pending!.value!.length} leave request'
                        '${pending.value!.length == 1 ? '' : 's'} awaiting your review',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
            Text('Balance this year', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (rows.isEmpty)
              Text('No leave types configured yet.',
                  style: theme.textTheme.bodySmall)
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Spacing.sm,
                crossAxisSpacing: Spacing.sm,
                childAspectRatio: 1.6,
                children: [
                  for (final row in rows)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.leaveType.name,
                                style: theme.textTheme.labelMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const Spacer(),
                            RichText(
                              text: TextSpan(
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: row.remainingDays == 0
                                      ? status.overdue
                                      : theme.colorScheme.onSurface,
                                ),
                                children: [
                                  TextSpan(text: '${row.remainingDays}'),
                                  TextSpan(
                                    text: ' / ${row.allocatedDays} days',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text('${row.usedDays} used',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.xl),
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Request leave'),
        onPressed: () => _requestLeave(context, ref),
      ),
      body: CrmAsyncView(
        value: requests,
        errorTitle: 'Could not load your requests',
        onRetry: () => ref.invalidate(leaveRequestsProvider(null)),
        builder: (all) {
          // Reviewers get their team's requests in the same response.
          final mine = all.where((r) => r.userId == me).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(leaveRequestsProvider(null).future),
            child: mine.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 320,
                        child: StateMessage(
                          icon: Icons.beach_access_outlined,
                          title: 'No leave requests yet',
                          message: 'Your requests and their status appear here.',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, Spacing.md, Spacing.md, 96),
                    itemCount: mine.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) => _LeaveRequestCard(
                      request: mine[index],
                      showUser: false,
                      onTap: () => _showRequest(context, ref, mine[index],
                          canCancel: mine[index].isPending),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _requestLeave(BuildContext context, WidgetRef ref) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _RequestLeaveSheet(),
    );
    if (submitted ?? false) {
      ref.invalidate(leaveRequestsProvider);
      ref.invalidate(myLeaveBalanceProvider);
    }
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

  int get _days => _start == null || _end == null
      ? 0
      : _end!.difference(_start!).inDays + 1;

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? (_start ?? DateTime.now()) : (_end ?? _start ?? DateTime.now());
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
      await ref.read(hrServiceProvider).requestLeave(
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
    final types = ref.watch(leaveTypesProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Request leave', style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          types.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(
                e is ApiException ? e.message : 'Could not load leave types',
                style: TextStyle(color: theme.colorScheme.error)),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _typeId,
              decoration: const InputDecoration(labelText: 'Leave type'),
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
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(_start == null
                      ? 'Start date'
                      : Formatting.date(_start)),
                  onPressed: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(
                      _end == null ? 'End date' : Formatting.date(_end)),
                  onPressed: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          if (_days > 0)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text('$_days day${_days == 1 ? '' : 's'} (inclusive)',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit request'),
          ),
        ],
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
                child: team.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 320,
                            child: StateMessage(
                              icon: Icons.task_alt_outlined,
                              title: 'Nothing to review',
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        itemCount: team.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Spacing.sm),
                        itemBuilder: (context, index) => _LeaveRequestCard(
                          request: team[index],
                          showUser: true,
                          onTap: () => _showRequest(
                            context,
                            ref,
                            team[index],
                            canReview: team[index].isPending,
                          ),
                        ),
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
// Shared request card + detail sheet
// ---------------------------------------------------------------------------

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({
    required this.request,
    required this.showUser,
    required this.onTap,
  });

  final LeaveRequest request;
  final bool showUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(showUser ? request.userName : request.typeName),
        subtitle: Text(
          [
            if (showUser) request.typeName,
            '${Formatting.date(request.startDate)} – ${Formatting.date(request.endDate)}',
            '${request.days} day${request.days == 1 ? '' : 's'}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: StatusChip(request.status, dense: true),
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
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(request.userName,
                        style: theme.textTheme.titleMedium),
                  ),
                  StatusChip(request.status, dense: true),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              CrmDetailRow('Type', request.typeName),
              CrmDetailRow(
                  'Dates',
                  '${Formatting.date(request.startDate)} – '
                      '${Formatting.date(request.endDate)}'),
              CrmDetailRow('Days', '${request.days}'),
              if (request.reason != null)
                CrmDetailRow('Reason', request.reason!),
              if (request.reviewer != null)
                CrmDetailRow(
                    'Reviewed by',
                    '${request.reviewer!.name}'
                    '${request.reviewedAt == null ? '' : ' · ${Formatting.date(request.reviewedAt)}'}'),
              if (request.reviewNote != null)
                CrmDetailRow('Note', request.reviewNote!),
              CrmDetailRow('Requested', Formatting.dateTime(request.createdAt)),
              if (canReview) ...[
                const SizedBox(height: Spacing.md),
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
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        onPressed: () => Navigator.pop(context, 'approve'),
                      ),
                    ),
                  ],
                ),
              ],
              if (canCancel) ...[
                const SizedBox(height: Spacing.md),
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
            const SnackBar(content: Text('Request cancelled.')));
      case 'approve' || 'reject':
        final note = await _askNote(context,
            title: action == 'approve' ? 'Approve leave' : 'Reject leave');
        if (note == null) return; // dismissed
        await service.reviewLeaveRequest(
          request.id,
          approve: action == 'approve',
          note: note.isEmpty ? null : note,
        );
        messenger.showSnackBar(SnackBar(
            content: Text(action == 'approve'
                ? 'Approved — the days are marked excused in attendance.'
                : 'Request rejected.')));
    }
    ref.invalidate(leaveRequestsProvider);
    ref.invalidate(myLeaveBalanceProvider);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Returns the note ('' when left blank), or null when dismissed.
Future<String?> _askNote(BuildContext context, {required String title}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Confirm'),
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
              label: const Text('Add'),
              onPressed: () => _editType(context, null),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          types.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(
                e is ApiException ? e.message : 'Could not load types',
                style: TextStyle(color: theme.colorScheme.error)),
            data: (list) => list.isEmpty
                ? Text('No leave types yet — add one to get started.',
                    style: theme.textTheme.bodySmall)
                : Card(
                    child: Column(
                      children: [
                        for (final (i, t) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 6,
                              backgroundColor: _parseColor(t.color) ??
                                  theme.colorScheme.primary,
                            ),
                            title: Text(t.name),
                            subtitle: Text(
                                '${t.daysPerYear} days/yr · ${t.isPaid ? 'paid' : 'unpaid'}'),
                            trailing: const Icon(Icons.edit_outlined, size: 18),
                            onTap: () => _editType(context, t),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: Spacing.lg),
          SectionHeader(
            'Allocations',
            trailing: DropdownButton<int>(
              value: _year,
              underline: const SizedBox.shrink(),
              items: [
                for (var y = DateTime.now().year - 1;
                    y <= DateTime.now().year + 1;
                    y++)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (y) => setState(() => _year = y!),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Each employee gets the type\'s default days unless an '
            'allocation is set here.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.sm),
          balances.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(
                e is ApiException ? e.message : 'Could not load allocations',
                style: TextStyle(color: theme.colorScheme.error)),
            data: (page) {
              final typeList = types.valueOrNull ?? const <LeaveType>[];
              if (page.users.isEmpty) {
                return Text('No active employees.',
                    style: theme.textTheme.bodySmall);
              }
              return Card(
                child: Column(
                  children: [
                    for (final user in page.users)
                      ExpansionTile(
                        title: Text(user.name),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        children: [
                          for (final t in typeList)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(
                                  left: Spacing.lg, right: Spacing.md),
                              title: Text(t.name),
                              trailing: Text(
                                page.allocationFor(user.id, t.id) == null
                                    ? '${t.daysPerYear} (default)'
                                    : '${page.allocationFor(user.id, t.id)!.allocatedDays} days',
                                style: theme.textTheme.bodySmall,
                              ),
                              onTap: () => _setAllocation(
                                context,
                                user: user,
                                type: t,
                                current: page
                                        .allocationFor(user.id, t.id)
                                        ?.allocatedDays ??
                                    t.daysPerYear,
                              ),
                            ),
                        ],
                      ),
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
          decoration: InputDecoration(labelText: 'Days for $_year'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (days == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrServiceProvider).setLeaveBalance(
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
  late final _days =
      TextEditingController(text: '${widget.existing?.daysPerYear ?? 0}');
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
            name: name, daysPerYear: days, isPaid: _paid);
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
            'Requests already made against "${widget.existing!.name}" keep their history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
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
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New leave type' : 'Edit leave type',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Days per year'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Paid leave'),
            value: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
          if (widget.existing != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive types cannot be requested'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
          if (widget.existing != null)
            TextButton(
              onPressed: _saving ? null : _delete,
              child: Text('Delete',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
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

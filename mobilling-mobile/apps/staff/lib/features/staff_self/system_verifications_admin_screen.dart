import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart' show ClientPickerSheet, StaffUserPickerSheet;
import '../crm/crm_ui.dart'
    show CrmDetailRow, CrmField, CrmPickerField, CrmSheet, showCrmSheet;
import 'staff_self_providers.dart';

/// The admin-wide roster behind `system_verifications.*`: register a system
/// that needs a daily check, assign it to a staff member, see every system's
/// today-status at a glance, and open its full check-in history.
///
/// This is the operator side of the loop; [MyVerificationsScreen] (in
/// `targets_and_systems_screens.dart`) is the other half — the staff member
/// actually submitting today's check against a system assigned to them.
class SystemVerificationsAdminScreen extends ConsumerStatefulWidget {
  const SystemVerificationsAdminScreen({super.key});

  @override
  ConsumerState<SystemVerificationsAdminScreen> createState() =>
      _SystemVerificationsAdminScreenState();
}

class _SystemVerificationsAdminScreenState
    extends ConsumerState<SystemVerificationsAdminScreen> {
  final _listKey = GlobalKey<PagedListViewState<SystemVerification>>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  void _reload() => _listKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate =
        session?.can(StaffSelfPermissions.systemVerificationsCreate) ?? false;
    final canUpdate =
        session?.can(StaffSelfPermissions.systemVerificationsUpdate) ?? false;
    final canDelete =
        session?.can(StaffSelfPermissions.systemVerificationsDelete) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'System verifications',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Register a system',
                onPressed: () => _openForm(),
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search by name or domain',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _onSearchChanged('');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        // One card, rows divided by hairlines — the paged list scrolls
        // inside it, same shape as every other admin roster in this app.
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: PagedListView<SystemVerification>(
            key: _listKey,
            padding: EdgeInsets.zero,
            separated: false,
            fetch: (page) => ref
                .read(staffSelfServiceProvider)
                .adminSystemVerifications(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            itemBuilder: (context, item) => _VerificationRow(
              verification: item,
              canUpdate: canUpdate,
              canDelete: canDelete,
              onEdit: () => _openForm(verification: item),
              onChanged: _reload,
            ),
            emptyIcon: Icons.verified_user_outlined,
            emptyTitle: 'No systems registered',
            emptyMessage: canCreate
                ? 'Register one to start daily checks.'
                : 'Systems registered for daily checks appear here.',
          ),
        ),
      ),
    );
  }

  Future<void> _openForm({SystemVerification? verification}) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) =>
          _SystemVerificationFormSheet(verification: verification),
    );
    if (saved == true) _reload();
  }
}

/// One row of the roster: name, domain/client/assignee, active state and
/// today's status — tapping it opens the row's actions.
class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.verification,
    required this.canUpdate,
    required this.canDelete,
    required this.onEdit,
    required this.onChanged,
  });

  final SystemVerification verification;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = verification;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          onTap: () => showCrmSheet<void>(
            context: context,
            builder: (_) => _VerificationActionsSheet(
              verification: v,
              canUpdate: canUpdate,
              canDelete: canDelete,
              onEdit: onEdit,
              onChanged: onChanged,
            ),
          ),
          title: Text(
            v.name,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (v.domainName != null) v.domainName!,
                    if (v.clientName != null) v.clientName!,
                    v.assignedUserName ?? 'Unassigned',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatusChip(v.isActive ? 'active' : 'inactive', dense: true),
                    const SizedBox(width: Spacing.sm),
                    _TodayStatusChip(verification: v),
                  ],
                ),
              ],
            ),
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Today's check at a glance: not yet checked, checked ok, or checked with
/// an issue — the same three colours [MyVerificationsScreen] reports with.
class _TodayStatusChip extends StatelessWidget {
  const _TodayStatusChip({required this.verification});

  final SystemVerification verification;

  @override
  Widget build(BuildContext context) {
    if (!verification.checkedToday) {
      return const StatusChip('pending', dense: true);
    }
    return StatusChip(
      verification.hasIssueToday ? 'overdue' : 'active',
      dense: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Row actions — view history, edit, delete
// ---------------------------------------------------------------------------

class _VerificationActionsSheet extends ConsumerStatefulWidget {
  const _VerificationActionsSheet({
    required this.verification,
    required this.canUpdate,
    required this.canDelete,
    required this.onEdit,
    required this.onChanged,
  });

  final SystemVerification verification;
  final bool canUpdate;
  final bool canDelete;

  /// Opens the edit sheet on the parent screen, so the same form serves both
  /// the masthead's add button and this row.
  final VoidCallback onEdit;

  /// Called once a delete succeeds, so the roster behind the sheet reloads.
  final VoidCallback onChanged;

  @override
  ConsumerState<_VerificationActionsSheet> createState() =>
      _VerificationActionsSheetState();
}

class _VerificationActionsSheetState
    extends ConsumerState<_VerificationActionsSheet> {
  bool _busy = false;

  SystemVerification get verification => widget.verification;

  Future<void> _history() => showCrmSheet<void>(
    context: context,
    builder: (_) => _VerificationHistorySheet(verification: verification),
  );

  Future<void> _delete() async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${verification.name}?'),
        content: const Text(
          'Every check-in report ever submitted for this system is deleted '
          'along with it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final message = await ref
          .read(staffSelfServiceProvider)
          .deleteSystemVerification(verification.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'System removed.')),
      );
      widget.onChanged();
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = verification;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: Spacing.md + sheetBottomInset(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SYSTEM VERIFICATION',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(v.name, style: Type.display(22, color: scheme.onSurface)),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      StatusChip(
                        v.isActive ? 'active' : 'inactive',
                        dense: true,
                      ),
                      const SizedBox(width: Spacing.sm),
                      _TodayStatusChip(verification: v),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (v.domainName != null)
                    CrmDetailRow('Domain', v.domainName!),
                  if (v.clientName != null)
                    CrmDetailRow('Client', v.clientName!),
                  CrmDetailRow('Assigned to', v.assignedUserName ?? 'Nobody'),
                  if (v.checkedToday)
                    CrmDetailRow(
                      'Today',
                      [
                        v.hasIssueToday ? 'Issue reported' : 'All good',
                        if (v.todaySubmittedAt != null)
                          'at ${Formatting.dateTime(v.todaySubmittedAt)}',
                        if (v.todayNotes != null) '— ${v.todayNotes}',
                      ].join(' '),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('View history'),
              subtitle: const Text('Every check-in ever submitted'),
              enabled: !_busy,
              onTap: _history,
            ),
            if (widget.canUpdate)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit system'),
                enabled: !_busy,
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onEdit();
                },
              ),
            if (widget.canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  'Delete system',
                  style: TextStyle(color: scheme.error),
                ),
                enabled: !_busy,
                onTap: _delete,
              ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History — GET /system-verifications/{id}/reports
// ---------------------------------------------------------------------------

class _VerificationHistorySheet extends ConsumerStatefulWidget {
  const _VerificationHistorySheet({required this.verification});

  final SystemVerification verification;

  @override
  ConsumerState<_VerificationHistorySheet> createState() =>
      _VerificationHistorySheetState();
}

class _VerificationHistorySheetState
    extends ConsumerState<_VerificationHistorySheet> {
  List<SystemVerificationReport>? _reports;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await ref
          .read(staffSelfServiceProvider)
          .verificationReports(widget.verification.id);
      if (mounted) setState(() => _reports = reports);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = screenHeight * 0.75 < 320 ? 320.0 : screenHeight * 0.75;
    final reports = _reports;

    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HISTORY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    widget.verification.name,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? StateMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load history',
                      message: _error!.message,
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  : (reports == null || reports.isEmpty)
                  ? const StateMessage(
                      icon: Icons.history_outlined,
                      title: 'No reports yet',
                      message: 'Check-ins submitted for this system appear here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                      ),
                      itemCount: reports.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: Spacing.md),
                      itemBuilder: (context, index) =>
                          _ReportTile(report: reports[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One past check-in: date, submitter, ok/issue and any notes.
class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final SystemVerificationReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final issue = report.status == 'issue';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(issue ? 'overdue' : 'active', dense: true),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Formatting.date(report.reportDate),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'by ${report.userName ?? 'Unknown'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (report.notes != null && report.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  report.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: issue ? scheme.error : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Register / edit — POST/PUT /system-verifications
// ---------------------------------------------------------------------------

class _SystemVerificationFormSheet extends ConsumerStatefulWidget {
  const _SystemVerificationFormSheet({this.verification});

  final SystemVerification? verification;

  @override
  ConsumerState<_SystemVerificationFormSheet> createState() =>
      _SystemVerificationFormSheetState();
}

class _SystemVerificationFormSheetState
    extends ConsumerState<_SystemVerificationFormSheet> {
  final _name = TextEditingController();
  final _domain = TextEditingController();

  String? _clientId;
  String? _clientName;
  String? _assignedUserId;
  String? _assignedUserName;
  bool _active = true;
  bool _submitting = false;
  String? _error;

  bool get _editing => widget.verification != null;

  @override
  void initState() {
    super.initState();
    final v = widget.verification;
    if (v == null) return;
    _name.text = v.name;
    _domain.text = v.domainName ?? '';
    _clientId = v.clientId;
    _clientName = v.clientName;
    _assignedUserId = v.assignedUserId;
    _assignedUserName = v.assignedUserName;
    _active = v.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked == null) return;
    setState(() {
      _clientId = picked.id;
      _clientName = picked.name;
    });
  }

  Future<void> _pickAssignee() async {
    final picked = await StaffUserPickerSheet.show(context);
    if (picked == null) return;
    setState(() {
      _assignedUserId = picked.id;
      _assignedUserName = picked.name;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the system a name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final domain = _domain.text.trim();
    try {
      final service = ref.read(staffSelfServiceProvider);
      if (_editing) {
        await service.updateSystemVerification(
          widget.verification!.id,
          name: name,
          domainName: domain.isEmpty ? null : domain,
          clientId: _clientId,
          assignedUserId: _assignedUserId,
          isActive: _active,
        );
      } else {
        await service.createSystemVerification(
          name: name,
          domainName: domain.isEmpty ? null : domain,
          clientId: _clientId,
          assignedUserId: _assignedUserId,
          isActive: _active,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editing ? 'System updated.' : 'System registered.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('name') ?? e.errorFor('domain_name') ?? e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: 'System verifications',
      title: _editing ? 'Edit system' : 'Register a system',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Accounts subsystem',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Domain (optional)',
          child: TextField(
            controller: _domain,
            enabled: !_submitting,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'e.g. moinfotech.co.tz',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Client (optional)',
          value: _clientName ?? 'Not linked to a client',
          placeholder: _clientName == null,
          icon: Icons.person_outline,
          onTap: _submitting ? null : _pickClient,
        ),
        if (_clientId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _clientId = null;
                      _clientName = null;
                    }),
              child: const Text('Unlink client'),
            ),
          ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Assigned staff (optional)',
          value: _assignedUserName ?? 'Nobody assigned',
          placeholder: _assignedUserName == null,
          icon: Icons.person_search_outlined,
          onTap: _submitting ? null : _pickAssignee,
        ),
        if (_assignedUserId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _assignedUserId = null;
                      _assignedUserName = null;
                    }),
              child: const Text('Unassign'),
            ),
          ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Staff must report on this daily'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : (_editing ? 'Save changes' : 'Register system'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

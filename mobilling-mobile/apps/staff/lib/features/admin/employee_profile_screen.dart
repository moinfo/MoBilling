import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        showCrmSheet;
import '../hr/hr_providers.dart' show hrServiceProvider;
import 'admin_providers.dart';

/// One staff member's HR record — `EmployeeProfileController::show`/`update`.
///
/// Reached by tapping "HR profile" on a [TeamScreen] row. Separate from that
/// row's "Edit details" action, which edits the sign-in account
/// (`UserController::update`: name/email/role) rather than this HR data.
class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(employeeProfileProvider(userId));
    final canUpdate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(AdminPermissions.employeesUpdate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(eyebrow: 'Team', title: userName),
      body: CrmAsyncView(
        value: pageAsync,
        errorTitle: 'Could not load HR profile',
        onRetry: () => ref.invalidate(employeeProfileProvider(userId)),
        builder: (page) =>
            _ProfileBody(userId: userId, page: page, canUpdate: canUpdate),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.userId,
    required this.page,
    required this.canUpdate,
  });

  final String userId;
  final EmployeeProfilePage page;
  final bool canUpdate;

  Future<void> _openEditForm(BuildContext context, WidgetRef ref) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) =>
          _EmployeeProfileFormSheet(userId: userId, profile: page.profile),
    );
    if (saved == true) ref.invalidate(employeeProfileProvider(userId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = page.user;
    final profile = page.profile;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.xl,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.xs),
                if (user.email != null)
                  Text(
                    user.email!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: [
                    if (user.roleLabel != null)
                      Chip(
                        label: Text(user.roleLabel!),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (profile?.department != null)
                      Chip(
                        label: Text(profile!.department!),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                if (user.supervisorName != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Reports to ${user.supervisorName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        SectionHeader(
          'Employee details',
          trailing: !canUpdate
              ? null
              : TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(profile == null ? 'Add details' : 'Edit'),
                  onPressed: () => _openEditForm(context, ref),
                ),
        ),
        const SizedBox(height: Spacing.sm),
        if (profile == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                canUpdate
                    ? 'No HR details on file yet. Tap "Add details" to add them.'
                    : 'No HR details on file yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrmDetailRow(
                    'Employee number',
                    profile.employeeNumber ?? '—',
                  ),
                  CrmDetailRow(
                    'Hire date',
                    profile.hireDate == null
                        ? '—'
                        : Formatting.date(profile.hireDate),
                  ),
                  CrmDetailRow('Department', profile.department ?? '—'),
                  CrmDetailRow('Position', profile.position ?? '—'),
                  CrmDetailRow(
                    'Employment type',
                    EmploymentTypes.label(profile.employmentType),
                  ),
                  CrmDetailRow('National ID', profile.nationalId ?? '—'),
                  CrmDetailRow('NSSF number', profile.nssfNumber ?? '—'),
                  CrmDetailRow('TIN number', profile.tinNumber ?? '—'),
                  CrmDetailRow('Next of kin', profile.nextOfKinName ?? '—'),
                  CrmDetailRow(
                    'Next of kin phone',
                    profile.nextOfKinPhone ?? '—',
                  ),
                  CrmDetailRow(
                    'Bank',
                    [profile.bankName, profile.bankAccountNumber]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' — ')
                        .ifEmpty('—'),
                  ),
                  CrmDetailRow(
                    'Mobile money',
                    [profile.mobileMoneyProvider, profile.mobileMoneyNumber]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' — ')
                        .ifEmpty('—'),
                  ),
                  if (profile.notes != null && profile.notes!.isNotEmpty)
                    CrmDetailRow('Notes', profile.notes!),
                  if (!profile.subjectToPaye) ...[
                    const SizedBox(height: Spacing.sm),
                    Row(
                      children: [
                        Text(
                          'Exempt from: ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Chip(
                          label: const Text('PAYE'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Leave history'),
        const SizedBox(height: Spacing.sm),
        _LeaveHistory(userId: userId),
      ],
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// A small read-only slice of the leave list, scoped to one user — the same
/// data `UserProfile.tsx` shows in its "Leave History" table.
class _LeaveHistory extends ConsumerWidget {
  const _LeaveHistory({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final requestsAsync = ref.watch(_employeeLeaveHistoryProvider(userId));

    return requestsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        error is ApiException ? error.message : 'Could not load leave history.',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
      ),
      data: (requests) => requests.isEmpty
          ? Text(
              'No leave requests.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : CrmCardList(
              children: [
                for (final r in requests)
                  ListTile(
                    title: Text(r.typeName, style: theme.textTheme.titleSmall),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${Formatting.date(r.startDate)} – '
                        '${Formatting.date(r.endDate)} · '
                        '${Formatting.integer(r.days)} '
                        'day${r.days == 1 ? '' : 's'}',
                        style: Type.mono(11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    trailing: StatusChip(r.status, dense: true),
                  ),
              ],
            ),
    );
  }
}

/// Declared here, not in `hr_providers.dart`, because nothing outside this
/// screen filters the leave list by an arbitrary user id.
final AutoDisposeFutureProviderFamily<List<LeaveRequest>, String>
_employeeLeaveHistoryProvider = FutureProvider.autoDispose
    .family<List<LeaveRequest>, String>(
      (ref, userId) =>
          ref.watch(hrServiceProvider).leaveRequests(userId: userId),
    );

/// Add or edit one HR profile. Every field is optional — unlike the sign-in
/// account form, a partial save is fine (`EmployeeProfileController::update`
/// validates each field independently, not the record as a whole).
class _EmployeeProfileFormSheet extends ConsumerStatefulWidget {
  const _EmployeeProfileFormSheet({
    required this.userId,
    required this.profile,
  });

  final String userId;
  final EmployeeProfile? profile;

  @override
  ConsumerState<_EmployeeProfileFormSheet> createState() =>
      _EmployeeProfileFormSheetState();
}

class _EmployeeProfileFormSheetState
    extends ConsumerState<_EmployeeProfileFormSheet> {
  late final _employeeNumber = TextEditingController(
    text: widget.profile?.employeeNumber ?? '',
  );
  late final _department = TextEditingController(
    text: widget.profile?.department ?? '',
  );
  late final _position = TextEditingController(
    text: widget.profile?.position ?? '',
  );
  late final _nationalId = TextEditingController(
    text: widget.profile?.nationalId ?? '',
  );
  late final _nssfNumber = TextEditingController(
    text: widget.profile?.nssfNumber ?? '',
  );
  late final _tinNumber = TextEditingController(
    text: widget.profile?.tinNumber ?? '',
  );
  late final _nextOfKinName = TextEditingController(
    text: widget.profile?.nextOfKinName ?? '',
  );
  late final _nextOfKinPhone = TextEditingController(
    text: widget.profile?.nextOfKinPhone ?? '',
  );
  late final _bankName = TextEditingController(
    text: widget.profile?.bankName ?? '',
  );
  late final _bankBranch = TextEditingController(
    text: widget.profile?.bankBranch ?? '',
  );
  late final _bankAccountName = TextEditingController(
    text: widget.profile?.bankAccountName ?? '',
  );
  late final _bankAccountNumber = TextEditingController(
    text: widget.profile?.bankAccountNumber ?? '',
  );
  late final _mobileMoneyProvider = TextEditingController(
    text: widget.profile?.mobileMoneyProvider ?? '',
  );
  late final _mobileMoneyNumber = TextEditingController(
    text: widget.profile?.mobileMoneyNumber ?? '',
  );
  late final _notes = TextEditingController(text: widget.profile?.notes ?? '');

  DateTime? _hireDate;
  String? _employmentType;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hireDate = widget.profile?.hireDate;
    _employmentType = widget.profile?.employmentType;
  }

  @override
  void dispose() {
    _employeeNumber.dispose();
    _department.dispose();
    _position.dispose();
    _nationalId.dispose();
    _nssfNumber.dispose();
    _tinNumber.dispose();
    _nextOfKinName.dispose();
    _nextOfKinPhone.dispose();
    _bankName.dispose();
    _bankBranch.dispose();
    _bankAccountName.dispose();
    _bankAccountNumber.dispose();
    _mobileMoneyProvider.dispose();
    _mobileMoneyNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _hireDate = picked);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminServiceProvider)
          .updateEmployeeProfile(
            widget.userId,
            employeeNumber: _employeeNumber.text.trim(),
            hireDate: _hireDate,
            department: _department.text.trim(),
            position: _position.text.trim(),
            employmentType: _employmentType,
            nationalId: _nationalId.text.trim(),
            nssfNumber: _nssfNumber.text.trim(),
            tinNumber: _tinNumber.text.trim(),
            nextOfKinName: _nextOfKinName.text.trim(),
            nextOfKinPhone: _nextOfKinPhone.text.trim(),
            bankName: _bankName.text.trim(),
            bankBranch: _bankBranch.text.trim(),
            bankAccountName: _bankAccountName.text.trim(),
            bankAccountNumber: _bankAccountNumber.text.trim(),
            mobileMoneyProvider: _mobileMoneyProvider.text.trim(),
            mobileMoneyNumber: _mobileMoneyNumber.text.trim(),
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Team',
    title: 'Employee details',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Employee number',
        child: TextField(controller: _employeeNumber),
      ),
      const SizedBox(height: Spacing.md),
      CrmPickerField(
        label: 'Hire date',
        value: _hireDate == null ? 'Not set' : Formatting.date(_hireDate),
        placeholder: _hireDate == null,
        onTap: _busy ? null : _pickHireDate,
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Department',
        child: TextField(controller: _department),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Position',
        child: TextField(controller: _position),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Employment type',
        child: DropdownButtonFormField<String>(
          initialValue: _employmentType,
          isExpanded: true,
          hint: const Text('Choose one'),
          items: [
            for (final (value, label) in EmploymentTypes.values)
              DropdownMenuItem(value: value, child: Text(label)),
          ],
          onChanged: _busy ? null : (v) => setState(() => _employmentType = v),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'National ID',
        child: TextField(controller: _nationalId),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'NSSF number',
        child: TextField(controller: _nssfNumber),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'TIN number',
        child: TextField(controller: _tinNumber),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Next of kin name',
        child: TextField(controller: _nextOfKinName),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Next of kin phone',
        child: TextField(
          controller: _nextOfKinPhone,
          keyboardType: TextInputType.phone,
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Bank name',
        child: TextField(controller: _bankName),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Bank branch',
        child: TextField(controller: _bankBranch),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Bank account name',
        child: TextField(controller: _bankAccountName),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Bank account number',
        child: TextField(controller: _bankAccountNumber),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Mobile money provider',
        child: TextField(controller: _mobileMoneyProvider),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Mobile money number',
        child: TextField(
          controller: _mobileMoneyNumber,
          keyboardType: TextInputType.phone,
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Notes',
        child: TextField(controller: _notes, maxLines: 3),
      ),
      const SizedBox(height: Spacing.sm),
      Text(
        'PAYE and other statutory exemptions are managed under '
        'Payroll > Settings > Statutory Rates > Assign.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: 'Save',
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}

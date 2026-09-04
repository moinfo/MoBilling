import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmField,
        CrmStatusLine,
        CrmSheet,
        showCrmSheet;
import 'hr_providers.dart';

/// The payroll catalogs: allowances, deductions and statutory rates.
///
/// The three share one shape — a name, a rate or amount, active/inactive —
/// and one interaction: tap an entry to see who it applies to. Create, edit
/// and delete live behind the edit icon so the tap on the row itself always
/// means the same thing everywhere in this file.

// ---------------------------------------------------------------------------
// Allowances & deductions (identical shape, so one tab serves both)
// ---------------------------------------------------------------------------

enum PayComponentKind { allowance, deduction }

class PayComponentCatalogTab extends ConsumerWidget {
  const PayComponentCatalogTab({
    super.key,
    required this.kind,
    required this.canManage,
  });

  final PayComponentKind kind;
  final bool canManage;

  String get _noun =>
      kind == PayComponentKind.allowance ? 'allowance' : 'deduction';

  AutoDisposeFutureProvider<List<PayComponent>> get _provider =>
      kind == PayComponentKind.allowance
      ? allowancesProvider
      : deductionsProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _provider;
    final list = ref.watch(provider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: list,
      errorTitle: 'Could not load ${_noun}s',
      onRetry: () => ref.invalidate(provider),
      builder: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (canManage) ...[
              PrimaryButton(
                icon: Icons.add,
                label: 'Add $_noun',
                onPressed: () => _edit(context, ref, null),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (items.isEmpty)
              SizedBox(
                height: 280,
                child: StateMessage(
                  icon: Icons.tune_outlined,
                  title: 'No ${_noun}s yet',
                  message: canManage
                      ? 'Add one, then assign it to the employees it '
                            'applies to.'
                      : 'None have been set up yet.',
                ),
              )
            else
              Reveal(
                child: CrmCardList(
                  children: [
                    for (final item in items)
                      ListTile(
                        title: Text(
                          item.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmStatusLine(
                            status: item.isActive ? 'active' : 'inactive',
                            meta: item.isPercent
                                ? '${Formatting.amount(item.defaultAmount)}% of basic'
                                : Formatting.currency(item.defaultAmount),
                          ),
                        ),
                        trailing: canManage
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _edit(context, ref, item),
                              )
                            : Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.outline,
                              ),
                        onTap: () => _assign(context, ref, item),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PayComponent? existing,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => PayComponentEditSheet(kind: kind, existing: existing),
    );
    if (saved ?? false) ref.invalidate(_provider);
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    PayComponent item,
  ) {
    final service = ref.read(hrServiceProvider);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => PayrollAssignSheet(
        eyebrow: kind == PayComponentKind.allowance
            ? 'Allowance'
            : 'Deduction',
        title: item.name,
        readOnly: !canManage,
        field: PayrollAssignField.amount,
        fieldLabel: item.isPercent ? '% override' : 'Amount override',
        fetch: () => kind == PayComponentKind.allowance
            ? service.allowanceSubscriptions(item.id)
            : service.deductionSubscriptions(item.id),
        onSave: ({required userId, required isActive, String? fieldText}) {
          final override = (fieldText == null || fieldText.isEmpty)
              ? null
              : double.tryParse(fieldText.replaceAll(',', ''));
          return kind == PayComponentKind.allowance
              ? service.setAllowanceSubscription(
                  item.id,
                  userId: userId,
                  isActive: isActive,
                  amountOverride: override,
                )
              : service.setDeductionSubscription(
                  item.id,
                  userId: userId,
                  isActive: isActive,
                  amountOverride: override,
                );
        },
      ),
    );
  }
}

class PayComponentEditSheet extends ConsumerStatefulWidget {
  const PayComponentEditSheet({super.key, required this.kind, this.existing});

  final PayComponentKind kind;
  final PayComponent? existing;

  @override
  ConsumerState<PayComponentEditSheet> createState() =>
      _PayComponentEditSheetState();
}

class _PayComponentEditSheetState
    extends ConsumerState<PayComponentEditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : Formatting.amount(widget.existing!.defaultAmount),
  );
  late String _calcType = widget.existing?.calculationType ?? 'fixed';
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;
  bool get _isPercent => _calcType == 'percent_of_basic';
  String get _noun =>
      widget.kind == PayComponentKind.allowance ? 'allowance' : 'deduction';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (name.isEmpty || amount == null || amount < 0) {
      setState(() => _error = 'Enter a name and a default amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = ref.read(hrServiceProvider);
    try {
      if (widget.kind == PayComponentKind.allowance) {
        if (_editing) {
          await service.updateAllowance(
            widget.existing!.id,
            name: name,
            calculationType: _calcType,
            defaultAmount: amount,
            isActive: _active,
          );
        } else {
          await service.createAllowance(
            name: name,
            calculationType: _calcType,
            defaultAmount: amount,
          );
        }
      } else {
        if (_editing) {
          await service.updateDeduction(
            widget.existing!.id,
            name: name,
            calculationType: _calcType,
            defaultAmount: amount,
            isActive: _active,
          );
        } else {
          await service.createDeduction(
            name: name,
            calculationType: _calcType,
            defaultAmount: amount,
          );
        }
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
        title: Text('Delete this $_noun?'),
        content: Text(
          'Employees currently assigned "${widget.existing!.name}" lose it '
          'from their next payslip.',
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
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _saving = true);
    try {
      if (widget.kind == PayComponentKind.allowance) {
        await ref.read(hrServiceProvider).deleteAllowance(widget.existing!.id);
      } else {
        await ref.read(hrServiceProvider).deleteDeduction(widget.existing!.id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: widget.kind == PayComponentKind.allowance
          ? 'Allowance'
          : 'Deduction',
      title: _editing ? 'Edit $_noun' : 'New $_noun',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Housing allowance',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Calculation',
          child: DropdownButtonFormField<String>(
            initialValue: _calcType,
            items: const [
              DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
              DropdownMenuItem(
                value: 'percent_of_basic',
                child: Text('% of basic salary'),
              ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _calcType = v ?? 'fixed'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: _isPercent ? 'Default amount (% of basic)' : 'Default amount',
          child: TextField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: _isPercent ? null : '${Formatting.tenantCurrency} ',
              suffixText: _isPercent ? '%' : null,
            ),
          ),
        ),
        if (_editing) ...[
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(
              'Inactive ${_noun}s are not applied to new payslips',
            ),
            value: _active,
            onChanged: _saving ? null : (v) => setState(() => _active = v),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _saving
              ? 'Saving…'
              : _editing
              ? 'Save changes'
              : 'Create $_noun',
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (_editing) ...[
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text(
              'Delete $_noun',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Statutory rates
// ---------------------------------------------------------------------------

class StatutoryRateCatalogTab extends ConsumerWidget {
  const StatutoryRateCatalogTab({super.key, required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(statutoryRatesProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: list,
      errorTitle: 'Could not load statutory rates',
      onRetry: () => ref.invalidate(statutoryRatesProvider),
      builder: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(statutoryRatesProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (canManage) ...[
              PrimaryButton(
                icon: Icons.add,
                label: 'Add statutory rate',
                onPressed: () => _edit(context, ref, null),
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (items.isEmpty)
              SizedBox(
                height: 280,
                child: StateMessage(
                  icon: Icons.account_balance_outlined,
                  title: 'No statutory rates yet',
                  message: canManage
                      ? 'Add one, then assign it to the employees it '
                            'applies to.'
                      : 'None have been set up yet.',
                ),
              )
            else
              Reveal(
                child: CrmCardList(
                  children: [
                    for (final item in items)
                      ListTile(
                        title: Text(
                          item.name,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmStatusLine(
                            status: item.isActive ? 'active' : 'inactive',
                            meta:
                                'Employee ${Formatting.amount(item.employeePercent)}% · '
                                'Employer ${Formatting.amount(item.employerPercent)}%',
                          ),
                        ),
                        trailing: canManage
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _edit(context, ref, item),
                              )
                            : Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.outline,
                              ),
                        onTap: () => _assign(context, ref, item),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    StatutoryRate? existing,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => StatutoryRateEditSheet(existing: existing),
    );
    if (saved ?? false) ref.invalidate(statutoryRatesProvider);
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, StatutoryRate item) {
    final service = ref.read(hrServiceProvider);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => PayrollAssignSheet(
        eyebrow: 'Statutory rate',
        title: item.name,
        readOnly: !canManage,
        field: PayrollAssignField.reference,
        fieldLabel: 'Reference no.',
        fetch: () => service.statutoryRateSubscriptions(item.id),
        onSave: ({required userId, required isActive, String? fieldText}) =>
            service.setStatutoryRateSubscription(
              item.id,
              userId: userId,
              isActive: isActive,
              referenceNumber: fieldText,
            ),
      ),
    );
  }
}

class StatutoryRateEditSheet extends ConsumerStatefulWidget {
  const StatutoryRateEditSheet({super.key, this.existing});

  final StatutoryRate? existing;

  @override
  ConsumerState<StatutoryRateEditSheet> createState() =>
      _StatutoryRateEditSheetState();
}

class _StatutoryRateEditSheetState
    extends ConsumerState<StatutoryRateEditSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _employeePercent = TextEditingController(
    text: widget.existing == null
        ? ''
        : Formatting.amount(widget.existing!.employeePercent),
  );
  late final _employerPercent = TextEditingController(
    text: widget.existing == null
        ? ''
        : Formatting.amount(widget.existing!.employerPercent),
  );
  late bool _reducesTaxable = widget.existing?.reducesTaxableIncome ?? false;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _employeePercent.dispose();
    _employerPercent.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final employee = double.tryParse(
      _employeePercent.text.replaceAll(',', '').trim(),
    );
    final employer = double.tryParse(
      _employerPercent.text.replaceAll(',', '').trim(),
    );
    if (name.isEmpty ||
        employee == null ||
        employee < 0 ||
        employer == null ||
        employer < 0) {
      setState(() => _error = 'Enter a name and both percentages.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = ref.read(hrServiceProvider);
    try {
      if (_editing) {
        await service.updateStatutoryRate(
          widget.existing!.id,
          name: name,
          employeePercent: employee,
          employerPercent: employer,
          reducesTaxableIncome: _reducesTaxable,
          isActive: _active,
        );
      } else {
        await service.createStatutoryRate(
          name: name,
          employeePercent: employee,
          employerPercent: employer,
          reducesTaxableIncome: _reducesTaxable,
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
        title: const Text('Delete this statutory rate?'),
        content: Text(
          'Employees currently assigned "${widget.existing!.name}" lose it '
          'from their next payslip.',
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
    if (!(confirmed ?? false) || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(hrServiceProvider).deleteStatutoryRate(widget.existing!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CrmSheet(
      eyebrow: 'Statutory rate',
      title: _editing ? 'Edit statutory rate' : 'New statutory rate',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. NSSF'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: CrmField(
                label: 'Employee %',
                child: TextField(
                  controller: _employeePercent,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    suffixText: '%',
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: CrmField(
                label: 'Employer %',
                child: TextField(
                  controller: _employerPercent,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    suffixText: '%',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reduces taxable income'),
          subtitle: const Text('Deducted before PAYE, like NSSF'),
          value: _reducesTaxable,
          onChanged: _saving
              ? null
              : (v) => setState(() => _reducesTaxable = v),
        ),
        if (_editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _active,
            onChanged: _saving ? null : (v) => setState(() => _active = v),
          ),
        const SizedBox(height: Spacing.md),
        PrimaryButton(
          label: _saving
              ? 'Saving…'
              : _editing
              ? 'Save changes'
              : 'Create rate',
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (_editing) ...[
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text(
              'Delete statutory rate',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The shared "assign to employees" sheet
// ---------------------------------------------------------------------------

/// What, if anything, each employee row edits besides the on/off toggle.
enum PayrollAssignField { none, amount, reference }

/// Every active employee, each with a toggle for one payroll catalog entry
/// (an allowance, a deduction, a statutory rate) or one blanket exemption —
/// and, where the caller asks for it, an inline field for a per-employee
/// amount override or a statutory reference number.
///
/// Saves one row at a time, on toggle or on leaving the field: there is no
/// bulk-save button, so leaving the sheet never discards anything.
class PayrollAssignSheet extends StatefulWidget {
  const PayrollAssignSheet({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.fetch,
    required this.onSave,
    this.field = PayrollAssignField.none,
    this.fieldLabel,
    this.readOnly = false,
  });

  final String eyebrow;
  final String title;
  final Future<SubscriptionsPage> Function() fetch;

  /// [fieldText] is the row's current field value (trimmed), or null when
  /// [field] is [PayrollAssignField.none].
  final Future<void> Function({
    required String userId,
    required bool isActive,
    String? fieldText,
  })
  onSave;
  final PayrollAssignField field;
  final String? fieldLabel;

  /// The signed-in user can see this but not change it (`payroll.view` only).
  final bool readOnly;

  @override
  State<PayrollAssignSheet> createState() => _PayrollAssignSheetState();
}

class _PayrollAssignSheetState extends State<PayrollAssignSheet> {
  late Future<SubscriptionsPage> _future = widget.fetch();
  final Map<String, bool> _active = {};
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _saving = {};
  String? _error;
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(SubscriptionsPage page) {
    if (_seeded) return;
    _seeded = true;
    for (final user in page.users) {
      final sub = page.subscriptions[user.id];
      _active[user.id] = sub?.isActive ?? false;
      final text = switch (widget.field) {
        PayrollAssignField.amount => sub?.amountOverride == null
            ? ''
            : Formatting.amount(sub!.amountOverride),
        PayrollAssignField.reference => sub?.referenceNumber ?? '',
        PayrollAssignField.none => '',
      };
      _controllers[user.id] = TextEditingController(text: text);
    }
  }

  Future<void> _save(String userId) async {
    if (widget.readOnly) return;
    setState(() => _saving.add(userId));
    try {
      await widget.onSave(
        userId: userId,
        isActive: _active[userId] ?? false,
        fieldText: widget.field == PayrollAssignField.none
            ? null
            : _controllers[userId]!.text.trim(),
      );
      if (mounted) setState(() => _error = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<SubscriptionsPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final e = snapshot.error;
            return Center(
              child: StateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load employees',
                message: e is ApiException ? e.message : null,
                actionLabel: 'Retry',
                onAction: () => setState(() => _future = widget.fetch()),
              ),
            );
          }
          final page = snapshot.data!;
          _seed(page);

          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            children: [
              Text(
                widget.eyebrow.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                widget.title,
                style: Type.display(22, color: scheme.onSurface),
              ),
              const SizedBox(height: Spacing.md),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: Spacing.md),
              ],
              if (page.users.isEmpty)
                const Card(
                  child: StateMessage(
                    icon: Icons.people_outline,
                    title: 'No active employees',
                    message: 'Assignments appear here once staff are added.',
                  ),
                )
              else
                CrmCardList(
                  children: [
                    for (final user in page.users)
                      _AssignRow(
                        name: user.name,
                        active: _active[user.id] ?? false,
                        controller: widget.field == PayrollAssignField.none
                            ? null
                            : _controllers[user.id],
                        fieldLabel: widget.fieldLabel,
                        keyboardType: widget.field == PayrollAssignField.amount
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        saving: _saving.contains(user.id),
                        readOnly: widget.readOnly,
                        onToggle: (v) {
                          setState(() => _active[user.id] = v);
                          _save(user.id);
                        },
                        onFieldDone: () => _save(user.id),
                      ),
                  ],
                ),
              const SizedBox(height: Spacing.xl),
            ],
          );
        },
      ),
    );
  }
}

/// One employee row inside a [PayrollAssignSheet]: the name, an optional
/// inline field, and the toggle — or a small spinner while that row's save
/// is in flight.
class _AssignRow extends StatelessWidget {
  const _AssignRow({
    required this.name,
    required this.active,
    required this.controller,
    required this.fieldLabel,
    required this.keyboardType,
    required this.saving,
    required this.readOnly,
    required this.onToggle,
    required this.onFieldDone,
  });

  final String name;
  final bool active;
  final TextEditingController? controller;
  final String? fieldLabel;
  final TextInputType keyboardType;
  final bool saving;
  final bool readOnly;
  final ValueChanged<bool> onToggle;
  final VoidCallback onFieldDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (controller != null) ...[
            SizedBox(
              width: 108,
              child: TextField(
                controller: controller,
                enabled: !saving && !readOnly,
                readOnly: readOnly,
                keyboardType: keyboardType,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: fieldLabel,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.sm,
                  ),
                ),
                onSubmitted: (_) => onFieldDone(),
                onTapOutside: (_) => onFieldDone(),
              ),
            ),
            const SizedBox(width: Spacing.sm),
          ],
          saving
              ? const SizedBox(
                  width: 40,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Switch(value: active, onChanged: readOnly ? null : onToggle),
        ],
      ),
    );
  }
}
